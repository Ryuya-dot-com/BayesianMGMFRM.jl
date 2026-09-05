# Migrating from FACETS and ACER ConQuest

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

# Freeze the compiled meaning before sampling.
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

### Version-specific ConQuest 5.47.5 execution fixture

The repository contains a privacy-reduced fixture from fresh RSM and PCM runs
made with the generated, hardened macOS verifier/runner and ConQuest 5.47.5
Demonstration. Both processes recorded exit code zero and both receipts bind 15
declared output records. Four raw outputs per model are retained: parameter
pairs, design matrix, estimation history, and the zero-byte labels file. The
executed control, manifest, verifier, runner, and receipt are also retained;
row-level ratings, person estimates, residuals, raw logs, the executable, and
activation material are not.

| Target | Persons | Ratings | Free design rank | Selected / final iteration | Rater RMSE | Item RMSE | Step RMSE |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| RSM | 120 | 1,440 | 6 | 13 / 18 | 0.03134 | 0.06592 | 0.11581 |
| PCM | 160 | 1,920 | 9 | 13 / 17 | 0.06851 | 0.04868 | 0.09016 |

The test suite recomputes every retained-file hash and receipt content hash,
rebuilds each bundle ID from its manifest, checks the complete 12 generalized-
item by 3-category design grids and matrix ranks, reconstructs the sum-to-zero
rater/item/step coordinates, links the minimum-deviance history row to the
parameter export, and recomputes RMSE. Selecting the final history row would be
wrong in both fits; iteration 13 has the minimum recorded deviance.

This is version-specific, single-run transport and known-truth recovery
evidence. The seed and truth are operator-recorded because the row-level
generation stream is intentionally omitted. Bytes for the other 11 raw outputs
are likewise omitted, so their receipt records cannot be independently
rehash-checked from the repository. The fixture is not independent execution,
convergence adjudication, a direct comparison with the package posterior,
construct validation, or product equivalence.

A valid receipt establishes input continuity, a zero recorded process exit,
the presence and byte-exact hashes of the declared files, no undeclared root or
result entries, and the absence of a small set of recognized fatal markers. It
records operator-reported completion but does **not** independently establish
that the executable ran, authenticate it, establish convergence, resolve
parameter labels, align gauges, demonstrate numerical agreement, or establish
product equivalence. The bridge therefore does not turn a reported external
run into validation evidence by itself.

Anchoring is intentionally a later, two-stage extension. First run the
unanchored control and return its declared labelled or score outputs together
with the identifier maps; for ConQuest, the declared files also include its
positional parameter export, design matrix, and labels. The transport stage,
privacy-reduced output-sample freeze, and version-specific three-category
source-gauge semantic adapter are now complete for ConQuest 5.47.5 RSM and
PCM. The next step is a separately tested transformation from the ConQuest
term-wise sum-to-zero gauge to the package's first-reference gauge, followed by
a convergence policy and direct comparison artifact. Only after those layers
resolve stable destination targets should a second-stage bridge compile
anchors for the exact returned design. The current bridge still does not
perform that second stage;
[`anchor_refit_plan`](@ref) remains a destination-side plan and does not
execute either an external anchored calibration or a package
anchor-constrained refit.

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
| Separation/reliability | `separation_reliability_summary` | Posterior screening summary, not an estimator-identical copy of source output. |
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

### Implemented stage: individual hard anchors for the minimal model

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
establishes a universal exact-parameter anchor count, and this package's within-
test hard-anchor pilot is not a two-test linking validation.
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

The local descriptive MCMC pilot can be reproduced with:

```bash
julia --project=. scripts/run_mfrm_anchor_recovery_pilot.jl
```

It uses two replications, four chains, known-truth/projection initialization,
and pilot-only diagnostic thresholds. Eighty fits cross fully crossed,
rotating-pair sparse, and two 10%-common-response nested designs; fitted-family
and R4 extremity-response generators; and true or shifted single anchors, true
endpoint or interior multi-anchors, and contaminated endpoint multi-anchors.
Named events share deterministic response uniforms across topologies, while
every within-topology anchor comparison uses identical training and independent
same-facet holdout responses. All 80 fits pass the pilot diagnostics with no
divergences or maximum-tree-depth hits.

Contamination worsens true-probability log-score regret in 16/16 pairs (mean
`+0.00862`) but finite-sample holdout log loss in only 10/16 (mean `+0.00335`).
Changing only the value of one rater and one item anchor has maximum absolute
regret difference `0.00624`; this is not expected to be exactly zero because
the likelihood gauge transformation does not also translate the fixed zero-
centered priors. Correct interior anchors are worse than correct endpoints in
10/16 pairs with a near-zero mean regret difference (`-0.00094`), so neither
location is generally preferred by this pilot.

An exact dense/sparse design check isolates this coordinate effect without
MCMC: the default and shifted single-anchor encodings have equal likelihood,
but unequal prior density. If every `MFRMPrior` standard deviation is multiplied
by `c`, their log-prior difference scales as `1/c^2`. Diffuse priors therefore
attenuate this difference but do not make finite-scale posterior comparisons
between gauges invariant or justify choosing a prior for that purpose.

A second exact check exhausts all 12 ordered clean/contaminated two-anchor
pairs across rater and item facets, with the contaminated position ranging over
both endpoints and the interior. Every pair changes response probabilities in
both dense and sparse designs. Removing either member, however, leaves a single
anchor whose value can be absorbed by a location-gauge shift and restores the
same true probabilities. Leave-one-anchor-out sensitivity can therefore expose
an incompatible pair but cannot identify the contaminated member from the
response likelihood alone; that attribution requires external provenance or a
model for source uncertainty.

The distributed nested-link design is worse than the early design in all 20
anchor/condition/replication contrasts, but this is deliberately recorded as a
composite stress, not a placement effect: early links balance items but have
rater loads `20/28/28/28`, whereas distributed links have loads `26/26/26/26`
and item counts `3/1/1/3`. The base simulator still shares the package
likelihood kernel, only two replications were run, and the holdout contains no
new facet levels. New-person, new-item, or new-rater prediction remains
unsupported because the fixed-effect MFRM has no hierarchical facet population
to marginalize. The output is not recovery calibration, independent-kernel
validation, or a public-release gate.

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

### Stage 2: threshold and group-mean hard anchors

After individual item/rater anchors pass, add complete rating-scale/PCM
threshold anchors and FACETS-style group-mean constraints. These require an
explicit threshold convention and a full-rank affine constraint system.
Imported threshold values must not be silently recentered to satisfy the
package's sum-to-zero gauge; an incompatible source scale should be rejected or
transformed by an explicit, recorded operation.

Group anchors constrain a declared weighted or unweighted group mean while
allowing members to vary. The report must state group membership, treatment of
extreme or unobserved levels, the mean definition, and the effective constraint
rank.

### Stage 3: soft anchors

A soft anchor should be an explicit prior on an identified direct parameter,
for example `Normal(anchor_value, anchor_scale)`. It must not be the sole
structural identification rule. The deterministic gauge remains in force, and
the report distinguishes the identification constraint from the informative
linking prior.

Under the current first-level-zero gauge, a soft prior on that fixed reference
coordinate is constant and contributes no information. Such a declaration is
invalid until the numerical compiler either reparameterizes the reference or
converts the imported anchor into an explicitly identified contrast.

Soft-anchor release evidence should vary the prior scale and source values,
report prior-to-posterior movement, compare hard/soft/unanchored refits, and
flag prior-dominated cells. A hard and soft anchor on the same direct parameter
should be rejected unless a future contract defines a nonredundant role for
both.

## Round-trip provenance contract

ConQuest warns that unidentified parameters can be removed, changing positional
parameter numbers in later anchor files. A package interchange format should
therefore use semantic identities rather than source row numbers as its primary
key. At minimum, every imported anchor or starting value should record:

```text
schema, role = anchor|initial_value, anchor_type,
block, level, step_or_category, value, scale_unit,
source_software, source_version, source_model, source_estimator,
source_sign, destination_sign, location_transform, scale_transform,
source_file_sha256, source_data_hash, source_model_hash
```

Starting values and anchors remain separate objects. If both target the same
parameter, the importer should report the conflict and apply an explicit policy;
it should not depend on file order. The normalized imported record, the compiled
constraint map, and the exact source bytes should each have their own hash.

An exported anchored fit should preserve the original import record unchanged
and add the destination package version, data/model/prior/sampler identities,
fixed/free status, direct fitted labels, constraint-rank check, and fit-artifact
hash. A round trip passes only when reimport reproduces the same semantic target
and normalized content hash. Equality of printed decimal text alone is not a
round-trip guarantee.

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
