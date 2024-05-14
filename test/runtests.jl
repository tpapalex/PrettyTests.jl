using TestMacroExtensions
using Test

const TM = TestMacroExtensions

 @testset "TestMacroExtensions.jl" begin
    include("nothrowtestset.jl") # structs used in testing of test macros

    include("helpers.jl")
    include("test_sets.jl")
    include("test_all.jl")
end
