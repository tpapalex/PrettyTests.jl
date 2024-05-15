## Set-like comparisons with `@test_sets`

The [`@test_sets`](@ref) macro is used for set-like comparisons of two collections.
The syntax is always `@test_sets L <op> R` where `op` is an infix set comparison
operator, and `L` and `R` are collections, broadly defined.

In the simplest example, one could test for set equality with the (overloaded) `==`
operator:

```@setup test_sets
using TestMacroExtensions, Test 
TestMacroExtensions.enable_failure_styling()
TestMacroExtensions.set_max_print_failures(10)
```

```@repl test_sets
a, b = [1, 1, 2], 1:2;
@test_sets a == b
```

This is equivalent to the uglier test `@test issetequal(a, 1:2)`. It is also more
informative in the case of failure:

```@repl test_sets
@test_sets a == 2:4
```

The failed test message lists exactly how many and which elements were in the set
differences`L \ R` and `R \ L`, which would have been empty in a passing test.

Note also how the collections interpreted as `L` and `R` are color-coded,
so that they can be more easily identified if the expressions are long:

```@repl test_sets
variable_with_long_name = 1:5;
function_with_long_name = () -> 6:15;
@test_sets variable_with_long_name ∪ Set(5:10) == function_with_long_name()
```

!!! note "Disabling colored subexpressions"
    The coloring of subexpressions can be disabled globally or partially for test suites,
    see [Changing display settings](@ref).

The symbol `∅` can be used as shorthand for `Set()` in the place of either `L` or `R`:

```@repl test_sets
@test_sets Set() == ∅
@test_sets Set(1) == ∅
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

Note how in this case the failure only produces the set difference `L \ R`, and omits the
irrelevant `R \ L`.

As a final example, the form `L ∩ R == ∅` can be used to test for disjointness,
expanding to [`isdisjoint`](@extref Julia Base.isdisjoint)`(L, R)`.
In the case of failure, the intersection `L ∩ R` is shown (as computed by
[intersect](@extref Julia Base.intersect)):

```@repl test_sets
@test_sets (1, 2, 3) ∩ (4, 5, 6) == ∅
@test_sets "baabaa" ∩ "abc" == ∅
```

!!! info "Shorthand disjointness syntax"
    Though slightly abusive in terms of notation, the macro will also accept `L ∩ R` and
    `L || R` as shorthands for `isdisjoint(L, R)`:

    ```@repl test_sets
    @test_sets "baabaa" ∩ "moooo"
    @test_sets (1,2) || (3,4)
    ```

## Vectorized tests with `@test_all`

The [`@test_all`](@ref) macro can be used to perform "vectorized"
[`@test`](@ref Julia Test.@test)s. The name derives from the fact that `@test_all ex`
should behave like `@test all(ex)`:

```@setup test_all
using TestMacroExtensions, Test 
TestMacroExtensions.enable_failure_styling()
TestMacroExtensions.set_max_print_failures(10)
```

```@repl test_all
a = [1, 2, 3, 4]; 
@test all(a .< 4)
@test_all a .< 4
```

With one important difference: `@test_all` will **not**
[short-circuit](@extref Julia Base.all-Tuple{Any}) when it encounters the first `false`
value. As a result, it is able to print errors for each "individual" failure:

```@repl test_all
@test_all a .< 2
```

The failed test informs us that `3` elements of the expression evaluated to `false`, at
indices `[2]`, `[3]` and `[4]`. Similar to [`@test`](@extref Julia Test.@test),
the error will introspect and show the unvectorized expression that resulted in
each failure, e.g. `4 < 2 ===> false` at index `[4]`, color-coded to match the quoted
expression.

Though complicated tests are not particularly advisable in a unit-testing framework,
the macro can introspect and color-code complicated expressions:

```@repl test_all
x, y, str = 2, 4.0, "baa";
@test_all (x .< 2) .| isnan.(y) .& .!occursin.(r"a|b", str)
```

Note that, since the expression evaluated to `false` rather than a `BitVector`, the
macro ommitted the summary and index information.

!!! note "Disabling colored subexpressions"
    The coloring of subexpressions can be disabled globally or partially for test suites,
    see [Changing display settings](@ref).

!!! info "Introspection mechanics"
    Failure messages are produced by recursively diving through the input expression's
    syntax tree (AST) and creating/combining format strings for any "displayable"
    subexpression that is encountered. Displayable expressions include:
    - `:comparison`s or `:call`s with vectorized operators, e.g. `.==`, `.≈`, `.∈`
    - `:call`s to the vectorized negation operator `.!`
    - `:call`s to vectorized bitwise logical operators, e.g. `&`, `|`, `⊻`, `⊽`
    - `:.`  (dot) calls to certain common functions, like `isnan`, `contains`, `occursin`

    Notably, only vectorized subexpressions are displayable. Compare the output of the 
    previous block with the following exactly equivalent test:
    ```@repl test_all
    @test_all (x < 2) .| isnan(y) .| !occursin(r"a|b", str)
    ```

    The parser only color codes the arguments to the vectorized parts.

TODO: talk about more complicated indexing [:a,:b] .== [:a :b], non-bool behaviour, 
missing behaviour.

## Integrations with `Test`

TODO: talk about testsets, broken/skip keywords

## Changing display settings

TODO: talk about turning off colors and setting max print
