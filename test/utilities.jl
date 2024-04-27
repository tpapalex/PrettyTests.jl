@testset "utilities.jl" begin

    @testset "TME._extract_skip_broken_kw" begin
        @test TME._extract_skip_broken_kw() == ((), :do)

        @test TME._extract_skip_broken_kw(:(skip=false)) == ((), :do)
        @test TME._extract_skip_broken_kw(:(broken=false)) == ((), :do)

        @test TME._extract_skip_broken_kw(:(skip=true)) == ((), :skip)
        @test TME._extract_skip_broken_kw(:(broken=true)) == ((), :broken)

        @test_throws ErrorException("invalid test macro call: cannot set both skip and broken keywords") TME._extract_skip_broken_kw(:(skip=true), :(broken=true))
        @test_throws ErrorException("invalid test macro call: cannot set skip keyword multiple times") TME._extract_skip_broken_kw(:(skip=true), :(skip=false))

        @test TME._extract_skip_broken_kw(:(atol=1)) == ((:(atol=1),), :do)
        @test TME._extract_skip_broken_kw(:(atol=1), :(rtol=1)) == ((:(atol=1),:(rtol=1)), :do)

        @test TME._extract_skip_broken_kw(:(atol=1), :(broken=false)) == ((:(atol=1),), :do)
        @test TME._extract_skip_broken_kw(:(atol=1), :(skip=false)) == ((:(atol=1),), :do)

        @test TME._extract_skip_broken_kw(:(atol=1), :(skip=true)) == ((:(atol=1),), :skip)
        @test TME._extract_skip_broken_kw(:(atol=1), :(broken=true)) == ((:(atol=1),), :broken)
    end

    @testset "TME._testerror" begin
        @test ErrorException("invalid test macro call: @testvec a == b ") == TME._testerror(:testvec, :(a == b), ())
        @test ErrorException("invalid test macro call: @testvec a == b atol = 1") == TME._testerror(:testvec, :(a == b), (:(atol=1),))
        @test ErrorException("invalid test macro call: @testvec a == b \nAdditional info") == TME._testerror(:testvec, :(a == b), (), "Additional info")
        @test ErrorException("invalid test macro call: @testvec a == b rtol = 2 atol = 1\nAdditional info") == TME._testerror(:testvec, :(a == b), (:(rtol=2), :(atol=1)), "Additional info")
    end

    @testset "_get_broken_result" begin
        pass_result = () -> Test.Pass(:test, :(a == b), nothing, true, LineNumberNode(1))
        fail_result = () -> Test.Fail(:test, :(a == b), "Failed", false, LineNumberNode(1))

        result = TME._get_broken_result(pass_result(), "a == b")
        @test result isa Test.Error
        @test result.test_type == :test_unbroken
        @test result.orig_expr == "a == b"

        result = TME._get_broken_result(fail_result(), "a == b")
        @test result isa Test.Broken
        @test result.test_type == :test
        @test result.orig_expr == "a == b"
    end
end