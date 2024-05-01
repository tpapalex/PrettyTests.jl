
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


# Internal function called on a test macros kws... to extract a named keyword
function extract_keyword(nm, kws...)
    # Collect the broken/skip keywords and remove them from the rest of keywords
    exs = [kw.args[2] for kw in kws 
           if isa(kw, Expr) && kw.head == :(=) && kw.args[1] === nm]
    kws = filter(kw -> !isa(kw, Expr) || (kw.args[1] !== nm), kws)

    if length(exs) > 1
        error("invalid test macro call: cannot set $nm keyword multiple times")
    end
    return kws, exs
end