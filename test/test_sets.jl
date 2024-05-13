@testset "test_sets.jl" begin

    @testset "printing utilities" begin

        @testset "printL/R" begin
            @test destyle(sprint(TM.printL)) == "(L)"
            @test destyle(sprint(TM.printL, "L")) == "L"
            @test destyle(sprint(TM.printL, "L", "suffix")) == "Lsuffix"

            @test destyle(sprint(TM.printR)) == "(R)"
            @test destyle(sprint(TM.printR, "R")) == "R"
            @test destyle(sprint(TM.printR, "R", "suffix")) == "Rsuffix"

            fLR = (args...) -> destyle(sprint(TM.printLsepR, args...))
            @test fLR("L", "sep", "R") == "L sep R"
            @test fLR("L", "sep", "R", " suffix") == "L sep R suffix"
            fRL = (args...) -> destyle(sprint(TM.printRsepL, args...))
            @test fRL("R", "sep", "L") == "R sep L"
            @test fRL("R", "sep", "L", " suffix") == "R sep L suffix"
        end

        @testset "printset()" begin
            f = v -> sprint(TM.printset, v, "set")

            @test contains(f([1]), "set has 1 element:  [1]")
            @test contains(f([2,3]), "set has 2 elements: [2, 3]")
            @test contains(f(Set([4])), "set has 1 element:  [4]")
            @test occursin(r"set has 2 elements: \[(5|6), (5|6)\]", f(Set([5,6])))
            @test contains(f(Int32[7,8]), "set has 2 elements: [7, 8]")
            @test contains(f(Set{Int32}([9])), "set has 1 element:  [9]")
            @test contains(f([1,π]), "set has 2 elements: [1.0, 3.14159]") 
            @test contains(f([TestStruct(1,π)]), "set has 1 element:  [S(1, 3.14159)]")
        end

        @testset "stringify_expr_test_sets()" begin
            f = ex -> destyle(TM.stringify_expr_test_sets(ex))
            @test f(:(a == b)) == "(L) a == b (R)"
            @test f(:(a ≠ b)) == "(L) a ≠ b (R)"
            @test f(:(a ⊆ b)) == "(L) a ⊆ b (R)"
            @test f(:(a ⊇ b)) == "(L) a ⊇ b (R)"
            @test f(:(a ⊊ b)) == "(L) a ⊊ b (R)"
            @test f(:(a ⊋ b)) == "(L) a ⊋ b (R)"
            @test f(:(a ∩ b)) == "(L) a ∩ b (R) == ∅"
            @test f(:(1:3 == 1:3)) == "(L) 1:3 == 1:3 (R)"
            @test f(:(Set(3) ≠ [1 2 3])) == "(L) Set(3) ≠ [1 2 3] (R)"
        end

    end

    @testset "preprocess_test_sets(ex)" begin

        @testset "valid expressions" begin
            cases = [
                # Left as is
                :(L == R) => :(L == R),
                :(L ≠ R) => :(L ≠ R),
                :(L ⊆ R) => :(L ⊆ R),
                :(L ⊇ R) => :(L ⊇ R),
                :(L ⊊ R) => :(L ⊊ R),
                :(L ⊋ R) => :(L ⊋ R),
                :(L ∩ R) => :(L ∩ R),
                # Converted
                :(L != R) => :(L ≠ R),
                :(L ⊂ R) => :(L ⊆ R),
                :(L ⊃ R) => :(L ⊇ R),
                :(L || R) => :(L ∩ R),
                :(issetequal(L, R)) => :(L == R),
                :(isdisjoint(L, R)) => :(L ∩ R),
                :(issubset(L, R)) => :(L ⊆ R),
            ]

            @testset "$ex" for (ex, res) in cases
                @test TM.preprocess_test_sets(ex) == res
            end
        end

        @testset "unsupported operator" begin
            cases = [
                :(a <= b),
                :(a .== b),
                :(a ∈ b),
                :(a ∪ b),
                :(a | b)
            ]
            @testset "$ex" for ex in cases
                @test_throws "unsupported set operator" TM.preprocess_test_sets(ex)
            end
        end

        @testset "invalid expression" begin
            cases = [
                :(a && b),
                :(a == b == c),
                :(g(a, b)),
            ]
            @testset "$ex" for ex in cases
                @test_throws "invalid test macro call: @test_set" TM.preprocess_test_sets(ex)
            end
        end
    end


    # @testset "eval_test_sets: !=" begin
    #     f = (lhs, rhs) -> TM.eval_test_sets(lhs, :!=, rhs, LineNumberNode(1))

    #     res = f([1,2,3], [1,2])
    #     @test res.value === true
    #     @test res.data === nothing

    #     res = f([1,2,3], [1,1,1])
    #     @test res.value === true
    #     @test res.data === nothing

    #     res = f([1,2,3], [3,2,1])
    #     @test res.value === false
    #     @test res.data == "Left and right sets are equal."

    #     res = f([1,1,1,2,1], [2,1])
    #     @test res.value === false
    #     @test res.data == "Left and right sets are equal."
    # end

    # @testset "eval_test_sets: ≠" begin
    #     f = (lhs, rhs) -> TM.eval_test_sets(lhs, :≠, rhs, LineNumberNode(1))

    #     res = f([1,2,3], [1,2])
    #     @test res.value === true
    #     @test res.data === nothing

    #     res = f([1,2,3], [1,1,1])
    #     @test res.value === true
    #     @test res.data === nothing

    #     res = f([1,2,3], [3,2,1])
    #     @test res.value === false
    #     @test res.data == "Left and right sets are equal."

    #     res = f([1,1,1,2,1], [2,1])
    #     @test res.value === false
    #     @test res.data == "Left and right sets are equal."
    # end

    # @testset "eval_test_sets: ==" begin
    #     f = (lhs, rhs) -> TM.eval_test_sets(lhs, :(==), rhs, LineNumberNode(1))

    #     res = f([1,2,3], [1,2,3])
    #     @test res.value === true
    #     @test res.data === nothing

    #     res = f([2,1,2], [1,2,1,2])
    #     @test res.value === true
    #     @test res.data === nothing

    #     res = f([1,2,3], [1,2])
    #     @test res.value === false
    #     @test startswith(res.data, "Left and right sets are not equal.")
    #     @test occursin("1 element  in left\\right: [3]", res.data)

    #     res = f(1:5, 2:6)
    #     @test res.value === false
    #     @test startswith(res.data, "Left and right sets are not equal.")
    #     @test occursin("1 element  in left\\right: [1]", res.data)
    #     @test occursin("1 element  in right\\left: [6]", res.data)

    #     res = f(4:6, 1:9)
    #     @test res.value === false
    #     @test startswith(res.data, "Left and right sets are not equal.")
    #     @test occursin(r"6 elements in right\\left: \[(\d, ){5}\.{3}\]", res.data)
    # end

    # @testset "eval_test_sets: ⊆" begin
    #     f = (lhs, rhs) -> TM.eval_test_sets(lhs, :⊆, rhs, LineNumberNode(1))

    #     res = f([1,2,3], [1,2,3])
    #     @test res.value === true
    #     @test res.data === nothing

    #     res = f([1,2], [1,2,3])
    #     @test res.value === true
    #     @test res.data === nothing

    #     res = f([1,2,2,1], 1:5)
    #     @test res.value === true
    #     @test res.data === nothing

    #     res = f([1,2,3], [1,2])
    #     @test res.value === false
    #     @test startswith(res.data, "Left set is not a subset of right set.")
    #     @test occursin("1 element  in left\\right: [3]", res.data)

    #     res = f(1:4, [1,2])
    #     @test res.value === false
    #     @test startswith(res.data, "Left set is not a subset of right set.")
    #     @test occursin("2 elements in left\\right: [3, 4]", res.data)
    # end

    # @testset "eval_test_sets: ⊇" begin
    #     f = (lhs, rhs) -> TM.eval_test_sets(lhs, :⊇, rhs, LineNumberNode(1))

    #     res = f([1,2,3], [1,2,3])
    #     @test res.value === true
    #     @test res.data === nothing

    #     res = f([1,2,3], [1,2])
    #     @test res.value === true
    #     @test res.data === nothing

    #     res = f(1:5, [1,2,2,1])
    #     @test res.value === true
    #     @test res.data === nothing

    #     res = f([1,2], [1,2,3])
    #     @test res.value === false
    #     @test startswith(res.data, "Left set is not a superset of right set.")
    #     @test occursin("1 element  in right\\left: [3]", res.data)

    #     res = f([1,2], 4:-1:1)
    #     @test res.value === false
    #     @test startswith(res.data, "Left set is not a superset of right set.")
    #     @test occursin("2 elements in right\\left: [4, 3]", res.data)
    # end

    # @testset "eval_test_sets: ⊊" begin
    #     f = (lhs, rhs) -> TM.eval_test_sets(lhs, :⊊, rhs, LineNumberNode(1))

    #     res = f([1,2], [1,2,3])
    #     @test res.value === true
    #     @test res.data === nothing

    #     res = f(1:5, 1:10)
    #     @test res.value === true
    #     @test res.data === nothing

    #     res = f([1,2,2,3], [1,2,3,1])
    #     @test res.value === false
    #     @test res.data == "Left and right sets are equal, left is not a proper subset."

    #     res = f([1,2,3], [1,2])
    #     @test res.value === false
    #     @test startswith(res.data, "Left set is not a proper subset of right set.")
    #     @test occursin("1 element  in left\\right: [3]", res.data)

    #     res = f([1,2,4,1,1,3], [1,2])
    #     @test res.value === false
    #     @test startswith(res.data, "Left set is not a proper subset of right set.")
    #     @test occursin("2 elements in left\\right: [4, 3]", res.data)
    # end

    # @testset "eval_test_sets: ⊋" begin
    #     f = (lhs, rhs) -> TM.eval_test_sets(lhs, :⊋, rhs, LineNumberNode(1))

    #     res = f([1,2,3], [1,2])
    #     @test res.value === true
    #     @test res.data === nothing

    #     res = f(1:10, 1:5)
    #     @test res.value === true
    #     @test res.data === nothing

    #     res = f([1,2,3], [1,2,3])
    #     @test res.value === false
    #     @test res.data == "Left and right sets are equal, left is not a proper superset."

    #     res = f([1,2], [1,2,3])
    #     @test res.value === false
    #     @test startswith(res.data, "Left set is not a proper superset of right set.")
    #     @test occursin("1 element  in right\\left: [3]", res.data)

    #     res = f([1,2], [1,2,5,1,1,4])
    #     @test res.value === false
    #     @test startswith(res.data, "Left set is not a proper superset of right set.")
    #     @test occursin("2 elements in right\\left: [5, 4]", res.data)
    # end
    
    # @testset "eval_test_sets: ||" begin
    #     f = (lhs, rhs) -> TM.eval_test_sets(lhs, :||, rhs, LineNumberNode(1))

    #     res = f([1,2,3], [4,5])
    #     @test res.value === true
    #     @test res.data === nothing

    #     res = f(1:5, 6:10)
    #     @test res.value === true
    #     @test res.data === nothing

    #     res = f([1,2,3], [3,4])
    #     @test res.value === false
    #     @test startswith(res.data, "Left and right sets are not disjoint.")
    #     @test occursin("1 element  in common: [3]", res.data)

    #     res = f(1:5, 3:8)
    #     @test res.value === false
    #     @test startswith(res.data, "Left and right sets are not disjoint.")
    #     @test occursin("3 elements in common: [3, 4, 5]", res.data)
    # end

    # @testset "@test_sets" begin
    #     @test_sets [1, 2, 3] == [3, 1, 2]
    #     @test_sets [1, 3, 5, 5, 3, 1] == 1:2:5
        
    #     @test_sets [1, 2, 3] != 1:4
    #     @test_sets 1 != [1, 2, 3, 4]

    #     @test_sets 1:5 ≠ 2
    #     @test_sets [1, 1, 1, 2] ≠ [2, 1, 42]

    #     @test_sets 1:5 ⊆ 1:5
    #     @test_sets [1, 2, 3] ⊆ 1:5
    #     @test_sets [1, 1, 1] ⊆ [1, 2, 3, 4, 5]

    #     @test_sets 1:5 ⊇ 1:5
    #     @test_sets 1:5 ⊇ [3, 3, 3, 1, 5]
        
    #     @test_sets [1, 2, 3] ⊊ [1, 2, 3, 4]
    #     @test_sets 1:5 ⊊ 1:10
    #     @test_sets [1, 1, 3, 1] ⊊ 3:-1:1

    #     @test_sets [1, 2, 3, 4] ⊋ [1, 2, 3]
    #     @test_sets 1:10 ⊋ 1:5
    #     @test_sets 3:-1:1 ⊋ [1, 1, 3, 1]

    #     @test_sets [1, 2, 3] || [4, 5]
    #     @test_sets 1:5 || 6:8
    # end

    # @testset "@test_sets should only evaluate arguments once" begin
    #     g = Int[]
    #     f = (x) -> (push!(g, x); x)
    #     @test_sets f(1) == 1
    #     @test g == [1]

    #     empty!(g)
    #     @test_sets 1 ≠ f(2)
    #     @test g == [2]
    # end

    # @testset "@test_sets fails" begin
    #     let fails = @testset NoThrowTestSet begin
    #             # 1: == 
    #             @test_sets [1,2,3] == [1,2,3,4]
                
    #             # 2: !=
    #             @test_sets [1,2,3] != [1,2,3]

    #             # 3: ≠
    #             @test_sets 1 ≠ 1

    #             # 4: ⊆
    #             @test_sets [3,2,1,3,2,1] ⊆ [2,3]

    #             # 5: ⊇
    #             @test_sets 2:4 ⊇ 1:5

    #             # 6: ⊊ (fail because equal)
    #             @test_sets [1,2,3] ⊊ [1,2,3]

    #             # 7: ⊆ (fail because missing RHS)
    #             @test_sets 1:4 ⊊ 1:3

    #             # 8: ⊋ (fail because equal)
    #             @test_sets [5,5,5,6] ⊋ [6,5]

    #             # 9: ⊋ (fail because missing LHS)
    #             @test_sets [1,1,1,2] ⊋ [3,2]

    #             # 10: || (disjoint)
    #             @test_sets [1,1,1,2] || [3,2]

    #         end # teststet

    #         for (i, fail) in enumerate(fails)
    #             @testset "isa Fail (i = $i)" begin
    #                 @test fail isa Test.Fail
    #                 @test fail.test_type === :test
    #             end
    #         end

    #         let str = sprint(show, fails[1])
    #             @test occursin("Expression: [1, 2, 3] == [1, 2, 3, 4]", str)
    #             @test occursin("Evaluated: Left and right sets are not equal.", str)
    #             @test occursin("0 elements in left\\right: []", str)
    #             @test occursin("1 element  in right\\left: [4]", str)
    #         end

    #         let str = sprint(show, fails[2])
    #             @test occursin("Expression: [1, 2, 3] != [1, 2, 3]", str)
    #             @test occursin("Evaluated: Left and right sets are equal.", str)
    #         end

    #         let str = sprint(show, fails[3])
    #             @test occursin("Expression: 1 ≠ 1", str)
    #             @test occursin("Evaluated: Left and right sets are equal.", str)
    #         end

    #         let str = sprint(show, fails[4])
    #             @test occursin("Expression: [3, 2, 1, 3, 2, 1] ⊆ [2, 3]", str)
    #             @test occursin("Evaluated: Left set is not a subset of right set.", str)
    #             @test occursin("1 element  in left\\right: [1]", str)
    #         end

    #         let str = sprint(show, fails[5])
    #             @test occursin("Expression: 2:4 ⊇ 1:5", str)
    #             @test occursin("Evaluated: Left set is not a superset of right set.", str)
    #             @test occursin("2 elements in right\\left: [1, 5]", str)
    #         end

    #         let str = sprint(show, fails[6])
    #             @test occursin("Expression: [1, 2, 3] ⊊ [1, 2, 3]", str)
    #             @test occursin("Evaluated: Left and right sets are equal, left is not a proper subset.", str)
    #         end

    #         let str = sprint(show, fails[7])
    #             @test occursin("Expression: 1:4 ⊊ 1:3", str)
    #             @test occursin("Evaluated: Left set is not a proper subset of right set.", str)
    #             @test occursin("1 element  in left\\right: [4]", str)
    #         end

    #         let str = sprint(show, fails[8])
    #             @test occursin("Expression: [5, 5, 5, 6] ⊋ [6, 5]", str)
    #             @test occursin("Evaluated: Left and right sets are equal, left is not a proper superset.", str)
    #         end

    #         let str = sprint(show, fails[9])
    #             @test occursin("Expression: [1, 1, 1, 2] ⊋ [3, 2]", str)
    #             @test occursin("Evaluated: Left set is not a proper superset of right set.", str)
    #             @test occursin("1 element  in right\\left: [3]", str)
    #         end

    #         let str = sprint(show, fails[10])
    #             @test occursin("Expression: [1, 1, 1, 2] || [3, 2]", str)
    #             @test occursin("Evaluated: Left and right sets are not disjoint.", str)
    #             @test occursin("1 element  in common: [2]", str)
    #         end

    #     end # let fails
    # end

    # @testset "@test_sets with skip/broken=false kwargs" begin
    #     a = 1
    #     @test_sets 1 == 1 broken=false
    #     @test_sets 1 == 1 skip=false
    #     @test_sets 1 == 1 broken=a==2
    #     @test_sets 1 == 1 skip=!isone(1)
    # end


    # @testset "@test_sets with skip=true" begin
    #     let skips = @testset NoThrowTestSet begin
    #             @test_sets 1 == 1 skip=true
    #             @test_sets 1 == 2 skip=true
    #         end # testset

    #         @test skips[1] isa Test.Broken && skips[1].test_type === :skipped
    #         @test skips[2] isa Test.Broken && skips[2].test_type === :skipped
    #     end # let skips
    # end

    # @testset "@test_sets with broken=true" begin
    #     let brokens = @testset NoThrowTestSet begin
    #             @test_sets 1 == 2 broken=true
    #             @test_sets 1 == 1 broken=true
    #         end

    #         @test brokens[1] isa Test.Broken && brokens[1].test_type === :test
    #         @test brokens[2] isa Test.Error && brokens[2].test_type === :test_unbroken
    #     end
    # end
    

end