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

        v = [1, 2]
    end

end