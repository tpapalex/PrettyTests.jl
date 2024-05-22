################### Global behavior variables ##################

# Whether expressions should be color coded in the output.
const STYLED_FAILURES = Ref{Bool}(get(stdout, :color, false)) 

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

Globally disable ANSI color styling in macro failure messages. 
    
All tests macros that are run after this function will print failure messages 
in plain text (or until `enable_failure_styling()` is called).

The function can be called when the module is loaded, e.g. in a `runtests.jl` file, to 
disable styling throughout a test suite. Alternatively, it can be called at the beginning
of a specific [`@testset`](@extref Julia Test.@testset) and renabled at the end to disable
styling for that specific test set.

See also [`enable_failure_styling`](@ref).
"""
function disable_failure_styling()
    STYLED_FAILURES[] = false
end

"""
    enable_failure_styling()

Globally enable ANSI color styling in macro failure messages. 
    
All test macros that are run after this function will print failure messages 
with ANSI color styling for readability (or until `disable_failure_styling()` is called).

See also [`disable_failure_styling`](@ref).
"""
function enable_failure_styling()
    STYLED_FAILURES[] = true
end

# Number of failures that are printed in a `@test_all` failures (via `print_failures()`).
const MAX_PRINT_FAILURES = Ref{Int}(10)

"""
    set_max_print_failures(n=10)

Globaly sets the maximum number of individual failures that will be printed in a 
failed [`@test_all`](@ref) test to `n`. If `n` is `nothing`, all failures are printed.
If `n == 0`, only a summary is printed.

By default, if there are more than `n=10` failing elements in a `@test_all`, the macro
only shows messages for the first and last `5`. Calling this function changes `n`
globally for all subsequent tests, or until the function is called again.

The function returns the previous value of `n` so that it can be restored if desired.

# Examples
```jldoctest; setup = (using PrettyTests: set_max_print_failures)
julia> @test_all 1:3 .== 0
Test Failed at none:1
  Expression: all(1:3 .== 0)
   Evaluated: false
    Argument: 3-element BitVector, 3 failures:
              [1]: 1 == 0 ===> false
              [2]: 2 == 0 ===> false
              [3]: 3 == 0 ===> false

julia> set_max_print_failures(0);

julia> @test_all 1:3 .== 0
Test Failed at none:1
  Expression: all(1:3 .== 0)
   Evaluated: false
    Argument: 3-element BitVector, 3 failures
```
"""
function set_max_print_failures(n::Integer=10)
    @assert n >= 0 
    old_n = MAX_PRINT_FAILURES[]
    MAX_PRINT_FAILURES[] = n
    return old_n
end
set_max_print_failures(::Nothing) = set_max_print_failures(typemax(Int))


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
