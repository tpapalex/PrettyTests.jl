using TestMacroExtensions
using Test

const TME = TestMacroExtensions

@testset "TestMacroExtensions.jl" begin
    include("utilities.jl")
    include("setsequal.jl")
    include("issubset.jl")
    include("vectorized.jl")
end
