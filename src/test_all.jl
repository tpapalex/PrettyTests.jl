
const COMPARISON_PREC = Base.operator_precedence(:(==)) # For identifying comparison expressions

const DISPLAYED_FUNCS = ( # Functions that will be nicely displayed
    :isequal,
    :isapprox,
    :occursin,
    :startswith,
    :endswith,
    :isempty,
    :contains, 
    :ismissing, 
    :isnan, 
    :isinf
)

const APPROX_OPS = (:≈, :≉, :.≈, :.≉) 

const LOGICAL_OPS = (:&&, :||, :.&&, :.||)

function _string_idxs_justify(idxs) 
    if eltype(idxs) <: CartesianIndex
        D = length(idxs[1])
        max_len = [maximum(idx -> length(string(idx.I[d])), idxs) for d in 1:D]
        to_str = idx -> join(map(i -> lpad(idx.I[i], max_len[i]), 1:D), ", ")
        return map(to_str, idxs)
    else
        ss = string.(idxs)
        return lpad.(ss, maximum(length, ss))
    end
end

function _pretty_print_failures(@nospecialize(bitarray), failure_printer, negate=false; max_vals=10) # TODO(tpapalex): add 'wrap_negation' kwarg?

    # Finda all failing indices. 
    idxs = findall(x -> !isa(x, Bool) || (x == negate), bitarray)

    # If no falures, return no message
    if length(idxs) == 0
        return nothing
    end

    # Write failures into buffer:
    io = IOBuffer()

    # Write number of failures:
    print(io, "Failed ", length(idxs), " test", length(idxs) == 1 ? "" : "s")

    # Write dimension of bitarray:
    sz = size(bitarray)
    if length(sz) == 0
        print(io, ".")
    elseif length(sz) == 1
        print(io, " from length ", sz[1], " result.")
    else
        print(io, " from size ", join(sz, "×"), " result.")
    end

    # Figure out if we need to abbreviate to the top/bottom `max_vals` because there
    # are too many failures.
    if length(idxs) > max_vals
        abbrev_i = max_vals ÷ 2
        idxs = idxs[[1:abbrev_i; end-abbrev_i+1:end]]
    else
        abbrev_i = 0
    end

    # Get pretty-stringified indices
    str_idxs = _string_idxs_justify(idxs)

    for (i, idx) in enumerate(idxs)
        print(io, "\n    idx=[", str_idxs[i], "]: ")
        negate && print(io, "!(")
        failure_printer(io, idx)
        negate && print(io, ")")
        if !isa(bitarray[idx], Bool)
            printstyled(IOContext(io, :color=>true), " non-Boolean ===> ", bitarray[idx], color=:light_yellow)
        end
        if (i == abbrev_i) && (abbrev_i > 0)
            print(io, "\n    ⋮")
        end
    end
    seekstart(io)
    return String(take!(io))
end

function _get_escaped_args(ex_args, kws)
    escaped_args = []
    escaped_kwargs = []

    # Keywords that occur before `;` # TODO(tpapalex): these are after `;` in examples tried? Comment mistake in Test?
    for a in ex_args
        if isa(a, Expr) && a.head === :kw
            push!(escaped_kwargs, :(Expr(:kw, $(QuoteNode(a.args[1])),$(esc(a.args[2])))))
        end
    end

    # Keywords that occur after ';' # TODO(tpapalex): these are before `;` in examples I tried? Comment mistake in Test?
    parameters_expr = ex_args[1]
    if isa(parameters_expr, Expr) && parameters_expr.head === :parameters
        for a in parameters_expr.args
            if isa(a, Expr) && a.head === :kw
                push!(escaped_kwargs, :(Expr(:kw, $(QuoteNode(a.args[1])), $(esc(a.args[2])))))
            else
                error("invalid test macro call: cannot pretty with splat (...) arguments. Use `disable_pretty=true` to disable pretty printing.")
            end
        end
    end

    # Positional arguments
    for a in ex_args
        isa(a, Expr) && a.head in (:kw, :parameters) && continue
        if isa(a, Expr) && a.head === :...
            error("invalid test macro call: cannot pretty print with splat (...) arguments. Use `disable_pretty=true` to disable pretty printing.")
        else
            push!(escaped_args, esc(a))
        end
    end

    # Add passed keywords
    for kw in kws 
        if !isa(kw, Expr) || kw.head !== :(=)
            error("invalid test macro call: extra arguments must be keywords of the form kw=val")
        end
        push!(escaped_kwargs, :(Expr(:kw, $(QuoteNode(kw.args[1])), $(esc(kw.args[2])))))
    end

    return escaped_args, escaped_kwargs
end

# GENERAL UTILITIES
_is_splat(x) = isa(x, Expr) && x.head === :...

function _get_preprocessed_expr(ex, kws...)

    negate = false

    # Extract initial negation
    if isa(ex, Expr) && ex.head === :call && (ex.args[1] === :! || ex.args[1] === :.!)
        negate = true
        ex = ex.args[2]
    end

    # Normalize comparisons to :comparison
    if isa(ex, Expr) && ex.head === :call && length(ex.args) == 3 && length(kws) == 0 &&
        first(string(ex.args[1])) != "." && !_is_splat(ex.args[2]) && !_is_splat(ex.args[3]) && 
        (ex.args[1] === :(==) || Base.operator_precedence(ex.args[1]) == COMPARISON_PREC)

        ex = Expr(:comparison, ex.args[2], ex.args[1], ex.args[3])

    # Mark <: and >: as :comparison expressions
    elseif isa(ex, Expr) && length(ex.args) == 2 &&
        !_is_splat(ex.args[1]) && !_is_splat(ex.args[2]) &&
        Base.operator_precedence(ex.head) == COMPARISON_PREC

        ex = Expr(:comparison, ex.args[1], ex.head, ex.args[2])

    # Mark .<: and .>: as :comparison expressions
    elseif isa(ex, Expr) &&  ex.head === :call && length(ex.args) == 3 && 
        !_is_splat(ex.args[2]) && !_is_splat(ex.args[3]) && 
        (ex.args[1] === :.<: || ex.args[1] === :.>:)

        ex = Expr(:comparison, ex.args[2], ex.args[1], ex.args[3])
    end

    return ex, negate
end

# COMPARISON EXPRESSION
function _is_comparison(ex, kws)
    return isa(ex, Expr) && 
        ex.head === :comparison
end

function _result_comparison(ex, kws, source, negate=false)
    if length(kws) > 0
        error("invalid test macro call: extra arguments with comparison $(join(kws, " "))")
    end

    # Replace all operators with vectorized versions (without loss of generality?)
    for i in 2:2:length(ex.args)
        @assert isa(ex.args[i], Symbol)
        if first(string(ex.args[i])) != '.'
            ex.args[i] = Symbol(:., ex.args[i])
        end
    end

    # Quote operators, escape arguments
    escaped_args = [i % 2 == 1 ? esc(arg) : QuoteNode(arg) for (i, arg) in enumerate(ex.args)]

    testret = quote
        _eval_testall_comparison(
            Expr(:comparison, $(escaped_args...)),
            $(QuoteNode(source)),
            $(QuoteNode(negate))
        )
    end

    return testret
end

function _eval_testall_comparison(ex::Expr, source::LineNumberNode, negate::Bool=false)

    if ex.head === :comparison # Most calls have been normalized to this form
        terms = ex.args[1:2:end]
        ops = ex.args[2:2:end]
    else # ex.head === :call, only for .≈ and .≉ with extra kwargs
        terms = ex.args[2:3]
        ops = [ex.args[1]]
    end

    # Create a quoted expression for pretty-printing failures
    quoted_ex = Expr(:comparison)
    for i in eachindex(ops)
        push!(quoted_ex.args, 0) # Placeholder, will be replaced with broadcast values later
        push!(quoted_ex.args, Symbol(replace(string(ops[i]), r"^." => ""))) # Unvectorized operator
    end
    push!(quoted_ex.args, 0) # Placeholder
    
    # Evaluate to get broadcasted bit array, and negate if necessary:
    bitarray = eval(ex)

    # Get broadcasted terms for accessing individual elements
    broadcasted_terms = Base.broadcasted(tuple, terms...)

    # Function to print the unvectorized expression with broadcasted terms spliced in.
    failure_printer = (io, idx) -> begin
        terms = broadcasted_terms[idx]
        for i in eachindex(terms)
            quoted_ex.args[2*i-1] = terms[i]
        end
        print(io, quoted_ex)
    end

    msg = _pretty_print_failures(bitarray, failure_printer, negate)

    return Returned(msg === nothing, msg, source)
end

# ISAPPROX SPECIAL CASE (to support kwargs)
function _is_approx_specialcase(ex, kws)
    return isa(ex, Expr) && 
        ex.head === :call && 
        length(ex.args) >= 3 && 
        !_is_splat(ex.args[2]) && 
        !_is_splat(ex.args[3]) &&
        ex.args[1] ∈ APPROX_OPS
end

function _result_approx_specialcase(ex, kws, source, negate=false)
    # Replace operator with vectorized version
    if first(string(ex.args[1])) != '.'
        ex.args[1] = Symbol(:., ex.args[1])
    end
    escaped_func = QuoteNode(ex.args[1])
    escaped_args, escaped_kwargs = _get_escaped_args(ex.args[2:end], kws)
    
    testret = quote
        _eval_testall_comparison(
            Expr(:call, $(escaped_func), $(escaped_args...), $(escaped_kwargs...)),
            $(QuoteNode(source)),
            $(QuoteNode(negate))
        )
    end

    return testret
end


# DISPLAYED FUNCTION
function _is_displayed_func(ex, kws)
    if !isa(ex, Expr) 
        return false
    elseif ex.head === :call && ex.args[1] ∈ DISPLAYED_FUNCS
        return length(ex.args) >= 2 && all(a -> !_is_splat(a), ex.args[2:end])
    elseif ex.head === :. && ex.args[1] ∈ DISPLAYED_FUNCS
        return length(ex.args[2].args) >= 1 && all(a -> !_is_splat(a), ex.args[2].args)
    else
        return false
    end
end

function _result_displayed_func(ex, kws, source, negate)
    # Treat .≈ and .≉ as special case, because they are not functions that can be vectorized
    if ex.head === :call && ex.args[1] ∈ (:.≈, :.≉)
        escaped_args, escaped_kwargs = _get_escaped_args(ex.args[2:end], kws)
    end
    
    # Otherwise, we can just vectorize the call
    ex = Expr(:., ex.args[1], Expr(:tuple, ex.args[2:end]...))
    escaped_func = QuoteNode(ex.args[1])
    escaped_args, escaped_kwargs = _get_escaped_args(ex.args[2].args, kws)

    return quote
        _eval_testall_displayed_func(
            Expr(:., $(escaped_func), Expr(:tuple, $(escaped_args...), $(escaped_kwargs...))),
            $(QuoteNode(source)),
            $(QuoteNode(negate))
        )
    end
end

function _eval_testall_displayed_func(ex::Expr, source::LineNumberNode, negate::Bool=false)

    # Extract the arguments which are presumably broadcasted
    terms = [a for a in ex.args[2].args if !isa(a, Expr)]

    # Create a quoted (unvectorized) expression for pretty-printing failures.
    quoted_ex = Expr(:call, ex.args[1], zeros(Bool, length(terms))...) # args

    # Evaluate to get broadcasted bit array, and negate if necessary:
    bitarray = eval(ex)

    # Get broadcasted terms for accessing individual elements
    broadcasted_terms = Base.broadcasted(tuple, terms...)

    # Function to print the unvectorized expression with broadcasted terms spliced in.
    failure_printer = (io, idx) -> begin
        terms = broadcasted_terms[idx]
        for i in eachindex(terms)
            quoted_ex.args[1+i] = terms[i]
        end
        print(io, quoted_ex)
    end

    msg = _pretty_print_failures(bitarray, failure_printer, negate)

    return Returned(msg === nothing, msg, source)
end

function _is_anonymous_map(ex, kws)
    return isa(ex, Expr) && ex.head === :->
end

function _result_anonymous_map(ex, kws, source, negate)
    # Check that there's an extra keyword argument, for the second argument of map
    if length(kws) == 0
        error("invalid test macro call: no expression given for mapping")
    elseif length(kws) > 1
        error("invalid test macro call: unused arguments $(join(kws, " "))")
    end

    # Create a mapping expression
    return quote
        _eval_testall_map(
            Expr(:call, :map, $(esc(ex)), $(esc(kws[1]))),
            $(QuoteNode(source)), 
            $(QuoteNode(negate))
        )
    end
end

function _eval_testall_map(ex::Expr, source::LineNumberNode, negate::Bool=false)

    terms = ex.args[3]
    
    # Evaluate to get broadcasted bit array, and negate if necessary:
    bitarray = eval(ex)

    # Function to print the unvectorized expression with broadcasted terms spliced in.
    failure_printer = (io, idx) -> begin
        print(io, "f(", terms[idx], ")")
    end

    msg = _pretty_print_failures(bitarray, failure_printer, negate)

    return Returned(msg === nothing, msg, source)
end

# FALLBACK 
function _result_fallback(ex, kws, source)
    if length(kws) > 0
        error("invalid test macro call: unused arguments $(join(kws, " "))")
    end
    return :(
        _eval_testall_fallback(
            $(esc(ex)),
            $(QuoteNode(source))
        )
    )
end

function _eval_testall_fallback(@nospecialize(bitarray), source::LineNumberNode)
    msg = _pretty_print_failures(bitarray, (io, idx) -> nothing, false)
    return Returned(msg === nothing, msg, source)
end


# Finally
function get_test_all_result(ex, kws, source, quoted=false)

    orig_ex = ex
    ex, negate = _get_preprocessed_expr(ex, kws...)

    if _is_comparison(ex, kws)
        @info "comparison"
        testret = _result_comparison(ex, kws, source, negate)
        quoted_ex = Expr(:call, :all, ex)
    elseif _is_approx_specialcase(ex, kws)
        @info "special case ≈ or ≉"
        testret = _result_approx_specialcase(ex, kws, source, negate)
        quoted_ex = ex
    elseif _is_displayed_func(ex, kws)
        @info "displayed func"
        testret = _result_displayed_func(ex, kws, source, negate)
        quoted_ex = ex
    elseif _is_anonymous_map(ex, kws)
        @info "mapped anonymous"
        testret = _result_anonymous_map(ex, kws, source, negate)
        quoted_ex = ex
    else 
        @info "fallback"
        testret = _result_fallback(orig_ex, kws, source)
        quoted_ex = ex
    end

    if negate
        quoted_ex = Expr(:call, :.!, quoted_ex)
    end

    result = quote
        try
            $testret
        catch _e
            _e isa InterruptException && rethrow()
            Threw(_e, Base.current_exceptions(), $(QuoteNode(source)))
        end
    end

    result, quoted_ex
end

"""
    @test_all ex
    @test_all 
"""
macro test_all(ex, kws...) #TODO(tpapalex): add 'quoted' argument
    kws, broken, skip = extract_broken_skip_keywords(kws...)
    kws, quoted = extract_keyword(:quoted, kws...)

    result, quoted_ex = get_test_all_result(ex, kws, __source__, quoted)
    quoted_ex = Expr(:inert, quoted_ex)
    quote 
        if $(length(skip) > 0 && esc(skip[1]))
            record(get_testset(), Broken(:skipped, $quoted_ex))
        else
            let _do = $(length(broken) > 0 && esc(broken[1])) ? do_broken_test : do_test
                _do($result, $quoted_ex)
            end
        end
    end
end

a = [1,2,3]
b = [1,2,5]
@test_all a == error()

