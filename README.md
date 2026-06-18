# BayesianMGMFRM.jl

BayesianMGMFRM.jl is an early Julia package scaffold for many-facet Rasch
measurement workflows.

The package is under active development. The current public slice focuses on
long-format many-facet rating data, deterministic facet indexing, pre-fit design
validation, and a minimal MFRM specification/design compiler. Bayesian
estimation APIs, generalized discrimination terms, group/DFF effects, and
Multidimensional Generalized Many-Facet Rasch Model (MGMFRM) terms are planned
after this data/spec layer is stable.

## Installation

Until the package is registered:

```julia
using Pkg
Pkg.add(url = "https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl")
```

After General registration:

```julia
using Pkg
Pkg.add("BayesianMGMFRM")
```

## Minimal Example

```julia
using BayesianMGMFRM

ratings = (
    examinee = ["E1", "E1", "E1", "E1", "E2", "E2", "E2", "E2"],
    rater = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
    item = ["I1", "I1", "I2", "I2", "I1", "I1", "I2", "I2"],
    group = ["A", "A", "B", "B", "B", "B", "A", "A"],
    score = [0, 1, 2, 0, 1, 2, 0, 2],
)

data = FacetData(ratings;
    person = :examinee,
    rater = :rater,
    item = :item,
    score = :score,
    group = :group,
)

validation = validate_design(data; bias = [(:rater, :group)])
spec = mfrm_spec(data; thresholds = :partial_credit, validation_report = validation)
design = getdesign(spec)

design.parameter_names
coverage_summary(spec)
coverage_matrix(data; rows = :rater, columns = :person)
rater_overlap(data)
threshold_map_data(design; params = zeros(length(design.parameter_names)))
```

See [`examples/minimal.jl`](examples/minimal.jl) for the same minimal example as
a script.

See [`docs/`](docs/) for the Documenter source pages covering data validation
and the public API.

## Development Status

Current public API:

- `FacetData`: long-format rating data with stable person/rater/item/category
  indexes and optional metadata such as `group`, `task`, `form`, and `occasion`.
- `validate_design`: pre-fit category, connectedness, singleton, and DFF-cell
  checks, item/category support warnings, plus a rank check for the current
  minimal reference-constrained location design.
- `mfrm_spec`: a minimal declarative MFRM specification for rating-scale or
  partial-credit thresholds.
- `getdesign`: an inspectable internal design object with deterministic
  parameter-block ordering. The current minimal design fixes the first rater and
  item levels as references and uses sum-to-zero threshold steps.
- `pointwise_loglikelihood`: pointwise log-likelihood evaluation for the
  minimal identified design, intended for validation and examples rather than
  Bayesian fitting.
- `coverage_summary`, `coverage_matrix`, `rater_overlap`, and
  `threshold_map_data`: fit-independent reporting-data helpers for Quarto
  tables, coverage heat maps, rater-linking plots, and threshold-map
  prototypes.

Planned fitting APIs will use domain-oriented names such as `fit`, `simulate`,
and `posterior_summary` rather than repeatedly prefixing function names with the
package name.

Not yet implemented in the public API:

- Bayesian fitting or posterior summaries.
- Full GMFRM/MGMFRM identification, loading, and prior blocks.
- Generalized discrimination, group/DFF, or MGMFRM terms.
- Automated regeneration of external Stan/BridgeStan fixtures in CI. The scalar
  analytic target already has non-optional Julia known-answer and
  BridgeStan-generated log-density fixtures in `Pkg.test()`. Its rater
  consistency prior convention is fixture-specific: the lognormal density is
  evaluated on constrained transformed `alpha_r` values and is not a general
  fitting API prior declaration.

Current registration checklist:

- Package name: `BayesianMGMFRM`
- Repository name for General: `BayesianMGMFRM.jl`
- License: MIT
- Initial version: `0.1.0`
- Tests: `Pkg.test()` passes locally
- Load check: `import BayesianMGMFRM` passes locally
- General registration is pending until the constrained data/spec API is fully
  documented and backed by non-optional validation fixtures. Stan-faithfulness
  claims are currently limited to the scalar fixture checked in `Pkg.test()`.

## Pre-Registration Gate

Before requesting Julia General registration, run:

```bash
julia --startup-file=no scripts/pre_registration_gate.jl
```

The gate checks clean temporary-environment import, `Pkg.test()`, the minimal
example, Documenter build, Aqua package hygiene, project metadata, `git diff
--check`, and public wording/skipped-test scans. CI runs the same gate in a
lighter mode because test and docs jobs already cover `Pkg.test()` and
Documenter.

Manifest policy: package `Manifest.toml` files are intentionally ignored for
General registration. The local gate develops the package in fresh temporary
environments so ignored local manifests do not affect registration checks.
Reproducibility manifests belong with versioned paper or evidence artifacts
rather than the registered package root.

## License

MIT License. See [`LICENSE`](LICENSE).
