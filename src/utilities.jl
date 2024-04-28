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
