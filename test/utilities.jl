@testset "utilities.jl" begin

    @testset "TM.MacroCallError" begin
        @test ErrorException("invalid test macro call: @testvec a == b") == TM.MacroCallError(:testvec, :(a == b), ())
        @test ErrorException("invalid test macro call: @testvec a == b atol = 1") == TM.MacroCallError(:testvec, :(a == b), (:(atol=1),))
        @test ErrorException("invalid test macro call: @testvec a == b\nAdditional info") == TM.MacroCallError(:testvec, :(a == b), (), "Additional info")
        @test ErrorException("invalid test macro call: @testvec a == b rtol = 2 atol = 1\nAdditional info") == TM.MacroCallError(:testvec, :(a == b), (:(rtol=2), :(atol=1)), "Additional info")
    end

    # @testset "_get_broken_result" begin
    #     pass_result = () -> Test.Pass(:test, :(a == b), nothing, true, LineNumberNode(1))
    #     fail_result = () -> Test.Fail(:test, :(a == b), "Failed", false, LineNumberNode(1))

    #     result = TM._get_broken_result(pass_result(), "a == b")
    #     @test result isa Test.Error
    #     @test result.test_type == :test_unbroken
    #     @test result.orig_expr == "a == b"

    #     result = TM._get_broken_result(fail_result(), "a == b")
    #     @test result isa Test.Broken
    #     @test result.test_type == :test
    #     @test result.orig_expr == "a == b"
    # end
end