module TestMacroExtensions
    using Test
    import Test: Result, Pass, Fail, Broken, Error
    import Test: ExecutionResult, Returned, Threw
    import Test: get_testset, record
    import Test: do_test, do_broken_test

    export @test_setop
    export @test_all

    include("utilities.jl")
    include("test_setop.jl")
    include("test_all.jl")

end