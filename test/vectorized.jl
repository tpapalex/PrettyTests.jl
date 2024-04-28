@testset "vectorized.jl" begin

    @testset "_get_failures_vectorized" begin
        lhs, rhs = [4.0, 5.0, 6.0], [7.0, 5.0, 6.0]
        @test TM._get_failures_vectorized(lhs, rhs, lhs .== rhs) == [(1, 4.0, 7.0)]
        @test TM._get_failures_vectorized(lhs, rhs, lhs .<= rhs) == []
        @test TM._get_failures_vectorized(lhs, rhs, lhs .< rhs) == [(2, 5.0, 5.0), (3, 6.0, 6.0)]

        lhs, rhs = [0, 1, 5], 0.0
        @test TM._get_failures_vectorized(lhs, rhs, lhs .== rhs) == [(2, 1, 0.0), (3, 5, 0.0)]
        @test TM._get_failures_vectorized(lhs, rhs, lhs .> rhs) == [(1, 0, 0.0)]

        lhs, rhs = [5 2 3], [2, 3]
        @test TM._get_failures_vectorized(lhs, rhs, lhs .== rhs) == [
            ((1,1), 5, 2),
            ((2,1), 5, 3),
            ((2,2), 2, 3),
            ((1,3), 3, 2),
        ]
        @test TM._get_failures_vectorized(lhs, rhs, lhs .>= rhs) == [
            ((2,2), 2, 3),
        ]

        lhs, rhs = [:a, :b, :c], [:a, :d, :c]
        @test TM._get_failures_vectorized(lhs, rhs, lhs .== rhs) == [(2, :b, :d)]
    end

    @testset "_get_test_message_vectorized" begin
        lhs, rhs = [4.0, 5.0, 6.0], [7.0, 5.0, 6.0]
        failures = TM._get_failures_vectorized(lhs, rhs, lhs .== rhs)
        @test TM._get_test_message_vectorized(failures, "==") == "Failed at 1 index.\n    [1]: 4.0 == 7.0"

        lhs, rhs = [0, 1, 5], 0.0
        failures = TM._get_failures_vectorized(lhs, rhs, lhs .<= rhs)
        @test TM._get_test_message_vectorized(failures, "<=") == "Failed at 2 indices.\n    [2]: 1 <= 0.0\n    [3]: 5 <= 0.0"

        lhs, rhs = [5 2 3], [2, 3]
        failures = TM._get_failures_vectorized(lhs, rhs, lhs .>= rhs)
        @test TM._get_test_message_vectorized(failures, ">=") == "Failed at 1 index.\n    [2,2]: 2 >= 3"

        lhs, rhs = [:a, :b, :b], :b
        failures = TM._get_failures_vectorized(lhs, rhs, lhs .>= rhs)
        @test TM._get_test_message_vectorized(failures, "==") == "Failed at 1 index.\n    [1]: :a == :b"
    end

    @testset "_process_test_expr_vectorized!" begin

        # All valid expressions, no keywords added
        @test TM._process_test_expr_vectorized!(:(a .== b)) == :(a .== b)
        @test TM._process_test_expr_vectorized!(:(a .!= b)) == :(a .!= b)
        @test TM._process_test_expr_vectorized!(:(a .≠ b)) == :(a .≠ b)
        @test TM._process_test_expr_vectorized!(:(a .< b)) == :(a .< b)
        @test TM._process_test_expr_vectorized!(:(a .> b)) == :(a .> b)
        @test TM._process_test_expr_vectorized!(:(a .<= b)) == :(a .<= b)
        @test TM._process_test_expr_vectorized!(:(a .>= b)) == :(a .>= b)
        @test TM._process_test_expr_vectorized!(:(a .≈ b)) == :(a .≈ b)
        @test TM._process_test_expr_vectorized!(:(a .≉ b)) == :(a .≉ b)
        @test TM._process_test_expr_vectorized!(:(a .& b)) == :(a .& b)
        @test TM._process_test_expr_vectorized!(:(a .&& b)) == :(a .&& b)
        @test TM._process_test_expr_vectorized!(:(a .| b)) == :(a .| b)
        @test TM._process_test_expr_vectorized!(:(a .|| b)) == :(a .|| b)

        # With keywords added
        @test TM._process_test_expr_vectorized!(:(a .≈ b), :(atol=1e-6)) == :(.≈(a, b, atol=1.0e-6))
        @test TM._process_test_expr_vectorized!(:(a .≉ b), :(rtol=1e-6)) == :(.≉(a, b, rtol=1.0e-6))
        @test TM._process_test_expr_vectorized!(:(a .≉ b), :(rtol=1e-6), :(atol=1)) == :(.≉(a, b, rtol=1.0e-6, atol=1))

        # Invalid expression, not supported
        @test_throws ErrorException("\
            invalid test macro call: @test_vectorized a .== b .== c \n\
            Must be of the form @test_vectorized a .<op> b [kwargs...] where <op> is a binary logical or comparison operator, e.g. .==, .<=, .&&, ...\
        ") TM._process_test_expr_vectorized!(:(a .== b .== c))

        @test_throws ErrorException("\
            invalid test macro call: @test_vectorized isapprox.(a, b, atol = 1) \n\
            Must be of the form @test_vectorized a .<op> b [kwargs...] where <op> is a binary logical or comparison operator, e.g. .==, .<=, .&&, ...\
        ") TM._process_test_expr_vectorized!(:(isapprox.(a, b, atol=1)))

        @test_throws ErrorException("\
            invalid test macro call: @test_vectorized a .+ b \n\
            Must be of the form @test_vectorized a .<op> b [kwargs...] where <op> is a binary logical or comparison operator, e.g. .==, .<=, .&&, ...\
        ") TM._process_test_expr_vectorized!(:(a .+ b))

        # Invalid expression, supported unvectorized operator
        @test_throws ErrorException("\
            invalid test macro call: @test_vectorized a == b \n\
            Requires a vectorized operation; did you mean to use .== instead?\
        ") TM._process_test_expr_vectorized!(:(a == b))

        @test_throws ErrorException("\
            invalid test macro call: @test_vectorized a ≈ b \n\
            Requires a vectorized operation; did you mean to use .≈ instead?\
        ") TM._process_test_expr_vectorized!(:(a ≈ b))
    end


    @testset "_get_test_result_vectorized" begin
        lhs, rhs = [4.0, 5.0, 6.0], [7.0, 5.0, 6.0]
        result = TM._get_test_result_vectorized(lhs, rhs, lhs .== rhs, "==", "lhs .== rhs")
        @test result isa Test.Fail
        @test result.orig_expr == "lhs .== rhs"
        @test result.data == "Failed at 1 index.\n    [1]: 4.0 == 7.0"

        lhs, rhs = [4.0, 5.0, 6.0], 10.0
        result = TM._get_test_result_vectorized(lhs, rhs, lhs .<= rhs, "<=", "lhs .== rhs")
        @test result isa Test.Pass
    end

    @testset "_get_operator_string" begin
        @test TM._get_operator_string(:(a .== b)) == "=="     
        @test TM._get_operator_string(:(a .!= b)) == "!="     
        @test TM._get_operator_string(:(a .≠ b)) == "≠"     
        @test TM._get_operator_string(:(a .< b))  == "<"    
        @test TM._get_operator_string(:(a .> b))  == ">"    
        @test TM._get_operator_string(:(a .<= b)) == "<="     
        @test TM._get_operator_string(:(a .>= b)) == ">="     
        @test TM._get_operator_string(:(a .≈ b))  == "≈"    
        @test TM._get_operator_string(:(a .≉ b))  == "≉"    
        @test TM._get_operator_string(:(a .& b))  == "&"    
        @test TM._get_operator_string(:(a .&& b)) == "&&"     
        @test TM._get_operator_string(:(a .| b))  == "|"    
        @test TM._get_operator_string(:(a .|| b)) == "||"     
    end

    @testset "passing tests" begin
        @test_vectorized [:a, :b, :c] .== [:a, :b, :c]
        @test_vectorized [1, 2, 3] .<= 3.0
        @test_vectorized [0.999, 1.0, 1.001] .≈ 1.0 atol=0.01
    end
end