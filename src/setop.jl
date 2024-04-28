# Set of valid operators for @test setop
const SETOP_VALID_OPS = (
    :(==),
    :!=, 
    :≠,
    :⊆,
    :⊇,
    :⊊,
    :⊋,
    :^,
)

"""
    test_setop_expr!(ex, kws...)

Preprocesses test_setop expressions to validate that the operator is valid and the 
expression is well-formed. 
"""
function test_setop_expr!(ex::Expr, kws::Expr...)

    if ex.head == :comparison 
        # Do not support a == b ⊆ c
        throw(MacroCallError(:test_setop, ex, (), 
            "Comparisons with more than 2 sets not supported."
        ))
    elseif ex.head !== :call || length(ex.args) > 3
        # Only support a <op> b
        throw(MacroCallError(:test_setop, ex, (), 
            "Must be of the form @test_setop a <op> b\
            where <op> is one of $(join(SETOP_VALID_OPS, ", "))"
        ))
    elseif ex.args[1] ∉ SETOP_VALID_OPS
        # Invalid operator
        throw(MacroCallError(:test_setop, ex, (), 
            "Unsupported set comparison operator $(ex.args[1]). \
            Must be one of $(join(SETOP_VALID_OPS, ", "))"
        ))
    end

    # Do not support keyword arguments
    if length(kws) > 0
        throw(MacroCallError(:test_setop, ex, kws, 
            "Keyword arguments not supported."
        ))
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
    lhs, rhs = Set(lhs), Set(rhs)

    # Take care of inequality first, which has simple messaging:
    if op === :(!=) || op === :≠ 
        res = lhs != rhs
        data = res ? nothing : "LHS and RHS are equal."
        return Returned(res, data, source)
    end

    # For other ops, we can perform the operation to get the result `value`
    if op === :^
        res = isdisjoint(lhs, rhs)
    else
        res = eval(op)(lhs, rhs)
    end

    # If the result is false, we create custom messages to pass as `data`, depending on 
    # the operator.
    if !res
        data = IOBuffer()

        if op === :^ # isdisjoint(a, b)
            print(data, "LHS and RHS are not disjoint.")
            print_pretty_set(data, intersect(lhs, rhs), "in common")

        elseif op === :(==) # a == b
            print(data, "LHS and RHS are not equal.")
            print_pretty_set(data, setdiff(rhs, lhs), "in RHS \\ LHS")
            print_pretty_set(data, setdiff(lhs, rhs), "in LHS \\ RHS")

        elseif op === :⊆  # a ⊆ b
            print(data, "LHS is not a subset of RHS.")
            print_pretty_set(data, setdiff(lhs, rhs), "in LHS \\ RHS")

        elseif op === :⊊ && lhs == rhs # a ⊊ b (equal case)
            print(data, "LHS is not a proper subset of RHS, they are equal.")

        elseif op === :⊊# a ⊊ b (missing elements in RHS)
            print(data, "LHS is not a proper subset of RHS.")
            print_pretty_set(data, setdiff(lhs, rhs), "in LHS \\ RHS")

        elseif op === :⊇ # a ⊇ b
            print(data, "LHS is not a superset of RHS.")
            print_pretty_set(data, setdiff(rhs, lhs), "in RHS \\ LHS")

        elseif op === :⊋ && lhs == rhs # a ⊋ b (equal case)
            print(data, "LHS is not a proper superset of RHS, they are equal.")

        elseif op === :⊋ # a ⊋ b (missing elements in LHS)
            print(data, "LHS is not a proper superset of RHS.")
            print_pretty_set(data, setdiff(rhs, lhs), "in RHS \\ LHS")

        else
            error("Unsupported operator $op.")
        end

        return Returned(res, String(take!(data)), source)

    else # res = true
        return Returned(res, nothing, source)
    end
end

function get_test_setop_result(expr, source)
    op, lhs, rhs = expr.args
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
    # Extract `broken`/`skip` keywords into modifier
    kws, modifier = extract_test_modifier(kws...)

    # Validate and process the test expression
    test_setop_expr!(ex, kws...)

    result = get_test_setop_result(ex, __source__)

    ex = Expr(:inert, ex)

    result = quote
        if $(modifier == :skip)
            record(get_testset(), Broken(:skipped, $ex))
        else
            let _do = $(modifier == :broken) ? do_broken_test : do_test
                _do($result, $ex)
            end
        end
    end

end