# Return `Set` of elements that are in `subset` but not in `superset`.
function _get_failures_issubset(subset, superset)
    subset, superset = Set(subset), Set(superset)
    return setdiff(subset, superset)
end

# Format result of `_get_failures_issubset` into a pretty message for the test.
function _get_test_message_issubset(failures)
    if isempty(failures) return nothing end

    io = IOBuffer()
    print(io, "LHS values not a subset of RHS values.")
    print(io, "\n    Missing from RHS: [", join(failures, ", "), "]")
    seekstart(io)
    return String(take!(io))
end

# Check whether an expression/kwargs are valid for `@test_issubset`
function _process_test_expr_issubset!(ex, kws...)
    # Check that expression is of the form "subset ⊆ superset"
    if isa(ex, Expr) && ex.head == :call && ex.args[1] == :(⊆) && length(ex.args) == 3
        # pass
    else
        throw(MacroCallError(:test_issubset, ex, kws, "Must be of the form @test_issubset a ⊆ b"))
    end

    # Throw error if any keyword arguments
    if length(kws) > 0
        throw(MacroCallError(:test_issubset, ex, kws, "No keyword arguments allowed."))
    end
    return ex
end

# Return a `Test.Pass` or `Test.Fail` (with formatted message)
function _get_test_result_issubset(
        subset, 
        superset, 
        orig_expr::String, 
        source::LineNumberNode = LineNumberNode(1)
    )
    failures = _get_failures_issubset(subset, superset)
    msg = _get_test_message_issubset(failures)
    if isnothing(msg)
        return Test.Pass(:test, orig_expr, nothing, nothing, source)
    else 
        return Test.Fail(:test, orig_expr, msg,     nothing, source)
    end
end

"""
    @test_issubset a ⊆ b [broken=false] [skip=false]

Tests that two objects contain the same elements.

# Examples
```
julia> @test_subset Set([1,2]) ⊆ Set([1,2,3])
Test Passed

julia> @test_subset Set([1,2,3]) ⊆ Set([1,2,4,5])
Test Failed
  Expression: Set([1, 2, 3]) ⊆ Set([1, 2, 4])
   Evaluated: LHS values not a subset of RHS values.
    Missing from RHS: [3]

julia> @test_subset [:b, :a, :a, :c] ⊆ [:a, :b, :a]
Test Failed
  Expression: [:b, :a, :a, :c] ⊆ [:a, :b, :a]
   Evaluated: LHS values not a subset of RHS values.
    Missing from RHS: [:c]
```
"""
macro test_issubset(ex, kws...)
    # Collect the broken/skip keywords and remove them from the rest of keywords
    kws, action = _extract_skip_broken_kw(kws...)

    # Validate and process the test expression
    _process_test_expr_issubset!(ex, kws...)

    # Extract the individual set expressions to eval and pass to the test function
    lhs, rhs = ex.args[2], ex.args[3]
    orig_ex = string(ex)

    quote 
        subset, superset = $(esc(lhs)), $(esc(rhs))
        if $(action == :skip)
            Test.record(Test.get_testset(), Test.Broken(:skipped, $(orig_ex)))
        else
            result = _get_test_result_issubset(subset, superset, $(orig_ex), $(QuoteNode(__source__)))
            if $(action == :broken) 
                result = _get_broken_result(result, $(orig_ex), $(QuoteNode(__source__)))
            end
            Test.record(Test.get_testset(), result);
        end
    end
end

