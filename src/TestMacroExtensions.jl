module TestMacroExtensions
    using Test

    export @test_vectorized
    export @test_issubset
    export @test_setsequal

    include("utilities.jl")
    include("setsequal.jl")
    include("issubset.jl")
    include("vectorized.jl")

end
