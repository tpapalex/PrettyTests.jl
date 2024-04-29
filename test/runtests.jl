using TestMacroExtensions
using Test

const TM = TestMacroExtensions

 @testset "TestMacroExtensions.jl" begin
    include("nothrowtestset.jl")
    include("utilities.jl")
    include("setop.jl")
    # include("vectorized.jl")
end
