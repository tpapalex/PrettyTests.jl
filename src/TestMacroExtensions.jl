module TestMacroExtensions
    using Test, Format
    import Test: Result, Pass, Fail, Broken, Error
    import Test: ExecutionResult, Returned, Threw
    import Test: get_testset, record
    import Test: do_test, do_broken_test

    export @test_setop
    export @testall

    include("utilities.jl")
    include("test_setop.jl")
    include("testall.jl")

end