# Getting Help and Contributing

If an analysis stops or its output is unclear, start with the matching recovery
step below. For a first analysis, use the [learning guide](learning-guide.md)
and [supported model scope](scope.md).

## Find the right recovery step

| What happened? | Where to start | What to retain |
| :--- | :--- | :--- |
| A ratings file will not load, or IDs/categories look wrong | [CSV input and category coding](data-validation.md#import-csv) | The error and column definitions; correct the source coding before fitting. |
| Data validation passes but a person has no ratings on one dimension | [Person-level dimension support](data-validation.md#person-dimension-support) | The item-to-dimension mapping and the affected assignment; passing a general check does not supply the missing ratings. |
| A fit reports numerical warnings or wide intervals | [Three kinds of uncertainty](interpreting-results.md#Separate-three-kinds-of-uncertainty) and [chain diagnostic figures](fitting.md#Chain-diagnostic-figures) | The warning, diagnostics and settings; distinguish incomplete computation from uncertainty in the data. |
| A saved fit or report will not reopen | [Saved-result recovery](api-saved-reporting.md#If-reopening-fails) | The original files, exact error, source and environment; do not bypass integrity checks. |
| Export fails after a fit has been saved | [Report export recovery](api-saved-reporting.md#If-reopening-fails) | The fit cache and partial output; recover the report in a new destination without repeating fitting. |
| An API or example is missing from the installed package | [Version and source identity](registration.md) | The manual version and exact installed source; development revisions can share a version number. |

## [Report a problem](@id report-a-problem)

Search the [repository's GitHub issues](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/issues)
for an existing report. For a new software or documentation problem, include:

1. The operation or documentation page, what you expected, and what happened.
2. The smallest code example and data needed to reproduce it, with column
   meanings, category order, model and prior when relevant.
3. The exact error and relevant diagnostic warnings. State whether failure
   occurred during loading, validation, fitting, reporting or reopening.
4. Julia, operating-system and package versions, the exact source revision or
   supplied source snapshot, and whether that source has local modifications.

This Julia command prints basic version information without fitting or reading
your ratings:

```julia
using BayesianMGMFRM
display((; julia=string(VERSION), operating_system=string(Sys.KERNEL),
    architecture=string(Sys.ARCH), package=string(Base.pkgversion(BayesianMGMFRM))))
```

Keep the original `Project.toml` and `Manifest.toml` for dependency matching.
The short version display does not identify a source revision or the complete
environment. For a saved-result problem, also state its format and whether the
original environment can read it; follow [reproduction instructions](api-saved-reporting.md#saved-result-reproduction).

GitHub issues are public. Use the bundled teaching ratings or a small shareable
example where possible. Do not attach private ratings or native fit caches,
which retain analysis data. Inspect logs and environment files for personal
paths or private locations before sharing them; keep the unmodified originals
locally. You do not need to post a complete study to report a software failure.
For an unclear explanation, identify the page or `?function_name` and the point
where you could not decide what to do.

## Choose checks for the change

Preserve existing model assumptions, parameter constraints and saved-result
contracts when changing implementation. Check the affected behavior, including
failure cases, before expanding to broader tests. Reuse completed evidence only
when the relevant source, environment and settings match. A documentation edit
does not require repeating a simulation or a posterior fit.

| Change | Relevant checks |
| :--- | :--- |
| User documentation or docstrings | Source wording checks, affected Julia help, documentation build and rendered links/content. |
| Likelihood, priors or parameter transforms | Algebra, deterministic density/gradient checks, affected model tests and independent numerical comparison. |
| Summaries or prediction | Defined estimands and conditioning, saved-result checks, numerical uncertainty and unsupported cases. |
| Saving or loading | Round trip, target/environment mismatch rejection and preservation of warnings. |
| Shared numerical dependencies or a release | Affected integration tests and supported environments; selected checks are not a full-suite result. |

In your source checkout, `test/README.md` lists the existing groups and commands.
Ordinary package tests include short fits. Some checks labelled "without fits"
still generate prior draws or run a transition; inspect the selected command's
scope before running it when computation is restricted. Statistical
performance claims need evaluation appropriate to the claim; successful unit
tests or a short fitting example do not establish calibration or model-choice
accuracy.

For version or citation edits, run this focused check from the source checkout:

```sh
julia --startup-file=no scripts/release_metadata.jl
```

It checks that `Project.toml`, the top-level `CITATION.cff` version/date fields
and the latest `NEWS.md` heading agree. An unreleased version has no release
date; a dated release uses the same valid calendar date in the citation and
release notes. The checker reads this repository's plain or quoted, one-line
scalar fields; it is not a general YAML or CFF schema validator. It uses only
Julia standard libraries and performs no fitting or dependency installation.
The existing release-verification gate also runs this check. Passing it does
not establish publication, registry status or a DOI.

## Build the manual

From a repository checkout with Julia and the declared dependencies available:

```sh
julia --project=docs -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd())); Pkg.instantiate()'
julia --project=docs docs/make.jl
julia --project=. scripts/public_language_gate.jl --rendered
```

The first command creates or updates the local documentation environment.
Restore the original project and manifest instead when reproducing an archived
build. The manual uses the explicit page list in `docs/make.jl`; source pages
outside that list are not rendered into the manual. Repository files are still
public when included in a public Git repository.

User-facing pages and Julia help should explain inputs, outputs, supported
operations, assumptions and limitations. Describe unavailable functionality
directly. Keep conversations, task assignments, approval records, changing
work queues and machine-specific working paths out of distributed documents.
Do not remove a scientific limitation merely to simplify wording.

## Reproduce an analysis or historical study

Record the source revision, Julia version, complete dependency environment,
data/category coding, model specification, prior, sampler settings and seed,
and the saved-result identities. Native Julia records require their original
trusted environment. Portable JSON reports retain computed summaries; they
are not posterior draws or refittable models.

Historical research scripts can refer to dated inputs, protocols and saved
results that are not part of the package distribution. Use the exact source
and evidence archive recorded by that study. Current package tests and help
are not substitutes for its protocol, and a script's presence does not mean
all of its study inputs are distributed. In particular, the foundation
assessment/design scripts require their original study documents and results.
Do not regenerate a historical study's source hashes against a newer checkout.

Version pinning and saved-result migration are described in the
[versioning guide](registration.md).
