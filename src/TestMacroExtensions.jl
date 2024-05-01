module TestMacroExtensions
    using Test
    import Test: Result, Pass, Fail, Broken, Error
    import Test: ExecutionResult, Returned, Threw
    import Test: get_testset, record
    import Test: do_test, do_broken_test

    export @test_setop

    include("utilities.jl")
    include("setop.jl")
    include("vecop.jl")

end
