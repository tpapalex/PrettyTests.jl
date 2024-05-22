using PrettyTests
using Documenter

DocMeta.setdocmeta!(PrettyTests, :DocTestSetup, :(using PrettyTests); recursive=true)

makedocs(;
    modules=[PrettyTests],
    authors="Ted Papalexopoulos",
    sitename="PrettyTests.jl",
    format=Documenter.HTML(;
        canonical="https://tpapalex.github.io/PrettyTests.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/tpapalex/PrettyTests.jl",
    devbranch="main",
)
