
const comparison_prec = Base.operator_precedence(:(==))

 TEST_ALL_DISPLAYED = (
    :isequal,
    :isapprox,
    :occursin,
    :startswith,
    :endswith,
    :isempty,
    :contains,
    :≈, :.≈,
    :≉, :.≉,
)

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

function _pretty_print_failures(@nospecialize(bitarray), failure_printer, negate=false; max_vals=10)

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

function _escaped_arguments_call(ex_args, kws)
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
                error("invalid test macro call: unable to pretty print with parameter $a. Use simple=true")
            end
        end
    end

    # Positional arguments
    for a in ex_args
        isa(a, Expr) && a.head in (:kw, :parameters) && continue
        if isa(a, Expr) && a.head === :...
            error("invalid test macro call: unable to pretty print with argument $a. Use simple=true")
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

function _eval_testall_fallback(@nospecialize(bitarray), source::LineNumberNode)
    msg = _pretty_print_failures(bitarray, (io, idx) -> nothing, false)
    return Returned(msg === nothing, msg, source)
end



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
        (ex.args[1] === :(==) || Base.operator_precedence(ex.args[1]) == comparison_prec)

        ex = Expr(:comparison, ex.args[2], ex.args[1], ex.args[3])

    # Mark <: and >: as :comparison expressions
    elseif isa(ex, Expr) && length(ex.args) == 2 &&
        !_is_splat(ex.args[1]) && !_is_splat(ex.args[2]) &&
        Base.operator_precedence(ex.head) == comparison_prec

        ex = Expr(:comparison, ex.args[1], ex.head, ex.args[2])

    # Mark .<: and .>: as :comparison expressions
    elseif isa(ex, Expr) &&  ex.head === :call && length(ex.args) == 3 && 
        !_is_splat(ex.args[2]) && !_is_splat(ex.args[3]) && 
        (ex.args[1] === :.<: || ex.args[1] === :.>:)

        ex = Expr(:comparison, ex.args[2], ex.args[1], ex.args[3])
    end

    return ex, negate
end

# Processing for comparison expressions
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
    return quote
        _eval_testall_comparison(
            Expr(:comparison, $(escaped_args...)),
            $(QuoteNode(source)),
            $(QuoteNode(negate))
        )
    end
end


# Processing for special case vectorized call .≈ or .≉ when extra kwargs...
function _is_approx_specialcase(ex, kws)
    OPS = (:≈, :≉, :.≈, :.≉)
    return isa(ex, Expr) && 
        ex.head === :call && 
        !_is_splat(ex.args[2]) && 
        !_is_splat(ex.args[3]) &&
        ex.args[1] ∈ OPS && 
        length(kws) > 0
end

function _result_approx_specialcase(ex, kws, source, negate=false)
    # Replace operator with vectorized version
    if first(string(ex.args[1])) != '.'
        ex.args[1] = Symbol(:., ex.args[1])
    end
    escaped_func = QuoteNode(ex.args[1])
    escaped_args, escaped_kwargs = _escaped_arguments_call(ex.args[2:end], kws)
    return quote
        _eval_testall_comparison(
            Expr(:call, $(escaped_func), $(escaped_args...), $(escaped_kwargs...)),
            $(QuoteNode(source)),
            $(QuoteNode(negate))
        )
    end
end

# Processing for fall back case
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

function _is_displayed_func(ex, kws)
    if isa(ex, Expr) && 
        (ex.head === :call || ex.head === :.) && 
        ex.args[1] ∈ TEST_ALL_DISPLAYED
        return true
    else
        return false
    end
end

function _result_displayed_func(ex, kws, source, negate)
    # Vectorize if unvectorized
    if ex.head === :call
        ex = Expr(:., ex.args[1], Expr(:tuple, ex.args[2:end]...))
    end

    escaped_func = QuoteNode(ex.args[1])
    escaped_args, escaped_kwargs = _escaped_arguments_call(ex.args[2].args, kws)

    return quote
        _eval_testall_displayed_func(
            Expr(:., $(escaped_func), Expr(:tuple, $(escaped_args...), $(escaped_kwargs...))),
            $(QuoteNode(source)),
            $(QuoteNode(negate))
        )
    end
end

function get_test_all_result(ex, kws, source)

    orig_ex = ex
    ex, negate = _get_preprocessed_expr(ex, kws...)

    if _is_comparison(ex, kws)
        @info "comparison"
        testret = _result_comparison(ex, kws, source, negate)
    elseif _is_approx_specialcase(ex, kws)
        @info "special case ≈ or ≉"
        testret = _result_approx_specialcase(ex, kws, source, negate)
    elseif _is_displayed_func(ex, kws)
        @info "displayed func"
        testret = _result_displayed_func(ex, kws, source, negate)
    else # fallback
        @info "fallback"
        testret = _result_fallback(orig_ex, kws, source)
    end

    return testret
end

"""
    @test_all ex

Note that any comparison operators in 'ex', as well as calls to the functions 
$(join("'" .* string.(TEST_ALL_DISPLAYED) .* "'", ", "))
will be automatically converted to their vectorized counterparts (unless simple=true).
"""
macro test_all(ex, kws...)
    res = get_test_all_result(ex, kws, __source__)
    quote 
        res = $(res)
        if isa(res, Test.Returned)
            println(res.data)
            return 
        else
            return res
        end
    end
end

function _eval_testall_displayed_func(ex::Expr, source::LineNumberNode, negate::Bool=false)
    #dump(ex.args[2].args[1])
    #func_str = 
    terms = [a for a in ex.args[2].args if !isa(a, Expr)]
    dump(terms)
    return Returned(true, nothing, source)
end

using Test
const Returned = Test.Returned

a = [1, 2, 3]
b = [1, 2, 3.0001]
TOL = 1e-5

@test_all ≈(a, b)

if false

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

end