@testset "test_all.jl" begin

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

    @testset "preprocess_test_all(ex)" begin

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
                proc_ex = TM.preprocess_test_all(ex)
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
                proc_ex = TM.preprocess_test_all(ex)
                @test proc_ex == res 
                @test proc_ex !== res # returns new expression
            end
        end

        @testset "no preprocess_test_alling" begin
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
                @test TM.preprocess_test_all(deepcopy(ex)) == ex 
                @test TM.preprocess_test_all(ex) === ex
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
                ex = TM.preprocess_test_all(ex)
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
                ex = TM.preprocess_test_all(ex)
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
                ex = TM.preprocess_test_all(ex)
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
                ex = TM.preprocess_test_all(ex)
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
                ex = TM.preprocess_test_all(ex)
                @test TM.isvecdisplayexpr(ex) === res
            end
        end
    end

    @testset "recurse_process!()" begin 

        escape! = (ex, args; kws...) -> TM.recurse_process!(deepcopy(ex), args; kws...)
        stringify! = fmt_io -> TM.stringify!(fmt_io)
        @testset "basecase" begin

            cases = [
                :(1),
                :(a), 
                :(:a),
                :([1,2]), 
                :(a[1]),
                :(g(x)), 
                :(g.(x,a=1;b=b)), 
                :(a + b), 
                :(a .- b),
                :(a...), 
                :(a .&& b),
                :(a:length(b)),
            ]

            @testset "ex: $ex" for ex in cases
                args = Expr[]

                res, str, fmt  = escape!(ex, args; outmost=true)
                @test args == Expr[esc(ex)]
                @test res == :(ARG[1])
                @test stringify!(str) == sprint(Base.show_unquoted, ex)
                @test stringify!(fmt) == "{1:s}"

                res, str, fmt  = escape!(ex, args; outmost=false)
                @test args == Expr[esc(ex), esc(ex)]
                @test res == :(ARG[2])
                @test stringify!(str) == sprint(Base.show_unquoted, ex)
                @test stringify!(fmt) == "{2:s}"
            end
        end

        @testset "keywords" begin
            kw = Expr(:kw, :a, 1)
            @testset "kw: $(kw.args[1]) = $(kw.args[2])" begin
                args = Expr[]

                res, str, fmt = escape!(kw, args)
                @test args == [esc(:(Ref(1)))]
                @test res == Expr(:kw, :a, :(ARG[1].x))
                @test stringify!(str) == "a=1"
                @test stringify!(fmt) == "a={1:s}"

                res, str, fmt = escape!(kw, args)
                @test args == [esc(:(Ref(1))), esc(:(Ref(1)))]
                @test res == Expr(:kw, :a, :(ARG[2].x))
                @test stringify!(str) == "a=1"
                @test stringify!(fmt) == "a={2:s}"
            end

            kw = Expr(:kw, :atol, :(1+TOL))
            @testset "kw: $(kw.args[1]) = $(kw.args[2])" begin
                args = Expr[]

                res, str, fmt = escape!(kw, args)
                @test args == [esc(:(Ref(1+TOL)))]
                @test res == Expr(:kw, :atol, :(ARG[1].x))
                @test stringify!(str) == "atol=1 + TOL"
                @test stringify!(fmt) == "atol={1:s}"

                res, str, fmt = escape!(kw, args)
                @test args == [esc(:(Ref(1+TOL))), esc(:(Ref(1+TOL)))]
                @test res == Expr(:kw, :atol, :(ARG[2].x))
                @test stringify!(str) == "atol=1 + TOL"
                @test stringify!(fmt) == "atol={2:s}"
            end
        end

        @testset "negation" begin
            ex = :(.!a)
            @testset "ex: $ex" begin
                args = Expr[]

                res, str, fmt = escape!(ex, args; outmost=true)
                @test args == Expr[esc(:a)]
                @test res == Expr(:call, esc(:.!), :(ARG[1]))
                @test stringify!(str) == ".!a"
                @test stringify!(fmt) == "!{1:s}"

                res, str, fmt = escape!(ex, args; outmost=false)
                @test args == Expr[esc(:a), esc(:a)]
                @test res == Expr(:call, esc(:.!), :(ARG[2]))
                @test stringify!(str) == ".!a"
                @test stringify!(fmt) == "!{2:s}"
            end
        end

        @testset "logical" begin
            ex = :(a .& b)
            @testset "ex: $ex" begin
                args = Expr[]

                res, str, fmt = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :b])
                @test res == Expr(:call, esc(:.&), :(ARG[1]), :(ARG[2]))
                @test stringify!(str) == "a .& b"
                @test stringify!(fmt) == "{1:s} & {2:s}"

                res, str, fmt = escape!(ex, args; outmost=false)
                @test args == Expr[esc(:a), esc(:b), esc(:a), esc(:b)]
                @test res == Expr(:call, esc(:.&), :(ARG[3]), :(ARG[4]))
                @test stringify!(str) == "(a .& b)"
                @test stringify!(fmt) == "({3:s} & {4:s})"
            end

            ex = :(a .| b .| c)
            @testset "ex: $ex" begin
                args = Expr[]

                res, str, fmt = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :b, :c])
                inner_res = Expr(:call, esc(:.|), :(ARG[1]), :(ARG[2]))
                @test res == Expr(:call, esc(:.|), inner_res, :(ARG[3]))
                @test stringify!(str) == "a .| b .| c"
                @test stringify!(fmt) == "{1:s} | {2:s} | {3:s}"

                res, str, fmt = escape!(ex, args; outmost=false)
                @test args == esc.([:a, :b, :c, :a, :b, :c])
                inner_res = Expr(:call, esc(:.|), :(ARG[4]), :(ARG[5]))
                @test res == Expr(:call, esc(:.|), inner_res, :(ARG[6]))
                @test stringify!(str) == "(a .| b .| c)"
                @test stringify!(fmt) == "({4:s} | {5:s} | {6:s})"
            end

            ex = :(a .& b .⊻ c .⊽ d .| e)
            @testset "ex: $ex" begin
                args = Expr[]

                res, str, fmt = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :b, :c, :d, :e])
                inner_res = Expr(:call, esc(:.&), :(ARG[1]), :(ARG[2]))
                inner_res = Expr(:call, esc(:.⊻), inner_res, :(ARG[3]))
                inner_res = Expr(:call, esc(:.⊽), inner_res, :(ARG[4]))
                @test res == Expr(:call, esc(:.|), inner_res, :(ARG[5]))
                @test stringify!(str) == "a .& b .⊻ c .⊽ d .| e"
                @test stringify!(fmt) == "{1:s} & {2:s} ⊻ {3:s} ⊽ {4:s} | {5:s}"
            end

            ex = :(.⊽(a, b, c))
            @testset "ex: $ex" begin
                args = Expr[]

                res, str, fmt = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :b, :c])
                @test res == Expr(:call, esc(:.⊽), :(ARG[1]), :(ARG[2]), :(ARG[3]))
                @test stringify!(str) == "a .⊽ b .⊽ c"
                @test stringify!(fmt) == "{1:s} ⊽ {2:s} ⊽ {3:s}"
            end
        end

        @testset "comparison" begin
            ex = :(a .== b)
            @testset "ex: $ex" begin
                args = Expr[]

                res, str, fmt = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :b])
                @test res == Expr(:comparison, :(ARG[1]), esc(:.==), :(ARG[2]))
                @test stringify!(str) == "a .== b"
                @test stringify!(fmt) == "{1:s} == {2:s}"

                res, str, fmt = escape!(ex, args; outmost=false)
                @test args == esc.([:a, :b, :a, :b])
                @test res == Expr(:comparison, :(ARG[3]), esc(:.==), :(ARG[4]))
                @test stringify!(str) == "(a .== b)"
                @test stringify!(fmt) == "({3:s} == {4:s})"
            end

            ex = :(a .≈ b .> c)
            @testset "ex: $ex" begin
                args = Expr[]

                res, str, fmt = escape!(ex, args; outmost=false)
                @test args == esc.([:a, :b, :c])
                @test res == Expr(:comparison, :(ARG[1]), esc(:.≈), :(ARG[2]), esc(:.>), :(ARG[3]))
                @test stringify!(str) == "(a .≈ b .> c)"
                @test stringify!(fmt) == "({1:s} ≈ {2:s} > {3:s})"
            end

            ex = :(a .<: b .>: c)
            @testset "ex: $ex" begin
                args = Expr[]

                res, str, fmt = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :b, :c])
                @test res == Expr(:comparison, :(ARG[1]), esc(:.<:), :(ARG[2]), esc(:.>:), :(ARG[3]))
                @test stringify!(str) == "a .<: b .>: c"
                @test stringify!(fmt) == "{1:s} <: {2:s} >: {3:s}"
            end
        end

        @testset "approx" begin
            ex = :(.≈(a, b, atol=10*TOL))
            @testset "ex: $ex" begin
                args = Expr[]

                res, str, fmt = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :b, :(Ref(10*TOL))])
                @test res == Expr(:call, esc(:.≈), 
                                  :(ARG[1]), :(ARG[2]), 
                                  Expr(:kw, :atol, :(ARG[3].x)))
                @test stringify!(str) == ".≈(a, b, atol=10TOL)"
                @test stringify!(fmt) == "{1:s} ≈ {2:s} (atol={3:s})"

                res, str, fmt = escape!(ex, args; outmost=false)
                @test args == esc.([:a, :b, :(Ref(10*TOL)), :a, :b, :(Ref(10*TOL))])
                @test res == Expr(:call, esc(:.≈), 
                                  :(ARG[4]), :(ARG[5]), 
                                  Expr(:kw, :atol, :(ARG[6].x)))
                @test stringify!(str) == ".≈(a, b, atol=10TOL)"
                @test stringify!(fmt) == "≈({4:s}, {5:s}, atol={6:s})"
            end

            ex = :(.≉(a, b, rtol=1, atol=1))
            @testset "ex: $ex" begin
                args = Expr[]

                res, str, fmt = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :b, :(Ref(1)), :(Ref(1))])
                @test res == Expr(:call, esc(:.≉), 
                                  :(ARG[1]), :(ARG[2]), 
                                  Expr(:kw, :rtol, :(ARG[3].x)), 
                                  Expr(:kw, :atol, :(ARG[4].x)))
                @test stringify!(str) == ".≉(a, b, rtol=1, atol=1)"
                @test stringify!(fmt) == "{1:s} ≉ {2:s} (rtol={3:s}, atol={4:s})"

                res, str, fmt = escape!(ex, args; outmost=false)
                @test args == esc.([:a, :b, :(Ref(1)), :(Ref(1)), :a, :b, :(Ref(1)), :(Ref(1))])
                @test res == Expr(:call, esc(:.≉), 
                                  :(ARG[5]), :(ARG[6]), 
                                  Expr(:kw, :rtol, :(ARG[7].x)), 
                                  Expr(:kw, :atol, :(ARG[8].x)))
                @test stringify!(str) == ".≉(a, b, rtol=1, atol=1)"
                @test stringify!(fmt) == "≉({5:s}, {6:s}, rtol={7:s}, atol={8:s})"
            end
        end

        @testset "displayable function" begin
            ex = :(isnan.(a))

            @testset "ex: $ex" begin
                args = Expr[]

                res, str, fmt = escape!(ex, args; outmost=true)
                @test args == esc.([:a])
                @test res == Expr(:., esc(:isnan), Expr(:tuple, :(ARG[1])))
                @test stringify!(str) == "isnan.(a)"
                @test stringify!(fmt) == "isnan({1:s})"

                res, str, fmt = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :a])
                @test res == Expr(:., esc(:isnan), Expr(:tuple, :(ARG[2])))
                @test stringify!(str) == "isnan.(a)"
                @test stringify!(fmt) == "isnan({2:s})"
            end

            ex = :(isnan.(a = 1))
            @testset "ex: $ex" begin
                args = Expr[]

                res, str, fmt = escape!(ex, args; outmost=true)
                @test args == esc.([:(Ref(1))])
                @test res == Expr(:., esc(:isnan), Expr(:tuple, Expr(:kw, :a, :(ARG[1].x))))
                @test stringify!(str) == "isnan.(a=1)"
                @test stringify!(fmt) == "isnan(a={1:s})"

                res, str, fmt = escape!(ex, args; outmost=false)
                @test args == esc.([:(Ref(1)), :(Ref(1))])
                @test res == Expr(:., esc(:isnan), Expr(:tuple, Expr(:kw, :a, :(ARG[2].x))))
                @test stringify!(str) == "isnan.(a=1)"
                @test stringify!(fmt) == "isnan(a={2:s})"
            end

            ex = :(isnan.())
            @testset "ex: $ex" begin
                args = Expr[]

                res, str, fmt = escape!(ex, args; outmost=true)
                @test args == esc.([])
                @test res == Expr(:., esc(:isnan), Expr(:tuple))
                @test stringify!(str) == "isnan.()"
                @test stringify!(fmt) == "isnan()"

                res, str, fmt = escape!(ex, args; outmost=false)
                @test args == esc.([])
                @test res == Expr(:., esc(:isnan), Expr(:tuple))
                @test stringify!(str) == "isnan.()"
                @test stringify!(fmt) == "isnan()"
            end

            ex = :(isapprox.(a, b, atol=1))
            @testset "ex: $ex" begin
                args = Expr[]

                res, str, fmt = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :b, :(Ref(1))])
                @test res == Expr(:., esc(:isapprox), Expr(:tuple, :(ARG[1]), :(ARG[2]), Expr(:kw, :atol, :(ARG[3].x))))
                @test stringify!(str) == "isapprox.(a, b, atol=1)"
                @test stringify!(fmt) == "isapprox({1:s}, {2:s}, atol={3:s})"

                res, str, fmt = escape!(ex, args; outmost=false)
                @test args == esc.([:a, :b, :(Ref(1)), :a, :b, :(Ref(1))])
                @test res == Expr(:., esc(:isapprox), Expr(:tuple, :(ARG[4]), :(ARG[5]), Expr(:kw, :atol, :(ARG[6].x))))
                @test stringify!(str) == "isapprox.(a, b, atol=1)"
                @test stringify!(fmt) == "isapprox({4:s}, {5:s}, atol={6:s})"

            end

            ex = :(isapprox.(a, b, atol=1, rtol=1))
            @testset "ex: $ex" begin
                args = Expr[]

                res, str, fmt = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :b, :(Ref(1)), :(Ref(1))])
                @test res == Expr(:., esc(:isapprox), Expr(:tuple, :(ARG[1]), :(ARG[2]), Expr(:kw, :atol, :(ARG[3].x)), Expr(:kw, :rtol, :(ARG[4].x))))
                @test stringify!(str) == "isapprox.(a, b, atol=1, rtol=1)"
                @test stringify!(fmt) == "isapprox({1:s}, {2:s}, atol={3:s}, rtol={4:s})"
            end

        end

        @testset "complicated expressions" begin
            ex = :(a .& f.(b) .& .!isnan.(x) .& .≈(y, z, atol=TOL))
            @testset "ex: $ex" begin
                args = Expr[]

                res, str, fmt = escape!(ex, args; outmost=true)
                @test args == esc.([:a, :(f.(b)), :x, :y, :z, :(Ref(TOL))])
                inner_res1 = :(ARG[1])
                inner_res2 = Expr(:call, esc(:.&), inner_res1, :(ARG[2]))
                inner_res3 = Expr(:call, esc(:.!), Expr(:., esc(:isnan), Expr(:tuple, :(ARG[3]))))
                inner_res4 = Expr(:call, esc(:.&), inner_res2, inner_res3)
                inner_res5 = Expr(:call, esc(:.≈), :(ARG[4]), :(ARG[5]), Expr(:kw, :atol, :(ARG[6].x)))
                @test res == Expr(:call, esc(:.&), inner_res4, inner_res5)
                @test stringify!(str) == "a .& f.(b) .& .!isnan.(x) .& .≈(y, z, atol=TOL)"
                @test stringify!(fmt) == "{1:s} & {2:s} & !isnan({3:s}) & ≈({4:s}, {5:s}, atol={6:s})"
            end
        end

        @testset "styling" begin
            f = ex -> begin
                args = Expr[]
                _, str, fmt = TM.recurse_process!(ex, args; outmost=true)
                TM.stringify!(str), TM.stringify!(fmt)
            end

            TM.enable_failure_styling()

            # Base case
            str, fmt = f(:(a))
            @test occursin(ansire("\ea\e"), str)
            @test occursin(ansire("\e{1:s}\e"), fmt)
            str, fmt = f(:(a .+ b))
            @test occursin(ansire("\ea \\.\\+ b\e"), str)
            @test occursin(ansire("\e{1:s}\e"), fmt)
            str, fmt = f(:(g.(x, a=1)))
            @test occursin(ansire("\eg\\.\\(x, a = 1\\)\e"), str)
            @test occursin(ansire("\e{1:s}\e"), fmt)
            str, fmt = f(:([1,2,3]))
            @test occursin(ansire("\e\\[1, 2, 3\\]\e"), str)
            @test occursin(ansire("\e{1:s}\e"), fmt)
            
            # keywords
            str, fmt = f(Expr(:kw, :a, 1))
            @test occursin(ansire("a=\e1\e"), str)
            @test occursin(ansire("a=\e{1:s}\e"), fmt)
            str, fmt = f(Expr(:kw, :atol, :(1+TOL)))
            @test occursin(ansire("atol=\e1 \\+ TOL\e"), str)
            @test occursin(ansire("atol=\e{1:s}\e"), fmt)

            # negation
            str, fmt = f(:(.!a))
            @test occursin(ansire("\\.!\ea\e"), str)

            # logical
            str, fmt = f(:(a .& b))
            @test occursin(ansire("\ea\e \\.& \eb\e"), str)
            @test occursin(ansire("\e{1:s}\e & \e{2:s}\e"), fmt)
            str, fmt = f(:(a .| b .⊻ c))
            @test occursin(ansire("\ea\e \\.| \eb\e .⊻ \ec\e"), str)
            @test occursin(ansire("\e{1:s}\e | \e{2:s}\e ⊻ \e{3:s}\e"), fmt)

            # comparison
            str, fmt = f(:(a .& b .| c))
            @test occursin(ansire("\ea\e \\.& \eb\e \\.| \ec\e"), str)
            @test occursin(ansire("\e{1:s}\e & \e{2:s}\e | \e{3:s}\e"), fmt)

            # approx
            str, fmt = f(:(.≈(a, b, atol=10*TOL)))
            @test occursin(ansire("\\.≈\\(\ea\e, \eb\e, atol=\e10TOL\e\\)"), str)
            @test occursin(ansire("\e{1:s}\e ≈ \e{2:s}\e \\(atol=\e{3:s}\e\\)"), fmt)

            # displayable function
            str, fmt = f(:(isnan.(x)))
            @test occursin(ansire("isnan\\.\\(\ex\e\\)"), str)
            @test occursin(ansire("isnan\\(\e{1:s}\e\\)"), fmt)
            str, fmt = f(:(isnan.(x, a=1)))
            @test occursin(ansire("isnan\\.\\(\ex\e, a=\e1\e\\)"), str)
            @test occursin(ansire("isnan\\(\e{1:s}\e, a=\e{2:s}\e\\)"), fmt)

            TM.disable_failure_styling()
        end
    end

    @testset "printing utilities" begin

        @testset "get/set max print failures" begin
            @test_throws AssertionError TM.set_max_print_failures(-1)

            TM.set_max_print_failures(10)
            @test TM.set_max_print_failures(5) == 10
            @test TM.set_max_print_failures(nothing) == 5
            @test TM.set_max_print_failures() == typemax(Int64)
        end

        @testset "stringify_idxs()" begin
            I = CartesianIndex
            @test TM.stringify_idxs([1,2,3]) == ["1", "2", "3"]
            @test TM.stringify_idxs([1,100,10]) == ["  1", "100", " 10"]
            @test TM.stringify_idxs([I(1,1), I(1,10), I(100,1)]) == [
                                    "  1, 1", "  1,10", "100, 1"]
        end

        @testset "print_failures()" begin
            printfunc = (args...) -> sprint(TM.print_failures, args...)

            # Without abbreviating output
            f = (io, idx) -> print(io, 2 * idx)
            @test printfunc(1:3, f) == "\n[1]: 2\n[2]: 4\n[3]: 6"
            @test printfunc(1:3, f, "*") == "\n*[1]: 2\n*[2]: 4\n*[3]: 6"

            f = (io, idx) -> print(io, sum(idx.I))
            idxs = CartesianIndex.([(1,10), (10,1)])
            @test printfunc(idxs, f) == "\n[ 1,10]: 11\n[10, 1]: 11"

            # With abbreviating output
            f = (io, idx) -> print(io, idx)

            TM.set_max_print_failures(5)
            @test printfunc(1:9, f) == "\n[1]: 1\n[2]: 2\n[3]: 3\n⋮\n[8]: 8\n[9]: 9"

            TM.set_max_print_failures(2)
            @test printfunc(1:9, f) == "\n[1]: 1\n⋮\n[9]: 9"

            TM.set_max_print_failures(1)
            @test printfunc(1:9, f, "*") == "\n*[1]: 1\n*⋮"

            TM.set_max_print_failures(0)
            @test printfunc(1:9, f) == ""

            TM.set_max_print_failures(10)
        end

        @testset "NonBoolTypeError" begin

            f = evaled -> destyle(TM.NonBoolTypeError(evaled).msg)

            # Non-array
            @test f(1) == "1 ===> Int64"
            @test f(:a) == "a ===> Symbol"
            @test f(TestStruct(1, π)) == "S(1, 3.14159) ===> TestStruct"
            @test f(Set{Int16}(1:1)) == "Set([1]) ===> Set{Int16}"

            # Arrays
            msg = f([1,2])
            @test contains(msg, "2-element Vector{Int64} with 2 non-Boolean values:") 
            @test contains(msg, "[1]: 1 ===> Int64\n")
            @test contains(msg, "[2]: 2 ===> Int64")
            
            msg = f([true, :a, false, TestStruct(1, π)])
            @test contains(msg, "4-element Vector{Any} with 2 non-Boolean values:")
            @test contains(msg, "[2]: :a ===> Symbol")
            @test contains(msg, "[4]: S(1, 3.14159) ===> TestStruct")

            msg = f(1:3)
            @test contains(msg, "3-element UnitRange{Int64} with 3 non-Boolean values:")
        end
    end

    @testset "eval_test_all()" begin

        @testset "method error when evaling all()" begin
            f = (evaled) -> TM.eval_test_all(evaled, [evaled], "", LineNumberNode(1))
            cases = [
                :a,     
                TestStruct(1,1)
            ]
            @testset "evaled: $case" for case in cases
                @test_throws "no method matching iterate" f(case)
            end
        end

        @testset "non-Boolean in evaled argument" begin
            f = (evaled) -> TM.eval_test_all(evaled, [evaled], "", LineNumberNode(1))
            cases = [
                1, 
                1:3, 
                [true, :a], 
                [TestStruct(1,1), false], 
            ]
            @testset "evaled: $case" for case in cases
                @test_throws TM.NonBoolTypeError f(case)
            end
        end

        @testset "passing all()" begin
            f = (evaled) -> TM.eval_test_all(evaled, [evaled], "", LineNumberNode(1))
            cases = [
                true, 
                [true, true], 
                1 .== [1,1], 
                Set([]), 
                Set([true]),
                Dict([]),
                .≈(1, [1, 2], atol=2)
            ]
            @testset "evaled: $case" for case in cases
                res = f(case)
                @test res isa Test.Returned
                @test res.value === true
                @test res.data === nothing
            end
        end

        f = (evaled, terms, fmt) -> begin 
            res = TM.eval_test_all(evaled, terms, fmt, LineNumberNode(1))
            @assert res isa Test.Returned
            return destyle(res.data)
        end

        @testset "evaled === false" begin
            msg = f(1 .== 2, [1, 2], "{1:s} == {2:s}")
            @test startswith(msg, "false")
            @test contains(msg, "Argument: 1 == 2 ===> false")
        end

        @testset "evaled isa BitArray" begin
            a, b = [1,1], [1,2]
            msg = f(a .== b, [a, b], "{1:s} == {2:s}")
            @test startswith(msg, "false")
            @test contains(msg, "Argument: 2-element BitVector, 1 failure:")
            @test contains(msg, "[2]: 1 == 2 ===> false")

            a, b = 1, [1, 2, missing]
            msg = f(a .== b, [a, b], "{1:s} == {2:s}")
            @test startswith(msg, "false")
            @test occursin(r"Argument: 3-element Vector.*, 1 missing and 1 failure:", msg)
            @test contains(msg, "[2]: 1 == 2 ===> false")
            @test contains(msg, "[3]: 1 == missing ===> missing")
        end
    end

    @testset "@test_all" begin

        @testset "Pass" begin
            a = [1,2,3]
            b = a .+ 0.01
            c = a .+ 1e-10 
            TOL = 0.1

            @test_all true
            @test_all fill(true, 5)
            @test_all Dict()
            @test_all Set([true])
            @test_all a .=== a
            @test_all a .== 1:3
            @test_all a .<= b
            @test_all 5:7 .>= b
            @test_all a .≈ c
            @test_all a .≉ b
            @test_all [Real, Integer] .>: Int16
            @test_all [1:2, 1:3, 1:4] .⊆ Ref(0:5)
            @test_all occursin.(r"a|b", ["aa", "bb", "ab"])
            @test_all a .≈ b atol=TOL
            @test_all a .≉ b atol=1e-8
            @test_all Bool[1,0,1] .| Bool[1,1,0]
            @test_all Bool[1,0,0] .⊻ Bool[0,1,0] .⊻ Bool[0,0,1]
        end

        @testset "Fail" begin
            messages = []
            let fails = @testset NoThrowTestSet begin
                    # 1
                    @test_all 1:3 .== 2:4
                    push!(messages, [
                        "Expression: all(1:3 .== 2:4)",
                        "Evaluated: false",
                        "Argument: 3-element BitVector, 3 failures:",
                        "[1]: 1 == 2 ===> false",
                        "[2]: 2 == 3 ===> false",
                        "[3]: 3 == 4 ===> false",
                    ])

                    # 2
                    @test_all [1 2] .== [1, 2]
                    push!(messages, [
                        "Expression: all([1 2] .== [1, 2])",
                        "Evaluated: false",
                        "Argument: 2×2 BitMatrix, 2 failures:",
                        "[2,1]: 1 == 2 ===> false",
                        "[1,2]: 2 == 1 ===> false",
                    ])

                    # 3
                    a, b = Bool[1,0], Bool[1,1]
                    @test_all a .⊻ b
                    push!(messages, [
                        "Expression: all(a .⊻ b)",
                        "Evaluated: false",
                        "Argument: 2-element BitVector, 1 failure:",
                        "[1]: true ⊻ true ===> false",
                    ])

                    # 4
                    @test_all 1:4 .∈ Ref(1:3)
                    push!(messages, [
                        "Expression: all(1:4 .∈ Ref(1:3))",
                        "Evaluated: false",
                        "Argument: 4-element BitVector, 1 failure:",
                        "[4]: 4 ∈ 1:3 ===> false",
                    ])

                    # 5
                    a = Set([false])
                    @test_all a
                    push!(messages, [
                        "Expression: all(a)",
                        "Evaluated: false",
                        "Argument: Set{Bool} with 1 element, 1 failure",
                    ])

                    # 6
                    a = [1,2,missing]
                    @test_all a .== 1
                    push!(messages, [
                        "Expression: all(a .== 1)",
                        "Evaluated: false",
                        "Argument: 3-element Vector{Union{Missing, Bool}}, 1 missing and 1 failure:",
                        "[2]: 2 == 1 ===> false",
                        "[3]: missing == 1 ===> missing",
                    ])

                    # 7
                    @test_all 1 .== 2
                    push!(messages, [
                        "Expression: all(1 .== 2)",
                        "Evaluated: false",
                        "Argument: 1 == 2 ===> false",
                    ])

                    # 8
                    a = [1,NaN,3]
                    @test_all .!isnan.(a)
                    push!(messages, [
                        "Expression: all(.!isnan.(a))",
                        "Evaluated: false",
                        "Argument: 3-element BitVector, 1 failure:",
                        "[2]: !isnan(NaN) ===> false",
                    ])

                    # 9
                    a = [0.9, 1.0, 1.1]
                    @test_all a .≈ 1 atol=1e-2
                    push!(messages, [
                        "Expression: all(.≈(a, 1, atol=0.01))",
                        "Evaluated: false",
                        "Argument: 3-element BitVector, 2 failures:",
                        "[1]: 0.9 ≈ 1 (atol=0.01) ===> false",
                        "[3]: 1.1 ≈ 1 (atol=0.01) ===> false",
                    ])

                    # 10
                    @test_all false
                    push!(messages, [
                        "Expression: all(false)",
                        "Evaluated: false",
                        "Argument: false ===> false",
                    ])

                    # 11
                    a = [[1,2], 1, 1:2]
                    @test_all a .== Ref(1:2)
                    push!(messages, [
                        "Expression: all(a .== Ref(1:2))",
                        "Evaluated: false",
                        "Argument: 3-element BitVector, 1 failure:",
                        "[2]: 1 == 1:2 ===> false",
                    ])

                    # 12 
                    @test_all [1] .== missing
                    push!(messages, [
                        "Expression: all([1] .== missing)",
                        "Evaluated: missing",
                        "Argument: 1-element Vector{Missing}, 1 missing:",
                        "[1]: 1 == missing ===> missing",
                    ])

                    # 13
                    @test_all 1 .== missing
                    push!(messages, [
                        "Expression: all(1 .== missing)",
                        "Evaluated: missing",
                        "Argument: 1 == missing ===> missing",
                    ])
                end
                
                @testset "ex[$i]: $(fail.orig_expr)" for (i, fail) in enumerate(fails)
                    @test fail isa Test.Fail
                    @test fail.test_type === :test
                    str = sprint(show, fail)
                    for msg in messages[i]
                        @test contains(str, msg)
                    end
                end

            end # let fails

        end

        @testset "skip/broken=false" begin
            a = 1
            @test_all 1 .== 1 broken=false
            @test_all 1 .== 1 skip=false
            @test_all 1 .== 1 broken=a==2
            @test_all 1 .== 1 skip=!isone(1)
        end


        @testset "skip=true" begin
            let skips = @testset NoThrowTestSet begin
                    # 1
                    @test_all 1 .== 1 skip=true
                    # 2
                    @test_all 1 .== 2 skip=true
                    # 3
                    @test_all 1 .== error("fail gracefully") skip=true
                end

                @testset "skipped[$i]" for (i, skip) in enumerate(skips)
                    @test skip isa Test.Broken
                    @test skip.test_type === :skipped
                end
            end # let skips
        end


        @testset "broken=true" begin
            let brokens = @testset NoThrowTestSet begin
                    # 1
                    @test_all 1 .== 2 broken=true
                    # 2
                    @test_all 1 .== error("fail gracefully") broken=true
                end

                @testset "broken[$i]" for (i, broken) in enumerate(brokens)
                    @test broken isa Test.Broken
                    @test broken.test_type === :test
                end
            end # let brokens

            let unbrokens = @testset NoThrowTestSet begin
                    # 1
                    @test_all 1 .== 1 broken=true
                end

                @testset "unbroken[$i]" for (i, unbroken) in enumerate(unbrokens)
                    @test unbroken isa Test.Error
                    @test unbroken.test_type === :test_unbroken
                end
            end # let unbrokens
        end

        @testset "Error" begin
            messages = []
            let errors = @testset NoThrowTestSet begin
                    # 1
                    @test_all A
                    push!(messages, ["UndefVarError: `A` not defined"])
                    # 2
                    @test_all sqrt.([1,-1])
                    push!(messages, ["DomainError with -1.0"])
                    # 3
                    @test_all error("fail ungracefully")
                    push!(messages, ["fail ungracefully"])
                    # 4
                end

                @testset "error[$i]" for (i, error) in enumerate(errors)
                    @test error isa Test.Error
                    @test error.test_type === :test_error

                    
                    for msg in messages[i]
                        @test contains(sprint(show, error), msg)
                    end
                end
            end
        end

        @testset "evaluate arguments once" begin
            g = Int[]
            f = (x) -> (push!(g, 1); x)
            @test_all f([1,2]) .== 1:2
            @test g == [1]

            empty!(g)
            @test_all occursin.(r"a|b", f(["aa", "bb", "ab"]))
            @test g == [1]
        end

    end
end