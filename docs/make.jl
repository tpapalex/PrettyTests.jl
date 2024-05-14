using TestMacroExtensions
using Documenter

DocMeta.setdocmeta!(TestMacroExtensions, :DocTestSetup, :(using TestMacroExtensions); recursive=true)

# makedocs(
#     sitename="TestMacroExtensions.jl",
# )
makedocs(;
    modules=[TestMacroExtensions],
    authors="Ted Papalexopoulos",
    sitename="TestMacroExtensions.jl",
    doctest = true,
    format=Documenter.HTML(;
        prettyurls = "true",
        canonical="https://tpapalex.github.io/TestMacroExtensions.jl",
        edit_link="dev",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

# deploydocs(;
#     repo="github.com/tpapalex/TestMacroExtensions.jl",
#     devbranch="main",
# )
