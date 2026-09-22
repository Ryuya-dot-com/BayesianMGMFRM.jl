# Run from the repository root after installing the project dependencies.
include(joinpath(pwd(), "scripts", "synthetic_paired_ratings.jl"))

length(ARGS) <= 1 || error("Usage: julia --project=. examples/synthetic_paired_ratings.jl [new-output-directory]")
directory = isempty(ARGS) ? tempname(mkpath(joinpath("results", "synthetic_paired_ratings"))) : only(ARGS)
panel = SyntheticPairedRatings.write_example(directory)
println("Synthetic paired ratings saved: ", relpath(directory))
println(panel.manifest.persons, " persons, ", panel.manifest.assigned_recordings,
    " recordings, ", panel.manifest.observed_rating_count, " observed ratings; ",
    panel.manifest.missing_rating_count, " missing criterion ratings.")
println("Observed data and generating truth are separate. No model was fitted.")
