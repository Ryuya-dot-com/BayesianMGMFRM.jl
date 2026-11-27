module CriterionCollapseLifecycleChecks
using BayesianMGMFRM, Test, Statistics, LinearAlgebra
using BayesianMGMFRM.GlassBox
using BayesianMGMFRM.Legacy
const B = BayesianMGMFRM
const L = B.LogDensityProblems
const C = B.Experimental.CriterionCollapse
include("fixtures/experimental_diagnostic_record.jl")

function enumerate_lik(t, q, ns; ordinary = false)
    c = C.category_logprobs(t, q)
    s = C.coordinates(t, q)
    sum(
        prod(z[r] == 0 ? exp(s.log1mpi) : exp(s.logpi) for r in 1:t.R) *
        prod(exp((z[t.rater[n]] == 0 ? c.ordinary : c.halo)[n, t.score[n] + 1]) for n in ns)
        for z in Iterators.product(fill(0:1, t.R)...) if !ordinary || all(iszero, z)
    )
end

function synthetic_masked_record(mt::C.MaskedTarget; chains = 4, ndraws = 60, phase = 0.0, diverge = false)
    init = C.initial(mt)
    n = chains * ndraws
    # Construct oscillatory multi-chain draws with rank-normalized R-hat ~ 1.00 and high ESS
    draws = [0.09 * sin(2.3 * s + 0.41 * j + phase) + 0.06 * cos(3.7 * s + 0.73 * j + phase)
             for s in 1:n, j in eachindex(init)]
    ld = [L.logdensity(mt, q) for q in eachrow(draws)]
    chain_ids = repeat(1:chains; inner = ndraws)
    iterations = repeat(1:ndraws; outer = chains)
    controls = (; ndraws, chains, warmup = 0, step_size = 0.08, target_accept = 0.9, max_depth = 10,
        max_energy_error = 1000.0, init_jitter = 0.0, metric = :diagonal,
        ad_backend = :ForwardDiff, gradient_backend = :ad)
    stats = NamedTuple[B._advancedhmc_stat_row((;
        log_density = ld[s], step_size = 0.08, acceptance_rate = 0.88,
        hamiltonian_energy = Float64(mod(s, 5) + 0.3 * sin(s)),
        numerical_error = diverge && s == 1, tree_depth = 2), chain_ids[s], iterations[s]) for s in 1:n]
    acceptance = fill(0.88, chains)
    run = (; checked = B._check_diagnostic_thresholds(1.05, 5), nparams = length(init), initial = init,
        initial_logdensity = L.logdensity(mt, init), total_draws = n, draws, logdensities = ld,
        chain_ids, iterations, chain_acceptance = acceptance, sampler_stats = stats, controls,
        sampler_rows = B._generalized_candidate_sampler_rows(ld, iterations, acceptance, stats, controls, :advancedhmc),
        backend = :advancedhmc, sampler = :nuts, split_chains_requested = true, actual_split = true,
        warmup_stats = NamedTuple[])
    rec = C._masked_target_record(mt)
    body = (; schema = C.SCHEMA_MASKED, target = rec, target_identity = B._cache_hash(rec), scope = C.SCOPE, run)
    return merge(body, (; content_hash = B._cache_hash(body)))
end

function well_mixed_cc_record(t::C.Target; chains = 4, ndraws = 60, phase = 0.0)
    init = C.initial(t)
    n = chains * ndraws
    draws = [0.09 * sin(2.3 * s + 0.41 * j + phase) + 0.06 * cos(3.7 * s + 0.73 * j + phase)
             for s in 1:n, j in eachindex(init)]
    ld = [L.logdensity(t, q) for q in eachrow(draws)]
    chain_ids = repeat(1:chains; inner = ndraws)
    iterations = repeat(1:ndraws; outer = chains)
    controls = (; ndraws, chains, warmup = 0, step_size = 0.08, target_accept = 0.9, max_depth = 10,
        max_energy_error = 1000.0, init_jitter = 0.0, metric = :diagonal,
        ad_backend = :ForwardDiff, gradient_backend = :ad)
    stats = NamedTuple[B._advancedhmc_stat_row((;
        log_density = ld[s], step_size = 0.08, acceptance_rate = 0.88,
        hamiltonian_energy = Float64(mod(s, 5) + 0.3 * sin(s)),
        numerical_error = false, tree_depth = 2), chain_ids[s], iterations[s]) for s in 1:n]
    acceptance = fill(0.88, chains)
    run = (; checked = B._check_diagnostic_thresholds(1.05, 5), nparams = length(init), initial = init,
        initial_logdensity = L.logdensity(t, init), total_draws = n, draws, logdensities = ld,
        chain_ids, iterations, chain_acceptance = acceptance, sampler_stats = stats, controls,
        sampler_rows = B._generalized_candidate_sampler_rows(ld, iterations, acceptance, stats, controls, :advancedhmc),
        backend = :advancedhmc, sampler = :nuts, split_chains_requested = true, actual_split = true,
        warmup_stats = NamedTuple[])
    rec = C._target_record(t)
    body = (; schema = C.SCHEMA, target = rec, target_identity = B._cache_hash(rec), scope = C.SCOPE, run)
    return merge(body, (; content_hash = B._cache_hash(body)))
end

@testset "CriterionCollapse unified lifecycle, MaskedTarget refits, and pair comparison" begin
    _, t = diagnostic_target(:CriterionCollapse)
    result = well_mixed_cc_record(t; phase = 0.1)

    # 1. Layer-1 & Layer-2 Glass-Box dispatch on Target and sample record
    vd = validate_design(t)
    @test vd.passed && vd.identified && vd.persons == t.P
    @test getdesign(result).P == t.P
    @test contract(t) == contract(result)
    @test :loo_refit_plan in contract(t).operations
    q0 = initial_params(t)
    @test length(q0) == L.dimension(t)
    @test length(parameter_names(t; scale = :raw)) == L.dimension(t)
    @test parameter_names(t; scale = :raw)[end] == "logit_pi"
    @test parameter_names(t; scale = :model)[end] == "pi"
    @test parameter_names(result; scale = :model) == parameter_names(t; scale = :model)
    val, grad = logdensity_and_gradient(t, q0)
    @test val ≈ logposterior(t, q0) atol = 1e-13
    @test val ≈ logprior(t, q0) + loglikelihood(t, q0) atol = 1e-13
    @test length(grad) == length(q0) && all(isfinite, grad)

    # Posterior summary / fit_report / posterior_predictive_check / waic & psis_loo guidance
    rep_sum = fit_report(result)
    @test hasproperty(rep_sum, :classes) && length(rep_sum.classes) == t.R
    ppc1 = predictive_check(result; category = 1)
    ppc2 = posterior_predictive_check(result; category = 1)
    @test ppc1.expected_count.estimate ≈ ppc2.expected_count.estimate atol = 1e-14
    @test_throws ArgumentError waic(result)
    @test_throws ArgumentError psis_loo(result)

    # 2. loo_refit_plan & MaskedTarget exact enumeration parity (both :mixture and :all_ordinary)
    plan_mix = loo_refit_plan(result, 1; unit = :performance_rater, model = :mixture)
    plan_by_tuple = loo_refit_plan(result, (plan_mix.person, plan_mix.rater);
        unit = :performance_rater, model = :mixture)
    @test C.target_identity(plan_mix.target) == C.target_identity(plan_by_tuple.target)
    @test plan_mix.automatic_refit === false
    @test plan_mix.unit === :performance_rater

    plan_ord = loo_refit_plan(result, 2; unit = :performance_rater, model = :all_ordinary)
    mt_mix = plan_mix.target
    mt_ord = plan_ord.target
    @test L.dimension(mt_mix) == L.dimension(t)
    @test L.dimension(mt_ord) == L.dimension(t) - 1
    @test mt_mix.base.Qp == t.Qp && mt_ord.base.Qp == t.Qp
    @test mt_mix.base.Qr == t.Qr && mt_ord.base.Qr == t.Qr
    @test parameter_names(mt_ord; scale = :raw)[end] == "log_rater_precision"
    @test parameter_names(mt_ord; scale = :model)[end] == "sigma_rater"
    @test validate_design(mt_ord).passed

    qm = result.run.draws[3, :]
    qo = qm[1:end-1]
    # Mixture training log-posterior matches exact 2^R enumeration on retained rows
    @test L.logdensity(mt_mix, qm) ≈ C.logprior(t, qm) + log(enumerate_lik(t, qm, mt_mix.retained; ordinary = false)) atol = 1e-13
    # All-ordinary training log-posterior integrates pi analytically over Beta(a,b), matching t.base (halo=false) prior + ordinary retained rows
    @test L.logdensity(mt_ord, qo) ≈ C.logprior(mt_ord.base, qo) + log(enumerate_lik(mt_ord.base, qo, mt_ord.retained; ordinary = true)) atol = 1e-13

    # Held-out profile conditional log probability on MaskedTarget matches exact enumeration ratio
    lp_mix_h = C._masked_heldout_logprobs(mt_mix, reshape(qm, 1, :))[1]
    @test lp_mix_h ≈ log(enumerate_lik(t, qm, 1:t.data.n; ordinary = false) / enumerate_lik(t, qm, mt_mix.retained; ordinary = false)) atol = 1e-13
    lp_ord_h = C._masked_heldout_logprobs(mt_ord, reshape(qo, 1, :))[1]
    @test lp_ord_h ≈ log(enumerate_lik(t, qm, 1:t.data.n; ordinary = true) / enumerate_lik(t, qm, mt_ord.retained; ordinary = true)) atol = 1e-13

    # 3. Masked sample record persistence, qualification, criteria refits & mixed-provenance compare_models
    rf_mix = synthetic_masked_record(mt_mix; phase = 0.7)
    rf_ord = synthetic_masked_record(mt_ord; phase = 1.3)
    @test getdesign(rf_ord).profile == 2
    @test qualify(rf_mix; max_rhat = 1.05, min_ess = 5.0).qualified
    @test qualify(rf_ord; max_rhat = 1.05, min_ess = 5.0).qualified
    mktempdir() do dir
        p_rf = joinpath(dir, "masked_ord.jls")
        save_fit(p_rf, rf_ord)
        loaded_rf = load_fit(p_rf)
        @test loaded_rf.content_hash == rf_ord.content_hash
    end

    c_ord_ref = criteria(result; unit = :performance_rater, model = :all_ordinary,
        refits = [2 => rf_ord], independent_refit_rng = true)
    @test C._operation_report_check(c_ord_ref) === c_ord_ref
    @test c_ord_ref.result.pointwise[2].method === :direct_refit
    @test length(c_ord_ref.result.reference_records) == 1

    # When independent_refit_rng = false, covariance is marked :unassessed_refit_covariance and mcse is missing
    c_ord_unassessed = criteria(result; unit = :performance_rater, model = :all_ordinary,
        refits = [2 => rf_ord], independent_refit_rng = false)
    @test C._operation_report_check(c_ord_unassessed) === c_ord_unassessed
    @test c_ord_unassessed.result.pointwise[2].mcse_status === :unassessed_refit_covariance
    @test ismissing(c_ord_unassessed.result.mcse) && c_ord_unassessed.mcse_warning

    # Mixed-provenance single-fit compare_models with both mixture and ordinary refits
    cmp_mixed = compare_models(result; criterion = :loo, unit = :performance_rater,
        mixture_refits = [1 => rf_mix], ordinary_refits = [2 => rf_ord], independent_refit_rng = true)
    @test C._operation_report_check(cmp_mixed) === cmp_mixed
    @test cmp_mixed.difference.estimate ≈ cmp_mixed.mixture.elpd - cmp_mixed.all_ordinary.elpd atol = 1e-12

    # Fraud/mismatch rejections
    @test_throws ArgumentError criteria(result; unit = :performance_rater, model = :mixture,
        refits = [2 => rf_ord], independent_refit_rng = true) # wrong model branch
    @test_throws ArgumentError criteria(result; unit = :performance_rater, model = :all_ordinary,
        refits = [1 => rf_ord], independent_refit_rng = true) # wrong profile index

    # 4. Two-report compare_models across distinct prior variants
    prior_wide = C.Prior(person_precision_shape = 3.0, person_precision_rate = 2.0,
        rater_precision_shape = 3.0, rater_precision_rate = 0.5,
        step_sd = 3.0, class_alpha = 1.0, class_beta = 1.0)
    t_wide = C.model(t.data; prior = prior_wide)
    result_wide = well_mixed_cc_record(t_wide; phase = 1.9)
    c_base = criteria(result; unit = :performance_rater, model = :mixture)
    c_wide = criteria(result_wide; unit = :performance_rater, model = :mixture)

    pair_indep = compare_models("step_1.5" => c_base, "step_3.0" => c_wide;
        criterion = :loo, independent_model_rng = true)
    @test pair_indep.kind === :criterion_collapse_heldout_pair_comparison
    @test C._operation_report_check(pair_indep) === pair_indep
    @test pair_indep.difference.estimate ≈ c_base.result.elpd - c_wide.result.elpd atol = 1e-12
    pair_vec = compare_models(["step_1.5" => c_base, "step_3.0" => c_wide];
        criterion = :loo, independent_model_rng = true)
    @test pair_vec.difference.estimate ≈ pair_indep.difference.estimate atol = 1e-14

    mktempdir() do dir
        rec = save_report(joinpath(dir, "pair_cmp.json"), pair_indep; return_receipt = true)
        restored = load_report(rec.path; expected_sha256 = rec.sha256)
        @test restored.difference.estimate ≈ pair_indep.difference.estimate atol = 1e-12
    end

    # Shared sample stream rejected when independent_model_rng = true
    c_ord_same = criteria(result; unit = :performance_rater, model = :all_ordinary)
    @test_throws ArgumentError compare_models("mix" => c_base, "ord" => c_ord_same;
        criterion = :loo, independent_model_rng = true)
    pair_dep = compare_models("mix" => c_base, "ord" => c_ord_same;
        criterion = :loo, independent_model_rng = false)
    @test pair_dep.difference.mcse_status === :unassessed_model_covariance && ismissing(pair_dep.difference.mcse)
    @test_throws ArgumentError compare_models("a" => c_base, "b" => c_wide; criterion = :waic)

    # 5. Unified BayesianMGMFRM.plot checks when CairoMakie is loaded
    if Base.get_extension(B, :BayesianMGMFRMCairoMakieExt) !== nothing
        @test B.plot(rep_sum; kind = :posterior, annotation_io = IOBuffer()) !== nothing
        @test B.plot(ppc1; kind = :predictive, annotation_io = IOBuffer()) !== nothing
        @test B.plot(c_ord_ref; kind = :comparison, annotation_io = IOBuffer()) !== nothing
        @test B.plot(cmp_mixed; kind = :comparison, annotation_io = IOBuffer()) !== nothing
        @test B.plot(pair_indep; kind = :comparison, annotation_io = IOBuffer()) !== nothing
        @test_throws ArgumentError B.plot(ppc1; kind = :comparison, annotation_io = IOBuffer())
        @test_throws ArgumentError B.plot(cmp_mixed; kind = :predictive, annotation_io = IOBuffer())
    end
end
end
