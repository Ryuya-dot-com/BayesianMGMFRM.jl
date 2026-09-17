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
    return _check_coordinates(spec, state)
end

function _check_coordinates(spec, state)
    data = spec.data
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

function _geometry(persons::Integer)
    !(persons isa Bool) && 2 <= persons <= 144 ||
        throw(ArgumentError("preparation persons must be an integer in 2:144"))
    cells = [(p, i, r) for p in 1:persons for i in 1:8 for r in 1:4]
    columns = (; person=["P$(lpad(p, 3, '0'))" for (p,i,r) in cells],
        item=["I$i" for (p,i,r) in cells], rater=["R$r" for (p,i,r) in cells])
    return (; cells, columns, data=_response_data(columns, zeros(Int, length(cells))))
end

_response_data(columns, scores) = B.FacetData(merge(columns, (;score=scores));
    person=:person, item=:item, rater=:rater, score=:score, category_levels=0:3)

function _response_panel(geometry, truth, response_rng; thin=false)
    logs = _log_probabilities(geometry.data, truth)
    scores = [B._ld1_inverse_cdf(rand(response_rng), exp.(row), 0:3) for row in eachrow(logs)]
    keep = [!thin || r-1 in (mod(p+i-2, 4), mod(p+i-1, 4)) for (p,i,r) in geometry.cells]
    cols = map(x -> x[keep], geometry.columns)
    # Preserve even an all-one-category outcome; model validation is a later step.
    return (; data=_response_data(cols, scores[keep]), truth)
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
    geometry = _geometry(persons)
    !(rho isa Bool) && isfinite(rho) && abs(rho) < 1 ||
        throw(ArgumentError("rho must be finite and strictly between -1 and 1"))
    person_rng !== response_rng || throw(ArgumentError("person and response RNGs must be separate objects"))
    theta = Matrix{Float64}(undef, persons, 2)
    for p in 1:persons
        z1, z2 = randn(person_rng), randn(person_rng)
        theta[p, :] = [z1, rho*z1 + sqrt(1-rho^2)*z2]
    end
    steps = zeros(8, 4)
    for i in 1:8
        steps[i, 2] = -(0.35+0.05*(i-1))
        steps[i, 4] = -steps[i, 2]
    end
    truth = merge(labels((;data=geometry.data, dimension_labels=["D1", "D2"])),
        (; theta, b=repeat([-1., -1/3, 1/3, 1.], 2),
        r=[-0.6, -0.2, 0.2, 0.6], steps, rho=Float64(rho)))
    return _response_panel(geometry, truth, response_rng; thin)
end

specification(panel) = B.mfrm_spec(panel.data; family=:mfrm, dimensions=2,
    q_matrix=Q, dimension_labels=["D1", "D2"])

function _prior_options(prior, correlated, lkj_eta)
    prior isa Union{B.MFRMPrior,B._ExchangeablePrior} || throw(ArgumentError("unsupported rater prior"))
    correlated isa Bool || throw(ArgumentError("correlated must be Bool"))
    if correlated
        B._checked_integer_lkj_eta(lkj_eta)
    else
        lkj_eta === nothing || throw(ArgumentError("independent abilities have no LKJ prior"))
    end
    return nothing
end

# Separate from _fixed_q_prior_draws: generate in full model coordinates.
function _prior_state(geometry, rng, prior; correlated::Bool, lkj_eta)
    _prior_options(prior, correlated, lkj_eta)
    rho = correlated ? 2rand(rng, B.Turing.Beta(lkj_eta, lkj_eta))-1 : 0.0
    abs(rho) < 1 || throw(ArgumentError("unrepresentable boundary prior correlation; retain this failure"))
    theta = Matrix{Float64}(undef, length(geometry.data.person_levels), 2)
    for p in axes(theta, 1)
        z1, z2 = randn(rng), randn(rng)
        theta[p, :] = prior.person_sd .* [z1, rho*z1+sqrt((1-rho)*(1+rho))*z2]
    end
    r = if prior isa B._ExchangeablePrior
        z = randn(rng, 4)
        prior.rater_kernel_sd .* (z .- mean(z))
    else
        free = prior.rater_sd .* randn(rng, 3)
        [free; -sum(free)]
    end
    b = prior.item_sd .* randn(rng, 8)
    free_steps = prior.step_sd .* randn(rng, 8, 2)
    steps = [zeros(8) free_steps -sum(free_steps; dims=2)]
    all(isfinite, (theta..., r..., b..., steps...)) ||
        throw(ArgumentError("nonfinite prior coordinates; retain this failure"))
    return merge(labels((; data=geometry.data, dimension_labels=["D1", "D2"])),
        (; theta, b, r, steps, rho))
end

"""Generate one complete joint-prior panel; never reject/redraw or fit it.
The selected prior/covariance is retained for binding later SBC test quantities.
"""
function prior_panel(prior_rng::AbstractRNG, response_rng::AbstractRNG;
        persons::Integer, prior, correlated::Bool, lkj_eta=correlated ? 2 : nothing)
    prior_rng !== response_rng || throw(ArgumentError("prior and response RNGs must be separate objects"))
    geometry = _geometry(persons)
    truth = _prior_state(geometry, prior_rng, prior; correlated, lkj_eta)
    return merge(_response_panel(geometry, truth, response_rng),
        (; generation=(; kind=:joint_prior, prior, correlated, lkj_eta)))
end

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

function _check_draw_binding(panel, target, parameter_names, expected_target_identity)
    target_identity(target) == expected_target_identity || throw(ArgumentError("target identity mismatch"))
    spec = base_target(target).design.spec
    B.design_identity(B.getdesign(specification(panel); preview=true)).value ==
        B.design_identity(base_target(target).design).value || throw(ArgumentError("response/specification mismatch"))
    parameter_names == B._mfrm_fixed_q_parameter_names(target) ||
        throw(ArgumentError("free-coordinate names/order mismatch"))
    check_state(spec, panel.truth)
    return spec
end

function sbc_quantities(spec, state; correlated::Bool)
    e = estimands(spec, state; correlated)
    joint_loglik = sum(e.log_probabilities[n, spec.data.category[n]] for n in 1:spec.data.n)
    values = [e.values; state.theta[1,1]; state.b[1]; joint_loglik]
    all(isfinite, values) || throw(ArgumentError("nonfinite SBC test quantity"))
    return (; names=[e.names; "theta11"; "b1"; "joint_log_likelihood"], values)
end

"""Bind SBC quantities to the generating prior and the retained chain IDs.
The same explicit iterations are selected per chain. This does not qualify
diagnostics or establish independent posterior draws; no ranks are inferred here.
"""
function sbc_draw_quantities(panel, target, draws::AbstractMatrix;
        parameter_names, chain_ids, iterations, selected_iterations,
        expected_target_identity::AbstractString)
    hasproperty(panel, :generation) && panel.generation.kind === :joint_prior ||
        throw(ArgumentError("SBC requires joint-prior generation, not fixed-facet recovery"))
    g = panel.generation
    _prior_options(g.prior, g.correlated, g.lkj_eta)
    g.correlated || iszero(panel.truth.rho) || throw(ArgumentError("independent SBC truth must have rho=0"))
    spec = _check_draw_binding(panel, target, parameter_names, expected_target_identity)
    model = g.correlated ? B.Experimental.correlated(spec; lkj_eta=g.lkj_eta) : spec
    target_identity(B._fixed_q_prior_target(model, g.prior)) == expected_target_identity ||
        throw(ArgumentError("generating and fitted priors/covariances differ"))
    layout = chain_order(chain_ids, iterations, size(draws, 1))
    selected = collect(selected_iterations)
    !isempty(selected) && all(x -> x isa Integer && !(x isa Bool) &&
        1 <= x <= size(draws,1) ÷ layout.chains, selected) && issorted(selected) &&
        length(unique(selected)) == length(selected) ||
        throw(ArgumentError("selected iterations must be nonempty, increasing, unique retained IDs"))
    # Validate every retained row, including rows not selected for ranks.
    states = model_states(target, draws[layout.order, :])
    chosen = findall(in(selected), iterations[layout.order])
    truth = sbc_quantities(spec, panel.truth; correlated=g.correlated)
    quantities = [sbc_quantities(spec, state; correlated=g.correlated) for state in states]
    retained_draws = permutedims(hcat([q.values for q in quantities]...))
    return (; target_identity=expected_target_identity, names=truth.names, truth=truth.values,
        draws=retained_draws[chosen, :], retained_draws,
        selected_rows=layout.order[chosen], chain_ids=chain_ids[layout.order[chosen]],
        iterations=iterations[layout.order[chosen]], n_chains=layout.chains,
        independence_verified=false, diagnostic_qualification_applied=false,
        scientific_acceptance=false)
end

"""Zero-based rank, with exact ties randomized uniformly in their rank interval."""
function randomized_rank(truth::Real, draws::AbstractVector{<:Real}, rng::AbstractRNG)
    !(truth isa Bool) && isfinite(truth) && !isempty(draws) &&
        all(x -> !(x isa Bool) && isfinite(x), draws) ||
        throw(ArgumentError("rank quantities must be finite real values with at least one draw"))
    lower = count(<(truth), draws)
    ties = count(==(truth), draws)
    return (; rank=lower+(ties == 0 ? 0 : rand(rng, 0:ties)), lower, upper=lower+ties,
        n_draws=length(draws), ties)
end

"""Conditional DKW screen for one quantity, with one rank or `missing` per
planned dataset. T is the predeclared within-target quantity family size.
This arithmetic assumes independent datasets and valid iid posterior ranks;
it neither checks that assumption nor treats no departure as calibration.
"""
function rank_cdf(ranks::AbstractVector; n_draws::Integer, n_quantities::Integer, alpha::Real=0.05)
    !(n_draws isa Bool) && n_draws > 0 && !(n_quantities isa Bool) && n_quantities > 0 &&
        !(alpha isa Bool) && isfinite(alpha) && 0 < alpha < 1 && !isempty(ranks) ||
        throw(ArgumentError("invalid rank support, quantity count, alpha or planned denominator"))
    all(r -> ismissing(r) || (r isa Integer && !(r isa Bool) && 0 <= r <= n_draws), ranks) ||
        throw(ArgumentError("each planned slot must contain a rank in 0:L or missing"))
    valid = collect(skipmissing(ranks))
    n, unresolved = length(ranks), count(ismissing, ranks)
    epsilon = sqrt((log(2.0)+log(n_quantities)-log(alpha))/(2n))
    rows = [begin
        c = count(<=(k), valid)
        lower = k == n_draws ? 1.0 : c/n
        upper = k == n_draws ? 1.0 : (c+unresolved)/n
        band_lower = k == n_draws ? 1.0 : max(0.0, lower-epsilon)
        band_upper = k == n_draws ? 1.0 : min(1.0, upper+epsilon)
        reference = (k+1)/(n_draws+1)
        (; rank=k, reference, lower, upper, band_lower, band_upper,
            resolved_departure=reference < band_lower || reference > band_upper)
    end for k in 0:n_draws]
    return (; planned=n, usable=length(valid), unresolved, n_draws, n_quantities, alpha, epsilon, rows,
        conditional_screen=isempty(valid) ? :unresolved :
            any(r -> r.resolved_departure, rows) ? :departure : :no_resolved_departure,
        independence_verified=false, calibration_verified=false, scientific_acceptance=false)
end

"""
Prepare known-truth scores from explicitly labelled retained draws. The supplied
diagnostic flag is a caller declaration on this low-level preparation path;
`score_fit` obtains it from the validated fit. Neither applies study acceptance.
"""
function score_draws(panel, target, draws::AbstractMatrix;
        parameter_names, chain_ids, iterations, diagnostic_flag::Symbol,
        expected_target_identity::AbstractString)
    spec = _check_draw_binding(panel, target, parameter_names, expected_target_identity)
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

_finite_number(x) = x isa Real && !(x isa Bool) && isfinite(x)

function _comparison_criteria(criteria)
    keys(criteria) == (:chains, :rhat, :ess, :ebfmi, :allow_treedepth_hits) &&
        criteria.chains isa Integer && !(criteria.chains isa Bool) && criteria.chains >= 2 &&
        all(_finite_number, (criteria.rhat, criteria.ess, criteria.ebfmi)) &&
        criteria.rhat > 1 && criteria.ess > 0 && criteria.ebfmi > 0 &&
        criteria.allow_treedepth_hits isa Bool || throw(ArgumentError("invalid explicit comparison criteria"))
    return criteria
end

"""Apply supplied criteria to diagnostic rows; this low-level path trusts the
caller's row/telemetry declarations. `prepare_comparison_fit` rebuilds them from
a validated record. Qualification is conditional, never scientific acceptance.
"""
function qualify_diagnostics(groups, sampler_rows; criteria, telemetry_complete::Bool)
    _comparison_criteria(criteria)
    keys(groups) == (:raw, :model, :focal) || throw(ArgumentError("raw, model and focal diagnostics required"))
    failures = NamedTuple[]
    fail(scope, name, reason) = push!(failures, (;scope, name=string(name), reason))
    for (scope, rows) in pairs(groups)
        isempty(rows) && fail(scope, "", :missing_parameters)
        length(unique(r.parameter for r in rows)) == length(rows) || throw(ArgumentError("duplicate diagnostic parameter"))
        for r in rows
            r.quality_gate_applicable isa Bool || throw(ArgumentError("invalid fixed-parameter declaration"))
            if !r.quality_gate_applicable
                scope === :model && r.diagnostic_status === :structurally_fixed ||
                    throw(ArgumentError("only structural model constants may be excluded"))
                continue
            end
            r.n_chains == criteria.chains && r.split_chains === true || fail(scope, r.parameter, :chain_layout)
            all(_finite_number, (r.rank_normalized_rhat, r.bulk_ess, r.tail_ess)) &&
                0 < r.rank_normalized_rhat < criteria.rhat &&
                r.bulk_ess >= criteria.ess && r.tail_ess >= criteria.ess || fail(scope, r.parameter, :parameter_diagnostics)
        end
    end
    length(unique(r.chain for r in sampler_rows)) == length(sampler_rows) || throw(ArgumentError("duplicate sampler chain"))
    sort([r.chain for r in sampler_rows]) == collect(1:criteria.chains) || fail(:sampler, "", :chain_coverage)
    telemetry_complete || fail(:sampler, "", :incomplete_telemetry)
    for r in sampler_rows
        for field in (:n_nonfinite_logdensity, :n_divergences, :n_max_treedepth)
            value = getproperty(r, field)
            value isa Integer && !(value isa Bool) && value >= 0 || fail(:sampler, r.chain, :unavailable_counts)
        end
        r.n_nonfinite_logdensity === 0 || fail(:sampler, r.chain, :nonfinite_logdensity)
        r.n_divergences === 0 || fail(:sampler, r.chain, :divergences)
        (criteria.allow_treedepth_hits || r.n_max_treedepth === 0) || fail(:sampler, r.chain, :treedepth)
        _finite_number(r.e_bfmi) && r.e_bfmi >= criteria.ebfmi || fail(:sampler, r.chain, :energy)
    end
    return (; qualified=isempty(failures), criteria, failures, sampler_rows,
        scientific_acceptance=false, criteria_adopted=false)
end

"""Rebuild raw, constrained and focal diagnostics and statistic-specific MCSE
from a canonical saved fit. No sampling, policy defaults or automatic rescue.
"""
function prepare_comparison_fit(panel, fit::B._FixedQMFRMFit;
        expected_target_identity::AbstractString, criteria)
    _comparison_criteria(criteria)
    checked = B._canonical_mfrm_fixed_q_samples(fit)
    checked.record.target_identity == expected_target_identity || throw(ArgumentError("fit target identity mismatch"))
    run = checked.record.run
    score = score_draws(panel, B._fixed_q_result_target(checked), run.draws;
        parameter_names=checked.parameter_names, run.chain_ids, run.iterations,
        diagnostic_flag=checked.diagnostics.summary.flag, expected_target_identity)
    diagnostics = _fit_qualification(checked, score.estimand_draws, [r.parameter for r in score.rows]; criteria)
    return (; status=:comparison_prepared, target_identity=expected_target_identity,
        backend=run.backend, rows=score.rows, diagnostics.qualification, diagnostics.diagnostic_rows,
        original_diagnostic_flag=score.diagnostic_flag, scientific_acceptance=false)
end

function _fit_qualification(checked, focal_draws, focal_names; criteria)
    run = checked.record.run
    diagnostic(values, names; fixed=Set{String}()) = B._candidate_mcmc_diagnostic_rows(
        values, names, run.controls.chains; split_chains=true,
        structurally_fixed_parameters=fixed, rhat_threshold=Float64(criteria.rhat),
        ess_threshold=Float64(criteria.ess))
    coordinates = checked.model_coordinates
    groups = (;
        raw=diagnostic(run.draws, checked.parameter_names),
        model=diagnostic(hcat([r.values for r in coordinates]...), [r.parameter for r in coordinates];
            fixed=Set(r.parameter for r in coordinates if r.fixed)),
        focal=diagnostic(focal_draws, focal_names))
    # Zero step/depth sentinels in historical records are not complete NUTS telemetry.
    telemetry_complete = all(run.sampler_stats) do r
        r.numerical_error isa Bool && r.n_steps isa Integer && !(r.n_steps isa Bool) && r.n_steps > 0 &&
            r.tree_depth isa Integer && !(r.tree_depth isa Bool) && r.tree_depth > 0 && _finite_number(r.hamiltonian_energy)
    end
    qualification = qualify_diagnostics(groups, checked.diagnostics.sampler_rows; criteria, telemetry_complete)
    return (; qualification, diagnostic_rows=groups)
end

function _sbc_generation(; persons, prior, correlated, lkj_eta)
    _geometry(persons)
    _prior_options(prior, correlated, lkj_eta)
    prior_record = prior isa B.MFRMPrior ? B._prior_cache_record(prior) :
        (; prior_contract=:exchangeable_zero_sum_normal, prior.person_sd,
            prior.rater_kernel_sd, prior.item_sd, prior.step_sd)
    return (; geometry=:complete_two_dimension_pcm, persons, q_matrix=copy(Q),
        prior=prior_record, correlated, lkj_eta)
end

"""Declare one target/backend's primary SBC roster before generating data.
IDs, complete geometry, prior, diagnostic criteria, selected iterations and a
dependence-policy reference are explicit. This neither seeds nor runs a study.
"""
function sbc_plan(ids; persons, prior, correlated, lkj_eta=correlated ? 2 : nothing,
        backend::Symbol, criteria, selected_iterations, dependence_policy::AbstractString)
    generation = _sbc_generation(; persons, prior, correlated, lkj_eta)
    _comparison_criteria(criteria)
    ids = collect(ids); selected = collect(selected_iterations)
    !isempty(ids) && all(x -> x isa AbstractString && !isempty(strip(x)), ids) &&
        length(unique(ids)) == length(ids) || throw(ArgumentError("SBC IDs must be nonempty unique strings"))
    !isempty(selected) && all(x -> x isa Integer && !(x isa Bool) && x > 0, selected) &&
        issorted(selected) && length(unique(selected)) == length(selected) ||
        throw(ArgumentError("SBC selection must be explicit increasing positive iteration IDs"))
    backend in (:advancedhmc, :cmdstan) && !isempty(strip(dependence_policy)) ||
        throw(ArgumentError("SBC requires a supported backend and dependence-policy reference"))
    body = (; ids=String.(ids), generation, backend, criteria,
        selected_iterations=Int.(selected), dependence_policy=String(dependence_policy))
    return merge(body, (; identity=B._cache_hash(body)))
end

function _check_sbc_plan(plan)
    plan.identity == B._cache_hash(Base.structdiff(plan, (;identity=nothing))) ||
        throw(ArgumentError("SBC plan changed after declaration"))
    return nothing
end

"""Own a snapshot of generated truth/responses before model validation or fitting.
Even a single-category generated dataset can be bound and retained as a failure.
"""
function bind_sbc_panel(plan, id::AbstractString, panel)
    _check_sbc_plan(plan)
    id in plan.ids || throw(ArgumentError("unplanned SBC dataset ID"))
    hasproperty(panel, :generation) && panel.generation.kind === :joint_prior ||
        throw(ArgumentError("SBC input requires joint-prior generation"))
    g = panel.generation
    generation = _sbc_generation(; persons=length(panel.data.person_levels), g.prior, g.correlated, g.lkj_eta)
    generation == plan.generation || throw(ArgumentError("SBC generating target differs from plan"))
    geometry = _geometry(generation.persons)
    data = panel.data
    all(k -> getproperty(data, k) == getproperty(geometry.data, k),
        (:n, :person, :rater, :item, :person_levels, :rater_levels, :item_levels,
            :category_levels, :optional, :optional_levels, :columns)) &&
        length(data.score) == data.n && all(in(0:3), data.score) && data.category == data.score .+ 1 ||
        throw(ArgumentError("SBC responses must retain the planned complete labelled geometry"))
    _check_coordinates((;data=geometry.data, dimension_labels=["D1", "D2"]), panel.truth)
    g.correlated || iszero(panel.truth.rho) || throw(ArgumentError("independent SBC truth must have rho=0"))
    data_payload = NamedTuple{fieldnames(B.FacetData)}(Tuple(getfield(data, k) for k in fieldnames(B.FacetData)))
    panel_identity = B._cache_hash((; generation, data=data_payload, panel.truth))
    return (; id=String(id), plan_identity=plan.identity, panel_identity, panel=deepcopy(panel))
end

function _checked_sbc_input(plan, input)
    expected = bind_sbc_panel(plan, input.id, input.panel)
    input.plan_identity == expected.plan_identity && input.panel_identity == expected.panel_identity ||
        throw(ArgumentError("SBC input changed after binding"))
    return expected
end

function _check_dependence(declaration)
    keys(declaration) == (:status, :evidence) &&
        declaration.status in (:unresolved, :declared_independent) &&
        declaration.evidence isa AbstractString && !isempty(strip(declaration.evidence)) ||
        throw(ArgumentError("supply an explicit dependence status and evidence/reference"))
    return nothing
end

_sbc_status(qualification, dependence) = !qualification.qualified ? :diagnostic_warning :
    dependence.status === :unresolved ? :dependence_unresolved : :rank_prepared
_seal_sbc_attempt(body) = merge(body, (;content_hash=B._cache_hash(body)))

"""Bind a canonical fit and all retained SBC quantity diagnostics to one input.
The dependence declaration refers to this plan's selected draws; it is not
inferred from diagnostics or thinning. Only eligible ranks consume `rank_rng`.
"""
function prepare_sbc_fit(plan, input, fit::B._FixedQMFRMFit;
        dependence, rank_rng::AbstractRNG)
    input = _checked_sbc_input(plan, input)
    _check_dependence(dependence)
    checked = B._canonical_mfrm_fixed_q_samples(fit)
    run = checked.record.run
    run.backend === plan.backend || throw(ArgumentError("SBC backend differs from plan"))
    quantities = sbc_draw_quantities(input.panel, B._fixed_q_result_target(checked), run.draws;
        parameter_names=checked.parameter_names, run.chain_ids, run.iterations,
        plan.selected_iterations, expected_target_identity=checked.record.target_identity)
    diagnostics = _fit_qualification(checked, quantities.retained_draws, quantities.names; criteria=plan.criteria)
    status = _sbc_status(diagnostics.qualification, dependence)
    ranks = status === :rank_prepared ? [merge((;parameter=name),
        randomized_rank(quantities.truth[j], quantities.draws[:,j], rank_rng))
        for (j,name) in pairs(quantities.names)] : nothing
    sample_identity = checked.record.content_hash
    draw_identity = B._cache_hash((; sample_identity, quantities))
    return _seal_sbc_attempt((; input.id, input.plan_identity, status, input,
        target_identity=checked.record.target_identity, sample_identity, draw_identity,
        quantities, diagnostics.qualification, diagnostics.diagnostic_rows, dependence, ranks,
        original_diagnostic_flag=checked.diagnostics.summary.flag,
        independence_verified=false, scientific_acceptance=false))
end

"""Retain a primary failure, including one before a panel/fit identity exists.
This records a caller-observed failure; it catches no exception and retries nothing.
"""
function sbc_failure(plan, id::AbstractString, status::Symbol; detail::AbstractString, input=nothing)
    _check_sbc_plan(plan)
    id in plan.ids && !isempty(strip(detail)) || throw(ArgumentError("planned SBC ID and failure detail required"))
    status in (:generation_error, :fit_error, :scoring_error, :timeout, :interrupted,
        :missing_draws, :nonfinite_draws) || throw(ArgumentError("unknown SBC failure status"))
    input === nothing && !(status in (:generation_error, :timeout, :interrupted)) &&
        throw(ArgumentError("post-generation SBC failures must retain the bound input"))
    input = input === nothing ? nothing : _checked_sbc_input(plan, input)
    input === nothing || input.id == id || throw(ArgumentError("failure/input dataset ID mismatch"))
    return _seal_sbc_attempt((; id=String(id), plan_identity=plan.identity, status,
        detail=String(detail), input, scientific_acceptance=false))
end

"""Join one frozen SBC roster to primary attempts and form full-denominator CDFs.
The complete 12/13-quantity family is fixed. Dataset independence is a separate
caller declaration; unresolved assumptions suppress the conditional DKW screen.
"""
function summarize_sbc_attempts(plan, attempts; alpha, dataset_independence)
    _check_sbc_plan(plan)
    _check_dependence(dataset_independence)
    results = _attempt_results([(;id, target_identity=plan.identity) for id in plan.ids],
        [(;r.id, target_identity=r.plan_identity, result=r) for r in attempts])
    names = vcat(FOCAL_NAMES, plan.generation.correlated ? ["rho"] : String[],
        ["mean_Pr(Y>=2)", "theta11", "b1", "joint_log_likelihood"])
    n_draws = Base.checked_mul(plan.criteria.chains, length(plan.selected_iterations))
    rank_columns = [Union{Missing,Int}[missing for _ in plan.ids] for _ in names]
    ledger, reasons = NamedTuple[], Dict{Symbol,Int}()
    seen_panels, seen_samples = Set{String}(), Set{String}()
    for (i,id) in pairs(plan.ids)
        r = get(results, id, nothing)
        status = r === nothing ? :missing_attempt : r.status
        if r !== nothing
            r.content_hash == B._cache_hash(Base.structdiff(r, (;content_hash=nothing))) ||
                throw(ArgumentError("SBC attempt changed after preparation"))
            if r.input !== nothing
                input = _checked_sbc_input(plan, r.input)
                input.id == id || throw(ArgumentError("SBC attempt/input ID mismatch"))
                input.panel_identity in seen_panels && throw(ArgumentError("SBC generated panel reused across primary IDs"))
                push!(seen_panels, input.panel_identity)
            end
            if status in (:rank_prepared, :diagnostic_warning, :dependence_unresolved)
                r.input !== nothing || throw(ArgumentError("SBC prepared result requires bound input"))
                _check_dependence(r.dependence)
                q = r.quantities
                q.names == names && q.target_identity == r.target_identity &&
                    r.qualification.criteria == plan.criteria &&
                    r.qualification.qualified === isempty(r.qualification.failures) &&
                    [d.parameter for d in r.diagnostic_rows.focal] == names &&
                    status === _sbc_status(r.qualification, r.dependence) ||
                    throw(ArgumentError("SBC quantity, diagnostic or status binding mismatch"))
                r.draw_identity == B._cache_hash((;r.sample_identity, quantities=q)) &&
                    q.chain_ids == repeat(1:q.n_chains; inner=length(plan.selected_iterations)) &&
                    q.iterations == repeat(plan.selected_iterations; outer=q.n_chains) ||
                    throw(ArgumentError("SBC selected draw identity mismatch"))
                r.sample_identity in seen_samples && throw(ArgumentError("SBC saved fit reused across primary IDs"))
                push!(seen_samples, r.sample_identity)
                if status === :rank_prepared
                    size(q.draws) == (n_draws, length(names)) &&
                        [x.parameter for x in r.ranks] == names || throw(ArgumentError("SBC rank family/support mismatch"))
                    for (j,rank) in pairs(r.ranks)
                        lower = count(<(q.truth[j]), q.draws[:,j])
                        ties = count(==(q.truth[j]), q.draws[:,j])
                        rank.n_draws == n_draws && rank.lower == lower && rank.ties == ties &&
                            rank.upper == lower+ties && rank.rank isa Integer && !(rank.rank isa Bool) &&
                            lower <= rank.rank <= lower+ties || throw(ArgumentError("SBC rank differs from its selected draws/truth"))
                        rank_columns[j][i] = rank.rank
                    end
                else
                    r.ranks === nothing || throw(ArgumentError("unqualified SBC attempt must not supply primary ranks"))
                end
            else
                expected = sbc_failure(plan, id, status; r.detail, r.input)
                r.content_hash == expected.content_hash || throw(ArgumentError("SBC failure must not contain partial rank results"))
            end
        end
        reasons[status] = get(reasons, status, 0)+1
        push!(ledger, (;id, status, result=r))
    end
    cdfs = [begin
        cdf = rank_cdf(ranks; n_draws, n_quantities=length(names), alpha)
        # The descriptive missing-rank envelope remains available without an
        # independence declaration; inferential bands/screens do not.
        declared = dataset_independence.status === :declared_independent
        if !declared
            cdf = merge(cdf, (;epsilon=missing, conditional_screen=:assumptions_unresolved,
                rows=[merge(row, (;band_lower=missing, band_upper=missing, resolved_departure=missing)) for row in cdf.rows]))
        end
        (;parameter=name, ranks, cdf)
    end for (name,ranks) in zip(names,rank_columns)]
    return (; plan_identity=plan.identity, planned=length(plan.ids), n_draws,
        n_quantities=length(names), reasons, ledger, cdfs, dataset_independence,
        independence_verified=false, calibration_verified=false, scientific_acceptance=false)
end

function _comparison_statistic(row, statistic)
    row === nothing && return (; estimate=missing, mcse=missing, available=false)
    row.mcse.parameter == row.parameter || throw(ArgumentError("MCSE parameter mismatch"))
    estimate = statistic === :mean ? row.estimate : statistic === :q025 ? row.lower : row.upper
    if statistic === :mean
        mcse = row.mcse.mean_mcse
    else
        probability = statistic === :q025 ? 0.025 : 0.975
        qs = filter(q -> q.probability == probability, row.mcse.quantiles)
        length(qs) <= 1 || throw(ArgumentError("duplicate quantile MCSE"))
        mcse = isempty(qs) ? missing : only(qs).mcse
        isempty(qs) || (_finite_number(estimate) && _finite_number(only(qs).estimate) &&
            isapprox(only(qs).estimate, estimate; atol=1e-12, rtol=1e-12)) ||
            throw(ArgumentError("quantile estimate/MCSE mismatch"))
    end
    available = row.mcse.mcse_status === :available &&
        all(_finite_number, (estimate, mcse, row.posterior_sd)) && mcse >= 0 && row.posterior_sd > 0
    return (; estimate, mcse, available)
end

"""Compare a fixed roster of primary backend pairs. Plan rows contain `id`,
`target_identity`, and ordered `margins` rows (`parameter`, `tolerance`). Attempt
rows add `result=(julia=..., cmdstan=...)`; either result can be a failure status.
Absent attempts, fits or scalar summaries retain all 27/30 planned comparisons.
Supplied margins and independent-stream declarations are not study approval.
"""
function compare_backend_pairs(plan, attempts; alpha, independent_streams::Bool)
    results = _attempt_results(plan, attempts)
    _finite_number(alpha) && 0 < alpha < 1 || throw(ArgumentError("alpha must be between zero and one"))
    pair_rows, rows = NamedTuple[], NamedTuple[]
    for p in plan
        names = [m.parameter for m in p.margins]
        names in (vcat(FOCAL_NAMES, ["mean_Pr(Y>=2)"]), vcat(FOCAL_NAMES, ["rho", "mean_Pr(Y>=2)"])) ||
            throw(ArgumentError("comparison plan must retain the complete primary estimand roster"))
        all(m -> _finite_number(m.tolerance) && m.tolerance > 0, p.margins) ||
            throw(ArgumentError("supply finite positive numerical margins"))
        family_size = 3length(names)
        z = quantile(B.Turing.Normal(), 1-alpha/(2family_size))
        isfinite(z) || throw(ArgumentError("alpha is too small for a finite comparison interval"))
        pair = get(results, p.id, nothing)
        fits = pair === nothing ? (nothing, nothing) : (pair.julia, pair.cmdstan)
        for (fit, backend) in zip(fits, (:advancedhmc, :cmdstan))
            fit === nothing && continue
            if fit.status === :comparison_prepared
                fit.target_identity == p.target_identity && fit.backend === backend ||
                    throw(ArgumentError("comparison target/backend mismatch"))
                fitnames = [r.parameter for r in fit.rows]
                length(unique(fitnames)) == length(fitnames) && all(in(names), fitnames) ||
                    throw(ArgumentError("duplicate or unplanned comparison parameter"))
                _comparison_criteria(fit.qualification.criteria)
                fit.qualification.qualified === isempty(fit.qualification.failures) ||
                    throw(ArgumentError("inconsistent diagnostic qualification"))
            else
                fit.status in (:generation_error, :fit_error, :scoring_error, :timeout, :interrupted,
                    :missing_draws, :nonfinite_draws) || throw(ArgumentError("unknown comparison failure status"))
                !hasproperty(fit, :rows) || fit.rows === nothing || throw(ArgumentError("failed fit has partial scores"))
            end
        end
        prepared = map(f -> f !== nothing && f.status === :comparison_prepared, fits)
        all(prepared) && fits[1].qualification.criteria != fits[2].qualification.criteria &&
            throw(ArgumentError("backend qualification criteria differ"))
        qualified = all(prepared) && all(f -> f.qualification.qualified, fits)
        tables = map(f -> f !== nothing && f.status === :comparison_prepared ?
            Dict(r.parameter => r for r in f.rows) : Dict(), fits)
        first_row = length(rows)+1
        for margin in p.margins, statistic in (:mean, :q025, :q975)
            a, b = map(t -> _comparison_statistic(get(t, margin.parameter, nothing), statistic), tables)
            delta = _finite_number(a.estimate) && _finite_number(b.estimate) ? a.estimate-b.estimate : missing
            combined = a.available && b.available ? hypot(a.mcse, b.mcse) : missing
            halfwidth = _finite_number(combined) ? z*combined : missing
            reason = !all(prepared) ? :missing_or_failed_fit : !qualified ? :diagnostics :
                !independent_streams ? :independence_undeclared :
                !(a.available && b.available && _finite_number(delta) && _finite_number(halfwidth)) ? :unavailable_precision : :precision
            status = reason !== :precision ? :inconclusive :
                abs(delta)+halfwidth <= margin.tolerance ? :agreement :
                abs(delta)-halfwidth > margin.tolerance ? :discrepancy : :inconclusive
            push!(rows, (;id=p.id, p.target_identity, margin.parameter, statistic, family_size, z,
                julia_estimate=a.estimate, cmdstan_estimate=b.estimate, delta,
                combined_mcse=combined, halfwidth, margin.tolerance, status, reason))
        end
        statuses = [r.status for r in rows[first_row:end]]
        status = :discrepancy in statuses ? :discrepancy : all(==(:agreement), statuses) ? :agreement : :inconclusive
        push!(pair_rows, (;id=p.id, p.target_identity, status, family_size,
            backend_statuses=map(f -> f === nothing ? :missing_attempt : f.status, fits),
            qualifications=map(f -> f !== nothing && f.status === :comparison_prepared ? f.qualification : nothing, fits)))
    end
    counts(rs) = (;agreement=count(r -> r.status === :agreement, rs),
        discrepancy=count(r -> r.status === :discrepancy, rs), inconclusive=count(r -> r.status === :inconclusive, rs))
    return (; planned_pairs=length(plan), planned_statistics=length(rows), pair_counts=counts(pair_rows),
        statistic_counts=counts(rows), pair_rows, rows, alpha, independent_streams_declared=independent_streams,
        independence_verified=false, scientific_acceptance=false, margins_adopted=false,
        multiplicity_scope=:within_pair)
end

function _attempt_results(plan, attempts)
    !isempty(plan) || throw(ArgumentError("planned denominator must be positive"))
    all(r -> r.id isa AbstractString && !isempty(r.id) && r.target_identity isa AbstractString &&
        !isempty(r.target_identity), [plan; attempts]) || throw(ArgumentError("attempt identities must be nonempty strings"))
    length(unique(r.id for r in plan)) == length(plan) &&
        length(unique(r.id for r in attempts)) == length(attempts) || throw(ArgumentError("duplicate primary attempt ID"))
    planned = Dict(r.id => r.target_identity for r in plan)
    all(r -> get(planned, r.id, nothing) == r.target_identity, attempts) ||
        throw(ArgumentError("unplanned attempt or mismatched target"))
    return Dict(r.id => r.result for r in attempts)
end

"""Join primary attempts to one cell's full planned roster, retaining missing IDs.
Each plan row has `id` and `target_identity`; each attempt also has `result`.
No retries or replacement are accepted. Failure results have a status and no rows.
"""
function summarize_attempts(plan, attempts; parameter::AbstractString)
    results = _attempt_results(plan, attempts)
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
