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
const OPS_LOGICAL = (:&&, :||, :.&&, :.||) # TODO(tpapalex) add XOR (⊻)
const OPS_NEGATION = (:!, :.!)
const OPS_APPROX = (:≈, :.≈, :≉, :.≉)  

_is_vecop = x::Symbol -> first(string(x)) == '.'
_is_splat = x -> isa(x, Expr) && x.head === :...

#################### Expression Parsing ###################

# Internal function that's called at the top-level @test_all macro call. Returns `ex` 
# with all negations recursively removed, and Bool of whether it should be negated once.
function extract_negation(ex)
    negate = false
    while is_negation(ex)
        negate = !negate
        ex = ex.args[2]
    end
    return ex, negate
end

add_keywords!(ex) = ex
function add_keywords!(ex, kws)
    if !(isa(ex, Expr) && (ex.head === :. || ex.head === :call))
        error("invalid test macro call: @test_all $ex cannot take keyword arguments")
    end

    ex_args = ex.head === :call ? ex.args : ex.args[2].args

    for kw in kws
        if isa(kw, Expr) && kw.head === :(=)
            kw.head = :kw
            push!(ex_args, kw)
        else
            error("invalid test macro call: $kw is not a keyword argument")
        end
    end

    return ex
end

# Internal function that performs some pre-processing on a single expression. This is called
# first in any `process_...` call to make pretty arguments.
#   1) Removes nested negations at the head.
#   2) Changes :calls with binary comparison operator and no args as :comparison 
#   3) Changes <:, >: expressions with no args to :comparison
function _preprocess(ex)

    # Normalize :call with comparison-precedence operator to :comparison. Do not do 
    # if arguments are splats, or if there are extra keywords.
    if isa(ex, Expr) && 
        ex.head === :call &&   
        (
            ex.args[1] === :(==) || 
            ex.args[1] === :.==  || 
            Base.operator_precedence(ex.args[1]) == COMPARISON_PREC
        ) &&
        length(ex.args) == 3 && # Excludes cases where kws were added
        !_is_splat(ex.args[2]) && 
        !_is_splat(ex.args[3])

        return Expr(:comparison, ex.args[2], ex.args[1], ex.args[3])

    # Mark <: and >: as :comparison expressions
    elseif isa(ex, Expr) && 
        Base.operator_precedence(ex.head) == COMPARISON_PREC &&
        !_is_splat(ex.args[1]) &&
        !_is_splat(ex.args[2]) 

        return Expr(:comparison, ex.args[1], ex.head, ex.args[2])

    # Mark vectorized .<: and .>: as :comparison expressions
    elseif isa(ex, Expr) && 
        ex.head === :call && 
        (ex.args[1] === :.<: || ex.args[1] === :.>:) && 
        length(ex.args) == 3 && # Exclude cases where kws were added
        !_is_splat(ex.args[2]) && 
        !_is_splat(ex.args[3]) 

        return Expr(:comparison, ex.args[2], ex.args[1], ex.args[3])  
    
    # Consolidate keyword arguments into parameters for :call or :.
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
        ex.args[1] ∈ OPS_NEGATION && 
        length(ex.args) == 2
end

# AND or OR expressions Logical expressions, e.g, a && b, a || c
function is_logical(ex)
    return isa(ex, Expr) && 
        ex.head ∈ OPS_LOGICAL && 
        length(ex.args) == 2
end

# Most comparison expressions, e.g. a == b, a <= b <= c, a ≈ B. Note that :call
# expressions with comparison ops are chanegd to :comparison in _do_preprocessing()
function is_comparison(ex)
    return isa(ex, Expr) && ex.head === :comparison
end


function is_argsapprox(ex)
    if isa(ex, Expr) && 
        ex.head === :call && 
        ex.args[1] ∈ OPS_APPROX

        # Must also have exactly two positional arguments, non-splat (plus operator)
        n_args = length(ex.args) - sum(a -> isa(a, Expr) && a.head ∈ (:kw, :parameters), ex.args)
        if n_args != 3 
            return false
        end

        # Check that positional arguments are not splats
        i = !isa(ex.args[2], Expr) || ex.args[2].head === :parameters ? 3 : 2
        if _is_splat(ex.args[i]) || _is_splat(ex.args[i+1])
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
        (ex.head === :call || ex.head === :.) && 
        ex.args[1] ∈ DISPLAYABLE_FUNCS

        # Check for non-displayable parameters/kwargs
        args = ex.head === :call ? ex.args[2:end] : ex.args[2].args

        par_ex = args[1]
        if isa(par_ex, Expr) && par_ex.head === :parameters
            for a in par_ex.args
                # If non-kw parameter, then do not support display
                if !(isa(a, Expr) && a.head === :kw)
                    return false
                end
            end
        end

        # Positional arguments
        for a in args
            isa(a, Expr) && a.head ∈ (:kw, :parameters) && continue
            # If splatted argument, then do not support display
            if isa(a, Expr) && a.head === :...
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
    ex = _preprocess(ex)
    is_negation(ex) && return false
    is_logical(ex) && return false
    is_comparison(ex) && return false
    is_argsapprox(ex) && return false
    is_displaycall(ex) && return false
    return true
end


# Anonymous function that can be displayed
function is_mappable(ex, kws=())
    return isa(ex, Expr) && 
        ex.head === :-> && 
        length(kws) == 1
end


#################### String creation ###################
function requires_outer_parens(ex; isoutmost::Bool=false)

end

function string_unvec(x::Symbol) 
    sx = string(x)
    return sx[1] == '.' ? sx[2:end] : sx 
end
function string_unvec(x::Expr)
    @assert ex.head === :call || ex.head === :.
    return string(ex.args[1])
end


#################### Escaped args updaters ###################
"""
    update_escaped!(args, kwargs, ex; isoutmost=false)

Updates `args` and `kwargs` with esc(...) expressions, and returns back a modified 
expression , as well as strings needed for pretty printing.

These functions are the core of @test_all's pretty-printing. TODO: write more.

# Arguments
- 'args::Vector`: Vector of escaped expressions to push broadcastable arguments to.
- 'kwargs::Vector`: Vector of escaped keyword argument values to push broadcastable 
arguments to.
- 'ex::Expr`: The source expression.
  
# Keyword Arguments
- 'isoutmost::Bool=false`: Whether the expression is the outmost expression, necessary
  to know whether the stringified expression should be wrapped in parentheses in a 
  recursive call. 

# Returns tuple:
- `::Expr`: A modified version of `ex` where broadcastable arguments/keywords have been 
  replaced with ARG[i] or KW[i]. Once ARG and KW have been defined (in the quoted 
  expression returned by `eval_test_op()`), evaluating this will return exactly the same
  thing as the original `ex`.
- `::String`: A stringified version of the unmodified `ex`. This is rebuilt up as we go, 
  since inner recursions modify the expression.
- `::String`: A string that can be used as a `FormatExpr` for pretty-printing arguments.
- `::String`: A string that can be used as a `FormatExpr` for pretty-printing keyword 
  arguments.
"""
function update_escaped!(args, kwargs, ex; isoutmost=false)
    # Pre-process the expression first, to normalize comparisons, fix keywords etc.
    ex = _preprocess(ex)
    if is_negation(ex)
        return update_escaped_negation!(args, kwargs, ex; isoutmost=isoutmost)
    elseif is_logical(ex)
        return update_escaped_logical!(args, kwargs, ex; isoutmost=isoutmost)
    elseif is_comparison(ex)
        return update_escaped_comparison!(args, kwargs, ex; isoutmost=isoutmost)
    elseif is_argsapprox(ex)
        return update_escaped_argsapprox!(args, kwargs, ex; isoutmost=isoutmost)
    elseif is_displaycall(ex)
        return update_escaped_displaycall!(args, kwargs, ex; isoutmost=isoutmost)
    else # is_fallback(ex)
        return update_escaped_fallback!(args, kwargs, ex; isoutmost=isoutmost)
    end
end

function update_escaped_negation!(args, kwargs, ex; isoutmost=false)
    # Recursively update terms for single argument
    ex.args[2], str_arg, fmt_arg, _ = update_escaped!(args, kwargs, ex.args[2]) 

    # No wrapping parenthese needed for negation, even if outmost
    str_ex = string(ex.args[1]) * str_arg
    fmt_ex = "!" * fmt_arg

    return ex, str_ex, fmt_ex, ""
end

function update_escaped_logical!(args, kwargs, ex; isoutmost=false)
    # Recursively update terms for both arguments
    ex.args[1], str_arg1, fmt_arg1, _ = update_terms!(args, kwargs, ex.args[1])
    ex.args[2], str_arg2, fmt_arg2, _ = update_terms!(args, kwargs, ex.args[2])

    # Paren always needed for logical expressions
    str_ex = str_arg1 * " " * string(ex.head) * " " * str_arg2
    fmt_ex = fmt_arg1 * " " * _string_unvec(ex.head) * " " *  fmt_arg2

    # Paren always unless outmost expression
    if !isoutmost
        str_ex, fmt_ex = "(" * str_ex * ")", "(" * fmt_ex * ")"
    end

    return ex, str_ex, fmt_ex, ""
end

function update_escaped_comparison!(args, kwargs, ex; isoutmost=false)
    # Recursively update every other term:
    str_ex, fmt_ex = "", ""
    for i in 1:length(args)
        if i % 2 == 1 # Term to be recursively updated
            ex.args[i], str_arg, fmt_arg = update_terms!(args, kwargs, ex.args[i])
            str_ex *= str_arg
            fmt_ex *= fmt_arg
        else
            str_ex *= " " * string(ex.args[i]) * " "
            fmt_ex *= " " * string_unvec(ex.args[i]) * " "
        end
    end
    
    # Paren always unless outmost
    if !isoutmost
        str_ex, fmt_ex = "(" * str_ex * ")", "(" * fmt_ex * ")"
    end
    
    return ex, str_ex, fmt_ex, ""
end

function update_escaped_argsapprox!(args, kwargs, ex; isoutmost=false)

    # Recursively update terms for both arguments
    ex.args[1], str_arg1, fmt_arg1, _ = update_terms!(args, kwargs, ex.args[1])
    ex.args[2], str_arg2, fmt_arg2, _ = update_terms!(args, kwargs, ex.args[2])
    fmt_kw = ""

    if isoutmost
        # Paren always needed for logical expressions
        str_ex = str_arg1 * " " * string(ex.args[1]) * " " * str_arg2
        fmt_ex = fmt_arg1 * " " * _string_unvec(ex.args[1]) * " " *  fmt_arg2

        i = 3
        while i <= length(ex.args)
            # Push escaped keyword value to kwargs
            push!(kwargs, esc(ex.args[i].args[2]))
            
            # Get the format
            fmt_kw_i = "$(ex.args[i].args[1]) = {$(length(kwargs)):s}, "
            fmt_kw *= fmt_kw_i

            # The keyword value should now be KW[.]
            ex.args[i].args[2] = :(KW[$(length(kwargs))])

            i += 1
        end
    else
        str_ex = string(ex.args[1]) * "(" * str_arg1 * ", " * str_arg2 * ", "

        i = 3
        while i <= length(ex.args)
            # Push escaped keyword value to kwargs
            push!(kwargs, esc(ex.args[i].args[2]))
            
            # Get the format
            fmt_kw_i = "$(ex.args[i].args[1]) = {$(length(kwargs)):s}, "
            if outmost
                fmt_kw *= fmt_kw_i
            else
                fmt_ex *= fmt_kw_i
            end

            # The keyword value should now be KW[.]
            ex.args[i].args[2] = :(KW[$(length(kwargs))])

            i += 1
        end

        # Finalize the string formatting
        fmt_ex
    end


    return ex, str_ex, fmt_ex, ""
end

function update_escaped_displaycall!(args, kwargs, ex; isoutmost=false)

    # Initialize string formatting stuff
    str_ex = string(ex.args[1]) * (ex.head === :call ? "(" : ".(")
    fmt_ex = string(ex.args[1]) * "("
    fmt_kw = ""
    
    if ex.head === :call
        # Positional arguments. Recall that :parameters have been converted to keywords 
        # in _preprocess() and will always come after all positional arguments.
        i = 2
        while !(isa(ex.args[i], Expr) && ex.args[i].head === :kw)
            ex.args[i], str_arg, fmt_arg = update_terms!(args, kwargs, ex.args[i])
            str_ex *= str_arg * ", "
            fmt_ex *= fmt_arg * ", "
            i += 1
        end

        while i <= length(ex.args)
            # Push escaped keyword value to kwargs
            push!(kwargs, esc(ex.args[i].args[2]))
            
            # Get the format
            fmt_kw_i = "$(ex.args[i].args[1]) = {$(length(kwargs)):s}, "
            if outmost
                fmt_kw *= fmt_kw_i
            else
                fmt_ex *= fmt_kw_i
            end

            # The keyword value should now be KW[.]
            ex.args[i].args[2] = :(KW[$(length(kwargs))])

            i += 1
        end

    else # ex.head === :.

        # Positional arguments. Assumes no :parameters because converted to :kw in 
        i = 1
        while !(isa(ex.args[2].args[i], Expr) && ex.args[2].args[i].head === :kw)
            ex.args[2].args[i], str_arg, fmt_arg = update_terms!(args, kwargs, ex.args[2].args[i])
            str_ex *= str_arg * ", "
            fmt_ex *= fmt_arg * ", "
            i += 1
        end

        # Keyword arguments
        while i <= length(ex.args[2].args)
            # Push escaped keyword value to kwargs
            push!(kwargs, esc(ex.args[2].args[i].args[2]))
            
            # Get the format
            fmt_kw_i = "$(ex.args[2].args[i].args[1]) = {$(length(kwargs)):s}, "
            if outmost
                fmt_kw *= fmt_kw_i
            else
                fmt_ex *= fmt_kw_i
            end

            # The keyword value should now be KW[.]
            ex.args[2].args[i].args[2] = :(KW[$(length(kwargs))])

            i += 1
        end

    end

    # Finalize string formatting stuff
    str_ex = chop_suffix(str_ex, ", ") * ")"
    fmt_ex = chop_suffix(fmt_ex, ", ") * ")"

    return ex, str_ex, fmt_ex, fmt_kw

end

function update_escaped_fallback!(args, kwargs, ex; isoutmost::Bool=false)
    # Add escaped term to terms
    push!(args, esc(ex))

    # If expression is a non-operator :call or :., then no need to parenthesize
    parens = if isoutmost
        false
    elseif !isa(ex, Expr)
        false
    elseif ex.head === :hcat || ex.head == :vcat
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


function _string_idxs_justify(idxs) 
    if eltype(idxs) <: CartesianIndex
        D = length(idxs[1])
        max_len = [maximum(idx -> length(string(idx.I[d])), idxs) for d in 1:D]
        to_str = idx -> join(map(i -> lpad(idx.I[i], max_len[i]), 1:D), ", ")
        return map(to_str, idxs)
    else
        ss = string.(idxs)
        return lpad.(ss, maximum(length, ss))
    end
end

function _pretty_print_failures(@nospecialize(bitarray), failure_printer, negate=false; max_vals=10) # TODO(tpapalex): add 'wrap_negation' kwarg?

    # Finda all failing indices. 
    idxs = findall(x -> !isa(x, Bool) || (x == negate), bitarray)

    # If no falures, return no message
    if length(idxs) == 0
        return nothing
    end

    # Write failures into buffer:
    io = IOBuffer()

    # Write number of failures:
    print(io, "Failed ", length(idxs), " test", length(idxs) == 1 ? "" : "s")

    # Write dimension of bitarray:
    sz = size(bitarray)
    if length(sz) == 0
        print(io, ".")
    elseif length(sz) == 1
        print(io, " from length ", sz[1], " result.")
    else
        print(io, " from size ", join(sz, "×"), " result.")
    end

    # Figure out if we need to abbreviate to the top/bottom `max_vals` because there
    # are too many failures.
    if length(idxs) > max_vals
        abbrev_i = max_vals ÷ 2
        idxs = idxs[[1:abbrev_i; end-abbrev_i+1:end]]
    else
        abbrev_i = 0
    end

    # Get pretty-stringified indices
    str_idxs = _string_idxs_justify(idxs)

    for (i, idx) in enumerate(idxs)
        print(io, "\n    idx=[", str_idxs[i], "]: ")
        negate && print(io, "!(")
        failure_printer(io, idx)
        negate && print(io, ")")
        if !isa(bitarray[idx], Bool)
            printstyled(IOContext(io, :color=>true), " non-Boolean ===> ", bitarray[idx], color=:light_yellow)
        end
        if (i == abbrev_i) && (abbrev_i > 0)
            print(io, "\n    ⋮")
        end
    end
    seekstart(io)
    return String(take!(io))
end

# function _get_escaped_args(ex_args, kws) # TODO(tpapalex): should probably not have this throw errors, since we might want to use fall back if can't parse arguments
#     escaped_args = []
#     escaped_kwargs = []

#     # Keywords that occur before `;` # TODO(tpapalex): these are after `;` in examples tried? Comment mistake in Test?
#     for a in ex_args
#         if isa(a, Expr) && a.head === :kw
#             push!(escaped_kwargs, :(Expr(:kw, $(QuoteNode(a.args[1])),$(esc(a.args[2])))))
#         end
#     end

#     # Keywords that occur after ';' # TODO(tpapalex): these are before `;` in examples I tried? Comment mistake in Test?
#     parameters_expr = ex_args[1]
#     if isa(parameters_expr, Expr) && parameters_expr.head === :parameters
#         for a in parameters_expr.args
#             if isa(a, Expr) && a.head === :kw
#                 push!(escaped_kwargs, :(Expr(:kw, $(QuoteNode(a.args[1])), $(esc(a.args[2])))))
#             else
#                 error("invalid test macro call: cannot pretty with splat (...) arguments. Use `disable_pretty=true` to disable pretty printing.")
#             end
#         end
#     end

#     # Positional arguments
#     for a in ex_args
#         isa(a, Expr) && a.head in (:kw, :parameters) && continue
#         if isa(a, Expr) && a.head === :...
#             error("invalid test macro call: cannot pretty print with splat (...) arguments. Use `disable_pretty=true` to disable pretty printing.")
#         else
#             push!(escaped_args, esc(a))
#         end
#     end

#     # Add passed keywords
#     for kw in kws 
#         if !isa(kw, Expr) || kw.head !== :(=)
#             error("invalid test macro call: extra arguments must be keywords of the form kw=val")
#         end
#         push!(escaped_kwargs, :(Expr(:kw, $(QuoteNode(kw.args[1])), $(esc(kw.args[2])))))
#     end

#     return escaped_args, escaped_kwargs
# end

# # GENERAL UTILITIES

# function _get_preprocessed_expr(ex, kws...)

#     negate = false

#     # Extract initial negation
#     if isa(ex, Expr) && ex.head === :call && (ex.args[1] === :! || ex.args[1] === :.!)
#         negate = true
#         ex = ex.args[2]
#     end

#     # Normalize comparison calls with printable args to :comparison
#     if isa(ex, Expr) && 
#         ex.head === :call && 
#         length(ex.args) == 3 && 
#         length(kws) == 0 && # To push ≈/≉ to 
#         (ex.args[1] === :(==) || Base.operator_precedence(ex.args[1]) == COMPARISON_PREC) &&
#         !_is_splat(ex.args[2]) && 
#         !_is_splat(ex.args[3]) 
#         ex = Expr(:comparison, ex.args[2], ex.args[1], ex.args[3])

#     # Mark <: and >: as :comparison expressions
#     elseif isa(ex, Expr) && length(ex.args) == 2 &&
#         !_is_splat(ex.args[1]) && !_is_splat(ex.args[2]) &&
#         Base.operator_precedence(ex.head) == COMPARISON_PREC

#         ex = Expr(:comparison, ex.args[1], ex.head, ex.args[2])

#     # Mark .<: and .>: as :comparison expressions
#     elseif isa(ex, Expr) &&  ex.head === :call && length(ex.args) == 3 && 
#         !_is_splat(ex.args[2]) && !_is_splat(ex.args[3]) && 
#         (ex.args[1] === :.<: || ex.args[1] === :.>:)

#         ex = Expr(:comparison, ex.args[2], ex.args[1], ex.args[3])
#     end

#     return ex, negate
# end

# # COMPARISON EXPRESSION
# function _is_comparison(ex, kws)
#     return isa(ex, Expr) && 
#         ex.head === :comparison
# end

# function _result_comparison(ex, kws, source, negate=false)
#     if length(kws) > 0
#         error("invalid test macro call: extra arguments with comparison $(join(kws, " "))")
#     end

#     # Replace all operators with vectorized versions (without loss of generality?)
#     for i in 2:2:length(ex.args)
#         if !_is_vecop(ex.args[i])
#             ex.args[i] = Symbol(:., ex.args[i])
#         end
#     end

#     # Quote operators, escape arguments
#     escaped_args = [i % 2 == 1 ? esc(arg) : QuoteNode(arg) for (i, arg) in enumerate(ex.args)]

#     testret = quote
#         _eval_testall_comparison(
#             Expr(:comparison, $(escaped_args...)),
#             $(QuoteNode(source)),
#             $(QuoteNode(negate))
#         )
#     end

#     return testret
# end

# function _eval_testall_comparison(ex::Expr, source::LineNumberNode, negate::Bool=false)

#     if ex.head === :comparison # Most calls have been normalized to this form
#         terms = ex.args[1:2:end]
#         ops = ex.args[2:2:end]
#     else # ex.head === :call, only for .≈ and .≉ with extra kwargs
#         terms = ex.args[2:3]
#         ops = [ex.args[1]]
#     end

#     # Create a quoted expression for pretty-printing failures
#     quoted_ex = Expr(:comparison)
#     for i in eachindex(ops)
#         push!(quoted_ex.args, 0) # Placeholder, will be replaced with broadcast values later
#         push!(quoted_ex.args, Symbol(replace(string(ops[i]), r"^." => ""))) # Unvectorized operator
#     end
#     push!(quoted_ex.args, 0) # Placeholder
    
#     # Evaluate to get broadcasted bit array, and negate if necessary:
#     bitarray = eval(ex)

#     # Get broadcasted terms for accessing individual elements
#     broadcasted_terms = Base.broadcasted(tuple, terms...)

#     # Function to print the unvectorized expression with broadcasted terms spliced in.
#     failure_printer = (io, idx) -> begin
#         terms = broadcasted_terms[idx]
#         for i in eachindex(terms)
#             quoted_ex.args[2*i-1] = terms[i]
#         end
#         print(io, quoted_ex)
#     end

#     msg = _pretty_print_failures(bitarray, failure_printer, negate)

#     return Returned(msg === nothing, msg, source)
# end

# # ISAPPROX SPECIAL CASE (to support kwargs)
# function _is_approx_specialcase(ex, kws)
#     return isa(ex, Expr) && 
#         ex.head === :call && 
#         length(ex.args) >= 3 && 
#         !_is_splat(ex.args[2]) && 
#         !_is_splat(ex.args[3]) &&
#         ex.args[1] ∈ APPROX_OPS
# end

# function _result_approx_specialcase(ex, kws, source, negate=false)
#     # Replace operator with vectorized version
#     if !_is_vecop(ex.args[1])
#         ex.args[1] = Symbol(:., ex.args[1])
#     end
#     escaped_func = QuoteNode(ex.args[1])
#     escaped_args, escaped_kwargs = _get_escaped_args(ex.args[2:end], kws)
    
#     testret = quote
#         _eval_testall_comparison(
#             Expr(:call, $(escaped_func), $(escaped_args...), $(escaped_kwargs...)),
#             $(QuoteNode(source)),
#             $(QuoteNode(negate))
#         )
#     end

#     return testret
# end

# # DISPLAYED FUNCTION
# function _is_displayed_func(ex, kws=())
#     if !isa(ex, Expr) 
#         return false
#     elseif ex.head === :call && ex.args[1] ∈ DISPLAYABLE_FUNCS
#         return length(ex.args) >= 2 && all(a -> !_is_splat(a), ex.args[2:end])
#     elseif ex.head === :. && ex.args[1] ∈ DISPLAYABLE_FUNCS
#         return length(ex.args[2].args) >= 1 && all(a -> !_is_splat(a), ex.args[2].args)
#     else
#         return false
#     end
# end

# function _result_displayed_func(ex, kws, source, negate)
#     # Treat .≈ and .≉ as special case, because they are not functions that can be vectorized
#     if ex.head === :call && ex.args[1] ∈ (:.≈, :.≉)
#         escaped_args, escaped_kwargs = _get_escaped_args(ex.args[2:end], kws)
#     end
    
#     # Otherwise, we can just vectorize the call
#     ex = Expr(:., ex.args[1], Expr(:tuple, ex.args[2:end]...))
#     escaped_func = QuoteNode(ex.args[1])
#     escaped_args, escaped_kwargs = _get_escaped_args(ex.args[2].args, kws)

#     return quote
#         _eval_testall_displayed_func(
#             Expr(:., $(escaped_func), Expr(:tuple, $(escaped_args...), $(escaped_kwargs...))),
#             $(QuoteNode(source)),
#             $(QuoteNode(negate))
#         )
#     end
# end

# function _eval_testall_displayed_func(ex::Expr, source::LineNumberNode, negate::Bool=false)

#     # Extract the arguments which are presumably broadcasted
#     terms = [a for a in ex.args[2].args if !isa(a, Expr)]

#     # Create a quoted (unvectorized) expression for pretty-printing failures.
#     quoted_ex = Expr(:call, ex.args[1], zeros(Bool, length(terms))...) # args

#     # Evaluate to get broadcasted bit array, and negate if necessary:
#     bitarray = eval(ex)

#     # Get broadcasted terms for accessing individual elements
#     broadcasted_terms = Base.broadcasted(tuple, terms...)

#     # Function to print the unvectorized expression with broadcasted terms spliced in.
#     failure_printer = (io, idx) -> begin
#         terms = broadcasted_terms[idx]
#         for i in eachindex(terms)
#             quoted_ex.args[1+i] = terms[i]
#         end
#         print(io, quoted_ex)
#     end

#     msg = _pretty_print_failures(bitarray, failure_printer, negate)

#     return Returned(msg === nothing, msg, source)
# end

# function _is_anonymous_map(ex, kws)
#     return isa(ex, Expr) && ex.head === :->
# end

# function _result_anonymous_map(ex, kws, source, negate)
#     # Check that there's an extra keyword argument, for the second argument of map
#     if length(kws) == 0
#         error("invalid test macro call: no expression given for mapping")
#     elseif length(kws) > 1
#         error("invalid test macro call: unused arguments $(join(kws, " "))")
#     end

#     # Create a mapping expression
#     return quote
#         _eval_testall_map(
#             Expr(:call, :map, $(esc(ex)), $(esc(kws[1]))),
#             $(QuoteNode(source)), 
#             $(QuoteNode(negate))
#         )
#     end
# end

# function _eval_testall_map(ex::Expr, source::LineNumberNode, negate::Bool=false)

#     terms = ex.args[3]
    
#     # Evaluate to get broadcasted bit array, and negate if necessary:
#     bitarray = eval(ex)

#     # Function to print the unvectorized expression with broadcasted terms spliced in.
#     failure_printer = (io, idx) -> begin
#         print(io, "f(", terms[idx], ")")
#     end

#     msg = _pretty_print_failures(bitarray, failure_printer, negate)

#     return Returned(msg === nothing, msg, source)
# end

# # FALLBACK 
# function _result_fallback(ex, kws, source)
#     if length(kws) > 0
#         error("invalid test macro call: unused arguments $(join(kws, " "))")
#     end
#     return :(
#         _eval_testall_fallback(
#             $(esc(ex)),
#             $(QuoteNode(source))
#         )
#     )
# end

# function _eval_testall_fallback(@nospecialize(bitarray), source::LineNumberNode)
#     msg = _pretty_print_failures(bitarray, (io, idx) -> nothing, false)
#     return Returned(msg === nothing, msg, source)
# end


# # Finally
# function get_test_all_result(ex, kws, source, quoted=false)

#     orig_ex = ex
#     ex, negate = _get_preprocessed_expr(ex, kws...)

#     if _is_comparison(ex, kws)
#         #@info "comparison"
#         testret = _result_comparison(ex, kws, source, negate)
#         quoted_ex = Expr(:call, :all, ex)
#     elseif _is_approx_specialcase(ex, kws)
#         #@info "special case ≈ or ≉"
#         testret = _result_approx_specialcase(ex, kws, source, negate)
#         quoted_ex = ex
#     elseif _is_displayed_func(ex, kws)
#         #@info "displayed func"
#         testret = _result_displayed_func(ex, kws, source, negate)
#         quoted_ex = ex
#     elseif _is_anonymous_map(ex, kws)
#         #@info "mapped anonymous"
#         testret = _result_anonymous_map(ex, kws, source, negate)
#         quoted_ex = ex
#     else 
#         #@info "fallback"
#         testret = _result_fallback(orig_ex, kws, source)
#         quoted_ex = ex
#     end

#     if negate
#         quoted_ex = Expr(:call, :.!, quoted_ex)
#     end

#     result = quote
#         try
#             $testret
#         catch _e
#             _e isa InterruptException && rethrow()
#             Threw(_e, Base.current_exceptions(), $(QuoteNode(source)))
#         end
#     end

#     result, quoted_ex
# end

# """
#     @test_all ex

# Test that all(ex) true.
# """
# macro test_all(ex, kws...) #TODO(tpapalex): add 'quoted' argument
#     kws, broken, skip = extract_broken_skip_keywords(kws...)
#     kws, quoted = extract_keyword(:quoted, kws...)

#     result, quoted_ex = get_test_all_result(ex, kws, __source__, quoted)
#     quoted_ex = Expr(:inert, quoted_ex)
#     quote 
#         if $(length(skip) > 0 && esc(skip[1]))
#             record(get_testset(), Broken(:skipped, $quoted_ex))
#         else
#             let _do = $(length(broken) > 0 && esc(broken[1])) ? do_broken_test : do_test
#                 _do($result, $quoted_ex)
#             end
#         end
#     end
# end

# function _recurse_stringify_logical(ex, toplevel=true)
#     if _is_logical_binary(ex)
#         lhs = _recurse_stringify_logical(ex.args[1], false)
#         rhs = _recurse_stringify_logical(ex.args[2], false)
#         return lhs * " " * string(ex.head) * " " * rhs
#     elseif _is_logical_unary(ex)
#         arg = _recurse_stringify_logical(ex.args[2], false)
#         return string(ex.args[1]) * arg
#     elseif !isa(ex, Expr)
#         return string(ex)
#     elseif (ex.head === :call || ex.head === :.) && Base.operator_precedence(ex.args[1]) == 0
#         return string(ex)
#     elseif toplevel
#         return string(ex)
#     else
#         return "(" * string(ex) * ")"
#     end
# end

# function _recurse_vectorize_logical!(ex)
#     if _is_logical_binary(ex)
#         if !_is_vecop(ex.head)
#             ex.head = Symbol(:., ex.head)
#         end
#         _recurse_vectorize_logical!(ex.args[1])
#         _recurse_vectorize_logical!(ex.args[2])
#     elseif _is_logical_unary(ex)
#         if !_is_vecop(ex.args[1])
#             ex.args[1] = Symbol(:., ex.args[1])
#         end
#         _recurse_vectorize_logical!(ex.args[2])
#     end
#     return ex
# end

# function _recurse_vectorize!(ex, kws = ())
#     if _is_logical_binary(ex)
#         if !_is_vecop(ex.head) 
#             ex.head = Symbol(:., ex.head)
#         end
#         _recurse_vectorize!(ex.args[1])
#         _recurse_vectorize!(ex.args[2])
#     elseif _is_logical_unary(ex)
#         if !_is_vecop(ex.args[1])
#             ex.args[1] = Symbol(:., ex.args[1])
#         end
#         _recurse_vectorize!(ex.args[2])
#     elseif _is_comparison(ex, kws)
#         for i in 2:2:length(ex.args)
#             if !_is_vecop(ex.args[i])
#                 ex.args[i] = Symbol(:., ex.args[i])
#             end
#         end
#     elseif _is_approx_specialcase(ex, kws)
#         if !_is_vecop(ex.args[1])
#             ex.args[1] = Symbol(:., ex.args[1])
#         end
#     elseif _is_displayed_func(ex, kw)
#         if ex.head === :call && ex.args[1] ∉ APPROX_OPS # TODO(tpapalex) The second predicate I think is unnecessary


#     elseif _is_displayed_func(ex, kws)
#         #@info "displayed func"
#         testret = _result_displayed_func(ex, kws, source, negate)
#         quoted_ex = ex
#     elseif _is_anonymous_map(ex, kws)
#         #@info "mapped anonymous"
#         testret = _result_anonymous_map(ex, kws, source, negate)
#         quoted_ex = ex
#     else 
#         #@info "fallback"
#         testret = _result_fallback(orig_ex, kws, source)
#         quoted_ex = ex
#     end
# end

