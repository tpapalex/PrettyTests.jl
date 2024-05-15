# Copied from Test package, for testing test failures
mutable struct NoThrowTestSet <: Test.AbstractTestSet
    results::Vector
    NoThrowTestSet(desc) = new([])
end
Test.record(ts::NoThrowTestSet, t::Test.Result) = (push!(ts.results, t); t)
Test.finish(ts::NoThrowTestSet) = ts.results

# User-defined struct with custom show for testing
struct TestStruct 
    a::Int64
    b::Float64
end
Base.show(io::IO, s::TestStruct) = print(io, "S(", s.a, ", ", s.b, ")")

# Remove ANSI color codes from a string
destyle = x -> replace(x, r"\e\[\d+m" => "")

# Evaluate occursin(x, str), but replaces every `\e` with a regex that matches an 
# ANSI color code.
ansioccursin = (x, str) -> occursin(Regex(replace(x, '\e' => raw"\e\[\d+m")), str)