using Pkg

Pkg.activate(@__DIR__)

package_root = normpath(joinpath(@__DIR__, ".."))
Pkg.develop(PackageSpec(path = package_root))
Pkg.instantiate()

include(joinpath(@__DIR__, "make.jl"))
