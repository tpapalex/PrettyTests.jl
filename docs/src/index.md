```@meta
CurrentModule = TestMacroExtensions
```

# TestMacroExtensions Package

This [TestMacroExtensions](https://github.com/tpapalex/TestMacroExtensions.jl) package
extends Julia's basic unit-testing functionality by providing drop-in replacements
for [`Test.@test`](@extref Julia) with more informative, human-readable failure messages.

- [`@test_sets`](@ref TestMacroExtensions.@test_sets) for set-like comparisons of collections.
- [`@test_all`](@ref TestMacroExtensions.@test_all) for element-wise (vectorized) tests.

All macros work seamlessly within the standard [`Test`](@extref Julia Unit-Testing)
framework, including integration with [`Test.@testset`](@extref Julia Working-with-Test-Sets)
and support for [broken tests](@extref Julia Test.Broken).