
@testset "@test_setsequal" begin
    @testset "_get_failures_setsequal" begin
        s1, s2 = Set([1,2,3]), Set([1,2,3])
        @test TME._get_failures_setsequal(s1, s2) == (Set(), Set())

        s1, s2 = Set([1,2,3]), Set([1, 2, 4])
        @test TME._get_failures_setsequal(s1, s2) == (Set([4]), Set([3]))

        s1, s2 = Set([1,2,4]), Set([1,2,5.2])
        @test TME._get_failures_setsequal(s1, s2) == (Set([5.2]), Set([4]))

        v1, v2 = [1,2,1,2], [1,2,3]
        @test TME._get_failures_setsequal(v1, v2) == (Set([3]), Set())

        v1, v2 = [:b, :a, :a, :b, :d], [:c, :a]
        @test TME._get_failures_setsequal(v1, v2) == (Set([:c]), Set([:b, :d]))
    end

    @testset "_get_test_message_setsequal" begin
        s1, s2 = Set([1,2,3]), Set([1,2,3])
        failures = TME._get_failures_setsequal(s1, s2)
        @test TME._get_test_message_setsequal(failures) === nothing

        s1, s2 = Set([1,2,3]), Set([1.0, 2.0, 4.0])
        failures = TME._get_failures_setsequal(s1, s2)
        @test TME._get_test_message_setsequal(failures) == "Sets are not equal.\n    Missing from LHS: [4.0]\n    Missing from RHS: [3]"

        s1, s2 = Set([1,2,3]), Set([1,2])
        failures = TME._get_failures_setsequal(s1, s2)
        @test TME._get_test_message_setsequal(failures) == "Sets are not equal.\n    Missing from RHS: [3]"

        s1, s2 = Set([1,2]), Set([1.0,2.0,5.2])
        failures = TME._get_failures_setsequal(s1, s2)
        @test TME._get_test_message_setsequal(failures) == "Sets are not equal.\n    Missing from LHS: [5.2]"
    end

    @testset "_process_test_expr_setsequal!" begin
        @test TME._process_test_expr_setsequal!(:(a == b)) == :(a == b)
        @test TME._process_test_expr_setsequal!(:(1 == b)) == :(1 == b)

        @test_throws ErrorException("\
            invalid test macro call: @test_setsequal a != b \n\
            Must be of the form @test_setsequal a == b\
        ") TME._process_test_expr_setsequal!(:(a != b))

        @test_throws ErrorException("\
            invalid test macro call: @test_setsequal a == b atol = 1\n\
            No keyword arguments allowed.\
        ") TME._process_test_expr_setsequal!(:(a == b), :(atol=1))
    end

    @testset "_get_test_result_setsequal" begin
        s1, s2 = Set([1,2,3]), Set([1,2,3])
        result = TME._get_test_result_setsequal(s1, s2, "s1 == s2")
        @test result isa Test.Pass

        s1, s2 = Set([1,2,3]), Set([1,2,4])
        result = TME._get_test_result_setsequal(s1, s2, "s1 == s2")
        @test result isa Test.Fail
        @test result.orig_expr == "s1 == s2"
        @test result.data == "Sets are not equal.\n    Missing from LHS: [4]\n    Missing from RHS: [3]"
    end

    @testset "passing tests" begin
        @test_setsequal Set([1,2,3]) == Set([1,2,3])
        @test_setsequal [:a, :b, :b] == Set([:a, :b])
        @test_setsequal [1, 1, 1, 1] == 1 broken=false
    end
end