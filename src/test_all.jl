const DISPLAYABLE_FUNCS = Set{Symbol}([
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
    :isfinite,
    :iseven, 
    :isodd, 
    :isreal,
    :isa, 
    :ifelse,
    :≈, 
    :≉,
])
const COMPARISON_PREC = Base.operator_precedence(:(==)) 
const OPS_LOGICAL = (:.&, :.|, :.⊻, :.⊽)
const OPS_APPROX = (:.≈, :.≉)  

@nospecialize

#################### Pre-processing expressions ###################
# Functions to preprocess expressions for `@test_all` macro.

isvecoperator(x::Symbol) = Meta.isoperator(x) && first(string(x)) == '.'
function unvecoperator_string(x::Symbol)
    sx = string(x)
    if startswith(sx, ".")
        return sx[2:end]
    else
        return sx
    end
end

# Used only on :call or :. args to check if args expression is displayable:
isdisplayableargexpr(ex) = !isexpr(ex, (:kw, :parameters, :...))

# Preprocess `@test_all` expressions of function calls with trailing keyword arguments, 
# so that e.g. `@test_all a .≈ b atol=ε` means `@test_all .≈(a, b, atol=ε)`.
# If `ex` is a negation expression (either a `!` or `.!` call), keyword arguments will 
# be added to the inner expression, so that `@test_all .!(a .≈ b) atol=ε` means 
# `@test_all .!(.≈(a, b, atol=ε))`.
pushkeywords!(ex) = ex

function pushkeywords!(ex, kws...)
    # Recursively dive through negations
    orig_ex = ex
    if isexpr(ex, :call, 2) && (ex.args[1] === :! || ex.args[1] === :.!)
        ex = ex.args[2]
    end

    # Check that inner expression is a :call or :.
    if !isexpr(ex, (:call, :.))
        error("invalid test macro call: @test_all $ex does not accept keyword arguments")
    end

    # Push keywords to the end of arguments as keyword expressions
    args = ex.head === :call ? ex.args : ex.args[2].args
    for kw in kws
        if isexpr(kw, :(=))
            kw.head = :kw
            push!(args, kw)
        else
            error("invalid test macro call: $kw is not valid keyword syntax")
        end
    end

    return orig_ex
end

# An internal function, recursively called on the @test_all expression to normalize it.
function preprocess_test_all(ex)

    # Normalize dot comparison operator calls to :comparison expressions. 
    # Do not if there are extra arguments or there are splats.
    if Meta.isexpr(ex, :call, 3) && 
        isvecoperator(ex.args[1]::Symbol) && 
        Base.operator_precedence(ex.args[1]) == COMPARISON_PREC &&
        isdisplayableargexpr(ex.args[2]) && 
        isdisplayableargexpr(ex.args[3])
        
        ex = Expr(:comparison, ex.args[2], ex.args[1], ex.args[3])

    # For displayable :call or :. expressions, push :kw expressions in :parameters to 
    # end of arguments. 
    elseif isexpr(ex, (:call, :.)) && 
        ((ex.args[1]::Symbol ∈ OPS_APPROX) || (ex.args[1]::Symbol ∈ DISPLAYABLE_FUNCS))

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
# certain groups that will be displayed differently by `@test_all`.

# NOT expressions, e.g. !a
isvecnegationexpr(ex) = isexpr(ex, :call, 2) && ex.args[1]::Symbol === :.!

# Vectorized AND or OR expressions, e.g, a .&& b, a .|| c
isveclogicalexpr(ex) = isexpr(ex, :call) && ex.args[1]::Symbol ∈ OPS_LOGICAL

# Vectorized comparison expressions, e.g. a .== b, a .<= b .> c, a .≈ B. Note that :call
# expressions with comparison ops are changed to :comparison in preprocess_test_all().
function isveccomparisonexpr(ex)
    if isexpr(ex, :comparison)
        for i in 2:2:length(ex.args)
            if !isvecoperator(ex.args[i]::Symbol)
                return false
            end
        end
        return true
    else
        return false
    end
end

# Special case of .≈ or .≉ calls with kws (and no splats), for formatting as comparison
function isvecapproxexpr(ex)
    return isexpr(ex, :call) && 
        ex.args[1]::Symbol ∈ OPS_APPROX &&
        isdisplayableargexpr(ex.args[2]) && 
        isdisplayableargexpr(ex.args[3])        
end

# Vectorized :. call to displayable function (with no splats)
function isvecdisplayexpr(ex)
    if isexpr(ex, :., 2) && 
        ex.args[1]::Symbol ∈ DISPLAYABLE_FUNCS &&
        isexpr(ex.args[2], :tuple) 

        for a in ex.args[2].args
            if isexpr(a, :...)
                return false
            end
        end
        return true
    else
        return false
    end
end

#################### Pretty-printing utilities ###################
# An internal, IO-like object, used to dynamically produce a `Format.FormatExpr`-like 
# string representation of the unvectorized @test_all expression.
struct Formatter
    ioc::IOContext{IOBuffer}
    parens::Bool
    function Formatter(parens::Bool) 
        ioc = failure_ioc()
        parens && print(ioc, "(")
        return new(ioc, parens)
    end
end

function stringify!(fmt::Formatter)
    fmt.parens && print(fmt.ioc, ")")
    return stringify!(fmt.ioc)
end

function Base.print(fmt::Formatter, strs::AbstractString...; i::Integer=0)
    if i == 0
        print(fmt.ioc, strs...)
    else
        printstyled(fmt.ioc, strs..., color=get_color(i))
    end
end

function Base.print(fmt::Formatter, innerfmt::Formatter)
    print(fmt.ioc, stringify!(innerfmt))
    close(innerfmt.ioc)
end

function Base.print(fmt::Formatter, s; i::Integer=0)
    print(fmt, string(s); i=i)
end

# Matches indenteation of TypeError in @test_all error message
const _INDENT_TYPEERROR = "            ";

# Matches indenteation of "Evaluated:" expression in @test_all fail message
const _INDENT_EVALUATED = "              ";

# Stringifies indices returned by findall() for pretty printing
function stringify_idxs(idxs::Vector{CartesianIndex{D}}) where D
    maxlens = [maximum(idx -> ndigits(idx.I[d]), idxs) for d in 1:D]
    to_str = idx -> join(map(i -> lpad(idx.I[i], maxlens[i]), 1:D), ",")
    return map(to_str, idxs)
end
function stringify_idxs(idxs::AbstractVector{<:Integer})
    maxlen = maximum(ndigits, idxs)
    return lpad.(string.(idxs), maxlen)
end
function stringify_idxs(idxs::AbstractVector)
    ss = string.(idxs)
    maxlen = maximum(length, ss)
    return lpad.(ss, maxlen)
end

# Prints the individual failures in a @test_all test, given the indices of the failures
# and a function to print an individual failure.
function print_failures(
        io::IO, 
        idxs::AbstractVector,
        print_idx_failure, 
        prefix=""
    )

    # Depending on MAX_PRINT_FAILURES, filter the failiing indices to some subset.
    MAX_PRINT_FAILURES[] == 0 && return
    if length(idxs) > MAX_PRINT_FAILURES[]
        i_dots = (MAX_PRINT_FAILURES[] ÷ 2)
        if MAX_PRINT_FAILURES[] % 2 == 1
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
# non-Boolean, non-Missing values are encountered in an evaluated `@test_all` expression. 
# It's constructed directly from the result of evaluting the expression, and pretty-prints
# the non-Boolean values.
struct NonBoolTypeError <: Exception
    msg::String

    # Constructor when the evaluated expression is a vector or array: pretty-print the
    # the non-Boolean indices.
    function NonBoolTypeError(evaled::AbstractArray) 
        io = failure_ioc(typeinfo = eltype(evaled))

        # First print the summary:
        n_nonbool = sum(x -> x !== true && x !== false && x !== missing, evaled, init=0)
        summary(io, evaled)
        print(io, " with ", n_nonbool, " non-Boolean value", n_nonbool == 1 ? "" : "s")

        if MAX_PRINT_FAILURES[] == 0
            return new(stringify!(io))
        end

        # Avoid allocating vector with `findall()` if only a few failures need to be
        # printed.
        print(io, ":")
        if MAX_PRINT_FAILURES[] == 1
            idxs = [findfirst(x -> x !== true && x !== false && x !== missing, evaled)]
        else
            idxs = findall(x -> x !== true && x !== false && x !== missing, evaled)
        end
        
        # Get the pretty-printing function for each index
        print_idx_failure = (io, idx) -> begin
            if evaled[idx] isa Union{Symbol,AbstractString}
                print(io, repr(evaled[idx]))
            else
                print(io, evaled[idx])
            end
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

#################### Escaping arguments ###################
# Internal functions to process an expression `ex` for use in `@test_all`. Recursively
# builds `escargs`, the vector of "broadcasted" sub-expressions. Returns a modified
# expression `ex` with references to `ARG[i]`, and two `Formatter` objects: one with 
# a pretty-printed string representation of `ex`, and one with python-like format 
# entries ("{i:s}"), that can be used to pretty-print individual failure messages. 
# Example: a .== b
# 1) Adds `a` and `b` as escaped expressions to `escargs`
# 2) Return [1] is a modified `ex` as `ARG[1] .== ARG[2]`
# 3) Return [2] a Formatter with the pretty-printed string "a .== b"
# 4) Return [3] a Formatter with the format string "{1:s} == {2:s}"

function recurse_process!(ex, escargs::Vector{Expr}; outmost::Bool=false)
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

function recurse_process_basecase!(ex, escargs::Vector{Expr}; outmost::Bool=false)
    # Escape entire expression to args
    push!(escargs, esc(ex))

    # Determine if parens are needed around the pretty-printed expression:
    parens = if outmost
        false
    elseif isexpr(ex, :call) && Meta.isbinaryoperator(ex.args[1]::Symbol)
        # Range definition, e.g. 1:5
        if ex.args[1] === :(:)
            false
        # scalar multiplication, e.g. 100x
        elseif ex.args[1] === :* &&
            length(ex.args) == 3 &&
            isa(ex.args[2], Union{Int, Int64, Float32, Float64}) && 
            isa(ex.args[3], Symbol)
            false
        # Other binary operator expressions
        else
            true
        end
    elseif isexpr(ex, (:&&, :||))
        true
    else
        false
    end

    # Pretty-print the expression using Base.show_unquoted for the base-case:
    str = Formatter(parens)
    print(str, sprint(Base.show_unquoted, ex), i=length(escargs))

    # Simplest format string {i:s} for the base-case (no parens since evaluated value
    # will be printed):
    fmt = Formatter(false)
    print(fmt, "{$(length(escargs)):s}", i=length(escargs))

    # Replace the expression with ARG[i]
    ex = :(ARG[$(length(escargs))])
    return ex, str, fmt
end

function recurse_process_keyword!(ex::Expr, escargs::Vector{Expr}; outmost::Bool=false)
    # Keyword argument values are pushed to escaped `args`, but should be
    # wrapped in a Ref() call to avoid broadcasting.
    push!(escargs, esc(Expr(:call, :Ref, ex.args[2])))

    str = Formatter(false)
    print(str, ex.args[1])
    print(str, "=")
    print(str, sprint(Base.show_unquoted, ex.args[2]), i=length(escargs))

    fmt = Formatter(false)
    print(fmt, ex.args[1])
    print(fmt, "=")
    print(fmt, "{$(length(escargs)):s}", i=length(escargs))

    # Replace keyword argument with ARG[i].x to un-Ref() in evaluation
    ex.args[2] = :(ARG[$(length(escargs))].x)
    
    return ex, str, fmt
end

function recurse_process_negation!(ex::Expr, escargs::Vector{Expr}; outmost::Bool=false)
    # Recursively update the second argument
    ex.args[2], str_arg, fmt_arg = recurse_process!(ex.args[2], escargs)

    # Never requires parentheses outside the negation
    str = Formatter(false)
    print(str, ex.args[1])
    print(str, str_arg)
    fmt = Formatter(false)
    print(fmt, "!")
    print(fmt, fmt_arg)

    # Escape negation operator
    ex.args[1] = esc(ex.args[1])

    return ex, str, fmt
end

function recurse_process_logical!(ex::Expr, escargs::Vector{Expr}; outmost::Bool=false)
    str = Formatter(!outmost)
    fmt = Formatter(!outmost)

    for i in 2:length(ex.args)
        # Recursively update the two arguments. If a sub-expression is also logical, 
        # there is no need to parenthesize so consider it `outmost=true`.
        ex.args[i], str_arg, fmt_arg = recurse_process!(
            ex.args[i], escargs, outmost=isveclogicalexpr(ex.args[i]))

        # Unless it's the first argument, print the operator
        i == 2 || print(str, " ", string(ex.args[1]), " ")
        i == 2 || print(fmt, " ", unvecoperator_string(ex.args[1]), " ")
        print(str, str_arg)
        print(fmt, fmt_arg)
    end

    # Escape the operator
    ex.args[1] = esc(ex.args[1])

    return ex, str, fmt
end

function recurse_process_comparison!(ex::Expr, escargs::Vector{Expr}; outmost::Bool=false)
    str = Formatter(!outmost)
    fmt = Formatter(!outmost)
    # Recursively update every other argument (i.e. the terms), and 
    # escape the operators.
    for i in eachindex(ex.args)
        if i % 2 == 1 # Term
            ex.args[i], str_arg, fmt_arg = recurse_process!(ex.args[i], escargs)
            print(str, str_arg)
            print(fmt, fmt_arg)
        else # Operator
            print(str, " ", string(ex.args[i]), " ")
            print(fmt, " ", unvecoperator_string(ex.args[i]), " ")
            ex.args[i] = esc(ex.args[i])
        end
    end
    
    return ex, str, fmt
end

function recurse_process_approx!(ex::Expr, escargs::Vector{Expr}; outmost::Bool=false)
    # Recursively update both positional arguments
    ex.args[2], str_arg2, fmt_arg2 = recurse_process!(ex.args[2], escargs)
    ex.args[3], str_arg3, fmt_arg3 = recurse_process!(ex.args[3], escargs)

    # If outmost, format as comparison, otherwise as a function call
    str = Formatter(false)
    print(str, string(ex.args[1]))
    print(str, "(")
    print(str, str_arg2)
    print(str, ", ")
    print(str, str_arg3)
    print(str, ", ")

    fmt = Formatter(false)
    if outmost
        print(fmt, fmt_arg2)
        print(fmt, " ", unvecoperator_string(ex.args[1]), " ")
        print(fmt, fmt_arg3)
        print(fmt, " (")
    else
        print(fmt, unvecoperator_string(ex.args[1]))
        print(fmt, "(")
        print(fmt, fmt_arg2)
        print(fmt, ", ")
        print(fmt, fmt_arg3)
        print(fmt, ", ")
    end

    # Recursively update with keyword arguments
    for i in 4:length(ex.args)
        ex.args[i], str_arg, fmt_arg = recurse_process!(ex.args[i], escargs)
        print(str, str_arg)
        print(fmt, fmt_arg)
        i == length(ex.args) || print(str, ", ")
        i == length(ex.args) || print(fmt, ", ")
    end
    print(str, ")")
    print(fmt, ")")

    # Escape function
    ex.args[1] = esc(ex.args[1])

    return ex, str, fmt
end

function recurse_process_displayfunc!(ex::Expr, escargs::Vector{Expr}; outmost::Bool=false)
    ex_args = ex.args[2].args

    str = Formatter(false)
    fmt = Formatter(false)

    print(str, string(ex.args[1]), ".(")
    print(fmt, string(ex.args[1]), "(")
    for i in eachindex(ex_args)
        ex_args[i], str_arg, fmt_arg = recurse_process!(ex_args[i], escargs, outmost=true)
        print(str, str_arg)
        print(fmt, fmt_arg)
        i == length(ex_args) || print(str, ", ")
        i == length(ex_args) || print(fmt, ", ")
    end
    print(str, ")")
    print(fmt, ")")

    # Escape the function name
    ex.args[1] = esc(ex.args[1])

    return ex, str, fmt
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


    # If evaled contains non-Bool values, throw a NonBoolTypeError with pretty-printed
    # message. Need the evaled !== missing check to avoid a MethodError for iterate(missing).
    if evaled !== missing && any(x -> x !== true && x !== false && x !== missing, evaled)
        throw(NonBoolTypeError(evaled))
    end

    # Compute the result of the all() call:
    res = evaled === missing ? missing : all(evaled)

    # If all() returns true, no need for pretty printing anything. 
    res === true && return Returned(true, nothing, source)

    # Broadcast the input terms and compile the formatting expression for pretty printing. 
    # Wrap in a try catch/block, so that we can fallback to a simple message if the
    # some terms are not broadcastable, or if the size of the broadcasted terms
    # does not match the size of the evaluated result (I believe the latter should not
    # happen, but better safe than sorry).
    # try 
        broadcasted_terms = Base.broadcasted(tuple, terms...)
        # size(broadcasted_terms) == size(evaled) || Broad)
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
        if MAX_PRINT_FAILURES[] == 0
            return Returned(false, stringify!(io), source)
        end
        idxs = try 
            if MAX_PRINT_FAILURES[] == 1
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
    mod_ex, str, fmt = recurse_process!(ex, escaped_args; outmost=true)
    str, fmt = stringify!(str), stringify!(fmt)

    result = quote
        try
            let ARG = Any[$(escaped_args...)] # Use `let` for local scope on `ARG`
                eval_test_all(
                    $(mod_ex), 
                    ARG, 
                    $(fmt),
                    $(QuoteNode(source))
                )
            end
        catch _e
            _e isa InterruptException && rethrow()
            Threw(_e, Base.current_exceptions(), $(QuoteNode(source)))
        end
    end

    return result, str
end

"""
    @test_all ex
    @test_all f(args...) key=val ...
    @test_all ex broken=true
    @test_all ex skip=true

Test that the expression `all(ex)` evaluates to `true`. Does not short-circuit at 
the first `false` value, so that all `false` elements are shown in case of failure.

Same return behaviour as [`Test.@test`](@extref Julia), namely: if executed inside a
`@testset`, returns a `Pass` `Result` if `all(ex)` evaluates to `true`, a `Fail` `Result`
if it evaluates to `false` or `missing`, and an `Error` `Result` if it could not be 
evaluated. If executed outside a `@testset`, throws an exception instead of returning 
`Fail` or `Error`.

# Examples
```@julia-repl
julia> @test_all [1.0, 2.0] .== [1, 2]
Test Passed

julia> @test_all [1, 2, 3] .< 2
Test Failed at none:1
  Expression: all([1, 2, 3] .< 2)
   Evaluated: false
    Argument: 3-element BitVector, 2 failures:
              [2]: 2 < 2 ===> false
              [3]: 3 < 2 ===> false
```

Similar to `@test`, the `@test_all f(args...) key=val...` form is equivalent to writing 
`@test_all f(args...; key=val...)` which can be useful when the expression is a call
using infix syntax such as vectorized approximate comparisons: 

```@julia-repl
julia> v = [0.99, 1.0, 1.01];

julia> @test_all v .≈ 1 atol=0.1
Test Passed
```

This is equivalent to the uglier test `@test_all .≈(v, 1, atol=0.1)`. 
Keyword splicing also works through any negation operator:

```@julia-repl
julia> @test_all .!(v .≈ 1) atol=0.001
Test Failed at none:1
  Expression: all(.!.≈(v, 1, atol=0.001))
   Evaluated: false
    Argument: 3-element BitVector, 1 failure:
              [2]: !≈(1.0, 1, atol=0.001) ===> false

```

As with `@test`, it is an error to supply more than one expression unless 
the first is a call (possibly broadcast `.` syntax) and the rest are 
assignments (`k=v`).

The macro supports `broken=true` and `skip=true` keywords, with similar behavior 
to [`Test.@test`](@extref Julia):

```@julia-repl
julia> @test_all [1, 2] .< 2 broken=true
Test Broken
  Expression: all([1, 2] .< 2)

julia> @test_all [1, 2] .< 3 broken=true
Error During Test at none:1
 Unexpected Pass
 Expression: all([1, 2] .< 3)
 Got correct result, please change to @test if no longer broken.

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
    str_ex = "all($str_ex)"

    # Copy `Test` code to create `Test.Result` using `do_test` or `do_broken_test`
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

@specialize