# Internal error formatting for invalid test macro calls. Returns an ErrorException to be
# thrown locally.
function MacroCallError(testtype::Symbol, ex, kws, addl=nothing)
    return ErrorException(
        "invalid test macro call: \
        @$(testtype) \
        $(ex)\
        $(length(kws) == 0 ? "" : " " * join(kws," "))\
        $(addl === nothing ? "" : "\n$(addl)")\
        "
    )
end


# Internal function that processes test macro `kws...` expressions to pick out `skip` 
# and `broken` keywords. Returns `kws` with `broken`/`skip` arguments removed, and a 
# `modifier::Symbol` ∈ (:do, :skip, :broken) indicating how the test should be 
# handled.
function extract_test_modifier(kws...)
    # Based on code in Test.@test macro.

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

    # Determine the test modifier based on the values:
    if length(skip) > 0 && skip[1]
        modifier = :skip
    elseif length(broken) > 0 && broken[1]
        modifier = :broken
    else
        modifier = :do
    end

    return kws, modifier
end

# # Internal function called on a test Result when performing a `broken=true` test. If 
# # `result` is Pass, returns a Error(:test_unbroken) instead. If the result is Fail,
# # returns a Broken(:test). Otherwise, returns the result as is.
# function do_broken_test(result::ExecutionResult)
#     if result isa Test.Pass
#         return Test.Error(:test_unbroken, result.orig_expr, result.value, nothing, result.source)
#     elseif result isa Test.Fail
#         return Test.Broken(:test, orig_expr)
#     else
#         return result
#     end
# end
