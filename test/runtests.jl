using PrettyTests
using PrettyTests
using Test

const PT = PrettyTests
PT.disable_failure_styling() # Will be enabled for some tests, but mostly don't want for tests

@testset "PrettyTests.jl" begin
    include("nothrowtestset.jl") # structs used in testing of test macros

    include("helpers.jl")
    include("test_sets.jl")
    include("test_all.jl")
end
