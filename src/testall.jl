#-----------------------------------------------------------------------
# List of functions whose arguments will be displayed nicely.
const DISPLAYABLE_FUNCS = (
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
    :isa, 
    :≈, 
    :≉,
)

# For identifying comparison expressions
const COMPARISON_PREC = Base.operator_precedence(:(==)) 

# Lists of operators to treat specially
const OPS_LOGICAL = (:.&, :.|, :.⊻, :.⊽)
const OPS_APPROX = (:.≈, :.≉)  

const isexpr = Meta.isexpr

# A reference value for the max number of failures to print in a @testall failure.
const MAX_PRINT_FAILURES = Ref{Int64}(10)

function set_max_print_failures!(n::Integer)
    MAX_PRINT_FAILURES[] = n
end
function get_max_print_failures()
    return MAX_PRINT_FAILURES[]
end

#################### Pre-processing expressions ###################

# Checks if an operator symbol is vectorized
function isvecoperator(x::Union{AbstractString,Symbol}) 
    return Meta.isoperator(x) && first(string(x)) == '.'
end

# Checks if an argument from  :call or :. expression is not a keyword/parameters/splat
function ispositionalargexpr(ex)
    return !isexpr(ex, (:kw, :parameters, :...))
end

# Get the unvectorized version of vectorized operator as a string,
function string_unvec(x::Symbol) 
    sx = string(x)
    return sx[1] == '.' ? sx[2:end] : sx 
end

"""
    pushkeywords!(ex, kws...)

Preprocess `@testall` expressions of function calls with trailing keyword arguments, 
so that e.g. `@testall a .≈ b atol=ε` means `@testall .≈(a, b, atol=ε)`.

If `ex` is a negation expression (either a `!` or `.!` call), keyword arguments will 
be added to the inner expression, so that `@testall .!(a .≈ b) atol=ε` means 
`@testall .!(.≈(a, b, atol=ε))`.
"""
pushkeywords!(ex) = ex

function pushkeywords!(ex, kws...)
    # Recursively dive through negations
    orig_ex = ex
    while isexpr(ex, :call, 2) && (ex.args[1] === :! || ex.args[1] === :.!)
        ex = ex.args[2]
    end

    # Check that inner expression is a :call or :.
    if !isexpr(ex, (:call, :.))
        error("invalid test macro call: @testall $ex does not accept keyword arguments")
    end

    # Push keywords to the end of arguments as keyword expressions
    args = ex.head === :call ? ex.args : ex.args[2].args
    for kw in kws
        if isexpr(kw, :(=))
            kw.head = :kw
            push!(args, kw)
        else
            error("invalid test macro call: $kw is not valid keyword synt")
        end
    end

    return orig_ex
end

# An internal function, recursively called on the @testall expression to normalize it.
function preprocess(ex)

    # Normalize dot comparison operator calls to :comparison expressions. 
    # Do not if there are extra arguments or there are splats.
    if Meta.isexpr(ex, :call, 3) && 
        Base.operator_precedence(ex.args[1]) == COMPARISON_PREC &&
        isvecoperator(ex.args[1]) && 
        ispositionalargexpr(ex.args[2]) && 
        ispositionalargexpr(ex.args[3])
        
        ex = Expr(:comparison, ex.args[2], ex.args[1], ex.args[3])

    # Mark .<: and .>: as :comparison expressions
    elseif Meta.isexpr(ex, :call, 3) && 
        (ex.args[1] === :.<: || ex.args[1] === :.>:) && 
        ispositionalargexpr(ex.args[2]) && 
        ispositionalargexpr(ex.args[3])

        ex = Expr(:comparison, ex.args[2], ex.args[1], ex.args[3])  
    
    # For displayable :call or :. expressions, push :kw expressions in :parameters to 
    # end of arguments. 
    elseif isexpr(ex, (:call, :.)) && 
        ((ex.args[1] ∈ OPS_APPROX) || (ex.args[1] ∈ DISPLAYABLE_FUNCS))

        # For :call arguments start at i = 2
        # For :. they start at i = 1, inside the ex.args[2] :tuple expression
        args, i = ex.head === :call ? (ex.args, 2) : (ex.args[2].args, 1)

        # Push any :kw expressions in :parameters as trailing keywords
        if length(args) != 0 && isexpr(args[i], :parameters)
            parex = args[i]
            new_args = args[i+1:end]
            new_parex_args = []
            for a in parex.args
                if isexpr(a, :kw)
                    push!(new_args, a)
                else
                    push!(new_parex_args)
                end
            end

            # If remaining :parameters, readd at beginning of args
            if length(new_parex_args) > 0
                insert!(new_args, 1, Expr(:parameters, new_parex_args...))
            end

            # Depending on head, recreate expression
            if ex.head === :call
                ex = Expr(:call, ex.args[1], new_args...)
            else
                ex = Expr(:., ex.args[1], Expr(:tuple, new_args...))
            end
        end
    end

    return ex
end

#################### Classifying expressions ###################
# The following internal functions are used to classify expressions into 
# certain groups that will be displayed differently by `@testall`.

# NOT expressions, e.g. !a
isvecnegationexpr(ex) = isexpr(ex, :call, 2) && ex.args[1] === :.!

# Vectorized AND or OR expressions, e.g, a .&& b, a .|| c
isveclogicalexpr(ex) = isexpr(ex, :call) && ex.args[1] ∈ OPS_LOGICAL

# Most comparison expressions, e.g. a == b, a <= b <= c, a ≈ B. Note that :call
# expressions with comparison ops are chanegd to :comparison in preprocess()
function isveccomparisonexpr(ex)
    return isexpr(ex, :comparison) && 
        all(i -> isvecoperator(ex.args[i]), 2:2:length(ex.args))
end

# Special case of .≈() or .≉() expression with no splats, for prettier formatting
function isvecapproxexpr(ex)
    return isexpr(ex, :call) && 
        ex.args[1] ∈ OPS_APPROX &&
        ispositionalargexpr(ex.args[2]) && 
        ispositionalargexpr(ex.args[3])        
end

# Vectorized call of displayable function with no splats
function isvecdisplayexpr(ex)
    return isexpr(ex, :.) && 
        ex.args[1] ∈ DISPLAYABLE_FUNCS &&
        sum(a -> isexpr(a, :...), ex.args[2].args, init=0) == 0
end

# Anonymous function (x -> )
isanonfuncexpr(ex) = isexpr(ex, :->)

#################### Escaping arguments ###################

"""
    recurse_escape!(args, ex; isoutmost=false)

Recursively replaces subexpressions in `ex` with references to `ARG[i]`, 
when the subexpression should be broadcast for displaying `@testall` failures.
The subexpressions themselves are escaped and pushed to `args`. 

The same is done for values in keyword subexpressions, except that the reference
is wrapped in a `Ref` call, so that they are not broadcast.

Returns `ex` with the modified subexpressions, as well as format strings 
for pretty printing failures.

# Arguments
- 'args`: Vector where escaped subexpressions should be pushed.
- 'ex`: The source expression to modify.
  
# Keyword Arguments
- 'isoutmost=false`: Whether the `ex` is the outmost expression, to know the format 
  expression wrap in parentheses.

# Returns Tuple{Expr,String,String,String}:
- modified `ex` with subexpressions replaced by the corresponding `ARG[i]`
- a `FormatExpr`-like string with the order of  broadcasted A
- a `FormatExpr`-like string, for pretty-printing the keyword arguments used in `ex` (only
  if `isoutmost` and `ex` is a displayable `:call` or `:.`)
"""
function recurse_escape!(ex, args::Vector{Expr}; outmost::Bool=true)
    ex = preprocess(ex)
    if isvecnegationexpr(ex)
        return recurse_escape_negation!(ex, args, outmost=outmost)
    elseif isveclogicalexpr(ex)
        return recurse_escape_logical!(ex, args, outmost=outmost)
    elseif isveccomparisonexpr(ex)
        return recurse_escape_comparison!(ex, args, outmost=outmost)
    elseif isvecapproxexpr(ex)
        return recurse_escape_approx!(ex, args, outmost=outmost)
    elseif isvecdisplayexpr(ex)
        return recurse_escape_displayfunc!(ex, args, outmost=outmost)
    else
        return recurse_escape_basecase!(ex, args, outmost=outmost)
    end
end

struct Formatter
    io::IOBuffer
    parens::Bool
    Formatter(parens::Bool=true) = new(IOBuffer(), parens)
end

function stringify!(fmt::Formatter)
    str = String(take!(fmt.io))
    if fmt.parens 
        return "($str)"
    else
        return str
    end
end

function Base.print(fmt::Formatter, i::Integer)
    print(fmt.io, "{$i:s}")
end

function Base.print(fmt::Formatter, strs::AbstractString...)
    print(fmt.io, strs...)
end

function Base.print(fmt::Formatter, innerfmt::Formatter)
    print(fmt.io, stringify!(innerfmt))
    close(innerfmt.io)
end

function Base.print(fmt::Formatter, s)
    print(fmt.io, string(s))
end

function recurse_escape_basecase!(ex, args::Vector{Expr}; outmost::Bool=true)
    # Escape entire expression to args
    push!(args, esc(ex))

    # Override parentheses if expression doesn't need them
    addparens = !outmost
    if !isa(ex, Expr) || 
        ex.head ∈ (:vect, :tuple, :hcat, :vcat) || 
        (isexpr(ex, (:call, :.)) && Base.operator_precedence(ex.args[1]) == 0)

        addparens = false
    end

    # Create a simple format string
    fmt = Formatter(addparens)
    print(fmt, length(args))

    # Replace the expression with ARG[i]
    ex = :(ARG[$(length(args))])
    return ex, fmt, Formatter(false)
end

function recurse_escape_keyword!(ex::Expr, args::Vector{Expr})
    # Keyword argument values are pushed to escaped `args`, but should be
    # wrapped in a Ref() call to avoid broadcasting.
    push!(args, esc(Expr(:call, :Ref, ex.args[2])))

    fmt = Formatter(false)
    print(fmt, ex.args[1])
    print(fmt, " = ")
    print(fmt, length(args))

    # Replace keyword argument with ARG[i].x to un-Ref() in evaluation
    ex.args[2] = :(ARG[$(length(args))].x)
    
    return ex, fmt
end

function recurse_escape_negation!(ex::Expr, args::Vector{Expr}; outmost::Bool=true)
    # Recursively update the second argument
    ex.args[2], fmt_arg, _ = recurse_escape!(ex.args[2], args)

    # Never requires parentheses outside the negation
    fmt = Formatter(false)
    print(fmt, "!")
    print(fmt, fmt_arg)

    # Escape negation operator
    ex.args[1] = esc(ex.args[1])

    return ex, fmt, Formatter(false)
end

function recurse_escape_logical!(ex::Expr, args::Vector{Expr}; outmost::Bool=true)

    fmt = Formatter(!outmost)
    for i in 2:length(ex.args)
        # Recursively update the two arguments. If a sub-expression is also logical, 
        # there is no need to parenthesize so consider it `outmost=true`.
        ex.args[i], fmt_arg, _ = recurse_escape!(
            ex.args[i], args, outmost=isveclogicalexpr(ex.args[i]))

        # Unless it's the first argument, print the operator
        i == 2 || print(fmt, " ", string_unvec(ex.args[1]), " ")
        print(fmt, fmt_arg)
    end

    # Escape the operator
    ex.args[1] = esc(ex.args[1])

    return ex, fmt, Formatter(false)
end

function recurse_escape_comparison!(ex::Expr, args::Vector{Expr}; outmost::Bool=false)
    fmt = Formatter(!outmost)
    # Recursively update every other argument (i.e. the terms), and 
    # escape the operators.
    for i in eachindex(ex.args)
        if i % 2 == 1 # Term
            ex.args[i], fmt_arg, _ = recurse_escape!(ex.args[i], args)
            print(fmt, fmt_arg)
        else # Operator
            print(fmt, " ", string_unvec(ex.args[i]), " ")
            ex.args[i] = esc(ex.args[i])
        end
    end
    
    return ex, fmt, Formatter(false)
end

function recurse_escape_approx!(ex::Expr, args::Vector{Expr}; outmost::Bool=false)
    # Recursively update both positional arguments
    ex.args[2], fmt_arg1, _ = recurse_escape!(ex.args[2], args)
    ex.args[3], fmt_arg2, _ = recurse_escape!(ex.args[3], args)

    # Recursively update with keyword arguments
    fmt_kws = Formatter(false)
    for i in 4:length(ex.args)
        ex.args[i], fmt_kw_i = recurse_escape_keyword!(ex.args[i], args)
        print(fmt_kws, fmt_kw_i)
        i == length(ex.args) || print(fmt_kws, ", ")
    end

    fmt_ex = Formatter(false)
    if outmost
        print(fmt_ex, fmt_arg1)
        print(fmt_ex, " ", string_unvec(ex.args[1]), " ")
        print(fmt_ex, fmt_arg2)
    else
        print(fmt_ex, string_unvec(ex.args[1]))
        print(fmt_ex, "(")
        print(fmt_ex, fmt_arg1)
        print(fmt_ex, ", ")
        print(fmt_ex, fmt_arg2)
        print(fmt_ex, ", ")
        print(fmt_ex, fmt_kws)
        print(fmt_ex, ")")
        fmt_kws = Formatter(false)
    end

    # Escape function
    ex.args[1] = esc(ex.args[1])

    return ex, fmt_ex, fmt_kws
end

function recurse_escape_displayfunc!(ex::Expr, args::Vector{Expr}; outmost::Bool=false)
    ex_args = ex.args[2].args

    fmt_ex = Formatter(false)
    print(fmt_ex, string(ex.args[1]), ".(")
    fmt_kws = Formatter(false)

    n_args, n_kws = 0, 0
    for i in eachindex(ex_args)
        if !isexpr(ex_args[i], :kw)
            # Recursively update each positional argument
            n_args += 1
            ex_args[i], fmt_arg, _ = recurse_escape!(ex_args[i], args)
            print(fmt_ex, fmt_arg)
            i == length(ex_args) || isexpr(ex_args[i+1], :kw) || print(fmt_ex, ", ")
        else
            # Treat keywords specially
            n_kws += 1
            ex_args[i], fmt_kw_i = recurse_escape_keyword!(ex_args[i], args)
            print(fmt_kws, fmt_kw_i)
            i == length(ex_args) || print(fmt_kws, ", ")
        end
    end

    if outmost
        print(fmt_ex, ")")
    else
        n_args == 0 || n_kws == 0 || print(fmt_ex, ", ")
        print(fmt_ex, fmt_kws)
        print(fmt_ex, ")")
        fmt_kws = Formatter(false)
    end

    # Escape the function name
    ex.args[1] = esc(ex.args[1])

    return ex, fmt_ex, fmt_kws
end


# function recurse_escape_displayfunc!(args, ex; isoutmost=false)
#     ex_args = ex.args[2].args

#     str_args, fmt_args = "", ""
#     str_kws, fmt_kws = "", ""
#     for i in eachindex(ex_args)
#         if !isexpr(ex_args[i], :kw)
#             # Recursively update each positional argument
#             ex_args[i], str_arg, fmt_arg, _ = recurse_escape!(args, ex_args[i])
#             str_args *= str_arg * ", "
#             fmt_args *= fmt_arg * ", "
#         else
#             # Treat keywords specially
#             ex_args[i], str_kw, fmt_kw = recurse_escape_keyword!(args, ex_args[i])
#             str_kws *= str_kw * ", "
#             fmt_kws *= fmt_kw * ", "
#         end
#     end

#     # Finalize string formatting
#     str_args = chopsuffix(str_args, ", ")
#     fmt_args = chopsuffix(fmt_args, ", ")
#     str_kws = chopsuffix(str_kws, ", ")
#     fmt_kws = chopsuffix(fmt_kws, ", ")
    
#     str_ex = "$(ex.args[1]).($(str_args)\
#               $(length(str_kws) == 0 ? "" : ", ")$(str_kws))"

#     if isoutmost
#         fmt_ex = "$(ex.args[1])($fmt_args)"
#     else
#         fmt_ex = "$(ex.args[1])($(fmt_args)\
#                   $(length(fmt_kws) == 0 ? "" : ", ")$(fmt_kws))"
#         fmt_kws = ""
#     end

#     # Escape the function name
#     ex.args[1] = esc(ex.args[1])
#     return ex, str_ex, fmt_ex, fmt_kws
# end

# function recurse_escape_fallback!(args, ex; isoutmost::Bool=false)
#     # Recursion base case, escape etntire expression
#     push!(args, esc(ex))

#     # Determine if parentheses are needed around the expression
#     parens = if isoutmost
#         false
#     elseif !isa(ex, Expr)
#         false
#     elseif ex.head === :vect || ex.head === :tuple || ex.head === :hcat || ex.head === :vcat
#         false
#     elseif (ex.head === :call || ex.head === :.) && Base.operator_precedence(ex.args[1]) == 0
#         false
#     else
#         true
#     end
#     str_ex = parens ?  "(" * string(ex) * ")" : string(ex)
#     fmt_ex = "{$(length(args)):s}"
#     fmt_kw = ""
    
#     # Replace the expression term should now be ARG[i]
#     ex = :(ARG[$(length(args))])

#     return ex, str_ex, fmt_ex, fmt_kw
# end

#################### Pretty Printing ###################
# Internal function to stringify vectors of indices, but justified.
function stringify_idxs(idxs::AbstractVector) 
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


const _INDENT_EVALUATED = "              "
const _INDENT_TYPEERROR = "    "

# Internal function to print failures
function print_failures(
            io::IO, 
            idxs::AbstractVector,
            print_idx_failure, 
            prefix=""
        )


    MAX_PRINT_FAILURES[] == 0 && return

    # Figure out if we need to abbreviate to the top/bottom `max_vals` because there
    # are too many failures.
    if length(idxs) > max_vals
        abbrev_i = max_vals ÷ 2
        idxs = idxs[[1:abbrev_i; end-abbrev_i+1:end]]
    else
        abbrev_i = 0
    end
    str_idxs = stringify_idxs(idxs)

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

function eval_testall(
        evaled,
        terms,
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

function get_testall_result(ex, source)
    escaped_args = []
    mod_ex, str_ex, fmt_ex, fmt_kw = recurse_escape!(escaped_args, ex; isoutmost=true)

    result = quote
        try
            let ARG = Any[$(escaped_args...)]
                eval_testall(
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

macro testall(ex, kws...)
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
    ex = pushkeywords!(ex, kws...)

    # Get the result expression and the stringified version of the expression
    result, str_ex = get_testall_result(ex, __source__)
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
