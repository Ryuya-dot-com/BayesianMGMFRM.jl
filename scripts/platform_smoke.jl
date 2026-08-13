#!/usr/bin/env julia

using BayesianMGMFRM

function require_smoke(condition::Bool, message::AbstractString)
    condition || error("platform smoke failed: $message")
    return nothing
end

person = String[]
rater = String[]
item = String[]
score = Int[]
for replicate in 1:2, person_index in 1:3, rater_index in 1:2, item_index in 1:2
    push!(person, "P$person_index")
    push!(rater, "R$rater_index")
    push!(item, "I$item_index")
    push!(score, mod(replicate + person_index + 2rater_index + item_index, 3))
end

data = FacetData(
    (; person, rater, item, score);
    person = :person,
    rater = :rater,
    item = :item,
    score = :score,
)
validation = validate_design(data)
require_smoke(validation.passed, "portable example design did not validate")

specification = mfrm_spec(data; thresholds = :partial_credit)
design = getdesign(specification)
initial = initial_params(design)
require_smoke(
    isfinite(loglikelihood(design, initial)),
    "initial log likelihood is not finite",
)

fitted = fit(
    specification;
    backend = :julia,
    ndraws = 2,
    warmup = 1,
    chains = 1,
    step_size = 0.02,
    init = initial,
    seed = 20260814,
)
require_smoke(fitted isa MFRMFit, "stable fit returned the wrong result type")
require_smoke(size(fitted.draws, 1) == 2, "stable fit returned the wrong draw count")
require_smoke(all(isfinite, fitted.draws), "stable fit returned a non-finite draw")

metadata = evidence_metadata(; include_packages = false)
require_smoke(haskey(metadata, "git"), "environment metadata omitted Git status")
require_smoke(
    haskey(metadata, "collection"),
    "environment metadata omitted probe status",
)

println(
    "portable package smoke passed on ",
    Sys.KERNEL,
    " / Julia ",
    VERSION,
    "; Git metadata is optional provenance",
)
