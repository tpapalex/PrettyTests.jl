```@meta
CurrentModule = PrettyTests
```

# Home

[PrettyTests](https://github.com/tpapalex/PrettyTests.jl) extends Julia's basic
unit-testing functionality by providing drop-in replacements for [`Test.@test`]
(@extref Julia) with more informative error messages.

The inspiration for the package comes from [`python`](@extref python assert-methods)
and [`numpy` asserts](@extref numpy numpy.testing), which customize their error messages
depending on the type of test being performed; for example, by showing the
differences between two sets that should be equal or the number of elements that
differ in two arrays.

`PrettyTests` macros are designed to (a) provide clear and concise error messages
tailored to specific situations, and (b) conform with the standard
[`Test`](@extref Julia stdlib/Test) library interface, so that they can fit into any
testing workflow. This guide walks through several examples:

```@contents
Pages = ["index.md"]
Depth = 2:3
```

The package requires Julia `1.7` or higher, and can be installed in the usual way:
type `]` to enter the package manager, followed by `add PrettyTests`.

## `@test_sets` for set-like comparisons

### Set equality

The [`@test_sets`](@ref) macro is used to compare two set-like objects.
It accepts expressions of the form `@test_sets L <op> R`, where `op` is an infix set
comparison operator and `L` and `R` are collections, broadly defined.

In the simplest example, one could test for set equality with the (overloaded) `==`
operator:

```@setup test_sets
using PrettyTests, Test 
PrettyTests.enable_failure_styling()
PrettyTests.set_max_print_failures(10)

mutable struct JustPrintTestSet <: Test.AbstractTestSet
    results::Vector
    JustPrintTestSet(desc) = new([])
end

function Test.record(ts::JustPrintTestSet, t::Test.Result)
    str = sprint(show, t, context=:color=>true)
    str = replace(str, r"Stacktrace:(.|\n)*$" => "Stacktrace: [...]")
    println(str)
    push!(ts.results, t)
    return t
end

Test.finish(ts::JustPrintTestSet) = nothing
```

```@repl test_sets
a, b = [2, 1, 1], [1, 2];
@testset JustPrintTestSet begin # hide
@test_sets a == b
end # hide
```

This is equivalent to the more verbose `@test issetequal(a, b)`. It is also more
informative in the case of failure:

```@repl test_sets
@testset JustPrintTestSet begin # hide
@test_sets a == 2:4
end # hide
```

The failed test message lists exactly how many and which elements were in the set
differences `L \ R` and `R \ L`, which should have been empty in a passing test.

Note how the collections interpreted as `L` and `R` are color-coded (using ANSI
color escape codes) so that they can be easily identified if the expressions are long:

```@repl test_sets
variable_with_long_name = 1:3;
function_with_long_name = () -> 4:9;
@testset JustPrintTestSet begin # hide
@test_sets variable_with_long_name ∪ Set(4:6) == function_with_long_name()
end # hide
```

!!! info "Disable color output"
    To disable colored subexpressions in failure messages use [`disable_failure_styling()`]
    (@ref PrettyTests.disable_failure_styling).

The symbol `∅` (typed as `\emptyset<tab>`) can be used as shorthand for `Set()` in any 
set expression:

```@repl test_sets
@testset JustPrintTestSet begin # hide
@test_sets Set() == ∅
end # hide

@testset JustPrintTestSet begin # hide
@test_sets [1,1] == ∅
end # hide
```

Because the macro internally expands the input expression to an
[`issetequal`](@extref Julia Base.issetequal) call
(and uses [`setdiff`](@extref Julia Base.setdiff) to print the differences),
it works very flexibly with general collections and iterables:

```@repl test_sets
@testset JustPrintTestSet begin # hide
@test_sets Dict() == Set()
end # hide

@testset JustPrintTestSet begin # hide
@test_sets "baabaa" == "abc"
end # hide
```

### Subsets

Set comparisons beyond equality are also supported, with modified error messages.
For example, [(as in base Julia)](@extref Julia Base.issubset), the expression `L ⊆ R`
is equivalent to `issubset(L, R)`:

```@repl test_sets
@testset JustPrintTestSet begin # hide
@test_sets "baabaa" ⊆ "abc"
end # hide

@testset JustPrintTestSet begin # hide
@test_sets (3, 1, 2, 3) ⊆ (1, 2)
end # hide
```

Note how, in this case, the failure displays only the set difference `L \ R` and omits the
irrelevant `R \ L`.

### Disjointness

The form `L ∩ R == ∅` is equivalent to [`isdisjoint`](@extref Julia Base.isdisjoint)`(L, R)`.
In the case of failure, the macro displays the non-empty intersection `L ∩ R`, as computed
by [intersect](@extref Julia Base.intersect):

```@repl test_sets
@testset JustPrintTestSet begin # hide
@test_sets (1, 2, 3) ∩ (4, 5, 6) == ∅
end # hide

@testset JustPrintTestSet begin # hide
@test_sets "baabaa" ∩ "abc" == ∅
end # hide
```

!!! info "Shorthand disjointness syntax"
    Though slightly abusive in terms of notation, the macro will also accept `L ∩ R` and
    `L || R` as shorthands for `isdisjoint(L, R)`:
    ```@repl test_sets
    @testset JustPrintTestSet begin # hide
    @test_sets "baabaa" ∩ "moooo"
    end # hide
    @testset JustPrintTestSet begin # hide
    @test_sets (1,2) || (3,4)
    end # hide
    ```

## `@test_all` for vectorized tests

### Basic usage

The [`@test_all`](@ref) macro is used for "vectorized"
[`@test`](@extref Julia Test.@test)s. The name derives from the fact that
`@test_all ex` will (mostly) behave like `@test all(ex)`:

```@setup test_all
using PrettyTests, Test 
PrettyTests.enable_failure_styling()
PrettyTests.set_max_print_failures(10)

mutable struct JustPrintTestSet <: Test.AbstractTestSet
    results::Vector
    JustPrintTestSet(desc) = new([])
end

function Test.record(ts::JustPrintTestSet, t::Test.Result)
    str = sprint(show, t, context=:color=>true)
    str = replace(str, r"Stacktrace:(.|\n)*$" => "Stacktrace: [...]")
    println(str)
    push!(ts.results, t)
    return t
end

#function Base.show(io::IO, t::Test.Fai)

Test.finish(ts::JustPrintTestSet) = nothing
```

```@repl test_all
a = [1, 2, 3, 4]; 
@testset JustPrintTestSet begin # hide
@test all(a .< 5)
end # hide
@testset JustPrintTestSet begin # hide
@test_all a .< 5
end # hide
```

With one important difference: `@test_all` does not
[short-circuit](@extref Julia Base.all-Tuple{Any}) when it encounters the first `false`
value. It evaluates the full expression and checks that *each element* is not `false`,
printing errors for each "individual" failure:

```@repl test_all
@testset JustPrintTestSet begin # hide
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
`a[4] = 4`, and `4 < 2` evaluated to `false`.

!!! note "Why not `@testset` for ...?"
    One could achieve a similar effect to `@test_all` by using the [`@testset for`]
    (@extref Julia Test.@testset) syntax built in to [`Test`](@extref Julia stdlib/Test).
    The test `@test_all a .< 2` is basically equivalent to:

    ```@julia
    @testset for i in eachindex(a)
        @test a[i] < 2
    end
    ```

    When the iteration is relatively simple, `@test_all` should be preferred for its 
    conciseness. It avoids the need for explicit indexing, e.g. `a[i]`, conforming with 
    Julia's intuitive broadcasting semantics.
    
    More importantly, all relevant information about the test failures (i.e. how many 
    and which indices failed) are printed in a single, concise [`Test.Fail`](@extref Julia)
    result rather than multiple, redundant messages in nested test sets.

The introspection goes quite a bit deeper than what [`@test`](@extref Julia Test.@test)
supports, handling pretty complicated expressions:

```@repl test_all
x, y, str, func = 2, 4.0, "baa", arg -> arg > 0;
@testset JustPrintTestSet begin # hide
@test_all (x .< 2) .| isnan.(y) .& .!occursin.(r"a|b", str) .| func(-1)
end # hide
```

Note also how, since `ex` evaluated to a scalar in this case, the failure message
ommitted the summary/indexing and printed just the single failure under `Argument:`.

!!! info "Disable color output"
    To disable colored subexpressions in failure messages use [`disable_failure_styling()`]
    (@ref PrettyTests.disable_failure_styling).

!!! details "Introspection mechanics"
    To create individual failure messages, the `@test_all` parser recursively dives
    through the [Abstract Syntax Tree (AST)](@extref Julia Surface-syntax-AST) of the
    input expression and creates/combines [`python`-like format strings]
    (https://github.com/JuliaString/Format.jl) for any of the following "displayable"
    forms:
    - `:comparison`s or `:call`s with vectorized comparison operators, e.g. `.==`, `.≈`,
      `.∈`, etc.
    - `:call`s to the vectorized negation operator `.!`
    - `:call`s to vectorized bitwise logical operators, e.g. `.&`, `.|`, `.⊻`, `.⊽`
    - `:.` (broadcast dot) calls to certain common functions, e.g. `isnan`, `contains`,
      `occursin`, etc.
    Any (sub-)expressions that do not fall into one of these categories are escaped and
    collectively [`broadcast`](@extref Julia Base.Broadcast.broadcast), so that
    elements can splatted into the format string at each failing index.

    *Note:* Unvectorized forms are not considered displayable by the parser. 
    This is to avoid certain ambiguities with broadcasting under the current
    implementation. This may be changed in future.

    ##### Example 1

    ```@repl test_all
    x, y = 2, 1;
    @testset JustPrintTestSet begin # hide
    @test_all (x .< y) .& (x < y)
    end # hide
    ```

    In this example, the parser first receives the top-level expression
    `(x .< y) .& (x < y)`, which it knows to display as `$f1 & $f2` in unvectorized form. 
    The sub-format strings `f1` and `f2` must then be determined by recursively parsing 
    the expressions on either side of `.&`. 

    On the left side, the sub-expression `x .< y` is also displayable as `($f11 < $f12)`
    with format strings `f11` and `f22` given by further recursion. At this level, the 
    parser hits the base case, since neither `x` nor `y` are displayable forms. The two
    expressions are escaped and used as the first and second broadcast arguments, while
    the corresponding format strings `{1:s}` and `{2:s}` are passed back up the recursion
    to create `f1` as `({1:s} < {2:s})`.

    On the right side, `x < y` is *not* displayable (since it is unvectorized) and 
    therefore escaped as whole to make the third broadcasted argument. The corresponding
    format string `{3:s}` is passed back up the recursion, and used as `f2`.

    By the end, the parser has created the format string is `({1:s} < {2:s}) & {3:s}`, 
    with three corresponding expressions `x`, `y`, and `x < y`. Evaluating and collectively 
    broadcasting the latter results in the scalar 3-tuple `(2, 1, false)`, which matches the
    dimension of the evaluated expression (`false`). Since this is a failure, the 3-tuple
    is splatted into the format string to create the part of the message that reads
    `(2 < 1) & false`.

    ##### Example 2

    ```@repl test_all
    x, y = [5 6; 7 8], [5 6];
    @testset JustPrintTestSet begin # hide
    @test_all x .== y
    end # hide
    ```

    Here, the top-level expression `x .== y` is displayable, while the two sub-expressions
    `x` and `y` are not. The parser creates a format string `{1:s} == {2:s}` with 
    corresponding expressions `x` and `y`. 

    After evaluating and broadcasting, the arguments create a `2×2` matrix of 2-tuples 
    to go with the `2×2 BitMatrix` result. The latter has two `false` elements at indices
    `[2,1]` and `[2,2]`, corresponding to the 2-tuples `(7, 5)` and `(8, 6)`. Splatting
    each of these into the format string creates the parts of the message that read 
    `7 == 5` and `8 == 6`.

### More complicated broadcasting

Expressions that involve more complicated broadcasting behaviour are naturally formatted.
For example, if the expression evaluates to a higher-dimensional array (e.g. `BitMatrix`),
individual failures are identified by their [`CartesianIndex`](@extref Julia Cartesian-indices):

```@repl test_all
@testset JustPrintTestSet begin # hide
@test_all [1 0] .== [1 0; 0 1]
end # hide

@testset JustPrintTestSet begin # hide
@test_all occursin.([r"a|b" "oo"], ["moo", "baa"])
end # hide
```

`Ref` can be used to avoid broadcasting certain elements:

```@repl test_all
vals = [1,2,3];
@testset JustPrintTestSet begin # hide
@test_all 1:5 .∈ Ref(vals)
end # hide
```

### Keyword splicing

Like [`@test`](@extref Julia Test.@test), [`@test_all`](@ref) will accept trailing keyword
arguments that will be spliced into `ex` if it is a function call (possibly `.` vectorized).
This is primarily useful to make vectorized approximate comparisons more readable:

```@repl test_all
v = [3, π, 4];
@testset JustPrintTestSet begin # hide
@test_all v .≈ 3.14 atol=0.15
end # hide
```

Splicing works with any callable function, including if it is wrapped in a negation:

```@repl test_all
iszero_mod(x; p=2) = x % p == 0;
@testset JustPrintTestSet begin # hide
@test_all .!iszero_mod.(1:3) p = 3
end # hide
```

### General iterables

Paralleling its [namesake](@extref Julia Base.all-Tuple{Any}), [`@test_all`](@ref)
works with general iterables (as long as they also define [`length`]
(@extref Julia Base.length)):

```@example test_all
struct IsEven vals end
Base.iterate(x::IsEven, i=1) = i > length(x.vals) ? nothing : (iseven(x.vals[i]), i+1);
Base.length(x::IsEven) = length(x.vals)
```

```@repl test_all
@testset JustPrintTestSet begin # hide
@test_all IsEven(1:4)
end # hide
```

If they also define [`keys`](@extref Julia Base.keys) and a corresponding [`getindex`]
(@extref Julia Base.getindex), failures will be printed by index:

```@example test_all
Base.keys(x::IsEven) = keys(x.vals)
Base.getindex(x::IsEven, args...) = getindex(x.vals, args...)
```

```@repl test_all
@testset JustPrintTestSet begin # hide
@test_all IsEven(1:4)
end # hide
```

!!! warning "Short-circuiting and iterables"
    Since `@test_all ex` does not short-circuit at the first `false` value, it may
    behave differently than `@test all(ex)` in certain edge cases, notably
    when iterating over `ex` has side-effects.
    
    Consider the same `IsEven` iterable as above, but with an assertion that each value
    is non-negative:

    ```@example test_all
    function Base.iterate(x::IsEven, i=1) 
        i > length(x.vals) && return nothing
        @assert x.vals[i] >= 0
        iseven(x.vals[i]), i+1
    end
    x = IsEven([1, 0, -1])
    nothing # hide
    ```

    Evaluating `@test all(x)` will return a [`Test.Fail`](@extref Julia), since the 
    evaluation of `all(x)` short-circuits after the first iteration and returns `false`:

    ```@repl test_all
    @testset JustPrintTestSet begin # hide
    @test all(x)
    end # hide
    ```
    
    Conversely, `@test_all x` will return a [`Test.Error`](@extref Julia) because it
    evaluates all iterations and thus triggers the assertion error on the third iteration:

    ```@repl test_all
    @testset JustPrintTestSet begin # hide
    @test_all x
    end # hide
    ```

### `Missing` values

The only other major difference between `@test all(ex)` and `@test_all ex` is in how they
deal with missing values. Recall that, in the presence of missing values,
[`all()`](@extref Julia Base.all-Tuple{Any}) will return `false` if any non-missing value
is `false`, or `missing` if all non-missing values are `true`.

Within an [`@test`](@extref Julia Test.@test), the former will return a [`Test.Fail`]
(@extref Julia) result, whereas the latter a [`Test.Error`](@extref Julia), pointing out
that the return value was non-Boolean:

```@repl test_all
@testset JustPrintTestSet begin # hide
@test all([1, missing] .== 2) # [false, missing] ===> false
end # hide
@testset JustPrintTestSet begin # hide
@test all([2, missing] .== 2) # [true, missing] ===> missing
end # hide
```

In the respective cases, [`@test_all`](@ref) will show the result of evaluating `all(ex)`
(`false` or `missing`), but always returns a [`Test.Fail`](@extref Julia) result showing individual
elements that were `missing` along with the ones that were `false`:

```@repl test_all
@testset JustPrintTestSet begin # hide
@test_all [1, missing] .== 2
end # hide
@testset JustPrintTestSet begin # hide
@test_all [2, missing] .== 2
end # hide
```

### Non-Boolean values

Finally, the macro will also produce a customized [`Test.Error`](@extref Julia) result
if the evaluated argument contains any non-Boolean, non-missing values. Where `all()`
would short-circuit and throw a [`Core.TypeError`](@extref Julia) on the first non-Boolean
value, [`@test_all`](@ref) identifies the indices of *all* non-Boolean, non-missing
values:

```@repl test_all
@testset JustPrintTestSet begin # hide
@test_all [true, false, 42, "a", missing]
end # hide
```

## `Test` integrations

```@setup integration
using PrettyTests, Test 
PrettyTests.enable_failure_styling()
PrettyTests.set_max_print_failures(10)

mutable struct JustPrintTestSet <: Test.AbstractTestSet
    results::Vector
    JustPrintTestSet(desc) = new([])
end

function Test.record(ts::JustPrintTestSet, t::Test.Result)
    str = sprint(show, t, context=:color=>true)
    str = replace(str, r"Stacktrace:(.|\n)*$" => "Stacktrace: [...]")
    println(str)
    push!(ts.results, t)
    return t
end

Test.finish(ts::JustPrintTestSet) = nothing
```

A core feature of `PrettyTests` is that macros integrate seamlessly with
Julia's standard [unit-testing framework](@extref Julia stdlib/Test). They return
one of the standard [`Test.Result`](@extref Julia) objects defined therein, namely:

- [`Test.Pass`](@extref Julia) if the test expression evaluates to `true`.
- [`Test.Fail`](@extref Julia) if it evaluates to `false` (or `missing` in the case of
  `@test_all`).
- [`Test.Error`](@extref Julia) if the expression cannot be evaluated.
- [`Test.Broken`](@extref Julia) if the test is marked as broken or skipped (see below).


### Broken/skipped tests

They also support `skip` and `broken` keywords, with identical behavior to
[`@test`](@extref Julia Test.@test):

```@repl integration
@testset JustPrintTestSet begin # hide
@test_sets 1 ⊆ 2 skip=true
end #hide
@testset JustPrintTestSet begin # hide
@test_all 1 .== 2 broken=true
end #hide
@testset JustPrintTestSet begin # hide
@test_all 1 .== 1 broken=true
end #hide
```

### Working with test sets

The macros will also [`record`](@extref Julia Test.record) the result in the test set
returned by [`Test.get_testset()`](@extref Julia Test.get_testset). This means that they
will play nicely with testing workflows that use [`@testset`](@extref Julia Test.@testset):

```@repl integration
@testset "MyTestSet" begin
    a = [1, 2]
    @test_all a .== 1:2
    @test_all a .< 1:2 broken=true
    @test_sets a ⊆ 1:2
    @test_sets a == 1:3 skip=true
end;
```
