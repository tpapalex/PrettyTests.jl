## Set-like comparisons with `@test_sets`

The [`@test_sets`](@ref) macro is used to do set-like comparisons of two collections.
The syntax is `@test_sets L <op> R`, where `op` is an infix set comparison
operator, and `L` and `R` are collections, broadly defined.

In the simplest example, one could test for set equality with the (overloaded) `==`
operator:

```@repl test_sets
using TestMacroExtensions, Test # hide
a = [1, 1, 2]; b = 1:2;
@test_sets a == b
```

This is equivalent to the uglier test `@test issetequal(a, 1:2)`. It is also more
informative in the case of failure:

```@repl test_sets
@test_sets a == 2:4
```

The failed test message lists exactly how many and which elements were in the set
difference `L \ R` (in this case the single element `[1]`), and vice-versa for
the difference `R \ L` (in this case `[3, 4]`).

The collections `L` and `R`are color-coded in the message, so that they can be easily
visually identified if the expressions are long:

```@repl test_sets
variable_with_long_name = 1:5
function_with_long_name = () -> 6:15
@test_sets variable_with_long_name ∪ Set(5:10) == function_with_long_name()
```

The symbol `∅` can be used as shorthand for `Set()` in the place of either `L` or `R`:

```@repl test_sets
@test_sets Set([1,2,3]) == ∅
```

Because the macro internally expands the input expression to an
[`issetequal`](@extref Julia Base.issetequal) call
(and uses [`setdiff`](@extref Julia Base.setdiff) to print the differences),
it works very flexibly with general collections, including sets, dictionaries,
strings, etc:

```@repl test_sets
@test_sets Dict() == Set()
@test_sets "baabaa" == "abc"
```

The macro supports several other set comparisons, using intuitive operator notation
and tailored failure messages. For example the expression `L ⊆ R` will evaluate
`issubset(L, R)` [(as it does in base Julia)](@extref Julia Base.issubset):

```@repl test_sets
@test_sets "baabaa" ⊆ "abc"
@test_sets (3, 1, 2, 3) ⊆ (1, 2)
```

Note how in this case the failure only produces the relevant set difference `L \ R`
(since `R \ L` is expected to be non-empty).

As a final example, the expression `L ∩ R == ∅` (and slightly abusive shorthands
`L ∩ R` or `L || R`) will expand to `[isdisjoint](@extref Julia Base.isdisjoint)(L, R)`.
In the case of failure, the intersection `L ∩ R` is shown (as computed by
[intersect](@extref Julia Base.intersect)):

```@repl test_sets
@test_sets (1, 2, 3) ∩ (4, 5, 6) == ∅
@test_sets "baabaa" ∩ "abc"
```

## Vectorized tests with `@test_all`

The [`@test_all`](@ref) macro can be used to perform "vectorized" (element-wise)
[`@test`](@ref Julia Test.@test)s. The name derives from the fact that `@test_all ex`
behaves equivalently to `@test all(ex)`:

```@repl test_all
using TestMacroExtensions, Test # hide
TestMacroExtensions.set_max_print_failures(10)
a = [1, 2, 3]; 
@test all(a .< 4)
@test_all a .< 4
```

There is one important difference however: `@test_all` will not
[short-circuit](@extref Julia Base.all!) when it encounters the first `false` value.
As a result, it is able to include clear messages for each "individual" failure:

```@repl test_all
@test_all a .< 2
```

Note how, similarly to [`@test`](@extref Julia Test.@test), the macro does some
introspection to format the individual failures as (unvectorized) human-readable
expressions; for example printing the failure at index `[3]` as `3 < 2`.

The introspection works for a range of vectorized expressions, including comparisons,
bitwise logical operations, and certain common functions:

```@repl test_all
a = 1:3
x = [1, 2, NaN];
s = ["baa", "moo", ""];
@test_all (a .< 2) .| isnan.(x) .& .!occursin.(r"a|b", s)
```

## Integration with [Test](@extref Julia Unit-Testing)
