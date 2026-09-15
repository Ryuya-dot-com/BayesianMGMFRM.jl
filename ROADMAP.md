# BayesianMGMFRM.jl — Internal Roadmap

Updated 2026-09-15 to establish the private two-dimensional correlated
fixed-coefficient density and its Julia/CmdStan checks. The independent model
retains its experimental fit, saved-result and figure/report workflow.
Julia remains primary, CmdStan remains its
maintained counterpart, and Uchihara (2022) remains a secondary application.
This is the **single current work order**, not a public feature catalogue or a
completion percentage. Start with the decision below;
do not reconstruct priorities from historical checkboxes. The
[ordered deliverables](#immediate-work-and-stop-conditions) are the work queue;
the source reviews below are their evidence, not additional milestones.

## Active Decision Roadmap

**Primary objective: establish a mathematically correct, reliable and reusable
Julia foundation for Bayesian MGMFRM, preserving the existing MFRM/GMFRM
behavior and making supported models usable from fitting through diagnostics,
visualization and saved results. Maintain CmdStan estimation of the same models
as a continuing computational check. Uchihara (2022) is a secondary application
that exercises this foundation.**

The user's 2026-09-11 clarification supersedes the prior case-first
sequence. Establish the Julia model and numerical contracts -> strengthen the
existing estimation/result path with CmdStan checks -> validate the declared
domain and user workflow -> apply the supported foundation to concrete studies.
The [ordered deliverables](#immediate-work-and-stop-conditions) control this work.
Completion of the Uchihara analysis, its data reconciliation or its specialized
extensions is not a prerequisite or the definition of completion for the Julia
foundation. Applications can reveal a reusable defect or requirement, but their
data layout and desired findings must not determine core defaults or architecture.

The user's 2026-09-15 scope clarification sets the long-term direction:
compensatory and non-compensatory response models, between-item and within-item
structures, estimated latent correlations, Q identification and structure
estimation, and configurable random effects. Treat these as distinct model
choices, with validated combinations added incrementally. The
[extension sequence](#long-term-extension-sequence) specifies their deliverables
and evidence requirements; it is not a claim that those options are available
today or that every combination belongs in the next release.
The subsequent Uchihara workflow discussion sharpens the reusable
[specification and prediction contract](#shared-specification-and-prediction-contract).
Implement each relevant part with its model extension; the application and a
complete future specification language are not prerequisites for the
[implementation handoffs](#next-implementation-handoffs).

The user's 2026-09-07 clarification corrects the previous work order's emphasis
on the MFRM anchor study. MFRM is a reusable foundation and comparison branch,
not the project's final deliverable. Completing its entire anchor panel is not
a blanket prerequisite for MGMFRM development. The existing fixed-Q MGMFRM
implementation is the starting point, not a permanent restriction to independent
dimensions or one dataset's two-trait structure. Prioritize model correctness
and the reusable fixed-coefficient/correlated-dimension extensions on their own
measurement and validation merits. The source and exchangeable-prior scientific
models retain their distinct research roles and identities; no complete model
catalogue or full source-reproduction study is a prerequisite for fixing the core.

The research-first sequencing decision defers M0's historical runtime
attribution and controlled benchmarking; it does not accept M0 or waive the
release criterion. Those performance tasks are no longer prerequisites for
M2. Fresh evaluation still requires a target-specific independently reviewed M1 and the
[research execution prerequisites](#research-execution-prerequisites).
The independent fixed-coefficient fit-to-report workflow is connected through
the experimental API. Its private 2D correlated-ability extension now has an
explicit prior/coordinate/Jacobian contract and sampler-free Julia/CmdStan
checks. The next bounded deliverable connects that target to private sampling
and a separately identified saved record, preserving the existing independent
model and caches. Public free-correlation fitting and statistical evaluation
remain separate steps; the generalized correlation candidate retains its own
model identity.
LD1b execution, soft/group anchors, and new-facet prediction remain separate
programs unless a reviewed core-model requirement makes them necessary.

The user's 2026-09-11 UX review adds a product completion requirement:
ordinary users must be able to fit, diagnose, interpret, visualize, and save
results without manually reshaping MCMC draws or learning research-management
APIs. README, public manuals and help must explain current behavior consistently
without requiring knowledge of development stages or study-execution approvals.
The [UX delivery contract](#user-workflow-api-naming-and-visualization), including
[documentation/help acceptance](#public-documentation-and-help-acceptance),
joins the existing work queue. Its acceptance criteria remain distinct from
the dated implementation checks below and from independent scientific review.

| Milestone | Status | Responsible role and concrete exit |
| --- | --- | --- |
| M0 — Package baseline | Implementation, placement/load review, and all 12 lane baselines recorded; runtime acceptance open, further performance work deferred | Maintainer: retain the unexplained 23.4% trigger and release hold; revisit after research progress or evidence of an actual execution blocker. Correctness, integrity, and resource-safety defects are not deferred |
| M1 — Julia model, implementation and validation contract | Existing generalized fits and focused numerical checks are available. Canonical fixed-coefficient multidimensional MFRM has experimental Julia/CmdStan fits, result reconstruction, manual v2 caches, full/public reports/artifacts and named-dimension figures. Selected source/exchangeable priors, identification and validation scope remain unresolved | Analyst/maintainer: connect the verified correlated density to private sampling/results, reconcile equations, coordinates, priors, gradients and result semantics, and prepare independent review of the target-specific validation protocol. Implementation checks do not close M1; Uchihara preparation is not a dependency |
| M2 — Core estimation evidence | Historical pilots and comparison assets retained; no fresh validation replication launched by this work order | Analyst: execute the reviewed bounded known-truth roster for the declared model/design domain, assess recovery/calibration, failures and prior sensitivity, and retain diagnostic-qualified Julia/CmdStan comparisons. A successful application fit does not close this milestone |
| M3 — Usable package and supported-domain review | Existing public-model content and saved-fit figure/report integration are verified. The new fixed-coefficient result has numerical reports/public projections and named-dimension plots/bundles; experimental fitting and a generic two-backend example are connected. Unfamiliar-reader and scientific review remain pending | Maintainer and independent reviewer: reproduce selected numerical/scientific claims, verify the documented user workflow, and decide supported/narrowed/rejected/inconclusive scope. Application reports are secondary outputs, not package acceptance gates |

Roles above do not imply that a person has accepted an assignment. In
particular, an independent reviewer is not yet assigned. Implementation by
the same author or another local receipt cannot satisfy that review.

### Core-model boundaries and next deliverable

Reuse the existing [model-family contract](src/model_family_contract.jl),
[experimental surface contract](src/experimental.jl),
[validation protocol](src/mgmfrm_validation_protocol.jl), and
[research design detail](docs/src/mgmfrm-research-roadmap.md). They already
separate the implemented branch from broader source-model targets. The two
scientific models need explicit identities and prior targets, not two copied
fitting engines, another roadmap, or a new generic model registry.

| Core concern | Current implementation and next decision |
| --- | --- |
| Multidimensional generalized likelihood | The experimental fit has at least two ability dimensions, fixed-Q positive item-dimension discriminations, rater severity and positive consistency, and item-owned partial-credit steps. Review the existing Julia/Stan equation, transforms, priors, and parameter/report mappings together; MFRM or scalar GMFRM checks do not validate this joint model |
| Fixed-coefficient multidimensional MFRM | Canonical specifications connect through `Experimental.fit` to Julia/CmdStan, dedicated results, manual v2 caches and full/public reports with named-dimension figures. Small 2D/3D fits and numerical checks establish operability, not recovery or coverage. A generic fit-to-report example exercises both backends. The separate private 2D correlated-ability density now has a measure/identity contract and numerical checks; it has no fit/result integration. Unit logits, fixed loadings/consistencies and the prior-anchored location convention remain explicit; this branch does not select the generalized source/exchangeable prior |
| Identification and intended scope | The current fit fixes latent correlation to identity and rejects anchors and fitted DFF; the fitted facets are person, item, and rater. Establish the implemented domain and the contracts for fixed-coefficient and correlated-dimension extensions independently of any application. Fixed within-item/mixed Q structures remain warning-bearing; criterion-specific raters, recording effects, arbitrary facets and generalized anchors require separate scope decisions |
| Bayesian practical decisions | Assess dimension-specific ability, discrimination, severity/consistency, category steps, and predictive uncertainty according to the user's intended use. Revisit the existing draft's secondary-only person-ability priority for individual decisions. Distinguish posterior uncertainty, prior sensitivity, model adequacy, and practical loss; neither a converged fit nor a finite interval alone establishes practical acceptability |
| Stress and scientific evidence | Reuse the existing Q/design validation and [response-pattern stress plan](src/mgmfrm_response_stress.jl), including all-minimum raters. Separate well-specified recovery from deterministic response contamination; an all-1 pattern does not itself identify its cause or justify automatic exclusion/downweighting. Evaluate joint severity/consistency uncertainty and predictions under sparse overlap and Q misspecification, not only warning detection |

The initial source-equation-to-implementation gap review is recorded below,
using existing sampler-free contract/identification tests before changing
fitting code. Any change must address an observed gap in a named
model block or user decision. The existing narrow fixed-Q/identity-correlation
branch is a reusable numerical baseline; the first substantive validation target
must follow the accepted package model and intended domain, with its restrictions
explicit. The Uchihara design does not define that domain. The
separate free-correlation density/gradient candidate and
historical pilots are useful assets, not a promoted fitting API or fresh
independent evaluation. This review does not change model code, protocol
constants, scientific acceptance, or execution permissions.

### First Julia core verification slice

The 2026-09-11 implementation passes traced the existing fixed-Q target,
corrected a numerical constraint failure, and hardened input conversion and
cache publication without changing the statistical model.

| Block | Implementation trace and finding |
| --- | --- |
| Raw prior and measure | `_SourceFixturePrior`, `_source_fixture_prior_sd` and `_source_fixture_logprior` in [bayesian_fit.jl](src/bayesian_fit.jl) apply independent normal priors to the free raw coordinates. Positive transforms add no Jacobian for this declared target; source/exchangeable prior decisions remain separate |
| Response equation and transforms | `_mgmfrm_source_constrained_params_from_unconstrained` and `_mgmfrm_source_linear_predictors!` in [facet_workflow.jl](src/facet_workflow.jl) reconstruct constrained parameters and use the additive ability score, item steps and `1.7` rater multiplier. The [Stan model](src/stan/mgmfrm.stan) and its [data adapter](src/cmdstan_fit.jl) retain the same raw layout and prior SD mapping |
| Product-one constraint — corrected | Finite factors `exp.([400, 400, -400, -400, 0])` have product approximately one, but ordinary intermediate multiplication overflowed and caused rejection. The shared positive-product calculation now uses log space in both validation and diagnostic rows, covering GMFRM item discriminations and MGMFRM rater consistencies. Product-scale tolerance stays `1e-8`; invalid factors and non-unit products remain failures |
| Prior and initial-value inputs — corrected | `MFRMPrior` and `_SourceFixturePrior` (also used by `Experimental.GeneralizedPrior`) now validate the stored `Float64` scales. Finite positive `BigFloat` inputs that convert to infinity or zero are rejected. Scalar `initial_params` methods likewise reject conversion overflow, including the research-only correlation coordinate; vector initializers already checked after conversion |
| Sampler controls and initialization — corrected | `_check_fit_controls` and `_check_nuts_controls` now share converted numeric bounds across fitting and cache-key creation. This covers stable Julia/Turing, GMFRM/MGMFRM AdvancedHMC, the research-only correlation sampler, and both CmdStan adapters. CmdStan retains its fixed divergence threshold, and stable MFRM rejects a non-finite initial log posterior before runtime discovery/compilation |
| Sampling and results — focused integration checked | `_run_generalized_candidate_advancedhmc` uses the target/gradient adapter; `_mgmfrm_guarded_local_fit_diagnostic_surface` reconstructs direct draws and constraint summaries; `_mgmfrm_fit_from_sampler_diagnostics` stores the common result. Tiny Julia fits check retained chain/iteration labels, sampler-stat alignment, recomputed log densities, and raw/direct summary names and means. Malformed chain labels/iterations are rejected by the existing layout check; this is not a full sampler-failure or statistical acceptance study |
| Rejected transitions and retained-output boundary — corrected | Random-walk proposals with non-finite coordinates or log density are rejected and counted separately from NUTS divergences. `_store_sampler_draw!` checks parameter count and converted finite draws/log densities before Julia NUTS output can become a fit result, identifying the chain and retained iteration on failure. The shared path covers stable AdvancedHMC/Turing, GMFRM/MGMFRM AdvancedHMC and the research-only correlation sampler; valid states retained after divergent transitions remain admissible |
| Cache publication — corrected | Shared `save_fit_cache` serializes and closes a same-directory temporary file before publishing it. Serialization/replacement failures preserve an existing result; exclusive publication also preserves a competing destination. `cached_fit` now passes `refresh` through as the overwrite policy. `load_fit_cache` retains the existing schema, key and artifact-hash checks; the artifact hash does not certify every field of the fitted object |

The [regression test](test/generalized_prior.jl) checks overflow/underflow orderings
against high-precision multiplication, finite gradients, expected probabilities,
diagnostic values and rejection of invalid inputs. On Julia 1.12.5,
`test/generalized_prior.jl` and `test/generalized_guard_contract.jl` passed all
409 assertions, including 108 new regression assertions. The existing
GMFRM/MGMFRM Stan-reference checks passed 44 assertions using the retained
fixtures and test helper; their source files and reference values were unchanged.
These are deterministic
implementation checks, not new CmdStan execution, posterior comparisons or
recovery evidence. No new prior, model option or default was adopted.
The follow-up [input and cache regression tests](test/fitting_boundaries.jl)
passed 256 assertions on Julia 1.12.5/macOS: 232 prior/initial-value checks and
24 publication/reload checks. Fault injection reproduced corruption of an
existing cache before the fix; the corrected path preserves its exact bytes,
rejects competing destinations, cleans temporary files, and replaces symbolic
links without changing their targets. These tests use deterministic fit objects,
not estimated posterior draws. The existing 409 generalized assertions and
44 retained Stan-reference assertions also passed after the input correction.
The existing `cached_fit` create/reuse/key-mismatch/refresh integration checks
passed eight assertions using two tiny random-walk fits (two chains, three
retained draws and two warmup iterations per chain per fit). This checks the
ordinary artifact/save/load connection, not posterior accuracy or convergence.
Native rename is used to avoid Julia 1.10's copy/remove fallback; minimum-version
runtime verification remains with the existing Julia 1.10.8 CI job and was not
run locally. This does not establish crash/power-loss durability.

The 2026-09-12 pass reproduced accepted `step_size` inputs becoming infinity
or zero, returning stationary random-walk draws with acceptance rates of zero
or one. These requests now fail at the numeric input boundary. The same fix
covers target acceptances rounding to zero/one, energy thresholds overflowing
or underflowing, and jitter overflowing; tiny negative jitter remains invalid
even when it rounds to negative zero. Valid equivalent numeric types retain
the same cache keys. The explicit-chain-initialization policy in the research
candidate still requires the original jitter input to be exactly zero.

The [boundary tests](test/fitting_boundaries.jl) add 700 control/initialization
assertions and 82 integration assertions on Julia 1.12.5/macOS. The final
passing integration uses five tiny fits: stable MFRM with random walk,
AdvancedHMC and Turing, plus GMFRM/MGMFRM with AdvancedHMC, each with two chains,
four retained draws and two warmup iterations per chain. This tests software
connections and metadata, not posterior accuracy, convergence or recovery.
The existing CmdStan contract/CSV checks (78 assertions), generalized guards
(58), and retained Stan density/gradient references (44) also pass; no new
CmdStan fit was launched. Full-suite, minimum-version and other-platform runs
remain unperformed for this change.

The next 2026-09-12 pass reproduced a finite, very large random-walk step
producing non-finite proposals while every sampler row claimed no numerical
error. The corrected rows retain the last valid state, mark the event and
expose `n_nonfinite_proposals` through `sampler_diagnostics` and `diagnostics`.
This is a retained-iteration count, not warmup coverage or a diagnosis of the
cause. NUTS divergence counts are unchanged. Older random-walk fits without
this telemetry report `missing`; cache reload does not invent historical data.
One acceptance uniform is still consumed per iteration, including rejection.

The focused [transition tests](test/fitting_boundaries.jl) pass 59 assertions:
24 for overflow rejection, ordinary rejection, warning priority, random
stream consumption, incomplete telemetry and current/legacy cache reload; 35 for valid divergent
states, malformed parameter counts, non-finite output and chain/draw context.
The latter inject invalid retained values into the shared output writer;
they do not demonstrate that AdvancedHMC or Turing emitted such values.
The existing tiny integration tests exercise the writer through actual Julia
sampling. No model, prior or default sampler setting changed.

The following 2026-09-12 pass reproduced explicit `InterruptException`s being
converted to `ArgumentError` during gradient initialization, to `CmdStanError`
during JSON output, and to a captured report-section error. The fitting and
CmdStan adapters now share the existing stress-runner policy: interruption,
out-of-memory and stack-overflow exceptions are rethrown unchanged. The report
capture path follows the same policy; ordinary section errors remain capturable.

Unexpected exceptions from random walk, AdvancedHMC and Turing sampling now
carry backend, chain and sampling-phase context with a `CapturedException`
retaining the original exception and backtrace. The shared AdvancedHMC path
covers stable and generalized fits and the research correlation sampler uses
the same wrapper. CmdStan initialization-file, command and parser errors gain
chain/phase context; existing `CmdStanError.stage` and `.reason` stay intact.
Existing CmdStan typed errors still store a diagnostic string rather than a
structured original cause. Preflight input errors retain their existing types.
No failed chain is retried or returned as a successful partial fit.

The runnable fault checks are in [fitting boundaries](test/fitting_boundaries.jl).
They inject exceptions through target evaluation, JSON serialization, finite
checks and real Julia sampler RNG calls. The random-walk case fails on chain 2
after a complete first chain. The CmdStan case uses a synthetic shell executable
and fails the parser on chain 2; it does not compile or sample a Stan model.
Constructed exception objects do not test actual memory exhaustion, live Ctrl-C
delivery, subprocess termination/reaping or cancellation of a process tree.

On Julia 1.12.5/macOS, all 76 new fault assertions pass. The 1,097 existing
boundary and tiny-fit assertions, CmdStan contract/CSV checks (78), generalized
guards (58), and retained Stan density/gradient references (44) also pass in
targeted runs. These are software checks, not posterior validation. The full
suite, minimum supported Julia version and other platforms were not run.
The existing isolated CmdStan cache probe (4,617 assertions) and synthetic
producer/control probe (431) also pass. The latter's imports were updated for
the shared control checks and fatal-exception policy; both probes avoid native
CmdStan execution.

The next pass extends the same context wrapper to chain initialization and
retained-output validation in stable Julia, guarded generalized, research
correlation and CmdStan paths. Initialization/output `ArgumentError`s retain
their type with context added; unexpected failures retain a captured cause.
CmdStan output dimensions and row counts must match exactly before assignment,
so broadcasting cannot conceal malformed output. Finite output is checked
after conversion into the retained Float64 arrays.

A real SIGINT sent to Julia while its owned command waited reproduced an
orphaned direct child with both terminal and captured output. The command
adapter now retains the process handle, enables interruption during the wait,
and kills/reaps the direct child before rethrowing. It preserves stdin and
the existing output-routing behavior explicitly when starting asynchronously,
following Julia's [process API](https://docs.julialang.org/en/v1/base/base/#Base.run)
and [signal handling API](https://docs.julialang.org/en/v1/base/c/#Base.disable_sigint).
The standalone [command lifecycle check](test/cmdstan_cancellation.py) runs
with `python3 test/cmdstan_cancellation.py`; it uses unchanged package helper
bodies, temporary shell commands and real POSIX signals, without loading the
full package or running CmdStan. It checks successful and failed commands,
stdin/output routing, and interruption with a child that ignores INT and TERM.
The probe explicitly uses `Base.exit_on_sigint(false)`, matching capturable
REPL interruptions. The package does not change Julia's global signal policy;
immediate script termination bypasses this exception-based cleanup.

On Julia 1.12.5/macOS, the 76 additional boundary assertions and all six live
command cases pass. The combined targeted Julia run passes 6,477 assertions,
including the existing tiny native fits, generalized guards, retained Stan
references and both isolated CmdStan probes. Invalid native output is injected
at the shared validation wrapper; these checks do not imply that Turing or
AdvancedHMC emitted malformed draws. No actual CmdStan fit, full-suite run,
minimum-version run or other-platform validation was performed.

The 2026-09-13 pass extends command ownership to a fresh POSIX process group,
using the same scope as the existing [command observer](scripts/measure_command.py).
The Julia adapter uses [detached commands](https://docs.julialang.org/en/v1/base/base/#Base.detach)
and the existing libuv runtime's [signal API](https://docs.libuv.org/en/v1.x/process.html#c.uv_kill).
Remaining group members are terminated after command completion as well as
interruption, including a wrapper's workers when the wrapper exits first.
Special group IDs and Julia's own group are rejected before signalling.
This uses no process-name search or new runtime dependency.

A lazily registered, single Julia exit hook cleans active commands at default
script SIGINT exits and explicit `exit()` calls. The registry is locked and
retains only active commands; completed commands are removed. Julia's global
SIGINT policy is unchanged: capturable interrupts still propagate, while
uncapturable script SIGINT still terminates Julia. Cleanup failures are reported;
an exception during the command wait and a subsequent cleanup exception are
retained together instead of discarding the original failure.

The expanded [lifecycle check](test/cmdstan_cancellation.py) tests the original
six command cases and twelve process-group cases: captured SIGINT sent to Julia
or its terminal group, default script SIGINT, explicit exit, two active groups,
and a leader exiting with status 0 or 7 before its worker. It verifies group
identity, preservation of an unrelated group, descendant exit via an owned
FIFO reaching EOF, and rejection of unsafe group IDs. FIFO EOF is not a claim
that Julia can reap non-child descendants. These are synthetic processes, not
native CmdStan build or estimation evidence.

On Julia 1.12.5/macOS, all eighteen live command cases and the group-ID guards
pass. The existing targeted Julia testsets pass 6,477 assertions; a final check
also confirms that the package's active-command registry is empty. The combined
error formatter is checked separately so a cleanup failure is visible alongside
the original error. No actual CmdStan fit or full-suite run was performed.

The remaining boundary is explicit: descendants that call `setsid`/`setpgid`
can escape the owned group; SIGKILL or other termination bypassing Julia exit
hooks cannot run cleanup. Windows retains direct-child cleanup. Runtime
discovery still uses its separate command path. Minimum-version, other-platform,
PID/group-reuse races, repeated-signal stress and actual CmdStan cancellation
remain unvalidated. These remain explicit acceptance limits.

The subsequent [blockwise measure check](#current-fixed-q-mgmfrm-executable-blockwise-measure)
now connects the current Julia target to production CmdStan densities and
gradients. The [normalized prior reference](#normalized-source-and-exchangeable-prior-reference)
specifies source/exchangeable blocks, now integrated into
[complete private Julia/Stan densities](#complete-fixed-q-normalized-prior-targets).
The [private sampling and saved-result slice](#normalized-prior-sampling-and-saved-results)
now exercises both backends. The subsequent
[fixed-Q posterior comparison](docs/internal/normalized-prior-backend-comparison.md)
initially meets diagnostics in all four fits but retains one of 640 comparison
rows on its predeclared precision criterion. The separately frozen larger-budget
follow-up passes all 640 rows, closing that bounded same-target precision check.
The subsequent normalized-prior slice records warmup events on both routes
without changing retained draws. The next integration exposes chain summaries
through ordinary fit diagnostics and cache save/load. A separate warmup report
section now reaches structured/public/Markdown/table/bundle outputs. Shared
Markdown column order now survives report/dossier JSON reload. Broader sampling
acceptance, full sampler-failure handling and other presentation limits remain open.
These corrections do not close M1.

#### Turing adaptation boundary, 2026-09-14

Auditing the missing Turing warmup telemetry exposed a control defect first:
`NUTS(-1, ...)` let Turing choose adaptation length from `ndraws`, while
`num_warmup` did not override that length. The initial state also occupied one
discarded row, so the previous discard count could retain adapting transitions.
With six retained draws, requests for 0, 1 and 8 warmup iterations all used
three adaptation transitions. The zero/one cases retained three adapting rows
while reporting `is_adapt = false`.

The adapter now sets `NUTS(warmup, ...)` and excludes the initial state plus
all `warmup` transitions. Fit metadata and cache request identity include the
explicit `nadapts` count, including zero. Old Turing caches remain manually
readable but cannot be automatically reused for the corrected request. Their
unrecorded warmup history stays unavailable even for a zero-warmup request.
Re-estimation is needed to use the corrected schedule; seed equality with the
old defective schedule is not an acceptance condition. Likelihoods, priors,
AdvancedHMC and CmdStan sampling paths are unchanged. The [existing owner](docs/internal/normalized-prior-backend-comparison.md#turing-adaptation-boundary-2026-09-14)
records the reproduction and focused checks. The subsequent recording slice
below preserves this corrected schedule; neither establishes convergence.

#### Turing warmup event recording, 2026-09-14

Ordinary Turing fits now record chain-level warmup iteration coverage,
divergences, maximum-depth hits and nonfinite log densities through the existing
summary/cache/report path. Initial states and adapting draws remain excluded
from posterior output. The adapter temporarily buffers warmup transitions per
chain; only compact summaries enter the fit and cache.

Julia 1.10.8 passes 305 warmup assertions; Julia 1.12.5 passes the 146 Turing/
unavailable-history assertions. Recording on/off preserves retained arrays,
diagnostics and the subsequent RNG stream. Direct Turing references verify the
event counts at warmup 0, 1 and 8. Another 40 checks verify two actual corrected
pre-recording caches: unchanged keys/bytes, ordinary reuse, exact fresh draw
equality and recorded-summary reload. The existing 1,458 boundary/CmdStan
contract checks pass. Details and limits are in the [existing owner](docs/internal/normalized-prior-backend-comparison.md#turing-warmup-event-recording-2026-09-14).
Fit structs, cache schema, likelihoods, priors and other samplers are unchanged.
Random-walk recording is covered by the following slice; interrupted-chain
telemetry remains separate.

#### Random-walk warmup event recording, 2026-09-14

Ordinary `backend = :julia` fits now retain one nonfinite-proposal counter per
chain during burn-in. The existing warmup diagnostic, cache and report paths
expose these counts separately from retained iterations. NUTS event fields are
missing because they do not apply. There is no proposal-scale adaptation or
warmup draw buffer. Older positive-warmup histories remain unavailable;
known zero warmup reports zero proposal events and inapplicable NUTS fields.

Julia 1.10.8 passes 383 warmup checks; Julia 1.12.5 passes the 80 random-walk
checks. Controlled nonfinite proposals verify phase/chain separation, while
recording on/off preserves retained results and subsequent RNG values. Forty
checks on two actual pre-edit caches verify unchanged keys/bytes, reuse and
fresh retained-result equality. Another 1,717 boundary/CmdStan-contract and
report checks pass. See the [existing owner](docs/internal/normalized-prior-backend-comparison.md#random-walk-warmup-event-recording-2026-09-14)
for persistence/report checks and limits. These are implementation checks,
not statistical validation or independent review.

#### Fixed-coefficient unit-logit MFRM reference, 2026-09-14

The private `_MFRMFixedQReferenceLogDensity` removes all active log-loadings
and free log-consistencies from the parameter vector. Active Q loadings and
all rater consistencies are exactly one. Abilities, item locations, free rater
severities and free item steps use unit-logit coordinates. Dividing only those
locations/steps by 1.7 permits reuse of the unchanged production MGMFRM kernel;
the reference prior is explicitly defined on the reduced unit-logit vector.
No positive-transform Jacobian or prior for a fixed coefficient is added.

Julia 1.10.8 passes 844 density/measure checks. Julia 1.12.5 and CmdStan 2.39.0
pass 1,206, including 51 checks of the reduced Stan reference. The 2D pure/mixed
and 3D pure examples have 18, 18 and 26 free coordinates, versus 24, 25 and 34
in their generalized targets. Independent equations, unit-scale prior mapping,
gradients and per-dimension scalar PCM likelihoods agree. These are numerical
checks without sampling, recovery, convergence or scientific acceptance.

Fixed coefficients do not remove the location invariance
`theta[p, :] += c; item[i] += dot(Q[i, :], c)`. Proper free-coordinate normal
priors anchor these directions in this reference. One scalar PCM over
person-dimension IDs retains unfixed locations and is rejected by the existing
design validator; dimension-specific scalar comparisons verify conditional
likelihoods only, retaining the shared rater effects. Neither independent
univariate posteriors nor prior invariance under gauge changes is established.
The [existing owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-unit-logit-mfrm-reference-2026-09-14)
records the equation, prior/measure, native checks and remaining fit boundary.

#### Fixed-coefficient MFRM sampling and persistence, 2026-09-14

The private unit-logit reference now uses the existing AdvancedHMC and CmdStan
NUTS runners. Retained draws, parameter diagnostics and posterior intervals keep
the reduced names and units; fixed coefficients do not appear as sampled
parameters. A separate sample schema records the actual prior, coordinate
measure, prior-anchored location convention and design identity. Loading verifies
the canonical record and recomputes retained Julia densities; CmdStan output and
saved records also verify `lp__`, including the normalizing constants.

Julia 1.10.8 passes 214 new sampling/persistence assertions. Julia 1.12.5 with
CmdStan 2.39.0 passes 457. These cover 2D mixed-Q and 3D pure-Q short fits,
warmup recording, reduced summaries, reloads, model/scale mismatches and
preservation of existing files after rejected writes. The shared Stan response
function expands to the exact pre-change MGMFRM source. The [existing owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-mfrm-sampling-and-persistence-2026-09-14)
records regression checks and a separate-process saved-result check.

This closes private sampler/persistence wiring, not a public model selector,
convergence, recovery or independent scientific acceptance. The follow-up below
adds reconstructed results and interval figures. Public exposure still needs
coherent model, prior and result semantics.

#### Fixed-coefficient MFRM reconstructed results and figures, 2026-09-14

The private result now reconstructs every rater severity and item step from
each retained draw in unit logits. Existing constraint algebra, posterior
summary and MCMC diagnostic builders supply full-coordinate summaries, with
fixed coefficients/baseline steps excluded from convergence gates. The last
rater and last item steps remain uncertain derived quantities. The canonical
sample record and v1 schema are unchanged; loading rebuilds these views.

The private interval-figure adapter reuses the ordinary parameter/dimension
selection, interval calculation and CairoMakie renderer. Model/backend labels,
unit-logit location/step axes and dimensionless fixed-coefficient axes are
explicit. Figures retain whole-model warnings when a subset is selected.
Older Julia/CmdStan sample files can supply these figures without refitting.
The [existing owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-mfrm-reconstructed-results-and-figures-2026-09-14)
records tests, saved-file compatibility, PDF/SVG inspection and limits.

This completes private reconstructed summaries and interval figures. The
follow-up below adds retained trace/rank panels. Public model selection,
report integration, predictive figures and statistical validation remain open.

#### Fixed-coefficient MFRM trace and rank figures, 2026-09-14

The private diagnostic-figure adapter now reuses the existing trace/rank data
builder and CairoMakie renderer. Every retained iteration remains attached to
its original chain. Last-rater and last-item-step coordinates are explicitly
marked as derived and show their own R-hat and bulk/tail ESS. Fixed coefficients
and baseline steps show a fixed line and an inapplicability message instead
of a rank comparison. Whole-model warnings and per-chain sampler diagnostics
remain visible when selecting a subset or a named dimension.

Julia 1.10.8 passes 1,920 focused assertions, and Julia 1.12.5/CmdStan 2.39.0
passes 2,648, including existing public plot-data regressions. Old backend
sample files supply the new figures without refitting or changing the sample
schema. Model/backend labels and unit-logit versus dimensionless axes stay
explicit; unstored warmup parameter draws are not reconstructed. The [existing owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-mfrm-trace-and-rank-figures-2026-09-14)
records rendering checks, output inspection and their limits.

The conditional category predictive follow-up below reuses the same saved
results. Public model/result/report integration and statistical validation
remain separate handoffs.

#### Fixed-coefficient MFRM conditional predictive checks, 2026-09-14

The private reference now produces replicated ratings and category-proportion
figures from canonical saved results. It reuses the existing category generator,
check summaries and CairoMakie renderer. The likelihood-coordinate mapping
preserves unit logits; active Q loadings and consistency remain fixed at one.
Independent 2D mixed-Q and 3D pure-Q formulas check probabilities and their
agreement with pointwise log likelihoods.

All retained draws, sampled indices with replacement, and explicit ordered
indices (including repeats) are supported with a local seeded RNG. Selected
chain IDs and iteration numbers remain attached, and the whole-model diagnostic
warning survives draw selection. All declared categories stay visible, including
zero observed counts. Figure intervals summarize replicated proportions for
existing rating rows, persons, items and raters. They are pointwise intervals;
this same-data check does not establish convergence or new-facet performance.

The [existing owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-mfrm-conditional-predictive-checks-2026-09-14)
records Julia/CmdStan checks, old-result regeneration and visual evidence.
The result/report contract below now specifies the handoff. Its production
assembler and public model selection remain separate implementation steps.

#### Fixed-coefficient MFRM result/report contract, 2026-09-14

The private result/report handoff is specified against the existing code in
[its owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-mfrm-resultreport-contract-2026-09-14).
Reuse the full report payload and JSON/table/Markdown exporters through a
private assembler. Its model label is fixed-coefficient multidimensional MFRM,
with unit logits, exact prior/target/sample identity, free and reconstructed
summaries, both diagnostic tables, separate warmup coverage and conditional
predictive rows. The reused `:mgmfrm` storage spec must not imply estimated
coefficients or generalized raw-coordinate priors.

The compatibility probe identifies presentation gaps: nested model identity
and non-warmup section explanations are not rendered automatically; the public
projection gives the private status `unknown`; a report-only bundle cannot add
figures. Existing `complete` means no captured section errors, independently of
MCMC quality and unsupported capabilities. The owner defines the required core,
unsupported reasons and acceptance checks. A 62-assertion Julia 1.12.5 probe round-trips report/table drafts from both
old backend samples with nested-hash checks and no MCMC. No production report
constructor, public selector or new sampling study is added by this
specification slice.

The private assembler and presentation follow-up below implements this first
handoff. Staged figure-bundle integration follows the verified report rows.

#### Fixed-coefficient MFRM internal reports, 2026-09-14

`_mfrm_fixed_q_report` now assembles full internal reports from canonical saved
results using the existing section and export helpers. It preserves the actual
unit-logit model/prior/target/sample identity, free and reconstructed summaries,
both diagnostic tables, fixed/derived applicability, warmup coverage and one
conditional predictive check with its selection/seed. It names ten unsupported
sections with specific reasons. Canonical corruption remains fatal before error
capture; report-generation completeness is separate from support and MCMC quality.

Markdown now shows the optional identity fields, coordinate/conditioning
explanations, unsupported reasons and captured errors even with table previews
disabled. The [existing owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-mfrm-internal-reports-2026-09-14)
records checks and saved-result round trips. Public model selection, cache
conversion and public projection remain separate. The following figure-bundle
slice connects the three existing private figures to these report rows.

#### Fixed-coefficient MFRM report figures, 2026-09-15

`_save_mfrm_fixed_q_report_bundle` connects saved Julia/CmdStan samples to the
existing staged report/figure writer. Posterior intervals use the report's
central interval; prediction uses its exact category rows and resolved draw
selection. Whole-model diagnostics, fixed/derived coordinates, named dimensions,
backend and unit-logit labels remain present. Figure JSON includes target and
source-sample identity alongside the report hash. Existing bundle schema v2,
PDF/SVG/JSON exports and loader checks are reused.

The [owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-mfrm-report-figures-2026-09-15)
records saved-result replay, destination-preservation checks and PDF review.
The public model/result contract below now specifies the next implementation
steps. Numerical implementation checks do not close statistical acceptance or
the independent-reader walkthrough.

#### Fixed-coefficient MFRM public API contract, 2026-09-15

The [owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-mfrm-public-api-contract-2026-09-15)
specifies the proposed `family = :mfrm, dimensions >= 2, q_matrix = Q` request,
initially through `Experimental.fit`. It preserves scalar MFRM and estimated-
coefficient MGMFRM behavior. A dedicated result type will reuse common summary,
diagnostic, plot and report calls without admitting unsupported numerical
analyses through the broad fit union. Julia NUTS (`:advancedhmc`) remains the
default for the new branch, with CmdStan as the maintained alternative;
`:julia` keeps its existing scalar random-walk meaning.

The contract separates manual save/reopen from automatic request caching,
specifies source/target/report identity and a new-result cache envelope, and
traces a named-dimension report/figure workflow. Artifact and rating-design
adapters are required for experimental exposure; the other eight unsupported
report analyses may remain explicit limitations. A 71-assertion probe verifies
the current boundary using old samples without fitting or rendering; the
proposed selector and result type are not implemented by this specification.

The dedicated result adapter and canonical specification/identity are implemented
below. The complete experimental fit/cache/report workflow remains required
before exposing fitting. Statistical acceptance remains separate.

#### Fixed-coefficient MFRM result adapter, 2026-09-15

The private root type `MultidimensionalMFRMFit` owns a detached canonical sample
record and revalidates it on every read. Explicit `fit_metadata`,
`posterior_summary`, `direct_posterior_summary` and `diagnostics` methods preserve
unit logits, named dimensions, actual prior/target/source identity, fixed/derived
coordinates, stored diagnostic criteria and separate warmup coverage. Display
names the model and backend. Shared metadata assembly preserves existing private
reports. The [owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-mfrm-result-adapter-2026-09-15)
records validation and the remaining exposure requirements.

The type remains unexported without an `Experimental` alias. Its report/plot,
cache/artifact and comparison methods are not activated by this adapter. The
canonical specification/design/identity follow-up is recorded below.

#### Fixed-coefficient MFRM canonical specification, 2026-09-15

`mfrm_spec(data; family = :mfrm, dimensions = D, q_matrix = Q,
dimension_labels = labels)` now represents the fixed-coefficient model for
`D >= 2`. `getdesign(spec; preview = true)` compiles its free unit-logit
coordinates; constraints, prior rows, model-family contract and full/public
manifests identify fixed coefficients, prior-anchored locations and identity
correlation. The existing Q/coverage gates and warnings are retained. Its
canonical target identity is distinct from the legacy storage-spec identity;
the reference density and CmdStan input use the same unit-logit target.

Public fitting and automatic cache requests reject this branch before numerical startup.
Row-level predictor inspection also remains unavailable with an explicit
explanation. The [owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-mfrm-canonical-specification-2026-09-15)
records the checks and remaining workflow requirements. The private sampling
connection is implemented below; cache/report exposure remains subsequent work.

#### Canonical fixed-coefficient MFRM fitting and replay, 2026-09-15

The private `_mfrm_fixed_q_fit(spec; ...)` now connects the canonical
multidimensional MFRM specification to Julia NUTS by default and to CmdStan
when requested, returning `MultidimensionalMFRMFit`. Its v2 sample record stores
the MFRM spec, actual prior and canonical target identity. The existing private
writer/loader preserves that record and rebuilds metadata, free/reconstructed
summaries and diagnostics. Schema/family mismatches reject even after rehashing;
old v1 records retain their original family, identity and bytes. Numerical entry
revalidates the authoritative design and rebuilds derived target views.

Small two/three-dimensional Julia fits and a matched two-dimensional CmdStan
fit pass on the tested runtimes; both backends' target/prior and retained
log-density checks agree. This verifies operability, not convergence, recovery
or interval coverage. Public fitting and result report/plot dispatch remain
unavailable; manual cache/artifact support is recorded below. The [owner](docs/internal/normalized-prior-backend-comparison.md#canonical-fixed-coefficient-fitting-and-replay-2026-09-15)
records the runs, compatibility evidence and remaining exposure conditions.

#### Fixed-coefficient MFRM manual cache and artifact, 2026-09-15

Canonical `MultidimensionalMFRMFit` results now use `save_fit_cache` /
`load_fit_cache` with a dedicated v2 envelope and `fit_artifact(view = :full)`.
The existing atomic writer, artifact hashes and environment metadata are reused.
The fit's sample record remains the sole model/draw authority; loading rebuilds
and checks the artifact's model, prior, controls, source/target identity,
summaries, diagnostics and archive summaries. Saved environment metadata and
diagnostic settings survive replay. V2 integrity checks remain mandatory when
`verify_hash = false`; existing v1 cache behavior is preserved.

Legacy private samples retain their loader and cannot be silently imported into
the new cache. Automatic request caching, public fitting and result report/plot
dispatch remain unavailable. The [owner](docs/internal/normalized-prior-backend-comparison.md#manual-fixed-coefficient-cache-contract-2026-09-15)
records the contract and validation. The numerical reporting connection is
recorded below; no additional sampler or saved-result type is introduced.

#### Fixed-coefficient MFRM saved-result reports, 2026-09-15

Canonical results now support `fit_report`, `fit_report_public` and
`fit_artifact(view = :public)`. The dedicated adapter reuses the private report
assembler, adds validated rating-design rows and the existing full artifact,
and preserves actual priors, unit logits, named dimensions, fixed/derived
coordinates, stored diagnostic settings and source/target identity. Public
output was labelled experimental while fitting was unavailable at that step. Central
posterior bounds use the existing interval semantics; unsupported analyses and
captured errors remain distinct from MCMC warnings. Full v1 artifacts and
v1/v2 fit-cache meanings are unchanged. See the
[owner's verification](docs/internal/normalized-prior-backend-comparison.md#canonical-fixed-coefficient-saved-result-reports-2026-09-15).
The subsequent [figure handoff](docs/internal/normalized-prior-backend-comparison.md#canonical-saved-result-figures-2026-09-15)
connects posterior, trace/rank and conditional predictive figures and staged
full/public bundles. The [experimental fitting handoff](docs/internal/normalized-prior-backend-comparison.md#experimental-fixed-coefficient-fitting-2026-09-15)
subsequently connects the API and generic example. Individual
saved-result checks pass; the combined Julia 1.12 assertion drivers still exceed
the 600-second budget. Track that compilation cost separately and do not claim
a complete 1.12 matrix or full-suite pass.

### Model axes and staged scope decisions

The user's seven-point model review on 2026-09-11 and extension review on
2026-09-15 refine M1 and the long-term scope. Specify the following axes
separately for each proposed model, using the existing
[family contract](src/model_family_contract.jl), [equations](docs/src/model-equations.md)
and [experimental scope](docs/src/experimental.md). These are distinct decisions,
with support established per declared combination. Source reproduction and the
exchangeable-rater-prior model retain their parallel scientific roles; the
current raw-prior implementation remains a separately identified baseline.

| Axis | Current evidence | Required specification and completion condition |
| --- | --- | --- |
| Logistic scale constant | MGMFRM executes `1.7` in Julia and Stan; `1.702` is reference metadata. Stable MFRM and the implemented 2020 scalar GMFRM use unit scaling | Name the multiplier `c` separately from dimension count `D`. Retain literal `1.7` for source reproduction. Any alternative needs an explicit likelihood/parameter/prior mapping and versioned identity; changing the constant alone is not a precision fix or exact normal-ogive conversion |
| Coordinate measure and Jacobians | Current generalized priors are normal densities on raw coordinates; deterministic positive transforms require no extra Jacobian for that target | Complete the blockwise measure/transform specification below. Distinguish Stan's automatic parameter-constraint transforms from manual changes of variables and from transformations of already sampled variables. Check density differences and gradients in common coordinates, including constrained-vector reconstruction; backend agreement alone does not establish source-prior fidelity |
| Explicit ability vector and multidimensional MFRM | MGMFRM estimates every person's `theta[p,d]`. `family = :mfrm, dimensions >= 2` supports fixed-Q specification/design inspection, Julia/CmdStan fitting and manual v2 cache/artifact replay; experimental fitting now connects through `Experimental.fit`. MGMFRM `discrimination = :none` still estimates active loadings and rater consistency. Fixed-Q MFRM has a dedicated result adapter, reconstructed summaries and report/figure bundles with `a[i,d] = Q[i,d]`, unit consistency, unit logits and explicit free-coordinate priors | The experimental fit-to-report path and a generic two-backend example are connected. Retain the prior-anchored location convention and identity-correlation ability prior as restrictions; hard anchors or another prior require a separately specified target. Operability does not establish statistical acceptance |
| Confirmatory versus exploratory | Current Q zero locations are fixed and active positive loadings are estimated. An all-active Q is rejected by the duplicate-column gate | First retain named confirmatory dimensions for the matched comparison. Full source loading reproduction needs its own identification/alignment treatment. Exploratory discovery additionally needs admissible rotations, signs/permutations and interpretation checks; a dense Q or estimated nonzero loadings alone does not supply that workflow |
| Between-item versus within-item | One active Q entry per item gives between-item structure; multiple active entries give within-item structure. Admitted within/mixed designs are warning-bearing; the narrow evaluation candidate is between-item | Declare the tested Q geometry and person/item/rater coverage. Select within-item checks for named loading-direction or cross-loading questions; pure-item evidence cannot close them. Q acceptance and structural rank do not establish joint identification or recovery |
| Compensatory versus non-compensatory | The weighted ability sum permits conditional compensation on cross-loaded items; no nonadditive ordinal kernel is implemented | Describe the response equation separately from the source author's label and the user's decision rule. Retain additive algebra and exact tradeoff checks for reproduction. A non-compensatory response alternative needs its own probability equation and claim; do not infer it from between-item structure, category accumulation or rater product constraints |
| Correlated factors versus bifactor | Ordinary generalized fit fixes latent correlation to identity, with covariance `person_sd^2 I`. A research-only generalized two-dimensional free-correlation candidate exists. The separate fixed-coefficient 2D density has an explicit prior/transform contract and Julia/CmdStan numerical checks; its sampling/result integration is next. Bifactor-shaped Q can be admitted as a warning-bearing within-item design | Specify covariance restrictions separately from loading roles. Correlated factors need a reviewed correlation prior/transform and both fitting routes. Bifactor needs explicit general/specific roles, orthogonality or declared deviations, identification, score interpretation and recovery evidence. Neither identity covariance nor Q acceptance certifies bifactor support; posterior dependence is not the latent-population correlation |
| Q identification versus Q estimation | Current validation checks the supplied Q structure and coverage; MGMFRM estimates positive active loadings while structural zeros stay fixed. No ordinary route estimates Q itself | Distinguish identification of a fixed-Q model, estimation of its continuous loadings, and inference over zero/nonzero structure. Start with prespecified candidate structures and a fixed dimension count, then partially unknown Q and exploratory loading structures. Define scale, labels, signs/rotations and observational equivalence; structural checks alone do not establish identification. Preserve structural uncertainty in ability and predictive summaries |
| Configurable random effects | The current fitting families have prescribed person/item/rater blocks and priors. Additional cluster identifiers and residual summaries do not fit cluster effects or estimate arbitrary variance components | Add declared grouping factors, random intercepts, nested/crossed structures, then justified random slopes and covariance blocks. Specify fixed predictors, grouping units, pooling/hyperpriors, replication requirements and existing/new-level prediction. Start with reusable blocks rather than a universal formula parser; expose only implemented combinations and diagnose confounded effects |

The sampler-free 2026-09-11 inspection used nine items, three disjoint groups
of three, and Q columns for one general plus three specific factors. Each item
loaded on the general factor and its group's specific factor. Q validation
passed with structural rank four, but returned
`guarded_generic_fixed_q_review_required` and cross-loading/no-pure-item
warnings. The preview retained eight ability coordinates for two persons.
This establishes representation and guard behavior only; no posterior fit,
Stan compilation, bifactor identification or scientific validation was performed.

**Next bounded deliverable:** connect the private two-dimensional correlated
fixed-coefficient target to Julia/CmdStan sampling and a separately identified
sample/reconstruction record. The [density contract and checks](docs/internal/normalized-prior-backend-comparison.md#correlated-fixed-coefficient-density-2026-09-15)
retain the independent model's likelihood and other priors. Reuse the existing
samplers and persistence primitives; verify the correlation coordinate, retained
densities, telemetry and reload identity under short operability controls.
Keep public fitting guarded until its result/report path is checked. Statistical
acceptance, automatic request caching and hard anchors remain separate.
The warmup recording slices above are verified. Interruption-time histories
remain unavailable; adding them is deferred until a concrete failure-diagnosis
need warrants it, while existing error and cache-preservation guarantees remain.
The [figure/report integration](#report-bundle-figure-integration-2026-09-14)
and [public documentation cleanup](#public-documentation-cleanup-2026-09-14)
are verified. An unfamiliar-reader walkthrough remains pending independently;
automated checks do not establish reader usability or block Julia core work.
The [cache-compilation follow-up](docs/internal/normalized-prior-backend-comparison.md#cache-record-compilation-2026-09-14)
isolates excessive specialization in two private persistence helpers and
preserves the serialized bytes. This closes that bounded diagnostic task;
broader M0 performance work retains its separate acceptance conditions.
The [precision follow-up](docs/internal/normalized-prior-backend-comparison.md#precision-follow-up-execution-receipt)
now passes all 640 comparisons and all four diagnostic gates with 6,000 draws
per chain (96,000 retained draws total), under unchanged criteria and new
predeclared seeds. The initially held R2 consistency quantile has an
error-inclusive difference bound of 0.09935 posterior SD in the follow-up,
below 0.3. Preserve the first trial's separate 639/1 unresolved receipt;
no cutoff changed and no draws were pooled. The preceding hash improvement
also preserves existing records while removing the measured save/load delay.

The private normalized-prior sampler now records warmup telemetry by default
on Julia and CmdStan. Its version-2 sample records preserve chain/iteration,
divergence, depth and nonfinite-log-density events; version-1 records remain
readable with explicit unavailable coverage. Matched short fits verify exact
retained-draw and diagnostic equality with recording enabled/disabled under
both priors and backends. The earlier 96,000-draw comparison also reloads and
reproduces all 640 decisions unchanged.

Ordinary AdvancedHMC, Turing and CmdStan fits now record compact
chain-level warmup summaries. `sampler_diagnostics(fit; phase = :warmup)`
selects them, while its retained default and posterior convergence diagnostics
stay unchanged. All three fit structs and the v1 cache schema retain their
layouts; summaries travel in the existing sampler metadata. New caches retain
the summaries and old caches report unavailable coverage. Generalized fits
retain AdvancedHMC/CmdStan support. Random walk still has no positive-warmup
telemetry in this interface.

`fit_report` now includes these summaries automatically in a separate `warmup`
section. The section has explanatory text, no adaptation pass/fail cutoff, and
no effect on retained diagnostic flags. Its Markdown columns are fixed across
in-memory and JSON-loaded reports. Existing report readers/exporters carry the
new section; older reports without it retain their saved contents and hashes.

The shared Markdown resolver now orders identifiers, sampler coverage,
estimates and uncertainty consistently and sorts remaining columns by name.
This covers full/public reports and dossier tables without a renderer per
section or a serialized schema migration. Existing row values, public-language
filtering and hash meanings are preserved. Column stability does not promise
identical whole-Markdown bytes: JSON reload can render `1.0` as `1`, and full
typed artifact hashes differ from JSON-normalized public-report identity.
See the [bounded handoff](docs/internal/normalized-prior-backend-comparison.md#next-bounded-work).
The subsequent failure audit confirms that mid-chain AdvancedHMC exceptions
do not return or cache partial fits for all three families, and failed refreshes
preserve existing cache bytes. The same existing control flow is retained;
131 added fault assertions cover the delayed Julia/cache cases and CmdStan's
second-chain command failure. `sampling` remains the reported stage when the
library exception cannot identify a warmup/retained iteration.
Julia remains primary, with CmdStan as its same-target counterpart. Public
prior selection, existing `GeneralizedPrior` caches, broader statistical claims
and the application remain unchanged. Retain the
[other failure boundaries](#first-julia-core-verification-slice); no Uchihara
preprocessing or new statistical validation roster is required for this handoff.

#### Long-term extension sequence

The near-term completion target remains a reliable Julia workflow for a
declared model/design domain, with matching CmdStan evidence. The long-term
target expands that domain along the axes above. These extensions do not all
have to finish before the current foundation can be accepted. Follow this
implementation sequence; specification of independent later branches can
proceed when it resolves a concrete model question. Non-compensatory models
and Q structure inference are separately prioritized branches; neither requires
the other to be implemented first. Fixed-Q identification and candidate
comparison can advance with the current additive model.

| Order and purpose | Bounded deliverable | Evidence and user-facing completion condition |
| --- | --- | --- |
| 1. Finish the existing foundation — make an estimated ability vector reusable | Expose restricted experimental fitting on the implemented canonical fixed-coefficient result, cache, full/public report and named-dimension figure path. Preserve existing MFRM/GMFRM/MGMFRM meanings and v1/v2 records | Same model, prior, diagnostic settings, selected dimensions and intervals survive Julia/CmdStan save/reload and report/figure export. Complete target-specific validation and reader review for the advertised scope; short fits establish operability only |
| 2. Correlated dimensions and within-item validation — distinguish related abilities and cross-loaded items | Reuse the correlation candidate for a declared fixed-Q model, initially two dimensions, then verify higher-dimensional covariance without making two traits a permanent API limit. Evaluate between-item, within-item and mixed Q separately. Change covariance and loading structure in separate contrasts; specify bifactor roles/constraints as a distinct extension | Recover ability, loading and population-correlation uncertainty under selected correlation, Q and coverage conditions; assess prior sensitivity and confusion between cross-loadings and correlations. Deliver correlation intervals/figures and named loading/ability summaries. Bifactor additionally requires general/specific score interpretation and its own recovery evidence |
| 3. Configurable random effects — represent dependence at the actual grouping units | Begin with one justified extra grouping block and an estimated variance/hyperprior, e.g. task or recording. Extend the same design representation to nested/crossed intercepts, then predictor-specific random slopes and selected covariance blocks. Distinguish a modeled effect from an identifier retained only for reporting | Use replication/overlap conditions that can separate the effects; test weak/near-zero variance, omitted effects, shrinkage and confounding with abilities or facet severity. Deliver effect/variance/covariance summaries and plots. Define conditional existing-level and integrated new-level prediction separately; expose each only when implemented and checked |
| 4. Non-compensatory response models — test a different ability-to-response mechanism | Select one scientifically justified ordinal response equation first; define category probabilities, thresholds, rater effects, scale/prior measures and its unidimensional behavior. Preserve the additive model as an explicit alternative with a distinct target identity | Verify normalized valid probabilities, intended monotonicity and the stated compensation behavior. Use known-truth fits under both generating mechanisms to assess ability/decision calibration and predictive discrimination. Report dimension-conditioned response surfaces; an operational pass rule or author label does not define the response kernel |
| 5. Q structure inference — quantify uncertainty about what each item measures | First improve fixed-Q identification explanations and compare a bounded, prespecified set of candidate Q matrices at a fixed dimension count. Next allow selected unknown cells with declared structural priors, then exploratory loading/rotation policies. Selection of dimension count is a separate decision | Check distinguishable/equivalent structures, weak cross-loadings, incorrect Q and sparse coverage; assess structure recovery and ability/interval calibration with alignment appropriate to the model. Report candidate support or cell-inclusion probabilities only for the implemented inferential method, plus loading/structure figures and sensitivity to Q. Conditional-on-Q results must remain labelled; selecting one Q does not account for structural uncertainty |

For Q inference, estimating continuous loadings under fixed zeros is not
estimating the zero pattern. Stan cannot directly sample discrete parameters;
its [latent-discrete guidance](https://mc-stan.org/docs/stan-users-guide/latent-discrete.html)
describes marginalization where feasible. Choose a bounded candidate comparison
or a tractable marginalization before promising a shared unknown-Q posterior.
Record the structural prior, computational limit and uncertainty calculation.
A continuous relaxation has its own target and cannot silently replace a binary
Q model. Julia may use a different algorithm, but the maintained CmdStan
comparison must address the same declared model and inferential quantity.

Flexible random effects means supported blocks can be combined with explicit
meaning and usable syntax. It does not imply every grouping, slope and covariance
combination is identifiable. Explain grouping levels, fixed versus varying
coefficients, scale constraints and insufficient replication before fitting.
Record which facet or ability scales remain fixed for identification when
other variances are estimated;
report unresolved confounding rather than treating sampler convergence as proof
of separation. Reuse existing facet/design structures where they suffice, and
introduce a compact public specification only with the first working block.
Criterion-specific raters, recording effects and phonetic predictors can motivate
a reusable block, but no application-specific schema or arbitrary formula
language is required in advance.

For each extension, the completion evidence must connect the user's question
to the chosen data/design conditions, the quantities checked and the answer:

- State the response equation, dimensions/Q, covariance/effect structure,
  identification constraints, scale constants and priors/Jacobians. Record
  supported combinations in the existing model/surface contract; a change to
  the statistical target has an explicit identity.
- Check Julia probabilities, densities and gradients against independent
  equations and the matched CmdStan implementation. Compare diagnostic-qualified
  posterior/predictive results with Monte Carlo uncertainty; neither matching
  backends nor more local test assertions establishes statistical validity.
- Use a reviewed, bounded known-truth design selected for the claimed mechanism:
  recovery, interval coverage, failures, misspecification and prior sensitivity.
  Retain failed attempts and state whether evidence supports, narrows or leaves
  the intended domain unresolved. Require fresh interaction checks when combining
  independently validated blocks; avoid an automatic full Cartesian experiment.
- Complete fit -> diagnose -> interpret -> visualize -> save/reload using the
  existing result/report/figure path. Include model-specific uncertainty plots,
  declared prediction targets, reproducibility metadata and compatible saved
  records. Check clear README/help/examples with an unfamiliar reader; users
  should not reshape MCMC draws or interpret internal development stages.

Julia remains primary throughout. Each promoted extension retains the
two-backend requirement; an unavailable CmdStan counterpart remains an explicit
incomplete item, not a reason to substitute another model. This sequence does
not launch research runs, select numerical defaults or relax existing release
conditions. Uchihara and external-software comparisons exercise the relevant
supported slice; they do not define completion of the foundation or every
extension.

#### Shared specification and prediction contract

Extend `FacetData`, `mfrm_spec`, the existing model/surface contracts and saved
results only as the first relevant model block is implemented. These requirements
define observable API behavior, not a new generic registry or a promise of
particular keyword names. A workflow sketch using a future `spec` is not a
currently executable example: preserve the documented `fit` versus
`Experimental.fit` boundary until that family is deliberately exposed.

| Concern | Required behavior | Smallest meaningful verification |
| --- | --- | --- |
| Observation and grouping units | Distinguish the response event, criterion, physical item, person, rater and optional response/recording group. Preserve a physical item's identity when measurement items are item × criterion. Declare outcome-specific uniqueness keys, category direction and missingness/inclusion rules | Pure row permutations and consistent level relabelling preserve aligned probabilities under explicit parameter/prior/reference mappings. Joining recording-level features cannot multiply observations; accidental duplicates are rejected under the declared event key. Repeated events remain representable with explicit IDs; missing outcomes are not replaced by the lowest category |
| Effects and covariance | Specify which coefficients are fixed, estimated, shared across criteria or varying by group; record pooling, variance priors, scale constraints and the level of each covariance. Separate person-population correlation from shared-response dependence and posterior draw correlations | Check a minimal crossed/nested example and a deliberately confounded design. Verify known invalid structures fail before sampling; report unresolved identification limits. Fixed loadings/consistency are removed from sampled coordinates; a zero prior SD does not substitute for a fixed coefficient |
| Predictors and transformations | Record each predictor's grouping level, coding, units, centering/scaling, missing-data treatment and criterion-specific effects. Retain transformations in the fitted specification and cache. Word/item-level predictors require a separately identified hierarchical effect or explicit constraint | Reproduce fitted predictions after reload and on transformed new rows. Detect redundant predictor/effect columns. During heldout evaluation, estimate transformations and any imputation from training data only. Explain whether person traits are total or conditional on the included predictors |
| Comparison and prediction | Name the outcome, evaluation population, heldout unit and information available at prediction time. Separate predictions conditional on estimated existing levels from predictions integrating effects for new levels. Record which model block changes and which settings/data stay matched | Keep all criteria and raters for one heldout recording in the same split. Integrate its unknown effect when predicting a new recording; observed heldout ratings may be used only for a separately declared prediction task. Compare models on the same eligible observations with explicit scale/prior mappings and Monte Carlo uncertainty |
| Saved results, capability and errors | The specification, backend, summaries, reports and plots must agree on fitted effects, dimensions, transformations, prediction target and experimental status. Use the existing artifact/report identities and compatible readers | Reload and regenerate the same named summaries/figures on both backends. Unimplemented covariance, effect, predictor or prediction requests fail explicitly; do not silently use independent dimensions, ignore columns or omit uncertainty. Extend automatic cache keys only when that model's automatic caching is implemented |

Use synthetic examples with generic person/item/rater/group names for these
checks. The Uchihara data shape is a later application of the same contract.
For a composition such as correlated traits plus recording effects, test their
separation jointly before advertising the combination; passing each block's
isolated tests is insufficient. Retain the existing practical-acceptance and
independent-review requirements without making every future combination a
prerequisite for an ordinary implementation correction.

### Julia and CmdStan continuity and comparison

The user's 2026-09-11 decision is to retain both Julia and CmdStan estimation
as a continuing means of checking computational results. Julia is the primary
implementation and user-facing foundation; this priority does not retire or
indefinitely postpone the matching CmdStan route. AdvancedHMC is the
Julia comparison route for the current generalized models. CmdStan remains
optional for ordinary Julia installation and use. Carry each newly supported
core MGMFRM model through both routes; an implementation available on only one
route remains explicitly partial until the matching route is verified.

The two scientific models (source reproduction and exchangeable-rater prior)
and the two execution routes are separate choices. First resolve the
[blockwise specification](#blockwise-specification-and-comparison-contract),
then compare Julia and CmdStan within each accepted model and shared structural
scope. Backend switching must preserve the declared likelihood, prior measure,
identification constraints and model/scale interpretation in reports and artifacts.
Record the backend and sampler configuration in execution/cache identity,
separately from the model identity.

Reuse the existing target tests and paired-validation scripts in two stages:

1. At matched parameter points, compare log-density differences, Jacobians,
   gradients and response probabilities in a common coordinate measure, with
   declared numerical tolerances. Shared helpers or fixtures can share errors;
   retain source-equation and independently derived checks as well.
2. In a scoped, authorized fitting comparison, use the same data and accepted
   model, assess each route's chain diagnostics, and compare declared posterior and
   predictive summaries with Monte Carlo uncertainty. Independent runs need
   not produce identical draws. Select representative conditions and retain
   failures; do not automatically double the entire evaluation roster.

Both routes must feed the same user-facing diagnostics, figures and saved
reports. Keep differences in installation, cache reuse and chain execution
visible in public backend help. Agreement strengthens implementation evidence;
it does not establish model adequacy, source reproduction or independent
scientific review. ConQuest/TAM comparisons remain a separate exercise in
matching supported response models, scales and estimands across estimators.

Core backend verification must use controlled numerical and synthetic cases
without depending on the Uchihara workbook or an empirical conclusion. Complete
model-equation, category/sign, prior-predictive and common-coordinate checks
before interpreting posterior agreement. Keep observation and prediction units
explicit in likelihood/report output and verify save/reload and figure output
from both routes. When the Uchihara application is undertaken, apply the same
checks to its named empirical comparisons and distinguish rating-level likelihoods
from heldout-recording predictions. The current CmdStan path does not reuse compiled-model caches
and does not wire `cached_fit` or parallel chain execution into the fit path;
document the current requirements and resolve a measured execution blocker
with the smallest existing-path change. A new general cache/scheduler framework
or the historical M0 benchmark investigation is not a prerequisite.

### ConQuest and TAM comparison scope

External measurement-software comparison and same-model backend verification
answer different questions. Retain three separate evidence levels: matching
response equations/parameter meanings; numerical implementation agreement;
and recovery, calibration or practical validity under a declared design.

| Comparison / responsible role | Current evidence | Next deliverable and claim limit |
| --- | --- | --- |
| ConQuest — analyst/maintainer | The [bridge](docs/src/mgmfrm-research-roadmap.md#migration-evidence-and-deferred-contracts-retained-2026-09-14) has version-specific execution records and source-gauge semantic reconstruction for ConQuest 5.47.5, three-category unanchored MFRM RSM/PCM. Destination-gauge alignment and numerical comparison remain unavailable | Finish one unanchored common-model path: map category/step meanings, signs and identification constraints, check probability-preserving translation, assess external convergence, then compare declared estimands. Keep unsupported versions, anchors and broader models explicit; a returned bundle is not direct posterior agreement |
| TAM — analyst with independent review | The [retained comparison](test/fixtures/mgmfrm_tam_direct_agreement_multireplication.json) contains ten selected unidimensional MFRM/PCM jobs, five each at 40 and 100 persons; the primary 100-person comparison gate passed. Despite the `mgmfrm_tam_*` prefix, GMFRM/MGMFRM were not evaluated | Resolve the [review packet's](test/fixtures/mgmfrm_tam_direct_agreement_post_execution_review_packet.json) outstanding independent review/re-execution and pre-execution packet lineage discrepancy without rewriting frozen evidence. Describe the tested family plainly. A future multidimensional comparison first needs a common fixed-loading/scoring model and explicit estimator/scale mapping; historical MFRM results cannot transfer to it |

For these comparisons, distinguish the external marginal maximum-likelihood
estimand from this package's joint Bayesian target, including prior and
uncertainty interpretation. Do not require identical estimates, equate standard
errors with credible intervals, or call interval inclusion coverage. General
ConQuest/TAM multidimensional capability is not proof that the exact proposed
MGMFRM is available there. This supporting work does not replace core model
specification or block unrelated MGMFRM implementation.

### Core equation and prior review

Read [Uto (2021)](https://doi.org/10.1007/s41237-021-00144-w), Sections 5--6.5
and the Appendix 1 code on printed page 451 (PDF page 27), using indexed text,
publisher-rendered equations and the rendered local PDF. This is a focused
equation/implementation review, not a new full-paper empirical replication.
The compensation/structure follow-up also reads the [published Stan code](https://github.com/AI-Behaviormetrics/Multidimensional-GMFRM/blob/master/mult_gmfrm_uto.stan)
and the Bolt and Lall (2003) equations from Zotero (item `Y2GABZ6D`);
the Uto PDF is Zotero item `38TX837G`. The initial Yao and Schwarz abstract
check is now supplemented by the [full-text review below](#yao-and-schwarz-full-text-review-and-adoption-limits).

| Finding | Evidence and consequence |
| --- | --- |
| Response equation agrees within the fixed-Q restriction | `_mgmfrm_source_linear_predictors!` and `src/stan/mgmfrm.stan` use the weighted ability sum, subtract item difficulty, rater severity and item steps, and multiply by `1.7 * rater_consistency`. The zero first logit removes a category-common term and preserves probabilities. This does not validate unrestricted loadings, free correlations or practical recovery |
| Source terminology conflicts with conditional algebra | Uto calls the model non-compensatory; [Yao and Schwarz (2006)](https://doi.org/10.1177/0146621605284537), p. 470, explicitly treats compensatory models, and Equation 4 plus the p. 491 dot-product note establish additive ability aggregation. Uto Equation 6 and Appendix 1 admit exact ability tradeoffs at fixed item parameters. The [focused operation/structure review](docs/src/experimental.md#dimension-aggregation-and-item-structure) separates the dimension dot product, category-step sums and rater product-one constraint. Preserve author terminology as attribution, not a model-behavior claim; do not silently substitute a nonadditive kernel |
| Source within-item structure is not the narrow between-item candidate | Appendix 1 estimates positive loadings in every item-dimension cell without a Q mask. For more than one dimension this is within-item, irrespective of how small some loadings are. The package's pure-Q branch is a restriction; its mixed/within fixed-Q branches remain warning-bearing. Compensation and item structure are separate axes, and source-like unrestricted loading identification remains open |
| Prior equivalence is not established by matching scales | Appendix 1 applies the severity normal density to the complete constrained vector; `_source_fixture_logprior` penalizes only the free coordinates. The [existing prior-asymmetry analysis](docs/internal/archive/roadmap-2026-09-05.md#fixed-q-identification-priors-and-nested-comparison-program) remains applicable, not a newly discovered mathematical issue. The manual calls its all-one setting `unit_raw_prior`, not a reproduction of the source prior. The [decision draft below](#m1-prior-measure-and-identification-decision-draft) also derives the source consistency prior's nonzero log-coordinate mean after the positive-to-log change of measure; source fidelity and exchangeability are different targets |
| Rater relabeling changes the implemented posterior target | The new deterministic block in [generalized_prior.jl](test/generalized_prior.jl) swaps R1/R3 on the same 24 ratings, including an all-1 rater. In separate severity and log-consistency cases it maps `(s,s,-2s)` to `(-2s,s,s)`: matched pointwise likelihoods agree, but the raw log-prior and unnormalized log-posterior each change by `-1.5`. At the zero vector the difference is zero, so it is not an additive normalizing constant. The coordinate permutation has unit absolute Jacobian. This is a density counterexample, not a measured posterior-mean or decision shift |
| Actual ability-prior scale reporting corrected | The no-fit `GeneralizedPrior(person_sd = 2)` counterexample exposed a hard-coded standard-normal claim. The [reporting correction](#actual-prior-reporting-correction) now resolves actual SD across shared consumers and leaves absent-prior checks unrecorded. This repairs metadata, not the numerical prior or scientific identification |
| Rater-report integration is incomplete | `rater_diagnostics` has MFRM/GMFRM methods but no `MGMFRMFit` method. MGMFRM direct posterior and residual infrastructure already exists; the missing convenience report is not absence of severity/consistency estimation. Reuse it after the prior/scale interpretation is explicit, without importing MFRM-only infit/outfit or automatic rater rejection |

**Next decision slice:** with actual-prior reporting corrected below, review
the [prior-measure and identification draft](#m1-prior-measure-and-identification-decision-draft), distinguishing a
constrained normal kernel scale from a desired
direct marginal SD. [Stan's transform reference](https://mc-stan.org/docs/reference-manual/transforms.html)
describes orthonormal zero-sum coordinates and the marginal-variance adjustment;
it is an alternative to evaluate, not a new dependency or an adopted model.
Any numerical replacement requires explicit prior/scale semantics, matching
Julia/Stan targets, cache compatibility and sensitivity checks. Do not silently
change defaults, rescale old draws, rewrite historical fixtures, or treat this
relabeling test as proof of scientific acceptability.

For the all-1 scenario, a low consistency multiplier at fixed finite remaining
parameters flattens category probabilities; it does not specifically encode
always selecting the minimum category. This follows from the implemented
softmax equation. Severity, consistency, item/person assignment, Q support and
prior influence must be examined jointly; no fitted reliability state or
automatic exclusion rule was added.

Verification on 2026-09-07: the existing generalized-prior file passes 73
prior-contract plus 14 relabeling-characterization assertions on Julia 1.12.5
and 1.10.8 (final quiet logs `xrYCu4` and `HIeIUZ`). The existing structural-Q
and model-family files pass 46 + 75 assertions on Julia 1.12.5; the same no-fit
check records the scale-report mismatch and missing MGMFRM rater method
(`ofTmV5`). These are implementation checks, including existing prior-predictive
test draws, not posterior fits, practical validation, or new CI results.
Package source, Stan kernels, priors/defaults, locks and historical evidence
remain unchanged by this review.

The compensation/structure follow-up passes all 75 existing model-family
assertions plus 14 new deterministic assertions on both Julia 1.10.8 and 1.12.5
(quiet logs `a9PDjS` and `M1eVOP`). These check the full three-category vector
for two raters and three ability tradeoffs, a nonzero step and nonunit rater
multiplier, pure-item negative controls, and a finite high-ability example.
The Stan comparison is a source-code review, not a new Stan execution or
cross-backend sampling result. Only this roadmap, the existing experimental
manual and the existing model-family test file change in this follow-up;
the actual-prior reporting correction was the next implementation slice and
is recorded separately below.

### Actual-prior reporting correction

The shared ability-prior metadata now uses the target/fit's `person_sd`.
SD 1 retains the existing standard-normal label; other SDs report a normal
prior with the numeric SD, zero mean, independent dimensions and fixed-prior-
hyperparameter conditioning. Without a supplied prior, scale and pass status
are missing rather than certified. This is not posterior covariance or an
identification proof. Stored sampler diagnostics, target pointwise checks,
full/public diagnostics, artifacts and reports use the same resolver; readers
do not trust stale stored scale rows over `fit.prior`. The research generator's
shared-row call and preview fields were updated, but it was not executed.

Design/source-reference prior and gauge declarations remain unchanged because
the design manifest participates in existing cache keys. Artifacts and report
Q sections label those declarations separately from the resolved fit prior.
The validation protocol's three current regimes all specify `person_sd = 1`,
so its standard-normal reference scale is not a nondefault-fit report. Its
`source_aligned` regime name still does **not** establish full source-prior
equivalence; reconcile that terminology with the next M1 prior decision.

Verification: [generalized_prior.jl](test/generalized_prior.jl) passes 144
assertions on each of Julia 1.12.5 (`uhzelZ`) and 1.10.8 (`BAiuzI`): 87 existing
plus 57 sampler-free reporting assertions, covering SD 0.5/1/2, unknown/stale
metadata, both reader views and artifact hashes. The new checks use fixed
numeric matrices, not posterior sampling; existing prior-predictive checks
remain. The numerical target, prior defaults, cache implementation, design
manifest and historical fixtures are unchanged. No MCMC, Stan execution,
fixture regeneration or CI was performed, and M0/M1 acceptance remains open.
On Julia 1.12.5, fixed-Q and model-family tests also pass 46 + 89 assertions;
the updated generator parses without execution and the changed manual passes
its language check (`tG1FT4`). An additional public-language check found
pre-existing README wording at
lines 321, 323, 331 and 337; README is unchanged by this correction, so that
repository-wide gate is not claimed as passing.

### Yao and Schwarz full-text review and adoption limits

[Yao and Schwarz (2006)](https://doi.org/10.1177/0146621605284537), pp. 469--492,
was read in full, including the appendix, from Zotero item `58X8E8BK`
(PDF attachment `KJDEPPHP`). Key equations were checked in rendered pages;
the indexed-text response stopped before the end, so the remaining pages were
read from the PDF. This is a source review plus local algebra checks, not
BMIRT reproduction, Stan execution, new package regression coverage, or
independent scientific acceptance. The consequences below are our analysis;
they do not assert that every source statement has been validated.

| Topic and source location | Finding and required M1 treatment |
| --- | --- |
| Aggregation and likelihood, Equations 4, 7, 9; p. 491 note | The dot product sums loading-by-ability products. The category-indicator product selects the observed category, and the person/item products form the joint likelihood. None is a product of dimension-specific success probabilities. Keep source attribution, conditional compensation, within/between structure, and practical decision rules separate in the existing contracts/reports; an unresolved operational label must not hide the proven conditional tradeoff |
| Structure and source mapping, pp. 471, 480, 490 | The demonstrated exploratory model does not impose simple structure; it is not validation of the package's pure-Q branch. Map Yao's category logits to Uto's rater multiplier, item difficulty and centered steps, including the explicit `1.7` scale. Yao allows item-specific category counts and has no rater facet in this kernel. Matching this conditional response family is not full-model, prior, mixed-format, or software equivalence; BMIRT/Metropolis--Hastings is not Stan |
| Conditional information, Equations 24, 48--50 | With other parameters fixed, `I_j = Var(Y_j \| theta) a_j a_j'` has rank at most one. For MGMFRM, the corresponding item/rater contribution is `(1.7 alpha_r)^2 Var(Y_ir \| theta, phi) a_i a_i'`, where `phi` fixes item/rater/step parameters. Repeated ratings in the same loading direction can add precision but not new ability directions. Assess loading directions, weak dimensions, and the summed information spectrum over the declared ability region; conditional full rank is not proof of joint item/rater/ability identification |
| Information versus uncertainty, Equations 49--55 | For unit direction `u`, distinguish `u' I u` from `1 / (u' inv(I) u)`. The latter requires a nonsingular matrix and is a local covariance-based approximation with nuisance item/rater parameters fixed, not the joint Bayesian posterior covariance. Name the estimand, conditioning, ability units and uncertainty source. Do not hide singularity with a prior or numerical ridge and report it as likelihood information |
| Identification and priors, pp. 472, 480 | Fixed population covariance does not generally remove likelihood rotation ambiguity. For identity covariance, jointly rotating abilities and loadings preserves their dot products and the ability-normal kernel; small rotations can preserve positive loadings. Loading priors need not be rotation-invariant, so do not infer full-posterior invariance. Review rotation, admissible sign/permutation changes, Q restrictions, transformed-prior measures and report alignment together. Interpret Equation 75's prior scale on the log scale; source-looking scale values do not establish source-posterior equivalence |
| Boundary raters and diverse user decisions | The variance in the information formula is model-implied, not the observed within-rater sample variance. An all-1 rater is not automatically zero-information, unreliable, or removable. Evaluate joint severity/consistency uncertainty, overlap, prior sensitivity and posterior predictions. Separate dimension-specific ability, declared composite scores and joint threshold-event probabilities according to use; a compensatory response kernel does not force a compensatory operational decision rule |
| Source corrections and optional statistics, Equations 47, 61, 65 | Equation 47's intermediate sum omits a minus sign; its final Hessian and Equation 48 agree with re-derivation. The 3PL claim in Equation 61 does not generally hold with positive guessing. Equation 65 supplies a stationary-point condition, not a sufficient global-maximum check. Retain these as review findings, not copied formulas. New 3PL or MID implementations are deferred unless a selected user-facing quantity requires them |
| Model comparison, pp. 480--481 and Appendix Equations 78--82 | The application fixes candidate correlations and counts examinee parameters in its fit-statistic calculation. Do not inherit its AIC parameter count, ordinary chi-square reference, trace-based convergence assessment or iteration budget as package acceptance rules. Predeclare conditional versus integrated prediction, heldout units and target population, check applicable regularity/diagnostics, and assess predictive performance separately from ability/decision calibration |

The full-text review's deterministic examples are reproducible mathematical
checks, not fitted results: for `I = [2 1; 1 2]` and `u = [1, 0]`, the two
information quantities are 2 and 1.5. With 3PL slope 1, location 0 and guessing
0.2, information is `0.1666667` at location 0 and `0.1703856` at its maximizer
near 0.267142, contradicting Equation 61's general claim. With ordinal slope
1 and adjacent thresholds `(-4, 4)`, logits `(0, theta + 4, 2theta)` give
information about 0.0353368 at the stationary point 0 but 0.2503353 at 4;
the center is a local minimum. These examples do not invalidate the correctly
derived M-2PPC response kernel or justify adding a 3PL branch to MGMFRM.

**Proposed stress extension, not an executable roster:** use a small set of
contrasting loading geometries (separated, nearly parallel, weak, and
rank-deficient), distinguish pure/within/mixed Q support, and examine dense
versus sparse overlap and regular versus boundary response patterns. Reuse
the existing [Q-design program](docs/src/mgmfrm-research-roadmap.md#v012-fixed-q-dimensionality-and-q-validation-expansion)
and [response-stress primitives](src/mgmfrm_response_stress.jl); the latter
currently generates a two-dimensional pure-Q design, not these new within-item
cells. Do not silently expand it into a full Cartesian experiment. Select cells
by the failure mechanism and decision they test, retaining rank-deficient
negative controls and separate misspecification/contamination outcomes.

Before M2, fix the needed model restrictions and estimands, make the relevant
algebra checks executable in existing focused tests, then specify per-cell
recovery/coverage, joint-posterior uncertainty, prediction/calibration,
practical loss and failure denominators. Eigenvalue/conditioning summaries
depend on the declared scale; no universal practical cutoff, replication count
or resource budget is adopted here. Review and size the selected cells before
authorizing any fresh evaluation. This planning refinement changes only this
roadmap and leaves the previous test receipts and all execution gates intact.

### M1 prior-measure and identification decision draft

**User-selected research priority on 2026-09-07: treat literal source
reproduction and an exchangeable-rater-prior model as parallel, distinct
scientific models.** Neither is merely a sensitivity setting subordinate to
the other. This selects their research roles, not a new implementation,
default prior, fitting scope or experiment authorization. Retain the current
raw-coordinate prior as the compatibility baseline; it is not silently renamed
as either model. Do not reinterpret `GeneralizedPrior` scales or relabel old draws.

The latest 2026-09-11 clarification prioritizes the Julia core prior/measure
contract independently of the Uchihara application. This section supplies the
derivations for the distinct source/exchangeable models and compatibility checks.
Completing unrestricted Uto reproduction is not a prerequisite for a bounded
core correction. Using a source-derived prior in an adapted application model
remains a restricted comparison, not literal source reproduction. Numerical
prior choices still need explicit specification.

For a prior-only comparison, match the likelihood, Q restrictions, response
scale, data and prediction/decision targets, while retaining each model's
explicit prior measure. Comparing unrestricted source loadings with pure-Q
exchangeable loadings would confound prior and structure. A source-prior model
under a fixed-Q restriction must be labeled a restricted reference, not full
Uto reproduction. Full source reproduction retains its separate loading-scope
and identification requirements; the current guarded API does not supply it.
Scale matching is itself a scientific choice: shared numeric SDs need not
match marginal or contrast uncertainty. Report remaining differences explicitly.

The source check revisited Zotero Uto item `38TX837G`, rendered Appendix 1 on
printed p. 451 (PDF page 27), and the
[author's Stan file](https://github.com/AI-Behaviormetrics/Multidimensional-GMFRM/blob/master/mult_gmfrm_uto.stan).
The PDF declares positive free consistencies and reconstructs the **first**
rater's consistency by the reciprocal product. It applies lognormal densities
to the complete consistency vector. The repository copy omits the positive
declaration bounds; this review does not certify equivalent initialization or
execution. Our derivation below uses the PDF's positive-coordinate measure,
including its change to free log coordinates, not a new Stan run.

Let `n >= 2`, `P = I - 11'/n`, and `C = [I_(n-1); -1']`. Here `s_raw` denotes
the current free-coordinate SD, `tau` a normal/lognormal kernel SD, and `s` a
desired common constrained marginal SD. These are different definitions, not
interchangeable argument names; severity and log-consistency scales are separate.

| Prior option | Induced rater distribution and scientific consequence | Proposed treatment |
| --- | --- | --- |
| Current raw-coordinate baseline | Severity and log-consistency have zero mean and covariance `s_raw^2 C C'`; free marginal variances are `s_raw^2`, the last is `(n-1)s_raw^2`. For `n > 2`, arbitrary rater renaming is not prior-invariant | Compatibility baseline, separate from the two selected scientific models; preserve the relabeling counterexample |
| Literal source measure | Full-vector severity normal kernel gives covariance `tau^2 P`. Source log-consistency has that same covariance but mean `tau^2 (1/n * 1 - e_1)`, where `e_1` marks the reconstructed first rater | Parallel reproduction track; equal log marginal variances do not make this nonzero-mean prior exchangeable. Distinguish full reproduction from a Q-restricted reference |
| Exchangeable zero-sum proposal | For severity and log-consistency separately, `v = s sqrt(n/(n-1)) H z`, with `z ~ N(0,I)`, `H'H = I` and `H'1 = 0`, gives zero mean and covariance `s^2 n/(n-1) P` | Parallel scientific model for raters whose IDs carry no declared prior information; an alternative kernel-SD convention uses `tau H z`. The construction and scale convention still need acceptance before implementation |

The zero-sum covariance and marginal-SD adjustment agree with
[Stan's sum-to-zero transform reference](https://mc-stan.org/docs/reference-manual/transforms.html#sum-to-zero-transforms).
The basis is a coordinate choice, not an additional rater effect. Exchangeable
does not mean independent: pairwise correlations are `-1/(n-1)` under this
constraint. If a future scale is estimated rather than fixed, normalization
must account for `n-1` free dimensions; blindly summing `n` normal log densities
adds an erroneous scale-dependent factor. No hierarchical scale is added here.

Kernel SD keeps pairwise contrast variance at `2 tau^2`; a fixed common
marginal SD gives contrast variance `2 s^2 n/(n-1)`. With different numbers of
raters, stable marginal uncertainty and stable contrast uncertainty are
different goals. Select the convention for the intended decisions, not just
by matching existing numeric scale arguments.

The source-consistency mean is **our change-of-measure derivation**, not a
claim made by Uto. The printed code fixes `tau = 1`; other positive `tau` values
here are an algebraic generalization. Write `z = log(alpha_2:n)` and
`ell = (-sum(z), z)`. The product-one constraint cancels the sum of the
lognormal `-log(alpha)` terms, but the density in free log coordinates uses
the inverse-map Jacobian `abs(det(d alpha_free / d z)) = exp(sum(z))`, as in
[Stan's change-of-variables rule](https://mc-stan.org/docs/stan-users-guide/reparameterization.html#changes-of-variables).
Thus, up to a constant for fixed `tau`,

```math
\log p(z) = -\frac{z^\top(I_{n-1}+11^\top)z}{2\tau^2}+1^\top z+\mathrm{const}_{\tau},
\quad E[z]=\frac{\tau^2}{n}1,
\quad \operatorname{Cov}(z)=\tau^2\left(I-\frac{11^\top}{n}\right).
```

For three raters and `tau = 1`, the full log-consistency means are
`(-2/3, 1/3, 1/3)`, not all zero. For `ell = (-0.8,0.4,0.4)`, reversing rater
labels preserves the quadratic penalty but changes the log-coordinate density
by `-1.2`; the corresponding free-log permutation has unit absolute Jacobian.
This is a prior-density result, not a fitted rater bias or a practical-error
estimate. In particular, it supplies no rule for excluding an all-1 rater.
The standalone source item-loading lognormal does not have this product-one
coupling. Source centered-step normals also differ from the package's free-step
prior, but ordered category positions must not automatically inherit a rater-
exchangeability requirement; settle the blocks separately.

For identification, the retained Yao--Schwarz full text (Zotero `58X8E8BK`,
pp. 472 and 480) motivates separating response invariances from prior
restrictions. The existing fixed-Q test now checks a concrete two-dimensional
example: a small joint orthogonal rotation preserves all ability-loading dot
products, positivity of dense loadings and the identity-normal ability kernel,
but not the independent direct-loading lognormal prior. That rotation violates
a pure-item Q mask. Moreover, the source-style all-active Q has full structural
rank but is **currently rejected** by the duplicate-column gate; warning-bearing
mixed/within fixed-Q support is not unrestricted source-model fitting.
None of these checks proves global or joint identification of an admitted Q.

Before accepting a numerical change: specify the intended Q/correlation scope
and each prior's base measure, scale, centering and admissible label changes;
separately check likelihood and prior/posterior transformations, including
Jacobians. Then require matching Julia/Stan density and gradient checks,
prior-predictive checks, versioned cache/report compatibility, and separately
authorized refit sensitivity for boundary raters and the selected practical
decisions. Preserve named dimensions when reporting ability/composite/joint-
event targets; do not silently rotate estimates to improve recovery. The
exchangeable construction removes this rater-label artifact, not all likelihood
ambiguity, weak information or dependence on substantive prior assumptions.

Verification on 2026-09-07: the existing generalized-prior and fixed-Q files
pass 299 assertions on each of Julia 1.12.5 (`oOGogT`) and 1.10.8 (`a9EWN6`).
These comprise 190 existing assertions and 109 new checks: 99 zero-sum/measure
checks over 2/3/5 raters and SD 0.5/1/2, plus 10 rotation/Q/prior checks.
One density-difference comparison cancels to zero and uses absolute tolerance
`1e-12` for floating-point roundoff; this is not a scientific acceptance margin.
The source-density check compares the lognormal-plus-Jacobian expression with
a completed-square Gaussian kernel, not with a newly executed Stan target.
No dependency was added. Only this roadmap and the two existing test files
change; package source, defaults, caches, fixtures and previous evidence stay
unchanged. No posterior fit, CI, library write or reviewer contact occurred.
Both model specifications, independent review and M1 acceptance remain open.

### Blockwise specification and comparison contract

**Reusable specification: resolve the applicable blocks for each selected model.**
The immediate target is the Julia core contract; the two columns below retain
the distinct source/exchangeable prior targets. Resolve a bounded model slice
without requiring both full research programs or an application study. Use the
source-prior derivation above and existing contracts; record
the chosen value, measure, source revision and unresolved restriction for each
block before proposing a numerical patch. Keep the legacy raw-coordinate model
separately identifiable for compatibility checks, not as a substitute for either
selected scientific model.

| Block | Literal source reproduction | Exchangeable-rater-prior model / comparison control |
| --- | --- | --- |
| Response kernel and categories | Reproduce the additive dimension score, category-step accumulation, rater multiplier and `1.7` convention; bind the printed positive-coordinate declarations to the source revision | Hold these fixed for a prior-only contrast. Declare category labels and step indexing; compensation is a property of this conditional equation, not of the subsequent decision rule |
| Ability distribution | Record source zero mean, unit SD and independent dimensions, together with the loading-scale convention | Specify actual ability SD and covariance restrictions. Hold them fixed in the initial prior-only comparison; a free-correlation model is a separate structural change, not an incidental part of rater exchangeability |
| Loading geometry and dimension identity | Full source reproduction needs its all-positive loading scope and an explicit identification/alignment treatment; the current duplicate-column gate blocks that surface | A matched fixed-Q comparison can be an earlier restricted study, provided both models use the same Q and loading prior. Declare named dimensions, admissible transformations and recovery targets; unrestricted source reproduction remains a separate unresolved deliverable |
| Rater severity | Full-vector zero-sum normal kernel, including the reconstructed coordinate | Select kernel-SD or marginal-SD semantics. Under kernel-SD matching this block can have the same distribution in both models; do not change it merely to make the tracks look different |
| Rater consistency | Positive free-coordinate measure with reciprocal-product reconstruction; retain its derived nonzero log-coordinate mean and distinguished source rater | Specify the centered exchangeable zero-sum log prior and its own scale convention. Record full log means, covariance and contrast variance, transformation Jacobians and the treatment of the distinguished source rater in comparisons |
| Item difficulty and category steps | Record the direct item prior and full centered-step kernel, free dimension and source category convention | Match these blocks when isolating the rater-prior effect. Do not silently keep a legacy free-step prior and call the comparison source-matched. Ordered category labels do not by themselves impose monotone step thresholds or justify exchangeability of category positions |
| Coordinate measure and Jacobians | For every block record free coordinates, base measure, constrained reconstruction, prior density and log-Jacobian, naming what Stan supplies automatically and what must be explicit | Match Julia/Stan in common coordinates. For `a = exp(z)`, a declared density on `a` contributes `log p_a(exp(z)) + z`; a prior directly on `z` needs no extra term. Treat sum-zero/product-one constraints in their free dimension, distinguish constant terms from parameter-dependent terms, and retain scale-dependent normalization if a scale becomes estimated. Avoid missing or double-counted adjustments |
| Persistence and reports | Preserve source identity, restrictions and actual fitted priors, including any deliberate departure from the printed code | Reuse existing target/artifact/report and cache mechanisms, adding only the identity needed to prevent cross-model reuse. Test old-artifact interpretation and unknown-prior handling; no relabeling of old draws, changed defaults or frozen-fixture rewrites |

A prior-comparison proposal should name **one shared structural scope and
one prior contrast**, not cross every prior with every possible geometry.
A Q-restricted source-prior reference versus the exchangeable model can isolate
the declared rater-prior difference; it is not full Uto replication. If the
accepted prior contrast also changes other blocks or scale conventions, report
it as a multi-block comparison and isolate those effects only where a named
claim requires it. Numeric equality of SD arguments is not distributional
matching, and a coordinate reparameterization with its correct Jacobian is not
automatically a different scientific model.

Before protocol freeze, reconcile the existing
[Stage-A protocol](src/mgmfrm_validation_protocol.jl) with this specification.
Its `implementation_reference`, `source_aligned` and `strong_regularizing`
regimes are settings of the current raw-coordinate prior, not implementations
of the selected two-model program. Its pure-Q/identity-correlation primary scope
and secondary-only person-ability target also need explicit disposition.
Update the relevant existing contract/protocol only after that decision; retain
old protocol identities and evidence rather than retroactively reinterpreting
them. No protocol constants or branch guards change in this roadmap edit.

#### Current fixed-Q MGMFRM: executable blockwise measure

The 2026-09-13 slice records the **existing raw-coordinate baseline**, using
the production Julia target and [Stan model](src/stan/mgmfrm.stan). Let `J`,
`I`, `R`, `K`, `D` denote persons, items, raters, categories and dimensions,
and `L` the number of active Q cells. The common parameter vector concatenates
the following blocks in this order. Each raw coordinate has an independent
`Normal(0, s_block)` prior with respect to ordinary Lebesgue measure on the
listed free coordinates. The SDs are fixed hyperparameters.

| Block / raw count | Reconstruction and scale meaning | Julia / production Stan mapping |
| --- | --- | --- |
| Ability / `J*D` | `theta[p,d]` directly; `person_sd` is the dimension marginal SD, covariance `person_sd^2 I` | `:person`; first `J*D` entries of `beta`, person-major then dimension |
| Severity / `R-1` | Free `b[1:R-1]`, last `b[R] = -sum(b_free)`; `rater_sd` is the free-coordinate SD, not a common full-rater SD | `:rater_free`; `rater_offset = J*D` |
| Difficulty / `I` | Direct item difficulties; `item_sd` is their independent SD | `:item`; `item_offset = J*D+R-1` |
| Loadings / `L` | `a[i,d] = exp(z[i,d])` at active Q cells, zero elsewhere; `log_discrimination_sd` is the log SD | `:log_item_dimension_discrimination`; item-major active Q order after difficulty |
| Consistency / `R-1` | Free `ell`, `ell[R] = -sum(ell_free)`, `alpha = exp(ell)`; `log_consistency_sd` is the free log SD | `:log_rater_consistency_free`; after active loadings |
| Steps / `I*(K-2)` | Per item `d[i,1]=0`, free positions `2:K-1`, `d[i,K]=-sum(d_free)`; `step_sd` is the free-step SD, without ordering | `:item_steps`; item-major free steps at the end of `beta` |

The Julia path is `_mgmfrm_unconstrained_blueprint` ->
`_mgmfrm_source_constrained_params_from_unconstrained` -> category logits,
with `_source_fixture_logprior` supplying the normalized raw density.
`_cmdstan_mgmfrm_data` sends this same raw order and per-coordinate SD vector;
Stan declares only `vector[P] beta`, where
`P=J*D+2*(R-1)+I+L+I*(K-2)`. Its `mgmfrm_eta` reconstructs the constrained
effects inside the likelihood, and `beta ~ normal(0, prior_sd)` supplies the
raw prior. The reconstructed severity, log-consistency and final steps receive
no additional independent prior penalties.

**Jacobian contract.** The target is `log L(beta) + sum(log Normal(beta_j;0,s_j))`
in `d beta`. The additional log-Jacobian is zero in every current block.
Stan has no bounded sampled parameter to transform automatically; switching
its `jacobian` flag should leave both density and gradient unchanged. These
statements do not mean the reconstruction derivatives vanish: the last
severity has derivative `-1` with respect to every free severity, and the
last consistency has derivative `-alpha[R]` with respect to every free log
consistency. They enter likelihood gradients through the chain rule.

For a density expressed instead in free positive loading/consistency
coordinates, the inverse-chart log-Jacobian is `-sum(z_free)`; pulling it
back to the existing log chart adds `+sum(z_free)`. Do not replace this sum
with the zero sum of the **full** product-one log vector. The full constrained
vector has redundant coordinates and no ordinary full-dimensional density.
For a zero-sum linear embedding `[v; -sum(v)]`, the volume factor relative to
orthonormal surface coordinates is the constant `sqrt(n)`, not an extra
parameter-dependent prior penalty. This baseline is defined in the free
chart, so no such constant is added to its normalized free normal density.
The source full-vector kernels and the exchangeable proposal above remain
different prior specifications, not corrections implied by this contract.

The runnable check is [mgmfrm_density_measure.jl](test/mgmfrm_density_measure.jl),
included in the generalized test group. It uses a separately written
category-score equation, explicit block counts, six distinct SDs, and
between-item/mixed Q layouts with three raters and four categories. Its eight
points per layout cover zero, a joint nonzero point and each isolated block.
It checks reconstruction derivatives, pointwise likelihoods, normalized priors,
analytic prior gradients, a finite-difference total-gradient reference and the
positive-coordinate change of measure. The opt-in production comparison uses
[CmdStan's standard `log_prob` command](https://mc-stan.org/docs/cmdstan-guide/log_prob_config.html),
compiles the current package Stan source once, and checks both Jacobian flags.
It compares densities after accounting for the known fixed normalizing constant,
density differences and all raw gradient coordinates. No MCMC is required:

```sh
BAYESIANMGMFRM_CMDSTAN_TESTS=true julia --project=. test/mgmfrm_density_measure.jl
```

**Local evidence, 2026-09-13:** Julia 1.12.5/macOS and CmdStan 2.39.0 pass
126 independent-equation/measure assertions and 50 production-Stan assertions.
There are 16 distinct matched points (24 or 25 raw coordinates), evaluated
under both Jacobian flags: 32 Stan density/gradient evaluations. Maximum
absolute error is `1.4211e-14` for normalized log density and `7.1055e-15`
for a gradient coordinate. Both flag settings produce identical output.
Declared tolerances are `atol=1e-9, rtol=1e-10` for densities/differences and
coordinatewise `atol=1e-8, rtol=1e-9` for gradients. The first build failed
because the sandbox disallowed a precompiled-header write in the installed
CmdStan tree; a task-owned copy in writable temporary storage completed the
comparison without altering the installation. No target source, numerical
default, historical fixture or sampler was changed.
The compiled package `src/stan/mgmfrm.stan` SHA-256 was
`2e8f9ebc6b53c5644dbaf4245557bf55a74465a465a6e9935563e05ea3793a25`.
The 351 existing generalized-prior assertions and 44 retained Stan-reference
assertions also pass: 571 numerical/regression assertions in this slice.
This was not a full-suite run.

README links into internal build-review notes were removed while retaining
the actual user-visible build constraints. Public generalized-model help now
explains why `log_posterior` remains a raw-coordinate density when examining
`direct_draws`, and why plotting transformed draws requires no Jacobian.
The source-language gate passes all 19 public files; rendered-HTML and human
usability review were not repeated.

This verifies the tested current raw-prior slice. It does not cover GMFRM/MFRM
production density gradients, free correlation, new source/exchangeable priors,
all accepted Q layouts, other platforms or the minimum Julia version. Existing
historical bridge fixtures remain separately identified reference evidence.
No MCMC, convergence, statistical recovery or source-posterior equivalence
claim follows from this comparison.

#### Normalized source and exchangeable prior reference

The next 2026-09-13 slice specifies normalized **block reference densities**;
it does not add a fitting selector, change `GeneralizedPrior`, or adopt new
defaults. The derivations extend the fixed-scale source reading above.
The [author's Stan file](https://github.com/AI-Behaviormetrics/Multidimensional-GMFRM/blob/master/mult_gmfrm_uto.stan)
was reread for block indexing: severity and consistency reconstruct the first
rater; `category_est` contains `K-1` centered steps, with `K-2` free values and
the last derived. Its normal density is on those `K-1` values, not the
leading zero appended before cumulative summation. The positive consistency
domain follows the previously visually checked printed Appendix, not the
unbounded declarations in that repository copy. Only the unit kernel SD is
literal source specification; other SDs below are our mathematical extension.

For a full zero-sum vector of length `n`, let `m=n-1`, `C=[I_m; -1']`,
`A=C'C=I_m+11'`, and `v` the package's last-reconstructed free coordinates.
All formulas in this section are densities in `d v`. The centered normalized
log density with **kernel SD** `tau>0` is

```math
g_0(v;\tau)=\tfrac12\log n-m\log\tau-\tfrac m2\log(2\pi)
 -\frac{v^\top A v}{2\tau^2},\qquad
\Sigma_v=\tau^2\left(I_m-\frac{11^\top}{n}\right).
```

This is a proper `m`-dimensional Gaussian; `det(A)=n`. Reconstructing the
full vector gives covariance `tau^2 (I_n-11'/n)`. Use `n=R` for severity and
centered log-consistency, and **`n=K-1` for each item's centered steps**.
For source consistency, retain the identity `r_star` of the source's
distinguished rater when changing coordinate charts. Its normalized free-log
density is

```math
g_{r_*}(v;\tau)=g_0(v;\tau)-(Cv)_{r_*}
 -\frac{\tau^2(n-1)}{2n},\qquad
E[Cv]=\tau^2\left(\frac1n1-e_{r_*}\right).
```

The covariance equals that of `g_0`; the mean does not. For the source's
first-rater identity in the package chart, the linear term is **`-v[1]`**.
The familiar `+sum(v)` term is correct only when the distinguished rater is
the reconstructed coordinate. Thus a change from first- to last-reconstructed
coordinates must not silently move the scientifically distinguished rater.
If `u=(Cv)[2:n]` denotes the source's free log coordinates, `u=T v` with
`T=C[2:n,:]` and `abs(det(T))=1`. Densities agree under this map, and
gradients transform by `T'`. For three raters the common-chart log means are
`(-2tau^2/3, tau^2/3)`, with the last reconstructed mean `tau^2/3`.
These are prior moments, not estimated rater effects.

The explicit gradients and scale scores are

```math
\nabla_v g_0=-Av/\tau^2,\qquad
\nabla_v g_{r_*}=-Av/\tau^2-C^\top e_{r_*},\qquad
\nabla_v^2 g=-A/\tau^2,
```

```math
\partial_\tau g_0=-m/\tau+(v^\top Av)/\tau^3,\qquad
\partial_\tau g_{r_*}=\partial_\tau g_0-\tau(n-1)/n.
```

Scale derivatives here verify normalization; they do not introduce an
estimated scale or hyperprior. If a future hierarchical extension is selected,
its conditional prior must retain these scale-dependent terms. Merely adding
a hyperprior to the printed fixed-scale kernel would generally define a
different scale distribution.

| Expression before normalization | Integral over the specified free measure | Required correction to its log density |
| --- | --- | --- |
| Product of `n` centered normal densities on `Cv`, integrated in `d v` | `Z0 = 1 / (sqrt(2pi*n) * tau)` | `-log(Z0)`; omitting it gives one excess `-log(tau)` |
| Source product of `n` lognormal densities on the product-one vector, integrated in its `n-1` free **positive** coordinates | `Zsource = Z0 * exp(tau^2*(n-1)/(2n))` | `-log(Zsource)`; in the source's free-log chart also add the change-of-variables term `sum(u)` |

The source severity block and a centered exchangeable severity block therefore
coincide under kernel-SD matching. A comparison intended to isolate the
consistency prior can hold the source-centered step block fixed in both
models. For a common constrained marginal SD `s`, use
`tau=s*sqrt(n/(n-1))`; contrast variance is `2tau^2`. This agrees with
[Stan's sum-to-zero scale convention](https://mc-stan.org/docs/reference-manual/transforms.html#sum-to-zero-transforms).
Equal numeric raw-coordinate SDs in the legacy model are not this matching.
For steps, symmetric normal penalties do not authorize permuting ordered
response labels or imply ordered thresholds.

**Implementation identity handoff.** Preserve the current raw-prior cache
record and `GeneralizedPrior` meaning. Any new complete target must distinguish
the raw-coordinate baseline, a Q-restricted source-prior reference, and the
exchangeable-rater model. Record the block distributions, explicit scale
convention/values, and the distinguished source **rater ID**, not just its
current sorted index. Coordinate-chart and backend identity remain separate
from that scientific identity. Source/exchangeable severity need no artificial
difference; loading, ability, difficulty and step choices must be matched and
recorded for a consistency-only comparison. A source-like prior under fixed Q
is still not unrestricted source reproduction. No new cache schema is adopted
until an executable target consumes it.

The runnable [Julia reference checks](test/mgmfrm_prior_measure.jl) compare
the closed forms with an independently evaluated multivariate-normal formula,
analytic gradients/Hessians, scale scores, chart changes and relabeling with
and without moving the distinguished rater. Stdlib quadrature independently
checks unit mass and zero integrated scale score in one and two free
dimensions. The [Stan prior reference](test/stan/mgmfrm_prior_measure.stan)
uses positive sampled consistencies and the source first-rater reconstruction,
full-vector `normal_lpdf`/`lognormal_lpdf` calls, and explicit normalizers.
Stan's automatic positive-parameter Jacobian is compared with the common-chart
Julia density; disabling it is a negative control with a known density and
gradient shift. The exchangeable reference explicitly converts its centered
log-coordinate density into a positive-coordinate density before Stan's
automatic transform, as required by the
[change-of-variables rule](https://mc-stan.org/docs/stan-users-guide/reparameterization.html#changes-of-variables).
No likelihood or MCMC is present in that new reference model.

```sh
julia --project=. test/mgmfrm_prior_measure.jl
BAYESIANMGMFRM_CMDSTAN_TESTS=true julia --project=. test/mgmfrm_prior_measure.jl
```

**Local evidence, 2026-09-13:** Julia 1.12.5/macOS passes 666
normalization/formula/derivative/chart assertions and 24 quadrature assertions.
The algebra covers `n=2/3/5` and kernel SD `0.5/1/2`; numerical integration
covers one and two free dimensions on `[-12tau,12tau]` per coordinate with
96-point Gauss-Legendre quadrature. Unit-mass and integrated-scale-score
tolerances are absolute `1e-9`. This finite-domain check is numerical evidence
alongside the Gaussian derivation, not a general-purpose integration guarantee.

CmdStan 2.39.0 passes 180 assertions across `(R,K)=(2,4),(3,3),(5,6)`, three
base scales, both prior choices, two parameter points and both Jacobian flags:
72 density/gradient evaluations. Severity, consistency and step kernel SDs are
respectively `tau`, `0.8tau`, and `1.3tau` to detect block-scale interchange.
Explicit `lpdf` calls retain normalizing constants under `log_prob`'s
`propto=true`, so the test compares absolute densities as well as gradients
after mapping to the common chart. Maximum absolute differences are
`2.6646e-15` in log density and `2.4425e-15` in gradient coordinates;
tolerances are `atol=rtol=1e-10` for density and coordinatewise
`atol=1e-9, rtol=1e-10` for gradients. The new Stan reference SHA-256 is
`fb880b171721eb39c19b76918cbd80598f8e8f879428b3eca8175b9bb2d7f0aa`.
It was compiled in a task-owned writable copy of CmdStan, subsequently removed.

The 126 existing raw-measure checks also pass, giving 996 assertions in this
slice. The initial test attempted to differentiate the package's fixed-Float64
normal SD argument; those two kernel-scale checks now use finite differences,
preserving the production helper's fixed-scale contract. Production priors,
likelihoods, caches and historical fixtures were not changed. Neither a full
suite nor MCMC was run; other platforms and the minimum Julia version were
not tested. These block references alone do not implement either new prior in
the fitting paths or establish statistical validity. The following slice
integrates the complete densities, retaining the sampling boundary.

#### Complete fixed-Q normalized prior targets

The next 2026-09-13 slice implements
[`_MGMFRMNormalizedPriorLogDensity`](src/mgmfrm_normalized_prior.jl), an
unexported complete Julia density. It consumes the existing validated fixed-Q
MGMFRM specification, requires all six scales explicitly, and accepts either
`:source` with an explicit observed `source_rater` ID or `:exchangeable` with
no distinguished rater. The base target supplies the same snapshot, coordinate
layout, `1.7` likelihood and fixed identity correlation. Ability, difficulty
and log-loading priors remain independent normals. Severity, log-consistency
and each item's steps use the normalized centered kernels above; source
log-consistency additionally retains its distinguished-rater linear term and
scale-dependent normalizer. Source SDs other than one and fixed-Q loading
restrictions remain declared adaptations, not unrestricted source reproduction.

The implementation reuses `_source_fixture_logprior` and adds, for each
centered block with `m` free entries, the exact log-density correction
`log(m+1)/2 - (sum(v)/tau)^2/2`. This avoids subtracting two potentially
infinite prior densities. It exposes ordinary `LogDensityProblems` density
and dimension methods, `initial_params`, and `logprior` for this private type.
No copied likelihood, new dependency or runtime work on package import is
introduced.

`_mgmfrm_normalized_prior_record` records the versioned prior schema,
source/exchangeable choice, scale convention, coordinate measure, six actual
scales and source-rater **ID**. `_mgmfrm_normalized_prior_identity` combines
that record with the existing canonical design identity. The in-memory
record constructor requires an expected identity and rejects unknown fields,
schemas/measures, missing IDs, invalid scales, changed priors and mismatched
designs. It reads no file and reuses no fit cache. Changing a caller's data
after construction cannot alter the target's validated snapshot. These checks
are compatibility checks, not authentication of external artifacts.

The [production MGMFRM Stan program](src/stan/mgmfrm.stan) now contains the
same three explicit prior branches. The ordinary adapter supplies
`prior_model=0, source_rater=0`, retaining the legacy raw-coordinate target.
The private normalized adapter supplies mode 1 (source) or 2 (exchangeable)
and the resolved source index. All branches reuse `mgmfrm_eta` and its
generated pointwise likelihood. The normalized branches require positive,
common SDs within each centered block and reject inconsistent prior/reference
selectors and non-finite source normalizers. Stan still samples unconstrained
`beta`, so its automatic Jacobian flag adds nothing in this parameterization.
The earlier positive-coordinate Stan prior reference remains an independent
change-of-measure check.

**Compatibility boundary:** the production Stan source/hash and its data
schema changed; older manually retained production-Stan JSON inputs require
the two explicit raw-mode fields or regeneration through the adapter. Existing
Julia prior defaults and cache meanings are unchanged. No historical fixture
was regenerated. A fresh compile is required under the existing no-reuse
build policy. Neither the ordinary `Experimental.fit` prior argument nor its
cache route accepts these new private targets/records. At this density-only
slice there was no saved-result or MCMC route; the subsequent private
integration is described below. There is still no public selector or full
source-model claim.

The extended [density test](test/mgmfrm_density_measure.jl) checks complete
priors against an independent multivariate-normal formula, complete gradients,
record reconstruction/rejection, source-ID snapshot behavior and relabeling
of the actual ratings. Source consistency is exercised with first, middle
and last distinguished raters; exchangeable and unit-SD source controls
share the same likelihood. Production Stan comparisons include both pure and
mixed Q, zero/joint/isolated-block points and both Jacobian flags. Invalid Stan
data exercise its selector, block-scale and source-normalizer rejection paths.
**Local evidence, 2026-09-13:** Julia 1.12.5/macOS and CmdStan 2.39.0 pass
126 retained raw-target assertions, 532 new complete-target/identity assertions
and 311 production-Stan assertions. The Stan check evaluates 192
density/gradient rows: two Q layouts, one raw and five normalized settings,
eight parameter points, and both Jacobian flags. Five normalized settings are
exchangeable, source with each of three rater IDs, and a unit-SD source
reference. Maximum absolute differences are `1.4211e-14` in normalized log
density and `7.1055e-15` in gradient coordinates. It retains the earlier
`atol=1e-9, rtol=1e-10` density/difference tolerances and coordinatewise
`atol=1e-8, rtol=1e-9` gradient tolerances. Eleven malformed Stan payloads are
rejected. The compiled source SHA-256 is
`d53f4aff0026e0b30f494595abd48b6bdf71a8b83acf8c5dc0cb2a0e0a57d018`.

The existing 690 prior-reference, 78 backend-contract, 4,617 synthetic
cache-containment and 431 synthetic producer/control assertions also pass:
969 density/identity/input assertions plus 5,816 related regression assertions.
Actual compilation/log-probability evaluation used a task-owned CmdStan copy;
the cache and producer probes remain synthetic evidence. No MCMC or full-suite
run occurred. The complete-target examples cover three raters, four categories
and two dimensions; other sizes have block-reference evidence, not a new
complete-target evaluation. Minimum Julia, other platforms, saved fits,
sampler/result parity, recovery and scientific validity remain unverified for
the new priors. The temporary CmdStan copy was removed after verification.

#### Normalized-prior sampling and saved results

The subsequent 2026-09-13 slice connects both normalized targets to actual
NUTS execution in [`mgmfrm_normalized_prior.jl`](src/mgmfrm_normalized_prior.jl).
`_mgmfrm_normalized_prior_sample(target; backend=:advancedhmc, ...)` uses
the existing Julia sampling loop; `backend=:cmdstan` uses the existing
compile/chain/CSV route and the same production MGMFRM program. Shared runners
now accept the private wrapper through its dimension, density and raw-vector
validation methods. Existing generalized callers retain their defaults and
concrete public result types. No sampler loop, dependency or public fitting
selector was added.

The normalized CmdStan parser retains the generated `log_lik` comparison,
evaluates each draw under the normalized Julia target, and checks `lp__`
after restoring the independent-normal constants omitted by Stan. This last
check detects a wrong prior branch even when pointwise likelihoods agree.
Stan's original `lp__` remains in sampler statistics. Shared adapters preserve
chain/phase error context.

The private result contains `record`, raw/direct parameter names,
`public_fit=false`, and `diagnostics`. Its
`bayesianmgmfrm.normalized_fixed_q_samples.v1` record retains the specification,
normalized-prior record, target identity and complete sampler run: raw draws,
normalized log densities, chain/iteration IDs, seed and effective controls,
backend, initial state, sampler telemetry and chain summaries. The prior
record carries actual scales and the original typed source-rater ID. These
posteriors are never represented as a legacy `MGMFRMFit` or raw-coordinate
`GeneralizedPrior` fit.

`_save_mgmfrm_normalized_prior_samples(path, result)` and
`_load_mgmfrm_normalized_prior_samples(path; expected_identity=...)` use
Julia's existing `Serialization` dependency for trusted records in the same
analysis environment. The saved payload contains the primitive record;
direct parameters, pointwise likelihoods and diagnostics are rebuilt on load.
Loading requires the caller's expected target identity, validates the schema,
prior and canonical data/design, and verifies a content hash covering the run
and prior metadata. It also checks dimensions, finite values, chain order,
effective backend controls, initial and retained normalized densities,
sampler-stat correspondence and chain summaries. Deliberately rehashing
inconsistent records does not bypass these semantic checks. The specification
is covered by canonical design identity, not generic object display. This is
compatibility/corruption detection, not authentication or a safe reader for
untrusted serialized objects; cross-version archival portability is untested.

Saving validates before publication. The existing fit-cache temporary-file,
hardlink and native-rename implementation is extracted into
`_save_serialized_record` and shared by both callers. Failed writes preserve
existing files, and overwrite is refused by default. Ordinary `load_fit_cache`
rejects this distinct schema. Derived diagnostics are not duplicated in the
file or substituted for the underlying draws.

The [runnable test](test/mgmfrm_normalized_samples.jl) uses 24 ratings,
two persons, four items, three raters, four categories and two dimensions.
Exchangeable priors use a pure Q and integer rater IDs; source priors use a
mixed Q and a distinguished middle rater with a Symbol ID. Each backend uses
2 chains, 10 warmup and 12 retained draws per chain, seed 9173, jitter 0.02,
initial step 0.03 and maximum depth 4. The six kernel SDs are
`(0.7,0.4,0.6,0.3,0.35,0.5)` in the existing six-block order. These are
operability inputs, not a chosen scientific prior. Tests check every retained
normalized density and pointwise likelihood, direct constraints, typed-ID and
full-run round trips, rebuilt diagnostics, schema/identity/content and semantic
rejection, and preservation of existing files on rejected save. A separate
synthetic CSV check preserves correct draws/likelihoods while changing `lp__`
to verify prior-mismatch rejection.

**Local evidence, 2026-09-13:** Julia 1.12.5/macOS and CmdStan 2.39.0 pass
608 assertions: 18 input/public-boundary, 6 synthetic parser, 268 Julia
sample/save/load and 316 actual CmdStan sample/save/load checks. Four fits
retain 96 draws in total. The deliberately short fits retain diagnostic
warnings; successful run/save/load establishes operability, not convergence,
posterior agreement, parameter recovery or application validity. The first
run's eight failures were incorrect exception-type expectations in the test;
the shared validator correctly kept `ArgumentError` with chain/phase context.
Those expectations were corrected before the final run.

Related regression checks pass 7,723 assertions: 658 complete-density/identity,
690 prior-reference, 78 backend-contract, 1,249 fitting-boundary, 4,617
synthetic cache-containment and 431 synthetic producer/control checks.
Total: **8,331 assertions** in the final bounded checks. The regression includes
legacy short fits and serialization failure/race preservation; the cache and
producer probes remain synthetic. Fixed Q, `1.7`, identity latent correlation
and declared scale adaptations are unchanged; the production Stan source
hash remains `d53f4aff0026e0b30f494595abd48b6bdf71a8b83acf8c5dc0cb2a0e0a57d018`.
The generalized shard now executes two short Julia fits; actual CmdStan
sampling requires `BAYESIANMGMFRM_CMDSTAN_TESTS=true`. No work occurs on package
import. There was no full-suite, minimum-Julia, other-platform or new
distribution/runtime-budget assessment. The task-owned CmdStan copy is
removed after verification; no application data or historical fixture changed.

#### Fixed-Q posterior comparison receipt

The next 2026-09-13 slice completes the single predeclared experiment in
[`normalized-prior-backend-comparison.md`](docs/internal/normalized-prior-backend-comparison.md).
Its [manual runner](scripts/run_normalized_prior_comparison.jl) reuses the
existing dense synthetic-data generator, private normalized sampler/results,
rank-normalized diagnostics, statistic-specific MCSE and serialization helpers.
It adds no production dependency, export, likelihood or ordinary-test MCMC
budget. The [manual synthetic decision test](test/normalized_prior_comparison.jl)
passes 52 assertions before execution. Source and exchangeable priors are
compared independently on the same pure-Q, 72-response, two-dimensional case,
using four chains per backend and 1,500 retained draws per chain: four fits
and 24,000 retained draws in total.

All four fits meet the frozen diagnostic criteria. Across raw/direct
parameters and six draw-wise contrasts, maximum R-hat is 1.00259, minimum
bulk ESS is 3226.3 and minimum tail ESS is 3511.5; all chains have E-BFMI above
0.8855, with zero retained divergences or depth hits. Of 640 mean/SD/quantile
comparisons, 639 satisfy both the 4.5-combined-MCSE screen and the 0.3-posterior-SD
error-inclusive resolution requirement. The source target passes all 320
rows; the exchangeable target retains one resolution hold. Its R2 consistency
90% quantile differs by -0.01761 (CmdStan minus Julia), with combined MCSE
0.00869. The resulting bound is 0.30478 SD, so the overall decision remains
**unresolved** despite passing diagnostics and no discrepancy-screen failures.
Thresholds, seeds and draw budgets were not changed after inspecting results.

All four sample records are saved and re-read before scoring. Source and
file hashes remain consistent; independent Python arithmetic reproduces all
640 comparison decisions. Full local records remain under git-ignored
`results/normalized-prior-comparison/20260913-fixed-q-01/`; the internal note
contains the durable human-readable receipt. Evidence is local to Julia
1.12.5/macOS, CmdStan 2.39.0 and this fixed model/data/scale choice. It is not
full-distribution equality, general backend equivalence, recovery, minimum-
version/other-platform acceptance or application evidence. Warmup-event and
other remaining failure boundaries are unchanged. The task-owned CmdStan copy
is removed after verification. The subsequent performance work below does
not discard or change this unresolved run.

#### Saved-result hash cost and compatibility receipt

The subsequent 2026-09-13 slice profiles one retained 6,000-draw Julia record
without fitting. SHA-256 over canonical `CodeUnits` takes 68.72 seconds;
run validation and diagnostic tables take 0.93 and 2.09 seconds. A separate
stdlib-only reproduction isolates the input-format cost. The shared cache
hash and seven fit/report hash sites now use `sha256(IOBuffer(text))` over
the same bytes. No canonicalization, target identity, density, draw, chain,
diagnostic or atomic-publication check is removed or altered.

The final repeat profile records 0.087 seconds for hashing, 2.00 for validated
save and 1.93 for validated load, versus 68.72/70.35/74.80 previously.
These are one local before/after pair, including JIT and profiler overhead;
they are not portable performance guarantees or new sampler benchmarks.
The in-memory draws, diagnostic tables and all 64 parameter/contrast
summaries match the pre-change serialized reference exactly. Re-reading
all four Julia/CmdStan records also reproduces the original hashes,
diagnostics, summaries and 640 comparison rows exactly: still 639 accepted
and one unresolved. Input files remain byte-identical.

The bounded regression passes **1,658 assertions**: 65 cache/report byte
compatibility, 292 normalized-prior Julia/parser/save-load, 1,249 fitting
boundary and 52 comparison-decision checks. These include Unicode, SHA
block/stream boundaries, corruption rejection and serialization failure/race
preservation. Only existing tiny Julia operability fits run; there is no new
CmdStan or posterior-comparison MCMC, full suite, minimum-Julia or other-platform
validation. The manual [profiler and saved-result verifier](scripts/profile_normalized_prior_results.jl)
add no package load work or public API. Timings, reproduction commands and
local artifact hashes are in the [comparison note](docs/internal/normalized-prior-backend-comparison.md#saved-result-performance-receipt-2026-09-13).

#### Fixed-Q precision follow-up receipt

The next 2026-09-13 slice executes the predeclared 6,000-draw-per-chain
follow-up: four fits, four chains each and **96,000 retained draws**. The
existing manual runner gains one explicit `--precision-followup` switch,
reusing the original fitting/scoring loop and preserving its initial default.
The new protocol records verified hashes of the initial receipt and unchanged
model/data/scale/gate identities before the first sampler call. The manual
decision test passes 57 assertions; no production source or public API changes.

**All 640 comparisons satisfy the unchanged criteria**, 320 per prior, and
all four fits pass retained-draw diagnostics. Across all quantities, maximum
R-hat is 1.00081, minimum bulk ESS is 14079.4 and minimum tail ESS is 16285.7.
Every chain has E-BFMI above 0.9461, with zero retained divergences or depth
hits. Maximum absolute discrepancy is 3.30633 combined MCSEs (limit 4.5);
maximum error-inclusive difference is 0.15226 posterior SD (limit 0.3).
The formerly held exchangeable R2 consistency 90% quantile has estimates
1.04296/1.04373 for Julia/CmdStan, combined MCSE 0.003887 and bound 0.09935 SD.
No extra fit, seed change, cutoff change or draw pooling follows the outcomes.

Each result is saved, re-read, validated against its target and checked for
identical retained runs and actual planned controls/seeds. A separate Python
arithmetic/file check reproduces all 640 decisions and verifies the frozen
protocol, source hashes and sample bytes. The original trial's JSON/JLS files
remain byte-identical and its unresolved receipt is retained. Local records
and exact runner/verifier snapshots are under git-ignored
`results/normalized-prior-comparison/20260913-fixed-q-precision-01/`;
the [execution note](docs/internal/normalized-prior-backend-comparison.md#precision-follow-up-execution-receipt)
contains the durable receipt. The task-owned CmdStan 2.39.0 runtime copy is
removed after completion.

This closes the selected same-target marginal/contrast precision check on
Julia 1.12.5/macOS and CmdStan 2.39.0. It does not establish whole-joint
equivalence, recovery/calibration, other Q/data/scales, source-paper reproduction
or application validity. No full-suite, minimum-Julia or other-platform run
is added. M1 remains open; the warmup slice below follows this comparison,
without promoting the private prior selector.

#### Normalized-prior warmup telemetry and saved-result compatibility

The following 2026-09-13 slice adds opt-in recording to the shared generalized
AdvancedHMC and CmdStan runners. The private normalized-prior sampler enables
it by default. Existing public callers retain their current behavior; the
likelihood, prior, sampling controls and public exports do not change.
Julia retains the library's warmup output long enough to extract compact event
rows, then indexes retained draws after warmup. CmdStan writes warmup rows and
the parser verifies the adaptation boundary and both row counts before using
only retained rows for posterior evaluation. Recorded events cover divergence,
maximum depth and nonfinite log density, with chain and warmup iteration.

Separate `warmup_diagnostics` rows distinguish `recorded`, `not_run` and
`not_recorded`, including expected/observed counts. They add no warmup R-hat,
ESS or pass/fail rule. Missing historical telemetry is never inferred to be
zero. Private sample schema v2 requires and hashes warmup event rows; v1
remains readable and keeps its original hash. Semantic checks reject incomplete
coverage, wrong chain/iteration layouts, invalid event fields and schema/data
mismatches even after a record is deliberately rehashed. Failed saves preserve
the existing file. No new public cache schema is introduced.

Final bounded checks cover **7,106 assertions**: 731 normalized-prior checks
including actual Julia/CmdStan fits, plus 6,375 existing backend, fitting-boundary
and synthetic cache/producer checks. The initial 292 normalized-prior assertions
were also run before the expanded 731; they are not counted twice here.
Seven short fits per backend cover both priors with recording on/off and one
zero-warmup case. Retained draws, log densities, chain/iteration labels, sampler
statistics and posterior diagnostic tables match exactly within each backend.
Synthetic checks exercise warmup-only divergences/nonfinite values, CSV phase
boundary errors, retained-only density evaluation and fatal interruption
propagation. These are operability checks, not convergence evidence.

The four historical precision-trial files (96,000 draws) reload successfully
and reproduce every original summary and all 640 decisions. Input bytes and
content identities remain unchanged. The receipt and logs are retained under
`results/warmup-telemetry/20260913-fixed-q-01/`; the
[internal note](docs/internal/normalized-prior-backend-comparison.md#warmup-telemetry-execution-receipt-2026-09-13)
records reproduction commands and scope. Validation is local to Julia 1.12.5,
AdvancedHMC 0.8.5 and CmdStan 2.39.0 on macOS. The owned CmdStan runtime copy
is removed. No full suite, minimum-version/other-platform run, new precision
study or native cancellation experiment is added. The following slice connects
public fit diagnostics and caches; report presentation and interruption-time
partial telemetry remain open.

#### Public fit warmup diagnostics and cache compatibility

The following 2026-09-13 slice enables warmup collection on ordinary
AdvancedHMC and CmdStan `fit`/`Experimental.fit` for MFRM, scalar GMFRM and
fixed-Q MGMFRM. `sampler_diagnostics(fit; phase = :warmup)` retrieves compact
chain summaries; its retained default and posterior diagnostics remain
unchanged. No fit struct layout, public export, dependency, prior, production
Stan model or cache request identity changes. The existing sampler metadata
carries the summaries through v1 fit-cache save/load and full fit artifacts.
Turing, random walk and older positive-warmup fits return unavailable coverage;
zero warmup is recorded as not run. Cache save/load reject malformed summary
metadata and failed saves preserve an existing destination.

The focused check passes **322 assertions**, including nine short fits per
NUTS backend and one each for Turing and random walk. It verifies exact
recording-on/off retained draws, sampler statistics and posterior diagnostic
outputs in all three families, zero-warmup behavior, both cache coverage states
and malformed metadata rejection. The broader regression passes **6,838**
assertions, including 33 checks that three actual pre-change Julia caches
remain byte-identical, load under their original keys, and match fresh retained
output/diagnostics. The distinct final count is **7,160**; short fits assess
operability and compatibility, not convergence or recovery.

The initial focused run stopped at the existing CmdStan cache-reuse guard
after its 159 Julia checks passed. The test harness now gives every fit a new
empty build directory; the complete rerun passed without changing that guard.
README and fitting help describe phase selection, coverage, cache refresh and
CmdStan's existing build-directory requirement. The
[internal receipt](docs/internal/normalized-prior-backend-comparison.md#public-fit-warmup-integration-2026-09-13)
records local artifacts, reproduction and limits. This does not close M1,
full-suite/CI runtime acceptance, minimum-version or other-platform validation.
The report slice below supplies dedicated presentation; interruption-time
partial telemetry and unsupported-backend recording remain separate work.

#### Warmup report presentation and legacy output compatibility

The following 2026-09-13 slice adds `warmup` to the existing fit-report section
and public-projection registries. The section uses the existing diagnostic API
and captured-error policy. Structured/public reports, Markdown, JSON tables
and bundles now carry chain coverage and event counts automatically. An
explanation distinguishes observed history, no requested warmup and unavailable
counts; `computed` records reporting success, not adaptation quality. Fixed
warmup column order preserves that table's appearance after JSON reload.
Retained convergence diagnostics and warning aggregation are unchanged.

The focused deterministic report checks pass **211 assertions** across MFRM,
GMFRM and fixed-Q MGMFRM with AdvancedHMC/CmdStan backend labels. They verify
nonzero adaptation events without added retained warnings, all output forms,
missing/zero distinctions, captured invalid metadata and strict error modes.
These labels do not constitute native backend execution. The existing
completeness/hash/prior checks and manual legacy checks pass **506 assertions**;
the distinct final count is **717**. Two actual pre-change full/public bundles
retain their file bytes and load with their original hashes. New reports from
three historical Julia fit caches correctly show unavailable warmup history.

An initial whole-Markdown equality assertion exposed pre-existing generic
column-order and full-report hash-representation differences. The final check
verifies the new warmup preview and all serialized rows; the following slice
addresses general report column stability. The
[internal receipt](docs/internal/normalized-prior-backend-comparison.md#warmup-report-presentation-2026-09-13)
records commands, local files and the stopped check. No new sampler validation,
CmdStan compilation, prior/model change or M1 acceptance follows from this
reporting slice. Full-suite, fresh-HTML and other-platform validation remain
separate.

#### Shared report and dossier column order

The following 2026-09-13 slice fixes the shared Markdown field resolver.
Identifiers, sampler coverage, estimates and uncertainty have a common readable
order; other fields sort by name. Full/public reports and dossiers now retain
that order after JSON reload. Warmup uses the same mechanism. Existing explicit
metadata/warning columns, public filtering, serialized rows and hash definitions
are preserved; older saved Markdown files are not rewritten.

The final checks pass **516 assertions**: column/dossier checks 36, expanded
three-family/two-backend-label warmup reports 223, report completeness 69,
hash byte compatibility 65, and manual historical-report/fit checks 123.
The latter read two actual old bundles and three historical Julia fit caches,
verify table values and hashes, and preserve all input file bytes. These are
reporting checks; no native CmdStan execution or new posterior validation is
claimed. JSON numeric spelling and full typed hash labels still need not match
whole-Markdown bytes across representations. The
[receipt](docs/internal/normalized-prior-backend-comparison.md#report-column-order-2026-09-13)
records the focused test corrections and reproduction commands. Julia 1.12.5
with `--compile=min` was used; full-suite, fresh-HTML and other-platform checks
remain open. The next task returns to the Julia sampling failure boundary.

#### Sampling-call failures and automatic cache preservation

The following 2026-09-13 audit confirms the existing sampling/result/cache
control flow with **131 additional assertions**. AdvancedHMC completes a first
chain and then fails after one warmup or one retained transition in chain 2,
for MFRM, GMFRM and fixed-Q MGMFRM. Ordinary errors retain the cause/backtrace
and chain/stage; constructed interruption, out-of-memory and stack-overflow
exceptions propagate unchanged. Automatic cache creation and refresh are tested
through a test-owned seeded RNG wrapper; a failure writes no new cache and
preserves an existing valid cache's exact bytes. A synthetic CmdStan command
exits on chain 2 after chain 1's output is accepted; no third command or parser
call for the failed chain occurs, and its stage/reason contract is retained.

The complete fitting-boundary file passes **1,380 assertions** on Julia
1.12.5/macOS with normal compilation (1,249 existing plus 131 added). No sampler
or cache implementation change was required. The public fitting help and
`cached_fit` docstring now explain cache preservation and the limit of the
`sampling` phase label. The
[receipt](docs/internal/normalized-prior-backend-comparison.md#sampling-failure-and-cache-publication-2026-09-13)
records test seams, initial harness corrections and source/evidence hashes.
Constructed exceptions do not test live SIGINT, actual resource exhaustion or
native CmdStan cancellation; the delayed tests use AdvancedHMC, with the older
Turing startup-fault checks retained. No new posterior-validation claim, M1
acceptance or full-suite/minimum-version/other-platform pass follows.

#### Minimum Julia version: recent contract verification

The 2026-09-13 check uses Julia 1.10.8 and the existing versioned manifest,
including AdvancedHMC 0.8.6. **2,852 assertions pass**: fitting boundaries 1,380,
reports/hash compatibility 393, historical JSON reports 26, public warmup/cache
322 and private normalized-prior records 731. The last two include 16 native
CmdStan short fits with `--compiled-modules=yes --pkgimages=yes --compile=min`.
Recording enabled/disabled preserves retained draws and diagnostics; fresh
records retain warmup metadata through save/load. Historical cross-version
reads cover portable JSON reports, not Julia binary fit caches.

Normal compilation passes the complete boundary file, including Turing. The
larger normal-compilation sampler run was manually stopped after about 25
minutes, after the AdvancedHMC portion passed; its CmdStan portion has no
completion result. The termination stack points into LLVM, without identifying
the root cause. Disabling compiled modules separately exposes a Turing world-age
error. Both attempts remain in the
[receipt](docs/internal/normalized-prior-backend-comparison.md#minimum-version-verification-2026-09-13)
and their repeated passes are excluded from the final count. Package sources,
tests, Project and both manifests remain unchanged. This verifies bounded
functional contracts under the recorded flags, not full-suite, runtime-budget,
other-platform, statistical or release acceptance. The compilation observation
was investigated in the follow-up below.

The 2026-09-14 follow-up isolates excessive specialization on nested cache
record types in `_check_fit_cache_record` and `_save_serialized_record`. Their
bodies remain unchanged; only compiler annotations limit specialization and
inference on the record argument. In fresh Julia 1.10.8 processes using the
same saved GMFRM record, structure checking falls from 75.73 to 0.04 seconds
and atomic serialization from 83.63 to 0.64 seconds. The 127,258 serialized
bytes are identical. These are local first-call measurements including JIT,
not sampler speed or CI runtime acceptance. Julia 1.10.8 passes the same 2,852
assertions with normal compilation; a fresh standalone warmup/cache run also
passes all 322 assertions in 147.70 seconds. See the
[follow-up receipt](docs/internal/normalized-prior-backend-comparison.md#cache-record-compilation-2026-09-14)
for normal-compilation regression results and retained incomplete attempts.
The separate Julia 1.12.5 report run reaches its 900-second limit after the
first four files pass 1,944 assertions. Its remaining 357 report assertions
pass with `--compile=min`; normal-compilation report runtime remains open.
This does not reopen the whole M0 matrix before the first figure.

### Practical acceptance and mechanism-selected stress

The user prioritizes **conditions under which use is practically acceptable**,
for diverse users and with Bayesian uncertainty available. Propose a small
set of decision profiles, not one universal cutoff or a compulsory feature
bundle. For each selected profile specify the target population, estimand,
conditioning, action/loss, tolerance and acceptable uncertainty before looking
at evaluation results:

Select profiles by the reusable package claim, not the available Uchihara data.
That application can later exercise trait/rater interpretation and prediction;
it does not itself justify pass/fail, rater-sanction or general proficiency
claims. The profiles below are options for a bounded validation design, not a
compulsory cross-product of features and conditions.

- **Individual assessment:** named dimension abilities, a declared weighted
  composite, or a joint event such as all required dimensions exceeding their
  cutoffs. Obtain joint events from joint posterior draws, not products of
  marginal probabilities; an additive response model does not require a
  compensatory pass rule. Include an indeterminate/review outcome when posterior
  uncertainty or model sensitivity exceeds the profile's accepted limit.
- **Rater and item monitoring:** posterior severity/consistency contrasts,
  category behavior and predictive consequences, conditional on assignment and
  prior choice. An all-1 rater is a diagnostic scenario, not a predeclared
  unreliable class; distinguish sparse information from predictive misfit and
  do not automatically delete, downweight or sanction the rater.
- **Prediction:** declare heldout units among supported persons/items/raters,
  predictive event weights and decision loss; compare integrated predictions,
  calibration and uncertainty. New-facet prediction remains out of scope unless
  its population model and implementation are separately selected.

Keep convergence/Monte Carlo diagnostics, likelihood information, posterior
uncertainty and practical loss as separate report fields. A finite posterior
under a proper prior must not conceal singular likelihood information. A
practical conclusion belongs to a model, profile and tested domain; disagreement
between the two models is an outcome to quantify, not permission to select the
more favorable answer after evaluation.

Select the smallest cell set that distinguishes these mechanisms; retain an
explicit expected rejection or inconclusive outcome for negative controls:

- **Prior/label effects:** matched data and geometry, informative versus sparse
  ratings, rater-ID permutations and selected rater counts. Declare how source
  distinguished-rater status moves under a permutation. Check exchangeable
  invariance separately from the expected source/legacy label sensitivity;
  these counterexamples do not yet measure posterior decision shifts.
- **Geometry and assignment:** separated, near-parallel, weak and rank-deficient
  loadings; pure versus selected within/mixed Q; sufficient, sparse and
  disconnected overlap. Separate rank/identification checks from practical
  precision and distinguish wrong-Q fits from well-specified recovery.
- **Boundary responses:** all-minimum raters, all-maximum persons and unused
  categories, reusing the [existing stress generator](src/mgmfrm_response_stress.jl)
  where supported. Distinguish model-generated extremes from deterministic
  contamination. Do not request simultaneous all-minimum/all-maximum patterns
  at a shared observation; the existing combined case uses nonoverlapping
  targets. New geometry cells need their own checked generator mapping.
- **Calibration versus robustness:** under each model, prior-generated
  calibration and fixed-truth recovery answer different questions. Use common
  declared truths/data for comparative performance, and separate contamination
  or misspecification outcomes; neither a shared generator/fit kernel nor a
  favorable own-prior result is independent validation.

For each retained cell, give its mechanism, decision profile, expected outcome,
generator/fit mismatch and applicable metrics. Size independent datasets by
the required Monte Carlo precision for recovery, coverage, loss and failure
rates; chains and multiple fits on one dataset are not new replications.
Report planned, started, completed and diagnostically usable attempts and the
applicable denominator for every metric. Paired model contrasts need the same
response data and their joint usable subset plus missing/failure counts; a
successful-only contrast cannot certify the full planned domain. Pilot tuning
and its data stay outside fresh evaluation. No cell count, seed roster,
scientific margin or experiment budget is adopted by this proposal.

### User workflow, API naming, and visualization

**Status: fit-taking posterior interval, trace/rank, category predictive and
stable MFRM Wright-map figures implemented; the stable MFRM and both guarded
generalized examples now run through save/reload and optional figures.
Public-content corrections are verified below; report integration and the
unfamiliar-reader walkthrough remain open.**
The acceptance unit is a user's completed analysis task, not the number of
exports, plotting-data helpers, report sections, or generated files. Keep
scientific validity and usability as separate requirements: neither a polished
figure nor a complete numerical report satisfies both.

#### Current UX baseline

| Observed surface | Consequence and reuse boundary |
| --- | --- |
| The [root API contract](src/root_api_contract.jl) lists 137 stable, five compatibility and 44 research bindings | Classification exists, but the 186-name root surface does not reveal a short ordinary workflow. Keep useful names such as `fit`, `validate_design`, `posterior_summary` and `fit_report`; reducing name length alone is not the objective |
| `mfrm_spec(...; family = :mgmfrm)` and the MGMFRM selector `discrimination = :none` | The latter still fits Q-masked discriminations. Resolve terminology and model selection together; an apparently simple name must describe the actual model |
| `fit(spec)` already delegates to `fit(getdesign(spec))`; [the minimal example](examples/minimal.jl) is now 56 lines, down from 181 | The default Julia NUTS route prints diagnostics and summaries, saves/reloads the fit, and optionally exports four figures. Design inspection and manual cache keys are optional; advanced reporting uses the existing manual |
| Generalized `posterior_summary` uses raw coordinates; qualified `BayesianMGMFRM.direct_posterior_summary` uses transformed parameters; `fit_report` includes direct summaries by default | Both guarded examples now print model-scale summaries and generate model-scale intervals plus raw-coordinate diagnostics from the saved fit. MGMFRM preserves named dimension selection. Existing draws and serialized objects retain their meanings |
| `wright_map_data` and `diagnostic_map_data` serve stable MFRM; calibration, predictive-check and recovery helpers return plotting rows | Category-proportion and stable MFRM Wright-map rows now feed finished figures; the remaining rows are reusable inputs. Do not advertise a generalized Wright map or MGMFRM rater report on the strength of stable-only methods |
| [Report bundles](src/bayesian_fit.jl) contain JSON, JSON tables and Markdown; qualified `BayesianMGMFRM.plot_posterior(fit)`, `BayesianMGMFRM.plot_diagnostics(fit)`, `BayesianMGMFRM.plot_predictive(fit)` and `BayesianMGMFRM.plot_wright(fit)` return editable figures | The optional CairoMakie extension consumes existing fit draws, summaries and transforms; the Wright map is stable MFRM only. Report-bundle figure integration remains pending; the historical batch-specific SVG script is not the user plotting engine |

The initial API/visualization inspection did not rerun package tests or fit
models. Later figure checks and native example runs are recorded below; they
do not establish that the current uncommitted tree passes CI. The longer
[archived UX proposals](docs/internal/archive/roadmap-2026-09-05.md#integrated-summary-warnings-persistence-and-visualization)
remain background: extra save/load aliases, HDIs and every diagnostic plot are
not prerequisites for the first delivery below.

#### Delivery order and dependencies

| Slice / responsible role | Concrete deliverable | Completion evidence and dependency |
| --- | --- | --- |
| Public content and ordinary workflow — maintainer, with analyst input | The [README/manual/help correction](#public-documentation-cleanup-2026-09-14) and short data -> specification -> fit -> diagnostics/summary -> figures -> save/reload route are implemented; retain their factual consistency during report integration. Record proposed spellings, old-to-new mappings, version/stability policy and affected callers only for actual API changes | Source, live-help and fresh-HTML checks now pass; unfamiliar-reader acceptance remains pending. The introductory path needs no custom printing helpers, private names, manual cache keys or compulsory design inspection. A user can identify the fitted family, restrictions and warning status. Preserve experimental boundaries and old calls; proposed figure operations stay out of runnable public examples until implemented |
| Draw and interpretation mapping — analyst/maintainer | Reuse fit draws, chain IDs, iterations, parameter layouts, direct transforms and existing report summaries behind the selected user operations. Allow selection by named parameter, facet/block and dimension, with explicit computational versus model scale | Stable MFRM and computational diagnostics can proceed without full M1 freeze. A generalized interpretation view needs the accepted model/scale slice, not completion of M2. Verify reconstruction of constrained coordinates, label/chain alignment, actual prior metadata and unchanged old-artifact interpretation; never silently change the existing raw-summary default |
| Standard figures — maintainer | Deliver fit-taking MCMC diagnostics, posterior interval plots, posterior predictive/calibration plots, and the supported MFRM Wright map. Return editable figure objects with documented display and PDF/SVG saving. Reuse one plotting backend and existing numerical consumers | First exercise existing stable fits and explicit generalized cases with known scale metadata; new scientific-model figures follow their verified implementation. Check every advertised family/plot combination. A stable-only plot remains explicitly unavailable for unsupported generalized fits. Plotting must not trigger a refit or require research artifacts |
| Integrated report and user walkthrough — maintainer, analyst and a reader unfamiliar with the implementation | Extend the existing report/bundle route with selected figures, captions and numerical tables from the same analysis settings. The stable minimal and both guarded examples now supply the short path | From a documented setup, the reader can fit, inspect a warning, select a rater/dimension, save/reload the fit through the existing cache/persistence route, and regenerate an editable figure and report without handling draw matrices. Record task outcomes and remaining friction. This is usability evidence, not independent scientific review |

**Immediate UX work:** integrate selected figures with the existing reports
and bundles, then record the unfamiliar-reader walkthrough. Short stable and
guarded workflows and public-content corrections are verified below. Preserve
the existing qualified figure names and compatibility bindings; no new API
registry or model decision is needed for the report integration.

Select `BayesianMGMFRM.plot_predictive` in place of the earlier proposed
abbreviation `plot_ppc`; no alias is added. It joins
`BayesianMGMFRM.plot_posterior`, `BayesianMGMFRM.plot_diagnostics` and now
`BayesianMGMFRM.plot_wright` as a qualified optional entry point.
Prefer clear, consistent names to cryptic abbreviations. Resolve the
`mfrm_spec`/discrimination mismatch against the accepted model specification.
Keep existing 0.1.x bindings and serialized type identities; a change to the
frozen export set needs an explicit version/migration decision and matching
API-contract tests, not an unnoticed extra export. Research helpers can leave
the introductory documentation now; moving/removing their bindings belongs to
that compatibility decision.

The first renderer review evaluated optional CairoMakie against installation,
headless operation, figure editing and PDF/SVG export needs. Its
[official backend documentation](https://docs.makie.org/stable/explanations/backends/cairomakie.html)
supports vector output, and [Julia package extensions](https://pkgdocs.julialang.org/v1/creating-packages/#Conditional-loading-of-code-in-packages-(Extensions))
allow plotting code to load only with its dependencies. The implementation
decision below selects this renderer. Retain backend-independent rows for custom work;
do not require users to assemble those rows to obtain standard figures. Avoid
multiple initial backends, a custom graphics engine, or a separate dashboard.

**First interval-figure implementation decision, 2026-09-14:** select CairoMakie
0.15 as a weak dependency and Julia package extension. The installed 0.15.13
renderer is the initial verification target. Add the qualified, opt-in
`BayesianMGMFRM.plot_posterior(fit; ...)` entry point for the next additive
0.1.x release; retain the exact root export set, existing names and serialized
type identities. No release/tag is made by this implementation. Stable MFRM
and the existing experimental GMFRM/fixed-Q MGMFRM fits keep their respective
support status. Default the figure to model coordinates, allow explicit raw
coordinates, and retain the existing numerical summary defaults unchanged.
Reuse the existing posterior summaries and constraint transforms, separate
blocks/dimensions into axes, label fixed coordinates as constants, and return
the native editable Figure. Use CairoMakie's own display/save functions;
do not add a figure wrapper, custom serializer or required plotting dependency.
Ordinary tests cover numerical/selection contracts without CairoMakie; a
separate optional test exercises the extension, editing, PDF/SVG export and
fit-cache reload on Julia 1.10.8 and 1.12.5.

#### First interval-figure verification, 2026-09-14

`BayesianMGMFRM.plot_posterior` now supports stable MFRM and existing experimental
GMFRM/fixed-Q MGMFRM fits, including block/parameter/dimension selection, model
and raw coordinates, fixed anchors and derived threshold constraints. Each of
Julia 1.10.8 and 1.12.5 passes **266 numerical/selection checks plus 41 optional
render/cache checks** with normal compilation. These are deterministic synthetic
draw fixtures, not new sampler runs or statistical validation. The final PDF
exports for all three families were rendered and visually inspected; row order,
spacing, fixed markers, long dimension labels and editable native output were
also checked. Earlier iterative passes are excluded from the final 614 total.

The public guide/help and README now describe the implemented operation. The
existing manual build succeeds, and the language gate passes 19 public source
files and 14 freshly generated HTML pages. Four existing missing-docstring
warnings for research/release helpers remain; the new plotting help is included.
These checks do not close the broader semantic cleanup or unfamiliar-reader
walkthrough. The optional test environments retain CairoMakie 0.15.13; root
inference dependency graphs and exports are unchanged. Project hashes were
updated for the optional dependency declaration. Commands, logs, environment
manifests and final figures are retained in the local ignored
[verification receipt](results/posterior-plots/20260914-01/receipt.json).
No full-suite, CI runtime-budget, new scientific-model or release acceptance
follows. The subsequent trace/rank implementation is recorded below.

#### Trace/rank figure implementation, 2026-09-14

Retain the same CairoMakie extension and additive qualified-entry-point policy
for `BayesianMGMFRM.plot_diagnostics`. No export, dependency, version, sampler or
serialized type change accompanies it. Shared coordinate reconstruction and
selection now serve interval and diagnostic figures; the interval summarizer
still uses the existing numerical consumer. Trace/rank defaults to raw
computational coordinates, with model coordinates selectable. The default
12-coordinate limit rejects an oversized selection rather than hiding rows.

Preserve every retained chain/iteration using the existing fit-layout check.
Use deterministic pooled average ranks for ties, chain-normalized bin counts
and a pooled reference that retains ties. Existing parameter R-hat/bulk/tail ESS
and whole-fit diagnostics supply the captions; generalized fits retain their
recorded thresholds and diagnostic-contract checks. Fixed and constant values,
single chains, absent/partial sampler statistics and derived coordinates without
stored diagnostics are explicit, not successful checks. Warmup draws are not
reconstructed; pairs/divergence overlays and energy plots remain separate work.
The existing [bayesplot rank-plot guidance](https://mc-stan.org/bayesplot/reference/MCMC-traces.html)
informs interpretation, not an additional package dependency or a new diagnostic
acceptance rule. The subsequent conditional predictive figure is recorded below.

Final normal-compilation checks pass **480 assertions per Julia 1.10.8 and
1.12.5**: 266 interval regressions, 128 trace/rank data checks and 86 optional
render/cache checks. The final PDFs for all three families were rasterized and
visually inspected; fixed/derived and single-chain views were also inspected.
Checks use deterministic synthetic draws, including two chains of 20 draws;
there was no sampler execution or backend-equivalence experiment. Initial
iterations are excluded from the final 960 assertions. Fresh live help,
19 public source files and 14 generated HTML pages pass the existing language
checks; the manual retains the four previously recorded missing-docstring
warnings. Projects, manifests, root exports and include boundaries are unchanged
in this slice. The local ignored
[receipt](results/posterior-plots/20260914-trace-rank-01/receipt.json) retains
commands, source hashes, logs and final figures. Full-suite, runtime-budget,
scientific and unfamiliar-reader acceptance remain open.

#### Category predictive figure implementation, 2026-09-14

`BayesianMGMFRM.plot_predictive` reuses `posterior_predictive_check`,
`predictive_check_summary` and `predictive_check_plot_data` through the same
optional renderer. It compares observed category proportions with replicated
means and pointwise central predictive intervals (90% by default), retaining
every declared category. Replications condition on the original rating rows
and fitted persons, items and raters. Whole-fit diagnostic warnings remain
visible; this aggregate same-data check is not new-facet validation.

By default use every retained draw once; `ndraws` samples indices with replacement
and `draw_indices` preserves explicit order and duplicates. A local seeded
MersenneTwister (default seed 1) supports exact replay after cache reload in the
same software environment. The caption distinguishes replications from distinct
posterior draws. Changing interval width does not change the replicated scores.
The shared categorical sampler now rejects invalid probability vectors before
consuming randomness: previously NaN or all-zero probabilities silently selected
the last category. The guard serves stable/generalized prediction and local
dependence replication; valid probability sampling retains its original sequence.

Final scoped checks pass **808 assertions per Julia 1.10.8 and 1.12.5**: 266
interval, 128 trace/rank, 294 predictive and 120 rendering/cache checks. Final
PDFs for all three supported fit families were rasterized and visually inspected,
including a separate zero-count-category view. Live help, 19 public sources and
14 fresh HTML pages pass the language checks; the four existing omitted research
docstrings remain. The local ignored
[receipt](results/posterior-plots/20260914-predictive-01/receipt.json) preserves
commands, final figures and hashes. Projects/manifests, exports, include lists
and fixtures are unchanged. These use synthetic parameter draws with simulated
responses, not native Julia/CmdStan MCMC or statistical validation. No full-suite,
CI/runtime, release or unfamiliar-reader acceptance follows. The subsequent
stable MFRM Wright map is recorded below; broader predictive displays and report
integration retain their own scope and evidence requirements.

#### Wright-map implementation decision, 2026-09-14

Select qualified `BayesianMGMFRM.plot_wright` in the same CairoMakie extension,
with no new export, dependency or serialized type. Reuse `wright_map_data` for
stable MFRM rating-scale/partial-credit fits only. Place facet levels and item-step
boundaries on linked vertical logit axes, retaining posterior intervals and
explicit fixed references/anchors. Preserve facet order and use a visible
60-position limit, adjustable by the caller; never silently drop levels.
Threshold boundaries mean item difficulty plus step at zero rater severity,
not expected-score half-points. Retain the item's and step's joint uncertainty.
Correct fixed-position metadata and reject derived overflow in the shared
numerical helper so custom plotting and diagnostic-map callers receive the same
correction. Verification remains distinct from native backend or scientific
validation. No generalized Wright-map support is inferred.

Final normal-compilation runs pass **1,351 assertions per Julia 1.10.8 and
1.12.5**: 266 interval, 128 trace/rank, 294 predictive, 380 Wright-map and 283
render/cache checks. Six stable cases cover RSM/PCM, binary data, nonzero anchors,
and long labels with unused categories. Tests verify joint item-step quantiles,
adjacent-category equality, facet signs, structural fixed values, overflow
rejection and exact plotting-input recovery after cache reload. Final PDFs were
rasterized and inspected; vertical labels correct the initially observed clipping.
Fresh live help and language checks pass 19 public sources and 14 generated
HTML pages, with the four existing omitted research docstrings unchanged.
Commands, source hashes and figures are in the local ignored
[receipt](results/posterior-plots/20260914-wright-01/receipt.json).
These are synthetic presentation/consumer checks, not native Julia/CmdStan MCMC
or statistical validation. Projects/manifests, exports, include lists and the
shared fixture are unchanged. Full-suite, CI/runtime, release and reader
acceptance remain open. The subsequent short ordinary workflow is recorded below.

#### Short stable MFRM workflow, 2026-09-14

`examples/minimal.jl` now uses 56 lines for ratings, validation, `fit(spec)`,
diagnostics, compact posterior summaries and checked fit save/reload. The default
is Julia AdvancedHMC/NUTS. Optional `--plots` loads CairoMakie before sampling
and writes interval, trace/rank, category predictive and Wright-map PDFs plus a
Wright-map SVG from the reloaded fit. Each run retains its own output directory;
`--cmdstan` uses the same specification and a fresh empty build directory.
README and the existing fitting/examples guides explain setup and later-session
figure editing. The examples guide also corrects its scalar GMFRM claim: the
implemented kernel estimates positive item discrimination and rater consistency.
No public API rename, helper, dependency or fitting-kernel change is needed.

Four final native runs pass **52 workflow assertions**: 11 for Julia 1.10.8
without plotting, 13 with plotting on each of Julia 1.10.8 and 1.12.5, and 15
for CmdStan 2.39.0 with plotting on Julia 1.12.5. Each also executes the example's
summary-equality assertion. Every run uses two chains with 50 warmup and 50
retained draws per chain and retains its diagnostic warning; these are execution
checks, not convergence or backend posterior-agreement evidence. A separate
fresh-session cache/figure check is recorded with the verification details in
the [backend note](docs/internal/normalized-prior-backend-comparison.md#short-stable-mfrm-workflow-2026-09-14).
No MCMC draw reshaping is required. Source, extension, test and script files,
Projects/manifests, exports and include lists are unchanged in this slice.

The guarded-example and public-cleanup follow-ups are recorded below.
Report-bundle figures, unfamiliar-reader acceptance, M0 runtime work and M1
scientific validation remain open. Julia remains primary; CmdStan remains maintained.

#### Guarded GMFRM/MGMFRM workflows, 2026-09-14

The existing GMFRM and MGMFRM examples are reduced from 103 lines each to 60
and 67 lines. They validate data, retain explicit `Experimental.fit` opt-in,
print diagnostics and qualified `BayesianMGMFRM.direct_posterior_summary`, and
check model-scale summary recovery after saving/reloading. `--plots` exports
three PDFs plus a posterior SVG from the saved fit; `--cmdstan` selects the
companion backend with a fresh build directory. GMFRM displays positive rater
consistency intervals and raw log-consistency traces. MGMFRM displays separately
named abilities and selects a dimension by label for diagnostics. Prediction
uses the same fitted rating rows. Wright maps remain stable MFRM only.

README and the fitting/examples guides now describe the actual 50-warmup,
50-retained-draw, two-chain controls, raw/model-scale distinction, outputs and
later-session editing. The two-item MGMFRM dataset remains an API demonstration,
not identification or substantive multidimensional evidence. Final Julia/CmdStan
workflow checks pass 175 assertions, with eight further fresh-session figure
checks. Verification and its limits are recorded in the [backend note](docs/internal/normalized-prior-backend-comparison.md#guarded-gmfrmmgmfrm-workflows-2026-09-14).
Live-help inspection exposed a missing model-scale-summary docstring; that help
and its existing API-reference entry are now supplied. No export, source kernel,
prior, dependency or serialized type changes are needed.
The public-content follow-up below precedes report-bundle figure integration
and the unfamiliar-reader walkthrough; none closes M0 or M1 by itself.

#### Public documentation cleanup, 2026-09-14

README is reduced from 700 to 265 lines. Public data/workflow/model/fitting and
migration pages now separate ordinary analysis from research execution plans,
resource probes, CI details and deferred anchor implementations. Existing
research owners retain missing commands and deferred contracts; historical
fixed-Q resource instructions remain in the existing archived roadmap, while
current M1/M2 decisions remain above. Research API schemas and compatibility
bindings retain their meanings. Stable and guarded support, raw/model scales,
`1.7`/`1.702`, Jacobians, priors, exact anchors and CmdStan restrictions remain
explicit. Live help replaces scaffold/Stage-0 descriptions with object behavior.

Julia 1.10.8 passes 35 checks: three parsed-code comparisons excluding docs and
source locations, 22 live-help checks and ten ordinary-data/preview checks.
Every other source, extension, script, test and runnable example is byte-identical
to this slice's starting tree, as are Projects/manifests, root exports and
serialized definitions. No MCMC, package installation or external fit ran.
The final Julia 1.12.5 manual build and language checks pass in 15.12 seconds:
19 public sources and 14 fresh HTML pages. Inspection found ten broken HTML
fragment links; corrected Documenter heading IDs now pass all 455 local
fragment links with no missing local files. Internal owner pages are absent
from generated navigation/search. Four pre-existing omitted research/release
docstrings remain outside the published manual. Details and preserved checks
are in the [existing workflow owner](docs/internal/normalized-prior-backend-comparison.md#public-documentation-cleanup-2026-09-14).
This closes the bounded editorial/runtime-help correction, not independent
reader, full-suite/CI, release, model-validity or scientific-review acceptance.

#### Report-bundle figure integration, 2026-09-14

`save_fit_report_bundle` now accepts optional posterior, trace/rank, conditional
category-predictive and stable-MFRM Wright figures from a saved fit. Existing
numerical and CairoMakie helpers supply the figures and captions; predictive
figures consume the report's exact summary rows and selected draws. PDF/SVG
and numerical-input JSON exports share the report's interval/diagnostic settings.
Figure bundles use manifest v2 with file hashes; ordinary v1 bundles and report/
table schemas remain compatible. Readers require neither CairoMakie nor a fit.
Summary-only figure requests and unsupported selections fail explicitly.

Julia 1.10.8 and 1.12.5 each pass 278 bundle checks across the three families.
The final no-renderer pass covers 46 checks, including both versions' exports,
missing files, symlinks and downgraded manifests. The existing report regression
passes 128 checks; its single two-draw Julia fit is distinct from the synthetic
draws used by every figure test. The existing standalone plot/cache regression
passes 1,351 checks on Julia 1.12. All ten primary Julia 1.12 bundle PDFs were
visually inspected. Manual/language checks pass for 19 sources and 14 fresh
HTML pages; all 458 local fragment links resolve. Details, attempt history and
remaining limits are in the [existing workflow owner](docs/internal/normalized-prior-backend-comparison.md#report-bundle-figures-2026-09-14).
No inference kernel, dependency or public export changes were needed. This
closes the bounded integration task; independent reader acceptance remains open.

#### Public documentation and help acceptance

**Initial observation on 2026-09-11, before corrections.** The short-workflow
changes and the dated cleanup above now cover the observed content defects;
unfamiliar-reader acceptance remains open. The following records the initial
findings and the acceptance criteria retained for future edits. The existing
[source-language check](scripts/public_language_gate.jl) examined 19 public
files and returned four language violations, all README links into the
supporting anchor-study document (lines 321, 323, 331 and 337 at inspection).
Navigation and workflow checks returned zero violations. The 14 saved public
HTML pages passed the rendered-language check, but those files were generated
on 2026-09-05 and visibly retain development-stage wording. They are neither
a fresh build of the edited source nor evidence of reader usability. Live
Julia help was read for `FacetData`, `MFRMFit`, `getdesign`, `fit`, `MGMFRMFit`
and `mgmfrm_validation_protocol`; the first four retain `scaffold` wording.
No fit or full package test was run for this inspection.

| Surface / existing owner file | Required treatment | Reader-visible completion condition |
| --- | --- | --- |
| [README](README.md) | Keep purpose, actual model support, installation, a short current analysis, essential limitations and manual links. Move the approximately 180-line study/resource discussion following Quick Start to its existing research owner, merging only missing information. Reduce the detailed CI/resource/quiet-wrapper instructions to a brief contributor route | An ordinary analysis does not require Stage 1--3, cell rosters, resource-review receipts or permission to execute the package's validation study. Clearly distinguish released from development-only behavior; all runnable examples use available APIs for the stated revision |
| [Fitting](docs/src/fitting.md) and CmdStan help | Keep actionable backend requirements in the public guide: current cache-directory behavior, rejected Make environment settings, readiness versus compilation, and errors. Replace the four README links to internal proposals with a self-contained public explanation and an appropriate public-manual link | Removing the internal links does not conceal cache-reuse restrictions or change backend behavior. A user can resolve a supported configuration error without reading the anchor-study methods draft |
| [Data validation](docs/src/data-validation.md), [Bayesian workflow](docs/src/bayesian-workflow.md), [scope](docs/src/scope.md) and [home](docs/src/index.md) | Explain the user's input, action, output and interpretation. Move `Primary work order`, LD1a/LD1b0/LD1b1 progress, study freeze decisions and execution sequencing out of ordinary analysis instructions; retain applicable diagnostic and evidence limitations in plain language | Readers can distinguish an available diagnostic from a fitted effect and from an unvalidated decision rule, without learning internal milestone names or mistaking research-execution blocks for a ban on ordinary fitting |
| Public help in [facet_workflow.jl](src/facet_workflow.jl) and [bayesian_fit.jl](src/bayesian_fit.jl) | Replace development-era descriptions such as `v0.1 design scaffold` with the supported data/model/result behavior. Lead with purpose, then inputs/defaults, return values/scale, a short example and relevant limits. Keep actual argument names and important raw/direct distinctions | `?FacetData`, `?getdesign`, `?fit`, `?MFRMFit` and generalized result help agree with the manual and implementation. No implementation detail is removed when needed to interpret a returned field, but the reader need not infer maturity from historical scaffolding language |
| [GMFRM example documentation](docs/src/examples.md) versus [experimental model description](docs/src/experimental.md) | Resolve the statement that scalar GMFRM does not support item discrimination: its current kernel uses positive item discrimination times rater consistency. State the restricted fitted structure, distinguish the compatibility selector from the actual parameters, and retain the partial-credit/no-anchor/no-DFF restrictions | README, example, help, model-family contract and equations describe the same fitted structure. Correct existing prose without claiming unrestricted discrimination or complete source-prior reproduction; verified changes for the two future scientific models get their own explicit descriptions |
| [Model equations](docs/src/model-equations.md), [experimental scope](docs/src/experimental.md), [fitting](docs/src/fitting.md) and [migration guide](docs/src/migration-facets-conquest.md) | Present the actual model choices using the model axes above: explicit abilities, fixed/estimated slopes, Q structure, aggregation, latent covariance and fitted effect blocks. Explain literal `1.7` versus reference `1.702`, and raw versus direct prior measures. Separate Julia/CmdStan backend selection from ConQuest/TAM migration/comparison | Users can identify what their chosen model estimates without interpreting `discrimination = :none` as fixed unit loadings, assuming free correlations, or treating a bifactor-shaped Q as validated bifactor support. Describe available behavior and limits, keeping proposed extensions and internal acceptance work in their research owner |
| [API reference](docs/src/api.md) and [research-helper reference](docs/src/api-validation-evidence.md) | Lead ordinary users to stable workflow operations. Keep retained research helpers clearly labeled in their advanced reference/help; remove instructions to future developers such as how to expand the root namespace | Source compatibility and stable/compatibility API documentation coverage are preserved. Research-return schemas may still document their actual status fields; they do not become ordinary analysis prerequisites or mature model claims |

Use existing research/protocol notes as destinations for developer material;
do not paste every removed paragraph into this roadmap or create a parallel
manual. Preserve genuinely missing methodological rationale and links once.
The existing placement review already keeps repository-only pages out of the
public build; the repair is primarily within published pages and docstrings.
Check generated navigation and search entries after edits so removed content
does not survive in stale output.

Acceptance requires both factual consistency and an understandable sequence:
what the user wants to know -> the operation and why -> its output -> the
interpretation and next action. For a few representative documented tasks,
compare actual model family, discrimination/loadings, thresholds, prior scale,
raw/direct summaries, fixed coordinates, prediction target and support status
across the existing implementation, help and guide. Reuse existing model tests
and contracts; no second capability registry or prose-to-source hash ledger.
Explicitly retain experimental/unsupported status, unknown or insufficient
evidence, and real operational limitations. Do not turn editorial cleanup into
a stronger scientific claim or change inference to match stale documentation.

Verification retained for documentation edits (source/help/HTML completed
above; the reader check remains pending):

1. Run the existing source-language/navigation checks and inspect each affected
   section semantically. Close the four observed README findings and the
   documented content contradictions; four removed links alone are insufficient.
2. Read live help from the edited package and make a fresh manual build with
   the existing [build entrypoint](docs/build.jl). Scan the resulting HTML with
   the rendered-language check; inspect navigation/search and the relevant API
   pages, rather than relying on Markdown or a September 5 build alone.
3. Check runnable examples against their stated revision using existing bounded
   example checks when execution is needed. Keep snippet parsing, actual
   execution and scientific validation distinct; do not execute copied research
   probes to validate documentation. Public plot examples wait for callable plots.
4. In the existing unfamiliar-reader walkthrough, require users to find the
   relevant function, understand its return scale and warning, and reach the
   next analysis step without internal notes. If no reader has performed it,
   record it as pending rather than treating an automated scan as a substitute.

Retain the existing language checks as regression tools. Add a narrow rule
only for a demonstrated recurrent leak with a meaningful check; do not weaken
them to pass the current links or add a blanket blacklist of `experimental`,
`validation`, `internal consistency`, or research API status fields. An allowed
word can still form a misplaced work order, and an accurate restriction is
still necessary user guidance. Record source, live-help, rendered-content and
reader-review outcomes separately against the edited revision.

#### Figure and report acceptance

- **Diagnostic meaning:** preserve chain and iteration identity for traces and
  rank views; show R-hat, bulk/tail ESS and available sampler warnings from the
  existing diagnostics. Insufficient chains/draws or absent backend statistics
  are unavailable, not successful diagnostics. A bounded overview identifies
  its displayed subset and allows named selection; it must not hide problems
  elsewhere. Add pairs/divergence or energy views when the needed statistics
  are present and a diagnostic task requires them. Report-construction health
  is not convergence or model adequacy.
- **Parameter meaning:** default interpretive figures to the declared model
  scale, with computational scale explicitly selectable. Show facet IDs,
  dimension names, constraints and fixed anchors; fixed values are not sampled
  intervals. Distinguish posterior dependence from fixed latent-population
  correlation. Preserve named ability dimensions rather than collapsing them
  into a single score; any composite or joint threshold event needs its declared
  weights/rule and joint-draw uncertainty. General/specific-factor labels and
  summaries apply only to an explicitly supported factor structure.
  Multidimensional abilities, loadings and thresholds cannot be
  placed on a common Wright-map axis without a justified mapping. Reference
  lines and practical margins must match the estimand, not a universal zero.
- **Uncertainty and prediction:** reuse declared interval levels and methods;
  label posterior credible intervals separately from predictive intervals and
  MCMC error. Do not introduce HDIs or change existing interval defaults in the
  first plotting slice. State the observed/replicated statistic and conditioning;
  same-data predictive checks and calibration are not heldout validation or
  new-person/item/rater prediction. Unobserved declared categories remain visible.
- **Reproducible output:** figures, captions and tables agree on model/prior
  identity, selected parameters, scales, interval policy and diagnostic status.
  Use the same checked summaries or selected draws; retain RNG/selection settings
  for stochastic predictive displays so saving/reloading does not silently
  regenerate different checks. Rendering consumes those results and starts no
  MCMC. Preserve existing JSON readers and bundle compatibility through explicit
  optional entries/schema handling; summary-only saved reports cannot recreate
  traces, so request the saved fit with a clear message instead of fabricating draws.
- **Readable, editable output:** inspect PDF/SVG exports for clipping, crowded
  labels, font sizes and readable grayscale/color-vision-safe encodings; do not
  communicate warnings by color alone. Expose labels, order, dimensions and
  interval controls through the returned figure or small documented options.
  Captions identify the estimand and uncertainty without exposing internal
  provenance tokens or implying a model/claim has passed independent review.

Verification should use a small deterministic fit/draw example exercising
chain separation, transformed and fixed coordinates, unavailable diagnostics,
and equality with existing summary rows, followed by visual inspection of the
exported figures and the saved/reloaded workflow. Test one supported combination
per advertised family and explicit unsupported cases; reuse existing numerical
tests rather than duplicate inference. Keep ordinary loading usable without the
optional backend; exercise rendering in a bounded optional-dependency check and
measure its added load/export cost without relaxing existing runtime gates.
Use separately bounded pilot data only if a real fit is needed for integration;
these checks add zero evaluation replications and do not replace M1/M3 review.

## Immediate work and stop conditions

Prioritize the Julia foundation. The canonical fixed-coefficient experimental
fit, manual cache, report and figure workflow is connected. Its generic example
covers both backends; the [owner's record](docs/internal/normalized-prior-backend-comparison.md#experimental-fixed-coefficient-fitting-2026-09-15)
separates bounded operability from statistical acceptance. The private correlated density has
a [model/coordinate contract and sampler-free checks](docs/internal/normalized-prior-backend-comparison.md#correlated-fixed-coefficient-density-2026-09-15).
The next concrete output is its private sampling/reconstruction/persistence
path. Application data preparation and reader recruitment do not block this
core work.

The numbered rows are bounded handoffs, not a requirement to finish every
specification before making a routine correction. Work on an accepted model
slice can proceed without waiting for unrelated extensions or an empirical
study. CmdStan checks accompany that slice; fresh statistical evaluation still
needs its reviewed protocol and resource/launch decision. Public documentation
corrections and supported-scope plots run alongside the numerical work. Their
priority follows the Julia user workflow, not the readiness of a paper dataset.

| Task / owner role | Next deliverable | Verification and stop condition |
| --- | --- | --- |
| 1. Correlated fixed-coefficient sampling/results — analyst/maintainer; density contract and common-coordinate checks implemented | Reuse existing Julia/CmdStan samplers for the private 2D target and create its separately tagged sample/reconstruction record, preserving actual priors, rho coordinates and target identity | Exit: bounded sampling/save/reload reconstructs retained densities, chains, telemetry and model quantities under both backends; invalid options fail before execution and old caches remain unchanged. Public fitting/report integration and statistical recovery/coverage remain separate |
| 2. M1 Julia model-to-code contract and estimation path — analyst/maintainer | Resolve the relevant source/exchangeable-prior, identification and validation-scope decisions; correct demonstrated shared-path gaps and retain the [core trace's remaining failure boundaries](#first-julia-core-verification-slice). Prepare the next covariance/within-item slice under the [extension sequence](#long-term-extension-sequence), reusing existing components | Exit: equations, coordinates, scale constants, priors/Jacobians and parameter meanings have code/evidence mappings and explicit unresolved decisions. Check target/gradients, invalid inputs, initialization/sampling failures and result integrity as affected. Record actual runtime/resource limits; model changes have distinct identities. No copied fitting engine or blanket source refactor |
| 3. CmdStan continuity — analyst/maintainer; accompanies each model slice | Maintain estimation of the same target under the [dual-backend contract](#julia-and-cmdstan-continuity-and-comparison); check common-coordinate densities, gradients and probabilities, then diagnostic-qualified posterior/predictive summaries under the execution budget | Exit: both routes preserve likelihood, priors, constraints, scale and saved-result meaning. Missing parity remains partial support; Julia work can advance incrementally without dropping this requirement. Backend agreement is implementation evidence, not model validity |
| 4. M2 core statistical validation — analyst; execution not started | Reconcile Stage-A with the accepted package model/claim. Select known-truth conditions for identification, recovery/calibration, sparse coverage, prior sensitivity and numerical failure mechanisms; verify scoring, all-attempt accounting and resource stops before reviewed execution | Exit: target-specific M1 and execution readiness are accepted, the bounded roster is accounted for, and uncertainty/failure rates support a stated domain or an inconclusive result. Representative Julia/CmdStan comparisons accompany it; do not restrict the core domain to the Uchihara design or substitute an empirical fit for recovery evidence |
| 5. Julia user workflow and public documentation — maintainer with analyst input; runs alongside rows 1--4 | Existing public-model [documentation/help](#public-documentation-cleanup-2026-09-14), standard figures, short saved-fit examples and [figure/report integration](#report-bundle-figure-integration-2026-09-14) are verified; record the unfamiliar-reader walkthrough. The independent fixed-coefficient example is available; document a correlated fitting workflow only after its result/report integration is verified | Exit: source/help/fresh-HTML consistency and [figure/report acceptance](#figure-and-report-acceptance) pass for the advertised scope, including save/reload and an unfamiliar-reader walkthrough without manual draw reshaping. Test reusable examples; neither a paper-specific script nor plotting-data rows close this task |
| 6. M3 supported-domain and package handoff — maintainer and independent reviewer | Reproduce selected model/numerical claims and the documented workflow in a separate environment at the recorded revision; make claim-level supported/narrowed/rejected/inconclusive decisions | Exit: usable Julia behavior, matching CmdStan evidence and independent scientific acceptance are reported separately. Public promotion retains its M0 gate and integration/release authority. Completion or publication of an application paper is not an exit condition |
| Long-term model extensions — analyst/maintainer; sequenced after the relevant foundation slice | Follow the [single extension sequence](#long-term-extension-sequence): correlated dimensions/within-item validation, configurable random effects, a specified non-compensatory ordinal kernel, and staged Q structure inference. Fixed-Q comparison and identification work can precede full structure learning | Promote one declared combination at a time with model-specific evidence, both backends and a complete user workflow. Independent block validation does not certify their composition. These are long-term deliverables, not newly available options or an automatic batch of implementation/research jobs |
| Uchihara reanalysis — analyst; secondary application, no fit completed | Follow the [staged application sequence](#application-sequence-and-reusable-dependencies) when each required model slice is ready: reconcile data, fit unadjusted measurement, then named generalized/phonetic comparisons and secondary outcomes. Use the example to assess practical interpretation and UX | Keep data preparation, application-specific raters/recording effects/covariates, empirical fits and report progress separate from core milestones. A discovered reusable defect returns to the core queue; case completion or the expected substantive result never defines Julia acceptance |
| ConQuest/TAM comparison — analyst/maintainer; supporting track | Complete the bounded [external-software handoffs](#conquest-and-tam-comparison-scope): ConQuest destination-scale mapping and estimator-aware comparison; TAM evidence reconciliation and independent-review handoff | Exit: scope, versions, parameter/uncertainty meanings and comparison decisions are explicit. Multidimensional comparisons wait for a matched model specification; historical MFRM evidence is not renamed MGMFRM validation. This is not a prerequisite for unrelated core implementation or a substitute for Julia/CmdStan verification |
| MFRM anchor sub-study — analyst; supporting track | Retain its [six freeze decisions](docs/internal/mfrm-anchor-study.md#freeze-decisions), 266-cell draft, resource proposal and reusable response/scoring checks; advance a piece when it addresses a core dependency or a separately selected anchor claim | All six decisions remain open. The 400/100 allocation is not automatically adequate for practical acceptance; the historical 20-assertion ordinal audit is not recovery evidence. Completing this panel does not certify generalized anchoring, and the full panel is not the next automatic launch |
| M0 observer integration — maintainer; local verification, candidate CI, and implementer review passed; unmerged | Use the [candidate CI and integration review](docs/internal/fitting-core-runtime-review.md#candidate-ci-and-integration-review) for the merge-approval handoff; no further fit is queued | At `5c4bff2`, all 12 ordinary CI jobs passed, including 21 guard cases on each of Linux/macOS; both manual research jobs were skipped. Verification C retains all 2,755 passing assertions and child/guard exit 0. PR #100 stays draft with auto-merge disabled; integration needs explicit approval. These checks repair local measurement, not the historical +23.4% acceptance trigger |
| M0 runtime acceptance — maintainer; open, deferred | Retain the [prospective acceptance proposal](#prospective-runtime-acceptance-proposal) and [minimal control changes](#minimal-control-change-proposal) as inactive options, not the next implementation task | No new measurement or criterion adoption. Resume for an actual study execution/cost blocker or a later release review; a new fast run still does not explain the historical trigger |

Completed work stays out of the active queue. **M0-DOC** closed at `bd22c01`:
both archived bodies were preserved with rebased links; 34 local links/fragments,
the Git-free install/load/example/manual smoke, and all 12 ordinary candidate-CI
jobs passed. That historical placement result does not close the newly observed
public-content defects; their bounded correction belongs to row 5 above.
**M0-BOUNDARY** retains the [123-fixture classification](docs/internal/fixture-boundary.md)
and [35 source / seven ordinary-script include review](docs/internal/code-load-boundary.md);
isolated loads passed on Julia 1.10.8 and 1.12.5 without research trees.
Reopen only for changed boundaries/consumers or measured budget pressure, not
to accumulate more completed checks. Relocation, large source decomposition
and new generic controllers remain out of scope. The UX backend proposal may
revisit optional dependencies and API migration for a concrete user workflow;
this roadmap refinement itself changes neither the load nor export boundary.
The single additional **verification C** is complete and is not a cache
experiment. Cold A remains a consumed attempt with observer exit 1; B never
ran. C neither resets nor completes that pair, and no further fit is queued.

### Next implementation handoffs

These completed outputs record the fixed-coefficient workflow handoff.
Experimental fitting, numerical reporting, figures and the generic example
are connected. They introduce no new sampler, result container or application-specific API. The numerical
report adapter builds on the `fcb282b` cache implementation. Focused checks and
earlier retained evidence do not constitute a full-suite pass or release acceptance.

| Output and dependency | Implementation boundary | Acceptance check |
| --- | --- | --- |
| Numerical reports — implemented | Dedicated `fit_report` and public report/artifact projections reuse the private assembler, full artifact and validated design rows. Central interval semantics, stored diagnostic settings and explicit unsupported sections are preserved | [Saved-result checks](docs/internal/normalized-prior-backend-comparison.md#canonical-fixed-coefficient-saved-result-reports-2026-09-15) cover reload/export, public hashes, named/fixed/derived coordinates and invalid inputs. Full artifacts and old caches retain their meanings. No sampling or plotting dependency is needed |
| Figure/report bundles — implemented | Dedicated plot and fitted-object bundle methods reuse the existing named-dimension figures and staged writer. Full/public exports share the numerical report's intervals and predictive simulation; CairoMakie remains optional | [Saved-result figure checks](docs/internal/normalized-prior-backend-comparison.md#canonical-saved-result-figures-2026-09-15) compare intervals, fixed/derived flags, chains, warning text, source/report hashes and exact predictive rows; verify selected PDF/SVG output and destination preservation on figure failure. Reader acceptance remains separate |
| Experimental fitting and usable examples — implemented | The restricted canonical fixed-coefficient route uses `Experimental.fit` and the existing surface contract. One generic specification -> fit -> diagnostics -> saved report/figures example selects either backend. Keep unsupported effects/correlations/predictors and automatic request caching unavailable | See the [bounded entry-to-reload and rejection checks](docs/internal/normalized-prior-backend-comparison.md#experimental-fixed-coefficient-fitting-2026-09-15); README, help and example describe the same API. A short fit proves operability only. Record unfamiliar-reader review and statistical-domain acceptance separately; root-level stable promotion is a later decision |

Keep the [detailed implementation handoff](docs/internal/normalized-prior-backend-comparison.md#next-bounded-work)
as the implementation reference. Correlation, random-effect and predictor
extensions follow their own accepted specification after the relevant foundation
slice; do not wait for Uchihara preprocessing or mixed outcomes to finish these
three outputs. Once an output is complete, replace its current status and next
action rather than adding another queue or duplicating the verification history.

### Decision handoff and progress accounting

The separate M0 engineering handoff retains the **observer correction, verification C, and
successful candidate CI at `5c4bff2`** in the existing runtime review.
The bounded implementer review found no blocking issue for the documented
local POSIX use; publication of this documentation update and integration
remain pending. CI for `5c4bff2` does not certify later edits, and this review
is not independent scientific acceptance. The active Julia handoff is now
**private correlated-ability sampling and separately identified saved results**,
following row 1 above. The relevant
model/prior and validation-scope decisions continue under row 2.
Application preparation does not precede this work. The existing
M1-01--06 identifiers and their proposals remain local to the MFRM anchor
sub-study; they do not become MGMFRM acceptance decisions by renaming them.
The user has selected Julia foundation work as the highest priority, retained
both estimation routes, and made Uchihara a secondary application. Prepare
concrete model, resource and review proposals within that scope; do not ask the
user to choose the priority again. Numerical priors, execution budget and
reviewer assignment remain open. No actual owner,
deadline or budget is assigned by this edit. Record an accepted assignment when
a person confirms it; lack of a reviewer does not block core specification or
implementation checks that do not claim independent scientific acceptance.

For each decision, retain only the proposal, missing input, linked evidence,
named decision-maker, and accept/request-revision outcome tied to a source
revision in its owning document. Do not create another task registry. Within
the anchor sub-study, review M1-06 against review-ready M1-01--05 proposals
and checks. For either study, **fresh M2 evaluation requires independently accepted target-specific
M1 and research execution readiness**, not closure of
the deferred M0 performance investigation. M3 still requires matched external
reproduction and claim-level decisions, not another implementation-authored receipt.

Report Julia core correctness and execution, CmdStan parity, model/protocol
acceptance, fresh known-truth replications, reusable UX/documentation and external
review separately. Track application data reconciliation, empirical fits and
reports as secondary progress; keep the anchor sub-study's six decisions on its
supporting track. Within each scientific model, distinguish
specification, verified implementation, reviewed protocol, fresh evidence and
independent domain acceptance; a shared passing kernel check is reusable but
does not close both models' remaining prior/scope gates. The legacy model's
compatibility coverage is reported separately. No weighted overall
completion percentage is defined; conversational estimates, test counts, and
document revisions are not evidence that a scientific gate has closed.
Track UX specification, public-content correction, callable implementation,
numerical/render verification and user walkthrough separately as well. The
2026-09-15 refinement retains Julia foundation work as the priority and adds
the explicit long-term extension sequence. Existing public-documentation and
figure/report corrections have their dated verification records; the earlier
failed source check and limited saved-HTML observation remain historical evidence.
The new fixed-coefficient public workflow and independent reader walkthrough
remain open. This roadmap edit adds no model implementation or statistical
evidence and does not report a naming migration or reader walkthrough as passed.

### Research execution prerequisites

Core validation has its own model/design roster and does not depend on a
particular empirical dataset. If an application such as Uchihara is scheduled,
retain its separate input derivation, inclusion rules, estimands, diagnostics,
backend comparisons and resource plan. Development probes and empirical fits
remain outside counts of fresh simulation replications. Core implementation
checks can proceed without waiting for application planning or the independent
review that governs scientific acceptance.

Before fresh M2 evaluation, retain one reviewed source/environment revision
and independently accepted target-specific decisions on model/identification,
cells/estimands, RNG/data allocation, scoring/thresholds, sampler settings,
failure handling, and budgets. The MGMFRM protocol's execution and independent
scientific-review blockers remain open; the anchor sub-study separately
requires all six of its accepted M1 decisions.
For MGMFRM, that acceptance must also resolve the selected loading geometry,
dimension alignment, conditional-information versus posterior-uncertainty
semantics, and source-statistic adoption limits above. Literature-derived
formulas and negative-control examples are inputs to review, not substitutes
for a target-specific validation result.
Verify the actual generation-to-fit-to-score path on that revision, including
truth and category alignment, saved response/source/attempt binding, no
replacement of failed primary attempts, and functioning time/resource stops.
Use the [source/environment requirements](docs/internal/mfrm-anchor-study.md#source-and-execution-environment-declaration-requirements)
to distinguish predeclared inputs, actual producer observations, and later
scoring metadata; collecting optional metadata is not environment acceptance.
Unresolved correctness or data-loss risks block execution; a green historical
CI or the deferred performance proposal cannot substitute for these checks.

M2 preparation and synthetic checks can proceed now. A small cost/pipeline
probe requires an explicit attempt/resource budget and separate pilot data;
it cannot enter evaluation counts. Full evaluation needs a separate launch
decision after readiness is recorded. Software/RNG provenance remains required,
but identical hosted CPU/cache states are not a blanket condition for scientific
recovery evaluation; any timing comparison needs its own comparable conditions.
This removes the former blanket M0-to-M2 dependency, not the M0 release hold,
independent review, or research safety checks.

### Uchihara 2022 secondary application

This is a retained application plan, subordinate to the Julia foundation work.
Its questions and inspected data inform possible requirements and later examples;
they do not set the package milestones, core defaults or next implementation task.
Schedule its data preparation and extensions when the needed foundation is ready
or a bounded piece directly checks a reusable package behavior. Its completion
is tracked separately from package acceptance.

The substantive problem is whether a word pronunciation can be relatively easy
to understand while still sounding strongly accented, and which properties of
the pronunciation help explain that distinction. Researchers and teachers need
to know what each measure tells them before treating an accent score as a
proxy for understanding. The final report must introduce this problem before
model terminology and follow question -> design and its rationale -> result ->
answer. An observational reanalysis can assess associations and measurement
under this task; it cannot establish a causal teaching effect or general spoken
language proficiency.

The source is Uchihara, T. (2022), *Is it possible to measure word-level
comprehensibility and accentedness as independent constructs of pronunciation
knowledge?*, Research Methods in Applied Linguistics, 1(2), 100011
([article](https://doi.org/10.1016/j.rmal.2022.100011);
[public data](https://osf.io/nc7yp/)). The 2026-09-11 review read the methods,
results and discussion from the Zotero copy and inspected `Raw Data (Speech
Measures).xlsx`, sheet `Speech Measures`, `A1:N5834`. This is an inspection
baseline, not a cleaned analysis dataset or a reproduced model fit.

| Observed unit | Inspected data and implication for the analysis |
| --- | --- |
| Speaker, word and recording | 12 speakers, 37 words and 307 observed speaker–word recordings from the immediate post-test. Of 444 possible speaker–word cells, 137 have no selected production. Preserve the recalled-word selection; do not code absent productions as the worst rating or assume random missingness |
| Ordinal ratings | 19 listeners per recording: 5,833 unique speaker–word–rater rows, 5,833 accentedness and 5,827 comprehensibility ratings on 1–9 scales. Higher original scores mean stronger accent or greater difficulty. Preserve the original columns and document any reversal, latent-score direction and plot labels |
| Intelligibility and processing time | A separate two-listener dictation task; the paper defines intelligibility as both listeners correct and analyzes latency conditional on joint correctness. The workbook supplies one intelligibility value and one time per recording, repeated across the 19 rating rows, without separate listener responses. Analyze these once per recording; do not create 19 independent trials or infer the two individual responses |
| Explanatory features | Segmental accuracy, stress accuracy, vowel-duration ratio and the column named articulation rate are recording-level predictors; syllable count is word-level. Some are human annotations. The paper's rate definition is duration per syllable, so its direction must not be described as syllables per second. Extra `FacetData` columns currently do not make these fitted predictors |

**Application handoff when scheduled: a reproducible data/measurement contract.** Retain the source
URL, retrieved-file checksum, sheet/range, original IDs and a derivation from
immutable input into rating-level and recording-level analysis views. Verify
joins and report sample flow by speaker, word, recording, rater and criterion.
Resolve the six missing comprehensibility ratings; missing vowel ratios for
24 recordings, segmental accuracy for three and stress accuracy for five; zero
values in the rate column; processing-time units, aggregation and eligibility;
and the paper's reported analysis counts versus the workbook. Explain each
exclusion or unresolved discrepancy instead of forcing agreement. Preserve
partially observed rating pairs when the specified model permits them; use
analysis-specific inclusion rules rather than a universal complete-case filter.
Document the 0/1/2 segmental coding and the published stress recoding before
choosing categorical or ordered covariate effects. An unavailable detail narrows
the affected analysis, not every independent implementation task. No additional
data request or contact with the authors is authorized by this plan.

| Research question | Analysis and why it addresses the question | Required evidence and limit |
| --- | --- | --- |
| How do comprehensibility and accentedness relate after accounting for word and rater differences? | Fit named, correlated speaker dimensions to the paired ordinal criteria, with word effects and dependence among ratings of the same recording. Contrast a declared common-dimension reference with the two-dimension model where identifiable | Report speaker profiles, population-correlation uncertainty, predictive adequacy and prior sensitivity. The paper's pooled rating correlation is not the speaker-population correlation; 12 speakers remain 12 speaker-level units despite thousands of ratings. A wide posterior or prior dependence limits claims of distinctness or independence |
| Do raters treat the two criteria differently, and does generalized scoring help? | Allow criterion-specific severity; compare fixed loading/unit-consistency multidimensional MFRM with explicitly selected MGMFRM loading and consistency blocks under matched scales, thresholds and dependence structure | Report rater contrasts, uncertainty and predictive/recovery consequences. Free one block at a time if attributing its benefit; a joint change supports only a combined comparison. More parameters or a better in-sample fit is not itself an improvement |
| Which phonetic properties relate differently to the criteria? | Add declared recording-level predictors and a separately identified word-level syllable effect; estimate criterion contrasts jointly | Report comparable predicted-category effects and uncertainty, plus coefficient contrasts only on declared comparable scales. A significant effect for one criterion and a nonsignificant effect for the other does not establish a difference. Explain total versus feature-adjusted speaker traits; annotation overlap with intelligibility and observational confounding limit interpretation |
| What do the two rating constructs tell us about successful recognition and processing time? | Relate recording-level latent predictions to the published joint-correctness event and eligible latency, propagating rating-model uncertainty. Evaluate heldout recordings where feasible, keeping all their criteria/raters in the same split and fitting outcome relationships on training data | Report associations and predictive uncertainty for these aggregate outcomes and the conditional latency population. Do not duplicate the outcome across listeners, plug in uncertain scores as error-free, or claim that a separate two-listener panel supplies a third 19-rater ordinal dimension. Holdout design must state the prediction target and implement integration for the heldout recording effect; generalization to new speakers, words or raters needs separate support |

The original paper already used mixed models with speaker, word and listener
effects. Reproduce the relevant published summaries and analysis populations
as a reference, recording any unavailable specification; the contribution is
the joint ordinal measurement model, explicit uncertainty and new contrasts,
not the first recognition of three crossed facets. The already inspected
published results make this a theory-directed reanalysis, not a new independent
confirmatory sample. Keep known-truth simulation evidence separate from its
empirical findings.

The minimum model proposal for this application is a **confirmatory, two-trait
correlated ordinal model**. Define a measurement item as word × criterion for a pure-Q
mapping while retaining the shared physical-word and recording IDs. Each
response measures its named criterion; two criteria on one word do not require
within-item cross-loadings. Specify the adjacent-category equation, category
steps (including shared versus item-specific structure), score direction,
location/scale constraints and the placement of the rater multiplier before
implementation. A fixed-loading, unit-consistency MFRM reference and the selected
generalized extensions must agree conditionally when the extra coefficients
are fixed under the same scaling; zero prior SD is not a fixed-parameter API.

#### Application sequence and reusable dependencies

The independent canonical fixed-coefficient reference already has experimental
public fitting, manual saved results and a report/figure workflow. Correlated
speaker estimation, criterion-specific rater effects, adequate recording
dependence and fitted predictors still need the relevant extensions. The
private fixed-coefficient 2D correlated density is checked; its fit/result
integration is next. Reuse the existing likelihood/transforms where the
accepted equation matches them.
The ordinary fit's identity correlation, common rater parameters and
metadata-only extra columns do not provide these features.

| Analysis output | Reusable capability or application prerequisite | Comparison and reporting condition |
| --- | --- | --- |
| Analysis-ready views and sample flow | The retained data/measurement contract; outcome-specific event keys, physical IDs, score directions and inclusion rules. Keep ordinal ratings in a criterion-labelled long view and outcomes/features in a unique recording view | Reconcile the inspected counts and exclusions without multiplying outcomes through joins. Preserve missing productions and partially observed rating pairs. This application preparation is independent of, and lower priority than, the current report/API handoff |
| Unadjusted joint measurement — primary application model | Public fixed-coefficient workflow plus correlated traits, identified word/criterion effects, criterion-specific rater severity and a justified shared-recording structure. Keep fixed loadings/unit consistency and fixed pure-Q as the reference | Fit the two-criterion ordinal ratings without requiring complete phonetic covariates. Compare a separately specified common-dimension reference where identifiable, using matched observations, score directions and nuisance structure. Report speaker profiles, population-correlation uncertainty, recording dependence, prior sensitivity and predictive adequacy |
| Generalized scoring — named comparison | Explicitly selectable loading and rater-consistency blocks with the same dependence structure and a declared likelihood/parameter/prior scale mapping | Add one block at a time when attributing its effect, or label a joint change as a combined comparison. Unit-logit MFRM and the literal `1.7` MGMFRM baseline are not automatically a nested prior-matched comparison. Keep the same eligible observations, thresholds and intended prediction target |
| Phonetic associations — adjusted model | Predictor coding/transformations and criterion-specific coefficients; an identified hierarchical word effect for syllable count and a declared treatment of missing annotations | Distinguish adjusted from total speaker traits. Compare adjusted/unadjusted models on matched eligible observations or under an explicit missing-data model, and retain the full-rating unadjusted analysis separately. Report predicted-category contrasts and uncertainty; changing the analysis population must not be attributed solely to phonetic adjustment |
| Recognition and eligible latency — secondary outcomes | One published joint-correctness event and eligible latency per recording; a specified outcome model that propagates rating uncertainty and declares whether feedback is allowed | Choose a predictive task, available inputs and grouped heldout split before fitting. Train transformations, measurement/outcome relationships and any structural selection inside that split as required by the task. Integrate unknown heldout effects, retain both stages' provenance and compare the same computational target in Julia/CmdStan. No duplicated outcome trials or reconstructed individual dictation responses |
| Reproducible answers and figures | Saved primary/comparison fits, diagnostic-qualified backend comparisons, application-specific validation and the existing report/figure bundle | Reopen in a separate environment and reproduce named contrasts, uncertainty and plots within stated tolerances. Explain each question's answer and limits. Broader Q learning, within-item, bifactor and non-compensatory models enter only for an explicit additional measurement question; their completion is not required for this application |

Resolve the allocation of shared variation before fitting the primary model:
retain the physical rater as well as criterion IDs, and define whether recording
effects are shared scalars or criterion-specific vectors. Keep speaker-population
correlation separate from recording-level covariance. Specify an identified
word/criterion hierarchy rather than adding a redundant free word effect to
unrestricted word × criterion difficulties. A word-level syllable predictor
must use that hierarchy or another explicit identifying constraint. Choose the
smallest justified dependence structure and assess its restrictions; do not add
unrestricted covariance matrices at every level by default.

The common-dimension reference needs its own equation and identification; do not
implement it by sending a perfect correlation into a nonsingular covariance
sampler. Report whether the data distinguish the proposed models under their
priors, rather than treating one fit statistic as proof of construct independence.
Thousands of rating rows do not increase the number of speaker-level units
beyond 12. Application validation must separate uncertainty about speaker
correlation from recording-level associations; a larger-speaker comparison
answers a small-sample question rather than changing the empirical population.

The first secondary-outcome implementation can propagate the rating posterior
into a recording-level model with an explicitly specified no-feedback target.
It must propagate model/parameter uncertainty rather than use posterior means
as error-free predictors, and preserve the linkage between its saved stages.
A fully joint binary/ordinal/continuous likelihood is a later alternative with
different feedback semantics. Listener-specific dictation modeling additionally
requires individual responses absent from the inspected workbook. Neither is
a prerequisite for Julia core acceptance or the unadjusted ordinal analysis.
Exact secondary likelihoods, missing-data choices and API signatures remain to
be selected with their model contracts; this table does not implement them.

When validating this application, target its 12-speaker/37-word/19-rater design and its
observed sparse speaker–word coverage. Use a small set of known-truth conditions
that tests trait correlation, fixed versus generalized scoring, recording
dependence, criterion-specific raters and feature contrasts. Include prior
predictive checks, recovery/calibration with failure denominators, and selected
prior/missingness/dependence sensitivities; a larger-speaker comparison is useful
only if it answers an explicit small-sample limitation. Predeclare the needed
precision and resource envelope instead of inheriting the old full panel.
Numerical backend agreement checks implementation; these simulations assess
estimation under assumptions; observed-data checks assess adequacy for the case.

**Application-specific acceptance:** the public-data recipe, selected equations/priors,
Julia and CmdStan executions, diagnostics, posterior comparisons, targeted
validation, sensitivity results, figures and report form one reproducible path.
Both backends must estimate the primary empirical model and named fitted
comparisons supporting the conclusions, with adequate diagnostics and declared
Monte Carlo tolerances; a Julia result plus an untested Stan translation is
incomplete. Retain model/environment identity, attempts and limitations through
the existing artifact/report paths. A separate environment must reproduce the
declared claims and figures within their stated tolerances.

Required figures cover the observed design/missingness; paired speaker profiles
and latent-correlation uncertainty; criterion-specific rater effects and any
estimated loadings/consistency; phonetic effect contrasts; posterior predictive
ratings and recording-level intelligibility/latency results; and chain diagnostics
for both backends. Report population correlation separately from correlations
among posterior draws or recording scores. Users must obtain and export these
from saved fits without manually reshaping draws. Use the existing
[figure/report acceptance](#figure-and-report-acceptance), including editable
plots, publication exports and uncertainty labels. The report must answer each
question in words, distinguish the original result from the reanalysis and
simulation, and state the narrow task/population to which the evidence applies.
Stable-public promotion of every package feature is a separate release decision.

### M0 runtime acceptance handoff

**Implementer assessment: insufficient evidence to accept M0 under the current
runtime criterion; maintainer disposition pending.** The retained
[historical comparison](#comparable-ci-timings) is arithmetically valid:
1,061s -> 1,309s, an increase of 248s (23.4%). Its two three-job windows share
`bd22c01`, so they contain five distinct jobs, not six independent observations.
The percentage is a monitoring trigger, not an identified causal effect.

Across those five revisions and the `0881fd4` follow-up, `src/`,
`test/runtests.jl`, the workflow, and `Project.toml` are byte-identical.
This does not identify the old CPU, effective cache, native binaries, or host
load, nor show that the package meets the runtime acceptance criterion.
The [16-job review](docs/internal/fitting-core-runtime-review.md#findings-and-limits)
characterizes later costs; the observer repair addresses the local measurement
failure. Neither establishes the cause of the historical increase.

The retained-evidence review is complete, not the acceptance gate. Drafting the
proposal below was authorized; changing the criterion or running it was not.
The maintainer may retain the current hold, reopening attribution for evidence
that addresses the historical trigger, or review the explicit policy change
below. M1/M2 preparation takes priority; fresh evaluation follows the research
prerequisites above instead of waiting for this historical attribution.

### Prospective runtime acceptance proposal

**Deferred draft only; the existing M0 release criterion still applies.** Proposed scope: accept
current, cohort-specific engineering operability while retaining the historical
+23.4% alert as **unexplained, with explicitly accepted residual uncertainty**.
This replaces the requirement to explain/remediate that alert for M0 acceptance;
it is not an explanation, a performance improvement, or a scientific finding.
A named maintainer must approve that tradeoff and its rationale before adoption.
Rejecting the change leaves M0 on hold without more automatic measurements.

| Decision | Proposed rule, inactive until approved |
| --- | --- |
| Workload and revision | Use only the existing Linux `fitting_core` job: the unchanged 2,641 + 114 assertions, seeds, draws, and compilation-inclusive test block. Proposed reference is `5c4bff2`; freeze the full checkout SHA before execution. A different candidate needs review, not a silent substitution. All 12 ordinary CI jobs must also pass for the exact candidate being accepted |
| Comparison cohort | Predeclare and verify the actual CPU model/Julia target, exposed CPU and memory class, OS image/provisioner, exact Julia build, effective dependency graph/native binaries, thread and compilation flags, and workflow/action versions. Match these within a batch and across compared batches. `ubuntu-latest` and Julia `1` labels alone are insufficient. Changed workload or unmatched environments require an explicit new-baseline decision, not pooling or CPU-normalizing old timings |
| Cache inputs | Before execution, choose one identifiable initial cache lineage/key/version for every attempt, or an explicit no-restored-cache regime for all. Retain restored provenance and emitted precompile work. A rebuild despite matching inputs remains an outcome, not an exclusion or permission to warm and retry. Unknown/mismatched inputs make the comparison inconclusive |
| Primary outcome | Preserve whole-job elapsed seconds, including setup/cleanup and excluding queueing. Retain command elapsed, compilation-inclusive block time, and both test and observer outcomes as diagnostics; do not replace the primary metric with a faster nested timer. Local macOS C and cold A are not Linux baseline observations |
| Initial baseline | Schedule exactly three attempts at one approved revision/cohort. All three must be comparable, successful, and within the existing 30-minute job limit; retain their individual times and freeze their median as the prospective reference. An incomplete batch cannot become a successful-only median. No relative speed or non-regression conclusion is available from this initial batch |
| Subsequent monitoring | Require the same comparability, success, and deadline checks for a separately authorized, non-overlapping three-attempt candidate batch. Using unrounded medians, `median(candidate) / median(reference) > 1.20` requires explanation/remediation and blocks runtime acceptance even when each job is under 30 minutes. Never slide the reference to absorb a slowdown. A ratio at or below 1.20 satisfies only this operational warning rule, not statistical equivalence or a causal/no-regression guarantee |

**Budget proposal:** at most three `fitting_core` job attempts for the initial
baseline, each retaining its existing 30-minute CI timeout, plus at most 15
minutes of no-fit preparation. These are job limits, not a guaranteed total
wall-clock bound or three individual model fits. Stop on failure, timeout,
cancellation, observer error, or missing/mismatched comparison inputs; retain
every started attempt and do not replace it. No fitting warm-up, full-matrix
rerun, `workflow_dispatch`, replacement host provisioning, or cold/warm-pair
restart is included. If the existing job cannot be isolated and its cohort/cache
inputs verified within this scope, stop as inconclusive instead of building a
new runner. A later comparator batch needs its own approval and attempt budget.

The three-attempt median, 20% warning, and 30-minute ceiling retain the existing
operational policy choices; they are not a power calculation or a confidence
bound. Hosted jobs use fresh runner environments ([GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners));
cache-key matches concern restored files ([cache reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching)),
while Julia timings can include compilation ([Julia performance guidance](https://docs.julialang.org/en/v1/manual/performance-tips/)).
These sources motivate recording conditions, not the numerical acceptance rules.

**Execution feasibility, read-only review on 2026-09-06: not ready under the
unchanged CI.** [Candidate job 101415767832](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/34006928912/job/101415767832)
and its resolved action sources establish the following limits, not another run:

- **Job isolation is available in principle.** GitHub supports rerunning one
  job and its dependent jobs; the existing workflow has no `needs` dependencies.
  The verified fitting-job `databaseId` is `101415767832`. No rerun was executed.
  The cancellation API is run-scoped, so a future stop procedure must first
  ensure no other work is active in that run ([GitHub workflow-run API](https://docs.github.com/en/rest/actions/workflow-runs#re-run-a-job-from-a-workflow-run)).
- **Runtime inputs are observed, not fixed.** The job used AMD EPYC 9V74,
  Julia target `znver4`, Julia 1.12.7, and image `20260831.293.1`;
  `ubuntu-latest`, Julia `1`, and major-version action tags do not freeze them.
  Only `Manifest-v1.10.toml` is tracked; it does not lock Julia 1.12's environment
  ([Pkg manifest selection](https://pkgdocs.julialang.org/v1/toml-files/#Different-Manifests-for-Different-Julia-versions)).
  The current `Pkg.test()` path does not enforce a frozen root/test dependency
  graph or native-binary identity before fitting. Same source SHA is insufficient.
- **Initial cache inputs advance.** The [exact cache action used](https://github.com/julia-actions/cache/blob/d10a6fd8f31b12404a54613ebad242900567f2b9/action.yml)
  puts `run_id`/`run_attempt` in the save key, restores by a shared prefix,
  updates restored registries, and defaults to deleting older PR caches.
  This job restored the `34004236027` attempt-1 cache and saved a new
  `34006928912` attempt-1 cache; deletion of three older caches failed.
  An unchanged rerun therefore does not enforce the same starting cache.
  Do not delete caches or broaden permissions to manufacture comparability.

These are gaps against the stricter draft, not failures of ordinary CI or the
local observer repair. No rerun, cache mutation, or workflow change was made by
this review. Defining controls beyond the existing-job scope requires a separate
scoped proposal; do not spend the three attempts hoping their inputs match.

Before any execution approval, name the maintainer, final SHA, available Linux
cohort, exact environment/cache inputs, and a job-only launch/stop procedure.
Those execution inputs remain unresolved. If the proposal is adopted and its
baseline plus all other M0 checks pass, the maintainer may explicitly accept M0
with the historical exception recorded; this is never automatic or independent
scientific acceptance. Neither approval to draft, policy adoption, nor a green
baseline authorizes a merge or changes M1. M2 follows the separate research
execution prerequisites; this performance proposal is not its launch authority.

### Minimal control-change proposal

**Deferred design, not implemented or execution-ready; no longer the next
task.** If this performance investigation is explicitly resumed, the minimal
candidate is one no-restored-cache path with rejection of mismatched inputs.
Its first implementation would be a bounded Linux **no-fit preflight**; reuse the
[existing native-environment checks](docs/internal/fitting-core-runtime-review.md#preflight-result-and-execution-gate)
and POSIX guard. Do not build a runner, cache service, or benchmark controller.
The controls below describe the eventual comparison, not permission to launch it.

| Boundary | Minimum proposed control and remaining limit |
| --- | --- |
| Host and runtime | Predeclare one CPU/target, exposed CPU/memory class, exact image/provisioner, Julia build, and resolved action SHAs. Check the host before expensive preparation, then actual Julia/Pkg, native libraries, threads, and flags before fitting. Missing or different inputs stop the batch; do not learn the accepted cohort from whichever attempt finishes. An explicit Ubuntu release label still does not select an exact CPU or image build |
| Root and native test environments | Prepare and retain Linux-specific root and effective test Project/Manifest files, preferences, package/artifact identities, and actual loaded BLAS identity. Use `Pkg.test(; allow_reresolve=false)` plus equality checks in its native merged test context and the root context used by the plan subprocess. The option alone does not freeze test-only dependencies. Re-audit the one-off private hook for the exact Julia 1.12.7/Pkg build and payload; the macOS 1.12.5 locks, native binaries, and hook are not a portable Linux implementation |
| Starting state | For every eventual job, start a fresh task-owned depot with no restored third-party packages/artifacts/compiled caches or user-depot fallback; retain the pinned Julia bundle's own resources. Bypass the cache action entirely, including save/delete hooks, rather than deleting existing caches. Replace the build action's implicit preparation with explicit locked setup; freeze any required registry input and verify installed artifacts. Keep preparation/download/build/precompile work inside whole-job elapsed time, then use Pkg offline mode for the fit. This is a cold-depot operability condition, not a cold OS page cache or an ordinary warm-cache CI estimate |
| Preflight and measurement | Reuse the guard and version/payload-checked native no-fit path in a separate disposable depot; never transfer its compiled cache into a measured attempt. Check the real test and plan children, not only a parent probe. Retain the two unchanged fitting testsets and compilation-inclusive block. One attempt remains one whole CI job, including setup and cleanup; three fits inside one job or local command times cannot substitute |

[Pkg's test API](https://pkgdocs.julialang.org/v1/api/#Pkg.test) and
[Julia depot semantics](https://docs.julialang.org/en/v1/manual/environment-variables/#JULIA_DEPOT_PATH)
support these mechanisms, not their Linux verification. Pkg offline mode is not
a network sandbox. Guard/check overhead remains part of the chosen measurement
boundary; do not suppress compilation or move setup outside the primary timer
to fit the 30-minute ceiling.

The first implementation slice would contain only the task-local Linux preflight
and its frozen input files; package/test sources and ordinary CI stay unchanged.
Within the proposed 15-minute no-fit preparation cap, require a valid native
launch, rejection of changed graph/payload/flags, untouched cache-flags probe
output, and unchanged source/locks. Stop on failure; no fit or replacement
attempt follows. Exact Linux inputs and an available execution context still
need to be supplied and reviewed; none was provisioned or captured in this edit.

Only after that feasibility check may a separate CI-wiring decision be made.
Keep ordinary current-Julia compatibility coverage: silently pinning its
`fitting_core` lane would narrow that coverage. Any controlled CI path needs a
reviewed checkout/workflow SHA, isolated launch/stop route, and explicit approval
of publication and every resulting CI run; `5c4bff2`'s green result does not
validate those changes. Count all started baseline jobs, including pre-fit
rejections, and launch sequentially so a failure stops further attempts.

**Residual limit:** fail-closed checks prevent mismatched comparisons; they do
not guarantee three matching hosted jobs or fixed host load. If the declared
cohort is unavailable, retain an incomplete batch without host-shopping,
replacement runs, relaxed controls, or a larger timeout. A guaranteed fixed
execution environment would be a separate infrastructure decision, not this
minimal implementation. M0 and the historical +23.4% exception remain open.

## Evidence baseline and claim limits

- `101b791`: [CI 33946739309](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33946739309)
  passed all 12 ordinary jobs. The full minimum-version suite and six current-
  Julia shards matched at 87 testsets / 14,731 assertions.
- `9668383`: [CI 33949682122](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33949682122)
  passed all 12 ordinary jobs. The six current-Julia shards passed 89 testsets /
  17,249 assertions; the Julia 1.10.8 full job passed in 30m48s. The two manual
  research jobs were skipped. This is not a three-run runtime median.
- `ed4185f`: 308 reference-declaration/estimand checks were added. The focused
  generator file passed 2,826 assertions locally on Julia 1.10.8 and 1.12.5.
  [CI 33951073887](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33951073887)
  subsequently passed all 12 ordinary jobs; both manual research jobs were
  skipped. The Julia 1.10.8 full job took 21m47s. Do not transfer this green
  result to a later documentation edit, or treat three changed-workload runs
  as an already-reviewed comparable runtime baseline.
- `bd22c01`: the document/layout reorganization passed all 12 ordinary jobs in
  [CI 33952439772](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33952439772);
  both manual research jobs were skipped. The full Julia 1.10.8 job took
  30m17s. The fixture inventory and median assessment are later documentation
  changes, not additional scientific evaluation.
- `fa7ffc9`: [CI 33953993916](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33953993916)
  passed all 12 ordinary jobs; two manual research jobs were skipped. The full
  Julia 1.10.8 job passed 90 testsets / 17,557 assertions in 29m56s. This closes
  the missing test-lane median observations below, not all runtime conditions
  or the later complete-fixture classification's candidate CI.
- `9a4d180`: [CI 33955509722](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33955509722)
  passed all 12 ordinary jobs; two manual research jobs were skipped. The full
  Julia 1.10.8 job passed the same 90 testsets / 17,557 assertions in 31m28s.
  The updated medians below expose a runtime investigation, not a test failure.
- `04daa4d`, `a13399c`, and `27fb7d7`: [CI 33958936886](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33958936886),
  [CI 33960125413](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33960125413),
  and [CI 33961918446](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33961918446)
  each passed all 12 ordinary jobs; both manual research jobs were skipped.
  Their Julia 1.10.8 full jobs passed 90 testsets / 17,557 assertions in
  33m15s, 30m57s, and 22m24s, respectively. These are engineering observations,
  not fresh anchor-study replications or acceptance of a later revision.
- `46f8d92` added 951 MCMC-free assertions. Its focused file passed four
  testsets / 3,777 assertions on Julia 1.10.8 and 1.12.5, and a deliberately
  malformed paired control was detected. [CI 33963553257](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33963553257)
  passed all 12 ordinary jobs: `fitting_reports` passed 25 / 7,453 and the
  full Julia 1.10.8 job passed 91 / 18,508 in 30m14s. Both manual research
  jobs were skipped. This verifies that revision, not subsequent changes.
- `5f58701` added the [response-sharing draft](docs/internal/mfrm-anchor-study.md#m1-data-sharing-and-rng-ownership-draft)
  and 131 smoke assertions. The focused file passed five testsets / 3,908
  assertions on Julia 1.10.8 and 1.12.5. [CI 33964790537](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33964790537)
  passed all 12 ordinary jobs: `fitting_reports` passed 26 / 7,584 and the
  full Julia 1.10.8 job passed 92 / 18,639 in 30m54s. Both manual research
  jobs were skipped. These results do not accept a subsequent source revision.
- `8cd32ff` extended the [scoring draft](docs/internal/mfrm-anchor-study.md#m1-scoring-applicability-and-denominator-draft)
  with 50 assertions for applicability, primary-attempt denominators, and
  paired finite-subset comparisons. All six focused testsets / 3,958 assertions
  pass locally on Julia 1.10.8 and 1.12.5; two memory-only mistakes are detected.
  [CI 33965531472](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33965531472)
  passed all 12 ordinary jobs; the full Julia 1.10.8 job passed 93 / 18,689
  in 20m00s. Both manual research jobs were skipped.
- `8f9be52`'s [predictive-boundary check](docs/internal/mfrm-anchor-study.md#predictive-scoring-boundaries-checked)
  fixes a shared KL overflow for positive subnormal probabilities and adds
  16 scorer / 28 M1 assertions. Locally, all 56 scorer and 3,986 anchor checks
  pass on Julia 1.10.8 and 1.12.5; the old KL formula fails three regressions.
  Category alignment, event weights, mean-before-log, and a finite-log heldout
  route were checked. [CI 33966444116](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33966444116)
  passed all 12 ordinary jobs: `fitting_reports` passed 28 / 7,662,
  `generalized` 19 / 2,461, and the full Julia 1.10.8 job 94 / 18,733 in
  26m06s. Both manual research jobs were skipped.
- `49871e3`'s [all-category log integration](docs/internal/mfrm-anchor-study.md#all-category-log-input-and-integration)
  adds explicit log input to the existing scorer, retaining its default input
  and result schema. All 4,202 anchor and 103 scorer checks passed on both local
  Julia versions; two memory-only numerical mistakes were detected.
  [CI 33968517600](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33968517600)
  passed all 12 ordinary jobs: `fitting_reports` 29 / 7,878, `generalized`
  20 / 2,508, and the full Julia 1.10.8 job 96 / 18,996 in 26m00s. Both
  manual research jobs were skipped. This does not certify later changes.
- `bc36adc`'s [independent log-truth check](docs/internal/mfrm-anchor-study.md#independent-log-truth-boundaries)
  extends the existing standalone primitive and feeds its logs into the
  24-scenario scoring check. No probability-kernel copy or export is added.
  The 277 new assertions bring the anchor file to 4,479; together with 103
  scorer and 2,168 unchanged LD assertions, 6,750 pass on Julia 1.10.8 and
  1.12.5. All 22 legacy LD raw outputs match the preceding revision within
  each environment; three memory-only numerical mistakes are detected.
  [CI 33970171857](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33970171857)
  passed all 12 ordinary jobs: `fitting_reports` at 30 / 8,155 and the full
  Julia 1.10.8 job at 97 / 19,273 in 30m10s. Both manual research jobs were
  skipped. Its CI does not certify subsequent revisions or close M0.
- `fe80126`'s [labelled JSON/scoring check](docs/internal/mfrm-anchor-study.md#labelled-json-roundtrip-and-scoring-boundary)
  reuses the existing JSON conversion and array scorer, adding one private
  label-alignment helper. All 4,531 anchor and 103 scorer assertions pass on
  Julia 1.10.8 and 1.12.5. The 52 new checks preserve tiny finite values,
  structural zero/infinite loss, missing records, and primary-attempt counts
  through temporary-file roundtrips; two memory-only mistakes are detected.
  [CI 33971936154](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33971936154)
  passed all 12 ordinary jobs: `fitting_reports` 31 / 8,207 and the full
  Julia 1.10.8 suite 98 / 19,325 in 20m13s. Both manual research jobs were skipped.
  Durable truth/RNG storage, full dataset/attempt binding, the persistent ledger,
  thresholds, and review remain open. No export, dependency, retained fixture,
  sampler, or evaluation replication is added; runtime acceptance stays open.
- [PR #97](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/pull/97) merged
  the verified `fe80126` head into `main` as `e8bc648` on 2026-09-06 JST,
  preserving individual source commits. This is engineering integration only:
  no release/tag/registration, research dispatch, or M0/M1 acceptance was made.
  Its [main CI 33973332148](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33973332148)
  passed all 12 ordinary jobs; the full Julia 1.10.8 suite passed 98 / 19,325
  in 33m36s. Both manual research jobs were skipped.
- `2f4f431`'s [attempt-identity/native-replay check](docs/internal/mfrm-anchor-study.md#attempt-identity-join-and-native-replay)
  adds 76 identity assertions and four native-save/replay assertions, reusing
  existing code and stdlib Serialization. The 4,611 anchor and 103 scorer
  assertions pass locally on Julia 1.10.8 and 1.12.5.
  [CI 33973824420](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33973824420)
  passed all 12 ordinary jobs: `fitting_reports` 32 / 8,287 and the full
  Julia 1.10.8 suite 99 / 19,405 in 33m11s. Both manual research jobs were skipped.
  [PR #98](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/pull/98) merged as
  `4b2c5a4` on 2026-09-06 JST; this does not certify the following revision.
  Payload/source binding, labelled durable archives, crash-safe publication,
  a persistent all-attempt ledger, and all scientific freeze decisions remain open.
- The [response-byte binding check](docs/internal/mfrm-anchor-study.md#byte-bound-labelled-response-restoration)
  reuses SHA, JSON3's typed reader, the event-label check, and `FacetData`.
  It adds 95 boundary assertions plus 64 labelled-table checks on the existing
  16 smoke blocks. All 4,770 anchor and 103 scorer assertions pass on Julia
  1.10.8 and 1.12.5; SHA-bypass and decimal-rounding mutations are detected.
  [CI 33975779252](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33975779252)
  at `ac31b41` passed all 12 ordinary jobs: `fitting_reports` 33 / 8,446 and
  the full Julia 1.10.8 suite 100 / 19,564 in 31m46s. Both manual research
  jobs were skipped. Trusted reference retention, data/state/source/attempt
  binding, durable publication, the persistent ledger, and scientific review
  remain open. No fresh fit/evaluation or new dependency/export is added.
- [PR #99](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/pull/99) merged
  verified `ac31b41` into `main` as `ad57606` on 2026-09-06 JST; their complete
  Git trees match. [Main CI 33997276971](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33997276971)
  passed all 12 ordinary jobs: `fitting_reports` 33 / 8,446 and the full
  Julia 1.10.8 suite 100 / 19,564 in 30m50s. Both manual research jobs were
  skipped. Integration does not close M0/M1 or authorize a release/evaluation.
- The runtime-review and no-fit preflight documentation at `b19eeec` passed all
  12 ordinary jobs in
  [CI 34001839651](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/34001839651):
  `fitting_reports` 33 / 8,446 and the full Julia 1.10.8 suite 100 / 19,564
  in 31m16s. Both manual research jobs were skipped. This does not certify the
  subsequent cold-A report, enlarge the fixed timing window, or close M0.
- The earlier anchor pilot completed 80 fits but only two independent datasets
  per cell, with PCM-only truth, favorable initialization, and a shared
  generation/fitting kernel. None of its fits enters the new evaluation count.
- Exact anchor checks cover fixed versus estimated coordinates, incompatible
  anchor contrasts, intended categories, reports, and persistence. They establish
  implementation behavior, not repeated recovery or uncertainty calibration.
- Narrow local TAM and version-specific ConQuest evidence remain useful but do
  not establish independent reproduction, broad product parity, or transfer to
  GMFRM/MGMFRM.

The finite implementation review and earlier timings are preserved in the
[baseline record](docs/internal/archive/roadmap-2026-09-05.md#immediate-milestones).
Its older “pending” observations are historical; the status above governs.
Track scientific readiness separately from engineering readiness. No count of
tests, generated files, or historical checkboxes is a project-completion score.

### Comparable CI timings

The following are complete successful jobs from attempt 1 of
[`33952439772`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33952439772)
(`bd22c01`),
[`33953993916`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33953993916)
(`fa7ffc9`), and
[`33955509722`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33955509722)
(`9a4d180`), in that order. The review window ends at `9a4d180`; later
completions do not retroactively enter it. Current-Julia rows use Julia 1.12.7; the full-suite row
uses Julia 1.10.8. All logs agree on Ubuntu 24.04, runner image
`20260831.293.1`, and provisioner `20260828.587`. Testset names and per-set
assertion counts match exactly within every row. Only the root roadmap,
internal fixture inventory, and fixture README changed across these revisions;
workflow, package/test code, dependency declarations, examples, and published
manual sources did not change.

These are workload/image-matched operational windows, not hardware-matched
benchmarks: CPU models were not logged in those jobs. The later instrumentation
below demonstrates why an unchanged runner-image label is insufficient.

| Lane | Testsets / assertions | Three whole-job times | Median | Change from initial median |
| --- | --- | --- | --- | --- |
| `core` | 11 / 2,899 | 20m46s, 22m30s, 17m05s | 20m46s | 0.0% |
| `fitting_core` | 2 / 2,755 | 15m41s, 22m15s, 21m49s | 21m49s | +23.4% — investigate |
| `local_dependence_core` | 32 / 2,904 | 23m35s, 23m29s, 23m36s | 23m35s | 0.0% |
| `local_dependence_integrity` | 2 / 52 | 13m57s, 12m05s, 11m19s | 12m05s | -31.9% |
| `generalized` | 19 / 2,445 | 11m19s, 8m26s, 13m26s | 11m19s | -12.9% |
| `fitting_reports` | 24 / 6,502 | 20m37s, 21m08s, 20m18s | 20m37s | -1.7% |
| Full suite, Julia 1.10.8 | 90 / 17,557 | 30m17s, 29m56s, 31m28s | 30m17s | +1.2% |

Initial medians are retained in the
[roadmap at `0881fd4`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/0881fd4276d5e960152a627b378145f8a63b43ee/ROADMAP.md#comparable-ci-timings).
The windows overlap: percentage changes are monitoring triggers, not independent
estimates of an optimization or regression. Setup/cache variation is included;
queue time is excluded. No timing here measures sampler speed.

The `fitting_core` trigger is localized but **not explained**. All three jobs
restored their lane cache. Their test-command steps took 15m04s, 21m44s, and
21m10s; the 2,641-assertion fitting testset itself took 9m51.3s, 14m59.6s, and
14m29.8s. Thus job setup alone cannot explain the increase. The later
[`0881fd4` fit job](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33956618271/job/101280994109)
passed the same 2,755 assertions in 22m01s; its fitting testset took 14m42.6s.
This is follow-up evidence, not a replacement of the fixed window above.

Across all six fit jobs from `9668383` through `0881fd4`, the 187 logged
versioned package entries match, the PR target commit is `6e8291c`, and
`runtests.jl`, package sources, and the workflow are unchanged. Slow fitting
testsets (14m29.8s--14m59.6s) already occur at `9668383`, before the document
reorganization; the two faster observations are 9m23.5s and 9m51.3s. The gap
between the group announcement and the inferred testset start is about
378--381s in the slower jobs versus 273--292s in the faster ones. This gap is
not a pure import or compilation timer. Identical logged versions do not prove
identical binaries, hardware, or scheduling; cache restoration does not prove
zero compilation. Existing logs cannot attribute the two timing ranges.

The existing fitting block now uses Julia's `@time ... @eval begin ... end`
to include compilation of the large expression, while preserving both original
testset trees, seeds, draw counts, and assertions. Its CPU target and Julia/BLAS
thread counts are logged without changing them. Only the Linux `fitting_core`
command adds `lscpu`, `free --mebi`, and
[`/usr/bin/time -v`](https://www.gnu.org/software/time/manual/time.html)
around the unchanged `Pkg.test()` call. Treat CPU time, RSS, GC, and compilation
as command/block diagnostics, not sampler-only performance or a system-wide
memory bound. The extra evaluation boundary makes this an instrumented series:
do not claim a speedup by mixing it with uninstrumented timings. Accept an
explanation only when these observations support it; retain the trigger if
they do not. No dependency, sampler, threshold, or timeout changes are bundled
with this measurement.

Local verification on Julia 1.12.5/macOS passed both fitting testsets unchanged
(2,641 + 114 assertions). The timed block took 677.526s: 78.16% compilation,
1.26% GC, and 32.437 GiB cumulatively allocated, **not peak resident memory**.
The testset summaries alone were 9m07.8s and 4.4s and omit part of the enclosing
block cost. One 1-second native sample during that run found compilation frames
in all 72 observed main-thread stacks; sampling perturbed this diagnostic run.
This supports investigating compilation locally, not attributing the historical
CI increase or pooling local and Linux timings. All 11 inline testset expression
trees match before/after instrumentation; selection checks passed 45/45 on
Julia 1.10.8 and 1.12.5. The minimum-version timing/failure smoke and the four
stubbed Bash routing/exit-status cases passed. Native Linux resource reporting
was subsequently verified by the first instrumented CI observation below.

Three ordinary instrumented fit jobs passed the same 2,755 assertions. They use
Julia 1.12.7, the same Ubuntu image/provisioner, four exposed logical CPUs, one
Julia thread, and two BLAS threads, but **different CPU models and targets**.

| Revision / fit job | CPU model / Julia target | Whole job | `Pkg.test()` command | Timed block | Compilation | Reported max RSS |
| --- | --- | --- | --- | --- | --- | --- |
| [`04daa4d`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33958936886/job/101287242614) | AMD EPYC 7763 / `znver3` | 22m36s | 1,317.54s | 1,121.871s | 80.45% | 2,555,816 KiB |
| [`a13399c`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33960125413/job/101290451261) | AMD EPYC 9V74 / `znver4` | 17m42s | 1,026.77s | 895.140s | 83.45% | 2,671,352 KiB |
| [`27fb7d7`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33961918446/job/101295159486) | Intel Xeon 6973P-C / `graniterapids` | 13m04s | 748.13s | 621.888s | 76.70% | 2,589,148 KiB |

The 180 extracted unique logged package/version entries match; all three PR merges
target `6e8291c`. Only the root roadmap and study draft changed between heads.
All restored their lane cache, but from different predecessor runs: cache
restoration does not establish identical effective precompilation. The first
two blocks report 679.74 million allocations / 31.977 GiB cumulative allocation;
the third reports 680.05 million / 31.992 GiB. These are not peak memory. GC
is 0.84% / 0.99% / 1.89%. Command user/system CPU times are 1,315.19/2.67s,
1,024.56/2.52s, and 745.73/2.29s; 99--100% CPU means about one CPU's capacity
on average, not saturation of all four. Reported max RSS is not simultaneous
process-tree memory; major page faults are zero and startup memory snapshots
are not run-long traces. Testset summaries exclude part of the enclosing
compilation-inclusive block cost. These successful runs precede the later
951-assertion M1 addition and do not verify that candidate.

These initial observations are compilation-heavy and demonstrate runner
heterogeneity. They do **not** isolate the CPU's causal contribution, establish
a documentation-induced speedup, or identify the CPU of any older job. Those
older logs cannot support retrospective hardware stratification. Keep M0 open;
separate subsequent ordinary observations by CPU/target, version, and threads
before forming a comparable window or choosing a measured compilation remedy.
In that initial window there is only one observation per CPU/target, not a
three-run matched median. The [16-job follow-up through `ad57606`](docs/internal/fitting-core-runtime-review.md)
now finds four source/version/CPU-matched observations (median 22m12s),
precompilation despite cache restoration, and a resolved JSON version change.
It localizes one later job-time change outside the fitting block, without
attributing the original trigger or claiming a sampler improvement.
Do not pool these observations into the original median, add research
execution, or inflate the timeout to close the trigger.

The remaining lanes use the same three runs, except macOS uses `fa7ffc9`,
`9a4d180`, and the completed macOS job of
[`33956618271`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33956618271)
(`0881fd4`; attempt 1). That run's other jobs were still in progress at review;
this observation does not transfer a green result to its whole candidate.

| Lane | Matched check | Three whole-job times | Baseline median |
| --- | --- | --- | --- |
| macOS smoke | Same portable-package script, Julia 1.12.7 | 1m09s, 1m08s, 0m55s | 1m08s |
| Windows smoke | Same portable-package script, Julia 1.12.7 | 2m00s, 2m01s, 2m05s | 2m01s |
| Documentation | 19 public sources / 14 rendered HTML files | 3m26s, 3m59s, 0m58s | 3m26s |
| Experimental boundary | 2 testsets / 1,123 assertions, Julia 1.10.8 | 6m36s, 3m02s, 2m35s | 3m02s |
| Release hygiene | Same gate; Aqua 7 testsets / 10 assertions; 351 runtime-language surfaces | 18m29s, 18m20s, 13m13s | 18m20s |

Ubuntu versions match the first table; docs/hygiene use Julia 1.12.7,
Documenter 1.19.0, and Aqua 0.8.16 where applicable. Windows uses
`windows-2025-vs2026` image `20260824.214.3`, provisioner `20260819.586`.
The accepted macOS observations use `macos-26-arm64` image `20260728.0273.1`,
provisioner `20260707.563`; exclude `bd22c01`'s 1m05s because its image and
provisioner differ. Platform and experimental fits remain bounded engineering
smokes, not new scientific evaluation.

### Distribution phases and budget interpretation

The hygiene jobs above ran the same
[`distribution_archive_smoke.jl`](scripts/distribution_archive_smoke.jl).
Seconds below follow `bd22c01`, `fa7ffc9`, `9a4d180`; all observations passed.

| Phase | Three times (seconds) | Median (seconds) | Budget (seconds) |
| --- | --- | --- | --- |
| Assemble and inspect | 0.171, 0.143, 0.136 | 0.143 | 30 |
| Instantiate | 5.205, 4.657, 4.670 | 4.670 | 600 |
| First load | 15.419, 14.709, 12.174 | 14.709 | 300 |
| Warm load | 2.798, 2.580, 2.297 | 2.580 | 120 |
| Minimal fit | 33.062, 31.839, 26.043 | 31.839 | 300 |
| Manual build | 25.059, 22.853, 19.489 | 22.853 | 600 |

These are operational baselines across documented internal-text changes, not
a byte-fixed archive benchmark. Candidate inventories were 427 / 428 / 428
files and 27,959,685 / 27,970,739 / 27,976,891 bytes; compressed Git archives
were 3,176,414 / 3,180,291 / 3,182,326 bytes, all below 4 MiB. The assembly and
privacy scan therefore process slightly different text. Other commands and
published build inputs are unchanged. Each candidate is Git-free and excludes
ignored local outputs, but uses the runner's existing depot: neither
instantiate nor first load is a cold-depot measurement. The separately
[classified research records](docs/internal/fixture-boundary.md) remain shipped;
passing this smoke alone does not prove their removal or non-use. The separate
fixture review establishes which ordinary checks consume them and how.

Phase budgets are **post-completion elapsed-time checks**, not process-killing
timeouts. The hard cancellation boundary is the 30-minute hygiene CI job;
standalone local use has no equivalent outer deadline. Preserve this distinction
when interpreting the older archived wording. Existing job ceilings remain
35 minutes for core/experimental, 30 for the other current-Julia shards/hygiene,
20 for platforms/docs, and 75 for the minimum-version full suite. Every current-
Julia shard observation above meets the 30-minute T2 target; the full suite is
a separate T3 job, not a 30-minute shard. A target exceeded three consecutive
times requires splitting or reclassification. Baseline collection is complete;
the >20% fitting trigger still prevents runtime P0 acceptance.

## Package release conditions

Stable-public MGMFRM promotion waits for every condition below and the
target-specific M0–M3 domain decision. Core development and sampler-free
validation need not wait for completion of the entire MFRM anchor study.
A checked engineering item is not scientific validation.

These conditions govern the primary Julia package deliverable, including its
continuing CmdStan verification. The [Uchihara application](#uchihara-2022-secondary-application)
is not an additional release gate, and its success does not waive any condition.
Historical M0 runtime attribution remains a release hold while further benchmarking
stays deferred under the existing decision. Actual correctness, data integrity,
load/runtime and resource-safety blockers in the core workflow take priority;
the priority correction does not automatically restart the old benchmark program.

- [x] A Git-free source candidate installs, loads, runs the stable example, and
  builds the manual without ignored artifacts, private paths, CmdStan, or R.
- [x] Stable MFRM supports declared categories and actual individual rater/item
  hard anchors through fitting, fixed-coordinate reports, and persistence;
  the finite M0 behavior review passed candidate CI.
- [x] Root exports are frozen and classified; stable exports are documented;
  experimental and research entry points remain visibly separated.
- [ ] Each advertised model has an accepted [seven-axis specification](#model-axes-and-staged-scope-decisions)
  and evidence for its declared domain. A fixed-Q or bifactor-shaped design,
  direct ability coordinates, or a correlation candidate does not imply
  support for every multidimensional MFRM/MGMFRM or factor structure.
- [ ] Complete the [content acceptance checks](#public-documentation-and-help-acceptance):
  README/manual/live-help/fresh-HTML consistency is verified on 2026-09-14;
  the independent unfamiliar-reader walkthrough remains pending.
  Ordinary user tasks do not depend on internal work orders; the four observed
  source-language findings and GMFRM explanation contradiction are resolved.
  Historical navigation/API-coverage checks do not satisfy this condition.
- [ ] The advertised MGMFRM workflow reaches standard diagnostic/result figures
  and a saved report without manual draw reshaping; scale/interval agreement,
  compatibility and the [UX walkthrough](#figure-and-report-acceptance) pass.
  Bounded saved-fit figure/report integration is verified on 2026-09-14;
  the unfamiliar-reader walkthrough remains pending.
- [ ] The advertised core MGMFRM models remain estimable through both
  Julia/AdvancedHMC and CmdStan, with the [cross-backend checks](#julia-and-cmdstan-continuity-and-comparison)
  complete for the declared scope. Record numerical target checks separately
  from diagnostic-qualified posterior comparisons and scientific validation;
  a single successful fit or one available backend does not close this item.
- [x] Release checks protect behavior, schema, performance, portability, and
  privacy rather than unrelated prose or transitive source digests.
- [ ] Runtime P0 acceptance resolves the retained >20% fitting trigger.
  Research-result isolation, whole-lane evidence, and three-run baseline
  collection are recorded above; they do not substitute for that decision.
- [x] The current 0.1.x package/research placement and load boundary is reviewed:
  active documents are short,
  retained fixtures have a shipped purpose or an explicit archival role, and
  research records are not numerical prerequisites for ordinary tests. Retained
  ordinary numerical/behavioral references are identified separately; shared
  research definitions still have parsing/load cost and are not promoted APIs.

Keep the existing 4 MiB compressed Git archive growth guard, the documented
250 KiB fixture-review threshold, phase elapsed-time gates, and CI job timeouts.
A size or timing exception needs a stated user benefit; do not inflate limits silently.
The four documented research-only missing-docstring warnings stay classified
under the existing Documenter policy; stable API completeness is checked
separately.

## Directory map and change boundaries

| Location | Role and rule |
| --- | --- |
| `Project.toml`, `src/` | Package dependencies and implementation; no source/API refactor in this organization pass |
| `examples/`, `README.md`, `docs/src/` | User workflows and manual sources; `docs/make.jl` explicitly selects published pages |
| `ROADMAP.md` | Current priorities, owners, exit decisions, and a compact evidence baseline |
| [`docs/internal/mfrm-anchor-study.md`](docs/internal/mfrm-anchor-study.md) | Supporting MFRM anchor methods draft; the only place to edit that sub-study's six freeze decisions, not the MGMFRM model contract |
| [`fixture-boundary.md`](docs/internal/fixture-boundary.md), [`code-load-boundary.md`](docs/internal/code-load-boundary.md) | Finite 0.1.x placement decisions and their verification limits; revisit only when the recorded boundary changes |
| [`fitting-core-runtime-review.md`](docs/internal/fitting-core-runtime-review.md) | Fixed-window M0 timing observations and comparison limits; acceptance and next work remain in this roadmap |
| [`docs/internal/archive/`](docs/internal/archive/) | Preserved roadmap snapshots and deferred rationale; outside the manual source tree and not an execution authority |
| `docs/src/development-*.md`, `docs/src/mgmfrm-research-roadmap.md` | Existing non-published ledgers and MGMFRM design/evidence detail to reuse in the active core review; older version schedules and execution decisions do not override this work order |
| `test/`, [`test/fixtures/`](test/fixtures/README.md) | Behavioral regressions and numerical references; ordinary versus opt-in behavior is documented in the fixture guide |
| `scripts/` | Existing release, diagnostic, and research commands; names do not authorize execution, and pinned paths are retained |
| `artifacts/`, `results/`, `test/fixtures/local/` | Ignored local outputs where present; neither delete nor publish them during directory cleanup |
| `Manifest.toml`, `docs/Manifest.toml`, `docs/build/` | Ignored local environments/build output; keep the tracked `Manifest-v1.10.toml` reproducibility reference |

Commands and inline source paths in internal documents are relative to the
repository root; Markdown links are relative to their containing file.
The old [manual roadmap path](docs/src/roadmap.md) is retained as a pointer.
The [root snapshot](docs/internal/archive/roadmap-2026-09-05.md) and
[manual snapshot](docs/internal/archive/manual-roadmap-2026-09-05.md) preserve
their pre-organization content and source commit. Frozen research bundles may
refer to the old paths/bytes: inspect their recorded revision; do not rewrite
old evidence digests just to match the new documentation.

## Deferred work and decision discipline

The [narrow fixed-Q program](docs/internal/archive/roadmap-2026-09-05.md#downstream-fixed-q-program)
is now an implementation/evidence input to the active MGMFRM core review, not
deferred wholesale until the MFRM anchor-domain decision. Its protocol, recovery,
external-review and promotion gates remain unsatisfied by this priority change.
Fixed-coefficient multidimensional MFRM now has canonical experimental fitting,
manual cache/full-artifact replay and report/figure workflows. Correlated dimensions, validated within-item structures, configurable
random effects, non-compensatory kernels and Q structure inference follow the
[long-term sequence](#long-term-extension-sequence). They are intended extensions
with separate identification and validation work, not indefinitely excluded
features or current support claims. Existing guards remain until the relevant
implementation and evidence are complete. Bifactor roles/score interpretation
require their own contract even when a Q pattern can be represented.

Criterion-specific raters, shared recording effects and phonetic predictors may
exercise the reusable effect design; the Uchihara-specific combination and mixed
outcomes remain a separate application scope. Full Uto reproduction, generalized
anchors, dynamic raters, broader testlet mechanisms and causal fairness claims
retain their distinct research decisions. Uchihara, ConQuest/TAM and the full
MFRM anchor panel are supporting work; none defines completion or blocks an
otherwise independent Julia foundation task.

Retain the [claim-to-evidence boundaries](docs/internal/archive/roadmap-2026-09-05.md#claim-to-evidence-ledger)
and [engineering sustainability constraints](docs/internal/archive/roadmap-2026-09-05.md#engineering-sustainability-gate).
A proposed change must name a shipped behavior, a demonstrated correctness
risk, or a predeclared scientific claim. Prefer an existing helper and a focused
check; do not add exports, dependencies, large fixtures, or source-hash chains
for one-off research convenience.

When a milestone changes, replace its status and record only the uncertainty
reduced, the affected claim, and the next blocking decision. Git records routine
edits; do not create another dated snapshot for each status update. Missing
external input triggers a concrete reviewer/data handoff, not endless local
simulation. No merge, release, broad claim, or independent review is implied
by this roadmap or by green CI.
