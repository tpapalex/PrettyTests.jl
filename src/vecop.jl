
const comparison_prec = Base.operator_precedence(:(==))

const VECOP_DISPLAY_FUNCS = (
    :isequal,
    :isapprox,
    :occursin,
    :startswith,
    :endswith,
    :isempty,
    :contains,
    :≈,
    :≉,
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


function pretty_print_vecop_failures(@nospecialize(bitarray), failure_printer, negate=false; max_vals=10)

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



function eval_test_vecop_comparison(ex::Expr, source::LineNumberNode, negate::Bool=false)
    if ex.head === :comparison # Most calls have been normalized to this form
        terms = ex.args[1:2:end]
        ops = ex.args[2:2:end]
    else # ex.head === :call, only for .≈ and .≉ with extra kwargs
        dump(ex)
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

    msg = pretty_print_vecop_failures(bitarray, failure_printer, negate)

    return Returned(msg === nothing, msg, source)
end

function eval_test_vecop_fallback(@nospecialize(bitarray), source::LineNumberNode)
    msg = pretty_print_vecop_failures(bitarray, (io, idx) -> nothing, false)
    return Returned(msg === nothing, msg, source)
end

@nospecialize

function get_test_vecop_result(ex, kws, source)

    negate = QuoteNode(false)
    orig_ex = ex

    # Evaluate not wrapped functions separately for pretty-printing failures
    if isa(ex, Expr) && ex.head === :call && ex.args[1] === :!
        error("invalid test macro call: use vectorized operator .!")
    elseif isa(ex, Expr) && ex.head === :call && ex.args[1] === :.!
        negate = QuoteNode(true)
        ex = ex.args[2]
    end

    # Normalize non-comparison operator :calls to :comparison expressions
    is_splat = x -> isa(x, Expr) && x.head === :...
    if isa(ex, Expr) && ex.head === :call && length(ex.args) == 3 && length(kws) == 0 &&
        first(string(ex.args[1])) != "." && !is_splat(ex.args[2]) && !is_splat(ex.args[3]) && 
        (ex.args[1] === :(==) || Base.operator_precedence(ex.args[1]) == comparison_prec)

        ex = Expr(:comparison, ex.args[2], ex.args[1], ex.args[3])

    # Mark <: and >: as :comparison expressions
    elseif isa(ex, Expr) && length(ex.args) == 2 &&
        !is_splat(ex.args[1]) && !is_splat(ex.args[2]) &&
        Base.operator_precedence(ex.head) == comparison_prec

        ex = Expr(:comparison, ex.args[1], ex.head, ex.args[2])
    end

    if isa(ex, Expr) && ex.head === :comparison
        # Check that all operators are vectorized
        for i in 2:2:length(ex.args)
            if string(ex.args[i])[1] != '.'
                error("invalid test macro call: use vectorized operator .$(ex.args[i])")
            end
        end

        if length(kws) > 0
            error("invalid test macro call: extra arguments $(join(kws, " "))")
        end

        # Avoid multiple evaluations by recreating expression; quote operators, escape quantities.
        escaped_args = [i % 2 == 1 ? esc(arg) : QuoteNode(arg) for (i, arg) in enumerate(ex.args)]
        testret = :(eval_test_vecop_comparison(
            Expr(:comparison, $(escaped_args...)),
            $(QuoteNode(source)),
            $negate,
        ))

    elseif isa(ex, Expr) && ex.head === :call && ex.args[1] in VECOP_DISPLAY_FUNCS
        # If unvectorized display function was used, fail and suggest vectorized version
        if ex.args[1] === :≈ || ex.args[1] === :≉
            fstr = "operator ." * string(ex.args[1])
        else
            fstr = "function " * string(ex.args[1]) * ".()"
        end
        error("invalid test macro call: use vectorized $fstr")

    elseif isa(ex, Expr) && ex.head === :call &&
        !is_splat(ex.args[2]) && !is_splat(ex.args[3]) &&
        (ex.args[1] === :.≈ || ex.args[1] === :.≉) 

        # Special case: vectorized .≈ and .≉ with extra kwargs (if no kwargs, should have
        # been normalized to comparison expression above)

        # Avoid multiple evaluations by recreating expression; quote operator, escape quantities.
        escaped_func = QuoteNode(ex.args[1])
        escaped_args = []
        escaped_kwargs = []

        # Keywords that occur before `;`
        for a in ex.args[2:end]
            if isa(a, Expr) && a.head === :kw
                push!(escaped_kwargs, Expr(:kw, QuoteNode(a.args[1]), esc(a.args[2])))
            end
        end

        # Keywords that occur after ';'
        parameters_expr = ex.args[2]
        if isa(parameters_expr, Expr) && parameters_expr.head === :parameters
            for a in parameters_expr.args
                if isa(a, Expr) && a.head === :kw
                    push!(escaped_kwargs, :(Expr(:kw, $(QuoteNode(a.args[1])), $(esc(a.args[2])))))
                elseif isa(a, Expr) && a.head === :...
                    push!(escaped_kwargs, :(Expr(:..., $(esc(a.args[1])))))
                end
            end
        end

        # Positional arguments
        for a in ex.args[2:end]
            isa(a, Expr) && a.head in (:kw, :parameters) && continue
            if isa(a, Expr) && a.head === :...
                error("invalid test macro call: cannot pretty print with splat arguments. Use simple=true")
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
        
        testret = :(eval_test_vecop_comparison(
            Expr(:call, $(escaped_func), $(escaped_args...), $(escaped_kwargs...)),
            $(QuoteNode(source)),
            $negate
        ))

    elseif isa(ex, Expr) && ex.head === :. && ex.args[1] ∈ VECOP_DISPLAY_FUNCS

        @assert ex.head === :. && isa(ex.args[2], Expr) && ex.args[2].head === :tuple

        testret = :(nothing)

    else
        testret = :(eval_test_vecop_fallback($(esc(orig_ex)), $(QuoteNode(source))))
    end

    result = quote
        $testret
    end
    return result
end
