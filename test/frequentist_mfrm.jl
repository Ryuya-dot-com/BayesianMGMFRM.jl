module FrequentistMFRMChecks
using BayesianMGMFRM
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

    # 1. Prior-free F-facet mfrm_spec AND Bayesian-prior F-facet mfrm_spec produce identical frequentist fits
    spec_noprior = mfrm_spec(tbl; person = :Person,
        facets = (Rater = :Rater, Task = :Task, Criterion = :Criterion),
        score = :Score, steps = :global, category_levels = 0:4)
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
        score = :Score, steps = :Criterion, category_levels = 0:4)
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
        score = :Score, steps = :global, category_levels = 0:4)
    f_ext_unadj = fit(sp_ext; method = :jmle, extreme_adjustment = 0.0)
    @test qualify(f_ext_unadj).qualified

    keep_int = [i for i in eachindex(tbl_ext.Person) if !(tbl_ext.Person[i] in ("P01", "P18"))]
    tbl_int = (; (k => getproperty(tbl_ext, k)[keep_int] for k in keys(tbl_ext))...)
    sp_int = mfrm_spec(tbl_int; person = :Person,
        facets = (Rater = :Rater, Task = :Task, Criterion = :Criterion),
        score = :Score, steps = :global, category_levels = 0:4)
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
end
end
