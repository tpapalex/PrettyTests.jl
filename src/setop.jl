# Set of valid operators for @test setop
const SETOP_VALID_OPS = (
    :(==),
    :!=, 
    :≠,
    :⊆,
    :⊇,
    :⊊,
    :⊋,
    :||,
)

"""
    test_setop_expr!(ex, kws...)

Preprocesses test_setop expressions to validate that the operator is valid and the 
expression is well-formed. 
"""
function test_setop_expr!(ex, kws...)

    if isa(ex, Expr)
        if ex.head === :comparison 
            # Do not support a == b ⊆ c
            error("invalid test macro call: does not support :comparison expressions")
        elseif ex.head === :||
            # Support a || b as alias for isdisjoint(a, b)
            # pass
        elseif ex.head !== :call || length(ex.args) > 3
            # Only support a <op> b
            error("invalid test macro call: @test_setop $(ex)")
        elseif ex.args[1] ∉ SETOP_VALID_OPS
            # Invalid operator
            error("invalid test macro call: unsupported set operator $(ex.args[1])")
        end
    else
        error("invalid test macro call: @test_setop $(ex)")
    end

    # No keyword arguments
    if length(kws) > 0
        error("invalid test macro call: unsupported extra arguments $(join(kws, " "))")
    end

    return ex
end

# Internal function to print nice message for sets
function print_pretty_set(io::IO, vals, desc, max_vals=5)
    print(io, "\n              ") # Matches spacing in Test Failed "Evaluated: " line
    print(io, length(vals), " element")
    print(io, length(vals) == 1 ? " " : "s")
    print(io, " ", desc, ": ")

    print(io, "[")
    for (i, val) in enumerate(vals)
        print(io, repr(val))
        if i == max_vals && i != length(vals)
            print(io, ", ...")
            break
        end
        if i != length(vals)
            print(io, ", ")
        end
    end
    print(io, "]")
end

function eval_test_setop(lhs, op, rhs, source)

    # First perform the operation to get the result
    if op === :(==)
        res = issetequal(lhs, rhs)
    elseif op === :!= || op === :≠
        res = !issetequal(lhs, rhs)
    elseif op === :||
        res = isdisjoint(lhs, rhs)
    else
        res = eval(op)(lhs, rhs)
    end

    # If the result is false, we create custom messages to pass as `data`, depending on 
    # the operator.
    if !res
        data = IOBuffer()

        if op === :(==) # a == b
            print(data, "Left and right sets are not equal.")
            print_pretty_set(data, setdiff(rhs, lhs), "in right\\left")
            print_pretty_set(data, setdiff(lhs, rhs), "in left\\right")
        elseif op === :!= || op === :≠ # a != b
            print(data, "Left and right sets are equal.")

        elseif op === :⊆  # a ⊆ b
            print(data, "Left set is not a subset of right set.")
            print_pretty_set(data, setdiff(lhs, rhs), "in left\\right")

        elseif op === :⊇ # a ⊇ b
            print(data, "Left set is not a superset of right set.")
            print_pretty_set(data, setdiff(rhs, lhs), "in right\\left")

        elseif op === :⊊ && issetequal(lhs, rhs) # a ⊊ b (failure because equal)
            print(data, "Left and right sets are equal, left is not a proper subset.")

        elseif op === :⊊# a ⊊ b (failure because missing elements in RHS)
            print(data, "Left set is not a proper subset of right set.")
            print_pretty_set(data, setdiff(lhs, rhs), "in left\\right")
        elseif op === :⊋ && issetequal(lhs, rhs) # a ⊋ b (failure because equal)
            print(data, "Left and right sets are equal, left is not a proper superset.")

        elseif op === :⊋ # a ⊋ b (failure because missing elements in LHS)
            print(data, "Left set is not a proper superset of right set.")
            print_pretty_set(data, setdiff(rhs, lhs), "in right\\left")

        elseif op === :|| # isdisjoint(a, b)
            print(data, "Left and right sets are not disjoint.")
            print_pretty_set(data, intersect(lhs, rhs), "in common")

        else
            error("Unsupported operator $op.")
        end

        return Returned(res, String(take!(data)), source)

    else # res = true
        return Returned(res, nothing, source)
    end
end

function get_test_setop_result(ex, source)
    # Assumes the expression is well-formed for @test_setop (see test_setop_expr!)
    if ex.head === :||
        op = :||
        lhs, rhs = ex.args
    else
        op, lhs, rhs = ex.args
    end
    result = quote
        try 
            eval_test_setop(
                $(esc(lhs)), 
                $(QuoteNode(op)),
                $(esc(rhs)), 
                $(QuoteNode(source))
            )
        catch _e
            _e isa InterruptException && rethrow()
            Threw(_e, Base.current_exceptions(), $(QuoteNode(source)))
        end
    end
    result
end

macro test_setop(ex, kws...)
    # Extract broken/skip keywords
    kws, broken, skip = extract_broken_skip_keywords(kws...)

    # Validate and process the test expression
    test_setop_expr!(ex, kws...)

    # Get the result expression
    result = get_test_setop_result(ex, __source__)

    ex = Expr(:inert, ex)

    result = quote
        if $(length(skip) > 0 && esc(skip[1]))
            record(get_testset(), Broken(:skipped, $ex))
        else
            let _do = $(length(broken) > 0 && esc(broken[1])) ? do_broken_test : do_test
                _do($result, $ex)
            end
        end
    end

end