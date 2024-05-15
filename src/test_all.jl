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

# A reference value for the max number of failures to print in a @testall failure.
const PRINT_FAILURES_MAX = Ref{Int64}(10)

"""
    set_max_print_failures(n::Union{Integer,Nothing}=10)

Set the number of individual failures that will be printed in a failing 
[`@test_all`](@ref) test. The failure summary will still show the total number
of failed tests, but only the first/last `n` will be individually printed. If 
`n === nothing`, all failures will be printed. 

```jldoctest; filter = r"(\\e\\[\\d+m|\\s+)", setup = (using TestMacroExtensions: set_max_print_failures)
julia> set_max_print_failures(2);

julia> @test_all 1:10 .< 0
Test Failed at none:1
  Expression: all(1:10 .< 0)
   Evaluated: false
    Argument: 10-element BitVector, 10 failures: 
              [ 1]: 1 < 0 ===> false
              ⋮
              [10]: 10 < 0 ===> false

julia> set_max_print_failures(0);

julia> @test_all 1:100 .< 0
Test Failed at none:1
  Expression: all(1:100 .< 0)
   Evaluated: false
    Argument: 100-element BitVector, 100 failures
```
"""
function set_max_print_failures(n::Integer = 10)
    @assert n >= 0 "Max number of failures to print must be non-negative."
    PRINT_FAILURES_MAX[] = n
end
function set_max_print_failures(::Nothing)
    PRINT_FAILURES_MAX[] = typemax(Int64)
    return
end

get_max_print_failures() = PRINT_FAILURES_MAX[]

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


# Preprocess `@testall` expressions of function calls with trailing keyword arguments, 
# so that e.g. `@testall a .≈ b atol=ε` means `@testall .≈(a, b, atol=ε)`.
# If `ex` is a negation expression (either a `!` or `.!` call), keyword arguments will 
# be added to the inner expression, so that `@testall .!(a .≈ b) atol=ε` means 
# `@testall .!(.≈(a, b, atol=ε))`.
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
function preprocess_test_all(ex)

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
# expressions with comparison ops are chanegd to :comparison in preprocess_test_all()
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

#################### Pretty-printing utilities ###################
# An internal, IO-like object, used to dynamically produce a `Format.FormatExpr`-like 
# string representation of the unvectorized @testall expression, used to pretty print
# individual failures.
struct Formatter
    ioc::IOContext{IOBuffer}
    parens::Bool
    Formatter(parens::Bool=true) = new(failure_ioc(), parens)
end

function stringify!(fmt::Formatter)
    str = stringify!(fmt.ioc)
    if fmt.parens 
        return "($s)"
    else
        return str
    end
end

function Base.print(fmt::Formatter, i::Integer)
    printstyled(fmt.ioc, "{$i:s}", color=get_color(i))
end

function Base.print(fmt::Formatter, strs::AbstractString...)
    print(fmt.ioc, strs...)
end

function Base.print(fmt::Formatter, innerfmt::Formatter)
    print(fmt.ioc, stringify!(innerfmt))
    close(innerfmt.ioc)
end

function Base.print(fmt::Formatter, s)
    print(fmt.ioc, string(s))
end

# Commonly used indentation levels for pretty printing
const _INDENT_TYPEERROR = "            ";
const _INDENT_EVALUATED = "              ";

# Stringifies indices returned by findall() for pretty printing
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

# Prints the individual failures in a @testall test, given the indices of the failures
# and a function to print an individual failure.
function print_failures(
        io::IO, 
        idxs::AbstractVector,
        print_idx_failure, 
        prefix=""
    )

    # Depending on PRINT_FAILURES_MAX, filter the indices to some subset.
    PRINT_FAILURES_MAX[] == 0 && return
    if length(idxs) > PRINT_FAILURES_MAX[]
        i_dots = (PRINT_FAILURES_MAX[] ÷ 2)
        if PRINT_FAILURES_MAX[] % 2 == 1
            i_dots = i_dots + 1
            idxs = idxs[[1:i_dots; end-i_dots+2:end]]
        else
            idxs = idxs[[1:i_dots; end-i_dots+1:end]]
        end
    else
        i_dots = 0
    end

    # Pretty print the failures with the provided function
    str_idxs = stringify_idxs(idxs)
    for (i, idx) in enumerate(idxs)
        print(io, "\n", prefix, "[", str_idxs[i], "]: ")
        print_idx_failure(io, idx)
        if i == i_dots
            print(io, "\n", prefix, "⋮")
        end
    end

    return
end

# An internal exception type, thrown (and later caught by the `Test` infrastructure), when 
# non-Boolean, non-Missing values are encountered in an evaluated `@testall` expression. 
# It's constructed directly from the result of evaluting the expression, and pretty-prints
# the non-Boolean values.
struct NonBoolTypeError <: Exception
    msg::String

    # Constructor when the evaluated expression is a vector or array: pretty-print the
    # the non-Boolean indices.
    function NonBoolTypeError(evaled::AbstractArray) 
        io = failure_ioc(typeinfo = eltype(evaled))

        # First print the summary:
        n_nonbool = sum(x -> !isa(x, Bool), evaled, init=0)
        summary(io, evaled)
        print(io, " with ", n_nonbool, " non-Boolean value", n_nonbool == 1 ? "" : "s")

        if PRINT_FAILURES_MAX[] == 0
            return new(stringify!(io))
        end

        # Avoid allocating vector with `findall()` if only a few failures need to be
        # printed.
        print(io, ":")
        if PRINT_FAILURES_MAX[] == 1
            idxs = [findfirst(x -> !isa(x, Bool), evaled)]
        else
            idxs = findall(x -> !isa(x, Bool), evaled)
        end
        
        # Get the pretty-printing function for each index
        print_idx_failure = (io, idx) -> begin
            print(io, evaled[idx])
            printstyled(io, " ===> ", typeof(evaled[idx]), color=:light_yellow)
        end
        print_failures(io, idxs, print_idx_failure, _INDENT_TYPEERROR)
    
        return new(stringify!(io))
    end

    function NonBoolTypeError(evaled)
        io = failure_ioc(typeinfo = typeof(evaled))
        print(io, evaled)
        printstyled(io, " ===> ", typeof(evaled), color=:light_yellow)
        return new(stringify!(io))
    end
end

function Base.showerror(io::IO, err::NonBoolTypeError)
    print(io, " TypeError: non-boolean used in boolean context")
    if err.msg != ""
        print(io, "\n  Argument: ", err.msg)
    end
end

@nospecialize

#################### Escaping arguments ###################
# Internal functions to process an expression `ex` for use in `@test_all`. It 
# recursively modifies subexpressions that will be broadcast for pretty-printing by
# by (i) escaping them and pushing them to `escargs`, and (ii) replacing them with
# references to `ARG[i]` in the `ex` itself. It does the same with keyword arguments
# but wraps them in `Ref()` before escaping. It also recursively produces a 
# `Formatter` object for pretty-printing the broadcasted arguments.
function recurse_process!(ex, escargs::Vector{Expr}; outmost::Bool=true)
    ex = preprocess_test_all(ex)
    if isexpr(ex, :kw)
        return recurse_process_keyword!(ex, escargs, outmost=outmost)
    elseif isvecnegationexpr(ex)
        return recurse_process_negation!(ex, escargs, outmost=outmost)
    elseif isveclogicalexpr(ex)
        return recurse_process_logical!(ex, escargs, outmost=outmost)
    elseif isveccomparisonexpr(ex)
        return recurse_process_comparison!(ex, escargs, outmost=outmost)
    elseif isvecapproxexpr(ex)
        return recurse_process_approx!(ex, escargs, outmost=outmost)
    elseif isvecdisplayexpr(ex)
        return recurse_process_displayfunc!(ex, escargs, outmost=outmost)
    else
        return recurse_process_basecase!(ex, escargs, outmost=outmost)
    end
end

function recurse_process_basecase!(ex, escargs::Vector{Expr}; outmost::Bool=true)
    # Escape entire expression to args
    push!(escargs, esc(ex))

    # Override parentheses if expression doesn't need them
    addparens = !outmost
    if !isa(ex, Expr) || 
        ex.head ∈ (:vect, :tuple, :hcat, :vcat, :ref) || 
        (isexpr(ex, (:call, :.)) && Base.operator_precedence(ex.args[1]) == 0)

        addparens = false
    end

    # Create a simple format string
    fmt_expr = Formatter(addparens)
    fmt_term = Formatter(addparens)
    print(fmt_expr, length(escargs))
    print(fmt_term, length(escargs))

    # Replace the expression with ARG[i]
    ex = :(ARG[$(length(escargs))])
    return ex, fmt_expr, fmt_term
end

function recurse_process_keyword!(ex::Expr, escargs::Vector{Expr}; outmost::Bool=true)
    # Keyword argument values are pushed to escaped `args`, but should be
    # wrapped in a Ref() call to avoid broadcasting.
    push!(escargs, esc(Expr(:call, :Ref, ex.args[2])))

    fmt_expr = Formatter(false)
    print(fmt_expr, ex.args[1])
    print(fmt_expr, "=")
    print(fmt_expr, length(escargs))

    fmt_term = Formatter(false)
    print(fmt_term, ex.args[1])
    print(fmt_term, "=")
    print(fmt_term, length(escargs))

    # Replace keyword argument with ARG[i].x to un-Ref() in evaluation
    ex.args[2] = :(ARG[$(length(escargs))].x)
    
    return ex, fmt_expr, fmt_term
end

function recurse_process_negation!(ex::Expr, escargs::Vector{Expr}; outmost::Bool=true)
    # Recursively update the second argument
    ex.args[2], fmt_expr_arg, fmt_term_arg = recurse_process!(ex.args[2], escargs)

    # Never requires parentheses outside the negation
    fmt_expr = Formatter(false)
    print(fmt_expr, ex.args[1])
    print(fmt_expr, fmt_expr_arg)
    fmt_term = Formatter(false)
    print(fmt_term, "!")
    print(fmt_term, fmt_term_arg)

    # Escape negation operator
    ex.args[1] = esc(ex.args[1])

    return ex, fmt_expr, fmt_term
end

function recurse_process_logical!(ex::Expr, escargs::Vector{Expr}; outmost::Bool=true)
    fmt_expr = Formatter(!outmost)
    fmt_term = Formatter(!outmost)

    for i in 2:length(ex.args)
        # Recursively update the two arguments. If a sub-expression is also logical, 
        # there is no need to parenthesize so consider it `outmost=true`.
        ex.args[i], fmt_expr_arg, fmt_term_arg = recurse_process!(
            ex.args[i], escargs, outmost=isveclogicalexpr(ex.args[i]))

        # Unless it's the first argument, print the operator
        i == 2 || print(fmt_expr, " ", string(ex.args[1]), " ")
        i == 2 || print(fmt_term, " ", string_unvec(ex.args[1]), " ")
        print(fmt_expr, fmt_expr_arg)
        print(fmt_term, fmt_term_arg)
    end

    # Escape the operator
    ex.args[1] = esc(ex.args[1])

    return ex, fmt_expr, fmt_term
end

function recurse_process_comparison!(ex::Expr, escargs::Vector{Expr}; outmost::Bool=false)
    fmt_expr = Formatter(!outmost)
    fmt_term = Formatter(!outmost)
    # Recursively update every other argument (i.e. the terms), and 
    # escape the operators.
    for i in eachindex(ex.args)
        if i % 2 == 1 # Term
            ex.args[i], fmt_expr_arg, fmt_term_arg = recurse_process!(ex.args[i], escargs)
            print(fmt_expr, fmt_expr_arg)
            print(fmt_term, fmt_term_arg)
        else # Operator
            print(fmt_expr, " ", string(ex.args[i]), " ")
            print(fmt_term, " ", string_unvec(ex.args[i]), " ")
            ex.args[i] = esc(ex.args[i])
        end
    end
    
    return ex, fmt_expr, fmt_term
end

function recurse_process_approx!(ex::Expr, escargs::Vector{Expr}; outmost::Bool=false)
    # Recursively update both positional arguments
    ex.args[2], fmt_expr_arg1, fmt_term_arg1 = recurse_process!(ex.args[2], escargs)
    ex.args[3], fmt_expr_arg2, fmt_term_arg2 = recurse_process!(ex.args[3], escargs)

    # If outmost, format as comparison, otherwise as a function call
    fmt_expr = Formatter(false)
    fmt_term = Formatter(false)
    if outmost
        print(fmt_expr, fmt_expr_arg1)
        print(fmt_expr, " ", string(ex.args[1]), " ")
        print(fmt_expr, fmt_expr_arg2)
        print(fmt_expr, " (")

        print(fmt_term, fmt_term_arg1)
        print(fmt_term, " ", string_unvec(ex.args[1]), " ")
        print(fmt_term, fmt_term_arg2)
        print(fmt_term, " (")
    else
        print(fmt_expr, string(ex.args[1]))
        print(fmt_expr, "(")
        print(fmt_expr, fmt_expr_arg1)
        print(fmt_expr, ", ")
        print(fmt_expr, fmt_expr_arg2)
        print(fmt_expr, ", ")

        print(fmt_term, string_unvec(ex.args[1]))
        print(fmt_term, "(")
        print(fmt_term, fmt_term_arg1)
        print(fmt_term, ", ")
        print(fmt_term, fmt_term_arg2)
        print(fmt_term, ", ")
    end

    # Recursively update with keyword arguments
    for i in 4:length(ex.args)
        ex.args[i], fmt_expr_arg, fmt_term_arg = recurse_process!(ex.args[i], escargs)
        print(fmt_expr, fmt_expr_arg)
        print(fmt_term, fmt_term_arg)
        i == length(ex.args) || print(fmt_expr, ", ")
        i == length(ex.args) || print(fmt_term, ", ")
    end
    print(fmt_expr, ")")
    print(fmt_term, ")")

    # Escape function
    ex.args[1] = esc(ex.args[1])

    return ex, fmt_expr, fmt_term
end

function recurse_process_displayfunc!(ex::Expr, escargs::Vector{Expr}; outmost::Bool=false)
    ex_args = ex.args[2].args

    fmt_expr = Formatter(false)
    fmt_term = Formatter(false)

    print(fmt_expr, string(ex.args[1]), ".(")
    print(fmt_term, string(ex.args[1]), "(")
    for i in eachindex(ex_args)
        ex_args[i], fmt_expr_arg, fmt_term_arg = recurse_process!(ex_args[i], escargs)
        print(fmt_expr, fmt_expr_arg)
        print(fmt_term, fmt_term_arg)
        i == length(ex_args) || print(fmt_expr, ", ")
        i == length(ex_args) || print(fmt_term, ", ")
    end
    print(fmt_expr, ")")
    print(fmt_term, ")")

    # Escape the function name
    ex.args[1] = esc(ex.args[1])

    return ex, fmt_expr, fmt_term
end

# Internal function used at `@test_all` runtime to get a `Returned` `Test.ExecutionResult`
# with nice failure messages. Used in the code generated by `get_test_all_result()` at
# compile time.
# - `evaled`: the result of evaluating the processed expression returned by 
#   `recurse_process!` (the one with references to `ARG[i]`) 
# - `terms`: a vector of all terms that were broadcasted to produce `evaled`, which can 
#    be used to produce individual failure messages. It is the result of evaluating and 
#    concatenating the escaped arguments extracted by `recurse_process!()` into a vector.
# - `fmt_term`: a FormatExpr-like string for pretty-printing an individual failure. It is the 
#    result of `stringify!(f)` on the `Formatter` returned by `recurse_process!()`.
function eval_test_all(
        @nospecialize(evaled),
        @nospecialize(terms),
        fmt::String, 
        source::LineNumberNode)

    # Try to evaluate all(). If `evaled === missing`, this would cause as a MethodError
    # for iterate(missing), but we just ignore it and process along with other cases below.
    # If a non-Bool TypeError, catch it and throw an internal `NonBoolTypeError` with 
    # a pretty-printed message. If other error, rethrow. Either way, it will be caught
    # and converted to a `Threw` execution result in the code generated by
    # `get_test_all_result()`.
    res = try 
        all(evaled)
    catch _e
        if evaled === missing
            missing
        elseif isa(_e, TypeError) && _e.expected === Bool
            throw(NonBoolTypeError(evaled))
        else
            rethrow(_e)
        end
    end

    # If all() returns true, no need for pretty printing anything. 
    if res === true
        return Returned(res, nothing, source)
    end

    # Catch invalid return values from all(). Should never happen, unless the user
    # has overridden all(). 
    @assert res isa Union{Bool,Missing} "all(ex) returned $(typeof(res)), not missing or false"

    # Broadcast the input terms and compile the formatting expression for pretty printing
    broadcasted_terms = Base.broadcasted(tuple, terms...)
    fmt = FormatExpr(fmt)

    # Print the evaluated result:
    io = failure_ioc()
    print(io, res)
    print(io, "\n    Argument: ")

    # Print a nice message. If the evaluated result (evaled) is a Bool or Missing (not 
    # a vector or array), print a simple message:
    if isa(evaled, Union{Bool,Missing})
        terms = repr.(first(broadcasted_terms))
        printfmt(io, fmt, terms...)
        printstyled(io, " ===> ", evaled, color=:light_yellow)

    # Otherwise, use pretty-printing with indices. Note that we are guaranteed that 
    # eltype(evaled) <: Union{Missing,Bool}. 
    else
        # First, print type of inner expression and number of false/missing values
        summary(io, evaled)
        n_missing = sum(x -> ismissing(x), evaled)
        n_false = sum(x -> !x, skipmissing(evaled), init=0)
        print(io, ", ")
        if n_missing > 0
            print(io, n_missing, " missing")
            n_false == 0 || print(io, " and ")
        end
        if n_false > 0
            print(io, n_false, " failure", n_false == 1 ? "" : "s")
        end

        # Avoid allocating with `findall()` if only a few failures need to be printed.
        if PRINT_FAILURES_MAX[] == 0
            return Returned(false, stringify!(io), source)
        end
        idxs = try 
            if PRINT_FAILURES_MAX[] == 1
                [findfirst(x -> x !== true, evaled)]
            else
                findall(x -> x !== true, evaled)
            end
        catch
            return Returned(false, stringify!(io), source)
        end
        print(io, ": ")

        print_idx_message = (io, idx) -> begin
            printfmt(io, fmt, repr.(broadcasted_terms[idx])...)
            printstyled(io, " ===> ", evaled[idx], color=:light_yellow)
        end
        print_failures(io, idxs, print_idx_message, _INDENT_EVALUATED)
    end

    return Returned(false, stringify!(io), source)
end

# Internal function used at compile time to generate code that will produce the final 
# `@test_all` `Test.ExecutionResult`. Wraps `eval_test_all()` in a try/catch block 
# so that exceptions can be returned as `Test.Threw` result.
function get_test_all_result(ex, source)
    escaped_args = Expr[]
    mod_ex, fmt_expr, fmt_term = recurse_process!(ex, escaped_args; outmost=true)

    # Get color-coded expression by passing the unescaped arguments:
    fmt_expr = FormatExpr("all(" * stringify!(fmt_expr) * ")")
    str_args = map(a -> sprint(Base.show_unquoted, a.args[1]), escaped_args)
    str_ex = sprint(printfmt, fmt_expr, str_args..., context = :color => true)

    result = quote
        try
            let ARG = Any[$(escaped_args...)] # Use `let` for local scope on `ARG`
                eval_test_all(
                    $(mod_ex), 
                    ARG, 
                    $(stringify!(fmt_term)),
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

"""
    @test_all ex
    @test_all f(args...) key=val ...

Performs the same test as `@test all(ex)`, but without short-circuiting. This allows 
more informative failure messages to be printed for each element of `ex` that was `false`.

# Examples
```jldoctest; filter = r"(\\e\\[\\d+m|\\s+|ERROR.*)"
julia> @test_all [1.0, 2.0] .== 1:2
Test Passed

julia> @test_all [1, 2, 3] .< 2
Test Failed at none:1
  Expression: all([1, 2, 3] .< 2)
   Evaluated: false
    Argument: 3-element BitVector, 2 failures:
              [2]: 2 < 2 ===> false
              [3]: 3 < 2 ===> false
```

The form `@test_all f(args...) key=val...` is equivalent to writing 
`@test_all f(args...; key=val...)`. This allows similar behaviour as 
`@test` when using infix syntax such as approximate comparisons:

```jldoctest; filter = r"(\\e\\[\\d+m|\\s+|ERROR.*)"
julia> v = [0.99, 1.0, 1.01];

julia> @test_all v .≈ 1 atol=0.1
Test Passed
```
As with `@test`, it is an error to supply more than one expression unless 
the first is a call (possibly vectorized with `.` suffix) and the rest are 
assignments (`k=v`).

Keywords `broken` and `skip` function as in `@test`:
```jldoctest; filter = r"(\\e\\[\\d+m|\\s+|ERROR.*)"
julia> @test_all [1, 2] .< 2 broken=true
Test Broken
  Expression: all([1, 2] .< 2)

julia> @test_all [1, 2, 3] .< 2 skip=true
Test Broken
  Skipped: all([1, 2, 3] .< 2)
```
"""
macro test_all(ex, kws...)
    # Collect the broken/skip keywords and remove them from the rest of keywords:
    kws, broken, skip = extract_broken_skip_keywords(kws...)

    # Add keywords to the expression
    ex = pushkeywords!(ex, kws...)

    # Generate code to evaluate expression and return a `Test.ExecutionResult`
    result, str_ex = get_test_all_result(ex, __source__)

    result = quote
        if $(length(skip) > 0 && esc(skip[1]))
            record(get_testset(), Broken(:skipped, $str_ex))
        else
            let _do = $(length(broken) > 0 && esc(broken[1])) ? do_broken_test : do_test
                _do($result, $str_ex)
            end
        end
    end
    return result
end
