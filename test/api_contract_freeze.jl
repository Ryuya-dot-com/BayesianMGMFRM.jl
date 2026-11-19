using Test
using BayesianMGMFRM
using BayesianMGMFRM.Distributions: Normal, LogNormal
import BayesianMGMFRM.ForwardDiff as ForwardDiff
using LinearAlgebra

@testset "Layer-1 & Layer-2 model × operation contract freeze (FF4a)" begin
    # 1. Root export freeze & ModelOperationMatrix
    rc = BayesianMGMFRM._root_api_contract()
    @test length(rc.stable) == 175
    @test :StanAdapter ∉ names(BayesianMGMFRM)
    @test :PortableHandoff ∉ names(BayesianMGMFRM)
    @test :ModelOperationMatrix ∉ names(BayesianMGMFRM)

    mat = BayesianMGMFRM.ModelOperationMatrix.audit()
    @test mat.schema == "bayesianmgmfrm.model_operation_matrix.v1"
    @test mat.n_routes == 18

    # 2. Common 1D MFRM + AdditiveFacets finite & explanatory Layer-1/Layer-2 alignment
    tbl = (
        person = repeat(["P1", "P2", "P3", "P4"], inner = 6),
        rater = repeat(["R1", "R2", "R3"], outer = 8),
        item = repeat(["I1", "I2"], inner = 3, outer = 4),
        perf = repeat(["PF1", "PF2", "PF3", "PF4", "PF5", "PF6", "PF7", "PF8"], inner = 3),
        score = [0, 1, 1, 1, 2, 1, 0, 0, 1, 1, 1, 2, 1, 2, 2, 2, 2, 1, 0, 1, 2, 1, 2, 2],
    )
    fd = FacetData((person = tbl.person, rater = tbl.rater, item = tbl.item, score = tbl.score);
        person = :person, rater = :rater, item = :item, score = :score, category_levels = [0, 1, 2])
    mf = fit(mfrm_spec(fd); chains = 2, warmup = 25, ndraws = 25, seed = 101)
    q_mf = initial_params(mf.design)
    @test validate_design(mf).passed == true
    @test design_summary(mf).n_observations == 24
    @test logprior(mf, q_mf) + loglikelihood(mf, q_mf) ≈ logposterior(mf, q_mf) atol = 1e-12
    @test sum(pointwise_loglikelihood(mf, q_mf)) ≈ loglikelihood(mf, q_mf) atol = 1e-12
    @test stan_data(mf) isa Union{AbstractDict, NamedTuple}

    # Finite-panel AdditiveFacets.Target & Fit
    af_t = mfrm_spec((person = tbl.person, rater = tbl.rater, item = tbl.item, score = tbl.score);
        person = :person, score = :score, facets = (rater = :rater, item = :item), steps = :global, category_levels = 0:2,
        prior_sd = (person = 1.0, facets = (rater = 1.0, item = 1.0), step = 1.0))
    q_af = initial_params(af_t)
    @test length(q_af) == length(parameter_names(af_t; scale = :raw))
    @test logprior(af_t, q_af) + loglikelihood(af_t, q_af) ≈ logposterior(af_t, q_af) atol = 1e-12

    af_fit = fit(af_t; chains = 2, warmup = 25, ndraws = 25, seed = 102)
    @test logposterior(af_fit, q_af) ≈ logposterior(af_t, q_af) atol = 1e-12
    @test stan_data(af_fit) isa AbstractDict
    @test isfinite(waic(af_fit).elpd_waic)
    @test isfinite(psis_loo(af_fit).elpd_loo)
    @test criteria(af_fit).psis_loo.elpd_loo ≈ psis_loo(af_fit).elpd_loo atol = 1e-12
    @test facet_summary(af_fit; facet = :rater).n_levels == 3
    @test category_summary(af_fit).schema == "bayesianmgmfrm.additive_category_summary.v1"
    @test ranking(af_fit; facet = :person, top_k = 2).n_levels == 4
    @test 0.0 <= reliability(af_fit; facet = :person).reliability <= 1.0
    @test classification(af_fit; cutoff = 0.0).cohort.n_people == 4
    @test event_probabilities(af_fit; rows = [1, 2]).schema == BayesianMGMFRM.AdditiveFacets.PREDICTION_SCHEMA

    # ExplanatoryTarget refuses bare waic/psis_loo with unit=:performance guidance
    ex_t = mfrm_spec(tbl; person = :person, score = :score,
        facets = (rater = :rater, item = :item, perf = :perf), steps = :global,
        performance = :perf, category_levels = 0:2,
        prior_sd = (person = 1.0, facets = (rater = 1.0, item = 1.0), step = 1.0),
        population = (perf = LogNormal(-0.5, 0.5),))
    ex_fit = fit(ex_t; chains = 2, warmup = 20, ndraws = 20, seed = 103)
    @test_throws ArgumentError waic(ex_fit)
    @test_throws ArgumentError psis_loo(ex_fit)
    @test isfinite(criteria(ex_fit; unit = :performance, integrate = :perf).elpd)

    # 3. FrequentistMFRM deterministic Bayesian-verb refusals
    freq_spec = mfrm_spec((person = tbl.person, rater = tbl.rater, item = tbl.item, score = tbl.score);
        person = :person, score = :score, facets = (rater = :rater, item = :item), steps = :global, category_levels = 0:2)
    @test_throws ArgumentError stan_data(freq_spec)
    freq_fit = fit(freq_spec; method = :jmle)
    for fn in (posterior_summary, posterior_mcse, waic, psis_loo, ranking,
               predictive_check, sampler_controls, stan_data, logprior, logposterior)
        @test_throws ArgumentError fn(freq_fit)
    end
    @test_throws ArgumentError classification(freq_fit; cutoff = 0.0)
    @test_throws ArgumentError prior_sensitivity(freq_fit, :alt)

    # 4. JointRatings & OrdinalAssociation Layer-2 decomposition
    jr_rows = [
        (observation_id = "OBS_$(e)_$c", rating_event_id = "E$e", response_id = "O$o",
         person = "P$p", task = "T$t", rater = "R$r", criterion = c, score = mod(p + r + (c == "C2"), 3))
        for (e, (o, p, t, r)) in enumerate([(1,1,1,1),(2,2,2,2),(3,3,1,2),(4,4,2,1),(5,5,1,1),(6,6,2,2)])
        for c in ("C1", "C2")
    ]
    jr_criteria = [
        (criterion = "C1", levels = 0:2, direction = :higher_is_more, threshold_group = "C1"),
        (criterion = "C2", levels = 0:2, direction = :higher_is_more, threshold_group = "C2"),
    ]
    jr_prior = (
        task_sd = 1.0,
        rater_sd = (1.0, 1.0),
        step_sd = (1.0, 1.0),
        response_log_sd_mean = (-0.5, -0.5),
        response_log_sd_sd = (0.5, 0.5),
        beta_sd = (),
        person_lkj_eta = 2.0,
        response_lkj_eta = 2.0,
    )
    jr_t = BayesianMGMFRM.Experimental.JointRatings.S.Target(jr_rows; criteria = jr_criteria, prior = jr_prior)
    q_jr = initial_params(jr_t)
    @test validate_design(jr_t).passed == true
    @test logprior(jr_t, q_jr) + loglikelihood(jr_t, q_jr) ≈ logposterior(jr_t, q_jr) atol = 1e-12
    @test stan_data(jr_t) isa Union{AbstractDict, NamedTuple}

    oa_prior = (
        task_sd = 1.0,
        rater_sd = (1.0, 1.0),
        step_sd = (1.0, 1.0),
        response_log_sd_mean = (-0.5, -0.5),
        response_log_sd_sd = (0.5, 0.5),
        person_lkj_eta = 2.0,
        response_lkj_eta = 2.0,
        intercept_sd = 1.0,
        person_log_sd_mean = 0.0,
        person_log_sd_sd = 0.5,
        lambda_sd = 0.5,
    )
    oa_t = BayesianMGMFRM.Experimental.JointRatings.OrdinalAssociation.model(
        jr_rows; criteria = jr_criteria, prior = oa_prior)
    q_oa = initial_params(oa_t) .+ 0.05 .* collect(1:length(initial_params(oa_t))) ./ 20
    @test validate_design(oa_t).passed == true
    @test logprior(oa_t, q_oa) + loglikelihood(oa_t, q_oa) ≈ logposterior(oa_t, q_oa) atol = 1e-12
    @test_throws ArgumentError pointwise_loglikelihood(oa_t, q_oa; unit = :rating)
    @test_throws ArgumentError stan_data(oa_t)

    # 5. RaterGroupEffects, RaterItemInteractions, CriterionCollapse & RaterDrift
    rge_fd = FacetData((
        person = ["P1","P1","P2","P2","P3","P3","P4","P4"],
        rater = ["R1","R2","R1","R2","R1","R2","R1","R2"],
        item = ["I1","I2","I2","I1","I1","I2","I2","I1"],
        group = ["G1","G1","G1","G1","G2","G2","G2","G2"],
        score = [0,1,1,2,0,1,2,2],
    ); person = :person, rater = :rater, item = :item, score = :score, group = :group, category_levels = [0, 1, 2])
    rge_p = BayesianMGMFRM.Experimental.RaterGroupEffects.Prior(
        person_sd = 1.0, group_mean_sd = 1.0, item_sd = 1.0, rater_sd = 1.0,
        step_sd = 1.0, interaction_logmean = -0.5, interaction_logsd = 0.5)
    rge_t = BayesianMGMFRM.Experimental.RaterGroupEffects.model(rge_fd; prior = rge_p)
    q_rge = initial_params(rge_t)
    @test validate_design(rge_t).identified == true
    @test length(parameter_names(rge_t; scale = :raw)) == length(q_rge)
    @test !isempty(parameter_names(rge_t; scale = :model))
    @test logprior(rge_t, q_rge) + loglikelihood(rge_t, q_rge) ≈ logposterior(rge_t, q_rge) atol = 1e-12
    @test_throws ArgumentError stan_data(rge_t)

    rge_rec = fit(rge_t; chains = 4, warmup = 15, ndraws = 15, seed = 104)
    @test facet_summary(rge_rec; facet = :person).n_levels == 4
    @test ranking(rge_rec; facet = :person).n_levels == 4
    @test 0.0 <= reliability(rge_rec; facet = :person).reliability <= 1.0
    @test classification(rge_rec; cutoff = 0.0).cohort.n_people == 4
    @test_throws ArgumentError waic(rge_rec)
    @test_throws ArgumentError psis_loo(rge_rec)
    @test_throws ArgumentError prior_sensitivity(rge_rec, :alt)

    rii_p = BayesianMGMFRM.Experimental.RaterItemInteractions.Prior(
        person_sd = 1.0, item_sd = 1.0, rater_sd = 1.0, step_sd = 1.0,
        interaction_logmean = -0.5, interaction_logsd = 0.5)
    rii_t = BayesianMGMFRM.Experimental.RaterItemInteractions.model(fd; prior = rii_p)
    q_rii = initial_params(rii_t)
    @test validate_design(rii_t).identified == true
    @test logprior(rii_t, q_rii) + loglikelihood(rii_t, q_rii) ≈ logposterior(rii_t, q_rii) atol = 1e-12
    @test_throws ArgumentError stan_data(rii_t)

    cc_p = BayesianMGMFRM.Experimental.CriterionCollapse.Prior(
        person_precision_shape = 2.0, person_precision_rate = 2.0,
        rater_precision_shape = 2.0, rater_precision_rate = 2.0,
        step_sd = 1.0, class_alpha = 1.0, class_beta = 1.0)
    cc_t = BayesianMGMFRM.Experimental.CriterionCollapse.model(fd; prior = cc_p)
    q_cc = initial_params(cc_t)
    @test_throws ArgumentError pointwise_loglikelihood(cc_t, q_cc)
    @test_throws ArgumentError stan_data(cc_t)
    @test logprior(cc_t, q_cc) + loglikelihood(cc_t, q_cc) ≈ logposterior(cc_t, q_cc) atol = 1e-12

    rd_rows = [
        (event_id = "ev1", performance = "P1", rater = "R1", time = "T1", score = 0),
        (event_id = "ev2", performance = "P1", rater = "R2", time = "T2", score = 1),
        (event_id = "ev3", performance = "P2", rater = "R1", time = "T2", score = 2),
        (event_id = "ev4", performance = "P2", rater = "R2", time = "T1", score = 1),
    ]
    rd_t = BayesianMGMFRM.Experimental.RaterDrift.model(
        rd_rows; categories = 3, time_ticks = [1, 2], time_labels = ["T1", "T2"],
        time_unit = "year", process = :rw1, innovation_log_sd_mean = -1.0)
    q_rd = initial_params(rd_t)
    @test validate_design(rd_t).passed == true
    @test length(parameter_names(rd_t; scale = :raw)) == length(q_rd)
    @test logprior(rd_t, q_rd) + loglikelihood(rd_t, q_rd) ≈ logposterior(rd_t, q_rd) atol = 1e-12
    @test sum(pointwise_loglikelihood(rd_t, q_rd)) ≈ loglikelihood(rd_t, q_rd) atol = 1e-12
    val_rd, grad_rd = logdensity_and_gradient(rd_t, q_rd)
    @test val_rd ≈ logposterior(rd_t, q_rd) atol = 1e-12
    @test grad_rd ≈ ForwardDiff.gradient(z -> logposterior(rd_t, z), q_rd) atol = 1e-8
    @test stan_data(rd_t).N == 4
end
