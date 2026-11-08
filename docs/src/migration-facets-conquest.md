# Migrating from FACETS and ACER ConQuest

!!! note "Unreleased documentation preview — 13 October 2026"
    This manual includes unreleased interfaces and examples. It is not the
    documentation of an installed release. Model support and scientific
    acceptance remain as stated on each page.

This page maps the smallest genuinely overlapping many-facet models from
FACETS and ACER ConQuest to `BayesianMGMFRM.jl`. It is a semantic migration
guide, not a parser for FACETS specification files or ConQuest command files.
The source likelihood, category structure, sign convention, identification,
weights, anchors, and estimator must be checked before comparing any numbers.

The fit-supported destination on this page is the one-dimensional additive
MFRM with either shared rating-scale steps or item-specific partial-credit
steps. Arbitrary facets, multiple rating-scale groups, observation weights,
fitted interactions, soft anchors, threshold anchors, and group-mean anchors
are not silently approximated by the current stable API. Exact individual
rater/item hard anchors are supported in the minimal MFRM path.

## [At-a-glance comparison with related rating software](@id software-comparison)

Before translating a specification or comparing parameter estimates across
packages, review how each tool handles estimation, uncertainty, design
validation, and model extensions:

| Capability / Workflow Stage | `BayesianMGMFRM.jl` | `FACETS` | `ACER ConQuest` | `R (TAM / mirt)` | `brms / CmdStan` |
| --- | --- | --- | --- | --- | --- |
| **Primary estimation & uncertainty** | Joint Bayesian MCMC (`AdvancedHMC` NUTS or `CmdStan`); simultaneous posterior draws & MCSE for all facets | Joint Maximum Likelihood (JMLE); asymptotic point-estimate SEs | Marginal Maximum Likelihood (MML) & Patz–Junker MCMC; asymptotic or MCMC SEs | MML-EM / quasi-MCEM; asymptotic SEs and plausible values | Joint Bayesian MCMC (HMC/NUTS); simultaneous posterior draws & MCSE |
| **Pre-fit rating connectivity & rank audit** | **Built-in** (`validate_design`, graph connectedness, category-gap & rank checks) | Subset connectivity checks during estimation | Design-matrix rank & aliasing checks during model setup | Manual data preparation or custom matrix checks | Manual data preparation & custom code |
| **Core 1D MFRM (RSM / PCM & hard anchors)** | **Supported** (`mfrm_spec`, `anchors = ...`, `rater = nothing` for 1PL) | **Supported** (comprehensive operational facet & anchor options) | **Supported** (general linear facet & anchor expressions) | **Supported** (via facet design matrices in `TAM::tam.mml.mfr`) | Requires custom formula / Stan program & sum-to-zero constraints |
| **Additional main-effect facets (5+ facets)** | **Experimental** ([User-Named Additive Facets](additive-facets.md)) | **Supported** (arbitrary declared main-effect facets) | **Supported** (arbitrary main-effect facet terms) | **Supported** (via facet formula in `TAM::tam.mml.mfr`) | **Supported** (via additional varying/fixed effects) |
| **Generalized slopes & multidimensional traits (GMFRM / MGMFRM)** | **Experimental** (1D GMFRM, fixed-Q 1D–3D MGMFRM, correlated 2D/3D traits) | 1D Rasch family (fixed unit slopes; diagnostic discrimination indices) | Multidimensional Rasch / 2PL MML (`score` statements) | Multidimensional 2PL / GPCM (`mirt`, `TAM`) | Requires custom non-linear formula or custom Stan program |
| **Multi-criterion rating events & rater-mechanism models** | **Experimental** (`:none` shared-response, `:uniform` paired, `:star` multi-criterion, RW1 drift, criterion collapse, rater group/item) | Bias/interaction tables (`Barcharts`, pairwise bias reports) | Linear interaction terms (`rater*item`, `rater*step`) | Facet interaction terms (`xsi.fixed` / custom design) | Requires writing custom likelihoods & Jacobians in Stan |
| **Prior predictive checks, PSIS-LOO & prior sensitivity** | **Built-in** (`prior_predictive_check`, `predictive_check`, `criteria`, `prior_sensitivity`) | Classic infit/outfit mean-square & standardized residuals | Classic infit/outfit, deviance/AIC, plausible-value checks | Infit/outfit, information criteria (AIC/BIC), item fit | Available via external R packages (`loo`, `priorsense`, `bayesplot`) |
| **Psychometric maps & reproducible portable reports** | **Built-in** (`plot` for Wright, Pathway, 3D surfaces; SHA-256 JSON `save_report`) | Built-in ASCII / GUI Wright maps & score tables | Built-in Wright maps & text/table outputs | Requires external plotting packages (`WrightMap`, `ggplot2`) | Requires custom post-processing & plotting scripts |
| **Glass-Box mathematical inspection** | **Built-in** (`contract`, `facet_basis`, `logposterior`, `logdensity_and_gradient`, `stan_data`) | Output tables & residual files | Design matrices & parameter logs | Exported design matrices & likelihood values | Generated Stan code & unconstrained draw methods |

## Two different comparison questions

**Do two implementations target the same posterior?** Match responses, category
support, likelihood, scale, identification, joint prior and reported quantities.
Changing from a reference level to a sum-zero constraint can also shift abilities
and induce prior dependence. Reassigning independent priors with the same SD is
not generally the same distribution. Compare whole-fit and focal numerical
precision before interpreting differences. A limited common binary-Rasch check
does not validate the public PCM prior or an additional rater mechanism.

**Which analysis helps explain these ratings?** Competing models and estimators
need not have identical priors, but their differences must be explicit. Keep the
observations, categories and evaluation question comparable, choose suitable
predictive or descriptive quantities and retain uncertainty and failures.
ConQuest MML standard errors, Bayesian posterior intervals and Monte Carlo error
have different meanings; unmatched fit statistics are not interchangeable.
An unresolved exact-prior MCMC mapping does not prevent this separate question.

For halo-related questions, ConQuest documents rater severity, rater-by-criterion
effects and rater/criterion-specific steps in its
[rater tutorial](https://conquestmanual.acer.org/s2-00.html#the-analysis-of-rater-effects).
These models can investigate relevant rating patterns with appropriate checks;
their coefficients do not by themselves identify a psychological halo or horns
mechanism. The package's [criterion-collapse model](criterion-collapse.md)
represents one specific loss of criterion discrimination. It does not estimate
signed positive/negative general-impression effects. The same shared-class
likelihood and joint prior have not been verified in native ConQuest. Neither
that uncertainty nor the package implementation establishes exclusive capability.

## [When fitted category counts agree by construction](@id fitted-category-counts)

Suppose some judges use the middle score much more often than others. A model
with only rater severity may leave this pattern unexplained. Adding a
rater-specific category effect can reproduce it, but a fitted match is not
independent evidence that the model has identified its cause.

A bounded ConQuest 5.47.5 comparison used two existing simulated datasets, each
with 12 persons, four raters, three criteria, scores 0–2 and 144 ratings. The
baseline was `rater + criteria + criteria*step`; the alternative added
`rater*step`. The alternative's initial design had thirteen columns of rank
twelve. Fixing the final rater's category-1 interaction to zero removed this
redundancy without changing the response family. Both models used normal-person
MML with mean zero and estimated variance. These directly written native
controls are separate from the minimal additive bridge described below.

Let `Nr` count rater r's middle-category ratings and define
`D=(N3+N4)-(N1+N2)`. Each rater contributes 36 ratings.

| Fixed input | Observed D | Baseline expected D | Category-use expected D | AIC(category-use − baseline) |
| --- | ---: | ---: | ---: | ---: |
| Ordinary ratings | 0 | 1.88 | approximately 0 | +3.17 |
| Middle-category preference | 15 | 2.61 | approximately 15 | -0.56 |

All four cells met independent likelihood, gradient, curvature and integration
criteria. Native reports stopped by deviance convergence; a false stored
convergence flag was retained rather than represented as an all-flags pass.
The two inputs share their original simulation uniforms and are not independent
replications. The alternative matches the counts, but its small AIC advantage
on the second input does not decisively favor that explanation. With twelve
persons, asymptotic model-selection claims are especially limited; the usual
AICc formula is not applicable when its `n > k+1` condition fails.

### Why the match occurs

Write an additive log-weight contribution as
``\gamma_r\mathbf{1}\{k=1\}`` for rater r. Let ``\psi`` include this coefficient
and the other global parameters. Define
``N_r=\sum_{(p,i)\in\mathcal O_r}\mathbf{1}\{y_{pir}=1\}``, with
``\mathcal O_r`` the observed person/criterion pairs for that rater. For the
unpenalized marginal log likelihood ``\ell(\psi)`` and a latent-person density
that does not itself depend on ``\gamma_r``, differentiation gives

```math
\frac{\partial\ell(\psi)}{\partial\gamma_r}
=N_r-\sum_{(p,i)\in\mathcal O_r}
  \mathbb E_{\theta\mid y,\psi}
  \left[P(Y_{pir}=1\mid\theta,\psi)\right].
```

At an interior maximum, a free coefficient's score is zero: its observed count
equals its conditional fitted expectation. Under identification constraints the
corresponding free contrasts must be used. In this example, the rater-category
and criterion-category score equations together cover all four rater counts,
so their contrast D also matches. The identity follows by differentiating the
[ConQuest multinomial-logit kernel](https://conquestmanual.acer.org/s3-00.html#the-item-response-model)
and its marginal likelihood; it is not a new detection method. Boundary
solutions, insufficient rank, penalties and priors change the conclusion.
In particular, this equality is not promised for Bayesian posterior means.

### What to report and check

State that the added effects reproduce the fitted category counts. Do not call
that match a successful independent check of centrality, halo/horns or fairness.
Choose further discrepancies for the substantive question, such as variation
across performances or dependence among criteria; first check whether those
summaries are also determined by the estimating equations. If the claim concerns
future ratings, evaluate genuinely unused observations at the relevant person,
rater or response level, preserving shared effects. These are requirements for
stronger claims, not automatic instructions to expand every descriptive analysis.

Also specify what uncertainty was integrated. The native calculations above fix
global MML estimates and integrate each existing person's ability conditional on
their ratings, along with replicated-response variation. They omit uncertainty
in fitted item/rater/population parameters. Saved Julia ordinary-model predictions
integrate joint posterior uncertainty under finite-panel priors and also leave
the middle-category discrepancy. Their predictive tails cannot be ranked as
though the two calculations used the same uncertainty treatment. MML standard
errors, posterior intervals and MCSE are distinct; an expected-value interval
does not include all replicated-count variation.

Low criterion-collapse class support does not establish adequate ordinary-model
fit. Conversely, a near-central predictive tail for a fitted count is not a
certificate of adequacy. The [Stan predictive-check guide](https://mc-stan.org/docs/stan-users-guide/posterior-predictive-checks.html#which-statistics-to-test)
illustrates why a fitted mean can be reproduced while another relevant feature
is wrong. See [interpreting results](interpreting-results.md#rater-decision-evidence)
for separating numerical precision, fit, model comparison and practical decisions.
The four-cell comparison does not establish exact native support for the shared
criterion-collapse mixture, general classification accuracy or a speed ranking.

## Source features worth preserving

The migration design follows several useful conventions documented by the two
source programs:

- FACETS separates the facet selectors, response-scale definition, and model
  weight in `Models=`. A `#` selector gives each matched element its own
  partial-credit scale, while named scales can be assigned to selected
  observations. The official [FACETS model help](https://www.winsteps.com/facetman64/models.htm)
  also warns that weights are external value judgments rather than parameters
  learned from the response data.
- FACETS distinguishes starting values, individually fixed element anchors,
  and group-mean anchors. Group members may vary relative to one another while
  their mean remains fixed; see the official
  [element and group-anchor help](https://www.winsteps.com/facetman64/elements.htm).
  Rating-scale thresholds can also be fixed for equating across analyses; see
  [anchoring rating-scale structures](https://www.winsteps.com/facetman64/anchoringscales.htm).
- FACETS supports model-, element-, and observation-level weights, multiplying
  them and treating the result as response replication. This changes the
  estimating target and the apparent amount of information; see
  [weighting the data](https://www.winsteps.com/facetman/weighting.htm).
- FACETS bias/interaction output is a secondary analysis: main-analysis
  estimates are fixed and interaction sizes are then estimated from residuals.
  This is not the same target as jointly estimating an interaction in the main
  likelihood; see the official
  [bias-estimation description](https://www.winsteps.com/facetman64/table9.htm).
- ConQuest turns additive terms and their interactions into a design matrix and
  a score matrix. It can also import an arbitrary design matrix. The construction
  rules and multifaceted example are described in
  [ConQuest Manual, Chapter 3](https://conquestmanual.acer.org/s3-00.html),
  Section 3.1.7.
- ConQuest's `model` grammar makes the threshold regime explicit:
  `item + step` is a rating-scale model, while `item + item*step` is a
  partial-credit model. Terms such as `rater*step`, `criteria*step`, and
  `rater*criteria*step` define different scale-sharing structures. See
  [ConQuest Manual, Chapter 4](https://conquestmanual.acer.org/s4-00.html),
  Section 4.7.43.
- ConQuest separates initial values from fixed anchors and can export estimates
  in a form that can be read back as initial values or anchors. See Chapter 4,
  Section 4.7.33, and the multifaceted example in
  [ConQuest Manual, Chapter 2](https://conquestmanual.acer.org/s2-00.html).

These are design principles for transparent compilation and interchange. They
do not imply that `BayesianMGMFRM.jl` should reproduce either product's entire
model catalog or estimation engine.

## Identify the overlapping model first

Only migrate directly when the source model reduces to one of these targets:

| Source intent | Representative source specification | Destination |
| --- | --- | --- |
| One common category-step structure | FACETS `Models = ?, ?, ?, R2`; ConQuest `model rater + item + step;` | `thresholds = :rating_scale` |
| Item-specific category-step structures | FACETS uses `#` for the item facet; ConQuest `model rater + item + item*step;` | `thresholds = :partial_credit` |

The FACETS example assumes three ordered facets in the data record, such as
person, rater, and item, followed by a response with categories `0:2`. FACETS
can reverse the direction of a facet or alter the reported scale. ConQuest
uses a plus sign for a difficulty-oriented term and a minus sign for an
easiness-oriented term. Record the actual source setting rather than inferring
orientation from a column name.

The current destination model uses

```math
\eta_{prik}=(k-1)(\theta_p-\rho_r-\beta_i)
             -\sum_{m=1}^{k-1}\delta_{im},
```

with `delta[m]` shared across items for `:rating_scale`. Positive
`rater` values mean greater severity and positive `item` values mean greater
difficulty, so both reduce the probability of a higher score. Transform
source estimates to this convention before comparing them.

## Executable minimal migration

First convert the source data to one row per observed rating. Preserve source
labels rather than replacing them with source-software parameter numbers.

```julia
using BayesianMGMFRM
using Statistics

ratings = (
    person = repeat(["E1", "E2", "E3"], inner = 4),
    rater = repeat(["R1", "R2", "R1", "R2"], outer = 3),
    item = repeat(["I1", "I1", "I2", "I2"], outer = 3),
    score = repeat([0, 1, 2], inner = 4),
)

data = FacetData(ratings;
    person = :person,
    rater = :rater,
    item = :item,
    score = :score,
)

validation = validate_design(data)
@assert validation.passed

# Choose :rating_scale for FACETS R / ConQuest + step, or
# :partial_credit for item-specific FACETS # / ConQuest item*step.
threshold_regime = :rating_scale
spec = mfrm_spec(data;
    thresholds = threshold_regime,
    validation_report = validation,
)
design = getdesign(spec)

# Inspect the constraints and record the model before sampling.
constraint_rows = constraint_table(design)
manifest = model_manifest(design; view = :public)

fit_result = fit(design;
    backend = :advancedhmc,
    ndraws = 500,
    warmup = 500,
    chains = 4,
    seed = 20260721,
)

posterior_rows = posterior_summary(fit_result)
rater_rows = rater_diagnostics(fit_result)
bayesian_fit_rows = fit_stats(fit_result; by = :rater)

# This separately labelled table is a posterior-mean plug-in approximation,
# not a claim of equality to FACETS JMLE output.
facets_labelled_rows = facets_report(fit_result; by = :rater)

posterior_mean = vec(mean(fit_result.draws; dims = 1))
threshold_rows = threshold_map_data(design; params = posterior_mean)
```

For a substantive analysis, increase sampling effort as needed, predeclare
sampler controls, and inspect [`sampler_diagnostics`](@ref),
[`mcmc_diagnostics`](@ref), [`parameter_block_diagnostics`](@ref), posterior
predictive checks, calibration, and sensitivity results. The numerical settings
above demonstrate the migration path; they are not universal production
defaults.

Run the rating-scale and partial-credit specifications as separate models. Do
not select the regime after inspecting which produces the preferred result.
If a FACETS or ConQuest analysis uses multiple named scale groups or a
`rater*step`/`rater*item*step` structure, it is outside this direct migration
example.

## Offline bridge for a licensed execution host

The machine that prepares an analysis does not need either external
executable. The package compiles a manual-syntax transfer bundle locally, while
execution remains a separate operator action on an authorized host. FACETS
bundles include a Windows launcher. ConQuest bundles include Windows and macOS
launchers. Neither product executable nor its licence is copied into a bundle.

Version 1 deliberately compiles only the fit-supported, one-dimensional,
additive `family = :mfrm` overlap with unit weights and either one shared RSM
step structure or item-specific PCM steps. It rejects generalized
discrimination, fitted bias or interaction terms, nonpassing design
validation, and nonempty parameter anchors. The ConQuest compiler also rejects
repeated person--item--rater cells, any observed rater--item generalized item
that does not contain both declared category endpoints, and an unobserved PCM
category between an item's minimum and maximum scores. FACETS requires both
declared endpoints in the data as a whole for RSM and PCM; PCM additionally
requires both endpoints within every item. These category-universe guards
prevent an external program from silently fitting a narrower response
denominator. Sparse observed designs remain sparse: the bridge does not create
missing rating rows, so a sparse design that cannot meet these guards is
rejected rather than padded with synthetic responses.

On the Mac, compile and save one bundle. Retain the returned `bundle_id`
separately so the returned directory can be checked against the exact original
manifest contract, including its input inventory and required-output list:

```julia
facets_bundle = facets_bridge_bundle(spec;
    title = "Minimal RSM FACETS bridge",
)
facets_saved = save_external_bridge_bundle(
    "facets_minimal_rsm_bridge",
    facets_bundle,
)
facets_bundle_id = facets_saved.bundle_id
facets_host_preflight = facets_saved.host_preflight

conquest_bundle = conquest_bridge_bundle(spec;
    title = "Minimal RSM ConQuest bridge",
)
conquest_saved = save_external_bridge_bundle(
    "conquest_minimal_rsm_bridge",
    conquest_bundle,
)
conquest_bundle_id = conquest_saved.bundle_id
conquest_host_preflight = conquest_saved.host_preflight
```

Each directory contains the control and rating files, ASCII-safe transfer
identifiers, category and observation maps, a SHA-256 manifest, a PowerShell
input verifier, a Windows runner, and a declaration of the required return
files. A ConQuest directory additionally contains `verify_bundle_macos.sh` and
`run_conquest_macos.sh`. Original person, rater, and item labels are omitted
from `id_map.tsv` by
default, although unsalted deterministic SHA-256 hashes of their canonical
representations are retained. This is pseudonymization, not anonymization:
guessable labels can be dictionary matched, and equal canonical labels can be
linked across bundles. Setting `include_original_labels = true` is an explicit
disclosure choice. Row-level ratings are present in every bundle and remain
sensitive even when labels are omitted.

On an authorized Windows host, set `FACETS_EXE` or `CONQUEST_EXE` to the full
path of the corresponding console executable. Also set `BRIDGE_BUNDLE_ID` to
the `bundle_id` retained separately on the Mac; do not recover it from a
possibly modified transfer manifest. Before running either transferred script,
use a trusted host-side hash tool to compare the verifier and runner against the
SHA-256 values retained from `host_preflight` through a separate channel. A
launcher contained in the same transfer is not its own trust anchor; without
this independent comparison it detects accidental corruption but does not
protect against hostile replacement. In a fresh bundle copy whose `results/`
directory is absent or empty, run `run_facets_windows.cmd` or
`run_conquest_windows.cmd`. The checked launcher verifies the manifest ledger,
rebuilds the complete manifest identity, compares the separately supplied
bundle ID, checks every input-file hash and byte length, and refuses stale
results before starting the external process. It then writes the console log
and exit code under `results/`. The bundle ID is an out-of-band integrity
reference, not a secret or a digital signature.

For example, a FACETS host can run:

```bat
set "FACETS_EXE=<full path to licensed Facets executable>"
set "BRIDGE_BUNDLE_ID=sha256:<Mac-side retained 64-hex digest>"
run_facets_windows.cmd
```

For ConQuest on Windows, use `CONQUEST_EXE` and
`run_conquest_windows.cmd` in the same sequence.

On macOS, first compare the two script digests against
`conquest_host_preflight.macos_verifier.sha256` and
`conquest_host_preflight.macos_runner.sha256` retained outside the transfer.
Then run a fresh bundle copy from a normal Terminal session:

```bash
cd conquest_minimal_rsm_bridge
export CONQUEST_EXE='/Applications/ConQuest/ConQuest'
export BRIDGE_BUNDLE_ID='sha256:<retained 64-hex bundle digest>'
/bin/sh run_conquest_macos.sh
```

The macOS runner neither removes quarantine attributes, re-signs the
executable, nor disables Gatekeeper. If macOS blocks the product, resolve access
for the exact ACER executable through the normal Privacy & Security workflow.
Some ConQuest builds also write product state outside the bundle; a restrictive
sandbox can therefore fail before command processing even when the bridge is
valid. Use a normal user Terminal rather than weakening system-wide security.

On either platform, separately record the product-reported software version,
SHA-256 of the exact executable, and UTC execution time. Keep these three
values outside the returned directory: adding an operator note under
`results/` violates the declared-output contract, and adding an undeclared root
file is also rejected. Return the whole directory without editing its inputs.

The receipt accepts a lowercase 64-hex executable digest and an execution time
in the exact `YYYY-MM-DDTHH:mm:ssZ` form (without fractional seconds). From
Command Prompt, these Windows PowerShell commands produce the accepted forms;
copy their outputs to the separate operator record rather than redirecting them
into the bundle:

```bat
powershell -NoProfile -Command "(Get-FileHash -LiteralPath $env:FACETS_EXE -Algorithm SHA256).Hash.ToLowerInvariant()"
powershell -NoProfile -Command "[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')"
```

For ConQuest, replace `FACETS_EXE` with `CONQUEST_EXE`. Record the
product-reported version separately. The generated scripts use syntax intended
for Windows PowerShell 5.1, but successful execution on that path must still be
established on the actual Windows host. On macOS, the equivalent values can be
recorded outside the bundle with:

```bash
/usr/bin/shasum -a 256 "$CONQUEST_EXE"
/bin/date -u '+%Y-%m-%dT%H:%M:%SZ'
```

Script generation is never treated as execution evidence.

Back on the Mac, first recheck the input bundle and then bind all declared raw
return files to a receipt. The example reads the three separately recorded
operator values from Mac environment variables so a placeholder version,
digest, or timestamp cannot be mistaken for evidence:

```julia
validate_external_bridge_bundle(
    "facets_minimal_rsm_bridge";
    expected_bundle_id = facets_bundle_id,
)

facets_receipt = external_bridge_result_receipt(
    "facets_minimal_rsm_bridge";
    expected_bundle_id = facets_bundle_id,
    software_version = ENV["FACETS_REPORTED_VERSION"],
    executable_sha256 = ENV["FACETS_EXE_SHA256"],
    executed_at_utc = ENV["FACETS_EXECUTED_AT_UTC"],
)
```

Use the same sequence for ConQuest. Its parameter export can then be read with
[`load_conquest_parameter_export`](@ref), preferably with the parameter-file
hash from the receipt. The parser accepts a decimal parameter number/value pair
and the optional single trailing `/* ... */` comment emitted by ConQuest 5.47.5.
It returns the trimmed comment as `source_comment`, but deliberately leaves
`semantic_parameter_identity_resolved = false`: a comment is source evidence,
not yet a version-independent item/rater/step adapter. The reader streams the
source, rejects non-decimal or malformed rows and logical lines longer than
4096 bytes, and caps an export at 1,000,000 parameter pairs.

ConQuest 5.47.5 can create a zero-byte `conquest_labels.txt` when the generated
bridge identifiers already appear in the model. The file remains required and
hash-bound by the receipt; only its content is allowed to be empty. Semantic
reconstruction should use the commented parameter export together with the
returned design matrix, not assume that a nonempty labels export exists. The
`gamma` column in the threshold export is a generalized rater--item threshold,
not the source step-parameter vector.

For the exact ConQuest 5.47.5, three-category RSM/PCM overlap, the complete
returned bundle can instead be passed through the public semantic layer:

```julia
conquest_semantic = load_conquest_semantic_parameters(
    "conquest_minimal_rsm_bridge",
    spec;
    expected_bundle_id = conquest_bundle_id,
    software_version = ENV["CONQUEST_REPORTED_VERSION"],
    executable_sha256 = ENV["CONQUEST_EXE_SHA256"],
    executed_at_utc = ENV["CONQUEST_EXECUTED_AT_UTC"],
)

@assert conquest_semantic.semantic_parameter_identity_resolved
@assert conquest_semantic.source_gauge_validated
@assert !conquest_semantic.destination_gauge_aligned
@assert !conquest_semantic.numerical_comparison_allowed
```

This is intentionally not a path-only interpretation of the raw parameter
file. The function revalidates the complete bundle, constructs a receipt from
the current returned-file snapshot, and requires the
hash-bound control, ratings, identifier map, category map, and observation map
to match `spec`, requires parameter numbers and comments to match the design-
matrix columns in their exact order, and verifies every generalized-item by
category design coefficient. It then reconstructs the final rater and item,
and the final common or item-specific step, as the negative sum of that block's
free values. The source orientation is retained directly: positive rater
values mean greater severity, positive item values mean greater difficulty,
and step values are subtractive transitions. No global sign reversal is used.

The result remains in ConQuest's term-wise sum-to-zero source gauge. It does
not create package parameters, anchors, or a numerical agreement claim, and it
does not turn receipt completion into convergence evidence. Versions other
than 5.47.5 and category counts other than three fail closed until matching
execution fixtures and structural tests are added.

### Align point estimates to the Julia reference gauge

For the same validated, unanchored three-category bundle, use the qualified
[`BayesianMGMFRM.load_conquest_reference_parameters`](@ref) loader:

```julia
aligned = BayesianMGMFRM.load_conquest_reference_parameters(
    "conquest_minimal_rsm_bridge", spec;
    expected_bundle_id = conquest_bundle_id,
    software_version = ENV["CONQUEST_REPORTED_VERSION"],
    executable_sha256 = ENV["CONQUEST_EXE_SHA256"],
    executed_at_utc = ENV["CONQUEST_EXECUTED_AT_UTC"],
)
aligned.parameter_rows  # aligned point values with source/reference values
aligned.source          # original semantic record, constraints and provenance
@assert aligned.destination_gauge_aligned
@assert !aligned.numerical_comparison_allowed
# For a source-scale ability theta_source, use:
# theta_julia = theta_source + aligned.ability_shift
```

Let the ConQuest source item difficulty and rater severity be $b_i$ and $r_j$.
With their first levels as references, the destination coordinates are

```math
b_i^{J}=b_i-b_1,\quad r_j^{J}=r_j-r_1,\quad
\theta^{J}=\theta-b_1-r_1,\quad \tau^{J}_{ik}=\tau_{ik}.
```

The same step identity holds for shared rating-scale steps. Therefore
$\theta^{J}-b_i^{J}-r_j^{J}-\tau^{J}_{ik}
=\theta-b_i-r_j-\tau_{ik}$: every adjacent-category log odds, normalized
category probability and conditional expected score agrees at the translated
ability. **Using the same numerical ability on both scales is incorrect.**
For the retained RSM point estimates the ability shift is +1.11884 logits;
for the PCM estimates it is +0.93482 logits. The first levels follow `spec`'s
validated level order. The loader neither selects a different reference nor
imports person estimates. It returns coordinate rows, not a `fit` object or a
complete fitting parameter vector.

Point-coordinate alignment is narrower than matching inference. A source
population with mean zero would have a destination mean equal to the ability
shift at these fixed estimates. A Bayesian transformation would also have to
transform the **joint** parameter/population prior and its density measure.
For the full free-coordinate change from last-derived sum-zero rater/item
blocks to first-fixed blocks (with person translation), the absolute forward
Jacobian determinant is the number of raters times the number of items, not
one. This observation does not specify or validate ConQuest's Bayesian prior.
No prior transformation is performed by this loader.

Likewise, the variance of a difference is
$\operatorname{Var}(b_i-b_1)=\operatorname{Var}(b_i)+
\operatorname{Var}(b_1)-2\operatorname{Cov}(b_i,b_1)$.
Marginal standard errors alone do not provide that covariance. The output
therefore supplies no transformed standard errors, intervals or posterior
draws. Original source provenance and limitations remain under `aligned.source`.
The saved 5.47.5 fixtures are MML runs using Gaussian integration, not MCMC.
Their retained parameter/design-matrix bytes support fixed-point arithmetic
checks; artificial complete bundles test loading. The original executed rating
rows and full returns are not reconstructed by those tests. Matched-data,
matched-estimand comparisons and convergence/uncertainty checks are separate.

### What a returned bundle establishes

A valid receipt establishes input continuity, a zero recorded process exit,
the presence and byte-exact hashes of the declared files, no undeclared root or
result entries, and the absence of a small set of recognized fatal markers. It
records operator-reported completion but does **not** independently establish
that the executable ran, authenticate it, establish convergence, resolve
parameter labels, align gauges, demonstrate numerical agreement, or establish
product equivalence. The bridge therefore does not turn a reported external
run into validation evidence by itself.

The current bridge accepts unanchored specifications only. The ConQuest
semantic adapter reconstructs the supported source gauge. The qualified
reference loader additionally aligns point coordinates; neither loader creates
anchors or transfers uncertainty. [`anchor_refit_plan`](@ref) checks
destination declarations separately and runs neither an external calibration
nor a package refit. A supported numerical declaration can be passed to
`fit`, as shown below.

## Comparing fit and decisions

Match a common model to check implementation. Select an analysis for its
measurement question, assumptions and decision consequences; ConQuest is not a
truth criterion, and this package's defaults are not automatically preferable.
ConQuest also offers MCMC, so this is not simply a choice between frequentist
and Bayesian software.

For the same target, a change of coordinates must transport the full prior,
abilities, anchors and relevant cut scores. The same category probabilities,
paired contrasts and observation-based fit statistic should then agree within
numerical precision. Raw locations need not agree. With a changed prior or
estimator, a different result is possible without a computational defect.
The [route-specific prior conventions](model-equations.md#Fixed-coefficient-routes-and-their-priors)
explain why scalar reference-zero priors can treat contrasts unequally.

Inspect `spec` before fitting and `report.fixed_coordinates.warning_rows`
afterward. The scalar default uses stored label order rather than input row
order; changing IDs can change the reference. Its independent free-coordinate
priors do not automatically transform with that change. Existing saved draws
can be re-expressed jointly without another fit, but they then belong to the
transported prior. Do not call them samples from freshly assigned independent
priors, or pair independently sorted parameter columns.

| Question | Suitable comparison and interpretation |
| --- | --- |
| Reproduce a legacy calibration | Preserve the actual estimator, anchors, weights and report definitions; reproducibility does not establish model adequacy. |
| Estimate population distributions | Check the population model. A fixed ability-prior SD in the minimal Julia fit is not an estimated population SD. |
| Judge differences or adjusted performance | Compare named joint contrasts or predictions for the same panel, with numerical precision and sensitivity to defensible priors. A reference is not an external calibration. |
| Predict future ratings | Specify whether the target is a new rating of known levels or an unobserved person/rater; use the matching held-out unit. |
| Select software for efficiency | Compare the full path to the required accuracy on the selected target, including diagnostics and save/reload; unlike MML/MCMC runtimes do not establish an engine ranking. |

The [ConQuest technical manual](https://conquestmanual.acer.org/s3-00.html#fit-testing)
describes MML parameter-level fit using design-column sufficient statistics and
integration over conditional person posteriors. The scalar `fit_stats` here
summarizes observation-score infit/outfit over joint posterior draws by facet
level. `facets_report` is a separate approximate plug-in calculation. Match
the statistic, aggregation, conditioning and uncertainty before comparing
numbers or transferring a cutoff. A narrower interval or lower training
deviance alone does not establish the better analysis; marginal deviance,
conditional deviance and WAIC/LOO are not interchangeable.

Define the actual action and practically important difference before choosing
a probability threshold. Check numerical precision, relevant misfit and whether
reasonable assumptions change the decision. If they do, report the sensitivity
and the information needed to resolve it. Increasing MCMC length addresses
computational error; it does not resolve prior ambiguity or missing links.
The current evidence does not establish scenario-specific false-flag rates or
a universally preferred prior/software choice. Existing experimental symmetric
prior routes have their own support and validation boundaries.

## Parameter and output crosswalk

| Source concept | `BayesianMGMFRM.jl` surface | Interpretation boundary |
| --- | --- | --- |
| Person ability/location | `posterior_summary`, `wright_map_data` | A posterior distribution, not a FACETS JMLE measure or ConQuest MLE/WLE/EAP. |
| Rater severity/harshness | `posterior_summary`, `rater_diagnostics` | Positive destination values lower expected scores. Confirm source direction first. |
| Item/criterion difficulty | `posterior_summary`, `wright_map_data` | Positive destination values lower expected scores. Re-express source constraints before comparing. |
| Rating-scale or PCM steps | `threshold_map_data` | Uses the package's sum-to-zero step convention; compare reconstructed steps, not raw free coordinates. |
| Fair average | `fair_average_summary` | Posterior balanced-reference expected score; document the reference grid. |
| Infit/outfit with uncertainty | `fit_stats` | Default Bayesian posterior diagnostic. |
| FACETS-labelled MnSq/df/ZSTD | `facets_report` | Unit-weighted posterior-mean plug-in approximation; posterior uncertainty is not propagated and FACETS numerical equality is not claimed. |
| Separation/reliability | `separation_reliability_summary` (legacy); `BayesianMGMFRM.posterior_reliability` (explicit cohort) | The legacy screen warns and must not supply reportable Strata. The new posterior variance ratio has an explicit finite-cohort target; it is not FACETS separation or population/design reliability. |
| Common-response score agreement | `BayesianMGMFRM.rater_agreement` | Observed exact/adjacent rates and joint-posterior model expectations use original categories and explicit response/item matching. No recentering at each rater's lowest PCM category, predictive interval or FACETS numerical identity is claimed. See the [agreement guide](interpreting-results.md#Agreement-and-practical-decisions). |
| Machine-readable report | `fit_report(fit_result; view = :public)` | Hashable package report; it is not a FACETS Scorefile or ConQuest export parser. |

FACETS can write measure tables for transfer to SPSS, Excel, R, and text files;
the available fields include measure, standard error, fit, group, weight, and
status. See the official
[score-and-measure output description](https://www.winsteps.com/facetman64/scorefileoutput.htm).
Migration code should preserve the original labels and status fields alongside
the package rows instead of joining only by row order.

## Important non-equivalences

| Axis | FACETS | ACER ConQuest | Current destination |
| --- | --- | --- | --- |
| Estimator | Primarily JMLE/UCON, with a specialized PMLE path | Marginal maximum likelihood using EM and numerical integration by default; JML and other methods are selectable | Bayesian joint posterior with explicit priors, sampled by the selected package backend |
| Person treatment | Person is another measured facet | Person/case ability is latent under MML, or jointly estimated under JML | One parameter per observed person with a proper prior in the minimal model |
| Identification | Centering, non-centering, individual anchors, group anchors, and user scaling are configurable | Constraints follow the generated/imported design; fixed parameter, covariance, regression, score, or case anchors are available | First rater/item fixed to zero by default; exact individual rater/item hard anchors replace that block gauge; threshold steps sum to zero |
| Threshold sharing | Common, element-specific, or named scale structures | Controlled by `step` interactions | One common RSM structure or item-specific PCM structures per fit |
| Weights | Model, element, and observation weights multiply as replications | `caseweight` changes item-response-model estimation | Unit-weighted likelihood only; weighted source analyses are not an exact overlap |
| Interactions | Secondary residual-based bias analysis is available | Interactions can be columns of the main design matrix | DFF/bias output is screening-only; fitted interaction effects are not supported in the stable minimal fit |
| Facet breadth | Many arbitrary facets and response formats | Generalized items, additive/interacted terms, and imported design matrices | The fitted minimal model has person, rater, and item facets; optional fields are metadata unless explicitly documented otherwise |
| Uncertainty | Frequentist standard errors and fit summaries | Asymptotic errors, latent estimates, or plausible values depend on method | Posterior intervals and posterior predictive uncertainty |

FACETS documents the JMLE/PMLE behavior and its finite-sample considerations in
[Estimation considerations](https://www.winsteps.com/facetman64/estimationconsiderations.htm).
ConQuest documents its marginal likelihood and EM algorithm in Chapter 3,
Section 3.1.3, and its selectable estimation methods in Chapter 4,
Section 4.7.22. An absence of JMLE or MMLE in this package is therefore an
estimator-scope difference, not a missing component of the Bayesian estimator.

## Unsupported source features must fail visibly

Use the following migration rules:

1. If source weights are not all one, stop the direct migration. Record whether
   each weight is a case, model, element, or observation weight and why it was
   used. Do not drop it silently.
2. If more than one rating-scale group is present, record the group assignment
   and threshold convention. Do not substitute one global RSM or independent
   item PCMs without a new model decision.
3. If additional facets or interactions affect the source likelihood, retain
   their columns as metadata for review, but do not describe the destination
   fit as equivalent. Collapsing an interaction into a compound item changes
   the estimand and requires a separate justification.
4. If source anchors or user scaling are active, transform them to the
   destination logit direction and identification before any comparison. The
   stable fit applies only exact individual rater/item hard anchors; soft,
   threshold, and group-mean anchors remain unsupported.
5. Compare source and destination results only after matching observed rows,
   response categories, signs, constraints, threshold sharing, and parameter
   labels. Compare point recovery separately from uncertainty calibration.

## Anchor-constrained refitting policy

For the distinction between a reference, an external calibration and a starting
value, begin with [references and anchors](learning-guide.md#references-and-anchors).

The stable minimal path accepts exact individual rater/item hard anchors. The
anchored level is removed from the sampled coordinates and restored at its
declared value in the likelihood, prediction, Wright-map rows, rater
diagnostics, and design manifest. This replaces the default first-level-zero
gauge for that block; it is not stacked on top of it.

The numerical declaration is intentionally small: `block`, an explicit
`level` (or `target`), a finite logit `value`, and `type = :hard`. Source hashes
and external artifact metadata are not fitting prerequisites for a distributed
package:

```julia
anchored_spec = mfrm_spec(data;
    thresholds = :rating_scale,
    anchors = [(
        block = :rater,
        level = "R1",
        value = 0.0,
        type = :hard,
    )],
)

plan = anchor_refit_plan(anchored_spec; require_provenance = false)
@assert plan.status == :hard_anchor_candidate_ready
@assert plan.candidate_supported
@assert plan.numerical_fit_supported
@assert plan.capability == :stable_hard_anchor_fit_available

anchored_fit = fit(anchored_spec; backend = :advancedhmc)
```

[`anchor_refit_plan`](@ref) remains a non-mutating declaration check; it does
not itself run a fit. With `require_provenance = true`, it can additionally
audit the following optional handoff metadata:

| Field | Accepted contract |
| --- | --- |
| `value` | A non-`Bool` `Real` that remains finite and non-underflowing after conversion to `Float64` |
| `source` | A `Symbol` or string matching `[A-Za-z][A-Za-z0-9_.-]{0,63}` |
| `source_version` | A nonempty, printable string of at most 128 bytes, without leading or trailing whitespace |
| `source_model` | `:mfrm_rsm` for `thresholds = :rating_scale`, or `:mfrm_pcm` for `:partial_credit` |
| `source_estimator` | One of `:jml`, `:pmle`, `:mml`, or `:mcmc` |
| `source_hash` | A lowercase 64-hex SHA-256 string, optionally prefixed by `sha256:`; the plan checks format, not source-byte correspondence |
| `source_scale` | `:logit` |
| `sign` | `:severity_positive` for a rater anchor or `:difficulty_positive` for an item anchor |

Here `source_scale` and `sign` describe the already transformed numeric anchor
value. A FACETS user scale, reversed orientation, or nonidentity transformation
must be resolved before constructing the declaration. The optional provenance
audit never converts the value and never controls whether the stable numerical
fit is available.

`source_hash_format_valid = true` means only that the declaration has the
accepted lowercase SHA-256 shape. The plan does not receive the source
bytes and therefore always reports `source_bytes_verified = false`; callers
must verify and preserve the byte-to-digest correspondence outside this plan.
Likewise, `provenance_complete = true` means the required fields are present
and satisfy their field contracts, not that the external artifact is authentic
or substantively correct.

`require_provenance = false` permits all provenance fields to be absent. It
never makes a supplied but invalid audit field acceptable for a strict audit.
Every row records `normalized_value`, `value_issue`,
`declared_scale`, `normalized_scale`, `scale_issue`,
`missing_provenance_fields`, `invalid_provenance_fields`, and
`provenance_issues` so rejection is machine-readable.

A hard anchor carrying `scale`, `sd`, or `prior_scale` is ambiguous and is
rejected; uncertainty metadata must not silently turn an exact constraint into
a soft prior. Conversely, a soft anchor requires a positive finite, non-Boolean
prior scale that remains positive and finite after `Float64` conversion.
Soft anchors remain inspection-only. In particular, a soft anchor on the
default reference would otherwise create a constant prior; the package rejects
that boundary rather than silently pretending it is informative.

The existing distinction between parameter anchors and common-response linking
must remain. A larger number of common responses does not turn them into fixed
parameter anchors, and fixed parameter anchors do not create observed links.
They do not waive the ordinary connectedness/rank validation gate. This package
therefore rejects disconnected person-rater-item graphs even when an individual
hard anchor is declared in every component. FACETS-style group anchoring instead
sets a facet-group mean and assumes the anchored groups are exchangeable; that
is a different, currently unsupported model. [Wind and Stager
(2019)](https://www.psychologie-aktuell.com/fileadmin/Redaktion/Journale/ptam-2019-1/03_Wind.pdf)
show that within-component design and misfit affect estimates under group
anchoring, while [Myford and Wolfe
(2000)](https://doi.org/10.1002/j.2333-8504.2000.tb01832.x) distinguish minimal
connectivity from link quality. No universal anchor percentage should be
recommended.

### Individual hard anchors for the minimal model

Exact item and rater anchors use the affine selection map

```math
\beta=b+Cz,
```

where `b` contains fixed values, `C` selects free coordinates, and `z` is
sampled. Unknown levels, missing targets, Boolean/nonfinite/unrepresentable
values, duplicate targets, hard anchors carrying a prior scale, and unsupported
blocks fail closed before stable compilation. Multiple exact anchors are
allowed; each fixed coordinate is omitted from the prior and sampler.

At the likelihood level, one exact anchor in a rater or item block only chooses
that block's location gauge: shifting the anchor can be offset by the free facet
coordinates and person locations without changing response probabilities. Two
or more anchors in the same block additionally fix within-block contrasts. A
contaminated multi-anchor contrast is therefore a substantive model restriction,
not a harmless change of origin. Sensitivity work should cross anchor count,
facet location, and plausible value perturbations; adding anchors is not
automatically stabilizing. The zero-centered-prior qualification appears below.

Keep this parameter-anchor question separate from common-response linking.
[Wind and Jones (2018)](https://doi.org/10.1177/0013164417703733) vary linking-
set size, location, and model-data fit, but explicitly do not provide parameter-
recovery evidence and did not manipulate rater effects. [Uto
(2021)](https://doi.org/10.3758/s13428-020-01498-x) fixes common-rater and
common-task values from a base test and shows that required commonality changes
with missingness, test scale, population differences, and drift. Neither
establishes a universal exact-parameter anchor count.
[Kopf et al. (2015)](https://doi.org/10.1177/0013164414529792) provide indirect
motivation for the contamination stress from a DIF-anchor context, not direct
validation of this MFRM implementation. Likewise, [Robitzsch
(2024)](https://doi.org/10.3390/appliedmath4030063) analytically derives bias
and linking error for fixed-item-parameter calibration under random uniform DIF
in a 2PL model. It supports treating fixed-parameter contamination as a model
risk, but it is not direct validation of this package's polytomous MFRM path.
[Robitzsch (2024)](https://doi.org/10.3390/stats7030036) further separates
person-sampling standard error from item-selection linking error and compares
robust and nonrobust linking under DIF. This supports keeping anchor-set
sensitivity separate from ordinary posterior uncertainty; its dichotomous 2PL
results do not supply a robust-linking method for the present MFRM.

Changing a single anchor can preserve the response likelihood after shifting
free facet coordinates and person locations, but the fixed zero-centered
priors are not translated with it. Thus a likelihood-equivalent change of
origin need not preserve the posterior. More diffuse priors attenuate this
coordinate effect; that fact alone does not justify choosing a diffuse prior.

For two incompatible anchors in one facet, removing either member leaves one
anchor whose value can be absorbed by a location shift. Leave-one-anchor-out
sensitivity can expose an incompatible pair but cannot identify the
contaminated member from the response likelihood alone. That attribution
requires external information or a model for source uncertainty.

Predictions from this fixed-effect model concern the observed facet levels.
New-person, new-item, or new-rater prediction is unsupported because the model
has no hierarchical facet population to marginalize.

Fixed coordinates are recorded as unsampled in the design/fit manifest and as
`is_fixed = true` with `status = :hard_anchor` in Wright-map rows. They receive
exact zero-width intervals there, not artificial R-hat or ESS values. The
normalized anchor declaration participates in the semantic model identity.
Cache keys use that identity, so reordering the same declarations does not
create a different cache request; changing an anchor or its recorded provenance
still does.

`fit_report(fit; view = :public)` keeps those constants in the dedicated
`fixed_coordinates.rows` table and out of posterior-summary rows. Each report
row states `sampled = false`, `prior_applied = false`, and
`posterior_estimated = false`. When at least one declared hard anchor is
present, `fixed_coordinates.warning_rows` contains two baseline warnings: the
listed values have no posterior, prior, or sampling uncertainty, and the
zero-centered prior on free identified coordinates is not shifted with the
anchor. Any estimation or linking error in externally obtained anchor values is
therefore not propagated. Consequently, likelihood-equivalent anchor changes
need not be prior- or posterior-invariant. The Markdown renderer places both
warnings near the top of the report before the section summary. If two or more anchors occur in the
same facet, a third warning marks the resulting within-facet contrast
restriction and requests contamination or drift sensitivity. Anchoring one
rater and one item still selects one gauge per block and does not trigger it.

### Unsupported anchor types and imported records

Threshold, group-mean, and soft anchors are not supported for fitting. Do not
silently recenter imported threshold values or replace a group-mean constraint
with individual fixed values: those operations change the declared model.
A soft anchor expresses uncertainty through an informative prior; the current
exact-anchor path does not propagate that uncertainty.

Starting values and anchors serve different purposes. Resolve source labels,
signs, location and scale conventions before declaring a destination anchor,
and retain the original values and transformations with the analysis.
`load_conquest_semantic_parameters` returns source-gauge records only. It does
not import destination starting values or anchors, and the package does not
provide a general anchor-file round trip. The optional provenance fields
accepted by `anchor_refit_plan` are listed above.

## Migration acceptance checklist

Before describing a source and destination run as an overlap comparison, record:

- the exact source software version, command/specification file, estimator, and
  convergence settings;
- the matched response rows and category coding;
- rating-scale versus partial-credit sharing and every scale group;
- sign, location, user-scale, and threshold transformations;
- anchors, starting values, linking responses, and weights as separate fields;
- the source and destination parameter-label map;
- point-estimate agreement, uncertainty behavior, predictive checks, and
  nonconvergence or unsupported cells as separate results;
- hashes for source data/config/output and destination data/spec/fit/report.

Passing this checklist establishes a reproducible comparison of a named
overlap target. It does not establish estimator equivalence, product parity,
or superiority of one program over another.
