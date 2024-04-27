# Create a custom error for invalid test macro calls. `addl` is appended to the error message.
function _testerror(testtype::Symbol, ex, kws, addl=nothing)
    return ErrorException(
        "invalid test macro call: \
        @$(testtype) \
        $(ex) \
        $(length(kws) == 0 ? "" : join(kws," "))\
        $(addl === nothing ? "" : "\n$(addl)")\
        "
    )
end

# Extract what type of test to do based on `skip` and `broken` keywords. Returns the 
# filtered keyword arguments and the test `action` to take (:skip, :broken, or :do)
function _extract_skip_broken_kw(kws...)
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

    # If either exists and is true, pick it as the test action, otherwise default :do
    if length(skip) > 0 && skip[1]
        action = :skip
    elseif length(broken) > 0 && broken[1]
        action = :broken
    else
        action = :do
    end

    return kws, action
end

# For the case where `broken=true`, returns an "unexpected pass" test is `result` is Test.Pass
# or a "broken" test if `result` is Test.Fail.
function _get_broken_result(result, orig_expr, source::LineNumberNode=LineNumberNode(1))
    if result isa Test.Pass
        return Test.Error(:test_unbroken, orig_expr, nothing, nothing, source)
    elseif result isa Test.Fail
        return Test.Broken(:test, orig_expr)
    else
        return result
    end
end
