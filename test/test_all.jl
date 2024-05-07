@testset "vecop.jl" begin

    @testset "extract_negation(ex)" begin
        cases = [
            :(a),
            :(a || b),
            :(a && b || c),
            :(g(x)),
            :(x == y),
            :(x == y == z),
            :(x ≈ y),
            :(a && b || c && g(x .+ y) || (x ≈ y)),
            :(x -> x == 1)
        ]

        @testset "$ex" for ex in cases
            ex! = Expr(:call, :!, ex)
            @test TM.extract_negation(ex!) == (ex, true)

            ex!! = Expr(:call, :!, ex!)
            @test TM.extract_negation(ex!!) == (ex, false)
        end

        cases = [
            :(a),
            :(a .|| b),
            :(a .&& b .|| c),
            :(g.(x)),
            :(x .== y),
            :(z .== y .== z),
            :(x .≈ y),
            :(a .&& b .|| c .&& g.(x .+ y) .|| (x .≈ y))
        ]

        @testset "$ex" for ex in cases
            ex! = Expr(:call, :.!, ex)
            @test TM.extract_negation(ex!) == (ex, true)

            ex!! = Expr(:call, :.!, ex!)
            @test TM.extract_negation(ex!!) == (ex, false)
        end
    end

    @testset "add_keywords!(ex, kws)" begin
        # Regular tests
        cases = [
            # Comparisons
            :(a == b)      => ()               => :(a == b),
            :(a .== b)     => ()               => :(a .== b),
            # Functions calls
            :(g())         => ()               => :(g()),
            :(a ≈ b)       => (:(x = 1),)      => :(≈(a, b, x = 1)),
            :(g(x))        => (:(y = 1),)      => :(g(x, y = 1)),
            :(g())         => (:(x=1), :(y=y)) => :(g(x=1, y=y)),
            # Vectorized calls
            :(g.())        => () => :(g.()),
            :(a .≈ b)      => (:(x = 1),)      => :(.≈(a, b, x = 1)),
            :(g.(x))       => (:(y = 1),)      => :(g.(x, y = 1)),
        ]

        @testset "$ex" for (ex, (kws, res)) in cases
            @test TM.add_keywords!(ex, kws) == res
        end

        # Does not support kwargs error
        cases = [
            :(a),
            :(a == b == c), 
            :(a .== b .== c),
            :(a && b), 
            :(a || b),
            :((a,b,c)),
            :([a,b,c]),
            :(a <: b), 
            :(a >: b),
        ]

        @testset "$ex" for ex in cases
            @test_throws "does not accept keyword arguments" TM.add_keywords!(ex, :(x=1))
        end

        # invalid keyword error
        cases = [
            (:(a),),
            (:(a==1),),
            (:(g(x)),),
            (:(a=1), :(b)),
            (:(a=1), :(g(x)))
        ]

        @testset "$kws" for kws in cases
            @test_throws "is not a valid keyword argument" TM.add_keywords!(:(a == b), kws)
        end
     end

     @testset "_preprocess(ex)" begin

        cases = [
            # Converted to comparisons
            :(a == b) => Expr(:comparison, :a, :(==), :b),
            :(a .== b) => Expr(:comparison, :a, :.==, :b),
            :(≈(a, b)) => Expr(:comparison, :a, :≈, :b),
            :(a .≈ b) => Expr(:comparison, :a, :.≈, :b),
            :(a ∈ b) => Expr(:comparison, :a, :∈, :b),
            :(a .⊆ b) => Expr(:comparison, :a, :.⊆, :b),
            :(a <: b) => Expr(:comparison, :a, :<:, :b),
            :(a .<: b) => Expr(:comparison, :a, :.<:, :b),
            :(a >: b) => Expr(:comparison, :a, :>:, :b),
            :(a .>: b) => Expr(:comparison, :a, :.>:, :b),
            # Displayable calls
            :(≈(a,b;atol=1)) => :(≈(a,b,atol=1)),
            :(.≈(a,b;atol=1)) => :(.≈(a,b,atol=1)),
            :(isapprox(a,b;atol=1)) => :(isapprox(a,b,atol=1)),
            :(isapprox.(a,b;atol=1)) => :(isapprox.(a,b,atol=1)),
            :(isnan(x;a=1)) => :(isnan(x,a=1)),
            :(isnan.(x;a=1)) => :(isnan.(x,a=1)),
            :(isnan(x;a=1,b=1)) => :(isnan(x,a=1,b=1)),
            :(isnan.(x;a=1,b=1)) => :(isnan.(x,a=1,b=1)),
            :(isnan(x,a=1,b=1;c=1,d=1)) => :(isnan(x,a=1,b=1,c=1,d=1)),
            :(isnan.(x,a=1,b=1;c=1,d=1)) => :(isnan.(x,a=1,b=1,c=1,d=1)),
            # No change
            :(a) => :(a),
            :(a && b) => :(a && b),
            :(a .|| b) => :(a .|| b),
            :(g(x)) => :(g(x)),
            :(g(x, a=1; b=1)) => :(g(x, a=1; b=1)),
            :(g.(x)) => :(g.(x)),
            :(g.(x, a=1; b=1)) => :(g.(x, a=1; b=1)),
            # Not keywordized because no positional arguments
            :(isnan(;a=1)) => :(isnan(;a=1)),
            :(isnan.(;a=1)) => :(isnan.(;a=1)),
            :(isnan(;a=1,b=1)) => :(isnan(;a=1,b=1)),
            :(isnan.(a=1;b=1)) => :(isnan.(a=1;b=1)),
            # Not keywordized because already parameter or splat arguments
            :(≈(a, b, atol=1)) => :(≈(a, b, atol=1)),
            :(isnan(x, a=1)) => :(isnan(x, a=1)), 
            :(isnan.(x, a=1)) => :(isnan.(x, a=1)), 
            :(isnan(x = 1)) => :(isnan(x = 1)),
            :(isnan.(x = 1)) => :(isnan.(x = 1))
        ]

        @testset "$ex" for (ex, res) in cases
            @test TM._preprocess(ex) == res
        end
     end


    @testset "expression classifiers: is...(ex)" begin

        cases = [
            # Negation
            :(!a) => :negation,
            :(.!g.(x)) => :negation, 
            :(!(a .|| b)) => :negation,
            # Logical
            :(a && b) => :logical,
            :(a && b || c) => :logical,
            :(a .|| (g.(x) && c)) => :logical,
            # Comparison
            :(a == b) => :comparison,
            :(a .== b) => :comparison,
            :(a ≈ b) => :comparison,
            :(a <: b) => :comparison,
            :(a .>: b) => :comparison,
            # Approx special case
            :(≈(a, b, a=1)) => :argsapprox,
            :(≉(a, b, a=1)) => :argsapprox,
            :(.≈(a, b; atol=1)) => :argsapprox,
            :(.≉(a, b; atol=1)) => :argsapprox,
            :(≈()) => :fallback, # incorrect number of positional arguments
            :(.≈(a, atol=1)) => :fallback, # incorrect number of positional arguments
            :(≉(a, b, c, atol=1)) => :fallback, # incorrect number of positional arguments
            :(≈(a, b..., atol=1)) => :fallback, # splat argument
            # Displayable function
            :(isnan(x)) => :displaycall,
            :(isreal.(x)) => :displaycall,
            :(occursin("a", b)) => :displaycall,
            :(contains.(r"a", "b")) => :displaycall,
            :(isinf()) => :fallback, # no positional arguments
            :(isnan.(a=1)) => :fallback, # no positional arguments
            :(isapprox(a..., atol=1)) => :fallback, # splat argument
            # Fall back
            :(1) => :fallback, 
            :(1:3) => :fallback,
            :((1,2,3)) => :fallback,
            :([1,2,3]) => :fallback,
            :([1 2 3]) => :fallback,
            :(Ref(1:3)) => :fallback,
            :(a) => :fallback,
            :(g(x)) => :fallback,
        ]

        @testset "is_$res($ex)" for (ex, res) in cases
            ex = TM._preprocess(ex)
            if res === :logical
                @test TM.is_logical(ex)
            elseif res === :negation
                @test TM.is_negation(ex)
            elseif res === :comparison
                @test TM.is_comparison(ex)
            elseif res === :argsapprox
                @test TM.is_argsapprox(ex)
            elseif res === :displaycall
                @test TM.is_displaycall(ex)
            elseif res === :fallback
                @test TM.is_fallback(ex)
            end
        end
    end

    @testset "update_escaped!()" begin 
    
        @testset "negation" begin
            cases = [
                :(!a) =>  (:(!ARG[1]),  "!a",  "!{1:s}"), 
                :(.!a) => (:(.!ARG[1]), ".!a", "!{1:s}"),
            ]

            @testset "$ex" for (ex, res) in cases
                # Pre-process and get expected results
                res_mod_ex, res_str_ex, res_fmt_ex = res
                ex, res_mod_ex = TM._preprocess(ex), TM._preprocess(res_mod_ex)
                
                @test TM.is_negation(ex)
                @test TM.is_negation(res_mod_ex)

                # Updated escaped terms with outmost = true
                args = []
                mod_ex, str_ex, fmt_ex, fmt_kw = TM.update_escaped!(args, deepcopy(ex), isoutmost=true)
                @test mod_ex == res_mod_ex
                @test str_ex == res_str_ex
                @test fmt_ex == res_fmt_ex
                @test fmt_kw == ""
                @test args   == [esc(:a)]

                # Updated escaped terms with outmost = false
                args = []
                mod_ex, str_ex, fmt_ex, fmt_kw = TM.update_escaped!(args, deepcopy(ex), isoutmost=false)
                @test mod_ex == res_mod_ex
                @test str_ex == res_str_ex 
                @test fmt_ex == res_fmt_ex
                @test fmt_kw == ""
                @test args   == [esc(:a)]
            end
        end


        @testset "logical" begin
            cases = [
                :(a  && b) => (:(ARG[1] && ARG[2]),                           
                               [:a, :b],            
                               "a && b",                
                               "{1:s} && {2:s}"),   
                :(a .|| b) => (:(ARG[1] .|| ARG[2]),                           
                               [:a, :b],           
                               "a .|| b",               
                               "{1:s} || {2:s}"),   
                :(a  && b  && c  || d) => (:(ARG[1]  && ARG[2]  && ARG[3]  || ARG[4]), 
                                        [:a, :b, :c, :d],
                                        "a && b && c || d",
                                        "{1:s} && {2:s} && {3:s} || {4:s}"),
                :(a .&& b .&& c .|| d) => (:(ARG[1] .&& ARG[2] .&& ARG[3] .|| ARG[4]), 
                                        [:a, :b, :c, :d],
                                        "a .&& b .&& c .|| d",
                                        "{1:s} && {2:s} && {3:s} || {4:s}"),
            ]

            @testset "$ex" for (ex, res) in cases
                # Pre-process and get expected results
                res_mod_ex, res_args, res_str_ex, res_fmt_ex = res
                res_args = esc.(res_args)
                ex, res_mod_ex = TM._preprocess(ex), TM._preprocess(res_mod_ex)

                @test TM.is_logical(ex)
                @test TM.is_logical(res_mod_ex)

                # Updated escaped terms with outmost = true
                args = []
                mod_ex, str_ex, fmt_ex, fmt_kw = TM.update_escaped!(args, deepcopy(ex), isoutmost=true)
                @test mod_ex == res_mod_ex
                @test str_ex == res_str_ex
                @test fmt_ex == res_fmt_ex
                @test args   == res_args
                @test fmt_kw == ""

                # Updated escaped terms with outmost = false
                args = []
                mod_ex, str_ex, fmt_ex, fmt_kw = TM.update_escaped!(args, deepcopy(ex), isoutmost=false)
                @test mod_ex == res_mod_ex
                @test str_ex == "(" * res_str_ex * ")"
                @test fmt_ex == "(" * res_fmt_ex * ")"
                @test args   == res_args
                @test fmt_kw == ""
            end
        end

        @testset "comparison" begin
            cases = [
                :(a == b) => (:(ARG[1] == ARG[2]),            
                              "{1:s} == {2:s}",
                              [:a, :b]),
                :(a .∈ b) => (:(ARG[1] .∈ ARG[2]),            
                              "{1:s} ∈ {2:s}",
                              [:a, :b]),
                :(a ≈ b .> c)   => (:(ARG[1] ≈ ARG[2] .> ARG[3]),   
                                    "{1:s} ≈ {2:s} > {3:s}",
                                    [:a, :b, :c]),
                :(a <: b .<: c) => (:(ARG[1] <: ARG[2] .<: ARG[3]), 
                                    "{1:s} <: {2:s} <: {3:s}",
                                    [:a, :b, :c]),
            ]

            @testset "$ex" for (ex, res) in cases
                # Pre-process and get expected results
                res_mod_ex, res_fmt_ex, res_args = res
                ex, res_mod_ex = TM._preprocess(ex), TM._preprocess(res_mod_ex)
                res_str_ex = string(ex)

                @test TM.is_comparison(ex)
                @test TM.is_comparison(res_mod_ex)

                # Updated escaped terms with outmost = true
                args = []
                mod_ex, str_ex, fmt_ex, fmt_kw = TM.update_escaped!(args, deepcopy(ex), isoutmost=true)
                @test mod_ex == res_mod_ex
                @test str_ex == res_str_ex
                @test fmt_ex == res_fmt_ex
                @test args   == esc.(res_args)
                @test fmt_kw == ""

                # Updated escaped terms with outmost = false
                args = []
                mod_ex, str_ex, fmt_ex, fmt_kw = TM.update_escaped!(args, deepcopy(ex), isoutmost=false)
                @test mod_ex == res_mod_ex
                @test str_ex == "(" * res_str_ex * ")"
                @test fmt_ex == "(" * res_fmt_ex * ")"
                @test args   == esc.(res_args)
                @test fmt_kw == ""
            end
        end

        @testset "argsapprox" begin
            cases_outmost = [
                :(≈(a, b, atol=TOL)) => (
                    :(≈(ARG[1], ARG[2], atol=ARG[3].x)), 
                    "≈(a, b, atol = TOL)",
                    "{1:s} ≈ {2:s}",
                    "atol = {3:s}",
                    [:a, :b, :(Ref(TOL))],
                ),
                :(.≉(a, b, rtol=100*1e-8, atol=TOL)) => (
                    :(.≉(ARG[1], ARG[2], rtol=ARG[3].x, atol=ARG[4].x)), 
                    ".≉(a, b, rtol = 100 * 1.0e-8, atol = TOL)",
                    "{1:s} ≉ {2:s}", 
                    "rtol = {3:s}, atol = {4:s}", 
                    [:a, :b, :(Ref(100*1e-8)), :(Ref(TOL))],
                )
            ]

            @testset "(outer) $ex" for (ex, res) in cases_outmost
                # Pre-process and get expected results
                res_mod_ex, res_str_ex, res_fmt_ex, res_fmt_kw, res_args = res
                ex, res_mod_ex = TM._preprocess(ex), TM._preprocess(res_mod_ex)
                res_str_ex = string(ex)

                @test TM.is_argsapprox(ex)
                @test TM.is_argsapprox(res_mod_ex)

                # Updated escaped terms with outmost = true
                args = []
                mod_ex, str_ex, fmt_ex, fmt_kw = TM.update_escaped!(args, deepcopy(ex), isoutmost=true)
                @test mod_ex == res_mod_ex
                @test str_ex == res_str_ex
                @test fmt_ex == res_fmt_ex
                @test args   == esc.(res_args)
                @test fmt_kw == res_fmt_kw
            end            

            cases_inner = [
                :(≈(a, b, atol=TOL)) => (
                    :(≈(ARG[1], ARG[2], atol=ARG[3].x)), 
                    "≈(a, b, atol = TOL)",
                    "≈({1:s}, {2:s}, atol = {3:s})", 
                    "",
                    [:a, :b, :(Ref(TOL))],
                ),
                :(.≉(a, b, rtol=100*1e-8, atol=TOL)) => (
                    :(.≉(ARG[1], ARG[2], rtol=ARG[3].x, atol=ARG[4].x)), 
                    ".≉(a, b, rtol = 100 * 1.0e-8, atol = TOL)",
                    "≉({1:s}, {2:s}, rtol = {3:s}, atol = {4:s})", 
                    "",
                    [:a, :b, :(Ref(100*1e-8)), :(Ref(TOL))],
                )
            ]

            @testset "(inner) $ex" for (ex, res) in cases_inner
                # Pre-process and get expected results
                res_mod_ex, res_str_ex, res_fmt_ex, res_fmt_kw, res_args = res
                ex, res_mod_ex = TM._preprocess(ex), TM._preprocess(res_mod_ex)
                res_str_ex = string(ex)

                @test TM.is_argsapprox(ex)
                @test TM.is_argsapprox(res_mod_ex)

                # Updated escaped terms with outmost = true
                args = []
                mod_ex, str_ex, fmt_ex, fmt_kw = TM.update_escaped!(args, deepcopy(ex), isoutmost=false)
                @test mod_ex == res_mod_ex
                @test str_ex == res_str_ex
                @test fmt_ex == res_fmt_ex
                @test args   == esc.(res_args)
                @test fmt_kw == res_fmt_kw
            end   
        end


        @testset "displaycall" begin
            cases_outmost = [
                :(isnan(a)) => (
                    :(isnan(ARG[1])), 
                    "isnan(a)",
                    "isnan({1:s})",
                    "",
                    [:a],
                ),
                :(isapprox(a, b, atol=TOL)) => (
                    :(isapprox(ARG[1], ARG[2], atol=ARG[3].x)), 
                    "isapprox(a, b, atol = TOL)",
                    "isapprox({1:s}, {2:s})",
                    "atol = {3:s}",
                    [:a, :b, :(Ref(TOL))],
                ),
                :(isapprox.(a, b, rtol=100*1e-8, atol=TOL)) => (
                    :(isapprox.(ARG[1], ARG[2], rtol=ARG[3].x, atol=ARG[4].x)), 
                    "isapprox.(a, b, rtol = 100 * 1.0e-8, atol = TOL)",
                    "isapprox({1:s}, {2:s})", 
                    "rtol = {3:s}, atol = {4:s}", 
                    [:a, :b, :(Ref(100*1e-8)), :(Ref(TOL))],
                ),
            ]

            @testset "(outer) $ex" for (ex, res) in cases_outmost
                # Pre-process and get expected results
                res_mod_ex, res_str_ex, res_fmt_ex, res_fmt_kw, res_args = res
                ex, res_mod_ex = TM._preprocess(ex), TM._preprocess(res_mod_ex)
                res_str_ex = string(ex)

                @test TM.is_displaycall(ex)
                @test TM.is_displaycall(res_mod_ex)

                # Updated escaped terms with outmost = true
                args = []
                mod_ex, str_ex, fmt_ex, fmt_kw = TM.update_escaped!(args, deepcopy(ex), isoutmost=true)
                @test mod_ex == res_mod_ex
                @test str_ex == res_str_ex
                @test fmt_ex == res_fmt_ex
                @test args   == esc.(res_args)
                @test fmt_kw == res_fmt_kw
            end            

            cases_inner = [
                :(isnan(a)) => (
                    :(isnan(ARG[1])), 
                    "isnan(a)",
                    "isnan({1:s})",
                    "",
                    [:a],
                ),
                :(isapprox(a, b, atol=TOL)) => (
                    :(isapprox(ARG[1], ARG[2], atol=ARG[3].x)), 
                    "isapprox(a, b, atol = TOL)",
                    "isapprox({1:s}, {2:s}, atol = {3:s})",
                    "",
                    [:a, :b, :(Ref(TOL))],
                ),
                :(isapprox.(a, b, rtol=100*1e-8, atol=TOL)) => (
                    :(isapprox.(ARG[1], ARG[2], rtol=ARG[3].x, atol=ARG[4].x)), 
                    "isapprox.(a, b, rtol = 100 * 1.0e-8, atol = TOL)",
                    "isapprox({1:s}, {2:s}, rtol = {3:s}, atol = {4:s})", 
                    "", 
                    [:a, :b, :(Ref(100*1e-8)), :(Ref(TOL))],
                ),
            ]

            @testset "(inner) $ex" for (ex, res) in cases_inner
                # Pre-process and get expected results
                res_mod_ex, res_str_ex, res_fmt_ex, res_fmt_kw, res_args = res
                ex, res_mod_ex = TM._preprocess(ex), TM._preprocess(res_mod_ex)
                res_str_ex = string(ex)

                @test TM.is_displaycall(ex)
                @test TM.is_displaycall(res_mod_ex)

                # Updated escaped terms with outmost = true
                args = []
                mod_ex, str_ex, fmt_ex, fmt_kw = TM.update_escaped!(args, deepcopy(ex), isoutmost=false)
                @test mod_ex == res_mod_ex
                @test str_ex == res_str_ex
                @test fmt_ex == res_fmt_ex
                @test args   == esc.(res_args)
                @test fmt_kw == res_fmt_kw
            end   
        end

        @testset "update_escaped! - fallback" begin
            # Cases as outmost expression
            cases = [
                :(1),
                :(a), 
                :([1,2]), 
                :(g(x)), 
                :(g.(x,a=1;b=b)), 
                :(a .+ b),
            ]

            @testset "$ex" for ex in cases
                ex = TM._preprocess(ex)
                @test TM.is_fallback(ex)

                args = []
                mod_ex, str_ex, fmt_ex = TM.update_escaped!(args, deepcopy(ex), isoutmost=true)
                
                @test mod_ex == :(ARG[1])
                @test str_ex == string(ex)
                @test fmt_ex == "{1:s}"
                @test args == [esc(ex)]
            end
        end
    end

    @testset "_string_idxs()" begin
        I = CartesianIndex
        @test TM._string_idxs([1,2,3]) == ["1", "2", "3"]
        @test TM._string_idxs([1,10,100]) == ["  1", " 10", "100"]
        @test TM._string_idxs([I(1,1), I(1,10), I(100,1)]) == ["  1, 1", "  1,10", "100, 1"]
    end

    @testset "_string_failures()" begin
        
        msg = (io, idx) -> print(io, 2*idx)
        idxs = [1,2,3]
        exp = "\n    idx=[1]: 2\n    idx=[2]: 4\n    idx=[3]: 6"
        @test sprint(TM.print_failures, idxs, msg) == exp

        msg = (io, idx) -> print(io, sum(idx.I))
        idxs = CartesianIndex.([(1,1), (1,10), (10,1)])
        exp = "\n    idx=[ 1, 1]: 2\n    idx=[ 1,10]: 11\n    idx=[10, 1]: 11"
        @test sprint(TM.print_failures, idxs, msg) == exp

        # Wrap to 
        printfunc = (args...) -> TM.print_failures(args...; max_vals=4)
        msg = (io, idx) -> print(io, idx)
        idxs = 1:20
        exp = "\n    idx=[ 1]: 1\n    idx=[ 2]: 2\n    ⋮\n    idx=[19]: 19\n    idx=[20]: 20"
        @test sprint(printfunc, idxs, msg) == exp
    end


    @testset "eval_test_all()" begin
        destyle = x -> replace(x, r"\e\[\d+m" => "")
        struct TestStruct
            x::Symbol
        end

        @testset "invalid broadcast behaviour" begin
            f = (args...) -> TM.eval_test_all(args..., "", "", LineNumberNode(1))
            @test_throws "not same size as broadcasted terms () != (2,)" f(true, [[1,2]])
            @test_throws "not same size as broadcasted terms (2,) != (3,)" f([true, false], [[1,2,3], [1,2,3]])
            @test_throws "not same size as broadcasted terms (2,) != (3, 3)" f([true, false], [[1,2,3], [1 2 3]])
        end

        @testset "evaled is not array or bool" begin
            f = (evaled) -> TM.eval_test_all(evaled, [evaled], "", "", LineNumberNode(1))
            # Non-boolean non-array
            res = f(1)   
            @test res isa Test.Returned
            @test res.value isa String
            @test occursin("1 ===> Int64", destyle(res.value))

            res = f(:a)   
            @test res isa Test.Returned
            @test res.value isa String
            @test occursin("a ===> Symbol", destyle(res.value))

            res = f(TestStruct(:b))
            @test res isa Test.Returned
            @test res.value isa String
            @test occursin("TestStruct(:b) ===> TestStruct", destyle(res.value))
        end

        @testset "evaled is non-bool array" begin
            f = (evaled) -> TM.eval_test_all(evaled, [evaled], "", "", LineNumberNode(1))

            res = f([10,2])
            @test res isa Test.Returned
            @test res.value isa String
            @test occursin("Vector{Int64}(2) with 2 non-Boolean values.", res.value)
            @test occursin("idx=[1]: 10 ===> Int64", destyle(res.value))
            @test occursin("idx=[2]: 2 ===> Int64", destyle(res.value))

            res = f(Any[true, :a, false, TestStruct(:b)])
            @test res isa Test.Returned
            @test res.value isa String
            @test occursin("Vector{Any}(4) with 2 non-Boolean values.", res.value)
            @test occursin("idx=[2]: a ===> Symbol", destyle(res.value))
            @test occursin("idx=[4]: TestStruct(:b) ===> TestStruct", destyle(res.value))

            res = f(Any[false true :a])
            @test res isa Test.Returned
            @test res.value isa String
            @test occursin("Matrix{Any}(1×3) with 1 non-Boolean value.", res.value)
            @test occursin("idx=[1,3]: a ===> Symbol", destyle(res.value))
        end

        @testset "evaled is bool" begin
            f = (evaled) -> TM.eval_test_all(evaled, [evaled], "{1:s}", "", LineNumberNode(1))
            res = f(true)
            @test res isa Test.Returned
            @test res.value === true
            @test res.data === nothing

            res = f(false)
            @test res isa Test.Returned
            @test res.value === false
            @test res.data isa String
            @test occursin("Failed 1 test.", res.data)
            @test occursin("idx=[1]: false", destyle(res.data))

            f = (args...) -> TM.eval_test_all(args..., LineNumberNode(1))

            terms = [1, 1.00001, Ref(1e-3)]
            evaled = isapprox(terms[1], terms[2], atol=terms[3].x)
            fmt_ex = "isapprox({1:s}, {2:s})"
            fmt_kw = "atol = {3:s}"

            res = f(evaled, terms, fmt_ex, fmt_kw)
            @test res isa Test.Returned
            @test res.value === true
            @test res.data === nothing
            
            terms = [1, 1.00001, Ref(1e-8)]
            evaled = isapprox(terms[1], terms[2], atol=terms[3].x)
            fmt_ex = "isapprox({1:s}, {2:s})"
            fmt_kw = "atol = {3:s}"

            res = f(evaled, terms, fmt_ex, fmt_kw)
            @test res isa Test.Returned
            @test res.value === false
            @test res.data isa String
            @test occursin("Failed 1 test.", destyle(res.data))
            @test occursin("Keywords: atol = 1.0e-8", destyle(res.data))
            @test occursin("idx=[1]: isapprox(1, 1.00001)", destyle(res.data))
        end

        @testset "evaled is bool array" begin
            f = (args...) -> TM.eval_test_all(args..., LineNumberNode(1))

            terms = [[1, 2, 3], [1, 2, 3.001]]

            res = f(terms[1] .<= terms[2], terms, "{1:s} <= {2:s}", "")
            @test res isa Test.Returned
            @test res.value === true
            @test res.data === nothing

            res = f(terms[1] .< terms[2], terms, "{1:s} < {2:s}", "")
            @test res isa Test.Returned
            @test res.value === false
            @test res.data isa String
            @test occursin("Failed 2 tests from length 3 result.", res.data)
            @test occursin("idx=[1]: 1.0 < 1.0", destyle(res.data))
            @test occursin("idx=[2]: 2.0 < 2.0", destyle(res.data))

            terms = [[1, 2, 3], [1, 2, 3.001], Ref(1e-8)]
            evaled = isapprox.(terms[1], terms[2], atol=terms[3].x)
            fmt_ex = "isapprox({1:s}, {2:s})"
            fmt_kw = "atol = {3:s}"
            res = f(evaled, terms, fmt_ex, fmt_kw)
            @test res isa Test.Returned
            @test res.value === false
            @test res.data isa String
            @test occursin("Failed 1 test from length 3 result.", res.data)
            @test occursin("Keywords: atol = 1.0e-8", destyle(res.data))
            @test occursin("idx=[3]: isapprox(3, 3.001)", destyle(res.data))

            terms = [[1, 2], [1 2.01], Ref(1e-3)]
            evaled = .≈(terms[1], terms[2], atol=terms[3].x)
            res = f(evaled, terms, "{1:s} ≈ {2:s}", "atol = {3:s}")
            @test res isa Test.Returned
            @test res.value === false
            @test res.data isa String
            @test occursin("Failed 3 tests from size 2×2 result.", res.data)
            @test occursin("Keywords: atol = 0.001", destyle(res.data))
            @test occursin("idx=[1,2]: 1 ≈ 2.01", destyle(res.data))
            @test occursin("idx=[2,1]: 2 ≈ 1", destyle(res.data))
            @test occursin("idx=[2,2]: 2 ≈ 2.01", destyle(res.data))

            terms = [[true, false], [true, true]]
            evaled = terms[1] .&& terms[2]
            res = f(evaled, terms, "{1:s} && {2:s}", "")
            @test res isa Test.Returned
            @test res.value === false
            @test res.data isa String
            @test occursin("Failed 1 test from length 2 result.", res.data)
            @test occursin("idx=[2]: false && true", destyle(res.data))
        end
    end
    # @testset "update_terms_simple" begin

    #     cases = [
    #         # Negation
    #         :(!a)  => :negation => ([:a], "!a", "!{1:s}"),
    #         :(.!a) => :negation => ([:a], ".!a", "!{1:s}"),
    #         # Logical
    #         :(a && b)  => :logical => ([:a, :b], "(a && b)",  "({1:s} && {2:s})"),
    #         :(a .|| b) => :logical => ([:a, :b], "(a .|| b)", "({1:s} || {2:s})"),
    #         # Comparison
    #         :(a == b)  => :comparison => ([:a, :b], "(a == b)",  "({1:s} == {2:s})"),
    #         :(a .≈ b)  => :comparison => ([:a, :b], "(a .≈ b)",  "({1:s} ≈ {2:s})"),
    #         :(a <: b)  => :comparison => ([:a, :b], "(a <: b)",  "({1:s} <: {2:s})"),
    #         :(a .∈ b)  => :comparison => ([:a, :b], "(a .∈ b)",  "({1:s} ∈ {2:s})"),
    #     ]

    #     @testset "$(ex)" for (ex, res) in cases
    #         ex = TM._preprocess(ex)
    #         if res === :fallback
    #             _, str_ex, _ = TM.update_terms_fallback!([], deepcopy(ex))
    #             @test Meta.parse(str_ex) == ex
    #         end
    #     end
    # end
     

    # @testset "@test_all" begin
    #     a = [1,2,3]
    #     b = a .+ 0.01
    #     c = a .+ 1e-10 

    #     # Comparison (from call)
    #     @test_all a == 1:3
    #     @test_all a .<= b
    #     @test_all 5:7 .>= b
    #     @test_all a ≈ c
    #     @test_all a .≉ b
    #     @test_all [Int, Float64] <: Real
    #     @test_all [Real, Integer] .>: Int16
    #     @test_all [1:2, 1:3, 1:4] ⊆ Ref(0:5)

    #     # Approx special case
    #     HIGH_TOL = 1e-1 # to check local scope
    #     @test_all a ≈ c atol=1e-8
    #     @test_all a .≈ c atol=HIGH_TOL # Check local scope
    #     @test_all a .≉ b atol=1e-8
    #     @test_all .≈(a, c) atol=1e-8
    #     @test_all ≈(a, b, atol=1e-1)
    #     @test_all .≈(a, b; atol=HIGH_TOL)
    #     @test_all .≉(a, b; atol=1e-8)
    #     @test_all .≉(a, b; atol=1e-8) rtol=1e-8

    #     # Displayed function
        
    #     @test_all occursin(r"(a|b){3}", ["saaa", "baab", "aabaa"])

    #     # Fall back
    #     func() = ([1, 2, 3] .> 0)
    #     @test_all func()
    #     @test_all func() .&& func()

    # end

    # @testset "_recurse_stringify_logical: output" begin
    #     f = ex -> TM._recurse_stringify_logical(ex)
    #     # Simple
    #     @test f(:(1)) == "1"
    #     @test f(:(a)) == "a"
    #     @test f(:(a && 1)) == "a && 1"
    #     @test f(:(a .&& b)) == "a .&& b"
    #     @test f(:(a || b)) == "a || b"

    #     # Multiple
    #     @test f(:(a && b || c)) == "a && b || c"
    #     @test f(:(a && b || c && true)) == "a && b || c && true"
    #     @test f(:(a .&& b .|| c)) == "a .&& b .|| c"
    #     @test f(:(a .&& b .|| c .&& true)) == "a .&& b .|| c .&& true"
        
    #     # With !/.!
    #     @test f(:(!a)) == "!a"
    #     @test f(:(.!a)) == ".!a"
    #     @test f(:(a && !b)) == "a && !b"
    #     @test f(:(a .&& .!b)) == "a .&& .!b"
    #     @test f(:(a || !g(x))) == "a || !g(x)"
    #     @test f(:(a .|| .!(g.(x)))) == "a .|| .!g.(x)"
    #     @test f(:(a || !(x ≈ y))) == "a || !(x ≈ y)"
    #     @test f(:(a .|| .!(x .≈ y))) == "a .|| .!(x .≈ y)"
    #     @test f(:(!(x == y))) == "!(x == y)"

    #     # With :call/:., not operator
    #     @test f(:(g(x))) == "g(x)"
    #     @test f(:(g.(x))) == "g.(x)"
    #     @test f(:(a && g(x))) == "a && g(x)"
    #     @test f(:(a .&& g.(x))) == "a .&& g.(x)"
    #     @test f(:(g(x) && g(x))) == "g(x) && g(x)"
    #     @test f(:(g.(x) && g.(x))) == "g.(x) && g.(x)"

    #     # With :call/:., operator
    #     @test f(:(x == 1)) == "x == 1"
    #     @test f(:(x .== 1)) == "x .== 1"
    #     @test f(:(a && (x >= 1))) == "a && (x >= 1)"
    #     @test f(:(a .&& (x .< 1))) == "a .&& (x .< 1)"
    #     @test f(:((x ≈ y) || true)) == "(x ≈ y) || true"
    #     @test f(:(a .&& (x .≈ y))) == "a .&& (x .≈ y)"

    #     # More complicated
    #     @test f(:((a && b) || !c && isnan(w) || (x ≈ y + z))) == "\
    #                 a && b || !c && isnan(w) || (x ≈ y + z)"
    #     @test f(:((a .&& b) .|| .!c .&& isnan.(w) .|| (x .≈ y .+ z))) == "\
    #                 a .&& b .|| .!c .&& isnan.(w) .|| (x .≈ y .+ z)"

    # end

    # @testset "_recurse_vectorize_logical!" begin
    #     f = ex -> TM._recurse_vectorize_logical!(ex)
    #     @test f(:(1)) == :(1)
    #     @test f(:(a)) == :(a)
    #     @test f(:(!a)) == :(.!(a))
    #     @test f(:(a && 1)) == :(a .&& 1)
    #     @test f(:(a && b)) == :(a .&& b)
    #     @test f(:(a || !b)) == :(a .|| .!(b))
    #     @test f(:(!(a == b))) == :(.!(a == b))

    # end

    # @testset "_recurse_stringify_logical: Meta.parse" begin
    #     f = ex -> ex == Meta.parse(TM._recurse_stringify_logical(ex))
        
    #     # Simple
    #     @test f(:(1))
    #     @test f(:(a))
    #     @test f(:(a && 1))
    #     @test f(:(a .&& b))
    #     @test f(:(a || b))

    #     # Multiple
    #     @test f(:(a && b || c))
    #     @test f(:(a && b || c && true))
    #     @test f(:(a .&& b .|| c))
    #     @test f(:(a .&& b .|| c .&& true))
        
    #     # With !/.!
    #     @test f(:(!a))
    #     @test f(:(.!a))
    #     @test f(:(a && !b))
    #     @test f(:(a .&& .!(b)))
    #     @test f(:(a || !g(x)))
    #     @test f(:(a .|| .!(g.(x))))
    #     @test f(:(a || !(x ≈ y)))
    #     @test f(:(a .|| .!(x .≈ y)))
    #     @test f(:(!(x == y)))

    #     # With :call/:., not operator
    #     @test f(:(g(x)))
    #     @test f(:(g.(x)))
    #     @test f(:(a && g(x)))
    #     @test f(:(a .&& g.(x)))
    #     @test f(:(g(x) && g(x)))
    #     @test f(:(g.(x) && g.(x)))

    #     # With :call/:., operator
    #     @test f(:(x == 1))
    #     @test f(:(x .== 1))
    #     @test f(:(a && (x >= 1)))
    #     @test f(:(a .&& (x .< 1)))
    #     @test f(:((x ≈ y) || true))
    #     @test f(:(a .&& (x .≈ y)))

    #     # More complicated
    #     @test f(:((a && b) || !c && isnan(w) || (x ≈ y + z)))
    #     @test f(:((a .&& b) .|| .!c .&& isnan.(w) .|| (x .≈ y .+ z)))
    # end

    #     a = [true, false, true]
    #     b = [true, false, false]
    #     c = [true ,true, true]
    #     d = [1, 2, 3]
    #     g(x) = x

    #     function test_stringify(ex) 
    #         ex = _recurse_vectorize_logical!(ex)
    #         sex = _recurse_stringify_logical(ex)
    #         println("Stringified: ", sex)
    #         if ex != Meta.parse(sex) 
    #             println("Don't make same expression:")
    #             println("ORIGINAL")
    #             dump(ex)
    #             println("\nREPARSED")
    #             dump(sex)
    #         else
    #             try 
    #                 eval(ex)
    #             catch e
    #                 println("Didn't eval correctly")
    #                 rethrow(e)
    #             end
    #         end
    #     end

    #     test_stringify(:(a))
    #     test_stringify(:(a && b))
    #     test_stringify(:(a || c))
    #     test_stringify(:(a && b || c))
    #     test_stringify(:(a && b || c && d))
    #     test_stringify(:(a && b || g(c) && d))
    #     test_stringify(:(a && b || g(c) || d))
    #     test_stringify(:(g(c) || g(c) || g(c) || g(c)))
    #     test_stringify(:((c.+ 1 .>= 1) || g(c) || g(c) || g(c)))
    #     test_stringify(:(d .> 1 || g(c) || g(c) || g(c)))

    #     :(d .> 1 || g(c) || g(c) || g(c)).args[1]

    #     ted = :(c .+ 1 .>= 1)
    #     ted.head
    #     Base.operator_precedence(ted.args[1])

    #     g(c + 1)
    #     a .&& b .|| g(c) .|| d

    #     test_stringify(:(a && b || g.(c)))
    # end

end