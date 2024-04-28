
# Returns a vector of (index, lhs, rhs) tuples, one for each index where the 
# `broadcasted_bit_result` is unexpected (false). `broadcasted_bit_result` is assumed to
# be the result of a vectorized (possibly broadcasted) operation on `lhs` and `rhs`, 
# i.e. `broadcasted_bit_result = lhs .== rhs`.
function _get_failures_vectorized(lhs, rhs, broadcasted_bit_result)
    # Find all failing indicies
    ii = findall(x -> !x, broadcasted_bit_result)
    # Create broadcasted versions of lhs and rhs
    lhs_broadcasted = Broadcast.broadcasted((x, y) -> x, lhs, rhs)
    rhs_broadcasted = Broadcast.broadcasted((x, y) -> y, lhs, rhs)
    # Extract the values at the failing indices
    lhs_vals = [lhs_broadcasted[i] for i in ii]
    rhs_vals = [rhs_broadcasted[i] for i in ii]
    # Convert CartesianIndex to tuples.
    if eltype(ii) <: CartesianIndex
        ii = getfield.(ii, :I)
    end
    return collect(zip(ii, lhs_vals, rhs_vals))
end

# Format result of `_get_test_message_vectorized` into a pretty message for the test.
function _get_test_message_vectorized(failures, op::String)
    if isempty(failures) return nothing end

    io = IOBuffer()
    if length(failures) == 1
        print(io, "Failed at 1 index.")
    else
        print(io, "Failed at ", length(failures), " indices.")
    end
    for (i, lhs, rhs) in failures
        print(io, "\n    [", join(i, ","), "]: ", repr(lhs), " ", op, " ", repr(rhs))
    end
    seekstart(io)
    return String(take!(io))
end

# Set of all supported (vectorized) logical or comparison operators.
const _VECTORIZED_VALID_OPS = (
    :.==,
    :.!=,
    :.≠,
    :.<,
    :.>,
    :.<=,
    :.>=,
    :.≈,
    :.≉,
    :.&,
    :.&&,
    :.|,
    :.||,
)

# Set of the corresponding unvectorized operators. This is used only to suggest the vectorized
# version if the expression is not valid.
const _UNVECTORIZED_VALID_OPS = map(x -> Symbol(replace(string(x), r"^." => "")), _VECTORIZED_VALID_OPS)

# Common error message for invalid vectorized test expressions.
const _VECTORIZED_ERROR = "Must be of the form @test_vectorized a .<op> b [kwargs...] where <op> is a binary logical or comparison operator, e.g. .==, .<=, .&&, ..."

# Check whether an expression/kwargs are valid for `@test_issubset`. Also adds the keyword arguments
# to the expression. 
function _process_test_expr_vectorized!(ex, kws...)

    # Check that expression is of the form "a .== b" or "a .&& b" etc, and extract operator.
    if isa(ex, Expr) && ex.head === :call && length(ex.args) == 3
        op = ex.args[1]
    # Logical operators (unvectorized only) are a special case, as they are the ex.head. We 
    # want to extract the op still, so we can give a custom error message below. 
    elseif isa(ex, Expr) && length(ex.args) == 2 # a && b (logical has a different head)
        op = ex.head
    else
        throw(MacroCallError(:test_vectorized, ex, kws, _VECTORIZED_ERROR))
    end

    # If valid format of expression, check that operator is supported.
    if op ∈ _VECTORIZED_VALID_OPS
        # pass
    elseif op ∈ _UNVECTORIZED_VALID_OPS
        throw(MacroCallError(:test_vectorized, ex, kws, "Requires a vectorized operation; did you mean to use $(Symbol(:., op)) instead?"))
    else
        throw(MacroCallError(:test_vectorized, ex, kws, _VECTORIZED_ERROR))
    end

    # Add keyword arguments to expression. This is primary to support atol and rtol for .≈/≉.
    for kw in kws
        kw isa Expr && kw.head === :(=) || error(_ERROR_MSG)
        kw.head = :kw
        push!(ex.args, kw)
    end

    return ex
end

# Return a `Test.Pass` or `Test.Fail` (with formatted message)
function _get_test_result_vectorized(
        lhs, 
        rhs, 
        broadcasted_bit_result, 
        op::String, 
        orig_expr::String, 
        source::LineNumberNode = LineNumberNode(1)
    )

    failures = _get_failures_vectorized(lhs, rhs, broadcasted_bit_result)
    msg = _get_test_message_vectorized(failures, op)

    if isnothing(msg)
        return Test.Pass(:test, orig_expr, nothing, nothing, source)
    else 
        return Test.Fail(:test, orig_expr, msg,     nothing, source)
    end
end

# Returns the string representation of the corresponding unvectorized operation, for 
# use in printing the error message prettily. Assumes that the expression is valid
# according to `_process_test_expr_vectorized!`.
function _get_operator_string(ex)
    if ex.head === :call
        op = ex.args[1]
    else
        op = ex.head
    end
    return replace(string(op), r"^." => "")
end

"""
    @test_vectorized a .<op> b [kwargs...] [broken=false] [skip=false]

Tests that all elements of a vectorized expression are true. Supports most vectorized
logical and comparison operators (.&, .|, .==, .<, .>, .≈, etc). `a` and `b` must
be broadcastable to a common size.

Like `@test`, allows for keyword argument interpolation, e.g. `atol` for `.≈`. 

# Examples
```
julia> @test_vectorized [1,2,3] .> 0
Test Passed

julia> @test_vectorized [:a,:b,:C] .== [:a,:b,:d]
Test Failed
  Expression: [:a, :b, :d, :E] .== [:a, :c, :d, :e]
   Evaluated: Failed at 1 index.
    [2]: :b == :c
    [4]: :E == :e

julia> @test_vectorized [1,2,3] .≈ [1, 2, 3.0001] atol=1e-3
Test Passed

julia> @test_vectorized [1,2,3] .≈ [1,2,3.001] atol=1e-8
Test Failed
  Expression: [1, 2, 3] .≈ [1, 2, 3.001] atol=1.0e-8
   Evaluated: Failed at 1 index.
    [3]: 3 ≈ 3.001


julia> @test_vectorized [1 3 5; 2 4 6] .!= 3.0
Test Failed
    Expression: [1 3 5; 2 4 6] .!= 3.0
    Evaluated: Failed at 1 index.
    [1,2]: 3 != 3.0

julia> @test_vectorized [1 2 3] .>= [1, 2]
Test Failed
  Expression: [1 2 3] .>= [1, 2]
   Evaluated: Failed at 2 indices.
    [2,1]: 1 >= 3
    [2,2]: 2 >= 3
```
"""
macro test_vectorized(ex, kws...)
    # Collect the broken/skip keywords and remove them from the rest of keywords
    kws, action = _extract_skip_broken_kw(kws...)

    orig_ex = string(ex)
    if length(kws) > 0
        orig_ex *= " $(join(kws, " "))"
    end

    # Validate and process the test expression
    _process_test_expr_vectorized!(ex, kws...)

    # Extract the individual expressions to eval and pass to the test function
    lhs, rhs = ex.args[2], ex.args[3]
    str_op = _get_operator_string(ex)

    quote 
        lhs, rhs = $(esc(lhs)), $(esc(rhs))
        broadcasted_bit_result = $(esc(ex))

        if $(action == :skip)
            Test.record(Test.get_testset(), Test.Broken(:skipped, $(orig_ex)))
        else
            result = _get_test_result_vectorized(
                lhs, rhs, broadcasted_bit_result, $(str_op),
                $(orig_ex), $(QuoteNode(__source__))
            )
            if $(action == :broken) 
                result = _get_broken_result(result, $(orig_ex), $(QuoteNode(__source__)))
            end
            Test.record(Test.get_testset(), result);
        end
    end
end

