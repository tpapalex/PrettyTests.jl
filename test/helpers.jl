@testset "helpers.jl" begin
    @testset "failure_styling" begin
        @test !PT.disable_failure_styling()
        @test PT.STYLED_FAILURES[] === false
        @test PT.enable_failure_styling()
        @test PT.STYLED_FAILURES[] === true
        @test !PT.disable_failure_styling()
        @test PT.STYLED_FAILURES[] === false
    end

    @testset "max_print_failures" begin
        PT.set_max_print_failures(0)
        @test PT.MAX_PRINT_FAILURES[] == 0
        @test PT.set_max_print_failures(5) == 0 # returns previous value
        @test PT.MAX_PRINT_FAILURES[] == 5
        @test PT.set_max_print_failures(nothing) == 5 
        @test PT.MAX_PRINT_FAILURES[] == typemax(Int64)
        @test PT.set_max_print_failures() == typemax(Int64)
        @test PT.MAX_PRINT_FAILURES[] == 10 # default is 10
    end
end