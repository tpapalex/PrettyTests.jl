# Set of valid operators for @test_sets
const OPS_SETCOMP = (
    :(==),
    :≠,
    :⊆, 
    :⊇, 
    :⊊, 
    :⊋,
    :∩,
)

# Additional valid operators that are converted in `preprocess`
const OPS_SETCOMP_CONVERTER = Dict(
    :!= => :≠,
    :⊂ => :⊆,
    :⊃ => :⊇,
    :|| => :∩,
    :issetequal => :(==),
    :isdisjoint => :∩,
    :issubset => :⊆,
)

#################### Pretty printing utilities ###################
const _INDENT_SETOP = "              "; # Match indentation of @test "Evaluated: " line

function printLsepR(
        io::IO, 
        L::AbstractString, 
        sep::AbstractString, 
        R::AbstractString, 
        suffixes::AbstractString...
    ) 
    printstyled(io, L, color=EXPRESSION_COLORS[1])
    print(io, " ")
    print(io, sep)
    print(io, " ")
    printstyled(io, R, color=EXPRESSION_COLORS[2])
    print(io, suffixes...)
end

const LminusR     = "L ∖ R"
const RminusL     = "R ∖ L"
const LequalR     = "L = R"
const LintersectR = "L ∩ R"

# Print a set or vector compactly, with a description:
function printset(io::IO, v::Union{AbstractVector, AbstractSet}, desc::AbstractString)
    n = length(v)
    print(io, "\n", _INDENT_SETOP)
    print(io, desc)
    print(io, " has ", n, " element", n == 1 ? ":  " : "s: ")
    Base.show_vector(IOContext(io, :typeinfo => typeof(v)), v)
end

function printset(io::IO, v, desc::AbstractString)
    printset(io, collect(v), desc)
end

# Stringify a processed `@test_sets` expression, to be printed in the `@test`
# `Evaluated: ` line.
function stringify_expr_test_sets(ex)
    suffix = ex.args[1] === :∩ ? " == ∅" : ""
    str = sprint(
        printLsepR, 
        sprint(Base.show_unquoted, ex.args[2]),
        sprint(Base.show_unquoted, ex.args[1]),
        sprint(Base.show_unquoted, ex.args[3]),
        suffix, 
        context = :color => STYLED_FAILURES[]
    )
    return str
end

#################### Evaluating @test_sets ###################

# Internal function to process an expression `ex` for use in `@test_sets`. Validates
# the form `L <op> R` and convert any operator aliases to the canonical version.
function process_expr_test_sets(ex)

    # Special case in case someone uses `a ∩ b == ∅`
    if isexpr(ex, :call, 3) && ex.args[1] === :(==) 
        if isexpr(ex.args[2], :call, 3) && ex.args[2].args[1] === :∩ && ex.args[3] === :∅
            ex = ex.args[2]
        elseif isexpr(ex.args[3], :call, 3) && ex.args[3].args[1] === :∩ && ex.args[2] === :∅
            ex = ex.args[3]
        end
    end

    if isexpr(ex, :call, 3)
        op, L, R = ex.args
        op = get(OPS_SETCOMP_CONVERTER, op, op)
        if op ∉ OPS_SETCOMP
            error("invalid test macro call: @test_set unsupported set operator $op")
        end
    elseif isexpr(ex, :||, 2)
        op = :∩
        L, R = ex.args
    else
        error("invalid test macro call: @test_set $ex")
    end

    return Expr(:call, op, L, R)
end

# Internal function used at `@test_sets` runtime to get a `Returned` `Test.ExecutionResult`
# with nice failure messages. Used in the code generated by `get_test_sets_result()` at 
# compile time.
# - `L`: the container on the left side of the operator
# - `op`: the operator, one of `OPS_SETCOMP`
# - `R`: the container on the right side of the operator
function eval_test_sets(L, op, R, source)
    # Perform the desired set operation to get the boolean result:
    if op === :(==)
        res = issetequal(L, R)
    elseif op === :≠
        res = !issetequal(L, R)
    elseif op === :∩
        res = isdisjoint(L, R)
    else
        res = eval(op)(L, R)
    end

    # If the result is false, create a custom failure message depending on the operator:
    if res === false
        io = failure_ioc()

        if op === :(==) # issetequal(L, R)
            printLsepR(io, "L", "and", "R", " are not equal.")
            printset(io, setdiff(L, R), LminusR)
            printset(io, setdiff(R, L), RminusL)

        elseif op === :!= || op === :≠ # !issetequal(L, R)
            printLsepR(io, "L", "and", "R", " are equal.")
            printset(io, intersect(L, R), LequalR)

        elseif op === :⊆  # issubset(L, R)
            printLsepR(io, "L", "is not a subset of", "R", ".")
            printset(io, setdiff(L, R), LminusR)

        elseif op === :⊇ # issubset(R, L)
            printLsepR(io, "L", "is not a superset of", "R", ".")
            printset(io, setdiff(R, L), RminusL)

        elseif op === :⊊ && issetequal(L, R) # L ⊊ R (failure b/c not *proper* subset)
            printLsepR(io, "L", "is not a proper subset of", "R", ", it is equal.")
            printset(io, intersect(L, R), LequalR)

        elseif op === :⊊ # L ⊊ R (failure because L has extra elements)
            printLsepR(io, "L", "is not a proper subset of", "R", ".")
            printset(io, setdiff(L, R), LminusR)

        elseif op === :⊋ && issetequal(L, R) # L ⊋ R (failure b/c not *proper* superset)
            printLsepR(io, "L", "is not a proper superset of", "R", ", it is equal.")
            printset(io, intersect(L, R), LequalR)

        elseif op === :⊋ # L ⊋ R (failure because R has extra elements)
            printLsepR(io, "L", "is not a proper superset of", "R", ".")
            printset(io, setdiff(R, L), RminusL)

        elseif op === :∩ # isdisjoint(L, R)
            printLsepR(io, "L", "and", "R", " are not disjoint.")
            printset(io, intersect(L, R), LintersectR)

        else
            error("Unsupported operator $op.")
        end

        return Returned(res, stringify!(io), source)

    else # res === true
        return Returned(res, nothing, source)
    end
end

# Internal function used at compile time to generate code that will produce the final
# `@test_sets` `Test.ExecutionResults`. Wraps `eval_test_sets()` in a try/catch block 
# so that exceptions can be returned as `Test.Threw` result.
function get_test_sets_result(ex, source)
    op, L, R = ex.args    
    if L === :∅ L = :(Set()) end
    if R === :∅ R = :(Set()) end
    
    result = quote
        try 
            eval_test_sets(
                $(esc(L)), 
                $(QuoteNode(op)),
                $(esc(R)), 
                $(QuoteNode(source))
            )
        catch _e
            _e isa InterruptException && rethrow()
            Threw(_e, Base.current_exceptions(), $(QuoteNode(source)))
        end
    end
    result
end

"""
    @test_sets L op R
    @test_sets L op R broken=true
    @test_sets L op R skip=true

Tests that the expression `L op R` returns `true`, where `op` is an infix operator
interpreted as a set-like comparison:

- `L == R` expands to `issetequal(L, R)`
- `L != R` or `L ≠ R` expands to `!issetequal(L, R)`
- `L ⊆ R` or `L ⊂ R` expands to `⊆(L, R)`
- `L ⊇ R` or `L ⊃ R` expands to `⊇(L, R)`
- `L ⊊ R` expands to `⊊(L, R)`
- `L ⊋ R` expands to `⊋(L, R)`
- `L ∩ R` or `L || R` expands to `isdisjoint(L, R)`

You can use any `L` and `R` that work with the expanded expressions (including tuples, 
arrays, sets, dictionaries and strings). The `∅` symbol can also be used for either 
expression as shorth and for `Set()`.

The only additional limitation is that `setdiff(L, R)` and `intersect(L, R)` must also
work, since they are used to generate informative failure messages in some cases.

See also: [`Base.issetequal`](@extref Julia), [`Base.issubset`](@extref Julia),
[`Base.isdisjoint`](@extref Julia), [`Base.setdiff`](@extref Julia), 
[`Base.intersect`](@extref Julia).

!!! note "Disjointness"
    The last form represents a slight abuse of notation, in that `isdisjoint(L, R)` is
    better notated as `L ∩ R == ∅`. The macro also supports this syntax, in addition 
    to shorthand `L ∩ R` and `L || R`.

!!! note "Typing unicode characters"
    Unicode operators like the above can be typed in Julia editors by typing 
    `\\<name><tab>`. The ones supported by this macro are `≠` (`\\neq`), 
    `⊆` (`\\subseteq`), `⊇` (`\\supseteq`), `⊂` (`\\subset`),`⊃` (`\\supset`), 
    `⊊` (`\\subsetneq`), `⊋` (`\\supsetneq`), `∩` (\\cap), and `∅` (`\\emptyset`). 

# Examples 

```jldoctest; filter = r"(\\e\\[\\d+m|\\s+)"
julia> @test_sets (1,2) == (2,1,1,1)
Test Passed

julia> @test_sets ∅ ⊆ 1:10
Test Passed

julia> @test_sets 1:20 ⊇ 42
Test Failed at none:1
  Expression: 1:20 ⊇ 42
   Evaluated: L is not a superset of R.
              R ∖ L has 1 element:  [42]

julia> @test_sets [1,2,3] ∩ [2,3,4]
Test Failed at none:1
  Expression: [1, 2, 3] ∩ [2, 3, 4] == ∅
   Evaluated: L and R are not disjoint.
              L ∩ R has 2 elements: [2, 3]

julia> @test_sets "baabaa" ≠ 'a':'b'
Test Failed at none:1
  Expression: "baabaa" ≠ 'a':'b'
   Evaluated: L and R are equal.
```

The macro supports `broken=cond` and `skip=cond` keywords, with similar behavior 
to [`Test.@test`](@extref Julia):

# Examples

```jldoctest; filter = r"(\\e\\[\\d+m|\\s+|ERROR.*)"
julia> @test_sets 1 ⊆ 2:3 broken=true
Test Broken
  Expression: 1 ⊆ 2:3

julia> @test_sets 1 ⊆ 1:3 broken=true
Error During Test at none:1
 Unexpected Pass
 Expression: 1 ⊆ 1:3
 Got correct result, please change to @test if no longer broken.

julia> @test_sets 1 ⊆ 2:3 skip=true
Test Broken
  Skipped: 1 ⊆ 2:3
```
"""
macro test_sets(ex, kws...)    
    # Collect the broken/skip keywords and remove them from the rest of keywords:
    kws, broken, skip = extract_broken_skip_keywords(kws...)

    # Ensure that no other expressions are present
    length(kws) == 0 || error("invalid test macro call: @test_sets $ex $(join(kws, " "))")
    
    # Process expression and get stringified version
    ex = process_expr_test_sets(ex)
    str_ex = stringify_expr_test_sets(ex)

    # Generate code to evaluate expression and return a `Test.ExecutionResult`
    result = get_test_sets_result(ex, __source__)

    result = quote
        if $(length(skip) > 0 && esc(skip[1]))
            record(get_testset(), Broken(:skipped, $str_ex))
        else
            let _do = $(length(broken) > 0 && esc(broken[1])) ? do_broken_test : do_test
                _do($result, $str_ex)
            end
        end
    end
end