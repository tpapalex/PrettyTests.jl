@testset "setop.jl" begin

    @testset "test_setop_expr!(ex, kws...)" begin
        # Valid simple expressions
        @test TM.test_setop_expr!(:(a == b)) == :(a == b)
        @test TM.test_setop_expr!(:(a ⊆ b)) == :(a ⊆ b)
        @test TM.test_setop_expr!(:(a ⊇ b)) == :(a ⊇ b)
        @test TM.test_setop_expr!(:(a ⊊ b)) == :(a ⊊ b)
        @test TM.test_setop_expr!(:(a ⊋ b)) == :(a ⊋ b)
        @test TM.test_setop_expr!(:(a != b)) == :(a != b)
        @test TM.test_setop_expr!(:(a ≠ b)) == :(a ≠ b)
        @test TM.test_setop_expr!(:(a || b)) == :(a || b)

        # Expressions with more complicated sets
        @test TM.test_setop_expr!(:(a == [1,2])) == :(a == [1,2])
        @test TM.test_setop_expr!(:(1:2 == [1,2,2])) == :(1:2 == [1,2,2])
        @test TM.test_setop_expr!(:(1:2:5 == Set(3))) == :(1:2:5 == Set(3))
        @test TM.test_setop_expr!(:([1 3 5] == [1; 2])) == (:([1 3 5] == [1; 2]))
        @test TM.test_setop_expr!(:(1:5 == 6:10)) == (:(1:5 == 6:10))

        # Invalid expression, comparison
        @test_throws r"does not support :comparison" TM.test_setop_expr!(:(a == b ⊆ c))
        @test_throws r"does not support :comparison" TM.test_setop_expr!(:(a ⊇ b ⊂ c))

        # Invalid expression, invalid head
        @test_throws r"invalid .* @test_setop a = b" TM.test_setop_expr!(:(a = b))
        @test_throws r"invalid .* @test_setop a && b" TM.test_setop_expr!(:(a && b))

        # Invalid expression, too many arguments
        @test_throws r"invalid .* @test_setop f\(a, b, c\)" TM.test_setop_expr!(:(f(a, b, c)))

        # Invalid expression, unsupported operator
        @test_throws r"invalid .* unsupported set operator ≈" TM.test_setop_expr!(:(a ≈ b))
        @test_throws r"invalid .* unsupported set operator >=" TM.test_setop_expr!(:(a >= b))
        @test_throws r"invalid .* unsupported set operator f" TM.test_setop_expr!(:(f(a, b)))

        # Unsupported keyword arguments
        @test_throws r"invalid .* unsupported extra arguments .*c = 1" TM.test_setop_expr!(:(a == b), :(c=1))
        @test_throws r"invalid .* unsupported extra arguments .*broken d = 2" TM.test_setop_expr!(:(a == b), :(broken), :(d=2))
    end
    
    @testset "print_pretty_set" begin
        # Test with vectors, to avoid unordered set differences
        @test sprint(TM.print_pretty_set, [1], "x") == 
            "\n              1 element  x: [1]"
        @test sprint(TM.print_pretty_set, [:a], "x") == 
            "\n              1 element  x: [:a]"

        @test sprint(TM.print_pretty_set, [1,2,3], "x") == 
            "\n              3 elements x: [1, 2, 3]"
        @test sprint(TM.print_pretty_set, [1,2,3], "x", 10) == 
            "\n              3 elements x: [1, 2, 3]"
        @test sprint(TM.print_pretty_set, 1:6, "x", 3) == 
            "\n              6 elements x: [1, 2, 3, ...]"
        @test sprint(TM.print_pretty_set, [:a,:b,:c], "x", 3) == 
            "\n              3 elements x: [:a, :b, :c]"
        @test sprint(TM.print_pretty_set, [:a => 3], "x") == 
            "\n              1 element  x: [:a => 3]"
        @test sprint(TM.print_pretty_set, [:a => 3, :b => 1], "x") == 
            "\n              2 elements x: [:a => 3, :b => 1]"

        # Test with sets
        val = sprint(TM.print_pretty_set, Set(1:9), "x", 10)
        @test occursin(r"9 elements x: \[(\d, ){8}\d\]", val)

        val = sprint(TM.print_pretty_set, Set(1:9), "x", 3)
        @test occursin(r"9 elements x: \[(\d, ){3}\.{3}\]", val)
    end

    @testset "eval_test_setop: !=" begin
        f = (lhs, rhs) -> TM.eval_test_setop(lhs, :!=, rhs, LineNumberNode(1))

        res = f([1,2,3], [1,2])
        @test res.value === true
        @test res.data === nothing

        res = f([1,2,3], [1,1,1])
        @test res.value === true
        @test res.data === nothing

        res = f([1,2,3], [3,2,1])
        @test res.value === false
        @test res.data == "Left and right sets are equal."

        res = f([1,1,1,2,1], [2,1])
        @test res.value === false
        @test res.data == "Left and right sets are equal."
    end

    @testset "eval_test_setop: ≠" begin
        f = (lhs, rhs) -> TM.eval_test_setop(lhs, :≠, rhs, LineNumberNode(1))

        res = f([1,2,3], [1,2])
        @test res.value === true
        @test res.data === nothing

        res = f([1,2,3], [1,1,1])
        @test res.value === true
        @test res.data === nothing

        res = f([1,2,3], [3,2,1])
        @test res.value === false
        @test res.data == "Left and right sets are equal."

        res = f([1,1,1,2,1], [2,1])
        @test res.value === false
        @test res.data == "Left and right sets are equal."
    end

    @testset "eval_test_setop: ==" begin
        f = (lhs, rhs) -> TM.eval_test_setop(lhs, :(==), rhs, LineNumberNode(1))

        res = f([1,2,3], [1,2,3])
        @test res.value === true
        @test res.data === nothing

        res = f([2,1,2], [1,2,1,2])
        @test res.value === true
        @test res.data === nothing

        res = f([1,2,3], [1,2])
        @test res.value === false
        @test startswith(res.data, "Left and right sets are not equal.")
        @test occursin("1 element  in left\\right: [3]", res.data)

        res = f(1:5, 2:6)
        @test res.value === false
        @test startswith(res.data, "Left and right sets are not equal.")
        @test occursin("1 element  in left\\right: [1]", res.data)
        @test occursin("1 element  in right\\left: [6]", res.data)

        res = f(4:6, 1:9)
        @test res.value === false
        @test startswith(res.data, "Left and right sets are not equal.")
        @test occursin(r"6 elements in right\\left: \[(\d, ){5}\.{3}\]", res.data)
    end

    @testset "eval_test_setop: ⊆" begin
        f = (lhs, rhs) -> TM.eval_test_setop(lhs, :⊆, rhs, LineNumberNode(1))

        res = f([1,2,3], [1,2,3])
        @test res.value === true
        @test res.data === nothing

        res = f([1,2], [1,2,3])
        @test res.value === true
        @test res.data === nothing

        res = f([1,2,2,1], 1:5)
        @test res.value === true
        @test res.data === nothing

        res = f([1,2,3], [1,2])
        @test res.value === false
        @test startswith(res.data, "Left set is not a subset of right set.")
        @test occursin("1 element  in left\\right: [3]", res.data)

        res = f(1:4, [1,2])
        @test res.value === false
        @test startswith(res.data, "Left set is not a subset of right set.")
        @test occursin("2 elements in left\\right: [3, 4]", res.data)
    end

    @testset "eval_test_setop: ⊇" begin
        f = (lhs, rhs) -> TM.eval_test_setop(lhs, :⊇, rhs, LineNumberNode(1))

        res = f([1,2,3], [1,2,3])
        @test res.value === true
        @test res.data === nothing

        res = f([1,2,3], [1,2])
        @test res.value === true
        @test res.data === nothing

        res = f(1:5, [1,2,2,1])
        @test res.value === true
        @test res.data === nothing

        res = f([1,2], [1,2,3])
        @test res.value === false
        @test startswith(res.data, "Left set is not a superset of right set.")
        @test occursin("1 element  in right\\left: [3]", res.data)

        res = f([1,2], 4:-1:1)
        @test res.value === false
        @test startswith(res.data, "Left set is not a superset of right set.")
        @test occursin("2 elements in right\\left: [4, 3]", res.data)
    end

    @testset "eval_test_setop: ⊊" begin
        f = (lhs, rhs) -> TM.eval_test_setop(lhs, :⊊, rhs, LineNumberNode(1))

        res = f([1,2], [1,2,3])
        @test res.value === true
        @test res.data === nothing

        res = f(1:5, 1:10)
        @test res.value === true
        @test res.data === nothing

        res = f([1,2,2,3], [1,2,3,1])
        @test res.value === false
        @test res.data == "Left and right sets are equal, left is not a proper subset."

        res = f([1,2,3], [1,2])
        @test res.value === false
        @test startswith(res.data, "Left set is not a proper subset of right set.")
        @test occursin("1 element  in left\\right: [3]", res.data)

        res = f([1,2,4,1,1,3], [1,2])
        @test res.value === false
        @test startswith(res.data, "Left set is not a proper subset of right set.")
        @test occursin("2 elements in left\\right: [4, 3]", res.data)
    end

    @testset "eval_test_setop: ⊋" begin
        f = (lhs, rhs) -> TM.eval_test_setop(lhs, :⊋, rhs, LineNumberNode(1))

        res = f([1,2,3], [1,2])
        @test res.value === true
        @test res.data === nothing

        res = f(1:10, 1:5)
        @test res.value === true
        @test res.data === nothing

        res = f([1,2,3], [1,2,3])
        @test res.value === false
        @test res.data == "Left and right sets are equal, left is not a proper superset."

        res = f([1,2], [1,2,3])
        @test res.value === false
        @test startswith(res.data, "Left set is not a proper superset of right set.")
        @test occursin("1 element  in right\\left: [3]", res.data)

        res = f([1,2], [1,2,5,1,1,4])
        @test res.value === false
        @test startswith(res.data, "Left set is not a proper superset of right set.")
        @test occursin("2 elements in right\\left: [5, 4]", res.data)
    end
    
    @testset "eval_test_setop: ||" begin
        f = (lhs, rhs) -> TM.eval_test_setop(lhs, :||, rhs, LineNumberNode(1))

        res = f([1,2,3], [4,5])
        @test res.value === true
        @test res.data === nothing

        res = f(1:5, 6:10)
        @test res.value === true
        @test res.data === nothing

        res = f([1,2,3], [3,4])
        @test res.value === false
        @test startswith(res.data, "Left and right sets are not disjoint.")
        @test occursin("1 element  in common: [3]", res.data)

        res = f(1:5, 3:8)
        @test res.value === false
        @test startswith(res.data, "Left and right sets are not disjoint.")
        @test occursin("3 elements in common: [3, 4, 5]", res.data)
    end

    @testset "@test_setop" begin
        @test_setop [1, 2, 3] == [3, 1, 2]
        @test_setop [1, 3, 5, 5, 3, 1] == 1:2:5
        
        @test_setop [1, 2, 3] != 1:4
        @test_setop 1 != [1, 2, 3, 4]

        @test_setop 1:5 ≠ 2
        @test_setop [1, 1, 1, 2] ≠ [2, 1, 42]

        @test_setop 1:5 ⊆ 1:5
        @test_setop [1, 2, 3] ⊆ 1:5
        @test_setop [1, 1, 1] ⊆ [1, 2, 3, 4, 5]

        @test_setop 1:5 ⊇ 1:5
        @test_setop 1:5 ⊇ [3, 3, 3, 1, 5]
        
        @test_setop [1, 2, 3] ⊊ [1, 2, 3, 4]
        @test_setop 1:5 ⊊ 1:10
        @test_setop [1, 1, 3, 1] ⊊ 3:-1:1

        @test_setop [1, 2, 3, 4] ⊋ [1, 2, 3]
        @test_setop 1:10 ⊋ 1:5
        @test_setop 3:-1:1 ⊋ [1, 1, 3, 1]

        @test_setop [1, 2, 3] || [4, 5]
        @test_setop 1:5 || 6:8
    end

    @testset "@test_setop with skip/broken=false kwargs" begin
        a = 1
        @test_setop 1 == 1 broken=false
        @test_setop 1 == 1 skip=false
        @test_setop 1 == 1 broken=a==2
        @test_setop 1 == 1 skip=!isone(1)
    end

    # @testset "@test_setop with skip=true" begin

    #     let fails = @testset NoThrowTestSet begin
    #         @test 1 == 1 skip=true
    #         end
    #     end

    #     @show fails
        
    # end

end