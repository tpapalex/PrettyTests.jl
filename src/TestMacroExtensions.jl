module TestMacroExtensions
    using Test
    import Test: Result, Pass, Fail, Broken, Error
    import Test: ExecutionResult, Returned, Threw
    import Test: get_testset
    import Test: do_broken_test

    # export @test_vectorized
    # export @test_issubset
    # export @test_setsequal

    include("utilities.jl")
    include("setop.jl")
    # include("setsequal.jl")
    # include("issubset.jl")
    # include("vectorized.jl")

end
