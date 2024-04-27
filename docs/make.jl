using TestMacroExtensions
using Documenter

DocMeta.setdocmeta!(TestMacroExtensions, :DocTestSetup, :(using TestMacroExtensions); recursive=true)

makedocs(;
    modules=[TestMacroExtensions],
    authors="Ted Papalexopoulos",
    sitename="TestMacroExtensions.jl",
    format=Documenter.HTML(;
        canonical="https://tpapalex.github.io/TestMacroExtensions.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/tpapalex/TestMacroExtensions.jl",
    devbranch="main",
)
