# PrettyTests.jl

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://tpapalex.github.io/PrettyTests.jl/dev/)
[![Build Status](https://github.com/tpapalex/PrettyTests.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/tpapalex/PrettyTests.jl/actions/workflows/CI.yml?query=branch%3Amain)

A Julia package that provides `@test`-like macros with more informative error messages.

The inspiration comes from `python` [asserts](https://docs.python.org/3/library/unittest.html#assert-methods), which customize the error message based on the type of unit test being performed; for example, by showing the differences between two sets or lists that should be equal.

`PrettyTests` exports drop-in replacements for `@test` that are designed to (a) provide concise error messages tailored to specific situations, and (b) conform with the standard [`Test`](https://docs.julialang.org/en/v1/stdlib/Test/) interface so that they fit into to any unit-testing workflow.

## Installation

The package requires Julia `1.7` or higher. It can be installed using Julia's package manager: first type `]` in the REPL, then:

```
pkg> add PrettyTests
```

## Example Usage


```@julia-repl
julia> @test_all [1, 2, 3] .< 2
Test Failed at none:1
  Expression: all([1, 2, 3] .< 2)
   Evaluated: false
    Argument: 3-element BitVector, 2 failures:
              [2]: 2 < 2 ===> false
              [3]: 3 < 2 ===> false

julia> @test_sets [1, 2, 3] ∩ [2, 3, 4] == ∅
Test Failed at none:1
  Expression: [1, 2, 3] ∩ [2, 3, 4] == ∅
   Evaluated: L and R are not disjoint.
              L ∩ R has 2 elements: [2, 3]

```

More details and functionalities are listed in the package [documentation](https://tpapalex.github.io/PrettyTests.jl/dev/).