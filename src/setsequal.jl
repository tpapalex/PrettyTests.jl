# Return two `Set`s, containing all elements from `rhs` that are not nin `lhs`, and vice-versa.
function _get_failures_setsequal(lhs, rhs)
    lhs, rhs = Set(lhs), Set(rhs)
    return setdiff(rhs, lhs), setdiff(lhs, rhs)
end

# Format result of `_get_failures_setsequal` into a pretty message for the test.
function _get_test_message_setsequal(failures)
    missing_lhs, missing_rhs = failures
    if isempty(missing_lhs) && isempty(missing_rhs) return nothing end

    io = IOBuffer()
    print(io, "Sets are not equal.")
    if !isempty(missing_lhs) print(io, "\n    Missing from LHS: [", join(missing_lhs, ", "), "]") end
    if !isempty(missing_rhs) print(io, "\n    Missing from RHS: [", join(missing_rhs, ", "), "]") end
    seekstart(io)
    return String(take!(io))
end

# Check whether an expression/kwargs are valid for `@test_setsequal`
function _process_test_expr_setsequal!(ex, kws...)
    # Check that expression is of the form "set1 == set2"
    if isa(ex, Expr) && ex.head == :call && ex.args[1] == :(==) && length(ex.args) == 3
        # pass
    else
        throw(_testerror(:test_setsequal, ex, kws, "Must be of the form @test_setsequal a == b"))
    end

    # Throw error if any keyword arguments
    if length(kws) > 0
        throw(_testerror(:test_setsequal, ex, kws, "No keyword arguments allowed."))
    end
    return ex
end

# Return a `Test.Pass` or `Test.Fail` (with formatted message)
function _get_test_result_setsequal(
        lhs, rhs, 
        orig_expr::String,
        source::LineNumberNode = LineNumberNode(1)
    )
    failures = _get_failures_setsequal(lhs, rhs)
    msg = _get_test_message_setsequal(failures)
    if isnothing(msg)
        return Test.Pass(:test, orig_expr, nothing, true, source)
    else 
        return Test.Fail(:test, orig_expr, msg,     false, source)
    end
end

"""
    @test_setsequal a == b [broken=false] [skip=false]

Tests that two containers `a` and `b` (e.g. sets or vectors) contain the same elements. 

# Examples
```
julia> @test_setsequal Set([1,2,3]) == Set([1,2,3])
Test Passed

julia> @test_setsequal Set([1,2,3]) == Set([1,2,4])
Test Failed
  Expression: Set([1, 2, 3]) == Set([1, 2, 4])
   Evaluated: Sets are not equal.
    Missing from LHS: [4]
    Missing from RHS: [3]

julia> @test_setsequal [:b, :a, :a, :c] == Set([:a, :b])
Test Failed
  Expression: [:b, :a, :a, :c] == Set([:a, :b])
   Evaluated: Sets are not equal.
    Missing from RHS: [:c]
```
"""
macro test_setsequal(ex, kws...)
    # Collect the broken/skip keywords and remove them from the rest of keywords
    kws, action = _extract_skip_broken_kw(kws...)

    # Validate and process the test expression
    _process_test_expr_setsequal!(ex, kws...)
    
    # Extract the individual set expressions to eval and pass to the test function
    lhs, rhs = ex.args[2], ex.args[3]
    orig_ex = string(ex)

    quote
        set1, set2 = $(esc(lhs)), $(esc(rhs))
        if $(action == :skip)
            Test.record(Test.get_testset(), Test.Broken(:skipped, $(orig_ex)))
        else
            result = _get_test_result_setsequal(set1, set2, $(orig_ex), $(QuoteNode(__source__)))
            if $(action == :broken) 
                result = _get_broken_result(result, $(orig_ex), $(QuoteNode(__source__)))
            end
            Test.record(Test.get_testset(), result);
        end
    end
end

