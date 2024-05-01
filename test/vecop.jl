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

end