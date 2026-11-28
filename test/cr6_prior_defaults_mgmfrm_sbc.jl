using Test
using BayesianMGMFRM
using BayesianMGMFRM.GlassBox
using BayesianMGMFRM.ValidationSuite
using Distributions: Normal, LogNormal, TDist, Cauchy, LocationScale, truncated
using ForwardDiff
using JSON3
using LinearAlgebra
using LogDensityProblems
using Random
using Statistics

const RP = BayesianMGMFRM.ValidationSuite.RecoveryPlanning
const EXP = BayesianMGMFRM.Experimental
const SIM = BayesianMGMFRM.ScaleIdentifiedMGMFRM

@testset "CR6: Zero-Supporting Scale Priors, Transparent Prior Summary, Hardened MGMFRM & v0.2 SBC" begin
    # -----------------------------------------------------------------------
    # 1. Default 1D prior is now zero-supporting HalfNormal(1.0) + transparent prior_summary
    # -----------------------------------------------------------------------
    @testset "prior = :default uses HalfNormal(1.0) and exposes prior_summary" begin
        rng = MersenneTwister(20261124)
        tbl = (
            person = repeat(1:8, inner = 6),
            item   = repeat(["I1", "I2", "I3"], inner = 2, outer = 8),
            rater  = repeat(["R1", "R2"], outer = 24),
            score  = rand(rng, 0:2, 48),
        )
        t_def = mfrm_spec(tbl; person = :person, score = :score,
            facets = (item = :item, rater = :rater), steps = :global,
            category_levels = 0:2, prior = :default)
        ds = design_summary(t_def)
        @test hasproperty(ds, :prior_summary)
        ps = ds.prior_summary
        @test ps.default_prior === true
        @test ps.person.family === :HalfNormal
        @test ps.person.zero_supporting === true
        @test isapprox(ps.person.scale, 1.0; atol = 1e-12)
        @test ps.person.prob_sd_le_025 > 0.15
        @test ps.population_mean.mean == 0.0 && ps.population_mean.sd == 2.5
        b_rater = only(filter(b -> b.name === :rater, ps.structural_blocks))
        b_item  = only(filter(b -> b.name === :item, ps.structural_blocks))
        # L=2 -> sqrt(2 * 2 / 1) = 2.0; L=3 -> sqrt(2 * 3 / 2) = sqrt(3)
        @test isapprox(b_rater.implied_pairwise_contrast_sd, 2.0; atol = 1e-12)
        @test isapprox(b_item.implied_pairwise_contrast_sd, sqrt(3.0); atol = 1e-12)

        # prior_draw produces finite draws matching HalfNormal(1.0) median empirically
        draws_sig = [exp(BayesianMGMFRM.AdditiveFacets.prior_draw(t_def; seed = s)[t_def.person_hyper_idx]) for s in 1:400]
        @test all(x -> isfinite(x) && x > 0.0, draws_sig)
        @test 0.50 <= median(draws_sig) <= 0.85

        # fit_report exposes prior_summary too
        f_def = fit(t_def; chains = 2, warmup = 60, ndraws = 60, seed = 91, progress = false)
        rep = BayesianMGMFRM.fit_report(f_def)
        @test hasproperty(rep, :prior_summary)
        @test rep.prior_summary.person.family === :HalfNormal
    end

    # -----------------------------------------------------------------------
    # 2. Zero-supporting scale priors (HalfNormal, HalfStudentT, HalfCauchy)
    #    ForwardDiff & CmdStan 2.39.0 parity
    # -----------------------------------------------------------------------
    @testset "HalfNormal / HalfStudentT / HalfCauchy ForwardDiff & CmdStan parity" begin
        rng = MersenneTwister(20261125)
        tbl = (
            person = repeat(1:6, inner = 12),
            item   = repeat(1:4, inner = 3, outer = 6),
            rater  = repeat(1:3, outer = 24),
            score  = rand(rng, 0:3, 72),
        )
        t_gen = mfrm_spec(tbl; person = :person, score = :score,
            facets = (item = :item, rater = :rater), steps = :global,
            category_levels = 0:3,
            intercept = Normal(0.0, 2.5),
            prior_sd = (
                person = truncated(TDist(4.0), 0.0, Inf),
                facets = (item = truncated(Normal(0.0, 1.0), 0.0, Inf), rater = 1.0),
                step = truncated(LocationScale(0.0, 0.75, TDist(3.0)), 0.0, Inf),
            ),
            interactions = [(:rater, :item) => truncated(Cauchy(0.0, 0.5), 0.0, Inf)])

        ds = design_summary(t_gen)
        @test ds.prior_summary.person.family === :HalfStudentT
        b_int = only(filter(b -> b.name === :item_rater, ds.prior_summary.structural_blocks))
        @test ismissing(b_int.implied_pairwise_contrast_sd) # 2-way Kronecker block

        # Record/restore roundtrip preserves person_scale_prior and exact logposterior
        t_rest = BayesianMGMFRM.AdditiveFacets.restore_mrcml(BayesianMGMFRM.AdditiveFacets.record(t_gen))
        D_dim = LogDensityProblems.dimension(t_gen)
        pts = [
            zeros(Float64, D_dim),
            [0.2 * sin(0.7 * j) for j in 1:D_dim],
            vcat(fill(0.15, D_dim - 4), [-2.2, -0.8, 0.4, -1.9]),
        ]
        j_lps = Float64[]
        j_grads = Vector{Float64}[]
        for q in pts
            lp, g = LogDensityProblems.logdensity_and_gradient(t_gen, q)
            lp_r = logposterior(t_rest, q)
            g_fd = ForwardDiff.gradient(x -> logposterior(t_gen, x), q)
            @test abs(lp - lp_r) <= 1e-13
            @test maximum(abs.(g .- g_fd)) <= 1e-11
            push!(j_lps, lp)
            push!(j_grads, g)
        end

        stan_chk = BayesianMGMFRM.cmdstan_backend_check(; include_paths = true)
        if stan_chk.runtime_ready
            mktempdir() do dir
                make_prog = BayesianMGMFRM._cmdstan_configured_program("MAKE", ("make", "gmake"))
                stem = joinpath(dir, "mrcml_cr6_scale")
                write(stem * ".stan", BayesianMGMFRM.MRCML.stan_code(t_gen))
                BayesianMGMFRM._cmdstan_run(Cmd(`$make_prog -f makefile $stem`; dir = stan_chk.cmdstan_root), :model_compile)
                exe = BayesianMGMFRM._cmdstan_executable_path(stem)
                d_path = joinpath(dir, "data.json")
                p_path = joinpath(dir, "pts.json")
                o_path = joinpath(dir, "out.csv")
                sd_json = Dict(k => (v isa AbstractMatrix ? [collect(r) for r in eachrow(v)] : v) for (k, v) in stan_data(t_gen))
                write(d_path, JSON3.write(sd_json))
                write(p_path, JSON3.write((; params_r = pts)))
                BayesianMGMFRM._cmdstan_run(`$exe log_prob unconstrained_params=$p_path jacobian=1 data file=$d_path output file=$o_path sig_figs=18 refresh=0`, :density_check)
                csv = BayesianMGMFRM._cmdstan_read_csv(o_path, length(pts))
                for r in eachindex(pts)
                    @test abs(csv.values[r, 1] - j_lps[r]) <= 1e-12
                    @test maximum(abs.(csv.values[r, 2:end] .- j_grads[r])) <= 1e-11
                end
            end
        end
    end

    # -----------------------------------------------------------------------
    # 3. ScaleIdentifiedMGMFRM PRS Reference-Design Person-Centered Sampling Chart
    # -----------------------------------------------------------------------
    @testset "ScaleIdentifiedMGMFRM PRS person-centered sampling chart parity & qualification" begin
        rng = MersenneTwister(20261126)
        P_n, I_n, R_n = 12, 4, 3
        Q = Bool[1 0; 1 0; 0 1; 0 1]
        p_col = String[]; i_col = String[]; r_col = String[]; y_col = Int[]
        for p in 1:P_n, i in 1:I_n, r in 1:R_n
            push!(p_col, "P$p"); push!(i_col, "I$i"); push!(r_col, "R$r")
            push!(y_col, rand(rng, 1:4))
        end
        fd = FacetData((; person = p_col, item = i_col, rater = r_col, score = y_col);
            person = :person, item = :item, rater = :rater, score = :score, category_levels = 1:4)
        spec = mfrm_spec(fd; family = :mgmfrm, dimensions = 2, thresholds = :partial_credit, q_matrix = Q)
        pr_geo = EXP.ScaleIdentifiedMGMFRMPrior(; scale_identification = :geometric_mean_one, logit_scale = 1.7)
        pr_anc = EXP.ScaleIdentifiedMGMFRMPrior(; scale_identification = :anchor_item, anchor_items = ["I1", "I3"], logit_scale = 1.7)

        for pr in (pr_geo, pr_anc)
            t = SIM.model(spec; prior = pr)
            # Outcome-free PRS auto check: 6 ratings/dim * 1.7^2 * 1.25 = 21.675 >= 8.0 -> [true, true]
            st_auto = SIM.SamplingTarget(t; person_coordinates = :auto)
            @test st_auto.centered_dims == [true, true]
            st_ncp = SIM.SamplingTarget(t; person_coordinates = :noncentered)
            @test st_ncp.centered_dims == [false, false]
            st_hi = SIM.SamplingTarget(t; person_coordinates = (information_cutoff = 50.0,))
            @test st_hi.centered_dims == [false, false]
            for st in (st_auto, SIM.SamplingTarget(t; person_coordinates = [false, true]))
                u0 = randn(MersenneTwister(33), t.dimension) .* 0.25
                q0 = SIM.to_raw(st, u0)
                @test maximum(abs.(SIM.from_raw(st, q0) .- u0)) <= 1e-13
                val_a, ga = LogDensityProblems.logdensity_and_gradient(st, u0)
                val_f = LogDensityProblems.logdensity(st, u0)
                gf = ForwardDiff.gradient(x -> LogDensityProblems.logdensity(st, x), u0)
                @test abs(val_a - val_f) <= 1e-12
                @test maximum(abs.(ga .- gf)) <= 1e-11
            end
        end

        # End-to-end fit with both default (:noncentered) and explicit (:auto -> centered) passes checked(f; full=true)
        f_mg_ncp = EXP.fit(spec; prior = pr_geo, chains = 2, warmup = 80, ndraws = 80, seed = 51, progress = false)
        @test SIM.checked(f_mg_ncp; full = true) isa SIM.Target
        f_mg_auto = SIM.fit(SIM.model(spec; prior = pr_geo); chains = 2, warmup = 80, ndraws = 80, seed = 51, person_coordinates = :auto, progress = false)
        @test SIM.checked(f_mg_auto; full = true) isa SIM.Target
    end

    # -----------------------------------------------------------------------
    # 4. Modernized v0.2 ValidationSuite SBC on MRCMLTarget and ScaleIdentifiedMGMFRM
    # -----------------------------------------------------------------------
    @testset "ValidationSuite v0.2 SBC end-to-end on MRCMLTarget and ScaleIdentifiedMGMFRM" begin
        # 4A. Isometric 1D MRCMLTarget (prior = :default, HalfNormal(1.0))
        tbl = (
            person = repeat(["P$p" for p in 1:6], inner = 4),
            item   = repeat(["I1", "I2"], inner = 2, outer = 6),
            rater  = repeat(["R1", "R2"], outer = 12),
            score  = repeat([0, 1, 1, 2], 6),
        )
        t_1d = mfrm_spec(tbl; person = :person, score = :score,
            facets = (item = :item, rater = :rater), steps = :global,
            category_levels = 0:2, prior = :default)
        jobs_1d = [
            (; dataset_id = "sbc_1d_$k", parameter_seed = 100 + k, response_seed = 200 + k, fit_seed = 300 + k)
            for k in 1:4
        ]
        study_1d = RP.prepare_sbc(t_1d;
            jobs = jobs_1d,
            parameters = ["population_mean", "residual_sd[person]", "rater[\"R1\"]", "item[\"I1\"]"],
            sampler = (; chains = 2, warmup = 100, ndraws = 100),
            gates = (; max_rhat = 1.05, min_ess = 20.0, min_bfmi = 0.2),
            rank_settings = (; iterations = collect(10:10:100), dependence_policy = "smoke test thinning stride 10"))
        @test study_1d.target_kind === :mrcml_target
        @test study_1d.test_quantities[end - 1] == "joint_log_likelihood"
        @test study_1d.test_quantities[end] == "joint_log_posterior"

        # Run 2 real fits + 1 explicit :fit_failed + leave 1 missing -> verify full denominator 4!
        outcomes_1d = Any[]
        for k in 1:2
            ds_k = RP.generate_sbc_dataset(study_1d, "sbc_1d_$k")
            f_k = fit(ds_k.target_sim; chains = 2, warmup = 100, ndraws = 100, seed = ds_k.fit_seed, progress = false)
            rev_k = RP.review_sbc_fit(study_1d, ds_k, f_k;
                posterior_dependence = (; status = :declared_independent, evidence = "smoke test"))
            @test length(rev_k.ranks) == 6
            # Verify sealed plan binding rejects mismatched thresholds, seed, warmup, and sampling chart
            if k == 1
                @test study_1d.sampling_chart.sampling_chart === :givens_mean_orthogonal
                @test_throws ArgumentError RP.review_sbc_fit(study_1d, ds_k, f_k;
                    posterior_dependence = (; status = :declared_independent, evidence = "smoke test"),
                    max_rhat = 1.10)
                f_wrong_seed = fit(ds_k.target_sim; chains = 2, warmup = 100, ndraws = 100, seed = ds_k.fit_seed + 1, progress = false)
                @test_throws ArgumentError RP.review_sbc_fit(study_1d, ds_k, f_wrong_seed;
                    posterior_dependence = (; status = :declared_independent, evidence = "smoke test"))
                f_wrong_wu = fit(ds_k.target_sim; chains = 2, warmup = 80, ndraws = 100, seed = ds_k.fit_seed, progress = false)
                @test_throws ArgumentError RP.review_sbc_fit(study_1d, ds_k, f_wrong_wu;
                    posterior_dependence = (; status = :declared_independent, evidence = "smoke test"))
                # Counterexample: Givens plan MUST reject a raw-coordinate fit (same target, same seed/warmup)
                f_raw_chart = fit(ds_k.target_sim; chains = 2, warmup = 100, ndraws = 100, seed = ds_k.fit_seed,
                    mean_orthogonalization = :none, progress = false)
                @test f_raw_chart.record.producer.sampling_chart === :raw
                @test_throws ArgumentError RP.review_sbc_fit(study_1d, ds_k, f_raw_chart;
                    posterior_dependence = (; status = :declared_independent, evidence = "smoke test"))
                # Converse: raw plan MUST accept the raw fit and reject the Givens fit
                study_1d_raw = RP.prepare_sbc(t_1d;
                    jobs = jobs_1d,
                    parameters = ["population_mean", "residual_sd[person]", "rater[\"R1\"]", "item[\"I1\"]"],
                    sampler = (; chains = 2, warmup = 100, ndraws = 100, mean_orthogonalization = :none),
                    gates = (; max_rhat = 1.05, min_ess = 20.0, min_bfmi = 0.2),
                    rank_settings = (; iterations = collect(10:10:100), dependence_policy = "smoke test thinning stride 10"))
                @test study_1d_raw.sampling_chart.sampling_chart === :raw
                ds_raw1 = RP.generate_sbc_dataset(study_1d_raw, "sbc_1d_1")
                @test length(RP.review_sbc_fit(study_1d_raw, ds_raw1, f_raw_chart;
                    posterior_dependence = (; status = :declared_independent, evidence = "smoke test")).ranks) == 6
                @test_throws ArgumentError RP.review_sbc_fit(study_1d_raw, ds_raw1, f_k;
                    posterior_dependence = (; status = :declared_independent, evidence = "smoke test"))
            end
            push!(outcomes_1d, rev_k)
        end
        push!(outcomes_1d, (; dataset_id = "sbc_1d_3", status = :fit_failed, reason = "simulated failure for denominator check"))
        # sbc_1d_4 intentionally omitted to verify missing slot retention!
        sum_1d = RP.summarize_sbc(study_1d, outcomes_1d;
            alpha = 0.05,
            dataset_independence = (; status = :declared_independent, evidence = "distinct RNG seeds"))
        @test sum_1d.n_planned == 4
        @test sum_1d.denominator_policy === :all_planned_jobs_retained_unconditionally
        @test length(sum_1d.roster) == 4
        @test sum_1d.exclusion_counts[:fit_failed] == 1
        @test sum_1d.exclusion_counts[:missing_outcome] == 1
        @test all(q -> q.planned == 4 && q.unresolved >= 2, sum_1d.quantities)

        # 4B. ScaleIdentifiedMGMFRM.Target (:geometric_mean_one)
        rng = MersenneTwister(20261127)
        p_c = String[]; i_c = String[]; r_c = String[]; y_c = Int[]
        for p in 1:8, i in 1:4, r in 1:2
            push!(p_c, "P$p"); push!(i_c, "I$i"); push!(r_c, "R$r"); push!(y_c, rand(rng, 1:3))
        end
        fd_m = FacetData((; person = p_c, item = i_c, rater = r_c, score = y_c);
            person = :person, item = :item, rater = :rater, score = :score, category_levels = 1:3)
        sp_m = mfrm_spec(fd_m; family = :mgmfrm, dimensions = 2, thresholds = :partial_credit,
            q_matrix = Bool[1 0; 1 0; 0 1; 0 1])
        t_m = SIM.model(sp_m; prior = EXP.ScaleIdentifiedMGMFRMPrior(; scale_identification = :geometric_mean_one))
        jobs_m = [
            (; dataset_id = "sbc_mg_$k", parameter_seed = 400 + k, response_seed = 500 + k, fit_seed = 600 + k)
            for k in 1:2
        ]
        study_m = RP.prepare_sbc(t_m;
            jobs = jobs_m,
            parameters = ["ability_sd[dim=1]", "ability_sd[dim=2]", "standardized_loading[I1, dim=1]"],
            sampler = (; chains = 2, warmup = 80, ndraws = 80),
            gates = (; max_rhat = 1.05, min_ess = 20.0, min_bfmi = 0.2),
            rank_settings = (; iterations = collect(8:8:80), dependence_policy = "smoke test thinning stride 8"))
        @test study_m.target_kind === :scale_identified_mgmfrm
        @test study_m.sampling_chart.sampling_coordinates === :orthogonal_decoupled
        @test study_m.sampling_chart.centered_dims == (false, false)
        ds_m1 = RP.generate_sbc_dataset(study_m, "sbc_mg_1")
        f_m1 = SIM.fit(ds_m1.target_sim; chains = 2, warmup = 80, ndraws = 80, seed = ds_m1.fit_seed, progress = false)
        @test f_m1.record.producer.sampling_coordinates === :orthogonal_decoupled
        @test f_m1.record.producer.centered_dims == (false, false)
        rev_m1 = RP.review_sbc_fit(study_m, ds_m1, f_m1;
            posterior_dependence = (; status = :declared_independent, evidence = "smoke test"))
        @test length(rev_m1.ranks) == 5 # 3 focal + joint_log_likelihood + joint_log_posterior
        # Counterexamples for MGMFRM B/C: noncentered plan MUST reject centered ([true, true] / [false, true]) and raw fits
        f_m1_centered = SIM.fit(ds_m1.target_sim; chains = 2, warmup = 80, ndraws = 80, seed = ds_m1.fit_seed,
            person_coordinates = :centered, progress = false)
        @test f_m1_centered.record.producer.centered_dims == (true, true)
        @test_throws ArgumentError RP.review_sbc_fit(study_m, ds_m1, f_m1_centered;
            posterior_dependence = (; status = :declared_independent, evidence = "smoke test"))
        f_m1_mixed = SIM.fit(ds_m1.target_sim; chains = 2, warmup = 80, ndraws = 80, seed = ds_m1.fit_seed,
            person_coordinates = [false, true], progress = false)
        @test f_m1_mixed.record.producer.centered_dims == (false, true)
        @test_throws ArgumentError RP.review_sbc_fit(study_m, ds_m1, f_m1_mixed;
            posterior_dependence = (; status = :declared_independent, evidence = "smoke test"))
        f_m1_raw = SIM.fit(ds_m1.target_sim; chains = 2, warmup = 80, ndraws = 80, seed = ds_m1.fit_seed,
            sampling_coordinates = :raw, progress = false)
        @test f_m1_raw.record.producer.sampling_coordinates === :raw
        @test_throws ArgumentError RP.review_sbc_fit(study_m, ds_m1, f_m1_raw;
            posterior_dependence = (; status = :declared_independent, evidence = "smoke test"))
        # Converse: centered plan (e.g. information_cutoff = 5.0 resolving to (true, true)) accepts centered fit and rejects noncentered fit
        study_m_centered = RP.prepare_sbc(t_m;
            jobs = jobs_m,
            parameters = ["ability_sd[dim=1]", "ability_sd[dim=2]", "standardized_loading[I1, dim=1]"],
            sampler = (; chains = 2, warmup = 80, ndraws = 80, person_coordinates = (information_cutoff = 5.0,)),
            gates = (; max_rhat = 1.05, min_ess = 20.0, min_bfmi = 0.2),
            rank_settings = (; iterations = collect(8:8:80), dependence_policy = "smoke test thinning stride 8"))
        @test study_m_centered.sampling_chart.centered_dims == (true, true)
        ds_m1_centered = RP.generate_sbc_dataset(study_m_centered, "sbc_mg_1")
        @test length(RP.review_sbc_fit(study_m_centered, ds_m1_centered, f_m1_centered;
            posterior_dependence = (; status = :declared_independent, evidence = "smoke test")).ranks) == 5
        @test_throws ArgumentError RP.review_sbc_fit(study_m_centered, ds_m1_centered, f_m1;
            posterior_dependence = (; status = :declared_independent, evidence = "smoke test"))
        sum_m = RP.summarize_sbc(study_m, [rev_m1];
            alpha = 0.05,
            dataset_independence = (; status = :declared_independent, evidence = "distinct RNG seeds"))
        @test sum_m.n_planned == 2
        @test sum_m.exclusion_counts[:missing_outcome] == 1
    end

    # -----------------------------------------------------------------------
    # 5. Exact volume-preserving Givens orthogonalization on 1D MRCMLTarget
    # -----------------------------------------------------------------------
    @testset "1D MRCMLTarget exact Givens mean-orthogonalization (log|det J| == 0)" begin
        AF = BayesianMGMFRM.AdditiveFacets
        tbl = (
            person = repeat(["P$p" for p in 1:6], inner = 4),
            item   = repeat(["I1", "I2"], inner = 2, outer = 6),
            rater  = repeat(["R1", "R2"], outer = 12),
            score  = repeat([0, 1, 1, 2], 6),
        )
        t_1d = mfrm_spec(tbl; person = :person, score = :score,
            facets = (item = :item, rater = :rater), steps = :global,
            category_levels = 0:2, prior = :default)
        gt = AF._maybe_mrcml_givens_target(t_1d)
        @test gt !== nothing
        u0 = randn(MersenneTwister(20261128), t_1d.dimension) .* 0.35
        q0 = AF._givens_to_raw(gt, u0)
        @test maximum(abs.(AF._givens_from_raw(gt, q0) .- u0)) <= 1e-13
        # Exact unit Jacobian determinant (volume-preserving)
        J = ForwardDiff.jacobian(u -> AF._givens_to_raw(gt, u), u0)
        lad, _ = LinearAlgebra.logabsdet(J)
        @test abs(lad) <= 1e-12
        # Exact density & gradient parity
        va, ga = LogDensityProblems.logdensity_and_gradient(gt, u0)
        vf = LogDensityProblems.logdensity(gt, u0)
        vq = LogDensityProblems.logdensity(t_1d, q0)
        gf = ForwardDiff.gradient(u -> LogDensityProblems.logdensity(gt, u), u0)
        @test abs(va - vf) <= 1e-12
        @test abs(va - vq) <= 1e-12
        @test maximum(abs.(ga .- gf)) <= 1e-11
        # End-to-end fit maps cleanly back to canonical raw q space and passes full checked(f; full=true)
        f_g = fit(t_1d; chains = 2, warmup = 80, ndraws = 80, seed = 91, progress = false)
        @test AF.checked(f_g; full = true) isa AF.MRCMLTarget
        @test f_g.record.producer.sampling_chart === :givens_mean_orthogonal
        # Explicit mean_orthogonalization = :none reproduces the pre-Givens raw sampling chart
        f_raw = fit(t_1d; chains = 2, warmup = 80, ndraws = 80, seed = 91, mean_orthogonalization = :none, progress = false)
        @test AF.checked(f_raw; full = true) isa AF.MRCMLTarget
        @test f_raw.record.producer.sampling_chart === :raw
    end

    # -----------------------------------------------------------------------
    # 6. CR6 Post-Review Bug Fixes:
    #    (a) Half-t cohort reliability / unavailable population target & :parameter_specific raw unit
    #    (b) Hierarchical facet marginal vs. conditional-at-median contrast SD (incl. Half-Cauchy Inf)
    #    (c) Single-RNG simulate(t; seed) stream threading for Half-t / Half-Cauchy
    # -----------------------------------------------------------------------
    @testset "CR6 Review Fixes: Half-t reliability, hierarchical contrast SD, single-RNG simulate" begin
        AF = BayesianMGMFRM.AdditiveFacets
        tbl = (
            person = repeat(["P$p" for p in 1:6], inner = 4),
            item   = repeat(["I1", "I2"], inner = 2, outer = 6),
            rater  = repeat(["R1", "R2"], outer = 12),
            score  = repeat([0, 1, 1, 2], 6),
        )
        # (a) HalfStudentT person scales retain cohort reliability, without an invalid population proxy
        t_ht = mfrm_spec(tbl; person = :person, score = :score,
            facets = (item = :item, rater = :rater), steps = :global, category_levels = 0:2,
            prior_sd = (person = truncated(TDist(4), 0.0, Inf), facets = (item = 1.0, rater = 1.0), step = 1.0),
            intercept = Normal(0.0, 2.5))
        f_ht = fit(t_ht; chains = 2, warmup = 80, ndraws = 80, seed = 77, progress = false)
        rel_ht = reliability(f_ht)
        @test ismissing(rel_ht.population_marginal_reliability)
        @test rel_ht.population_status === :requires_population_and_design_marginalization
        @test 0 <= rel_ht.reliability <= 1
        # Raw summary unit and diagnostic parameter_space MUST be :parameter_specific for non-lognormal scales
        @test posterior_summary(f_ht; scale = :raw).unit === :parameter_specific
        @test diagnostics(f_ht).raw[1].parameter_space === :parameter_specific

        # (b) Hierarchical facet contrast SD: marginal second moment vs. conditional-at-median
        # 2 raters => sqrt(2 * L / (L - 1)) = 2.0
        t_hn_r = mfrm_spec(tbl; person = :person, score = :score,
            facets = (item = :item, rater = :rater), steps = :global, category_levels = 0:2,
            prior_sd = (person = 1.0, facets = (item = 1.0, rater = truncated(Normal(0.0, 1.0), 0.0, Inf)), step = 1.0),
            intercept = Normal(0.0, 2.5))
        br_hn = only(filter(b -> b.name === :rater, design_summary(t_hn_r).prior_summary.structural_blocks))
        @test br_hn.pairwise_contrast_sd_basis === :marginal_second_moment
        @test br_hn.scale_prior.second_moment_finite === true
        @test isapprox(br_hn.implied_pairwise_contrast_sd, 2.0; atol = 1e-12)
        @test isapprox(br_hn.conditional_median_pairwise_contrast_sd, 2.0 * br_hn.scale_prior.median_sd; atol = 1e-12)
        @test isapprox(br_hn.conditional_median_pairwise_contrast_sd, 1.3489795003921634; atol = 1e-10)

        t_ht_r = mfrm_spec(tbl; person = :person, score = :score,
            facets = (item = :item, rater = :rater), steps = :global, category_levels = 0:2,
            prior_sd = (person = 1.0, facets = (item = 1.0, rater = truncated(TDist(4), 0.0, Inf)), step = 1.0),
            intercept = Normal(0.0, 2.5))
        br_ht = only(filter(b -> b.name === :rater, design_summary(t_ht_r).prior_summary.structural_blocks))
        @test br_ht.pairwise_contrast_sd_basis === :marginal_second_moment
        @test isapprox(br_ht.implied_pairwise_contrast_sd, 2.0 * sqrt(2.0); atol = 1e-12)

        t_hc_r = mfrm_spec(tbl; person = :person, score = :score,
            facets = (item = :item, rater = :rater), steps = :global, category_levels = 0:2,
            prior_sd = (person = 1.0, facets = (item = 1.0, rater = truncated(Cauchy(0.0, 1.0), 0.0, Inf)), step = 1.0),
            intercept = Normal(0.0, 2.5))
        br_hc = only(filter(b -> b.name === :rater, design_summary(t_hc_r).prior_summary.structural_blocks))
        @test br_hc.pairwise_contrast_sd_basis === :divergent_second_moment
        @test br_hc.scale_prior.second_moment_finite === false
        @test isinf(br_hc.implied_pairwise_contrast_sd)
        @test isinf(br_hc.marginal_sd)
        @test isapprox(br_hc.conditional_median_pairwise_contrast_sd, 2.0; atol = 1e-12)

        t_ln_r = mfrm_spec(tbl; person = :person, score = :score,
            facets = (item = :item, rater = :rater), steps = :global, category_levels = 0:2,
            prior_sd = (person = 1.0, facets = (item = 1.0, rater = LogNormal(0.0, 0.5)), step = 1.0),
            intercept = Normal(0.0, 2.5))
        br_ln = only(filter(b -> b.name === :rater, design_summary(t_ln_r).prior_summary.structural_blocks))
        @test br_ln.pairwise_contrast_sd_basis === :marginal_second_moment
        @test isapprox(br_ln.implied_pairwise_contrast_sd, 2.0 * exp(0.25); atol = 1e-12)
        @test isapprox(br_ln.conditional_median_pairwise_contrast_sd, 2.0; atol = 1e-12)

        # (c) Single-RNG simulate(t; seed) under Half-t continues strictly after Chisq scale draws (no RNG reuse)
        for sd_seed in (1, 2, 7, 13)
            sim_res = simulate(t_ht; seed = sd_seed)
            # Manual single-stream continuation:
            rng_ref = MersenneTwister(sd_seed)
            q_ref = AF._prior_draw!(rng_ref, t_ht)
            @test sim_res.truth == q_ref
            probs_ref = exp.(AF.logprobs(t_ht, q_ref))
            cat_ref = [AF._sample_category(t_ht, n, view(probs_ref, n, :), rand(rng_ref)) for n in eachindex(t_ht.person)]
            @test sim_res.category == cat_ref
            # Explicit q passes cleanly through the same post-prior stream position
            sim_q = simulate(t_ht; seed = sd_seed, q = q_ref)
            @test sim_q.category == cat_ref
        end
    end
end
