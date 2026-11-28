module FrequentistMFRMChecks
using BayesianMGMFRM
using BayesianMGMFRM.GlassBox
using BayesianMGMFRM.Legacy
using Test
using LinearAlgebra
using ForwardDiff
using Statistics
using Random

const B = BayesianMGMFRM
const FM = B.FrequentistMFRM

function make_4facet_dataset(; n_persons = 18)
    rng = MersenneTwister(20261118)
    th_true = collect(range(-1.4, 1.4; length = n_persons))
    r_true = [-0.55, -0.10, 0.25, 0.40]
    t_true = [-0.30, 0.30]
    c_true = [-0.45, 0.15, 0.30]
    steps_rsm = [-1.2, -0.3, 0.4, 1.1] # K = 5 categories (0..4), sum = 0

    persons = String[]; raters = String[]; tasks = String[]; crits = String[]; scores = Int[]
    for p in 1:n_persons, r in 1:4, t in 1:2, c in 1:3
        # Connected incomplete balanced design (drop ~25% deterministically)
        mod(p + r + t + c, 4) == 0 && continue
        eta = th_true[p] - r_true[r] - t_true[t] - c_true[c]
        # Shift steps slightly by criterion so PCM has genuine signal too
        st = steps_rsm .+ (c == 1 ? [-0.2, 0.1, 0.1, 0.0] : c == 2 ? [0.15, -0.05, -0.1, 0.0] : [0.0, 0.0, 0.0, 0.0])
        lps = [0.0; [k * eta - sum(st[1:k]) for k in 1:4]]
        m = maximum(lps)
        ps = exp.(lps .- m)
        ps ./= sum(ps)
        u = rand(rng)
        cdf = cumsum(ps)
        y = clamp(searchsortedfirst(cdf, u) - 1, 0, 4)
        push!(persons, "P$(lpad(p, 2, '0'))")
        push!(raters, "R$r")
        push!(tasks, "T$t")
        push!(crits, "C$c")
        push!(scores, y)
    end
    return (; Person = persons, Rater = raters, Task = tasks, Criterion = crits, Score = scores)
end

@testset "Frequentist 1D RSM/PCM JMLE & MMLE across 3-facet FacetSpec and F-facet mfrm_spec" begin
    tbl = make_4facet_dataset()

    # 1. Silent frequentist fallback rejected; explicit prior = :none AND Bayesian-prior F-facet mfrm_spec produce identical frequentist fits
    @test_throws ArgumentError mfrm_spec(tbl; person = :Person,
        facets = (Rater = :Rater, Task = :Task, Criterion = :Criterion),
        score = :Score, steps = :global, category_levels = 0:4)
    @test_throws ArgumentError mfrm_spec(tbl; person = :Person,
        facets = (Rater = :Rater, Task = :Task, Criterion = :Criterion),
        score = :Score, steps = :global, category_levels = 0:4,
        prior = :none,
        prior_sd = (person = 1.0, facets = (Rater = 0.8, Task = 0.8, Criterion = 0.8), step = 1.0))
    spec_noprior = mfrm_spec(tbl; person = :Person,
        facets = (Rater = :Rater, Task = :Task, Criterion = :Criterion),
        score = :Score, steps = :global, category_levels = 0:4, prior = :none)
    @test spec_noprior isa FM.Spec
    @test validate_design(spec_noprior).identified
    @test design_summary(spec_noprior).n_persons == 18
    @test contract(spec_noprior).supported_methods == (:jmle, :mmle)
    @test_throws ArgumentError fit(spec_noprior)
    @test_throws ArgumentError prior_draw(spec_noprior)

    spec_withprior = mfrm_spec(tbl; person = :Person,
        facets = (Rater = :Rater, Task = :Task, Criterion = :Criterion),
        score = :Score, steps = :global, category_levels = 0:4,
        prior_sd = (person = 1.0, facets = (Rater = 0.8, Task = 0.8, Criterion = 0.8), step = 1.0))
    @test spec_withprior isa B.AdditiveFacets.Target
    @test_throws UndefKeywordError fit(spec_withprior) # preserves Bayesian keyword contract!

    # 2. Analytical gradient & exact Schur-complement Hessian verification vs ForwardDiff
    prob_j = FM.compile_problem(spec_noprior; method = :jmle)
    lay_j = FM.build_layout(prob_j)
    u_test = 0.15 .* sin.(1:lay_j.n_free)
    g_ana = zeros(lay_j.n_free)
    v_ana = FM.jmle_nll_and_grad!(g_ana, u_test, prob_j, lay_j)
    g_fd = ForwardDiff.gradient(z -> FM.jmle_nll_and_grad!(nothing, z, prob_j, lay_j), u_test)
    @test maximum(abs, g_ana .- g_fd) <= 1e-13

    prob_m = FM.compile_problem(spec_noprior; method = :mmle)
    lay_m = FM.build_layout(prob_m; estimate_mean = true, estimate_sd = true)
    q_m = FM.gauss_hermite_normal(21; sd = 1.0)
    # Check Golub-Welsch moments: E[1]=1, E[Z]=0, E[Z^2]=1, E[Z^4]=3
    @test sum(q_m.weights) ≈ 1.0 atol = 1e-13
    @test abs(sum(q_m.weights .* q_m.std_nodes)) <= 1e-13
    @test sum(q_m.weights .* (q_m.std_nodes .^ 2)) ≈ 1.0 atol = 1e-14
    @test sum(q_m.weights .* (q_m.std_nodes .^ 4)) ≈ 3.0 atol = 1e-13

    u_mtest = 0.12 .* cos.(1:lay_m.n_free)
    gm_ana = zeros(lay_m.n_free)
    vm_ana = FM.mmle_nll_and_grad!(gm_ana, u_mtest, prob_m, lay_m, q_m)
    gm_fd = ForwardDiff.gradient(z -> FM.mmle_nll_and_grad!(nothing, z, prob_m, lay_m, q_m), u_mtest)
    @test maximum(abs, gm_ana .- gm_fd) <= 1e-12

    # 3. Fit JMLE & verify Schur-complement SE == dense ForwardDiff Hessian SE to <= 1e-13!
    f_jml_1 = fit(spec_noprior; method = :jmle)
    f_jml_2 = fit(spec_withprior; method = :jmle)
    @test qualify(f_jml_1).qualified
    @test loglikelihood(f_jml_1) ≈ loglikelihood(f_jml_2) atol = 1e-12
    @test sum(pointwise_loglikelihood(f_jml_1)) ≈ loglikelihood(f_jml_1) atol = 1e-12
    @test f_jml_1.record.summary.max_abs_gradient <= 1e-10

    H_dense = Symmetric(ForwardDiff.hessian(z -> FM.jmle_nll_and_grad!(nothing, z, prob_j, lay_j), f_jml_1.record.u_free))
    cov_dense_full = Matrix(lay_j.J_mat * inv(cholesky(H_dense)) * transpose(lay_j.J_mat))
    se_dense = [sqrt(max(cov_dense_full[i, i], 0.0)) for i in 1:lay_j.n_full_structural]
    @test maximum(abs, f_jml_1.record.full_se .- se_dense) <= 1e-12

    # Gauge invariance: :sum_to_zero vs :reference_first give identical loglikelihood, infit/outfit, and contrasts!
    f_jml_ref = fit(spec_noprior; method = :jmle, centering = :reference_first)
    @test loglikelihood(f_jml_ref) ≈ loglikelihood(f_jml_1) atol = 1e-11
    c_sz = contrast(f_jml_1; facet = :Rater, left = "R1", right = "R4")
    c_rf = contrast(f_jml_ref; facet = :Rater, left = "R1", right = "R4")
    @test c_sz.estimate ≈ c_rf.estimate atol = 1e-10
    @test c_sz.se ≈ c_rf.se atol = 1e-10

    # 4. Fit MMLE (fixed SD, ConQuest free SD, full N(mu, sigma^2), and rectangular quadrature) + PCM comparison
    f_mml_rsm = fit(spec_noprior; method = :mmle, quad_points = 31, population_sd = 1.0)
    @test qualify(f_mml_rsm).qualified
    @test sum(pointwise_loglikelihood(f_mml_rsm)) ≈ loglikelihood(f_mml_rsm) atol = 1e-12

    spec_pcm = mfrm_spec(tbl; person = :Person,
        facets = (Rater = :Rater, Task = :Task, Criterion = :Criterion),
        score = :Score, steps = :Criterion, category_levels = 0:4, prior = :none)
    f_mml_pcm = fit(spec_pcm; method = :mmle, quad_points = 31, population_sd = 1.0)
    @test qualify(f_mml_pcm).qualified
    @test loglikelihood(f_mml_pcm) >= loglikelihood(f_mml_rsm) - 1e-8

    cmp_ic = compare_models("RSM" => f_mml_rsm, "PCM" => f_mml_pcm; criterion = :aic)
    @test cmp_ic.schema == FM.COMPARISON_SCHEMA
    @test length(cmp_ic.rows) == 2 && cmp_ic.rows[1].delta_criterion == 0.0
    @test cmp_ic.likelihood_ratio !== nothing && cmp_ic.likelihood_ratio.df == 6
    @test_throws ArgumentError compare_models("J1" => f_jml_1, "J2" => f_jml_ref)
    @test_throws ArgumentError compare_models("RSM" => f_mml_rsm, "PCM" => f_mml_pcm; criterion = :waic)

    f_mml_free = fit(spec_noprior; method = :mmle, quad_points = 31, estimate_sd = true, estimate_mean = true)
    @test qualify(f_mml_free).qualified
    @test loglikelihood(f_mml_free) >= loglikelihood(f_mml_rsm) - 1e-8
    @test isfinite(f_mml_free.record.summary.population_sd) && f_mml_free.record.summary.population_sd > 0

    f_mml_rect = fit(spec_noprior; method = :mmle, quadrature = :rectangular, quad_points = 41, theta_lim = 5.0)
    @test qualify(f_mml_rect).qualified
    @test sum(pointwise_loglikelihood(f_mml_rect)) ≈ loglikelihood(f_mml_rect) atol = 1e-12

    # 5. Standard 3-facet FacetSpec (with and without anchors) + ExplanatoryTarget pure-facet compatibility
    d3 = FacetData((; person = tbl.Person, rater = tbl.Rater, item = tbl.Criterion, score = tbl.Score);
        person = :person, rater = :rater, item = :item, score = :score, category_levels = 0:4)
    sp3_rsm = mfrm_spec(d3; thresholds = :rating_scale)
    sp3_pcm = mfrm_spec(d3; thresholds = :partial_credit)
    f3_jml = fit(sp3_rsm; method = :jmle)
    f3_mml = fit(sp3_pcm; method = :mmle, quad_points = 25)
    @test qualify(f3_jml).qualified && qualify(f3_mml).qualified

    sp3_anc = mfrm_spec(d3; thresholds = :rating_scale,
        anchors = [(; block = :rater, level = "R1", value = -0.5), (; block = :rater, level = "R2", value = 0.0)])
    f3_anc = fit(sp3_anc; method = :mmle, quad_points = 21)
    f3_anc_kw = fit(sp3_rsm; method = :mmle, quad_points = 21, anchors = (rater = Dict("R1" => -0.5, "R2" => 0.0),))
    @test loglikelihood(f3_anc) ≈ loglikelihood(f3_anc_kw) atol = 1e-12
    rmeas_anc = facet_summary(f3_anc; facet = :rater).rows
    @test rmeas_anc[1].fixed && rmeas_anc[1].estimate == -0.5 && ismissing(rmeas_anc[1].se)
    @test !rmeas_anc[3].fixed && !ismissing(rmeas_anc[3].se)

    # Unsupported model axes rejected cleanly
    sp_2d = mfrm_spec(d3; dimensions = 2, q_matrix = [1 0; 1 0; 0 1])
    @test_throws ArgumentError fit(sp_2d; method = :mmle)
    sp_gpcm = mfrm_spec(d3; family = :gmfrm, thresholds = :partial_credit, discrimination = :item)
    @test_throws ArgumentError fit(sp_gpcm; method = :jmle)

    # 6. Extreme-score person exact limit (unadjusted vs interior subproblem) & FACETS 0.3 adjustment
    scores_ext = copy(tbl.Score)
    for i in eachindex(scores_ext)
        tbl.Person[i] == "P01" && (scores_ext[i] = 0)
        tbl.Person[i] == "P18" && (scores_ext[i] = 4)
    end
    tbl_ext = merge(tbl, (; Score = scores_ext))
    sp_ext = mfrm_spec(tbl_ext; person = :Person,
        facets = (Rater = :Rater, Task = :Task, Criterion = :Criterion),
        score = :Score, steps = :global, category_levels = 0:4, prior = :none)
    f_ext_unadj = fit(sp_ext; method = :jmle, extreme_adjustment = 0.0)
    @test qualify(f_ext_unadj).qualified

    keep_int = [i for i in eachindex(tbl_ext.Person) if !(tbl_ext.Person[i] in ("P01", "P18"))]
    tbl_int = (; (k => getproperty(tbl_ext, k)[keep_int] for k in keys(tbl_ext))...)
    sp_int = mfrm_spec(tbl_int; person = :Person,
        facets = (Rater = :Rater, Task = :Task, Criterion = :Criterion),
        score = :Score, steps = :global, category_levels = 0:4, prior = :none)
    f_int_only = fit(sp_int; method = :jmle)
    # Theorem check: unadjusted JMLE with +/-Inf extreme persons equals exact interior supremum!
    @test loglikelihood(f_ext_unadj) ≈ loglikelihood(f_int_only) atol = 1e-10
    @test [r.estimate for r in f_ext_unadj.record.facet_measures] ≈ [r.estimate for r in f_int_only.record.facet_measures] atol = 1e-10
    ps_ext = facet_summary(f_ext_unadj; facet = :person).rows
    @test !ps_ext[1].finite_mle && ismissing(ps_ext[1].estimate) && !ismissing(ps_ext[1].wle)
    @test !ps_ext[end].finite_mle && ismissing(ps_ext[end].estimate) && !ismissing(ps_ext[end].wle)

    f_ext_adj = fit(sp_ext; method = :jmle, extreme_adjustment = 0.3)
    @test qualify(f_ext_adj).qualified
    @test sum(pointwise_loglikelihood(f_ext_adj)) ≈ loglikelihood(f_ext_adj) atol = 1e-12
    ps_adj = facet_summary(f_ext_adj; facet = :person).rows
    @test isfinite(ps_adj[1].estimate) && isfinite(ps_adj[end].estimate)

    # 7. Persistence, Reporting, Prediction, Bayesian-verb refusals & CairoMakie plots
    rep = fit_report(f_mml_rsm)
    @test rep.summary.is_bayesian_posterior === false
    @test length(reliability(f_mml_rsm)) == 4
    @test length(category_summary(f_mml_rsm).categories) == 5
    pr_plug = predict(f_mml_rsm; rows = [1, 2], mode = :plugin)
    pr_marg = predict(f_mml_rsm; rows = [1, 2], mode = :marginal_new_person)
    @test sum(pr_plug.rows[1].probabilities) ≈ 1.0 atol = 1e-14
    @test sum(pr_marg.rows[1].probabilities) ≈ 1.0 atol = 1e-14

    for fn in (posterior_summary, posterior_mcse, waic, psis_loo, logprior, logposterior)
        @test_throws ArgumentError fn(f_mml_rsm)
    end

    mktempdir() do dir
        p_fit = joinpath(dir, "mml.jls")
        save_fit(p_fit, f_mml_rsm)
        loaded_f = load_fit(p_fit)
        @test loglikelihood(loaded_f) == loglikelihood(f_mml_rsm)

        rec_r = save_report(joinpath(dir, "mml.json"), f_mml_rsm; return_receipt = true)
        loaded_r = load_report(rec_r.path; expected_sha256 = rec_r.sha256)
        @test loaded_r.summary.loglikelihood ≈ loglikelihood(f_mml_rsm) atol = 1e-10

        rec_c = save_report(joinpath(dir, "cmp.json"), cmp_ic; return_receipt = true)
        loaded_c = load_report(rec_c.path; expected_sha256 = rec_c.sha256)
        @test length(loaded_c.rows) == 2
    end

    if Base.get_extension(B, :BayesianMGMFRMCairoMakieExt) !== nothing
        @test B.plot(f_mml_rsm; kind = :posterior, annotation_io = IOBuffer()) !== nothing
        @test B.plot(f_mml_rsm; kind = :wright, annotation_io = IOBuffer()) !== nothing
        @test B.plot(f_mml_rsm; kind = :pathway, annotation_io = IOBuffer()) !== nothing
        @test B.plot(cmp_ic; kind = :comparison, annotation_io = IOBuffer()) !== nothing
    end

    # 8. Structured MRCML frequentist parity (prior = :default MMLE & JMLE vs prior = :none),
    #    low-df Wilson-Hilferty ZSTD (WHEXACT = Yes), FACETS Table 7 conventions, and Bayesian boundary
    begin
        # 8a. Exact Wilson-Hilferty ZSTD parity across all 3 engines (manual normal df & low df < 1)
        z_manual_exact = 3.0 * (cbrt(0.975) - 1.0) / sqrt(2.0 / 20.0) + sqrt(2.0 / 20.0) / 3.0
        z_manual_no = 3.0 * (cbrt(0.975) - 1.0) / sqrt(2.0 / 20.0)
        z_lowdf_exact = 3.0 * (cbrt(1.0) - 1.0) / sqrt(2.0 / 0.25) + sqrt(2.0 / 0.25) / 3.0 # sqrt(8)/3 ≈ 0.94280904
        @test z_manual_exact ≈ 0.025684200526727263 atol = 1e-12
        @test z_lowdf_exact ≈ 0.9428090415820634 atol = 1e-12

        @test FM._wilson_hilferty_zstd(0.975, 20.0; cap = 9.9, whexact = true) ≈ z_manual_exact atol = 1e-12
        @test FM._wilson_hilferty_zstd(0.975, 20.0; cap = 9.9, whexact = false) ≈ z_manual_no atol = 1e-12
        @test FM._wilson_hilferty_zstd(1.0, 0.25; cap = 9.9, whexact = true) ≈ z_lowdf_exact atol = 1e-12
        @test B._facets_wilson_hilferty_zstd(0.975, 20.0, 9.9) ≈ z_manual_exact atol = 1e-12
        @test B._facets_wilson_hilferty_zstd(1.0, 0.25, 9.9) ≈ z_lowdf_exact atol = 1e-12
        @test B.ValidationSuite._wilson_hilferty_z(0.975, 2.0 / 20.0; cap = 9.9) ≈ z_manual_exact atol = 1e-12
        @test B.ValidationSuite._wilson_hilferty_z(1.0, 2.0 / 0.25; cap = 9.9) ≈ z_lowdf_exact atol = 1e-12

        # 8b. 12x3x2 (72-rating) deterministic dataset: standard MRCML (`prior = :default`) vs `prior = :none`
        rng72 = MersenneTwister(20261127)
        th12 = collect(range(-1.3, 1.3; length = 12))
        it3 = [-0.5, 0.1, 0.4]
        rt2 = [-0.35, 0.35]
        st3 = [-0.9, 0.0, 0.9]
        p72 = String[]; i72 = String[]; r72 = String[]; y72 = Int[]; feat_i = Float64[]
        for p in 1:12, ii in 1:3, rr in 1:2
            eta = th12[p] - it3[ii] - rt2[rr]
            lps = [0.0; [k * eta - sum(st3[1:k]) for k in 1:3]]
            m_lp = maximum(lps)
            ps = exp.(lps .- m_lp); ps ./= sum(ps)
            y = clamp(searchsortedfirst(cumsum(ps), rand(rng72)), 1, 4)
            push!(p72, "P$(lpad(p, 2, '0'))")
            push!(i72, "I$ii")
            push!(r72, "R$rr")
            push!(y72, y)
            push!(feat_i, Float64(ii - 2))
        end
        tbl72 = (; person = p72, item = i72, rater = r72, score = y72, feat = feat_i)

        sp_none = mfrm_spec(tbl72; person = :person, facets = (item = :item, rater = :rater),
            score = :score, steps = :global, category_levels = 1:4, prior = :none)
        sp_def_free_mu = mfrm_spec(tbl72; person = :person, facets = (item = :item, rater = :rater),
            score = :score, steps = :global, category_levels = 1:4, prior = :default)
        sp_def_zero_mu = mfrm_spec(tbl72; person = :person, facets = (item = :item, rater = :rater),
            score = :score, steps = :global, category_levels = 1:4,
            prior_sd = (person = 1.0, facets = (item = 1.0, rater = 1.0), step = 1.0))

        # MMLE parity (`prior = :default` has free `population_mean`, matching `prior = :none` with `estimate_mean = true`;
        # `location_identification = :zero_mean_population` matches default `prior = :none` `estimate_mean = false`!)
        fit_m_none_mu = fit(sp_none; method = :mmle, estimate_mean = true, gtol = 1e-11)
        fit_m_def_mu = fit(sp_def_free_mu; method = :mmle, gtol = 1e-11)
        fit_m_none_0 = fit(sp_none; method = :mmle, gtol = 1e-11)
        fit_m_def_0 = fit(sp_def_zero_mu; method = :mmle, gtol = 1e-11)

        # JMLE parity (`location_identification = :zero_mean_population` vs `prior = :none`)
        fit_j_none = fit(sp_none; method = :jmle, gtol = 1e-11)
        fit_j_def = fit(sp_def_zero_mu; method = :jmle, gtol = 1e-11)

        for (fa, fb) in ((fit_m_none_mu, fit_m_def_mu), (fit_m_none_0, fit_m_def_0), (fit_j_none, fit_j_def))
            @test loglikelihood(fa) ≈ loglikelihood(fb) atol = 1e-9
            ra = reliability(fa)
            rb = reliability(fb)
            @test length(ra) == 3 && length(rb) == 3
            @test [r.facet for r in rb] == [:person, :item, :rater]
            for k in 1:3
                @test rb[k].status === :available_descriptive
                @test rb[k].variance_definition === :sample
                @test ra[k].sd ≈ rb[k].sd atol = 1e-7
                @test ra[k].rmse ≈ rb[k].rmse atol = 1e-7
                @test ra[k].separation ≈ rb[k].separation atol = 1e-6
                @test ra[k].strata ≈ rb[k].strata atol = 1e-6
                @test ra[k].reliability ≈ rb[k].reliability atol = 1e-6
                @test rb[k].strata ≈ (4.0 * rb[k].separation + 1.0) / 3.0 atol = 1e-12
                @test ra[k].population_separation ≈ rb[k].population_separation atol = 1e-6
                @test ra[k].real_separation ≈ rb[k].real_separation atol = 1e-6
                if k >= 2
                    @test !ismissing(rb[k].facets_conditional_separation)
                    @test ra[k].facets_conditional_separation ≈ rb[k].facets_conditional_separation atol = 1e-6
                end
            end

            for fn in (:person, :item, :rater)
                dsa = diagnostics(fa; kind = :fit_statistics, by = fn)
                dsb = diagnostics(fb; kind = :fit_statistics, by = fn)
                @test length(dsa.rows) == length(dsb.rows)
                @test [r.infit for r in dsa.rows] ≈ [r.infit for r in dsb.rows] atol = 1e-7
                @test [r.outfit for r in dsa.rows] ≈ [r.outfit for r in dsb.rows] atol = 1e-7
                @test [r.infit_zstd for r in dsa.rows] ≈ [r.infit_zstd for r in dsb.rows] atol = 1e-6
                @test [r.outfit_zstd for r in dsa.rows] ≈ [r.outfit_zstd for r in dsb.rows] atol = 1e-6
                @test [r.df_infit for r in dsa.rows] ≈ [r.df_infit for r in dsb.rows] atol = 1e-6
                @test [r.df_outfit for r in dsa.rows] ≈ [r.df_outfit for r in dsb.rows] atol = 1e-6
                fs_b = facet_summary(fb; facet = fn)
                @test length(fs_b.rows) == length(dsa.rows)
            end
        end

        # FACETS Table 7 explicit slices via `reliability(fit; variance, se, nonextreme_only)`
        rel_pop = reliability(fit_m_def_mu; variance = :population)
        @test rel_pop[2].variance_definition === :population
        @test rel_pop[2].separation ≈ reliability(fit_m_def_mu)[2].population_separation atol = 1e-12
        rel_cond = reliability(fit_m_def_mu; se = :conditional)
        @test rel_cond[2].se_definition === :model_conditional
        @test rel_cond[2].separation ≈ reliability(fit_m_def_mu)[2].facets_conditional_separation atol = 1e-12
        rel_real = reliability(fit_m_def_mu; se = :real)
        @test rel_real[2].separation ≈ reliability(fit_m_def_mu)[2].real_separation atol = 1e-12

        rel_ext_withheld = reliability(f_ext_unadj)
        @test rel_ext_withheld[1].status === :withheld_incomplete_or_extreme_levels
        rel_ext_noext = reliability(f_ext_unadj; nonextreme_only = true)
        @test rel_ext_noext[1].status === :available_descriptive && rel_ext_noext[1].extreme_policy === :excluded_extremes

        # LLTM restriction marks restricted facet reliability as `:not_applicable_lltm_subspace` while keeping level Infit/ZSTD
        sp_lltm = mfrm_spec(tbl72; person = :person, facets = (item = :item, rater = :rater),
            score = :score, steps = :global, category_levels = 1:4,
            lltm = (item = (features = [:feat],),), prior = :none)
        fit_lltm = fit(sp_lltm; method = :mmle)
        rel_lltm = reliability(fit_lltm)
        @test length(rel_lltm) == 3
        @test rel_lltm[1].status === :available_descriptive # person
        @test rel_lltm[2].facet === :item && rel_lltm[2].status === :not_applicable_lltm_subspace && ismissing(rel_lltm[2].separation)
        @test rel_lltm[3].facet === :rater && rel_lltm[3].status === :available_descriptive
        @test all(r -> !ismissing(r.infit_zstd), diagnostics(fit_lltm; kind = :fit_statistics, by = :item).rows)

        # Exchange Schema v1.0 parity between `FrequentistMFRM.Spec` and `MRCMLTarget`
        # (including observation weights = 1/3 AND person_score_method = :wle!)
        w72 = Float64[isodd(idx) ? 1.0 : 3.0 for idx in 1:length(y72)]
        fit_mw_none = fit(sp_none; method = :mmle, weights = w72, zstd_cap = 9.9, gtol = 1e-11)
        fit_mw_def = fit(sp_def_zero_mu; method = :mmle, weights = w72, zstd_cap = 9.9, gtol = 1e-11)
        mktempdir() do exdir
            B.ValidationSuite.write_exchange_run(joinpath(exdir, "none"), fit_m_none_0;
                case_id = "c72", input_sha256 = "00", estimator = "MMLE", model = "RSM")
            B.ValidationSuite.write_exchange_run(joinpath(exdir, "def"), fit_m_def_0;
                case_id = "c72", input_sha256 = "00", estimator = "MMLE", model = "RSM")
            ex_none = B.ValidationSuite.read_exchange_run(joinpath(exdir, "none"))
            ex_def = B.ValidationSuite.read_exchange_run(joinpath(exdir, "def"))
            @test ex_none.meta.extra.zstd_whexact == true && ex_none.meta.extra.zstd_cap == 9.9
            @test [r.infit_z for r in ex_none.facets] ≈ [r.infit_z for r in ex_def.facets] atol = 1e-6
            @test [r.outfit_z for r in ex_none.persons] ≈ [r.outfit_z for r in ex_def.persons] atol = 1e-6

            # Weighted MMLE CSV matches fit object ZSTD AND agrees across simple/structured specs
            B.ValidationSuite.write_exchange_run(joinpath(exdir, "w_none"), fit_mw_none;
                case_id = "c72w", input_sha256 = "00", estimator = "MMLE", model = "RSM")
            B.ValidationSuite.write_exchange_run(joinpath(exdir, "w_def"), fit_mw_def;
                case_id = "c72w", input_sha256 = "00", estimator = "MMLE", model = "RSM")
            ex_wn = B.ValidationSuite.read_exchange_run(joinpath(exdir, "w_none"))
            ex_wd = B.ValidationSuite.read_exchange_run(joinpath(exdir, "w_def"))
            fit_w_f_z = [r.infit_zstd for r in fit_mw_def.record.facet_measures if r.facet in (:item, :rater)]
            @test [r.infit_z for r in ex_wd.facets] ≈ fit_w_f_z atol = 1e-12
            @test [r.infit_z for r in ex_wn.facets] ≈ [r.infit_z for r in ex_wd.facets] atol = 1e-6
            @test [r.infit_z for r in ex_wn.persons] ≈ [r.infit_z for r in ex_wd.persons] atol = 1e-6

            # Alternate `person_score_method = :wle` recomputes MNSQ/ZSTD at WLE on BOTH paths (weighted & unweighted)
            B.ValidationSuite.write_exchange_run(joinpath(exdir, "wle_none"), fit_mw_none;
                case_id = "c72wle", input_sha256 = "00", estimator = "MMLE", model = "RSM", person_score_method = :wle)
            B.ValidationSuite.write_exchange_run(joinpath(exdir, "wle_def"), fit_mw_def;
                case_id = "c72wle", input_sha256 = "00", estimator = "MMLE", model = "RSM", person_score_method = :wle)
            ex_wle_n = B.ValidationSuite.read_exchange_run(joinpath(exdir, "wle_none"))
            ex_wle_d = B.ValidationSuite.read_exchange_run(joinpath(exdir, "wle_def"))
            @test [r.infit_z for r in ex_wle_n.facets] ≈ [r.infit_z for r in ex_wle_d.facets] atol = 1e-6
            @test [r.infit_z for r in ex_wle_n.persons] ≈ [r.infit_z for r in ex_wle_d.persons] atol = 1e-6
            @test !([r.infit_z for r in ex_wle_n.persons] ≈ [r.infit_z for r in ex_wn.persons])
            @test !([r.infit_z for r in ex_wle_n.facets] ≈ [r.infit_z for r in ex_wn.facets])
        end

        # High-1: Extreme-adjusted (`extreme_adjustment = 0.3`) structured JMLE person `conditional_se` & separation parity
        y72_ext = copy(y72)
        for idx in eachindex(y72_ext)
            p72[idx] == "P01" && (y72_ext[idx] = 1)
            p72[idx] == "P12" && (y72_ext[idx] = 4)
        end
        tbl72_ext = merge(tbl72, (; score = y72_ext))
        sp72_ext_none = mfrm_spec(tbl72_ext; person = :person, facets = (item = :item, rater = :rater),
            score = :score, steps = :global, category_levels = 1:4, prior = :none)
        sp72_ext_def = mfrm_spec(tbl72_ext; person = :person, facets = (item = :item, rater = :rater),
            score = :score, steps = :global, category_levels = 1:4,
            prior_sd = (person = 1.0, facets = (item = 1.0, rater = 1.0), step = 1.0))
        fj_ext_none = fit(sp72_ext_none; method = :jmle, extreme_adjustment = 0.3, gtol = 1e-11)
        fj_ext_def = fit(sp72_ext_def; method = :jmle, extreme_adjustment = 0.3, gtol = 1e-11)
        @test loglikelihood(fj_ext_none) ≈ loglikelihood(fj_ext_def) atol = 1e-9
        @test fj_ext_none.record.overall_fit.deviance ≈ fj_ext_def.record.overall_fit.deviance atol = 1e-9
        @test sum(pointwise_loglikelihood(fj_ext_none)) ≈ loglikelihood(fj_ext_none) atol = 1e-11
        @test sum(pointwise_loglikelihood(fj_ext_def)) ≈ loglikelihood(fj_ext_def) atol = 1e-11
        ps_en = facet_summary(fj_ext_none; facet = :person).rows
        ps_ed = facet_summary(fj_ext_def; facet = :person).rows
        @test [r.estimate for r in ps_en] ≈ [r.estimate for r in ps_ed] atol = 1e-7
        @test [r.se for r in ps_en] ≈ [r.se for r in ps_ed] atol = 1e-7
        @test [r.conditional_se for r in ps_en] ≈ [r.conditional_se for r in ps_ed] atol = 1e-7
        @test [r.real_se for r in ps_en] ≈ [r.real_se for r in ps_ed] atol = 1e-7
        rel_en = reliability(fj_ext_none)
        rel_ed = reliability(fj_ext_def)
        @test rel_ed[1].status === :available_descriptive && !ismissing(rel_ed[1].separation)
        @test rel_en[1].separation ≈ rel_ed[1].separation atol = 1e-6
        @test rel_en[1].strata ≈ rel_ed[1].strata atol = 1e-6

        # Weighted (`weights = [1, 3, ...]`) extreme-adjusted JMLE parity + CSV `real_se` / score-method / ZSTD-meta checks
        fjw_ext_none = fit(sp72_ext_none; method = :jmle, extreme_adjustment = 0.3, weights = w72, gtol = 1e-11)
        fjw_ext_def = fit(sp72_ext_def; method = :jmle, extreme_adjustment = 0.3, weights = w72, gtol = 1e-11)
        @test loglikelihood(fjw_ext_none) ≈ loglikelihood(fjw_ext_def) atol = 1e-9
        @test sum(pointwise_loglikelihood(fjw_ext_def)) ≈ loglikelihood(fjw_ext_def) atol = 1e-11
        @test [r.estimate for r in facet_summary(fjw_ext_none; facet = :person).rows] ≈
              [r.estimate for r in facet_summary(fjw_ext_def; facet = :person).rows] atol = 1e-7
        @test [r.estimate for r in facet_summary(fjw_ext_none; facet = :rater).rows] ≈
              [r.estimate for r in facet_summary(fjw_ext_def; facet = :rater).rows] atol = 1e-7
        @test reliability(fjw_ext_none)[1].separation ≈ reliability(fjw_ext_def)[1].separation atol = 1e-7
        @test reliability(fjw_ext_none)[3].separation ≈ reliability(fjw_ext_def)[3].separation atol = 1e-7

        mktempdir() do exdir2
            # 1) JMLE CSV `real_se` matches fit `ps.real_se` on both simple & structured
            B.ValidationSuite.write_exchange_run(joinpath(exdir2, "jw_n"), fjw_ext_none;
                case_id = "c72jw", input_sha256 = "00", estimator = "JMLE", model = "RSM")
            B.ValidationSuite.write_exchange_run(joinpath(exdir2, "jw_d"), fjw_ext_def;
                case_id = "c72jw", input_sha256 = "00", estimator = "JMLE", model = "RSM")
            ex_jwn = B.ValidationSuite.read_exchange_run(joinpath(exdir2, "jw_n"))
            ex_jwd = B.ValidationSuite.read_exchange_run(joinpath(exdir2, "jw_d"))
            @test [r.real_se for r in ex_jwn.persons] ≈ [r.real_se for r in fjw_ext_none.record.person_scores] atol = 1e-12
            @test [r.real_se for r in ex_jwd.persons] ≈ [r.real_se for r in fjw_ext_def.record.person_scores] atol = 1e-12
            @test [r.real_se for r in ex_jwn.persons] ≈ [r.real_se for r in ex_jwd.persons] atol = 1e-7

            # 2) Incompatible estimator × person_score_method combinations are rejected at entry
            @test_throws ArgumentError B.ValidationSuite.write_exchange_run(joinpath(exdir2, "bad1"), fjw_ext_none;
                case_id = "c", input_sha256 = "00", estimator = "JMLE", model = "RSM", person_score_method = :eap)
            @test_throws ArgumentError B.ValidationSuite.write_exchange_run(joinpath(exdir2, "bad2"), fjw_ext_none;
                case_id = "c", input_sha256 = "00", estimator = "JMLE", model = "RSM", person_score_method = :mle)
            @test_throws ArgumentError B.ValidationSuite.write_exchange_run(joinpath(exdir2, "bad3"), fit_mw_none;
                case_id = "c", input_sha256 = "00", estimator = "MMLE", model = "RSM", person_score_method = :jml)
            @test !isdir(joinpath(exdir2, "bad1"))

            # 3) Conflicting `extra` ZSTD metadata is rejected, and keyword `zstd_cap` / `zstd_whexact` is actually applied
            @test_throws ArgumentError B.ValidationSuite.write_exchange_run(joinpath(exdir2, "bad_meta1"), fit_mw_def;
                case_id = "c", input_sha256 = "00", estimator = "MMLE", model = "RSM",
                extra = Dict("zstd_cap" => 0.01))
            @test_throws ArgumentError B.ValidationSuite.write_exchange_run(joinpath(exdir2, "bad_meta2"), fit_mw_def;
                case_id = "c", input_sha256 = "00", estimator = "MMLE", model = "RSM",
                extra = Dict("zstd_whexact" => false))

            B.ValidationSuite.write_exchange_run(joinpath(exdir2, "cap_applied"), fit_mw_def;
                case_id = "c", input_sha256 = "00", estimator = "MMLE", model = "RSM",
                zstd_cap = 0.01, zstd_whexact = false)
            ex_cap = B.ValidationSuite.read_exchange_run(joinpath(exdir2, "cap_applied"))
            @test ex_cap.meta.extra.zstd_cap == 0.01 && ex_cap.meta.extra.zstd_whexact == false
            @test maximum(abs(r.infit_z) for r in ex_cap.persons) <= 0.01 + 1e-15
            @test maximum(abs(r.infit_z) for r in ex_cap.facets) <= 0.01 + 1e-15
        end

        # High-2 & High-4: Exact `real_se` -> `reliability(fit; se = :real)` reproducibility AND `by = nothing` `fit_statistics`
        # across all 4 frequentist paths (simple/structured × MMLE/JMLE)
        for f4 in (fit_m_none_0, fit_m_def_0, fit_j_none, fit_j_def)
            d_all = diagnostics(f4; kind = :fit_statistics)
            @test d_all.by === :all
            for (k_idx, fn) in enumerate((:person, :item, :rater))
                rows_fn = getproperty(d_all.by_facet, fn)
                @test isequal(rows_fn, diagnostics(f4; kind = :fit_statistics, by = fn).rows)

                frows = facet_summary(f4; facet = fn).rows
                ests = Float64[r.estimate for r in frows]
                rses = Float64[r.real_se for r in frows]
                mv_s = var(ests; corrected = true)
                ev_r = mean(rses .^ 2)
                is_eap_p = (fn === :person && f4.record.summary.method === :mmle)
                sig_r = is_eap_p ? mv_s : max(mv_s - ev_r, 0.0)
                exp_sep_r = sqrt(sig_r / ev_r)
                exp_str_r = (4.0 * exp_sep_r + 1.0) / 3.0

                r_real = reliability(f4; se = :real)[k_idx]
                r_def = reliability(f4)[k_idx]
                @test r_real.rmse ≈ sqrt(ev_r) atol = 1e-12
                @test r_def.real_rmse ≈ sqrt(ev_r) atol = 1e-12
                @test r_real.separation ≈ exp_sep_r atol = 1e-12
                @test r_def.real_separation ≈ exp_sep_r atol = 1e-12
                @test r_real.strata ≈ exp_str_r atol = 1e-12
                @test r_def.real_strata ≈ exp_str_r atol = 1e-12
            end
        end

        # Priority 3 guard: Bayesian `MRCMLTarget` reliability keeps `separation === missing, strata === missing` and no frequentist ZSTD
        fit_bay = fit(sp_def_free_mu; chains = 2, warmup = 30, ndraws = 30, seed = 77)
        rel_bay = reliability(fit_bay)
        @test ismissing(rel_bay.separation) && ismissing(rel_bay.strata)
        fs_bay = diagnostics(fit_bay; kind = :fit_statistics, by = :rater)
        @test all(r -> !haskey(r, :infit_zstd) && haskey(r, :infit_mnsq_mean), fs_bay.rows)

        if Base.get_extension(B, :BayesianMGMFRMCairoMakieExt) !== nothing
            @test B.plot(fit_m_def_mu; kind = :posterior, annotation_io = IOBuffer()) !== nothing
            @test B.plot(fit_m_def_mu; kind = :wright, annotation_io = IOBuffer()) !== nothing
            @test B.plot(fit_m_def_mu; kind = :pathway, annotation_io = IOBuffer()) !== nothing
        end
    end
end
end

include("large_panel_speed_parity.jl")
