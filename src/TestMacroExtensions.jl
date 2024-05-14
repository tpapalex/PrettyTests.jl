module TestMacroExtensions
    using Test, Format
    
    import Test: ExecutionResult, Returned, Threw, Broken
    import Test: get_testset, record
    import Test: do_test, do_broken_test

    export @test_sets
    export @test_all

    const isexpr = Meta.isexpr

    include("helpers.jl")
    include("test_sets.jl")
    include("test_all.jl")

end