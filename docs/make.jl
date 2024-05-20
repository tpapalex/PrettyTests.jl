using TestMacroExtensions
using Documenter
using DocumenterInterLinks

DocMeta.setdocmeta!(TestMacroExtensions, :DocTestSetup, :(using TestMacroExtensions); recursive=true)

# makedocs(
#     sitename="TestMacroExtensions.jl",
# )

links = InterLinks(
    "Julia" => "https://docs.julialang.org/en/v1/", 
    "numpy" => "https://numpy.org/doc/stable/"
);

makedocs(;
    modules=[TestMacroExtensions],
    authors="Ted Papalexopoulos",
    sitename="TestMacroExtensions.jl",
    doctest = true,
    checkdocs = :exports,
    format=Documenter.HTML(;
        prettyurls = true,
        canonical="https://tpapalex.github.io/TestMacroExtensions.jl",
        edit_link="dev",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Reference" => "reference.md",
    ],
    plugins=[
        links
    ]
)

# deploydocs(;
#     repo="github.com/tpapalex/TestMacroExtensions.jl",
#     devbranch="main",
# )
