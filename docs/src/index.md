```@meta
CurrentModule = TestMacroExtensions
```

# Introduction

This [TestMacroExtensions](https://github.com/tpapalex/TestMacroExtensions.jl) package
extends Julia's basic unit-testing functionality by providing drop-in replacements
for [`Test.@test`](@extref Julia) with more informative, human-readable failure messages.
It currently exports two such macros:

- [`@test_sets`](@ref TestMacroExtensions.@test_sets) works for set-like comparisons of collections.
- [`@test_all`](@ref TestMacroExtensions.@test_all) works for element-wise (vectorized) tests.

The macros work seamlessly within Julia's standard [`Test`](@extref Julia Unit-Testing)
library, including integration with [`Test.@testset`](@extref Julia Working-with-Test-Sets)
and support for [broken](@extref Julia Test.@test_broken) or [skipped](@extref Julia
Test.@test_skip) tests.
