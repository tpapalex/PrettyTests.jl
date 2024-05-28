using PrettyTests
using Documenter
using DocumenterInterLinks

DocMeta.setdocmeta!(PrettyTests, :DocTestSetup, :(using PrettyTests; PrettyTests.disable_failure_styling()); recursive=true)

links = InterLinks(
    "Julia" => "https://docs.julialang.org/en/v1/", 
    "numpy" => "https://numpy.org/doc/stable/",
    "python" => "https://docs.python.org/3/"
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

deploydocs(;
    repo="github.com/tpapalex/PrettyTests.jl"
)
