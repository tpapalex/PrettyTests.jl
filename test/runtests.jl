using TestMacroExtensions
using Test

const TM = TestMacroExtensions
TM.disable_failure_styling() # Will be enabled for some tests, but mostly don't want for tests

@testset "TestMacroExtensions.jl" begin
    include("nothrowtestset.jl") # structs used in testing of test macros

    include("helpers.jl")
    include("test_sets.jl")
    # include("test_all.jl")
end
