@testset "test_sets.jl" begin

    @testset "printing utilities" begin

        @testset "printL/R" begin
            @test destyle(sprint(TM.printL)) == "L"
            @test destyle(sprint(TM.printL, "(L)")) == "(L)"
            @test destyle(sprint(TM.printL, "L", " suffix")) == "L suffix"

            @test destyle(sprint(TM.printR)) == "R"
            @test destyle(sprint(TM.printR, "(R)")) == "(R)"
            @test destyle(sprint(TM.printR, "R", " suffix")) == "R suffix"

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
            @test f(:(a == b)) == "a == b"
            @test f(:(a ≠ b)) == "a ≠ b"
            @test f(:(a ⊆ b)) == "a ⊆ b"
            @test f(:(a ⊇ b)) == "a ⊇ b"
            @test f(:(a ⊊ b)) == "a ⊊ b"
            @test f(:(a ⊋ b)) == "a ⊋ b"
            @test f(:(a ∩ b)) == "a ∩ b == ∅"
            @test f(:(1:3 == 1:3)) == "1:3 == 1:3"
            @test f(:(Set(3) ≠ [1 2 3])) == "Set(3) ≠ [1 2 3]"
            @test f(:([1,2] ∩ [3,4])) == "[1, 2] ∩ [3, 4] == ∅"
        end

    end

    @testset "process_expr_test_sets(ex)" begin

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
                # Disjoint syntactic sugar
                :(L ∩ R == ∅) => :(L ∩ R),
                :(∅ == L ∩ R) => :(L ∩ R),
            ]

            @testset "$ex" for (ex, res) in cases
                @test TM.process_expr_test_sets(ex) == res
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
                @test_throws "unsupported set operator" TM.process_expr_test_sets(ex)
            end
        end

        @testset "invalid expression" begin
            cases = [
                :(a && b),
                :(a == b == c),
                :(g(a, b)),
            ]
            @testset "$ex" for ex in cases
                @test_throws "invalid test macro call: @test_set" TM.process_expr_test_sets(ex)
            end
        end
    end

    @testset "eval_test_sets()" begin

        @testset "op: ==" begin
            f = (lhs, rhs) -> TM.eval_test_sets(lhs, :(==), rhs, LineNumberNode(1))

            res = f(Set([1,2,3]), [1,2,3])
            @test res.value === true

            res = f([2,1,2], [1,2,1,2])
            @test res.value === true

            res = f([1,2,3], Set([1,2]))
            @test res.value === false
            msg = destyle(res.data)
            @test startswith(msg, "L and R are not equal.")
            @test contains(msg, "L ∖ R has 1 element:  [3]")
            @test contains(msg, "R ∖ L has 0 elements: []")

            res = f(4:6, 1:9)
            @test res.value === false
            msg = destyle(res.data)
            @test startswith(msg, "L and R are not equal.")
            @test contains(msg, "L ∖ R has 0 elements: []")
            @test occursin(r"R ∖ L has 6 elements: \[(\d, ){5}\d]", msg)
        end

        @testset "op: ≠" begin
            f = (lhs, rhs) -> TM.eval_test_sets(lhs, :≠, rhs, LineNumberNode(1))

            res = f([1,2,3], Set([1,2]))
            @test res.value === true

            res = f([1,2,3], [1,1,1])
            @test res.value === true
            
            res = f(Set([1,2,3]), [3,2,1])
            @test res.value === false
            @test destyle(res.data) == "L and R are equal."

            res = f([1,1,1,2,1], [2,1])
            @test res.value === false
            @test destyle(res.data) == "L and R are equal."
        end

        @testset "op: ⊆" begin
            f = (lhs, rhs) -> TM.eval_test_sets(lhs, :⊆, rhs, LineNumberNode(1))

            res = f([1,2,3], [1,2,3])
            @test res.value === true

            res = f([1,2], Set([1,2,3]))
            @test res.value === true

            res = f([1,2,2,1], 1:5)
            @test res.value === true

            res = f([1,2,3], Set([2,1]))
            @test res.value === false
            msg = destyle(res.data)
            @test startswith(msg, "L is not a subset of R.")
            @test contains(msg, "L ∖ R has 1 element:  [3]")

            res = f(4:-1:1, [1,2])
            @test res.value === false
            msg = destyle(res.data)
            @test startswith(msg, "L is not a subset of R.")
            @test contains(msg, "L ∖ R has 2 elements: [4, 3]")
        end

        @testset "op: ⊇" begin
            f = (lhs, rhs) -> TM.eval_test_sets(lhs, :⊇, rhs, LineNumberNode(1))

            res = f([1,2,3], [1,2,3])
            @test res.value === true

            res = f(Set([1,2,3]), [1,2])
            @test res.value === true

            res = f(1:5, [1,2,2,1])
            @test res.value === true

            res = f(Set([2,1]), [1,2,3])
            @test res.value === false
            msg = destyle(res.data)
            @test startswith(msg, "L is not a superset of R.")
            @test contains(msg, "R ∖ L has 1 element:  [3]")

            res = f([1,2], 4:-1:1)
            @test res.value === false
            msg = destyle(res.data)
            @test startswith(msg, "L is not a superset of R.")
            @test contains(msg, "R ∖ L has 2 elements: [4, 3]")
        end

        @testset "op: ⊊" begin
            f = (lhs, rhs) -> TM.eval_test_sets(lhs, :⊊, rhs, LineNumberNode(1))

            res = f([1,2], [1,2,3])
            @test res.value === true

            res = f(1:5, 0:10)
            @test res.value === true

            res = f([1,2,2,3], [1,2,3,1])
            @test res.value === false
            msg = destyle(res.data)
            @test startswith(msg, "L is not a proper subset of R, it is equal.")

            res = f(Set([1,2,3]), [1,2])
            @test res.value === false
            msg = destyle(res.data)
            @test startswith(msg, "L is not a proper subset of R.")
            @test contains(msg, "L ∖ R has 1 element:  [3]")

            res = f([1,2,4,1,1,3], [1,2])
            @test res.value === false
            msg = destyle(res.data)
            @test startswith(msg, "L is not a proper subset of R.")
            @test contains(msg, "L ∖ R has 2 elements: [4, 3]")
        end

        @testset "op: ⊋" begin
            f = (lhs, rhs) -> TM.eval_test_sets(lhs, :⊋, rhs, LineNumberNode(1))

            res = f([1,2,3], [1,2])
            @test res.value === true

            res = f(0:10, 1:5)
            @test res.value === true

            res = f([1,2,3,1], [1,2,2,3])
            @test res.value === false
            msg = destyle(res.data)
            @test startswith(msg, "L is not a proper superset of R, it is equal.")

            res = f([1,2], Set([1,2,3]))
            @test res.value === false
            msg = destyle(res.data)
            @test startswith(msg, "L is not a proper superset of R.")
            @test contains(msg, "R ∖ L has 1 element:  [3]")

            res = f([1,2], [1,2,4,1,1,3])
            @test res.value === false
            msg = destyle(res.data)
            @test startswith(msg, "L is not a proper superset of R.")
            @test contains(msg, "R ∖ L has 2 elements: [4, 3]")
        end

        @testset "op: ∩" begin
            f = (lhs, rhs) -> TM.eval_test_sets(lhs, :∩, rhs, LineNumberNode(1))

            res = f([1,2,3], [4,5])
            @test res.value === true

            res = f(1:5, 6:10)
            @test res.value === true

            res = f(1, [3,4])
            @test res.value === true

            res = f([1,2,3], [3,4])
            @test res.value === false
            msg = destyle(res.data)
            @test startswith(msg, "L and R are not disjoint.")
            @test contains(msg, "L ∩ R has 1 element:  [3]")

            res = f(1:5, 3:8)
            @test res.value === false
            msg = destyle(res.data)
            @test startswith(msg, "L and R are not disjoint.")
            @test contains(msg, "L ∩ R has 3 elements: [3, 4, 5]")
        end
    end

    @testset "@test_sets" begin

        @testset "Pass" begin
            @test_sets 1:2 == [2,1]
            @test_sets [1,1] == Set(1)
            @test_sets issetequal([1,3,3,1], 1:2:3)
            @test_sets ∅ == ∅
            
            @test_sets [1,2] != 1:3
            @test_sets Set(1:3) ≠ 2
            @test_sets ∅ ≠ [1 2]

            @test_sets 1:2 ⊆ [1,2]
            @test_sets 3 ⊂ Set(3)
            @test_sets issubset([1,2],0:100)
            @test_sets ∅ ⊆ 1:2

            @test_sets [1,2] ⊇ 1:2
            @test_sets Set(3) ⊃ [3]
            @test_sets 0:100 ⊇ [42,42]
            @test_sets 1:2 ⊇ ∅

            @test_sets [1,2] ⊊ 1:3
            @test_sets 1 ⊊ [1,2,1]
            @test_sets [3] ⊊ Set(1:3)
            @test_sets ∅ ⊊ 1

            @test_sets [1,2,3] ⊋ 1:2
            @test_sets 1:100 ⊋ [42,42]
            @test_sets Set(1:3) ⊋ [3]
            @test_sets 1 ⊋ ∅

            @test_sets [1,2,3] ∩ [4,5]
            @test_sets 1:5 || 6:8
            @test_sets isdisjoint(3, Set([1,2]))
            @test_sets ∅ ∩ ∅ == ∅
            @test_sets isdisjoint(∅, 1:2)
            @test_sets 1 ∩ [2,3] == ∅
            @test_sets ∅ == [4,5] ∩ Set(6)
        end

        @testset "Fail" begin
            messages = []
            let fails = @testset NoThrowTestSet begin
                    # 1
                    @test_sets [1,2,3] == [1,2,3,4]
                    push!(messages, [
                        "Expression: [1, 2, 3] == [1, 2, 3, 4]",
                        "Evaluated: L and R are not equal.",
                    ])

                    # 2
                    a, b = 1, 1
                    @test_sets a ≠ b
                    push!(messages, [
                        "Expression: a ≠ b",
                        "Evaluated: L and R are equal.",
                    ])

                    # 3
                    a = [3,2,1,3,2,1]
                    @test_sets a ⊆ 2:3
                    push!(messages, [
                        "Expression: a ⊆ 2:3",    
                        "Evaluated: L is not a subset of R.",
                    ])

                    # 4
                    @test_sets 2:4 ⊇ 1:5
                    push!(messages, [
                        "Expression: 2:4 ⊇ 1:5",
                        "Evaluated: L is not a superset of R.",
                    ])

                    # 5
                    b = 1:3
                    @test_sets [1,2,3] ⊊ b
                    push!(messages, [
                        "Expression: [1, 2, 3] ⊊ b",
                        "Evaluated: L is not a proper subset of R, it is equal.",
                    ])

                    # 6
                    @test_sets 1:4 ⊊ 1:3
                    push!(messages, [
                        "Expression: 1:4 ⊊ 1:3",
                        "Evaluated: L is not a proper subset of R.",
                    ])

                    # 7
                    SET = Set([5,5,5,6])
                    @test_sets SET ⊋ [6,5]
                    push!(messages, [
                        "Expression: SET ⊋ [6, 5]",
                        "Evaluated: L is not a proper superset of R, it is equal.",
                    ])

                    # 8
                    @test_sets (1,1,1,2) ⊋ (3,2)
                    push!(messages, [
                        "Expression: (1, 1, 1, 2) ⊋ (3, 2)",
                        "Evaluated: L is not a proper superset of R.",
                    ])

                    # 9
                    @test_sets [1,1,1,2] ∩ [3,2] 
                    push!(messages, [
                        "Expression: [1, 1, 1, 2] ∩ [3, 2] == ∅",
                        "Evaluated: L and R are not disjoint.",
                    ])

                    # 10
                    a = [1,2,3]
                    @test_sets a != [1,2,3]
                    push!(messages, [
                        "Expression: a ≠ [1, 2, 3]",
                        "Evaluated: L and R are equal.",
                    ])

                    # 11
                    @test_sets 4 ⊂ Set(1:3)
                    push!(messages, [
                        "Expression: 4 ⊆ Set(1:3)",
                        "Evaluated: L is not a subset of R.",
                    ])

                    # 12
                    a = Set(1:3)
                    @test_sets a ⊃ 4
                    push!(messages, [
                        "Expression: a ⊇ 4",
                        "Evaluated: L is not a superset of R.",
                    ])

                    # 13
                    @test_sets 1:3 || 2:4
                    push!(messages, [
                        "Expression: 1:3 ∩ 2:4 == ∅",
                        "Evaluated: L and R are not disjoint.",
                    ])

                    # 14
                    a = [1]
                    @test_sets issetequal(a, 2)
                    push!(messages, [
                        "Expression: a == 2",
                        "Evaluated: L and R are not equal.",
                    ])

                    # 15
                    @test_sets isdisjoint(1, 1)
                    push!(messages, [
                        "Expression: 1 ∩ 1 == ∅",
                        "Evaluated: L and R are not disjoint.",
                    ])

                    # 16
                    @test_sets issubset(1:5, 3)
                    push!(messages, [
                        "Expression: 1:5 ⊆ 3",
                        "Evaluated: L is not a subset of R.",
                    ])

                    # 17
                    @test_sets ∅ ⊋ ∅
                    push!(messages, [
                        "Expression: ∅ ⊋ ∅",
                        "Evaluated: L is not a proper superset of R, it is equal.",
                    ])

                    # 18
                    @test_sets ∅ == 1:5
                    push!(messages, [
                        "Expression: ∅ == 1:5",
                        "Evaluated: L and R are not equal.",
                    ])

                end

                @testset "ex[$i]: $(fail.orig_expr)" for (i, fail) in enumerate(fails)
                    @test fail isa Test.Fail
                    @test fail.test_type === :test
                    str = destyle(sprint(show, fail))
                    for msg in messages[i]
                        @test contains(str, msg)
                    end
                end
            end # let fails
        end

        @testset "skip/broken=false" begin
            a = 1
            @test_sets 1 == 1 broken=false
            @test_sets 1 == 1 skip=false
            @test_sets 1 == 1 broken=a==2
            @test_sets 1 == 1 skip=!isone(1)
        end

        @testset "skip=true" begin
            let skips = @testset NoThrowTestSet begin
                    # 1
                    @test_sets 1 == 1 skip=true
                    # 2
                    @test_sets 1 == 2 skip=true
                    # 3
                    @test_sets 1 == error("fail gracefully") skip=true
                end

                @testset "skipped[$i]" for (i, skip) in enumerate(skips)
                    @test skip isa Test.Broken
                    @test skip.test_type === :skipped
                end
            end # let skips
        end

        @testset "broken=true" begin
            let brokens = @testset NoThrowTestSet begin
                    # 1
                    @test_sets 1 == 2 broken=true
                    # 2
                    @test_sets 1 == error("fail gracefully") broken=true
                end

                @testset "broken[$i]" for (i, broken) in enumerate(brokens)
                    @test broken isa Test.Broken
                    @test broken.test_type === :test
                end
            end # let brokens

            let unbrokens = @testset NoThrowTestSet begin
                    # 1
                    @test_sets 1 == 1 broken=true
                end

                @testset "unbroken[$i]" for (i, unbroken) in enumerate(unbrokens)
                    @test unbroken isa Test.Error
                    @test unbroken.test_type === :test_unbroken
                end
            end # let unbrokens
        end

        @testset "Error" begin
            messages = []
            let errors = @testset NoThrowTestSet begin
                    # 1
                    @test_sets A == B
                    push!(messages, "UndefVarError: `A` not defined")
                    # 2
                    @test_sets sqrt(-1) == 3
                    push!(messages, "DomainError with -1.0")
                    # 3
                    @test_sets 3 == error("fail ungracefully")
                    push!(messages, "fail ungracefully")
                end

                @testset "error[$i]" for (i, error) in enumerate(errors)
                    @test error isa Test.Error
                    @test error.test_type === :test_error
                    @test contains(sprint(show, error), messages[i])
                end
            end
        end

        @testset "evaluate arguments once" begin
            g = Int[]
            f = (x) -> (push!(g, x); x)
            @test_sets f(1) == 1
            @test g == [1]

            empty!(g)
            @test_sets 1 ≠ f(2)
            @test g == [2]
        end

    end
end