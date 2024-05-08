@testset "vecop.jl" begin

    @testset "add_keywords!(ex, kws)" begin

        @testset "adding cases" begin
            # Regular tests
            cases = [
                # Comparisons
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
                # Function calls with negation
                :(!g())         => ()              => :(!g()),
                :(!!g())        => (:(x = 1),)     => :(!!g(x = 1)),
                :(!(a ≈ b))     => (:(x = 1),)     => :(!≈(a, b, x = 1)),
                # Vectorized calls with negation
                :(.!g.())       => ()              => :(.!g.()),
                :(.!.!g.())     => (:(x = 1),)     => :(.!.!g.(x = 1)),
            ]

            @testset "$ex" for (ex, (kws, res)) in cases
                @test TM.add_keywords!(ex, kws...) == res
            end
        end

        @testset "does not support kwargs" begin
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
                :(a >: b)
            ]

            @testset "$ex" for ex in cases
                @test_throws "does not accept keyword arguments" TM.add_keywords!(ex, :(x=1))
            end
        end

        @testset "invalid keyword syntax" begin
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
     end

     @testset "preprocess(ex)" begin

        @testset "convert to comparison" begin
            cases = [
                # Converted to comparisons
                :(a .== b) => Expr(:comparison, :a, :.==, :b),
                :(.≈(a, b)) => Expr(:comparison, :a, :.≈, :b),
                :(a .≈ b) => Expr(:comparison, :a, :.≈, :b),
                :(a .∈ b) => Expr(:comparison, :a, :.∈, :b),
                :(a .⊆ b) => Expr(:comparison, :a, :.⊆, :b),
                :(a .<: b) => Expr(:comparison, :a, :.<:, :b),
                :(a .>: b) => Expr(:comparison, :a, :.>:, :b),
            ]

            @testset "$ex" for (ex, res) in cases
                @test TM.preprocess(ex) == res
            end
        end

        @testset "change parameters to keywords" begin
            cases = [
                :(isnan.(x;a=1)) => :(isnan.(x,a=1)),
                :(isnan.(x;a=1,b=1)) => :(isnan.(x,a=1,b=1)),
                :(isnan.(x,a=1,b=1;c=1,d=1)) => :(isnan.(x,a=1,b=1,c=1,d=1)),
                :(.≈(a,b;atol=1)) => :(.≈(a,b,atol=1)),
                :(isapprox.(a,b;atol=1)) => :(isapprox.(a,b,atol=1)),
            ]

            @testset "$ex" for (ex, res) in cases
                @test TM.preprocess(ex) == res
            end
        end

        @testset "unchanged" begin
            cases = [
                :(a), 
                :(:a),
                :(a && b), 
                :(a == b), 
                :(a == b == c), 
                :(g(x)), 
                :(g.(x, a=1)), 
                :(isapprox(a,b,atol=1)),  
                :(isnan(x)), 
                :([1,2,3]), 
                :((1,2,3)),
                :([1 2 3]),
                :(1:3),
                :(Ref(a)),
                # Already comparison
                :(a .== b .== c),
                Expr(:comparison, :a, :.==, :b),
                # Is displaycall but already keywordized
                :(isnan.(x)),
                :(isapprox.(a,b,atol=1)),
                # Is argsapprox but already keywordized
                :(.≈(a,b,atol=1)),

            ]

            @testset "$ex" for ex in cases
                @test TM.preprocess(ex) === ex
            end
        end


     end

    @testset "is_xxx(ex)" begin
        @testset "is_negation(ex)" begin
            cases = [
                # True
                :(.!a) => true,
                :(.!(a .== b)) => true,
                :(.!g(x)) => true,
                :(.!g.(x)) => true,
                :(.!isnan.(x)) => true,
                # False
                :(!a) => false,
                :(!g(x)) => false,
                :(!(a == b)) => false,
                :(a .== b) => false
            ]

            @testset "$ex => $res" for (ex, res) in cases
                ex = TM.preprocess(ex)
                @test TM.is_negation(ex) === res
            end
        end

        @testset "is_logical(ex)" begin
            cases = [
                # True
                :(a .&& b) => true,
                :(a .|| b) => true,
                :(a .&& b .|| c) => true,
                :(a .&& (g.(x) .&& c)) => true,
                # False
                :(a && b) => false,
                :(a || b) => false,
                :(a == b) => false,
                :(a .== b) => false,
            ]

            @testset "$ex => $res" for (ex, res) in cases
                ex = TM.preprocess(ex)
                @test TM.is_logical(ex) === res
            end
        end

        @testset "is_comparison(ex)" begin
            cases = [
                # True
                :(a .== b) => true,
                :(a .≈ b) => true,
                :(a .>: b) => true,
                :(a .<: b) => true,
                :(a .∈ b) => true,
                # False (splat)
                :(a... .== b) => false, 
                :(a .∈ b...) => false,
                # False (other)
                :(a == b) => false,
                :(a .== b <= c) => false,
                :(a .&& b) => false,
                :(a .|| b) => false,
            ]

            @testset "$ex => $res" for (ex, res) in cases
                ex = TM.preprocess(ex)
                @test TM.is_comparison(ex) === res
            end
        end

        @testset "is_argsapprox(ex)" begin
            cases = [
                # True
                :(.≈(a, b, atol=1)) => true,
                :(.≉(a, b, atol=1)) => true,
                # False (incorrect number of positional arguments)
                :(.≈()) => false,
                :(.≈(a, atol=1)) => false,
                :(.≉(a, b, c, atol=1)) => false,
                # False (splats)
                :(.≈(a, b..., atol=1)) => false,
                :(.≉(a..., b, atol=1)) => false,
                # False (other)
                :(≈(a, b, atol=1)) => false,
                :(≉(a, b, atol=1)) => false,
                :(a == b) => false,
                :(a .== b <= c) => false,
                :(a .&& b) => false,
                :(a .|| b) => false,
            ]
            @testset "$ex => $res" for (ex, res) in cases
                ex = TM.preprocess(ex)
                @test TM.is_argsapprox(ex) === res
            end
        end

        @testset "is_displaycall(ex)" begin
            cases = [
                # True
                :(isnan.(x)) => true, 
                :(isreal.(x)) => true,
                :(occursin.(a, b)) => true,
                :(isapprox.(a, b, atol=1)) => true,
                # False (no positional arguments)
                :(isinf.()) => false,
                :(isapprox.(a=1)) => false,
                # False (splats in positional arguments)
                :(isnan.(a...)) => false,
                :(isapprox.(a..., b..., atol=1)) => false,
                # False (other)
                :(g.(x)) => false,
                :(a .== b) => false,
            ]
            @testset "$ex => $res" for (ex, res) in cases
                ex = TM.preprocess(ex)
                @test TM.is_displaycall(ex) === res
            end
        end

        @testset "is_fallback(ex)" begin
            cases = [
                :(1),
                :(1:3),
                :((1,2,3)),
                :([1,2,3]),
                :([1 2 3]),
                :(Ref(1:3)),
                :(a),
                :(:a),
                :(g(x)),
                :(g.(x)),
            ]
            @testset "$ex" for ex in cases
                ex = TM.preprocess(ex)
                @test TM.is_fallback(ex) === true
            end
        end

        @testset "is_mappable(ex)" begin
            cases = [
                # True
                :(x -> iseven(x)) => true,
                :(x -> x^2) => true,
                :(x -> true) => true,
                :(x -> x == 1 && y) => true,
                # False 
                :(:a) => false,
                :(:a == b) => false,
                :(a .== b) => false,
                :(a .== b .== c) => false,
            ]
            @testset "$ex => $res" for (ex, res) in cases
                ex = TM.preprocess(ex)
                @test TM.is_mappable(ex) === res
            end
        end

    end


    @testset "update_escaped!()" begin 
    
        @testset "negation" begin
            cases = [
                :(.!a) => (:(.!ARG[1]), ".!a", "!{1:s}"),
            ]

            @testset "$ex" for (ex, res) in cases
                # Pre-process and get expected results
                res_mod_ex, res_str_ex, res_fmt_ex = res
                ex, res_mod_ex = TM.preprocess(ex), TM.preprocess(res_mod_ex)

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
                :(a .&& b) => (:(ARG[1] .&& ARG[2]),                           
                               [:a, :b],            
                               "a .&& b",                
                               "{1:s} && {2:s}"), 
                :(a .|| b .|| c) => (:(ARG[1] .|| ARG[2] .|| ARG[3]), 
                                     [:a, :b, :c], 
                                     "a .|| b .|| c", 
                                     "{1:s} || {2:s} || {3:s}"),
                :(a .&& b .&& c .|| d) => (:(ARG[1] .&& ARG[2] .&& ARG[3] .|| ARG[4]), 
                                            [:a, :b, :c, :d],
                                            "a .&& b .&& c .|| d",
                                            "{1:s} && {2:s} && {3:s} || {4:s}"),
            ]

            @testset "$ex" for (ex, res) in cases
                # Pre-process and get expected results
                res_mod_ex, res_args, res_str_ex, res_fmt_ex = res
                res_args = esc.(res_args)
                ex, res_mod_ex = TM.preprocess(ex), TM.preprocess(res_mod_ex)

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
                :(a .== b) => (:(ARG[1] .== ARG[2]),            
                              "{1:s} == {2:s}",
                              [:a, :b]),
                :(a .∈ b) => (:(ARG[1] .∈ ARG[2]),            
                              "{1:s} ∈ {2:s}",
                              [:a, :b]),
                :(a .≈ b .> c)   => (:(ARG[1] .≈ ARG[2] .> ARG[3]),   
                                    "{1:s} ≈ {2:s} > {3:s}",
                                    [:a, :b, :c]),
                :(a .<: b .>: c) => (:(ARG[1] .<: ARG[2] .>: ARG[3]), 
                                    "{1:s} <: {2:s} >: {3:s}",
                                    [:a, :b, :c]),
            ]

            @testset "$ex" for (ex, res) in cases
                # Pre-process and get expected results
                res_mod_ex, res_fmt_ex, res_args = res
                ex, res_mod_ex = TM.preprocess(ex), TM.preprocess(res_mod_ex)
                res_str_ex = string(ex)

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
                :(.≈(a, b, atol=TOL)) => (
                    :(.≈(ARG[1], ARG[2], atol=ARG[3].x)), 
                    ".≈(a, b, atol = TOL)",
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
                ex, res_mod_ex = TM.preprocess(ex), TM.preprocess(res_mod_ex)
                res_str_ex = string(ex)

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
                :(.≈(a, b, atol=TOL)) => (
                    :(.≈(ARG[1], ARG[2], atol=ARG[3].x)), 
                    ".≈(a, b, atol = TOL)",
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
                ex, res_mod_ex = TM.preprocess(ex), TM.preprocess(res_mod_ex)
                res_str_ex = string(ex)

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
                :(isnan.(a)) => (
                    :(isnan.(ARG[1])), 
                    "isnan.(a)",
                    "isnan({1:s})",
                    "",
                    [:a],
                ),
                :(isapprox.(a, b, atol=TOL)) => (
                    :(isapprox.(ARG[1], ARG[2], atol=ARG[3].x)), 
                    "isapprox.(a, b, atol = TOL)",
                    "isapprox({1:s}, {2:s})",
                    "atol = {3:s}",
                    [:a, :b, :(Ref(TOL))],
                ),
            ]

            @testset "(outer) $ex" for (ex, res) in cases_outmost
                # Pre-process and get expected results
                res_mod_ex, res_str_ex, res_fmt_ex, res_fmt_kw, res_args = res
                ex, res_mod_ex = TM.preprocess(ex), TM.preprocess(res_mod_ex)
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
                :(isnan.(a)) => (
                    :(isnan.(ARG[1])), 
                    "isnan.(a)",
                    "isnan({1:s})",
                    "",
                    [:a],
                ),
                :(isapprox.(a, b, atol=TOL)) => (
                    :(isapprox.(ARG[1], ARG[2], atol=ARG[3].x)), 
                    "isapprox.(a, b, atol = TOL)",
                    "isapprox({1:s}, {2:s}, atol = {3:s})",
                    "",
                    [:a, :b, :(Ref(TOL))],
                ),
            ]

            @testset "(inner) $ex" for (ex, res) in cases_inner
                # Pre-process and get expected results
                res_mod_ex, res_str_ex, res_fmt_ex, res_fmt_kw, res_args = res
                ex, res_mod_ex = TM.preprocess(ex), TM.preprocess(res_mod_ex)
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
                :(:a),
                :([1,2]), 
                :(g(x)), 
                :(g.(x,a=1;b=b)), 
                :(a .+ b),
            ]

            @testset "$ex" for ex in cases
                ex = TM.preprocess(ex)
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

    @testset "string_idxs()" begin
        I = CartesianIndex
        @test TM.string_idxs([1,2,3]) == ["1", "2", "3"]
        @test TM.string_idxs([1,10,100]) == ["  1", " 10", "100"]
        @test TM.string_idxs([I(1,1), I(1,10), I(100,1)]) == ["  1, 1", "  1,10", "100, 1"]
    end

    @testset "print_failures()" begin
        
        printfunc = (args...) -> TM.print_failures(args...; prefix="", max_vals=4)

        msg = (io, idx) -> print(io, 2*idx)
        idxs = [1,2,3]
        exp = "\nidx=[1]: 2\nidx=[2]: 4\nidx=[3]: 6"
        @test occursin(exp, sprint(printfunc, idxs, msg))

        msg = (io, idx) -> print(io, sum(idx.I))
        idxs = CartesianIndex.([(1,1), (1,10), (10,1)])
        exp = "\nidx=[ 1, 1]: 2\nidx=[ 1,10]: 11\nidx=[10, 1]: 11"
        @test occursin(exp, sprint(printfunc, idxs, msg))

        # Wrap to 
        msg = (io, idx) -> print(io, idx)
        idxs = 1:20
        exp = "\nidx=[ 1]: 1\nidx=[ 2]: 2\n⋮\nidx=[19]: 19\nidx=[20]: 20"
        @test occursin(exp, sprint(printfunc, idxs, msg))
    end

    # @testset "eval_test_all()" begin
    #     destyle = x -> replace(x, r"\e\[\d+m" => "")
    #     struct TestStruct
    #         x::Symbol
    #     end

    #     @testset "invalid broadcast behaviour" begin

    #     end

    #     @testset "evaled is not array or bool" begin
    #         f = (evaled) -> TM.eval_test_all(evaled, [evaled], "", "", LineNumberNode(1))

    #         res = f(1)
    #         @test res.value === false
    #         @test occursin("1 ===> Int64", destyle(res.data))

    #         res = f(:a)
    #         @test res.value === false
    #         @test occursin(":a ===> Symbol", destyle(res.value))

    #         res = f(TestStruct(:b))
    #         @test res.value === false
    #         @test occursin("TestStruct(:b) ===> TestStruct", destyle(res.value))
    #     end

    #     @testset "evaled is non-bool array" begin
    #         f = (evaled) -> TM.eval_test_all(evaled, [evaled], "", "", LineNumberNode(1))

    #         res = f([10,2])
    #         @test res.value === false
    #         @test occursin("Vector{Int64}(2) with 2 non-Boolean values.", res.data)
    #         @test occursin("idx=[1]: 10 ===> Int64", destyle(res.data))
    #         @test occursin("idx=[2]: 2 ===> Int64", destyle(res.data))

    #         res = f(Any[true, :a, false, TestStruct(:b)])
    #         @test res.value === false
    #         @test occursin("Vector{Any}(4) with 2 non-Boolean values.", res.data)
    #         @test occursin("idx=[2]: :a ===> Symbol", destyle(res.data))
    #         @test occursin("idx=[4]: TestStruct(:b) ===> TestStruct", destyle(res.data))

    #         res = f(Any[false true :a])
    #         @test res.value === false
    #         @test occursin("Matrix{Any}(1×3) with 1 non-Boolean value.", res.data)
    #         @test occursin("idx=[1,3]: :a ===> Symbol", destyle(res.data))
    #     end

    #     @testset "evaled is bool" begin
    #         f = (evaled) -> TM.eval_test_all(evaled, [evaled], "{1:s}", "", LineNumberNode(1))
    #         res = f(true)
    #         @test res isa Test.Returned
    #         @test res.value === true
    #         @test res.data === nothing

    #         res = f(false)
    #         @test res isa Test.Returned
    #         @test res.value === false
    #         @test res.data isa String
    #         @test occursin("Failed 1 test.", res.data)
    #         @test occursin("idx=[1]: false", destyle(res.data))

    #         f = (args...) -> TM.eval_test_all(args..., LineNumberNode(1))

    #         terms = [1, 1.00001, Ref(1e-3)]
    #         evaled = isapprox(terms[1], terms[2], atol=terms[3].x)
    #         fmt_ex = "isapprox({1:s}, {2:s})"
    #         fmt_kw = "atol = {3:s}"

    #         res = f(evaled, terms, fmt_ex, fmt_kw)
    #         @test res isa Test.Returned
    #         @test res.value === true
    #         @test res.data === nothing
            
    #         terms = [1, 1.00001, Ref(1e-8)]
    #         evaled = isapprox(terms[1], terms[2], atol=terms[3].x)
    #         fmt_ex = "isapprox({1:s}, {2:s})"
    #         fmt_kw = "atol = {3:s}"

    #         res = f(evaled, terms, fmt_ex, fmt_kw)
    #         @test res isa Test.Returned
    #         @test res.value === false
    #         @test res.data isa String
    #         @test occursin("Failed 1 test.", destyle(res.data))
    #         @test occursin("Keywords: atol = 1.0e-8", destyle(res.data))
    #         @test occursin("idx=[1]: isapprox(1, 1.00001)", destyle(res.data))
    #     end

    #     @testset "evaled is bool array" begin
    #         f = (args...) -> TM.eval_test_all(args..., LineNumberNode(1))

    #         terms = [[1, 2, 3], [1, 2, 3.001]]

    #         res = f(terms[1] .<= terms[2], terms, "{1:s} <= {2:s}", "")
    #         @test res isa Test.Returned
    #         @test res.value === true
    #         @test res.data === nothing

    #         res = f(terms[1] .< terms[2], terms, "{1:s} < {2:s}", "")
    #         @test res isa Test.Returned
    #         @test res.value === false
    #         @test res.data isa String
    #         @test occursin("Failed 2 tests from length 3 result.", res.data)
    #         @test occursin("idx=[1]: 1.0 < 1.0", destyle(res.data))
    #         @test occursin("idx=[2]: 2.0 < 2.0", destyle(res.data))

    #         terms = [[1, 2, 3], [1, 2, 3.001], Ref(1e-8)]
    #         evaled = isapprox.(terms[1], terms[2], atol=terms[3].x)
    #         fmt_ex = "isapprox({1:s}, {2:s})"
    #         fmt_kw = "atol = {3:s}"
    #         res = f(evaled, terms, fmt_ex, fmt_kw)
    #         @test res isa Test.Returned
    #         @test res.value === false
    #         @test res.data isa String
    #         @test occursin("Failed 1 test from length 3 result.", res.data)
    #         @test occursin("Keywords: atol = 1.0e-8", destyle(res.data))
    #         @test occursin("idx=[3]: isapprox(3, 3.001)", destyle(res.data))

    #         terms = [[1, 2], [1 2.01], Ref(1e-3)]
    #         evaled = .≈(terms[1], terms[2], atol=terms[3].x)
    #         res = f(evaled, terms, "{1:s} ≈ {2:s}", "atol = {3:s}")
    #         @test res isa Test.Returned
    #         @test res.value === false
    #         @test res.data isa String
    #         @test occursin("Failed 3 tests from size 2×2 result.", res.data)
    #         @test occursin("Keywords: atol = 0.001", destyle(res.data))
    #         @test occursin("idx=[1,2]: 1 ≈ 2.01", destyle(res.data))
    #         @test occursin("idx=[2,1]: 2 ≈ 1", destyle(res.data))
    #         @test occursin("idx=[2,2]: 2 ≈ 2.01", destyle(res.data))

    #         terms = [[true, false], [true, true]]
    #         evaled = terms[1] .&& terms[2]
    #         res = f(evaled, terms, "{1:s} && {2:s}", "")
    #         @test res isa Test.Returned
    #         @test res.value === false
    #         @test res.data isa String
    #         @test occursin("Failed 1 test from length 2 result.", res.data)
    #         @test occursin("idx=[2]: false && true", destyle(res.data))
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