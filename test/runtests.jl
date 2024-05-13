using TestMacroExtensions
using Test

const TM = TestMacroExtensions

 @testset "TestMacroExtensions.jl" begin
    include("nothrowtestset.jl") # structs required for testing

    # include("utilities.jl")
    include("test_sets.jl")
    # include("test_all.jl")
end
