# For identifying comparison expressions
const COMPARISON_PREC = Base.operator_precedence(:(==)) 

# List of functions that can be displayed nicely
const DISPLAYABLE_FUNCS = Set([
    :isequal,
    :isapprox,
    :occursin,
    :startswith,
    :endswith,
    :isempty,
    :contains, 
    :ismissing, 
    :isnan, 
    :isinf, 
    :iseven, 
    :isodd, 
    :isreal,
    :isa
])

# Lists of operators to treat specially
const OPS_LOGICAL = (:.&&, :.||) # TODO(tpapalex) add XOR (.⊻)
const OPS_APPROX = (:.≈, :.≉)  

_is_vecop = x::Symbol -> first(string(x)) == '.'
_is_splat = x -> isa(x, Expr) && x.head === :...

#################### Expression Parsing ###################

function add_keywords!(ex, kws...)
    if length(kws) == 0
        return ex
    end

    orig_ex = ex

    # Recursively dive through negations.
    while isa(ex, Expr) && 
        ex.head === :call && 
        (ex.args[1] === :.! || ex.args[1] === :!) && 
        length(ex.args) == 2

        ex = ex.args[2]
    end

    # Not valid to add keywords, unless it's a call or .
    if !(isa(ex, Expr) && (ex.head === :. || ex.head === :call))
        error("invalid test macro call: @test_all $ex does not accept keyword arguments")
    end

    # Push keywords to the end of arguments
    ex_args = ex.head === :call ? ex.args : ex.args[2].args

    for kw in kws
        if isa(kw, Expr) && kw.head === :(=)
            kw.head = :kw
            push!(ex_args, kw)
        else
            error("invalid test macro call: $kw is not a valid keyword argument")
        end
    end

    return orig_ex
end

# Internal function that performs some pre-processing on a single expression. This is called
# first in any `process_...` call to make pretty arguments.
#   2) Changes :calls with binary comparison operator and no args as :comparison 
#   3) Changes <:, >: expressions with no args to :comparison
function preprocess(ex)

    # Normalize :call with comparison-precedence operator to :comparison. Do not do 
    # if arguments are splats, or if there are extra keywords.
    if isa(ex, Expr) && 
        ex.head === :call &&   
        Base.operator_precedence(ex.args[1]) == COMPARISON_PREC &&
        _is_vecop(ex.args[1]) && 
        length(ex.args) == 3 && # Excludes cases where kws were added
        !any(a -> isa(a, Expr) && a.head ∈ (:kw, :parameters, :...), ex.args)

        return Expr(:comparison, ex.args[2], ex.args[1], ex.args[3])


    # Mark vectorized .<: and .>: as :comparison expressions
    elseif isa(ex, Expr) && 
        ex.head === :call && 
        (ex.args[1] === :.<: || ex.args[1] === :.>:) && 
        length(ex.args) == 3 && # Exclude cases where kws were added
        !_is_splat(ex.args[2]) && 
        !_is_splat(ex.args[3]) 

        return Expr(:comparison, ex.args[2], ex.args[1], ex.args[3])  
    
    # Consolidate parameters arguments into keywords for :call or :.
    elseif is_argsapprox(ex) || is_displaycall(ex)

        if ex.head === :call 
            par_ex = ex.args[2]
            if isa(par_ex, Expr) && par_ex.head === :parameters
                for a in par_ex.args
                    if isa(a, Expr) && a.head === :kw
                        push!(ex.args, a)
                    end
                end
                ex = Expr(:call, ex.args[1], ex.args[3:end]...)
            end
        elseif ex.head === :.
            par_ex = ex.args[2].args[1]
            if isa(par_ex, Expr) && par_ex.head === :parameters
                for a in par_ex.args
                    if isa(a, Expr) && a.head === :kw
                        push!(ex.args[2].args, a)
                    end
                end
                ex.args[2].args = ex.args[2].args[2:end]
            end
        end

    end 

    return ex
end

# NOT expressions, e.g. !a
function is_negation(ex) 
    return isa(ex, Expr) && 
        ex.head === :call && 
        ex.args[1] === :.! && 
        length(ex.args) == 2
end

# AND or OR expressions Logical expressions, e.g, a && b, a || c
function is_logical(ex)
    return isa(ex, Expr) && 
        ex.head ∈ OPS_LOGICAL && 
        length(ex.args) == 2
end

# Most comparison expressions, e.g. a == b, a <= b <= c, a ≈ B. Note that :call
# expressions with comparison ops are chanegd to :comparison in preprocess()
function is_comparison(ex)
    if isa(ex, Expr) && ex.head === :comparison
        # Check that all ops are vectorized
        for i in 2:2:length(ex.args)
            if !_is_vecop(ex.args[i])
                return false
            end
        end
        # And that non of the arguments are splats
        for i in 1:2:length(ex.args)
            if _is_splat(ex.args[i])
                return false
            end
        end
        return true
    else
        return false
    end
end

# Special case for nicer formatting of ≈/≉ with keyword arguments (atol or rtol)
function is_argsapprox(ex)
    if isa(ex, Expr) && 
        ex.head === :call && 
        ex.args[1] ∈ OPS_APPROX

        # Must have exactly two positional arguments
        is_not_positional = a -> isa(a, Expr) && a.head ∈ (:kw, :parameters, :...)
        n_args = length(ex.args) - sum(is_not_positional, ex.args; init=0)
        if n_args != 3 
            return false
        end

        return true
    else
        return false
    end
end

# Displayable functions, e.g. isnan(x), isapprox(x, y), etc. as well as comparison
# operators with printable arguments
function is_displaycall(ex)
    if isa(ex, Expr) && 
        ex.head === :. && 
        ex.args[1] ∈ DISPLAYABLE_FUNCS

        # Extract arguments
        args = ex.args[2].args

        # Check at least one positional argument
        is_not_positional = a -> isa(a, Expr) && a.head ∈ (:kw, :parameters, :...)
        n_args = length(args) - sum(is_not_positional, args; init=0)
        if n_args == 0
            return false
        end

        # Check that parameters are all keywords
        par_ex = args[1]
        if isa(par_ex, Expr) && par_ex.head === :parameters
            for a in par_ex.args
                # If non-kw parameter, then do not support display
                if !(isa(a, Expr) && a.head === :kw)
                    return false
                end
            end
        end

        # Check that positional arguments are not splats
        for a in args
            isa(a, Expr) && a.head ∈ (:kw, :parameters) && continue
            # If splatted argument, then do not support display
            if _is_splat(a)
                return false
            end
        end

        return true
    else
        return false
    end
end

# Convenience function, returns true if the expression doesn't fall in the other categories
function is_fallback(ex)
    ex = preprocess(ex)
    is_negation(ex) && return false
    is_logical(ex) && return false
    is_comparison(ex) && return false
    is_argsapprox(ex) && return false
    is_displaycall(ex) && return false
    return true
end

# Anonymous function that can be displayed
function is_mappable(ex)
    return isa(ex, Expr) && 
        ex.head === :->
end

#################### Escaped args updaters ###################
function string_unvec(x::Symbol) 
    sx = string(x)
    return sx[1] == '.' ? sx[2:end] : sx 
end

"""
    update_escaped!(args, ex; isoutmost=false)

Rescursively populates `args` with escaped sub-expressions in `ex`, and replaces them 
with ARG[i].

# Arguments
- 'args::Vector{Expr}`: Vector where escaped sub-expressions will be pushed.
- 'ex::Expr`: The source expression. Caution: will be modified in place.
  
# Keyword Arguments
- 'isoutmost::Bool=false`: Whether the expression is the outmost expression, to know
  whether stringifying should wrap in parentheses.

# Returns Tuple{Expr,String,String,String}:
- modified `ex` with sub-expressions replaced by the corresponding ARG[i]
- stringified version of the original `ex`.
- the `FormatExpr` for pretty-printing an unvectorized version of `ex`
- the `FormatExpr` for pretty-printing the keyword arguments of `ex` (only for 
  displayable :call and :. expressions)
"""
function update_escaped!(args, ex; isoutmost=false)
    # Pre-process the expression first, to normalize comparisons, fix keywords etc.
    ex = preprocess(ex)
    if is_negation(ex)
        return update_escaped_negation!(args, ex; isoutmost=isoutmost)
    elseif is_logical(ex)
        return update_escaped_logical!(args, ex; isoutmost=isoutmost)
    elseif is_comparison(ex)
        return update_escaped_comparison!(args, ex; isoutmost=isoutmost)
    elseif is_argsapprox(ex)
        return update_escaped_argsapprox!(args, ex; isoutmost=isoutmost)
    elseif is_displaycall(ex)
        return update_escaped_displaycall!(args, ex; isoutmost=isoutmost)
    else # is_fallback(ex)
        return update_escaped_fallback!(args, ex; isoutmost=isoutmost)
    end
end

function update_escaped_negation!(args, ex; isoutmost=false)
    # Recursively update terms for single argument
    ex.args[2], str_arg, fmt_arg, _ = update_escaped!(args, ex.args[2]) 

    # No wrapping parenthese needed for negation, even if outmost
    str_ex = string(ex.args[1]) * str_arg
    fmt_ex = string_unvec(ex.args[1]) * fmt_arg

    ex.args[1] = esc(ex.args[1])

    return ex, str_ex, fmt_ex, ""
end

function update_escaped_logical!(args, ex; isoutmost=false)
    # Recursively update terms for both arguments. If a sub-expression is also logical,
    # it doesn't need to be parenthesized, so consider it "outmost".
    ex.args[1], str_arg1, fmt_arg1, _ = update_escaped!(args, ex.args[1], isoutmost=is_logical(ex.args[1]))
    ex.args[2], str_arg2, fmt_arg2, _ = update_escaped!(args, ex.args[2], isoutmost=is_logical(ex.args[2]))

    str_ex = str_arg1 * " " * string(ex.head) * " " * str_arg2
    fmt_ex = fmt_arg1 * " " * string_unvec(ex.head) * " " *  fmt_arg2

    # Parenthesize always, unless outmost expression
    if !isoutmost
        str_ex, fmt_ex = "(" * str_ex * ")", "(" * fmt_ex * ")"
    end

    return ex, str_ex, fmt_ex, ""
end

function update_escaped_comparison!(args, ex; isoutmost=false)
    # Recursively update every other term (i.e. not operators):
    str_ex, fmt_ex = "", ""
    for i in 1:length(ex.args)
        if i % 2 == 1 # Term to be recursively updated
            ex.args[i], str_arg, fmt_arg, _ = update_escaped!(args, ex.args[i])
            str_ex *= str_arg
            fmt_ex *= fmt_arg
        else # Operator
            str_ex *= " " * string(ex.args[i]) * " "
            fmt_ex *= " " * string_unvec(ex.args[i]) * " "
            ex.args[i] = esc(ex.args[i])
        end
    end
    
    # Paren always, unless outmost
    if !isoutmost
        str_ex, fmt_ex = "(" * str_ex * ")", "(" * fmt_ex * ")"
    end
    
    return ex, str_ex, fmt_ex, ""
end

function update_escaped_argsapprox!(args, ex; isoutmost=false)
    # Recursively update terms for both arguments
    ex.args[2], str_arg1, fmt_arg1, _ = update_escaped!(args, ex.args[2])
    ex.args[3], str_arg2, fmt_arg2, _ = update_escaped!(args, ex.args[3])

    # Iterate through keyword arguments
    i = 4
    str_kw, fmt_kw = "", ""
    while i <= length(ex.args)
        # Keyword arguments will also be pushed to escaped args, but should be
        # wrapped in a Ref() call to avoid broadcasting
        push!(args, esc(Expr(:call, :Ref, ex.args[i].args[2])))

        # Add keywords to string format
        str_kw *= "$(ex.args[i].args[1]) = $(ex.args[i].args[2]), "
        fmt_kw *= "$(ex.args[i].args[1]) = {$(length(args)):s}, "

        # Replace keyword argument with ARG[i].x (.x is to un-Ref())
        ex.args[i].args[2] = :(ARG[$(length(args))].x)

        i += 1
    end

    # Format strings:
    str_ex = string(ex.args[1]) * "(" * str_arg1 * ", " * str_arg2  * ", " * chopsuffix(str_kw, ", ") * ")"
    if isoutmost 
        fmt_ex = fmt_arg1 * " " * string_unvec(ex.args[1]) * " " *  fmt_arg2
        fmt_kw = chopsuffix(fmt_kw, ", ")
    else
        fmt_ex = string_unvec(ex.args[1]) * "(" * fmt_arg1 * ", " * fmt_arg2 * ", " * chopsuffix(fmt_kw, ", ") * ")"
        fmt_kw = ""
    end

    ex.args[1] = esc(ex.args[1])

    return ex, str_ex, fmt_ex, fmt_kw
end

function update_escaped_displaycall!(args, ex; isoutmost=false)
    #TODO(tpapalex): this could use some cleaning up

    # Extract arguments and starting index depending on whether it's a :call or :.
    ex_args, i = ex.args[2].args, 1

    # Positional arguments. Recall that :parameters have been converted to keywords 
    # in preprocess() and will always come after all positional arguments.
    str_args, fmt_args = "", ""
    while i <= length(ex_args) && !(isa(ex_args[i], Expr) && ex_args[i].head === :kw)
        # Recursively update terms for both arguments
        ex_args[i], str_arg, fmt_arg = update_escaped!(args, ex_args[i])
        str_args *= str_arg * ", "
        fmt_args *= fmt_arg * ", "
        i += 1
    end

    # Keyword arguments
    str_kw, fmt_kw = "", ""
    while i <= length(ex_args)
        # Keyword arguments will also be pushed to escaped args, but should be
        # wrapped in a Ref() call to avoid broadcasting
        push!(args, esc(Expr(:call, :Ref, ex_args[i].args[2])))

        # Add keywords to string format
        str_kw *= "$(ex_args[i].args[1]) = $(ex_args[i].args[2]), "
        fmt_kw *= "$(ex_args[i].args[1]) = {$(length(args)):s}, "

        # Replace keyword argument with ARG[i].x (.x is to un-Ref())
        ex_args[i].args[2] = :(ARG[$(length(args))].x)

        i += 1
    end

    # Finalize string formatting
    str_ex = string(ex.args[1]) *  ".(" * 
        chopsuffix(str_args, ", ") * 
        (length(str_kw) == 0 ? "" : ", ") *
        chopsuffix(str_kw, ", ") * ")"
    if isoutmost
        fmt_ex = string(ex.args[1]) * "(" * 
            chopsuffix(fmt_args, ", ") * ")"
        fmt_kw = chopsuffix(fmt_kw, ", ")
    else
        fmt_ex = string(ex.args[1]) * "(" *
            chopsuffix(fmt_args, ", ") * 
            (length(fmt_kw) == 0 ? "" : ", ") *
            chopsuffix(fmt_kw, ", ") * ")"
        fmt_kw = ""
    end

    ex.args[1] = esc(ex.args[1])
    return ex, str_ex, fmt_ex, fmt_kw
end

function update_escaped_fallback!(args, ex; isoutmost::Bool=false)

    # Add escaped term to terms
    push!(args, esc(ex))

    # Determine if parentheses are needed around the expression
    parens = if isoutmost
        false
    elseif !isa(ex, Expr)
        false
    elseif ex.head === :vect || ex.head === :tuple || ex.head === :hcat || ex.head === :vcat
        false
    elseif (ex.head === :call || ex.head === :.) && Base.operator_precedence(ex.head) == 0
        false
    else
        true
    end

    # Stringify the expression, but replace
    str_ex = parens ?  "(" * string(ex) * ")" : string(ex)
    
    # The format string will just be the value of the term
    fmt_ex = "{$(length(args)):s}"
    
    # The expression term should now be ARG[i]
    ex = :(ARG[$(length(args))])

    return ex, str_ex, fmt_ex, ""
end

#################### Pretty Printing ###################
# Returns string.(idxs), but nicely justified within each dimension.
function string_idxs(idxs) 
    if eltype(idxs) <: CartesianIndex
        D = length(idxs[1])
        max_len = [maximum(idx -> length(string(idx.I[d])), idxs) for d in 1:D]
        to_str = idx -> join(map(i -> lpad(idx.I[i], max_len[i]), 1:D), ",")
        return map(to_str, idxs)
    else
        ss = string.(idxs)
        return lpad.(ss, maximum(length, ss))
    end
end

function print_failures(io, idxs, print_idx_message; prefix="              ", max_vals=10)
    # Figure out if we need to abbreviate to the top/bottom `max_vals` because there
    # are too many failures.
    if length(idxs) > max_vals
        abbrev_i = max_vals ÷ 2
        idxs = idxs[[1:abbrev_i; end-abbrev_i+1:end]]
    else
        abbrev_i = 0
    end
    str_idxs = string_idxs(idxs)

    for (i, idx) in enumerate(idxs)
        print(io, "\n", prefix, "idx=[", str_idxs[i], "]: ")
        print_idx_message(io, idx)
        if (i == abbrev_i) && (abbrev_i > 0)
            print(io, "\n", prefix, "⋮")
        end
    end

    return nothing
end

struct TypeErrorOnAllCall <: Exception
    msg::String
    function TypeErrorOnAllCall(evaled::AbstractArray) 
        io = IOBuffer()
        # Print type of result first
        print(io, typeof(evaled))
        if typeof(evaled) <: AbstractVector
            print(io, "(", length(evaled), ")")
        elseif typeof(evaled) <: AbstractArray
            print(io, "(", join(size(evaled), "×"), ")")
        end
    
        idxs = findall(x -> !isa(x, Bool), evaled)
        print(io, " with ", length(idxs), " non-Boolean value", length(idxs) == 1 ? ":" : "s:")
    
        print_idx_message = (io, idx) -> begin
            print(io, repr(evaled[idx]))
            printstyled(IOContext(io, :color => true), " ===> ", typeof(evaled[idx]), color=:light_yellow)
        end
        print_failures(io, idxs, print_idx_message, prefix="    ")
    
        return new(String(take!(io)))
    end
    function TypeErrorOnAllCall(evaled)
        io = IOBuffer()
        print(io, sprint(show, evaled, context = :limit => true))
        printstyled(IOContext(io, :color => true), " ===> ", typeof(evaled), color=:light_yellow)
        return new(String(take!(io)))
    end
end

function Base.showerror(io::IO, err::TypeErrorOnAllCall)
    print(io, "TypeError: non-boolean used in boolean context")
    if err.msg != ""
        print(io, "\n  Argument isa ", err.msg)
    end
end

function eval_test_all(
        @nospecialize(evaled),
        @nospecialize(terms),
        fmt_ex, 
        fmt_kw, 
        source::LineNumberNode=LineNumberNode(1))

    # Try to evaluate all()
    res = try 
        all(evaled)
    catch _e
        # If TypeError because non-boolean used in boolean context, rethrow with 
        # internal TypeErrorOnAllCall exception for nicer formatting.
        if isa(_e, TypeError) && _e.expected === Bool
            throw(TypeErrorOnAllCall(evaled))
        else
            rethrow(_e)
        end
    end

    if res === true
        return Returned(res, nothing, source)
    end

    if !isa(res, Union{Bool, Missing})
        error("all() did not return a boolean or missing value")
    end

    if !isa(fmt_ex, FormatExpr)
        fmt_ex = FormatExpr(fmt_ex)
    end

    # Broadcast the input terms
    broadcasted_terms = Base.broadcasted(tuple, terms...)

    io = IOBuffer()

    # Print a nice message. If the evaluated result (evaled) is a false or missing, 
    # then no need for pretty indexing.
    if isa(evaled, Union{Bool,Missing})
        these_terms = repr.(first(broadcasted_terms))
        printfmt(io, fmt_ex, these_terms...)
        if fmt_kw != ""
            print(io, " with evaluated keywords: ")
            printfmt(io, fmt_kw, these_terms...)
        end
        if ismissing(evaled)
            printstyled(IOContext(io, :color => true), " ===> missing", color=:light_yellow)
        else
            printstyled(IOContext(io, :color => true), " ===> false", color=:light_yellow)
        end

    else # Otherwise, use pretty-printing with indices:
        # First, print type of inner expression 
        io = IOBuffer()
        print(io, "Argument isa ")
        if isa(evaled, AbstractVector)
            print(io, "BitVector(", length(evaled), ")")
        elseif isa(evaled, AbstractArray)
            print(io, "BitArray(", join(size(evaled), "×"), ")")
        else
            print(io, typeof(evaled))
        end

        # Then print the number of failures and missing values
        n_false = sum(x -> !x, skipmissing(evaled), init=0)
        n_missing = sum(x -> ismissing(x), evaled)
        print(io, " with ")
        if n_false > 0
            print(io, n_false, " failure", n_false == 1 ? "" : "s")
            if n_missing > 0
                print(io, " and ")
            end
        end
        if n_missing > 0
            print(io, n_missing, " missing value", n_missing == 1 ? "" : "s")
        end
        print(io, ":")

        # If non-blank keyword print, print it:
        if fmt_kw != ""
            print(io, "\n    Evaluated keywords: ")
            printfmt(io, fmt_kw, repr.(first(broadcasted_terms))...)
        end

        # Try to print findall all the failiing indices and pretty-print, otherwise
        # continue
        
        idxs = try 
            findall(x -> x !== true, evaled)
        catch _e
            return Returned(false, String(take!(io)), source)
        end

        print_idx_message = (io, idx) -> begin
            printfmt(io, fmt_ex, repr.(broadcasted_terms[idx])...)
            if ismissing(evaled[idx])
                printstyled(IOContext(io, :color => true), " ===> missing", color=:light_yellow)
            else
                printstyled(IOContext(io, :color => true), " ===> false", color=:light_yellow)
            end
        end
        print_failures(io, idxs, print_idx_message)
    end

    return Returned(false, String(take!(io)), source)
end

function get_test_all_result(ex, source)
    escaped_args = []
    mod_ex, str_ex, fmt_ex, fmt_kw = update_escaped!(escaped_args, ex; isoutmost=true)

    result = quote
        try
            let ARG = Any[$(escaped_args...)]
                eval_test_all(
                    $(mod_ex), 
                    ARG, 
                    $(fmt_ex), 
                    $(fmt_kw), 
                    $(QuoteNode(source))
                )
            end
        catch _e
            _e isa InterruptException && rethrow()
            Threw(_e, Base.current_exceptions(), $(QuoteNode(source)))
        end
    end

    return result, str_ex
end

macro test_all(ex, kws...)
    # Collect the broken/skip keywords and remove them from the rest of keywords
    broken = [kw.args[2] for kw in kws if kw.args[1] === :broken]
    skip = [kw.args[2] for kw in kws if kw.args[1] === :skip]
    kws = filter(kw -> kw.args[1] ∉ (:skip, :broken), kws)
    # Validation of broken/skip keywords
    for (kw, name) in ((broken, :broken), (skip, :skip))
        if length(kw) > 1
            error("invalid test macro call: cannot set $(name) keyword multiple times")
        end
    end
    if length(skip) > 0 && length(broken) > 0
        error("invalid test macro call: cannot set both skip and broken keywords")
    end

    # Add keywords to the expression
    ex = add_keywords!(ex, kws...)

    # Get the result expression and the stringified version of the expression
    result, str_ex = get_test_all_result(ex, __source__)
    str_ex = "all(" * str_ex * ")"

    # Return the result expression
    result = quote
        if $(length(skip) > 0 && esc(skip[1]))
            record(get_testset(), Broken(:skipped, $ex))
        else
            let _do = $(length(broken) > 0 && esc(broken[1])) ? do_broken_test : do_test
                _do($result, $str_ex)
            end
        end
    end
    return result
end
