
@testset "@test_subset" begin
    @testset "_get_failures_issubset" begin
        s1, s2 = Set([1,2,3]), Set([1,2,3])
        @test TME._get_failures_issubset(s1, s2) == Set()

        s1, s2 = Set([1,2,3]), Set([1, 2, 4])
        @test TME._get_failures_issubset(s1, s2) == Set([3])

        s1, s2 = Set([1,2,4]), Set([1,2,5.2])
        @test TME._get_failures_issubset(s1, s2) == Set([4])

        v1, v2 = [1,2,1,2], [1,2,3]
        @test TME._get_failures_issubset(v1, v2) == Set()

        v1, v2 = [:b, :a, :a, :b, :d, :e], [:c, :a]
        @test TME._get_failures_issubset(v1, v2) == Set([:b, :d, :e])
    end

    @testset "_get_test_message_issubset" begin
        s1, s2 = Set([1,2,3]), Set([1,2,3])
        failures = TME._get_failures_issubset(s1, s2)
        @test TME._get_test_message_issubset(failures) === nothing

        s1, s2 = Set([1,2,3]), Set([1.0, 2.0, 4.0])
        failures = TME._get_failures_issubset(s1, s2)
        @test TME._get_test_message_issubset(failures) == "LHS values not a subset of RHS values.\n    Missing from RHS: [3]"

        v1, v2 = [:b, :a, :a, :b, :d, :e], [:c, :a]
        failures = TME._get_failures_issubset(v1, v2)
        @test TME._get_test_message_issubset(failures) == "LHS values not a subset of RHS values.\n    Missing from RHS: [b, d, e]"
    end

    @testset "_process_test_expr_issubset!" begin
        @test TME._process_test_expr_issubset!(:(a ⊆ b)) == :(a ⊆ b)
        @test TME._process_test_expr_issubset!(:(1 ⊆ b)) == :(1 ⊆ b)

        @test_throws ErrorException("\
            invalid test macro call: @test_issubset a != b \n\
            Must be of the form @test_issubset a ⊆ b\
        ") TME._process_test_expr_issubset!(:(a != b))

        @test_throws ErrorException("\
            invalid test macro call: @test_issubset a ⊆ b atol = 1\n\
            No keyword arguments allowed.\
        ") TME._process_test_expr_issubset!(:(a ⊆ b), :(atol=1))
    end

    @testset "_get_test_result_issubset" begin
        s1, s2 = Set([1,2,3]), Set([1,2,3])
        result = TME._get_test_result_issubset(s1, s2, "s1 ⊆ s2")
        @test result isa Test.Pass

        s1, s2 = Set([1,2,3]), Set([1.0, 2.0, 4.0])
        result = TME._get_test_result_issubset(s1, s2, "s1 ⊆ s2")
        @test result isa Test.Fail
        @test result.orig_expr == "s1 ⊆ s2"
        @test result.data == "LHS values not a subset of RHS values.\n    Missing from RHS: [3]"
    end

    @testset "passing tests" begin
        @test_issubset 2 ⊆ 1:3
        @test_issubset Set([1,2,3]) ⊆ 1:3
        @test_issubset [:a, :b, :b] ⊆ Set([:a, :b, :d])
    end
end