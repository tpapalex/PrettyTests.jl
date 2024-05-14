## Set-like comparisons of collections

The [`@test_sets`](@ref) macro can be used when two collections need to be compared
as unordered sets, e.g. to check that they have the same elements, are disjoint, one is
a subset of the other, etc.


## Vectorized tests

The `@test_all`(@ref) macro is most useful when performing a large number of simple/true
false tests.
