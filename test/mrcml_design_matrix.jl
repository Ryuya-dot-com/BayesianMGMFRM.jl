using BayesianMGMFRM
using BayesianMGMFRM.GlassBox
using BayesianMGMFRM.Legacy
using Distributions: Normal, LogNormal, MvNormal, cov, mean
using ForwardDiff
using LinearAlgebra
using LogDensityProblems
using Random
using Serialization
using SparseArrays
using Statistics
using Test

const _MRCML_TEST = BayesianMGMFRM.MRCML

@testset "FF6a: Sparse MRCML Design-Matrix Engine, Isometric Compiler & Interoperability" begin
    include("mrcml_specification.jl")

    # -----------------------------------------------------------------------
    # 5. Frequentist MMLE & JMLE + Bayesian NUTS Lifecycle, Model Comparison & Persistence
    # -----------------------------------------------------------------------
    @testset "End-to-end MMLE, JMLE, Bayesian NUTS, compare_models & persistence" begin
        P_n = 28
        base_tbl = (
            person = repeat(["P$p" for p in 1:P_n], inner = 6),
            rater  = repeat(["R1", "R2", "R3"], outer = 2 * P_n),
            item   = repeat(["I1", "I1", "I1", "I2", "I2", "I2"], outer = P_n),
            score  = zeros(Int, 6 * P_n),
        )
        dgp_spec = mfrm_spec(base_tbl; person = :person, score = :score,
            facets = (rater = :rater, item = :item), steps = :item, category_levels = 0:2,
            interactions = ((:rater, :item),),
            prior_sd = (person = 0.95, facets = (rater = 0.45, item = 0.5), step = 0.45,
                        interactions = (rater_item = 0.35,)))
        sim = simulate(dgp_spec; seed = 888)
        tbl = sim.simulated
        # Compare plain PCM vs MRCML PCM + rater*item on both MMLE and Bayesian NUTS!
        spec_pcm_f = mfrm_spec(tbl; person = :person, score = :score,
            facets = (rater = :rater, item = :item), steps = :item, category_levels = 0:2, prior = :none)
        spec_int_f = mfrm_spec(tbl; person = :person, score = :score,
            facets = (rater = :rater, item = :item), steps = :item, category_levels = 0:2,
            interactions = ((:rater, :item),), prior = :none)

        f_pcm_mml = fit(spec_pcm_f; method = :mmle, estimate_mean = true, estimate_sd = true)
        f_int_mml = fit(spec_int_f; method = :mmle, estimate_mean = true, estimate_sd = true)
        @test qualify(f_pcm_mml).qualified
        @test qualify(f_int_mml).qualified
        # Nested model: adding `rater*item` (2 df) must have >= loglikelihood!
        @test f_int_mml.record.summary.loglikelihood >= f_pcm_mml.record.summary.loglikelihood - 1e-7
        cmp_mml = compare_models("PCM" => f_pcm_mml, "PCM+RxI" => f_int_mml; criterion = :aic)
        @test cmp_mml.likelihood_ratio !== nothing
        @test cmp_mml.likelihood_ratio.df == 2

        # JMLE + Layer-1/Layer-2 dispatches on MRCML frequentist fit
        f_int_jml = fit(spec_int_f; method = :jmle)
        @test qualify(f_int_jml).qualified
        @test isapprox(sum(pointwise_loglikelihood(f_int_jml)), loglikelihood(f_int_jml); atol = 1e-10)
        @test isapprox(sum(pointwise_loglikelihood(f_int_mml)), loglikelihood(f_int_mml); atol = 1e-10)
        c_res = contrast(f_int_mml; facet = :rater, left = "R1", right = "R2")
        @test isfinite(c_res.estimate) && isfinite(c_res.se)
        p_res = predict(f_int_mml; rows = 1:3, mode = :marginal_new_person)
        @test length(p_res.rows) == 3 && all(r -> isapprox(sum(r.probabilities), 1.0; atol = 1e-12), p_res.rows)

        # Short Bayesian NUTS fit + PSIS-LOO/WAIC compare_models + save/load + PortableHandoff
        psd_b = (person = 1.0, facets = (rater = 0.6, item = 0.7), step = 0.5)
        spec_pcm_b = mfrm_spec(tbl; person = :person, score = :score,
            facets = (rater = :rater, item = :item), steps = :item, category_levels = 0:2, prior_sd = psd_b)
        spec_int_b = mfrm_spec(tbl; person = :person, score = :score,
            facets = (rater = :rater, item = :item), steps = :item, category_levels = 0:2,
            interactions = ((:rater, :item),),
            prior_sd = merge(psd_b, (; interactions = (rater_item = 0.4,))))

        # Orthogonalized `fit(mrcml_target; method = :mmle | :jmle)` matches prior-free `MRCMLSpec` to <= 1e-12!
        f_int_b_as_mml = fit(spec_int_b; method = :mmle, estimate_mean = true, estimate_sd = true)
        f_int_b_as_jml = fit(spec_int_b; method = :jmle)
        @test abs(loglikelihood(f_int_b_as_mml) - loglikelihood(f_int_mml)) <= 1e-12
        @test abs(loglikelihood(f_int_b_as_jml) - loglikelihood(f_int_jml)) <= 1e-12

        # This comparison checks reporting and restoration; both fits still use real NUTS.
        pr_smoke = get(ENV, "BAYESIANMGMFRM_PR_SMOKE", "false") == "true"
        controls = pr_smoke ? (; chains=2, warmup=25, ndraws=32) : (; chains=2, warmup=150, ndraws=200)
        fit_pcm_b = fit(spec_pcm_b; controls..., seed = 42)
        fit_int_b = fit(spec_int_b; controls..., seed = 43)

        cmp_loo = compare_models("PCM" => fit_pcm_b, "PCM+RxI" => fit_int_b; criterion = :psis_loo)
        @test length(cmp_loo.rows) == 2
        @test criteria(fit_int_b).waic.elpd_waic isa Float64
        @test contrast(fit_int_b; left = "rater[\"R1\"]", right = "rater[\"R2\"]").result.mean isa Float64
        @test predictive_probabilities(fit_int_b; rows = 1:4).mean isa Matrix{Float64}
        @test predictive_check(fit_int_b; ndraws = 40, seed = 91).schema == BayesianMGMFRM.AdditiveFacets.PPC_SCHEMA

        mktempdir() do tmp
            f_path = joinpath(tmp, "mrcml_fit.jls")
            save_fit(f_path, fit_int_b)
            restored = load_fit(f_path)
            @test restored.record.content_hash == fit_int_b.record.content_hash

            rep = fit_report(fit_int_b; parameters = ["rater[\"R1\"]", "interaction[rater,item][\"R1\",\"I1\"]"], include_draws = true)
            rcpt = save_report(joinpath(tmp, "mrcml_rep.json"), rep; return_receipt = true)
            rep_loaded = load_report(rcpt.path; expected_sha256 = rcpt.sha256)
            @test rep_loaded.target_identity == rep.target_identity

            hoff_obj = BayesianMGMFRM.PortableHandoff.export_handoff(fit_int_b; include_log_lik = true, include_log_prior = true)
            hoff = save_report(joinpath(tmp, "handoff.json"), hoff_obj; return_receipt = true)
            h_loaded = load_report(hoff.path; expected_sha256 = hoff.sha256)
            @test size(h_loaded.fit.record.run.draws) == (controls.chains * controls.ndraws, length(parameter_names(fit_int_b; scale = :model)))
            @test isapprox(psis_loo(h_loaded).elpd_loo, psis_loo(fit_int_b).elpd_loo; atol = 1e-10)
        end
    end

    @testset "6. Category-scale fidelity, exact linear-subspace LRT nesting & B-reversal extreme invariance" begin
        rng = MersenneTwister(202611201)
        np, ni = 24, 3
        people = repeat(1:np, inner = ni)
        items = repeat(1:ni, np)
        theta_true = randn(rng, np)
        shifts = [0.0, -0.65, 0.65]
        scores0 = map(eachindex(items)) do r
            eta = theta_true[people[r]] + shifts[items[r]]
            w = exp.((0:2) .* eta)
            u = rand(rng) * sum(w)
            u < w[1] ? 0 : (u < w[1] + w[2] ? 1 : 2)
        end
        # Ensure both all-0 and all-2 extreme persons exist deterministically
        scores0[1:3] .= 0
        scores0[4:6] .= 2
        tbl0 = (; person = people, item = items, score = scores0)
        tbl_rev = (; person = people, item = items, score = 2 .- scores0)
        tbl_neg = (; person = people, item = items, score = scores0 .- 1)

        mk_custom(t, cols; labels = 0:2, backwards = false) = begin
            cats = backwards ? [2.0, 1.0, 0.0] : [0.0, 1.0, 2.0]
            A = zeros(Float64, ni, 3, length(cols))
            for (j, ic) in enumerate(cols)
                A[ic, :, j] .= cats
            end
            _MRCML_TEST.custom_spec(t; person = :person, score = :score, facets = (item = :item,),
                category_levels = labels, A = A, B = repeat(reshape(cats, 1, :), ni, 1), item_index = t.item)
        end

        s1 = mk_custom(tbl0, [1])
        s2 = mk_custom(tbl0, [2])
        s23 = mk_custom(tbl0, [2, 3])
        f1 = fit(s1; method = :mmle)
        f2 = fit(s2; method = :mmle)
        f23 = fit(s23; method = :mmle)

        # (A) 0:2 and negative-offset -1:1 category-scale prediction fidelity
        for mode in (:plugin, :marginal_new_person)
            pr = predict(f23; mode).rows
            @test all(r -> r.categories == [0, 1, 2], pr)
            @test all(i -> pr[i].observed_score == tbl0.score[i], eachindex(pr))
            @test maximum(abs(r.expected_score - dot([0, 1, 2], r.probabilities)) for r in pr) <= 1e-14
        end
        f_neg = fit(mk_custom(tbl_neg, [2, 3]; labels = -1:1); method = :mmle)
        for mode in (:plugin, :marginal_new_person)
            pr_neg = predict(f_neg; mode).rows
            @test all(r -> r.categories == [-1, 0, 1], pr_neg)
            @test all(i -> pr_neg[i].observed_score == tbl_neg.score[i], eachindex(pr_neg))
            @test maximum(abs(r.expected_score - dot([-1, 0, 1], r.probabilities)) for r in pr_neg) <= 1e-14
        end

        # Classical mfrm_spec on 0:2 also preserves exact 0:2 scale & binds identically with FacetSpec and MRCML!
        tbl_mf = (; person = ["P$p" for p in people], rater = repeat(["R1", "R2"], inner = 1)[mod1.(eachindex(people), 2)],
                    item = ["I$i" for i in items], score = scores0)
        d_mf = FacetData(tbl_mf; person = :person, rater = :rater, item = :item, score = :score, category_levels = 0:2)
        f_fspec = fit(mfrm_spec(d_mf; thresholds = :rating_scale); method = :mmle)
        f_mspec = fit(mfrm_spec(tbl_mf; person = :person, score = :score, facets = (rater = :rater, item = :item),
            steps = :global, category_levels = 0:2, prior = :none); method = :mmle)
        f_mr_int = fit(mfrm_spec(tbl_mf; person = :person, score = :score, facets = (rater = :rater, item = :item),
            steps = :global, category_levels = 0:2, interactions = ((:rater, :item),), prior = :none); method = :mmle)
        @test predict(f_mspec; mode = :plugin).rows[1].categories == [0, 1, 2]
        @test [r.category for r in f_mspec.record.category_usage] == [0, 1, 2]
        cmp_cross = compare_models("RSM_FacetSpec" => f_fspec, "RSM+RxI_MRCML" => f_mr_int; criterion = :aic)
        @test cmp_cross.nested == true && cmp_cross.likelihood_ratio !== nothing
        @test isapprox(f_fspec.record.summary.deviance, f_mspec.record.summary.deviance; atol = 1e-10)

        # (B) Exact algebraic subspace nesting vs. non-nested refusal of LRT p-values
        cmp_nonnested = compare_models("item1" => f1, "item23" => f23; criterion = :aic)
        @test cmp_nonnested.nested == false
        @test cmp_nonnested.nesting_status == :non_nested_intercept_subspace
        @test cmp_nonnested.likelihood_ratio === nothing

        cmp_nested = compare_models("item2" => f2, "item23" => f23; criterion = :aic)
        @test cmp_nested.nested == true
        @test cmp_nested.likelihood_ratio !== nothing
        @test cmp_nested.likelihood_ratio.df == 1
        @test 0.0 <= cmp_nested.likelihood_ratio.asymptotic_chisq_pvalue <= 1.0

        # Free SD in smaller-df model vs fixed SD in larger-df model is NOT nested
        f2_freesd = fit(s2; method = :mmle, estimate_sd = true)
        f123_fixsd = fit(mk_custom(tbl0, [1, 2, 3]); method = :mmle, estimate_sd = false)
        cmp_sd_mismatch = compare_models("item2+sd" => f2_freesd, "item123_fixsd" => f123_fixsd; criterion = :aic)
        @test cmp_sd_mismatch.nested == false
        @test cmp_sd_mismatch.nesting_status == :free_sd_not_nested_in_fixed_sd
        @test cmp_sd_mismatch.likelihood_ratio === nothing

        # (C) Reverse-scoring (0 <-> 2, B: [0,1,2] <-> [2,1,0]) preserves both interior AND +/-Inf extreme abilities!
        j_plain = fit(s23; method = :jmle)
        j_rev = fit(mk_custom(tbl_rev, [2, 3]; backwards = true); method = :jmle)
        ps_map = Dict(r.person => r.limit_estimate for r in j_plain.record.person_scores)
        rs_map = Dict(r.person => r.limit_estimate for r in j_rev.record.person_scores)
        for p in 1:np
            yp = tbl0.score[tbl0.person .== p]
            if all(==(0), yp)
                @test ps_map[p] == -Inf && rs_map[p] == -Inf
            elseif all(==(2), yp)
                @test ps_map[p] == Inf && rs_map[p] == Inf
            else
                @test isapprox(ps_map[p], rs_map[p]; atol = 1e-12)
            end
        end
        # Plug-in prediction on JMLE (including +/-Inf extreme persons!) satisfies exact E[2 - Y] = 2 - E[Y]
        pr_plain = predict(j_plain; mode = :plugin).rows
        pr_rev = predict(j_rev; mode = :plugin).rows
        @test maximum(abs((2.0 - pr_plain[i].expected_score) - pr_rev[i].expected_score) for i in eachindex(pr_plain)) <= 1e-12

        # Extreme adjustment (0.3) also preserves exact abilities under score + B reversal!
        j_plain_adj = fit(s23; method = :jmle, extreme_adjustment = 0.3)
        j_rev_adj = fit(mk_custom(tbl_rev, [2, 3]; backwards = true); method = :jmle, extreme_adjustment = 0.3)
        @test maximum(abs(j_plain_adj.record.person_scores[p].estimate - j_rev_adj.record.person_scores[p].estimate) for p in 1:np) <= 1e-10
    end
end

include("named_fixed_equating.jl")

include("joint_calibration.jl")
include("grouped_calibration_transfer.jl")

include("subset_mean_equating.jl")

include("wave_linking.jl")

include("fixed_interaction_cells.jl")

include("cr3_isometric_1d_remediation.jl")
