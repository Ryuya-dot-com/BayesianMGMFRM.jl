# Selecting checks for a change

Use the smallest existing check that exercises the changed behavior, then expand
only for shared dependencies or an observed failure. A local commit or push does
not itself require another full suite. Reuse completed integration evidence when
the relevant source, tests, environment and entry point are unchanged; state any
documentation, CI or formatting delta explicitly. Never describe selected tests
as a complete suite or old CI as validation of a new commit.

| Change | First check | When to expand |
| --- | --- | --- |
| Internal prose / roadmap | Review links, claims and `git diff --check` | Public wording: `julia --startup-file=no scripts/public_language_gate.jl`; published manual/build changes: documentation build |
| Saved-draw summaries, MCSE, contrasts, response surfaces | `julia --startup-file=no --project=. test/postprocessing.jl` | Renderer changes: `test/response_surface_render.jl`; shared report/cache changes: `fitting_reports` |
| Normalized prior / location map | Relevant standalone density, gradient or prior check below | Public fit/save changes: explicit tiny smoke and `generalized` |
| Sampler / shared likelihood / fit controls | Relevant deterministic regression and tiny fit | Affected fitting groups on supported Julia versions; shared numerical/dependency changes: ordinary integration |
| Python arithmetic / orchestration | Explicit `python3 test/<changed_check>.py -v` | Shared helper changes: its dependent entry points; do not use ambiguous discovery |
| CI / packaging | YAML structure and changed shell command; actual `git archive --format=tar.gz HEAD` size | Runtime/environment/matrix changes: corresponding hosted jobs |

Run one ordinary group through the existing selector, for example:

```sh
BAYESIANMGMFRM_RESEARCH_EVIDENCE_TESTS=false BAYESIANMGMFRM_TEST_GROUP=generalized \
  julia --startup-file=no --compiled-modules=yes --project=. -e 'using Pkg; Pkg.test()'
```

The six groups are `core`, `fitting_core`, `fitting_reports`,
`local_dependence_core`, `local_dependence_integrity` and `generalized`;
`all` remains the default. Full ordinary integration is appropriate for a
substantial combined candidate, shared numerical/dependency changes and release
verification. Avoid repeatedly running it between prose edits or already-covered
commits. The October 2 candidate has completed all six Julia 1.12.6 groups and the
Julia 1.10.8 all run; see the [current evidence and limits](../ROADMAP.md#execution-priorities-after-local-integration).

This is the local selection policy. Hosted CI still runs its existing ordinary
matrix for pull requests and main/master pushes. Changing that routing is separate
work: required check names and skipped-workflow behavior must be checked first.
No elapsed-time cutoff is imposed on ordinary local tests. Monitor progress and
resources; do not reduce draw counts or relax numerical assertions to meet a clock.
Use the normal compiled-module mode (`yes`), not restricted cache modes as a speed
substitute. A no-fit test can still compile substantial Julia code.

## Focused MGMFRM checks without fitting

The deterministic foundation scale/acceptance worksheet has an additional
standalone check (same Python dependencies; no Julia, saved fits or results needed):

```sh
python3 test/mgmfrm_foundation_acceptance_review.py -v
python3 scripts/mgmfrm_foundation_acceptance_review.py /tmp/new-foundation-review.json
```

It checks conditional positive-acceptance count thresholds against exact finite
outcome sums and simultaneous Gaussian prior widths against independent
quadrature. It does not assess existing fits or change the frozen SBC cohort;
see the [interpretation and design table](../docs/internal/mgmfrm-foundation-scale-acceptance.md).

The exact-normal location-pivot classifier has a separate sampler-free check:

```sh
python3 test/mgmfrm_location_oracle_review.py -v
```

It verifies correct, wrong and unresolved probability masses by analytic interval
arithmetic, including diagnostic failures and insufficient ESS. The accompanying
`run_mgmfrm_foundation_oracle.jl` is a separate, explicit one-fit research runner;
it is not called by this test or by the frozen SBC cohort.

The normalized location-coordinate research adapter has a separate Julia check.
With the explicit smoke flag, this command includes four tiny sampler runs
(two chains, warmup 10, retained 12 per chain). Without the flag it checks
only the deterministic density, coordinate map and gradients:

```sh
BAYESIANMGMFRM_NORMALIZED_FIT_SMOKE=true julia --startup-file=no --compiled-modules=yes --project=. test/mgmfrm_normalized_location.jl
```

It checks the full normalized density, unit Jacobian, derivatives, raw-space
initialization and canonical saved-result semantics. These short runs do not
assess mixing improvement or statistical acceptance.

The ordinary `generalized` test group enables this flag for both
`mgmfrm_normalized_fit.jl` (two short raw-coordinate fits) and
`mgmfrm_normalized_location.jl` (four short transformed-coordinate fits).
The postprocessing CI job keeps the flag unset and performs no such fits.

The separate `scripts/run_mgmfrm_normalized_location_comparison.jl` research
runner performs **two full foundation pilot fits**, each with four chains and
1,000 warmup plus 1,000 retained draws per chain. It is explicitly invoked with
an existing foundation input JSON and a new output directory, and does not run
as part of the tests above. Its protocol and interpretation are in the
[foundation record](../docs/internal/mgmfrm-foundation-scale-acceptance.md).

`scripts/mgmfrm_normalized_core_review.jl` and
`scripts/mgmfrm_normalized_core_analysis.py` read existing normalized samples,
verify the original 150-quantity roster and independently check derived values,
quantiles and location pivots. They do not sample. The separate
`scripts/run_mgmfrm_normalized_replication.jl` runs **one full four-chain fit**
on an explicitly supplied independent candidate-C dataset, at 1,000 warmup and
1,000 retained draws per chain, and applies that review. It refuses an existing
output directory and records failures without retrying. These research commands
are not included in ordinary tests or the original raw SBC cohort.

`python3 test/mgmfrm_foundation_replication_budget.py -v` checks the sampler-free
inverse acceptance worksheet, including nonmonotone integer thresholds against
the existing scalar implementation. The corresponding
`scripts/mgmfrm_foundation_replication_budget.py NEW_OUTPUT.json` compares three
margins and five error/unresolved-rate scenarios. It reads the two named local
pilot timing records for cost references and launches no fits; those historical
files are not required by the test. This check is standalone, not added to CI.

`python3 test/mgmfrm_foundation_precision_analysis.py -v` checks all-150
transition accounting and rejects missing, reordered or invalid events.
The standalone `scripts/mgmfrm_foundation_precision_slices.jl NEW_OUTPUT`
reads three named local pilot exports and recomputes four saved windows;
`scripts/mgmfrm_foundation_precision_analysis.py OUTPUT_DIRECTORY` compares
their classifications and exact normal-pivot risks. Both commands are
sampler-free. Neither treats the longest window as truth nor supplies a
complete diagnostic gate for each window. Historical exports are required
by these research commands but not by the standalone Python test.

The normalized-C prediction binding audit is also sampler-free. It uses the
saved B01-R0/R1 inputs and B01-R0-050 full-data fit from a completed foundation
assessment to check training-target isolation, wrong-input rejection, heldout
IDs, log-domain scores and covariance-aware MCSE. It writes a new receipt and
adds no independent evaluation panels:

```sh
julia --startup-file=no --project=. test/mgmfrm_foundation_prediction.jl \
  results/workflows/20261004-foundation-fixed-facet-assessment-01 \
  /tmp/new-foundation-prediction-binding.json
```

The `mgmfrm-core-python` job in [CI](../.github/workflows/CI.yml) runs the
following checks on Ubuntu with Python 3.14. They also run on macOS; the
execution helpers use POSIX process accounting and file locks, so this group
does not cover Windows. From the repository root, install the two Python
dependencies in a separate environment:

```sh
python3.14 -m venv /tmp/bmg-core-checks-venv
/tmp/bmg-core-checks-venv/bin/python -m pip install -r test/requirements-mgmfrm-core.txt
```

Then run the same explicit test group as CI:

```sh
(
  for check in coverage_review classifier_review rank_review item_conditional \
    sbc_review sbc_error_budget sbc_plan sbc_decision sbc_runner sbc_cohort; do
    /tmp/bmg-core-checks-venv/bin/python "test/mgmfrm_core_${check}.py" -v || exit 1
  done
)
```

Run each file through its standalone entry point: tests and implementation
scripts share basenames, so unqualified `unittest` discovery/imports can collide
or load an implementation module without running its tests. The loop stops on
the first failing file and reports the executed test counts.

This group checks coverage arithmetic against rational probabilities,
classification against analytic references, rank boundaries, conditional
density/quadrature, full-roster failure accounting, export identity, lossless
archives, serial batch behavior, and decision safeguards that retain unverified
assumptions even after a complete non-rejecting cohort. Driver calls are mocked in orchestration
tests; synthetic settings, arrays and cache bytes are created in temporary
directories. Julia, CmdStan, a local `Manifest.toml`, saved fits and
`results/workflows` are not required. The synthetic setting is not a study
manifest and must not be used to start scientific runs.

Passing these checks does not establish posterior calibration or independent
scientific acceptance. Replay of historical Julia fits remains a separate,
explicit evidence check (`mgmfrm_core_sbc_worker.jl` and
`mgmfrm_core_sbc_archive.jl`). The full Julia suite and other CI jobs include
fits; this command intentionally selects only the Python checks above.

The same CI job also installs Julia and runs the actual saved-runtime import:

```sh
python test/mgmfrm_core_sbc_runtime.py
```

This separate check needs Julia on `PATH` and an instantiated local project
with `Manifest.toml`, plus the Python dependencies above. It prepares a complete
snapshot, loads its Python and Julia worker, then reproduces an omitted Julia
include whose absence was not detectable by hashes alone. The incomplete
snapshot must fail before any dataset ID is claimed or data are generated.
It runs no sampler and uses no historical workflow results. An optional
`--directory NEW_DIRECTORY` retains its explicitly synthetic records and log
metadata; the expected missing-file exception is part of the passing check.

The `postprocessing` CI job runs the Julia checks below on the minimum supported
version (1.10.8) and current stable Julia. In an instantiated package environment:

```sh
julia --startup-file=no --project=. test/postprocessing.jl
```

This entry point runs the existing matrix-based MCSE checks, numerical inputs
for posterior/diagnostic/predictive/Wright figures, saved-MGMFRM contrasts,
and conditional MGMFRM item response surfaces.
It uses synthetic joint draws and deterministic reporting objects; it neither
estimates a posterior nor requires `results/`, pre-existing fit caches,
CairoMakie or CmdStan. Cache round trips use temporary files. Synthetic objects
with a backend label are not evidence that the backend was executed. The
ordinary fitting tests retain their actual-fit checks; this entry point is
additional fast feedback, not a substitute for fitting or rendering tests.

Response-surface checks compare posterior means and pointwise intervals with
the observation-level probability kernel and a separate three-category formula.
They cover pure/mixed Q, inactive axes, rater selection, actual category levels,
three-dimensional slices, all-category normalization and single-category agreement,
joint-draw averaging, warnings and cache reload.
Run them alone with `julia --project=. test/response_surface.jl`. With CairoMakie
available, `test/response_surface_render.jl` checks editable 3D/heatmap data,
numbered axes, consistent category colors, legends, shared uncertainty scales,
diagnostic captions and PNG/SVG saving; its optional argument is an output
directory. It uses synthetic reporting objects and never fits a posterior.

The same CI job checks MGMFRM estimand invariance without fitting:

```sh
julia --startup-file=no --project=. test/mgmfrm_estimand_invariance.jl
```

It compares all category probabilities under simultaneous location/positive-scale
changes, reconstructs identifiable blocks from complete pure-Q probability
tables, and retains counterexamples for raw item-difference ordering and
constant-ability dimensions. The derivation and its assumptions are in
[the estimand review](../docs/internal/mgmfrm-estimands-identification.md).
These are algebra and implementation checks, not recovery or calibration fits.

The same job runs `julia --startup-file=no --project=. test/mgmfrm_prior_measure.jl`.
It checks normalized prior densities, exact Gaussian means/covariances, numerical
normalization, scale conventions, binary zero-dimensional step blocks, and score
reflection at K=2,3,4,6. Reversing scores reverses response probabilities; the raw
step density need not remain unchanged, while the normalized references do. The
optional CmdStan branch is off by default; the normal job does not compile Stan
or sample a posterior. See [prior choice and scales](../docs/internal/mgmfrm-prior-choice.md).

`test/mgmfrm_normalized_prior_predictive.jl` also runs in this job. It checks
the normalized MGMFRM generator against the actual Gaussian density using
deterministic basis innovations, then checks independent response equations,
prior metadata, score-independence, RNG behavior and existing v1/v2 sample-record
serialization. The saved inputs are explicitly synthetic serialization fixtures,
not posterior or sampler-performance evidence. No MCMC or Stan compilation runs.

`test/mgmfrm_normalized_fit.jl` also runs from `test/postprocessing.jl` and checks the explicit normalized MGMFRM API,
prior prediction, synthetic v1/v2 result adapters, summaries, MCSE, report data
and manual caches. It rejects mismatched targets/artifacts even when optional
hash verification is disabled. This check runs no sampler; synthetic retained
arrays are not posterior evidence. It also covers single-rater/binary and
three-dimensional mixed-Q reporting boundaries.

The fixed, exploratory [prior-response study](../docs/internal/mgmfrm-prior-responses.md)
has a separate reproducible calculation and production check:

```sh
python3 scripts/mgmfrm_prior_response_review.py /tmp/new-mgmfrm-prior-response
julia --startup-file=no --compiled-modules=yes --project=. scripts/check_mgmfrm_prior_response_review.jl /tmp/new-mgmfrm-prior-response
```

Use a new output directory; Python requires NumPy, SciPy and Matplotlib. It draws
joint prior parameters, not outcomes or posterior chains. The Julia check compares
fixed probes against production probabilities/densities and reconstructs the
generator's Gaussian covariance from the production Hessian. This descriptive
study is separate from routine CI and from the frozen raw SBC cohort.

The job also separately runs deterministic conditional-dynamics checks:

```sh
julia --startup-file=no --project=. test/mgmfrm_core_location_section.jl
```

These use the exact Gaussian fitted-person-mean conditional under independent
normal raw priors. They compare mean, orthogonal and whitened coordinates with
the actual model density and the installed AdvancedHMC leapfrog integrator,
using explicit positions and momenta. No random momentum, Markov chain,
adaptation or fit is generated. Pure/mixed Q, nonunit priors, matched metric
transformations, forward/backward integration and deliberately incorrect
controls are covered. The Gaussian section fixes all other coordinates;
passing it does not validate full-dimensional NUTS, its tree/selection rules,
mixing or calibration. This check also runs in the ordinary `generalized`
group, whose other tests can fit models. Historical prior-002 probes remain
separate from this cache-free test.

The same job also runs `test/mgmfrm_core_nuts_stationarity.jl`. This small,
seeded check exercises the independent one-transition probe helper: exact
Gaussian starts, separate input/transition RNG streams, actual full-momentum
refreshment and multinomial generalized NUTS, no chaining, repeatability,
standardization and analytic/embedded density agreement. It runs stochastic
transitions but no model fits or adaptation. Its assertions check mechanics,
not a random significance threshold. The larger declared stationarity study
and historical saved-fit inputs remain outside ordinary CI; passing the
mechanics check is not a calibration or sampler correctness claim.

`test/mgmfrm_core_coupled_geometry.jl` also runs in that CI job and the ordinary
generalized group. It checks the full location-map Jacobian and sampler
gradient, and the mixed-curvature chain rule including the loading-dependent
second derivatives of the map. One-person, mixed-Q, two-/three-dimensional
and nonunit-prior examples include controls that omit the loading coupling,
omit the nonlinear curvature term or incorrectly put independent priors on
item offsets. It uses no RNG, transitions or fits. Saved prior-002 checks
against the historical independent Python analytic score remain separate
from this cache-free regression test.

The contrast checks can also run separately:

```sh
julia --project=. test/saved_mgmfrm_contrasts.jl
```

They check posterior dependence, reversed contrasts, log ratios, ROPE event
counts and unavailable precision at constant/short-chain boundaries. A synthetic
MGMFRM result also checks both named dimensions, the reconstructed last rater,
warning preservation, invalid selectors/chain order and save/reload. These
checks remain included in the ordinary `fitting_reports` group; other tests in
that group may fit models. Replay of historical posterior fits stays separate.

## Adaptation records and saved-record review

`julia --startup-file=no --project=. test/mgmfrm_adaptation_record.jl` runs a
separate engineering check using small, seeded MGMFRM fits. It belongs to the
ordinary `generalized` group, not the fit-free postprocessing job. Paired runs
with and without the recorder compare exact draws, densities, diagnostics,
sampler statistics and subsequent RNG outputs in raw/orthogonal coordinates,
with unit/diagonal/dense metrics and zero/nonzero warmup. Other assertions check
actual chain starts, metric timing and copies, coordinate labels, cache/JSON
reload, refusal to overwrite attempts and failure recording. Each actual
recorded fit is also passed through `MGMFRMAdaptationReview.review`; its chain
windows, retained step sizes and metric update times are checked against the
record, and both cache and record hashes must remain unchanged. Failed attempts
must be rejected by the review. These checks need
no historical results and do not establish calibration or diagnose prior-002.

To retain the actual records and review outputs from all 18 paired conditions,
pass a new directory to the standalone command:

```sh
julia --project=. test/mgmfrm_adaptation_record.jl /tmp/new-adaptation-check
```

An existing directory is refused. Without the argument, or when included by the
ordinary test suite, outputs use a temporary directory. Retained outputs are
engineering fixtures (three persons, eight retained draws per chain), not a
scientific replication cohort. The test runs 36 small fits per Julia environment;
it is not part of the fit-free `postprocessing` job.

`test/cmdstan_adaptation_record.jl` checks native-format parsing and explicitly
missing warmup metrics without fitting or requiring CmdStan. It also checks
partial-file preservation using a deliberately failing POSIX shell executable;
that subprocess fixture is skipped on Windows. It belongs to `generalized`.

`test/mgmfrm_adaptation_review.jl` checks the read-only review of complete saved
adaptation records. It uses deterministic reporting caches and synthetic native
file formats, never a fit or transition. Both backends, three metrics, no-warmup
and warmup cases, transformed coordinates, unavailable versus nonfinite values,
and mismatched records/files are covered. It runs in the `postprocessing` CI job
and the ordinary `generalized` group; no historical result directories or
CmdStan installation are required. These fixtures are not sampler evidence.

`test/cmdstan_adaptation_sampling.jl` requires an installed CmdStan >= 2.34 and
runs six native sampler pairs (three metrics, zero/nonzero warmup) plus an
ordinary/recorded public-fit pair on small synthetic data. A fresh compilation
is hash-checked for the sampler pairs, and the public pair uses separate fresh
build directories. It checks exact retained results, Julia RNG preservation,
chain starts/seeds, metric JSON/CSV agreement and cache linkage. Run it directly
or through `BAYESIANMGMFRM_CMDSTAN_TESTS=true`; it is not in a fit-free job.
An optional directory argument on the standalone command retains its engineering
outputs. Existing result directories are never reused.
