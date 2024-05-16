This showcase assumes some familiarity with Julia's standard unit-testing library
[Test](@extref Julia Basic-Unit-Tests) and the [`@test`](@extref Julia Test.@test)
macro in particular. 

```@contents
Pages = ["showcase.md"]
```

## Set comparisons with `@test_sets`

The [`@test_sets`](@ref) macro can be used in lieu of [`@test`](@extref Julia Test.@test)
when comparing two set-like objects. It accepts expressions of the form
`@test_sets L <op> R` where `op` is an infix set comparison
operator, and `L` and `R` are Julia collections, broadly defined.

In the simplest example, one could test for set equality with the (overloaded) `==`
operator:

```@setup test_sets
using TestMacroExtensions, Test 
TestMacroExtensions.enable_failure_styling()
TestMacroExtensions.set_max_print_failures(10)

mutable struct NoThrowTestSet <: Test.AbstractTestSet
    results::Vector
    NoThrowTestSet(desc) = new([])
end
Test.record(ts::NoThrowTestSet, t::Test.Result) = (push!(ts.results, t); t)
function Test.finish(ts::NoThrowTestSet)
    length(ts.results) > 0 || return nothing 
    str = sprint(show, ts.results[end], context=:color=>true)
    str = replace(str, r"Stacktrace:(.|\n)*$" => "Stacktrace: ...")
    print(str);
end
```

```@repl test_sets
a, b = [1, 1, 2], 1:2;
@testset NoThrowTestSet begin # hide
@test_sets a == b
end # hide
```

This is equivalent to the uglier test `@test issetequal(a, 1:2)`. It is also more
informative in the case of failure:

```@repl test_sets
@testset NoThrowTestSet begin # hide
@test_sets a == 2:4
end # hide
```

The failed test message lists exactly how many and which elements were in the set
differences`L \ R` and `R \ L`, which should have been empty in a passing test.

Note how the collections interpreted as `L` and `R` are color-coded,
so that they can be more easily identified if the expressions are long:

```@repl test_sets
variable_with_long_name = 1:5;
function_with_long_name = () -> 6:15;
@testset NoThrowTestSet begin # hide
@test_sets variable_with_long_name ∪ Set(5:10) == function_with_long_name()
end # hide
```

!!! note "Disabling colored subexpressions"
    The coloring of subexpressions can be disabled globally or partially for test suites,
    see [Changing display settings](@ref).

The symbol `∅` can be used as shorthand for `Set()` in the place of either `L` or `R`:

```@repl test_sets
@testset NoThrowTestSet begin # hide
@test_sets Set() == ∅
end # hide

@testset NoThrowTestSet begin # hide
@test_sets Set(1) == ∅
end # hide
```

Because the macro internally expands the input expression to an
[`issetequal`](@extref Julia Base.issetequal) call
(and uses [`setdiff`](@extref Julia Base.setdiff) to print the differences),
it works very flexibly with general collections, including sets, dictionaries,
strings, etc:

```@repl test_sets
@testset NoThrowTestSet begin # hide
@test_sets Dict() == Set()
end # hide

@testset NoThrowTestSet begin # hide
@test_sets "baabaa" == "abc"
end # hide
```

Other comparison tests are also supported, with tailored failure messages. For example,
the expression `L ⊆ R` tests that `issubset(L, R)`
[(as it does in base Julia)](@extref Julia Base.issubset):

```@repl test_sets
@testset NoThrowTestSet begin # hide
@test_sets "baabaa" ⊆ "abc"
end # hide

@testset NoThrowTestSet begin # hide
@test_sets (3, 1, 2, 3) ⊆ (1, 2)
end # hide
```

Note how in this case the failure only displays the set difference `L \ R`, and omits the
irrelevant `R \ L`.

Disjointness of two collections can be tested with the form `L ∩ R == ∅`, which
internally evaluates [`isdisjoint`](@extref Julia Base.isdisjoint)`(L, R)`.
In the case of failure, the macro displays the non-empty intersection `L ∩ R` (as computed
by [intersect](@extref Julia Base.intersect)):

```@repl test_sets
@testset NoThrowTestSet begin # hide
@test_sets (1, 2, 3) ∩ (4, 5, 6) == ∅
end # hide

@testset NoThrowTestSet begin # hide
@test_sets "baabaa" ∩ "abc" == ∅
end # hide
```

!!! info "Shorthand disjointness syntax"
    Though slightly abusive in terms of notation, the macro will also accept `L ∩ R` and
    `L || R` as shorthands for `isdisjoint(L, R)`:

    ```@repl test_sets
    @testset NoThrowTestSet begin # hide
    @test_sets "baabaa" ∩ "moooo"
    end # hide

    @testset NoThrowTestSet begin # hide
    @test_sets (1,2) || (3,4)
    end # hide
    ```

## Vectorized tests with `@test_all`

The [`@test_all`](@ref) macro can be used to perform "vectorized"
[`@test`](@ref Julia Test.@test)s. The name derives from the fact that 
`@test_all ex` will (mostly) behave like `@test all(ex)`:

```@setup test_all
using TestMacroExtensions, Test 
TestMacroExtensions.enable_failure_styling()
TestMacroExtensions.set_max_print_failures(10)
mutable struct NoThrowTestSet <: Test.AbstractTestSet
    results::Vector
    NoThrowTestSet(desc) = new([])
end
Test.record(ts::NoThrowTestSet, t::Test.Result) = (push!(ts.results, t); t)
function Test.finish(ts::NoThrowTestSet)
    length(ts.results) > 0 || return nothing 
    str = sprint(show, ts.results[end], context=:color=>true)
    str = replace(str, r"Stacktrace:(.|\n)*$" => "Stacktrace: ...")
    print(str);
end
```

```@repl test_all
a = [1, 2, 3, 4]; 
@testset NoThrowTestSet begin # hide
@test all(a .< 5)
end # hide
@testset NoThrowTestSet begin # hide
@test_all(a .< 5)
end # hide
```

There is one important difference: `@test_all` will not
[short-circuit](@extref Julia Base.all-Tuple{Any}) when it encounters the first `false`
value. It evaluates the full expression and checks that *each element* is not false,
printing errors for each "individual" failure:

```@repl test_all
@testset NoThrowTestSet begin # hide
@test_all a .< 2
end # hide
```

The failure message can be parsed as follows:

- The expression `all(a .< 2)` evaluated to `false`
- The argument to `all()` was a `4-element BitVector`
- There were `3` failures, i.e. elements of the argument that were `false`
- These occured at indices `[2]`, `[3]` and `[4]`

Like [`@test`](@extref Julia Test.@test), the macro performed some
introspection to show an *unvectorized* (and color-coded) form of the expression
for each individual failure. For example, the failure at index `[4]` was because
`4 < 2 ===> false`.

The introspection can handle pretty complicated expressions (though these are probably
not advisable in a unit-testing context):

```@repl test_all
x, y, str = 2, 4.0, "baa";
@testset NoThrowTestSet begin # hide
@test_all (x .< 2) .| isnan.(y) .& .!occursin.(r"a|b", str)
end # hide
```

Note also how, since the argument to `all` was a scalar (`false`), the failure message
ommitted the summary and indexing notation and instead just printed the individual

!!! note "Disabling colored subexpressions"
    The coloring of subexpressions can be disabled globally or partially for test suites,
    see [Changing display settings](@ref).

!!! info "Introspection mechanics"
    Failure messages are produced by recursively diving through the input expression's
    syntax tree (AST) and creating/combining format strings for any "displayable"
    subexpression that is encountered. Displayable expressions include:
    - `:comparison`s or `:call`s with vectorized operators, e.g. `.==`, `.≈`, `.∈`
    - `:call`s to the vectorized negation operator `.!`
    - `:call`s to vectorized bitwise logical operators, e.g. `.&`, `.|`, `.⊻`, `.⊽`
    - `:.`  (dot) calls to certain common functions, like `isnan`, `contains`, `occursin`

    **Note that only vectorized subexpressions are displayable**. Compare the output of the 
    previous block with the following exactly equivalent test:
    ```@repl test_all
    @testset NoThrowTestSet begin # hide
    @test_all (x .< 2) .| isnan(y) .| !occursin(r"a|b", str)
    end # hide
    ```

    The parser only color codes the arguments to the vectorized parts. For example, 
    if 

Expressions that involve more complicated broadcasting behaviour are also nicely
formatted:

```@repl test_all
@testset NoThrowTestSet begin # hide
@test_all 1 .== [1 0; 0 1]
end # hide

@testset NoThrowTestSet begin # hide
@test_all occursin.([r"a|b" "oo"], ["baa", "moo"])
end # hide
```

Generally, the macro will parallel the behaviour of
[`all()`](@extref Julia Base.all-Tuple{Any}) pretty closely, with some bells and whistles.
It will work with general iterables (albeit with less informative messages):

```@example test_all
struct IsEven vals end
Base.length(x::IsEven) = length(x.vals)
Base.iterate(x::IsEven, i=1) = i > length(x.vals) ? nothing : (x.vals[i] % 2 == 0, i+1);
```

```@repl test_all
@testset NoThrowTestSet begin # hide
@test_all IsEven([1, 0, -1])
end # hide
```

!!! warning "Behaviour due to short-circuiting."
    By design, `@test_all` does not short-circuit at the first `false` value. This may
    cause different behaviour than `all()` in certain edge cases, notably when evaluating
    the expression has side effects. Consider the same iterable as above, but with an
    error when negative numbers are encountered:

    ```@example test_all
    struct IsEvenPositive vals end
    Base.length(x::IsEvenPositive) = length(x.vals)
    function Base.iterate(x::IsEvenPositive, i=1) 
        i > length(x.vals) && return nothing
        @assert x.vals[i] >= 0
        x.vals[i] % 2 == 0, i+1
    end;
    ```
    ```@repl test_all
    all(IsEvenPositive([1, 0, -1]))
    ```
    Because `all` short-circuits when the first element fails to be even, it never 
    throws an assertion error. The same is not true of `@test_all`, which does not 
    short-circuit:

    ```@repl test_all
    @testset NoThrowTestSet begin # hide
    @test_all IsEvenPositive([1, 0, -1])
    end # hide
    ```

The macro will produce a [`Test.Error`](@extref Julia) result if non-Boolean values
are encountered in the evaluated expression, just like
[`all()`](@extref Julia Base.all-Tuple{Any}) does, and specify at which indices this
occured:

```@repl test_all
@testset NoThrowTestSet begin # hide
@test_all [true, false, 42, "a", missing]
end # hide
```

Note how the `missing` value was not flagged as a non-Boolean. Again, this is to parallel
the behaviour of [`all()`](@extref Julia Base.all-Tuple{Any}), which will evaluate
to `missing` or `false` if there are any missing values (depending whether all
non-missing values were `true` or not). To this end, `@test_all` will return a `Test.Fail`
if it encounters any missing value.

```@repl test_all
all([1, missing] .== 1)
@testset NoThrowTestSet begin # hide
@test_all [1, missing] .== 1
end # hide
all([2, missing] .== 2)
@testset NoThrowTestSet begin # hide
@test_all [2, missing] .== 2
end # hide
```

## Changing display settings

TODO: talk about turning off colors and setting max print


## Integrations with `Test`

TODO: talk about how 
TODO: talk about testsets, broken/skip keywords