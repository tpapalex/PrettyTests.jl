################### Global behavior variables ##################

# Whether expressions should be color coded in the output.
const STYLED_FAILURES = Ref{Bool}(true) 

# Color cycle used for expression coloring
const EXPRESSION_COLORS = (
    :light_cyan, 
    :light_magenta, 
    :light_blue,
    :light_green, 
)

# Utility to extract the i'th color of the cycle:
get_color(i::Integer) = EXPRESSION_COLORS[(i - 1) % length(EXPRESSION_COLORS) + 1]

"""
    disable_failure_styling()
    enable_failure_styling()

Globally enable or disable failure message styling in the exported test macros.
If enabled, failure messages will color-code failure messages to make them more
human-readable.

!!! note "Does not affect `Test` styling"
    These function do not affect any styling from the Test module, e.g. green 
    `"Test Passed"` or red `Test Failed` print-outs or colored test set summaries. 
"""
function disable_failure_styling()
    STYLED_FAILURES[] = false
end
function enable_failure_styling()
    STYLED_FAILURES[] = true
end

# Function to create a new IOBuffer() wrapped in an IOContext for creating 
# failure messages. 
function failure_ioc(; 
        compact::Bool=true, 
        limit::Bool=true, 
        override_color::Bool=false, 
        typeinfo=nothing
    )
    io = IOBuffer()
    if typeinfo === nothing
        io = IOContext(io, 
            :compact => compact, 
            :limit => limit, 
            :color => STYLED_FAILURES[] || override_color
        )
    else
        io = IOContext(io, 
            :compact => compact, 
            :limit => limit, 
            :typeinfo => typeinfo,
            :color => STYLED_FAILURES[] || override_color
        )
    end
    return io
end
stringify!(io::IOContext) = String(take!(io.io))

# Internal function called on a test macros kws... to extract broken and skip keywords.
# Modified from Test.@test macro processing
function extract_broken_skip_keywords(kws...)
    # Collect the broken/skip keywords and remove them from the rest of keywords
    broken = [kw.args[2] for kw in kws 
              if isa(kw, Expr) && kw.head == :(=) && kw.args[1] === :broken]
    skip   = [kw.args[2] for kw in kws 
              if isa(kw, Expr) && kw.head == :(=) && kw.args[1] === :skip]
    kws = filter(kw -> !isa(kw, Expr) || (kw.args[1] ∉ (:skip, :broken)), kws)
    # Validation of broken/skip keywords
    for (kw, name) in ((broken, :broken), (skip, :skip))
        if length(kw) > 1
            error("invalid test macro call: cannot set $(name) keyword multiple times")
        end
    end
    if length(skip) > 0 && length(broken) > 0
        error("invalid test macro call: cannot set both skip and broken keywords")
    end

    return kws, broken, skip
end