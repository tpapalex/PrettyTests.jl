@testset "testall.jl" begin

    @testset "pushkeywords!(ex, kws)" begin

        @testset "without keywords" begin
            # Test that returns input if there are no keywords added to case
            cases = [
                :(a == b), 
                :(a .< b),
                :(!(a == b)), 
                :(.!(a .≈ b)),
                :(f()), 
                :(f.(a)), 
                :(!f()),
                :(.!f.(a))
            ]

            @testset "ex: $ex" for ex in cases
                modex = TM.pushkeywords!(ex)
                @test modex === ex
            end
        end
        
        @testset "with keywords" begin
            # Add :(x = 1) keyword to case
            cases = [
                :(a ≈ b) => :(≈(a, b, x = 1)),
                :(a .≈ b) => :(.≈(a, b, x = 1)),
                :(g()) => :(g(x = 1)),
                :(!g()) => :(!g(x = 1)), 
                :(g.(a)) => :(g.(a, x = 1)),
                :(.!g.(a)) => :(.!g.(a, x = 1)),
                :(!!!!g()) => :(!!!!g(x = 1))
            ]

            @testset "push (x=1) to ex: $ex" for (ex, res) in cases
                mod_ex = TM.pushkeywords!(ex, :(x = 1))
                @test mod_ex == res
            end

            # Add :(x = 1, y = 2) keywords to case
            cases = [
                :(g()) => :(g(x = 1, y = 2))
                :(.!g.(a)) => :(.!g.(a, x = 1, y = 2))
            ]
            @testset "push (x=1,y=2) to ex: $ex" for (ex, res) in cases
                mod_ex = TM.pushkeywords!(ex, :(x = 1), :(y=2))
                @test mod_ex == res
            end
        end

        @testset "does not accept keywords" begin
            # Throws error because case does not support keywords
            cases = [
                :(a),
                :(:a),
                :(a && b), 
                :(a .|| b), 
                :([a,b]), 
                :((a,b)), 
                :(a <: b)
            ]

            @testset "ex: $ex" for ex in cases
                @test_throws "does not accept keyword" TM.pushkeywords!(ex, :(x = 1))
            end
        end

        @testset "invalid keyword syntax" begin
            # Throws error because case is not valid keyword syntax
            cases = [
                :(a), 
                :(:a), 
                :(a == 1), 
                :(g(x)), 
            ]

            @testset "kw: $kw" for kw in cases
                @test_throws "is not valid keyword" TM.pushkeywords!(:(g()), kw)
            end

            # Same but where only some keywords are invalid
            @testset "kws: (x = 1, $kw)" for kw in cases
                @test_throws "is not valid keyword" TM.pushkeywords!(:(g()), :(x = 1), kw)
            end
        end
    end

    @testset "preprocess(ex)" begin

        @testset "convert to comparison" begin
            # Case is converted to :comparison call
            cases = [
                :(a .== b) => Expr(:comparison, :a, :.==, :b),
                :(.≈(a, b)) => Expr(:comparison, :a, :.≈, :b),
                :(a .≈ b) => Expr(:comparison, :a, :.≈, :b),
                :(a .∈ b) => Expr(:comparison, :a, :.∈, :b),
                :(a .⊆ b) => Expr(:comparison, :a, :.⊆, :b),
                :(a .<: b) => Expr(:comparison, :a, :.<:, :b),
                :(a .>: b) => Expr(:comparison, :a, :.>:, :b),
            ]

            @testset "ex: $ex" for (ex, res) in cases
                proc_ex = TM.preprocess(ex)
                @test proc_ex == res
                @test proc_ex !== res # returns new expression
            end
        end

        @testset "change parameters kws to trailing" begin
            # Parameter kws in case are moved to trailing arguments
            cases = [
                # Displayable, not vectorized
                :(isnan(x; a=1)) => :(isnan(x, a=1)),
                :(isnan(x, a=1; b=1)) => :(isnan(x, a=1, b=1)),
                :(isnan(x; a=1, b=1)) => :(isnan(x, a=1, b=1)),
                # Displayable, vectorized
                :(isnan.(x; a=1)) => :(isnan.(x, a=1)),
                :(isnan.(x, a=1; b=1)) => :(isnan.(x, a=1, b=1)),
                :(isnan.(x; a=1, b=1)) => :(isnan.(x, a=1, b=1)),
                # Approx cases
                :(≈(x, y; a=1)) => :(≈(x, y, a=1)),
                :(≈(x, y, a=1; b=1)) => :(≈(x, y, a=1, b=1)),
                :(.≈(x, y; a=1)) => :(.≈(x, y, a=1)),
                :(.≈(x, y, a=1; b=1)) => :(.≈(x, y, a=1, b=1)),
            ]

            @testset "ex: $ex" for (ex, res) in cases
                proc_ex = TM.preprocess(ex)
                @test proc_ex == res 
                @test proc_ex !== res # returns new expression
            end
        end

        @testset "no preprocessing" begin
            # Expression remains unchanged
            cases = [
                :a, 
                :(:a), 
                :(a == b), 
                :(a .== b .== c),
                Expr(:comparison, :a, :.==, :b), 
                :(g(x; a = 1)), 
                :(isnan(x)), # Displayable call, but no keywords
                :(isnan(x, a = 1)), # Displayable call, but already trailing keywords
                :(isnan.(x)), # Displayable, but no keywords
                :(isnan.(x, a = 1)) # Displayable, but already trailing keywords
            ]

            @testset "ex: $ex" for ex in cases
                @test TM.preprocess(deepcopy(ex)) == ex 
                @test TM.preprocess(ex) === ex
            end
        end
    end

    @testset "expression classifiers" begin

        @testset "isvecnegationexpr(ex)" begin
            cases = [
                # True
                :(.!a) => true,
                :(.!(a .== b)) => true,
                :(.!g(x)) => true,
                :(.!g.(x)) => true,
                :(.!isnan.(x)) => true,
                # False
                :(a .== b) => false,
                :(!a) => false,
                :(!g(x)) => false,
                :(!(a == b)) => false,
            ]

            @testset "ex: $ex ===> $res" for (ex, res) in cases
                ex = TM.preprocess(ex)
                @test TM.isvecnegationexpr(ex) === res
            end
        end

        @testset "isveclogicalexpr(ex)" begin
            cases = [
                # True
                :(a .& b) => true,
                :(a .| b) => true,
                :(a .⊽ b) => true,
                :(a .⊻ b) => true,
                :(a .& b .| c) => true,
                :(a .⊽ g.(x) .⊻ c) => true,
                # False
                :(a & b) => false,
                :(a || b) => false,
                :(a ⊻ b) => false,
                :(a .== b) => false,
            ]

            @testset "ex: $ex ===> $res" for (ex, res) in cases
                ex = TM.preprocess(ex)
                @test TM.isveclogicalexpr(ex) === res
            end
        end

        @testset "isveccomparisonexpr(ex)" begin
            cases = [
                # True
                :(a .== b) => true,
                :(a .≈ b) => true,
                :(a .>: b) => true,
                :(a .<: b) => true,
                :(a .∈ b) => true,
                # False (other)
                :(a == b) => false,
                :(a .== b <= c) => false,
                :(a .&& b) => false,
                :(a .|| b) => false,
            ]

            @testset "$ex => $res" for (ex, res) in cases
                ex = TM.preprocess(ex)
                @test TM.isveccomparisonexpr(ex) === res
            end
        end

        @testset "isvecapproxexpr(ex)" begin
            cases = [
                # True
                :(.≈(a, b, atol=1)) => true,
                :(.≉(a, b, atol=1)) => true,
                # False (splats)
                :(.≈(a..., atol=1)) => false,
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
            @testset "ex: $ex ===> $res" for (ex, res) in cases
                ex = TM.preprocess(ex)
                @test TM.isvecapproxexpr(ex) === res
            end
        end

        @testset "isvecdisplayexpr(ex)" begin
            cases = [
                # True
                :(isnan.(x)) => true, 
                :(isreal.(x)) => true,
                :(occursin.(a, b)) => true,
                :(isapprox.(a, b, atol=1)) => true,
                # False (not vectorized)
                :(isnan(x)) => false,
                :(isapprox(a, b, atol=1)) => false,
                # False (splats)
                :(isnan.(a...)) => false,
                :(isapprox.(a..., atol=1)) => false,
                # False (other)
                :(g.(x)) => false,
                :(a .== b) => false,
            ]
            @testset "ex: $ex ===> $res" for (ex, res) in cases
                ex = TM.preprocess(ex)
                @test TM.isvecdisplayexpr(ex) === res
            end
        end
    end


    @testset "recurse_escape!()" begin 

        escape! = (ex, args; kws...) -> TM.recurse_escape!(deepcopy(ex), args; kws...)
        stringify! = fmt_io -> TM.stringify!(fmt_io)
        @testset "basecase" begin

            # No parentheses needed
            cases = [
                :(1),
                :(a), 
                :(:a),
                :([1,2]), 
                :(g(x)), 
                :(g.(x,a=1;b=b)), 
            ]

            @testset "ex: $ex" for ex in cases
                args = Expr[]
                res, fmt, _  = escape!(ex, args; outmost=true)
                
                @test args == Expr[esc(ex)]
                @test res == :(ARG[1])
                @test stringify!(fmt) == "{1:s}"

                res, fmt, _  = escape!(ex, args; outmost=false)
                @test args == Expr[esc(ex), esc(ex)]
                @test res == :(ARG[2])
                @test stringify!(fmt) == "{2:s}"
            end

            # Parentheses needed
            cases = [
                :(a + b), 
                :(a .- b),
                :(a...), 
                :(a .&& b)
            ]
            @testset "ex: $ex" for ex in cases
                args = Expr[]
                res, fmt, _  = escape!(ex, args; outmost=true)
                
                @test args == Expr[esc(ex)]
                @test res == :(ARG[1])
                @test stringify!(fmt) == "{1:s}"

                res, fmt, _  = escape!(ex, args; outmost=false)
                @test args == Expr[esc(ex), esc(ex)]
                @test res == :(ARG[2])
                @test stringify!(fmt) == "({2:s})"
            end
        end

        @testset "keywords" begin
            kw = Expr(:kw, :a, 1)
            @testset "kw: $(kw.args[1]) = $(kw.args[2])" begin
                args = Expr[]
                res, fmt = TM.recurse_escape_keyword!(deepcopy(kw), args)

                @test args == [esc(:(Ref(1)))]
                @test res == Expr(:kw, :a, :(ARG[1].x))
                @test stringify!(fmt) == "a = {1:s}"

                res, fmt = TM.recurse_escape_keyword!(deepcopy(kw), args)

                @test args == [esc(:(Ref(1))), esc(:(Ref(1)))]
                @test res == Expr(:kw, :a, :(ARG[2].x))
                @test stringify!(fmt) == "a = {2:s}"
            end

            kw = Expr(:kw, :atol, :(1+TOL))
            @testset "kw: $(kw.args[1]) = $(kw.args[2])" begin
                args = Expr[]
                res, fmt = TM.recurse_escape_keyword!(deepcopy(kw), args)

                @test args == [esc(:(Ref(1+TOL)))]
                @test res == Expr(:kw, :atol, :(ARG[1].x))
                @test stringify!(fmt) == "atol = {1:s}"

                res, fmt = TM.recurse_escape_keyword!(deepcopy(kw), args)

                @test args == [esc(:(Ref(1+TOL))), esc(:(Ref(1+TOL)))]
                @test res == Expr(:kw, :atol, :(ARG[2].x))
                @test stringify!(fmt) == "atol = {2:s}"
            end
        end

        @testset "negation" begin
            ex = :(.!a)
            @testset "ex: $ex" begin
                args = Expr[]
                res, fmt, _  = escape!(ex, args; outmost=true)
                
                @test args == Expr[esc(:a)]
                @test res == Expr(:call, esc(:.!), :(ARG[1]))
                @test stringify!(fmt) == "!{1:s}"

                res, fmt, _  = escape!(ex, args; outmost=false)
                @test args == Expr[esc(:a), esc(:a)]
                @test res == Expr(:call, esc(:.!), :(ARG[2]))
                @test stringify!(fmt) == "!{2:s}"
            end
        end

        @testset "logical" begin
            ex = :(a .& b)
            @testset "ex: $ex" begin
                args = Expr[]
                res, fmt, _  = escape!(ex, args; outmost=true)
                
                @test args == esc.([:a, :b])
                @test res == Expr(:call, esc(:.&), :(ARG[1]), :(ARG[2]))
                @test stringify!(fmt) == "{1:s} & {2:s}"

                res, fmt, _  = escape!(ex, args; outmost=false)
                @test args == Expr[esc(:a), esc(:b), esc(:a), esc(:b)]
                @test res == Expr(:call, esc(:.&), :(ARG[3]), :(ARG[4]))
                @test stringify!(fmt) == "({3:s} & {4:s})"
            end

            ex = :(a .| b .| c)
            @testset "ex: $ex" begin
                args = Expr[]

                res, fmt, _  = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :b, :c])
                inner_res = Expr(:call, esc(:.|), :(ARG[1]), :(ARG[2]))
                @test res == Expr(:call, esc(:.|), inner_res, :(ARG[3]))
                @test stringify!(fmt) == "{1:s} | {2:s} | {3:s}"

                res, fmt, _  = escape!(ex, args; outmost=false)
                @test args == esc.([:a, :b, :c, :a, :b, :c])
                inner_res = Expr(:call, esc(:.|), :(ARG[4]), :(ARG[5]))
                @test res == Expr(:call, esc(:.|), inner_res, :(ARG[6]))
                @test stringify!(fmt) == "({4:s} | {5:s} | {6:s})"
            end

            ex = :(a .& b .⊻ c .⊽ d .| e)
            @testset "ex: $ex" begin
                args = Expr[]

                res, fmt, _  = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :b, :c, :d, :e])
                inner_res = Expr(:call, esc(:.&), :(ARG[1]), :(ARG[2]))
                inner_res = Expr(:call, esc(:.⊻), inner_res, :(ARG[3]))
                inner_res = Expr(:call, esc(:.⊽), inner_res, :(ARG[4]))
                @test res == Expr(:call, esc(:.|), inner_res, :(ARG[5]))
                @test stringify!(fmt) == "{1:s} & {2:s} ⊻ {3:s} ⊽ {4:s} | {5:s}"
            end

            ex = :(.⊽(a, b, c))
            @testset "ex: $ex" begin
                args = Expr[]

                res, fmt, _  = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :b, :c])
                @test res == Expr(:call, esc(:.⊽), :(ARG[1]), :(ARG[2]), :(ARG[3]))
                @test stringify!(fmt) == "{1:s} ⊽ {2:s} ⊽ {3:s}"
            end
        end

        @testset "comparison" begin
            ex = :(a .== b)
            @testset "ex: $ex" begin
                args = Expr[]

                res, fmt, _ = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :b])
                @test res == Expr(:comparison, :(ARG[1]), esc(:.==), :(ARG[2]))
                @test stringify!(fmt) == "{1:s} == {2:s}"

                res, fmt, _ = escape!(ex, args; outmost=false)
                @test args == esc.([:a, :b, :a, :b])
                @test res == Expr(:comparison, :(ARG[3]), esc(:.==), :(ARG[4]))
                @test stringify!(fmt) == "({3:s} == {4:s})"
            end

            ex = :(a .≈ b .> c)
            @testset "ex: $ex" begin
                args = Expr[]

                res, fmt, _ = escape!(ex, args; outmost=false)
                @test args == esc.([:a, :b, :c])
                @test res == Expr(:comparison, :(ARG[1]), esc(:.≈), :(ARG[2]), esc(:.>), :(ARG[3]))
                @test stringify!(fmt) == "({1:s} ≈ {2:s} > {3:s})"
            end

            ex = :(a .<: b .>: c)
            @testset "ex: $ex" begin
                args = Expr[]

                res, fmt, _ = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :b, :c])
                @test res == Expr(:comparison, :(ARG[1]), esc(:.<:), :(ARG[2]), esc(:.>:), :(ARG[3]))
                @test stringify!(fmt) == "{1:s} <: {2:s} >: {3:s}"
            end
        end

        @testset "approx" begin
            ex = :(.≈(a, b, atol=10*TOL))
            @testset "ex: $ex" begin
                args = Expr[]

                res, fmt_ex, fmt_kw = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :b, :(Ref(10*TOL))])
                @test res == Expr(:call, esc(:.≈), 
                                  :(ARG[1]), :(ARG[2]), 
                                  Expr(:kw, :atol, :(ARG[3].x)))
                @test stringify!(fmt_ex) == "{1:s} ≈ {2:s}"
                @test stringify!(fmt_kw) == "atol = {3:s}"

                res, fmt_ex, fmt_kw = escape!(ex, args; outmost=false)
                @test args == esc.([:a, :b, :(Ref(10*TOL)), :a, :b, :(Ref(10*TOL))])
                @test res == Expr(:call, esc(:.≈), 
                                  :(ARG[4]), :(ARG[5]), 
                                  Expr(:kw, :atol, :(ARG[6].x)))
                @test stringify!(fmt_ex) == "≈({4:s}, {5:s}, atol = {6:s})"
                @test stringify!(fmt_kw) == ""
            end

            ex = :(.≉(a, b, rtol=1, atol=1))
            @testset "ex: $ex" begin
                args = Expr[]

                res, fmt_ex, fmt_kw = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :b, :(Ref(1)), :(Ref(1))])
                @test res == Expr(:call, esc(:.≉), 
                                  :(ARG[1]), :(ARG[2]), 
                                  Expr(:kw, :rtol, :(ARG[3].x)), 
                                  Expr(:kw, :atol, :(ARG[4].x)))
                @test stringify!(fmt_ex) == "{1:s} ≉ {2:s}"
                @test stringify!(fmt_kw) == "rtol = {3:s}, atol = {4:s}"

                res, fmt_ex, fmt_kw = escape!(ex, args; outmost=false)
                @test args == esc.([:a, :b, :(Ref(1)), :(Ref(1)), :a, :b, :(Ref(1)), :(Ref(1))])
                @test res == Expr(:call, esc(:.≉), 
                                  :(ARG[5]), :(ARG[6]), 
                                  Expr(:kw, :rtol, :(ARG[7].x)), 
                                  Expr(:kw, :atol, :(ARG[8].x)))
                @test stringify!(fmt_ex) == "≉({5:s}, {6:s}, rtol = {7:s}, atol = {8:s})"
                @test stringify!(fmt_kw) == ""
            end
        end

        @testset "displayable function" begin
            ex = :(isnan.(a))

            @testset "ex: $ex" begin
                args = Expr[]

                res, fmt_ex, fmt_kw = escape!(ex, args; outmost=true)
                @test args == esc.([:a])
                @test res == Expr(:., esc(:isnan), Expr(:tuple, :(ARG[1])))
                @test stringify!(fmt_ex) == "isnan.({1:s})"
                @test stringify!(fmt_kw) == ""

                res, fmt_ex, fmt_kw = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :a])
                @test res == Expr(:., esc(:isnan), Expr(:tuple, :(ARG[2])))
                @test stringify!(fmt_ex) == "isnan.({2:s})"
                @test stringify!(fmt_kw) == ""
            end

            ex = :(isnan.(a = 1))
            @testset "ex: $ex" begin
                args = Expr[]

                res, fmt_ex, fmt_kw = escape!(ex, args; outmost=true)
                @test args == esc.([:(Ref(1))])
                @test res == Expr(:., esc(:isnan), Expr(:tuple, Expr(:kw, :a, :(ARG[1].x))))
                @test stringify!(fmt_ex) == "isnan.()"
                @test stringify!(fmt_kw) == "a = {1:s}"

                res, fmt_ex, fmt_kw = escape!(ex, args; outmost=false)
                @test args == esc.([:(Ref(1)), :(Ref(1))])
                @test res == Expr(:., esc(:isnan), Expr(:tuple, Expr(:kw, :a, :(ARG[2].x))))
                @test stringify!(fmt_ex) == "isnan.(a = {2:s})"
                @test stringify!(fmt_kw) == ""
            end

            ex = :(isnan.())
            @testset "ex: $ex" begin
                args = Expr[]

                res, fmt_ex, fmt_kw = escape!(ex, args; outmost=true)
                @test args == esc.([])
                @test res == Expr(:., esc(:isnan), Expr(:tuple))
                @test stringify!(fmt_ex) == "isnan.()"
                @test stringify!(fmt_kw) == ""

                res, fmt_ex, fmt_kw = escape!(ex, args; outmost=false)
                @test args == esc.([])
                @test res == Expr(:., esc(:isnan), Expr(:tuple))
                @test stringify!(fmt_ex) == "isnan.()"
                @test stringify!(fmt_kw) == ""
            end

            ex = :(isapprox.(a, b, atol=1))
            @testset "ex: $ex" begin
                args = Expr[]

                res, fmt_ex, fmt_kw = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :b, :(Ref(1))])
                @test res == Expr(:., esc(:isapprox), Expr(:tuple, :(ARG[1]), :(ARG[2]), Expr(:kw, :atol, :(ARG[3].x))))
                @test stringify!(fmt_ex) == "isapprox.({1:s}, {2:s})"
                @test stringify!(fmt_kw) == "atol = {3:s}"

                res, fmt_ex, fmt_kw = escape!(ex, args; outmost=false)
                @test args == esc.([:a, :b, :(Ref(1)), :a, :b, :(Ref(1))])
                @test res == Expr(:., esc(:isapprox), Expr(:tuple, :(ARG[4]), :(ARG[5]), Expr(:kw, :atol, :(ARG[6].x))))
                @test stringify!(fmt_ex) == "isapprox.({4:s}, {5:s}, atol = {6:s})"
                @test stringify!(fmt_kw) == ""
            end

            ex = :(isapprox.(a, b, atol=1, rtol=1))
            @testset "ex: $ex" begin
                args = Expr[]

                res, fmt_ex, fmt_kw = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :b, :(Ref(1)), :(Ref(1))])
                @test res == Expr(:., esc(:isapprox), Expr(:tuple, :(ARG[1]), :(ARG[2]), Expr(:kw, :atol, :(ARG[3].x)), Expr(:kw, :rtol, :(ARG[4].x))))
                @test stringify!(fmt_ex) == "isapprox.({1:s}, {2:s})"
                @test stringify!(fmt_kw) == "atol = {3:s}, rtol = {4:s}"
            end

        end

        # @testset "complicated expressions" begin
        #     ex = :(a .&& f.(b) .&& .!isnan.(x) .&& isapprox.(y, z, atol=1))
        #     @testset "ex: $ex" begin
        #         ex, args = TM.preprocess(ex), []
        #         res_ex, res_str, res_fmt, _ = TM.recurse_escape!(args, deepcopy(ex), isoutmost=true)

        #         @test args == esc.([:a, :(f.(b)), :x, :y, :z, :(Ref(1))])
        #         res_ex1 = :(ARG[1])
        #         res_ex2 = :(ARG[2])
        #         res_ex3 = Expr(:call, esc(:.!), Expr(:., esc(:isnan), Expr(:tuple, :(ARG[3]))))
        #         res_ex4 = Expr(:., esc(:isapprox), Expr(:tuple, :(ARG[4]), :(ARG[5]), Expr(:kw, :atol, :(ARG[6].x))))
        #         res_ex = :($(res_ex1) .&& $(res_ex2) .&& $(res_ex3) .&& $(res_ex4))
        #         @test res_ex == res_ex
        #         @test res_str == "a .&& f.(b) .&& .!isnan.(x) .&& isapprox.(y, z, atol = 1)"
        #         @test res_fmt == "{1:s} && {2:s} && !isnan({3:s}) && isapprox({4:s}, {5:s}, atol = {6:s})"
        #     end
        # end
    end

    @testset "printing utilities" begin
        @testset "stringify_idxs()" begin
            I = CartesianIndex
            @test TM.stringify_idxs([1,2,3]) == ["1", "2", "3"]
            @test TM.stringify_idxs([1,100,10]) == ["  1", "100", " 10"]
            @test TM.stringify_idxs([I(1,1), I(1,10), I(100,1)]) == [
                                    "  1, 1", "  1,10", "100, 1"]
        end

        # @testset "print_failures()" begin
            
        #     printfunc = (args...) -> TM.print_failures(args...; prefix="", max_vals=4)

        #     msg = (io, idx) -> print(io, 2*idx)
        #     idxs = [1,2,3]
        #     exp = "\nidx=[1]: 2\nidx=[2]: 4\nidx=[3]: 6"
        #     @test occursin(exp, sprint(printfunc, idxs, msg))

        #     msg = (io, idx) -> print(io, sum(idx.I))
        #     idxs = CartesianIndex.([(1,1), (1,10), (10,1)])
        #     exp = "\nidx=[ 1, 1]: 2\nidx=[ 1,10]: 11\nidx=[10, 1]: 11"
        #     @test occursin(exp, sprint(printfunc, idxs, msg))

        #     # Wrap to 
        #     msg = (io, idx) -> print(io, idx)
        #     idxs = 1:20
        #     exp = "\nidx=[ 1]: 1\nidx=[ 2]: 2\n⋮\nidx=[19]: 19\nidx=[20]: 20"
        #     @test occursin(exp, sprint(printfunc, idxs, msg))
        # end

    end
    # @testset "eval_testall()" begin
    #     destyle = x -> replace(x, r"\e\[\d+m" => "")
    #     struct TestStruct
    #         x::Symbol
    #     end

    #     @testset "invalid broadcast behaviour" begin

    #     end

    #     @testset "evaled is not array or bool" begin
    #         f = (evaled) -> TM.eval_testall(evaled, [evaled], "", "", LineNumberNode(1))

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
    #         f = (evaled) -> TM.eval_testall(evaled, [evaled], "", "", LineNumberNode(1))

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
    #         f = (evaled) -> TM.eval_testall(evaled, [evaled], "{1:s}", "", LineNumberNode(1))
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

    #         f = (args...) -> TM.eval_testall(args..., LineNumberNode(1))

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
    #         f = (args...) -> TM.eval_testall(args..., LineNumberNode(1))

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

    # @testset "@testall" begin
    #     a = [1,2,3]
    #     b = a .+ 0.01
    #     c = a .+ 1e-10 

    #     # Comparison (from call)
    #     @testall a == 1:3
    #     @testall a .<= b
    #     @testall 5:7 .>= b
    #     @testall a ≈ c
    #     @testall a .≉ b
    #     @testall [Int, Float64] <: Real
    #     @testall [Real, Integer] .>: Int16
    #     @testall [1:2, 1:3, 1:4] ⊆ Ref(0:5)

    #     # Approx special case
    #     HIGH_TOL = 1e-1 # to check local scope
    #     @testall a ≈ c atol=1e-8
    #     @testall a .≈ c atol=HIGH_TOL # Check local scope
    #     @testall a .≉ b atol=1e-8
    #     @testall .≈(a, c) atol=1e-8
    #     @testall ≈(a, b, atol=1e-1)
    #     @testall .≈(a, b; atol=HIGH_TOL)
    #     @testall .≉(a, b; atol=1e-8)
    #     @testall .≉(a, b; atol=1e-8) rtol=1e-8

    #     # Displayed function
        
    #     @testall occursin(r"(a|b){3}", ["saaa", "baab", "aabaa"])

    #     # Fall back
    #     func() = ([1, 2, 3] .> 0)
    #     @testall func()
    #     @testall func() .&& func()

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