using PrettyTests
using Documenter
using DocumenterInterLinks

DocMeta.setdocmeta!(PrettyTests, :DocTestSetup, :(using PrettyTests); recursive=true)

# makedocs(
#     sitename="PrettyTests.jl",
# )

links = InterLinks(
    "Julia" => "https://docs.julialang.org/en/v1/", 
    "numpy" => "https://numpy.org/doc/stable/"
);

makedocs(;
    modules=[PrettyTests],
    authors="Ted Papalexopoulos",
    sitename="PrettyTests.jl",
    doctest = true,
    checkdocs = :exports,
    format=Documenter.HTML(;
        prettyurls = true,
        canonical="https://tpapalex.github.io/PrettyTests.jl",
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
#     repo="github.com/tpapalex/PrettyTests.jl",
#     devbranch="main",
# )
