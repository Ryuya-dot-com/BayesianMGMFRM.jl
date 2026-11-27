# Reference-coded examples

These scripts retain the earlier reference-coded models for reproducing old
analyses. They fix reference facet levels and the person distribution origin;
use the standard examples in the parent directory for new unanchored analyses.

- `first_analysis.jl`: the original 72-rating teaching analysis, including
  `--saved-fit` for matching trusted native caches.
- `minimal.jl`: the original short sampler/figure example, including its
  `--cmdstan` and `--plots` options.

Run them from the repository root, for example
`julia --project=. examples/legacy/first_analysis.jl`. Historical `.jls` files
still require their original producing source, Julia version and environment.
Moving these scripts does not migrate a historical cache to the current source.
