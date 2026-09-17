module MFRMValidationPreparation

# Internal, sampler-free preparation for fixed-coefficient-validation-protocol.md.
# No include-time work, fitting, evaluation seed allocation or public exports.
import BayesianMGMFRM as B
using Random, Statistics

const Q = [i <= 4 ? d == 1 : d == 2 for i in 1:8, d in 1:2]
const FOCAL_NAMES = ["r4-r1", "r2-r1", "b4-b1", "b8-b5", "theta11-theta21",
    "theta12-theta22", "s1,1", "s8,3"]

function labels(spec)
    data = spec.data
    return (; person_levels=copy(data.person_levels), item_levels=copy(data.item_levels),
        rater_levels=copy(data.rater_levels), category_levels=copy(data.category_levels),
        dimension_labels=copy(spec.dimension_labels))
end

function check_state(spec, state)
    data = spec.data
    B._is_mfrm_fixed_q(spec) && spec.q_matrix == Q &&
        spec.thresholds === :partial_credit && spec.discrimination === :none &&
        isempty(spec.anchors) && isempty(spec.validation_bias_terms) &&
        length(data.rater_levels) == 4 && data.category_levels == collect(0:3) ||
        throw(ArgumentError("preparation requires the two-dimensional, eight-item, four-rater protocol geometry"))
    expected_labels = labels(spec)
    all(k -> getproperty(state, k) == getproperty(expected_labels, k), keys(expected_labels)) ||
        throw(ArgumentError("truth/draw facet, dimension or category labels do not match the specification"))
    size(state.theta) == (length(data.person_levels), 2) && length(data.person_levels) >= 2 &&
        size(state.b) == (8,) && size(state.r) == (4,) && size(state.steps) == (8, 4) ||
        throw(ArgumentError("coordinate dimensions do not match the protocol geometry"))
    all(x -> x isa Real && !(x isa Bool) && isfinite(x),
        (state.theta..., state.b..., state.r..., state.steps..., state.rho)) ||
        throw(ArgumentError("coordinates must be finite real values"))
    abs(state.rho) < 1 && all(iszero, state.steps[:, 1]) &&
        isapprox(sum(state.r), 0; atol=1e-12) &&
        all(x -> isapprox(x, 0; atol=1e-12), sum(state.steps; dims=2)) ||
        throw(ArgumentError("invalid correlation, baseline step or zero-sum coordinates"))
    return nothing
end

"""Independent of the fitted response kernel; reuse the standalone PCM generator."""
function log_probabilities(spec, state)
    check_state(spec, state)
    return _log_probabilities(spec.data, state)
end

function _log_probabilities(data, state)
    out = Matrix{Float64}(undef, data.n, 4)
    for n in 1:data.n
        p, i, r = data.person[n], data.item[n], data.rater[n]
        location = sum(Q[i, :] .* state.theta[p, :]) - state.b[i] - state.r[r]
        out[n, :] = B._ld1_pcm_probabilities(location, state.steps[i, 2:4]; log_probabilities=true)
    end
    return out
end

"""
    recovery_panel(person_rng, response_rng; persons, rho, thin=false)

Generate one preparation dataset with the protocol's fixed facet truths.
Explicit separate RNGs only. Complete ratings are generated before thinning;
equal initial RNG states give exact person-prefix and thin-subset pairing.
This is not joint-prior SBC and never calls a sampler.
"""
function recovery_panel(person_rng::AbstractRNG, response_rng::AbstractRNG;
        persons::Integer, rho::Real, thin::Bool=false)
    !(persons isa Bool) && 2 <= persons <= 144 ||
        throw(ArgumentError("preparation persons must be an integer in 2:144"))
    !(rho isa Bool) && isfinite(rho) && abs(rho) < 1 ||
        throw(ArgumentError("rho must be finite and strictly between -1 and 1"))
    person_rng !== response_rng || throw(ArgumentError("person and response RNGs must be separate objects"))
    theta = Matrix{Float64}(undef, persons, 2)
    for p in 1:persons
        z1, z2 = randn(person_rng), randn(person_rng)
        theta[p, :] = [z1, rho*z1 + sqrt(1-rho^2)*z2]
    end
    cells = [(p, i, r) for p in 1:persons for i in 1:8 for r in 1:4]
    columns = (; person=["P$(lpad(p, 3, '0'))" for (p,i,r) in cells],
        item=["I$i" for (p,i,r) in cells], rater=["R$r" for (p,i,r) in cells])
    make_data(cols, scores) = B.FacetData(merge(cols, (;score=scores));
        person=:person, item=:item, rater=:rater, score=:score, category_levels=0:3)
    geometry = make_data(columns, zeros(Int, length(cells)))
    steps = zeros(8, 4)
    for i in 1:8
        steps[i, 2] = -(0.35+0.05*(i-1))
        steps[i, 4] = -steps[i, 2]
    end
    truth = merge(labels((;data=geometry, dimension_labels=["D1", "D2"])),
        (; theta, b=repeat([-1., -1/3, 1/3, 1.], 2),
        r=[-0.6, -0.2, 0.2, 0.6], steps, rho=Float64(rho)))
    logs = _log_probabilities(geometry, truth)
    scores = [B._ld1_inverse_cdf(rand(response_rng), exp.(row), 0:3) for row in eachrow(logs)]
    keep = [!thin || r-1 in (mod(p+i-2, 4), mod(p+i-1, 4)) for (p,i,r) in cells]
    cols = map(x -> x[keep], columns)
    # Preserve even an all-one-category outcome; model validation is a later step.
    return (; data=make_data(cols, scores[keep]), truth)
end

specification(panel) = B.mfrm_spec(panel.data; family=:mfrm, dimensions=2,
    q_matrix=Q, dimension_labels=["D1", "D2"])

base_target(t::B._MFRMFixedQReferenceLogDensity) = t
base_target(t::Union{B._MFRMFixedQCorrelated2DLogDensity,B._MFRMExchangeableRatersLogDensity}) = base_target(t.base)
target_identity(t::B._MFRMFixedQReferenceLogDensity) = B._mfrm_fixed_q_identity(t)
target_identity(t::B._MFRMFixedQCorrelated2DLogDensity) = B._mfrm_correlated_2d_identity(t)
target_identity(t::B._MFRMExchangeableRatersLogDensity) = B._mfrm_exchangeable_rater_identity(t)
is_correlated(t) = B.LogDensityProblems.dimension(t) == B.LogDensityProblems.dimension(base_target(t))+1

"""Reconstruct saved coordinates using the existing model-coordinate adapter."""
function model_states(target, draws)
    spec = base_target(target).design.spec
    coords = B._mfrm_fixed_q_model_coordinates(target, draws)
    block(name) = filter(row -> row.block === name, coords)
    person, item, rater, steps = block(:person), block(:item), block(:rater), block(:item_steps)
    rho = block(:latent_correlation)
    states = [merge(labels(spec), (;
        theta=permutedims(reshape([r.values[s] for r in person], 2, :)),
        b=[r.values[s] for r in item], r=[r.values[s] for r in rater],
        steps=permutedims(reshape([r.values[s] for r in steps], 4, 8)),
        rho=isempty(rho) ? 0.0 : only(rho).values[s])) for s in axes(draws, 1)]
    foreach(s -> check_state(spec, s), states)
    return states
end

function estimands(spec, state; correlated::Bool)
    logs = log_probabilities(spec, state)
    values = [state.r[4]-state.r[1], state.r[2]-state.r[1], state.b[4]-state.b[1],
        state.b[8]-state.b[5], state.theta[1,1]-state.theta[2,1],
        state.theta[1,2]-state.theta[2,2], state.steps[1,2], state.steps[8,4]]
    names = copy(FOCAL_NAMES)
    if correlated
        push!(values, state.rho); push!(names, "rho")
    end
    push!(values, mean(sum(exp.(logs[:, 3:4]); dims=2)))
    push!(names, "mean_Pr(Y>=2)")
    center = vec(mean(state.theta; dims=1))
    return (; names, values, log_probabilities=logs,
        centered_theta=state.theta .- transpose(center), centered_b=state.b-spec.q_matrix*center)
end

function chain_order(chain_ids, iterations, n)
    length(chain_ids) == length(iterations) == n && n > 0 ||
        throw(ArgumentError("chain/iteration IDs must cover every retained draw"))
    all(x -> x isa Integer && !(x isa Bool) && x > 0, [chain_ids; iterations]) ||
        throw(ArgumentError("chain/iteration IDs must be positive integers"))
    chains = sort(unique(chain_ids))
    chains == collect(1:length(chains)) || throw(ArgumentError("chain IDs must be 1:C"))
    n % length(chains) == 0 || throw(ArgumentError("chains must have equal retained lengths"))
    count = n ÷ length(chains)
    all(c -> sort(iterations[chain_ids .== c]) == collect(1:count), chains) ||
        throw(ArgumentError("iterations must cover 1:L once per chain; no gaps or duplicates"))
    return (; order=sortperm(collect(zip(chain_ids, iterations))), chains=length(chains))
end

"""
Prepare known-truth scores from explicitly labelled retained draws. The supplied
diagnostic flag is a caller declaration on this low-level preparation path;
`score_fit` obtains it from the validated fit. Neither applies study acceptance.
"""
function score_draws(panel, target, draws::AbstractMatrix;
        parameter_names, chain_ids, iterations, diagnostic_flag::Symbol,
        expected_target_identity::AbstractString)
    target_identity(target) == expected_target_identity || throw(ArgumentError("target identity mismatch"))
    spec = base_target(target).design.spec
    B.design_identity(B.getdesign(specification(panel); preview=true)).value ==
        B.design_identity(base_target(target).design).value || throw(ArgumentError("response/specification mismatch"))
    parameter_names == B._mfrm_fixed_q_parameter_names(target) ||
        throw(ArgumentError("free-coordinate names/order mismatch"))
    check_state(spec, panel.truth)
    layout = chain_order(chain_ids, iterations, size(draws, 1))
    correlated = is_correlated(target)
    truth = estimands(spec, panel.truth; correlated)
    states = model_states(target, draws[layout.order, :])
    transformed = [estimands(spec, state; correlated) for state in states]
    values = permutedims(hcat([e.values for e in transformed]...))
    mcse = B.posterior_mcse(values; chains=layout.chains, parameter_names=truth.names,
        probabilities=(0.025, 0.975))
    rows = [begin
        samples = values[:, j]
        lower, upper = quantile(samples, [0.025, 0.975])
        estimate = mean(samples)
        (; parameter=name, truth=truth.values[j], estimate, error=estimate-truth.values[j],
            lower, upper, covered=lower <= truth.values[j] <= upper, width=upper-lower,
            posterior_sd=std(samples), mcse=mcse[j])
    end for (j, name) in pairs(truth.names)]
    # ponytail: a probability cube suffices for bounded preparation. Stream draws
    # only if the reviewed evaluation's measured memory budget requires it.
    logs = Array{Float64}(undef, length(states), spec.data.n, 4)
    for s in eachindex(states)
        logs[s, :, :] = transformed[s].log_probabilities
    end
    predictive = B.mgmfrm_predictive_recovery_score(logs, truth.log_probabilities;
        category_levels=0:3, log_probabilities=true)
    status = diagnostic_flag !== :ok ? :diagnostic_warning :
        any(r -> r.mcse.mcse_status !== :available, rows) ? :mcse_unavailable : :prepared
    return (; status, target_identity=expected_target_identity, diagnostic_flag,
        rows, estimand_draws=values, chain_order=layout.order, mcse_chains=layout.chains,
        predictive, mean_brier_regret=4predictive.summary.root_mean_squared_category_probability_error^2,
        scientific_acceptance=false, precision_threshold_applied=false)
end

function score_fit(panel, fit::B._FixedQMFRMFit; expected_target_identity::AbstractString)
    checked = B._canonical_mfrm_fixed_q_samples(fit)
    checked.record.target_identity == expected_target_identity || throw(ArgumentError("fit target identity mismatch"))
    run = checked.record.run
    return score_draws(panel, B._fixed_q_result_target(checked), run.draws;
        parameter_names=checked.parameter_names, run.chain_ids, run.iterations,
        diagnostic_flag=checked.diagnostics.summary.flag, expected_target_identity)
end

"""Join primary attempts to one cell's full planned roster, retaining missing IDs.
Each plan row has `id` and `target_identity`; each attempt also has `result`.
No retries or replacement are accepted. Failure results have a status and no rows.
"""
function summarize_attempts(plan, attempts; parameter::AbstractString)
    !isempty(plan) || throw(ArgumentError("planned denominator must be positive"))
    all(r -> r.id isa AbstractString && !isempty(r.id) && r.target_identity isa AbstractString &&
        !isempty(r.target_identity), [plan; attempts]) || throw(ArgumentError("attempt identities must be nonempty strings"))
    length(unique(r.id for r in plan)) == length(plan) &&
        length(unique(r.id for r in attempts)) == length(attempts) || throw(ArgumentError("duplicate primary attempt ID"))
    planned = Dict(r.id => r.target_identity for r in plan)
    all(r -> get(planned, r.id, nothing) == r.target_identity, attempts) ||
        throw(ArgumentError("unplanned attempt or mismatched target"))
    results = Dict(r.id => r.result for r in attempts)
    reasons = Dict{Symbol,Int}()
    usable = NamedTuple[]
    for p in plan
        result = get(results, p.id, nothing)
        status = result === nothing ? :missing_attempt : result.status
        status in (:missing_attempt, :generation_error, :fit_error, :scoring_error, :timeout, :interrupted, :missing_draws,
            :nonfinite_draws, :diagnostic_warning, :mcse_unavailable, :prepared) ||
            throw(ArgumentError("unknown preparation attempt status"))
        reasons[status] = get(reasons, status, 0)+1
        if status in (:prepared, :diagnostic_warning, :mcse_unavailable)
            result.target_identity == p.target_identity || throw(ArgumentError("score target identity mismatch"))
            row = only(filter(r -> r.parameter == parameter, result.rows))
            status === :prepared && begin
                result.diagnostic_flag === :ok && row.mcse.mcse_status === :available &&
                    all(isfinite, (row.estimate, row.truth, row.error, row.lower, row.upper, row.width)) ||
                    throw(ArgumentError("prepared result has unavailable diagnostics, precision or scores"))
                row.mcse.parameter == row.parameter && row.lower <= row.upper &&
                    isapprox(row.error, row.estimate-row.truth; atol=1e-12) &&
                    isapprox(row.width, row.upper-row.lower; atol=1e-12) &&
                    row.covered === (row.lower <= row.truth <= row.upper) ||
                    throw(ArgumentError("inconsistent scalar score or MCSE binding"))
                push!(usable, row)
            end
        elseif result !== nothing && hasproperty(result, :rows) && result.rows !== nothing
            throw(ArgumentError("failed attempt must not contain partial score rows"))
        end
    end
    n, total = length(usable), length(plan)
    covered = count(r -> r.covered, usable)
    errors = [r.error for r in usable]
    rmse = n == 0 ? missing : sqrt(mean(abs2, errors))
    wilson(c) = B._free_correlation_study_wilson(c, total, 1.959963984540054; interval_kind=:two_sided_95)
    return (; parameter, planned=total, usable=n, unresolved=total-n, reasons,
        conditional_coverage=n == 0 ? missing : covered/n,
        all_attempt_coverage_bounds=(covered/total, (covered+total-n)/total),
        coverage_wilson_envelope=(wilson(covered).lower, wilson(covered+total-n).upper),
        conditional_bias=n == 0 ? missing : mean(errors), conditional_rmse=rmse,
        bias_mcse=n < 2 ? missing : std(errors)/sqrt(n),
        rmse_mcse=n < 2 || iszero(rmse) ? missing : std(abs2.(errors))/(2rmse*sqrt(n)),
        conditional_mean_width=n == 0 ? missing : mean(r.width for r in usable),
        all_attempt_continuous_scores_available=total == n, scientific_acceptance=false)
end

end
