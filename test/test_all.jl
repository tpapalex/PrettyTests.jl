@testset "vecop.jl" begin
    
    @testset "_string_idxs_justify" begin
    end

    @testset "_pretty_print_vecop_failures" begin
    end

    @testset "_get_preprocessed_expr" begin
        f = (ex, kws...) -> TM._get_preprocessed_expr(ex, kws...)

        # Normalize comparison operators
        pex, neg = f(:(a == b))
        @test pex.head === :comparison
        @test pex.args == [:a, :(==), :b]
        @test neg === false

        pex, neg = f(:(a .== b))
        @test pex.head === :comparison
        @test pex.args == [:a, :.==, :b]
        @test neg === false

        pex, neg = f(:(a != b))
        @test pex.head === :comparison
        @test pex.args == [:a, :!=, :b]
        @test neg === false

        pex, neg = f(:(a .≈ b))
        @test pex.head === :comparison
        @test pex.args == [:a, :.≈, :b]
        @test neg === false

        ex = :(a... .!= b) 
        pex, neg = f(ex) # Splat skipped
        @test ex === pex

        ex = :(a .+ b)
        pex, neg = f(ex) # Incorrect precedence skipped
        @test ex === pex

        # <: and >: as comparisons
        pex, neg = f(:(a >: b))
        @test pex.head === :comparison
        @test pex.args == [:a, :>:, :b]
        @test neg === false

        pex, neg = f(:(a <: b))
        @test pex.head === :comparison
        @test pex.args == [:a, :<:, :b]
        @test neg === false

        pex, neg = f(:(a .<: b))
        @test pex.head === :comparison
        @test pex.args == [:a, :.<:, :b]
        @test neg === false

        pex, neg = f(:(a .>: b))
        @test pex.head === :comparison
        @test pex.args == [:a, :.>:, :b]
        @test neg === false

        # Other examples
        ex = :(a .& b)
        pex, neg = f(ex) # Incorrect precedence skipped
        @test ex === pex

        ex = :(isapprox.(a, b))
        pex, neg = f(ex) # Incorrect precedence skipped
        @test ex === pex

        ex = :(myfunction(a, b...; arg=1))
        pex, neg = f(ex) # Incorrect precedence skipped
        @test ex === pex

        # With negation
        ex = :(!(a == b))
        pex, neg = f(ex)
        @test pex.head === :comparison
        @test pex.args == [:a, :(==), :b]
        @test neg === true

        ex = :(.!(occursin(a, b)))
        pex, neg = f(ex)
        @test pex.head === :call
        @test pex.args[1] === :occursin
        @test neg === true

        ex = :(.!(contains.(a, b)))
        pex, neg = f(ex)
        @test pex.head === :.
        @test pex.args[1] === :contains
        @test neg === true

    end


    @testset "@test_all" begin
        a = [1,2,3]
        b = a .+ 0.01
        c = a .+ 1e-10 

        # Comparison (from call)
        @test_all a == 1:3
        @test_all a .<= b
        @test_all 5:7 .>= b
        @test_all a ≈ c
        @test_all a .≉ b
        @test_all [Int, Float64] <: Real
        @test_all [Real, Integer] .>: Int16
        @test_all [1:2, 1:3, 1:4] ⊆ Ref(0:5)

        # Approx special case
        HIGH_TOL = 1e-1 # to check local scope
        @test_all a ≈ c atol=1e-8
        @test_all a .≈ c atol=HIGH_TOL # Check local scope
        @test_all a .≉ b atol=1e-8
        @test_all .≈(a, c) atol=1e-8
        @test_all ≈(a, b, atol=1e-1)
        @test_all .≈(a, b; atol=HIGH_TOL)
        @test_all .≉(a, b; atol=1e-8)
        @test_all .≉(a, b; atol=1e-8) rtol=1e-8

        # Displayed function
        
        @test_all occursin(r"(a|b){3}", ["saaa", "baab", "aabaa"])

        # Fall back
        func() = ([1, 2, 3] .> 0)
        @test_all func()
        @test_all func() .&& func()

    end

    @testset "_recurse_stringify_logical: output" begin
        f = ex -> TM._recurse_stringify_logical(ex)
        # Simple
        @test f(:(1)) == "1"
        @test f(:(a)) == "a"
        @test f(:(a && 1)) == "a && 1"
        @test f(:(a .&& b)) == "a .&& b"
        @test f(:(a || b)) == "a || b"

        # Multiple
        @test f(:(a && b || c)) == "a && b || c"
        @test f(:(a && b || c && true)) == "a && b || c && true"
        @test f(:(a .&& b .|| c)) == "a .&& b .|| c"
        @test f(:(a .&& b .|| c .&& true)) == "a .&& b .|| c .&& true"
        
        # With !/.!
        @test f(:(!a)) == "!a"
        @test f(:(.!a)) == ".!(a)"
        @test f(:(a && !b)) == "a && !b"
        @test f(:(a .&& .!(b))) == "a .&& .!(b)"
        @test f(:(a || !(x ≈ y))) == "a || !(x ≈ y)"
        @test f(:(a .|| .!(x .≈ y))) == "a .|| .!(x .≈ y)"

        # With :call/:., not operator
        @test f(:(g(x))) == "g(x)"
        @test f(:(g.(x))) == "g.(x)"
        @test f(:(a && g(x))) == "a && g(x)"
        @test f(:(a .&& g.(x))) == "a .&& g.(x)"
        @test f(:(g(x) && g(x))) == "g(x) && g(x)"
        @test f(:(g.(x) && g.(x))) == "g.(x) && g.(x)"

        # With :call/:., operator
        @test f(:(x == 1)) == "x == 1"
        @test f(:(x .== 1)) == "x .== 1"
        @test f(:(a && (x >= 1))) == "a && (x >= 1)"
        @test f(:(a .&& (x .< 1))) == "a .&& (x .< 1)"
        @test f(:((x ≈ y) || true)) == "(x ≈ y) || true"
        @test f(:(a .&& (x .≈ y))) == "a .&& (x .≈ y)"

        # More complicated
        @test f(:((a && b) || !c && isnan(w) || (x ≈ y + z))) == "\
                    a && b || !c && isnan(w) || (x ≈ y + z)"
        @test f(:((a .&& b) .|| .!c .&& isnan.(w) .|| (x .≈ y .+ z))) == "\
                    a .&& b .|| .!(c) .&& isnan.(w) .|| (x .≈ y .+ z)"

    end

    @testset "_recurse_vectorize_logical!" begin
        f = ex -> TM._recurse_vectorize_logical!(ex)

        @test f(:(1)) == :(1)
        @test f(:(a)) == :(a)
        @test f(:(a && 1)) == :(a .&& 1)
        @test f(:(a .&& b)) == :(a .&& b)
        @test f(:(a && b || c)) == :(a .&& b .|| c)
        @test f(:(a && b || g(x))) == :(a .&& b .|| g(x))
        @test f(:(a && b || g(x))) == :(a .&& b .|| g(x))
    end


    @testset "_recurse_stringify_logical: Meta.parse" begin
        f = ex -> ex == Meta.parse(TM._recurse_stringify_logical(ex))
        
        # Simple
        @test f(:(1))
        @test f(:(a))
        @test f(:(a && 1))
        @test f(:(a .&& b))
        @test f(:(a || b))

        # Multiple
        @test f(:(a && b || c))
        @test f(:(a && b || c && true))
        @test f(:(a .&& b .|| c))
        @test f(:(a .&& b .|| c .&& true))
        
        # With !/.!
        @test f(:(!a))
        @test f(:(.!a))
        @test f(:(a && !b))
        @test f(:(a .&& .!(b)))
        @test f(:(a || !(x ≈ y)))
        @test f(:(a .|| .!(x .≈ y)))

        # With :call/:., not operator
        @test f(:(g(x)))
        @test f(:(g.(x)))
        @test f(:(a && g(x)))
        @test f(:(a .&& g.(x)))
        @test f(:(g(x) && g(x)))
        @test f(:(g.(x) && g.(x)))

        # With :call/:., operator
        @test f(:(x == 1))
        @test f(:(x .== 1))
        @test f(:(a && (x >= 1)))
        @test f(:(a .&& (x .< 1)))
        @test f(:((x ≈ y) || true))
        @test f(:(a .&& (x .≈ y)))

        # More complicated
        @test f(:((a && b) || !c && isnan(w) || (x ≈ y + z)))
        @test f(:((a .&& b) .|| .!c .&& isnan.(w) .|| (x .≈ y .+ z)))

    end

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