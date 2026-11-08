module UnifiedAPIAndStarAssociationChecks

using Test
using BayesianMGMFRM
using ForwardDiff
using LinearAlgebra
using Random
using Statistics

const B = BayesianMGMFRM
const E = B.Experimental
const SA = E.StarAssociation
const C3D = E.Correlated3D
const JR = E.JointRatings
const S = JR.S
const OA = JR.OrdinalAssociation
const VS = B.ValidationSuite

include("joint_ratings_fixture.jl")

function _mfrm_connected_data()
    rows = (;
        person = ["P1", "P1", "P1", "P2", "P2", "P2", "P3", "P3", "P3", "P4", "P4", "P4"],
        rater  = ["R1", "R2", "R1", "R1", "R2", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
        item   = ["I1", "I1", "I2", "I1", "I2", "I2", "I1", "I1", "I2", "I1", "I2", "I2"],
        score  = [0, 1, 2, 1, 0, 2, 2, 1, 1, 0, 2, 1],
    )
    return FacetData(rows; person = :person, rater = :rater, item = :item, score = :score)
end

function _correlated_3d_spec()
    cells = [(p, i, r) for p in 1:3 for i in 1:6 for r in 1:3]
    data = FacetData(
        (;
            person = first.(cells),
            item = getindex.(cells, 2),
            rater = last.(cells),
            score = [mod(p + i + r, 4) for (p, i, r) in cells],
        );
        person = :person,
        item = :item,
        rater = :rater,
        score = :score,
        category_levels = 0:3,
    )
    Q = [j == 1 + mod(cld(i, 2) - 1, 3) for i in 1:6, j in 1:3]
    return mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 3,
        thresholds = :partial_credit,
        q_matrix = Q,
        dimension_labels = ["T1", "T2", "T3"],
    )
end

function _star_mixed_support_fixture()
    criteria = [
        (; criterion = "C1", role = :root, levels = [1, 2, 3, 4, 5], direction = :higher_is_more),
        (; criterion = "C2", levels = [0, 1, 2, 3], direction = :higher_is_more),
        (; criterion = "C3", levels = [0, 1], direction = :higher_is_less),
    ]
    prior = (;
        entity_log_sd_mean = log(0.8),
        rater_log_sd_mean = log(0.5),
        log_sd_sd = 0.5,
        entity_lkj_eta = 2.0,
        rater_lkj_eta = 2.0,
        mu_sd = 1.5,
        step_sd = 0.8,
        step_spacing = 0.6,
        phi_sd = 0.5,
    )
    # Connected, non-uniform observation counts across 5 entities and 4 raters
    pairs_er = [
        ("E1", "R1"), ("E1", "R2"), ("E1", "R3"), ("E1", "R4"),
        ("E2", "R1"), ("E2", "R2"), ("E2", "R3"),
        ("E3", "R1"), ("E3", "R2"),
        ("E4", "R1"), ("E4", "R4"),
        ("E5", "R2"),
    ]
    rows = NamedTuple[]
    obs_id = 0
    for (ev_idx, (ent, rat)) in enumerate(pairs_er)
        eid = "ev_$ev_idx"
        s1 = 1 + mod(ev_idx * 2, 5)
        s2 = mod(ev_idx + 1, 4)
        s3 = mod(ev_idx, 2)
        for (cid, sc) in (("C1", s1), ("C2", s2), ("C3", s3))
            obs_id += 1
            push!(rows, (;
                observation_id = "obs_$obs_id",
                rating_event_id = eid,
                entity = ent,
                rater = rat,
                criterion = cid,
                score = sc,
            ))
        end
    end
    return (; rows, criteria, prior)
end

@testset "Namespace governance, ValidationSuite, and root contract" begin
    @test :Experimental ∉ names(B)
    @test :ValidationSuite ∉ names(B)
    @test :plot ∉ names(B)
    @test isdefined(B, :ValidationSuite)
    @test isdefined(B, :plot)
    @test E.StarAssociation === JR.StarAssociation

    vs_contract = VS.contract()
    @test vs_contract.schema == "bayesianmgmfrm.validation_suite.v1"
    @test vs_contract.root_compatibility_preserved
    @test VS.RecoveryPlanning === E.RecoveryPlanning
    for sym in B._ROOT_API_RESEARCH_BINDINGS
        @test sym in names(VS)
        @test getfield(VS, sym) === getfield(B, sym)
    end
    for sym in vs_contract.groups.free_latent_correlation_2d_study
        @test sym in names(VS)
        @test getfield(VS, sym) === getfield(E, sym)
    end

    root_contract = B._root_api_contract()
    for verb in (
        :design_summary, :with_options, :prior_draw, :simulate,
        :prepare_fit, :run_chain_worker, :worker_status, :collect_fit,
        :qualify, :facet_summary, :category_summary, :contrast,
        :event_probabilities, :reliability, :ranking, :classification,
        :criteria, :predictive_check, :save_fit, :load_fit,
        :save_report, :load_report, :contract, :parameter_names,
        :facet_basis, :coordinates, :to_ncp_reference, :from_ncp_reference,
        :reparameterize_point, :reparameterize_draws, :log_jacobian_to_ncp,
        :logdensity_and_gradient, :stan_data, :sampler_controls,
    )
        @test verb in names(B)
        @test verb in root_contract.stable
    end
end

@testset "Unified practitioner & glass-box lifecycle on scalar MFRM" begin
    data = _mfrm_connected_data()
    spec = mfrm_spec(data; thresholds = :partial_credit)
    spec_rsm = with_options(spec; thresholds = :rating_scale)
    @test spec_rsm.thresholds === :rating_scale
    @test spec.thresholds === :partial_credit

    ds_data = design_summary(data)
    ds_spec = design_summary(spec)
    design = getdesign(spec)
    ds_des = design_summary(design)
    @test ds_data.n_observations == 12
    @test ds_spec.family === :mfrm
    @test ds_des.n_free_parameters == length(design.parameter_names)

    # Glass-box surface on MFRM
    c_view = contract(spec)
    @test c_view.family === :mfrm
    @test parameter_names(spec; scale = :raw) == design.parameter_names
    @test length(parameter_names(spec; scale = :model)) >= length(design.parameter_names)
    fb_p = facet_basis(spec, :person)
    @test fb_p.n_levels == 4
    @test sum(fb_p.observation_counts) == 12

    q = prior_draw(spec; seed = 42)
    @test length(q) == length(design.parameter_names)
    sim = simulate(spec; seed = 42)
    @test sim.truth ≈ q
    @test sim.simulated.n == 12

    target = MFRMLogDensity(design, MFRMPrior())
    coords = coordinates(target, q)
    @test length(coords.person) == 4
    @test coords.rater[1] == 0.0
    @test coords.item[1] == 0.0
    @test sum(coords.steps) ≈ 0.0 atol = 1e-12
    @test to_ncp_reference(target, q) ≈ q
    @test from_ncp_reference(target, q) ≈ q
    @test log_jacobian_to_ncp(target, q) == 0.0
    pw_ll = pointwise_loglikelihood(target, q)
    @test sum(pw_ll) ≈ loglikelihood(target, q) atol = 1e-12
    @test logprior(target, q) + loglikelihood(target, q) ≈ logposterior(target, q) atol = 1e-12
    val, grad = logdensity_and_gradient(target, q)
    @test val ≈ logposterior(target, q) atol = 1e-12
    @test grad ≈ ForwardDiff.gradient(z -> logposterior(target, z), q) atol = 1e-10
    sdata = stan_data(target)
    @test sdata.N == 12

    # Practitioner fitting, reporting, decisions, and persistence
    mfrm_fit = fit(spec; chains = 2, warmup = 15, ndraws = 15, seed = 101)
    q_gate = qualify(mfrm_fit)
    @test hasproperty(q_gate, :qualified)
    @test !isempty(posterior_summary(mfrm_fit))
    fs_p = facet_summary(mfrm_fit; facet = :person)
    @test fs_p.n_levels == 4
    cs = category_summary(mfrm_fit)
    @test hasproperty(cs, :usage_rows) || hasproperty(cs, :categories) || cs isa NamedTuple
    ctr = contrast(mfrm_fit; left = fs_p.rows[1].parameter, right = fs_p.rows[2].parameter)
    @test isfinite(ctr.summary.mean)
    evp = event_probabilities(mfrm_fit)
    @test size(evp) == (30, 12, 3) || evp isa AbstractArray || evp isa NamedTuple
    rel = reliability(mfrm_fit)
    @test hasproperty(rel, :reliability) || hasproperty(rel, :estimate)
    rnk = ranking(mfrm_fit)
    @test !isempty(rnk.rows)
    cls = classification(mfrm_fit; cutoff = 0.0)
    @test !isempty(cls.rows)
    crit = criteria(mfrm_fit)
    @test hasproperty(crit, :waic) && hasproperty(crit, :psis_loo)
    ppc_res = predictive_check(mfrm_fit; ndraws = 8, seed = 7)
    @test ppc_res isa NamedTuple
    sc = sampler_controls(mfrm_fit)
    @test sc isa NamedTuple

    if Base.get_extension(B, :BayesianMGMFRMCairoMakieExt) === nothing
        @test_throws ArgumentError B.plot(mfrm_fit; kind = :posterior)
    end
    @test_throws ArgumentError B.plot(mfrm_fit; kind = :nonexistent_kind)

    mktempdir() do dir
        fit_path = joinpath(dir, "mfrm_fit.jls")
        save_fit(fit_path, mfrm_fit)
        @test_throws Exception save_fit(fit_path, mfrm_fit)
        reloaded = load_fit(fit_path)
        @test reloaded.draws == mfrm_fit.draws

        rep = fit_report(mfrm_fit; view = :public)
        rep_path = joinpath(dir, "mfrm_report.json")
        save_report(rep_path, rep)
        loaded_rep = load_report(rep_path)
        @test loaded_rep isa AbstractDict || loaded_rep isa NamedTuple

        rep_path2 = joinpath(dir, "mfrm_report_direct.json")
        save_report(rep_path2, mfrm_fit; view = :public)
        @test isfile(rep_path2)
    end
end

@testset "Unified 3D correlated MGMFRM delegation and lifecycle" begin
    spec3d = _correlated_3d_spec()
    scales = (;
        person_sd = 1.0,
        rater_sd = 0.5,
        item_sd = 0.7,
        log_discrimination_sd = 0.3,
        log_consistency_sd = 0.4,
        step_sd = 0.6,
    )
    t3d = E.correlated(spec3d; scales, lkj_eta = 2.5)
    @test t3d isa C3D.Target
    @test contract(t3d) == E.surface_contract(t3d)
    @test design_summary(t3d).lkj_eta == 2.5
    @test length(parameter_names(t3d; scale = :raw)) == 40
    @test length(parameter_names(t3d; scale = :model)) == 57

    q = prior_draw(t3d; seed = 11)
    @test length(q) == 40
    sim3 = simulate(t3d; seed = 11)
    @test sim3.truth == q
    ppc3 = prior_predictive_check(t3d; ndraws = 4, seed = 11)
    @test length(ppc3.rows) == 4

    @test sum(pointwise_loglikelihood(t3d, q)) ≈ loglikelihood(t3d, q) atol = 1e-12
    @test logprior(t3d, q) + loglikelihood(t3d, q) ≈ logposterior(t3d, q) atol = 1e-12
    val3, grad3 = logdensity_and_gradient(t3d, q)
    @test val3 ≈ logposterior(t3d, q) atol = 1e-12
    @test grad3 ≈ ForwardDiff.gradient(z -> logposterior(t3d, z), q) atol = 1e-10
    @test haskey(stan_data(t3d), :N) || stan_data(t3d) isa NamedTuple

    r3d = fit(t3d; chains = 2, warmup = 8, ndraws = 8, seed = 12, step_size = 0.05, max_depth = 5)
    @test qualify(r3d) isa NamedTuple
    @test diagnostics(r3d) isa NamedTuple
    rep3d = posterior_summary(r3d)
    @test rep3d.schema == "bayesianmgmfrm.correlated_3d_report.v1"
    c3 = contrast(r3d; left = "rho[\"T1\",\"T2\"]", right = "rho[\"T1\",\"T3\"]")
    @test isfinite(c3.mean)
    ep3_one = event_probabilities(r3d; observation = 1)
    @test ep3_one.operation === :probabilities
    ep3 = event_probabilities(r3d; rows = [1, 2])
    @test length(ep3.rows) == 2
    crit3 = criteria(r3d)
    @test isfinite(crit3.waic.waic) && isfinite(crit3.psis_loo.elpd_loo)
    @test waic(r3d).waic ≈ crit3.waic.waic
    @test psis_loo(r3d).elpd_loo ≈ crit3.psis_loo.elpd_loo
    @test sampler_controls(r3d).chains == 2

    mktempdir() do dir
        fpath = joinpath(dir, "c3d.jls")
        save_fit(fpath, r3d)
        r3d_back = load_fit(fpath)
        @test r3d_back.content_hash == r3d.content_hash

        rpath = joinpath(dir, "c3d_report.json")
        save_report(rpath, rep3d)
        @test load_report(rpath) isa Any
    end
end

@testset "Unified joint_rating_spec (:none, :uniform, :star) and full StarAssociation surface" begin
    # 1. association = :none (JointRatings) and :uniform (OrdinalAssociation)
    b_fix = static_fixture(; K = 3, shared = false, predictors = false, sparse = true)
    t_none = E.joint_rating_spec(b_fix.data.rows; criteria = b_fix.data.criteria, prior = b_fix.prior, association = :none)
    @test t_none isa JR.S.Target
    @test design_summary(t_none).n_criteria == 2
    q_none = JR.S.initial(t_none)
    v_none, g_none = logdensity_and_gradient(t_none, q_none)
    @test v_none ≈ logposterior(t_none, q_none) atol = 1e-12
    @test g_none ≈ ForwardDiff.gradient(z -> logposterior(t_none, z), q_none) atol = 1e-8

    oa_prior = merge(
        Base.structdiff(b_fix.prior, (; beta_sd = nothing)),
        (; intercept_sd = 1.5, person_log_sd_mean = log(0.5), person_log_sd_sd = 0.5, lambda_sd = 0.5),
    )
    t_unif = E.joint_rating_spec(b_fix.data.rows; criteria = b_fix.data.criteria, prior = oa_prior, association = :uniform)
    @test t_unif isa OA.Target
    @test design_summary(t_unif).n_criteria == 2
    q_unif = OA.initial(t_unif)
    v_unif, g_unif = logdensity_and_gradient(t_unif, q_unif)
    @test v_unif ≈ logposterior(t_unif, q_unif) atol = 1e-12
    @test g_unif ≈ ForwardDiff.gradient(z -> logposterior(t_unif, z), q_unif) atol = 2e-9

    # 2. association = :star (General D=3 mixed-support StarAssociation)
    sf = _star_mixed_support_fixture()
    m_star = E.joint_rating_spec(sf.rows; criteria = sf.criteria, prior = sf.prior, association = :star)
    @test m_star isa SA.StarModel
    @test contract(m_star).status === :experimental
    @test E.surface_contract(m_star) == SA.contract()

    ds = design_summary(m_star)
    @test ds.n_criteria == 3
    @test ds.n_entities == 5
    @test ds.n_raters == 4
    @test ds.connectivity.is_connected

    # Schur-complement permutation invariance across relabeled entity IDs
    relabel = Dict("E1" => "Z9", "E2" => "A1", "E3" => "M5", "E4" => "B2", "E5" => "K7")
    rows_perm = [merge(r, (; entity = relabel[r.entity])) for r in reverse(sf.rows)]
    m_perm = E.joint_rating_spec(rows_perm; criteria = sf.criteria, prior = sf.prior, association = :star)
    @test facet_basis(m_star, :entity).effective_counts ≈ facet_basis(m_perm, :entity).effective_counts atol = 1e-14

    # Exact chart diffeomorphism, triangular log-Jacobian, and analytical gradient
    m_cp = with_options(m_star; parameterization = :cp)
    m_ncp = with_options(m_star; parameterization = :ncp)
    m_lex = with_options(m_star; parameterization = :cp, basis_order = :legacy_lexicographic)
    m_nophi = with_options(m_star; association = false)

    q = prior_draw(m_star; seed = 21)
    q_ncp = to_ncp_reference(m_star, q)
    @test from_ncp_reference(m_star, q_ncp) ≈ q atol = 1e-12
    @test logposterior(m_star, q) ≈ logposterior(m_ncp, q_ncp) + log_jacobian_to_ncp(m_star, q) atol = 1e-12

    q_lex = reparameterize_point(m_lex, m_star, q)
    @test reparameterize_point(q, m_star, m_lex) ≈ q_lex atol = 1e-12
    c_orig = coordinates(m_star, q)
    c_lex = coordinates(m_lex, q_lex)
    @test c_orig.A ≈ c_lex.A atol = 1e-12
    @test c_orig.S ≈ c_lex.S atol = 1e-12
    @test pointwise_loglikelihood(m_star, q) ≈ pointwise_loglikelihood(m_lex, q_lex) atol = 1e-12
    @test sum(pointwise_loglikelihood(m_star, q)) ≈ loglikelihood(m_star, q) atol = 1e-12
    @test logprior(m_star, q) + loglikelihood(m_star, q) ≈ logposterior(m_star, q) atol = 1e-12

    lp_val, lp_grad = logdensity_and_gradient(m_star, q)
    fd_grad = ForwardDiff.gradient(
        z -> first(SA.evaluate_density_gradient(m_star, z; likelihood = true, compute_gradient = false)),
        q,
    )
    @test lp_val ≈ logposterior(m_star, q) atol = 1e-12
    @test lp_grad ≈ fd_grad atol = 1e-10
    @test stan_data(m_star).D_crit == 3

    # Prior predictive & synthetic simulation
    sim_star = simulate(m_star; seed = 22)
    @test length(sim_star.rows) == length(sf.rows)
    ppc_prior = prior_predictive_check(m_star; ndraws = 6, seed = 22)
    @test ppc_prior.ndraws == 6

    # Direct fit + multi-worker checkpointed fit + post-fit workflow
    res_star = fit(m_star; chains = 2, warmup = 10, ndraws = 10, seed = 31)
    res_nophi = fit(m_nophi; chains = 2, warmup = 10, ndraws = 10, seed = 32)
    @test res_star isa SA.StarResult
    @test sampler_controls(res_star).chains == 2
    @test length(parameter_names(res_star; scale = :raw)) == m_star.dim
    @test !isempty(parameter_names(res_star; scale = :model))

    # Reparameterizing draws preserves retained_stats and exact Jacobian-adjusted log_density
    res_ncp = reparameterize_draws(res_star, m_ncp)
    @test length(res_ncp.retained_stats) == size(res_ncp.draws, 1)
    for s in 1:size(res_ncp.draws, 1)
        @test res_ncp.logdensities[s] ≈ logposterior(m_ncp, view(res_ncp.draws, s, :)) atol = 1e-11
        @test res_ncp.retained_stats[s].log_density ≈ res_ncp.logdensities[s] atol = 1e-11
    end
    mat_ncp = reparameterize_draws(res_star.draws, m_star, m_ncp)
    @test mat_ncp ≈ res_ncp.draws atol = 1e-12

    @test qualify(res_star).operation === :qualify
    @test diagnostics(res_star).operation === :qualify
    psum = posterior_summary(res_star)
    psum_ncp = posterior_summary(res_ncp)
    @test [r.mean for r in psum.result.posterior] ≈ [r.mean for r in psum_ncp.result.posterior] atol = 1e-11

    @test facet_summary(res_star; facet = :entity).result.n_selected_levels == 5
    @test category_summary(res_star).operation === :category_summary
    @test isfinite(contrast(res_star; facet = :entity, criterion = "C1", left = "E1", right = "E2").result.summary.mean)
    @test event_probabilities(res_star; rating_event_id = "ev_1").operation === :event_probabilities
    @test isfinite(reliability(res_star; criterion = "C1").result.reliability)
    @test ranking(res_star; criterion = "C1", top_k = 2).result.n_levels == 5
    @test classification(res_star; criterion = "C1", cutoff = 0.0).result.n_levels == 5

    @test isfinite(waic(res_star).result.waic)
    @test isfinite(psis_loo(res_star).result.elpd_loo)
    @test criteria(res_star).operation === :criteria
    @test predictive_check(res_star; seed = 51).operation === :ppc
    @test SA.evaluate(res_star; seed = 51).operation === :evaluate

    cmp_direct = compare_models(res_star, res_nophi)
    cmp_pairs = compare_models([:star => res_star, :independent => res_nophi])
    @test cmp_direct.psis_loo_diff.elpd_diff ≈ cmp_pairs.psis_loo_diff.elpd_diff atol = 1e-12

    alt_prior = SA.PriorConfig(; merge(sf.prior, (; phi_sd = 0.8, step_sd = 1.0))...)
    ps_single = prior_sensitivity(res_star, alt_prior)
    ps_vec = prior_sensitivity(res_star, [:wider => alt_prior])
    @test length(ps_single.result.variants) == 1
    @test ps_single.result.variants[1].max_physical_coord_error < 1e-12
    @test ps_vec.result.variants[1].max_likelihood_invariance_error < 1e-11

    if Base.get_extension(B, :BayesianMGMFRMCairoMakieExt) === nothing
        @test_throws ArgumentError B.plot(res_star; kind = :posterior)
    end

    # Multi-worker checkpointing + native & JSON persistence
    mktempdir() do dir
        ws = joinpath(dir, "workers")
        prepare_fit(m_star, ws; chains = 2, warmup = 8, ndraws = 8, seed = 41, checkpoint_every = 4)
        st0 = worker_status(ws)
        @test !st0.all_complete
        @test all(c -> c.completed == 0, st0.chains)
        run_chain_worker(ws, 1)
        run_chain_worker(ws, 2)
        st1 = worker_status(ws)
        @test st1.all_complete
        res_ws = collect_fit(ws)
        @test size(res_ws.draws) == (16, m_star.dim)

        fit_file = joinpath(dir, "star_fit.jls")
        save_fit(fit_file, res_star)
        @test_throws ArgumentError save_fit(fit_file, res_star)
        res_loaded = load_fit(fit_file)
        @test res_loaded.content_hash == res_star.content_hash

        rep_file = joinpath(dir, "star_summary.json")
        save_report(rep_file, psum)
        @test_throws ArgumentError save_report(rep_file, psum)
        rep_loaded = load_report(rep_file)
        @test String(rep_loaded.schema) == SA.REPORT_SCHEMA
    end
end

end
