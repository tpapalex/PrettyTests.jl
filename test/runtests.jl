using TestMacroExtensions
using Test

const TM = TestMacroExtensions

 @testset "TestMacroExtensions.jl" begin
    include("nothrowtestset.jl")
    # include("utilities.jl")
    # include("test_setop.jl")
    include("testall.jl")
end
