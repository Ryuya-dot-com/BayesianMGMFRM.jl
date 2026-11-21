using BayesianMGMFRM
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
    # -----------------------------------------------------------------------
    # 1. Isometric Helmert & Kronecker Bases + Subspace Isometric Prior
    # -----------------------------------------------------------------------
    @testset "Isometric bases and TAM -1 prior-asymmetry cure" begin
        for J in (2, 3, 5)
            C = _MRCML_TEST.helmert_basis(J)
            @test size(C) == (J, J - 1)
            @test isapprox(C' * C, Matrix{Float64}(I, J - 1, J - 1); atol = 1e-14)
            @test maximum(abs.(sum(C; dims = 1))) <= 1e-14
            P_proj = C * C'
            @test all(i -> isapprox(P_proj[i, i], (J - 1) / J; atol = 1e-14), 1:J)
        end

        K34 = _MRCML_TEST.kronecker_isometric_basis(3, 4)
        @test size(K34) == (12, 6)
        @test isapprox(K34' * K34, Matrix{Float64}(I, 6, 6); atol = 1e-14)
        # Check exact row-sum and column-sum zero for every column of K34
        for col in 1:6
            mat = reshape(K34[:, col], 4, 3)' # 3 x 4
            @test maximum(abs.(sum(mat; dims = 1))) <= 1e-14
            @test maximum(abs.(sum(mat; dims = 2))) <= 1e-14
        end
        P_kr = K34 * K34'
        @test all(i -> isapprox(P_kr[i, i], (2 * 3) / 12; atol = 1e-14), 1:12)

        # TAM last-level -1 sum-to-zero basis M_tam = [I_{J-1}; -1^T] for J = 4 raters
        M_tam = [1.0 0.0 0.0;
                 0.0 1.0 0.0;
                 0.0 0.0 1.0;
                -1.0 -1.0 -1.0]
        sd_target = 0.65
        mvn_iso = _MRCML_TEST.subspace_isometric_prior(M_tam, sd_target)
        Sigma_induced = M_tam * Matrix(cov(mvn_iso)) * M_tam'
        # Every single level 1..4 has exact marginal SD = 0.65 (variance = 0.4225)!
        @test all(j -> isapprox(sqrt(Sigma_induced[j, j]), sd_target; atol = 1e-14), 1:4)
        @test maximum(abs.(sum(Sigma_induced; dims = 1))) <= 1e-14
    end

    # -----------------------------------------------------------------------
    # 2. Exact Reduction to AdditiveFacets.Target + Label-Permutation Invariance
    # -----------------------------------------------------------------------
    @testset "Exact reduction & label-permutation invariance" begin
        rng = MersenneTwister(20261120)
        n_p = 8
        tbl = (
            person = repeat(["P$p" for p in 1:n_p], inner = 6),
            rater  = repeat(["R1", "R2", "R3"], outer = 2 * n_p),
            item   = repeat(["I1", "I1", "I1", "I2", "I2", "I2"], outer = n_p),
            score  = rand(rng, 0:2, 6 * n_p),
        )
        psd = (person = 1.1, facets = (rater = 0.55, item = 0.8), step = 0.45)
        spec_af = mfrm_spec(tbl; person = :person, score = :score,
            facets = (rater = :rater, item = :item), steps = :item,
            category_levels = 0:2, prior_sd = psd)
        spec_mr = BayesianMGMFRM.AdditiveFacets.compile_structured_mrcml(tbl;
            person = :person, score = :score, facets = (rater = :rater, item = :item),
            steps = :item, category_levels = 0:2, prior_sd = psd)

        q0 = randn(MersenneTwister(99), LogDensityProblems.dimension(spec_af))
        lp_af, g_af = logdensity_and_gradient(spec_af, q0)
        lp_mr, g_mr = logdensity_and_gradient(spec_mr, q0)
        @test isapprox(lp_af, lp_mr; atol = 1e-13)
        @test maximum(abs.(g_af .- g_mr)) <= 1e-13
        @test isapprox(coordinates(spec_af, q0).log_volume, coordinates(spec_mr, q0).log_volume; atol = 1e-13)

        # Label-permutation invariance on 2-way interactions `(rater, item)` + `(rater, :step)`
        psd_int = (person = 1.0, facets = (rater = 0.6, item = 0.7), step = 0.5,
                   interactions = (rater_item = 0.35, rater_step = 0.25))
        spec_orig = mfrm_spec(tbl; person = :person, score = :score,
            facets = (rater = :rater, item = :item), steps = :item,
            interactions = ((:rater, :item), (:rater, :step)),
            category_levels = 0:2, prior_sd = psd_int,
            levels = (person = ["P$p" for p in 1:n_p], facets = (rater = ["R1", "R2", "R3"], item = ["I1", "I2"])))
        spec_perm = mfrm_spec(tbl; person = :person, score = :score,
            facets = (rater = :rater, item = :item), steps = :item,
            interactions = ((:rater, :item), (:rater, :step)),
            category_levels = 0:2, prior_sd = psd_int,
            levels = (person = ["P$p" for p in 1:n_p], facets = (rater = ["R3", "R1", "R2"], item = ["I2", "I1"])))

        @test !validate_design(spec_orig).prior_symmetry.prior_asymmetry_detected
        @test !validate_design(spec_perm).prior_symmetry.prior_asymmetry_detected

        # Map an arbitrary white vector q_orig -> model coordinates -> equivalent white vector q_perm
        q_orig = randn(MersenneTwister(777), length(initial_params(spec_orig)))
        c_orig = coordinates(spec_orig, q_orig)
        names_orig = parameter_names(spec_orig; scale = :model)
        names_perm = parameter_names(spec_perm; scale = :model)
        val_orig_full = vcat(c_orig.person, c_orig.structural_model)
        val_map = Dict(names_orig[i] => val_orig_full[i] for i in eachindex(names_orig))

        xi_perm_target = [val_map[nm] for nm in spec_perm.operator.model_names]
        # Solve J_model * eta_perm = xi_perm_target, then map eta_perm -> q_perm
        eta_perm = Matrix(spec_perm.operator.J_model) \ xi_perm_target
        q_perm = copy(q_orig)
        for b in spec_perm.prior_blocks
            for (k, ei) in enumerate(b.eta_range)
                q_perm[b.raw_range[k]] = eta_perm[ei] / b.scale_vec[k]
            end
        end
        @test isapprox(logposterior(spec_orig, q_orig), logposterior(spec_perm, q_perm); atol = 1e-12)
        @test isapprox(loglikelihood(spec_orig, q_orig), loglikelihood(spec_perm, q_perm); atol = 1e-12)
        @test isapprox(logprior(spec_orig, q_orig), logprior(spec_perm, q_perm); atol = 1e-12)
    end

    # -----------------------------------------------------------------------
    # 3. Analytic vs ForwardDiff Gradients Across Structured & Custom MRCML
    # -----------------------------------------------------------------------
    @testset "Analytic reverse-mode gradients across interactions, tuple steps, LLTM & MvNormal" begin
        tbl = (
            person = repeat(["P$p" for p in 1:8], inner = 9),
            rater  = repeat(["R1", "R2", "R3"], outer = 24),
            item   = repeat(vcat(fill("I1", 3), fill("I2", 3), fill("I3", 3)), outer = 8),
            score  = rand(MersenneTwister(1234), 0:2, 72),
            f_lin  = repeat(vcat(fill(-1.0, 3), fill(0.0, 3), fill(1.0, 3)), outer = 8),
        )

        # (a) Hierarchical person SD + hierarchical rater*item SD + fixed rater*step SD
        sp_a = mfrm_spec(tbl; person = :person, score = :score,
            facets = (rater = :rater, item = :item), steps = :item, category_levels = 0:2,
            interactions = ((:rater, :item), (:rater, :step)),
            prior_sd = (person = LogNormal(0.0, 0.35),
                        facets = (rater = 0.5, item = 0.7),
                        step = 0.5,
                        interactions = (rater_item = LogNormal(log(0.35), 0.4), rater_step = 0.3)))
        qa = randn(MersenneTwister(11), length(initial_params(sp_a)))
        lpa, ga = logdensity_and_gradient(sp_a, qa)
        ga_fd = ForwardDiff.gradient(x -> logposterior(sp_a, x), qa)
        @test isapprox(lpa, logposterior(sp_a, qa); atol = 1e-14)
        @test maximum(abs.(ga .- ga_fd)) <= 1e-12

        # (b) Tuple cell-owned steps = (:rater, :item) + LLTM with residual
        sp_b = mfrm_spec(tbl; person = :person, score = :score,
            facets = (rater = :rater, item = :item), steps = (:rater, :item), category_levels = 0:2,
            lltm = (item = (features = (:f_lin,), prior = Normal(0.1, 0.8), residual = LogNormal(log(0.25), 0.35)),),
            prior_sd = (person = 1.0, facets = (rater = 0.6,), step = 0.45))
        qb = randn(MersenneTwister(22), length(initial_params(sp_b)))
        lpb, gb = logdensity_and_gradient(sp_b, qb)
        gb_fd = ForwardDiff.gradient(x -> logposterior(sp_b, x), qb)
        @test maximum(abs.(gb .- gb_fd)) <= 1e-12

        # (c) Layer-2 custom TAM design matrix with TAM -1 rater coding:
        #     verify warning under isotropic Normal prior vs zero warning under subspace_isometric_prior!
        # 3 items * 3 raters = 9 generalized items, 3 categories (0,1,2), 6 parameters:
        # [I1, I2, I3, rater1, rater2, step1] + xsi_fixed fixing I1 = -0.5!
        A_tam = zeros(Float64, 9, 3, 6)
        M_tr = zeros(Float64, 7, 6) # expand [I1,I2,I3, R1,R2, R3=-R1-R2, step1]
        M_tr[1, 1] = 1.0; M_tr[2, 2] = 1.0; M_tr[3, 3] = 1.0
        M_tr[4, 4] = 1.0; M_tr[5, 5] = 1.0; M_tr[6, 4] = -1.0; M_tr[6, 5] = -1.0
        M_tr[7, 6] = 1.0
        for ic in 1:3, rc in 1:3
            gi = (ic - 1) * 3 + rc
            for k in 1:2
                A_tam[gi, k + 1, ic] = -Float64(k)
                if rc == 1
                    A_tam[gi, k + 1, 4] = -Float64(k)
                elseif rc == 2
                    A_tam[gi, k + 1, 5] = -Float64(k)
                else
                    A_tam[gi, k + 1, 4] = Float64(k)
                    A_tam[gi, k + 1, 5] = Float64(k)
                end
            end
            A_tam[gi, 2, 6] = -1.0
        end
        resp_wide = fill(NaN, 24, 3)
        pids_w = String[]
        raters_w = String[]
        idx_r = 0
        for p in 1:8, r in 1:3
            idx_r += 1
            push!(pids_w, "P$p")
            push!(raters_w, "R$r")
            for ic in 1:3
                row_match = (p - 1) * 9 + (ic - 1) * 3 + r
                resp_wide[idx_r, ic] = Float64(tbl.score[row_match])
            end
        end
        bmeta_tam = [(; name = :rater, kind = :tam_sum_zero, model_range = 4:6, check_exchangeable_symmetry = true)]
        mnames_tam = ["I1", "I2", "I3", "R1", "R2", "R3", "step1"]

        sp_tam_naive = _MRCML_TEST.from_tam(A_tam, resp_wide;
            facets = (rater = raters_w,), pid = pids_w,
            xsi_fixed = [1 -0.5], # fix I1 = -0.5 -> 5 free parameters [I2, I3, R1, R2, step1]
            parameter_names = ["I1", "I2", "I3", "R1", "R2", "step1"],
            model_transform = M_tr, model_names = mnames_tam, block_meta = bmeta_tam,
            prior = Normal(0.0, 0.7), person_prior_sd = 1.0)
        vd_naive = validate_design(sp_tam_naive)
        @test vd_naive.identified
        @test vd_naive.prior_symmetry.prior_asymmetry_detected
        @test isapprox(vd_naive.prior_symmetry.max_to_min_variance_ratio, 2.0; atol = 1e-10)
        @test any(w -> occursin("prior_variance_asymmetry", w), vd_naive.warnings)

        # Now apply MvNormal with subspace_isometric_prior on [R1, R2]!
        Sig_5 = Matrix{Float64}(0.7^2 * I, 5, 5)
        M_r3 = [1.0 0.0; 0.0 1.0; -1.0 -1.0]
        Sig_5[3:4, 3:4] .= Matrix(cov(_MRCML_TEST.subspace_isometric_prior(M_r3, 0.7)))
        sp_tam_iso = _MRCML_TEST.from_tam(A_tam, resp_wide;
            facets = (rater = raters_w,), pid = pids_w,
            xsi_fixed = [1 -0.5],
            parameter_names = ["I1", "I2", "I3", "R1", "R2", "step1"],
            model_transform = M_tr, model_names = mnames_tam, block_meta = bmeta_tam,
            prior = MvNormal(zeros(5), Symmetric(Sig_5)), person_prior_sd = 1.0)
        vd_iso = validate_design(sp_tam_iso)
        @test vd_iso.identified
        @test !vd_iso.prior_symmetry.prior_asymmetry_detected

        qc = randn(MersenneTwister(33), length(initial_params(sp_tam_iso)))
        lpc, gc = logdensity_and_gradient(sp_tam_iso, qc)
        gc_fd = ForwardDiff.gradient(x -> logposterior(sp_tam_iso, x), qc)
        @test maximum(abs.(gc .- gc_fd)) <= 1e-12
    end

    # -----------------------------------------------------------------------
    # 4. SPQR Rank-Deficiency Refusals (No Silent QR Column-Dropping)
    # -----------------------------------------------------------------------
    @testset "SPQR rank-deficiency detection and deterministic fit refusals" begin
        tbl = (
            person = ["P1", "P1", "P2", "P2", "P3", "P3", "P4", "P4"],
            rater  = ["R1", "R1", "R1", "R1", "R2", "R2", "R2", "R2"],
            item   = ["I1", "I2", "I1", "I2", "I1", "I2", "I1", "I2"],
            score  = [0, 1, 1, 2, 0, 2, 1, 1],
        )
        # Disconnected (P1,P2 only with R1; P3,P4 only with R2) -> rank deficient in finite_connected!
        sp_disc = mfrm_spec(tbl; person = :person, score = :score,
            facets = (rater = :rater, item = :item), steps = :global, category_levels = 0:2,
            interactions = ((:rater, :item),),
            prior_sd = (person = 1.0, facets = (rater = 0.5, item = 0.5), step = 0.5,
                        interactions = (rater_item = 0.3,)))
        @test !validate_design(sp_disc).identified
        @test_throws ArgumentError fit(sp_disc; chains = 2, warmup = 50, ndraws = 50, seed = 1)
        @test_throws ArgumentError fit(sp_disc; method = :jmle)

        # Duplicate columns in custom A -> structural rank deficiency caught by SPQR!
        A_dup = zeros(Float64, 2, 3, 2)
        A_dup[1, 2, 1] = -1.0; A_dup[1, 3, 1] = -2.0
        A_dup[1, 2, 2] = -1.0; A_dup[1, 3, 2] = -2.0
        A_dup[2, 2, 1] = -1.0; A_dup[2, 3, 1] = -2.0
        A_dup[2, 2, 2] = -1.0; A_dup[2, 3, 2] = -2.0 # exact duplicate column across all items!
        sp_dup = _MRCML_TEST.custom_spec(
            (person = ["P1", "P1", "P2", "P2"], item = [1, 2, 1, 2], score = [0, 2, 1, 1]);
            person = :person, score = :score, category_levels = 0:2,
            A = A_dup, item_index = [1, 2, 1, 2],
            prior = Normal(0, 1.0), person_prior_sd = 1.0)
        @test !validate_design(sp_dup).structural_identified
        @test !isempty(validate_design(sp_dup).dependent_structural_columns)
        @test_throws ArgumentError fit(sp_dup; method = :mmle)
        @test_throws ArgumentError fit(sp_dup; chains = 2, warmup = 50, ndraws = 50, seed = 1)
    end

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
            facets = (rater = :rater, item = :item), steps = :item, category_levels = 0:2)
        spec_int_f = mfrm_spec(tbl; person = :person, score = :score,
            facets = (rater = :rater, item = :item), steps = :item, category_levels = 0:2,
            interactions = ((:rater, :item),))

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

        fit_pcm_b = fit(spec_pcm_b; chains = 2, warmup = 150, ndraws = 200, seed = 42)
        fit_int_b = fit(spec_int_b; chains = 2, warmup = 150, ndraws = 200, seed = 43)

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
            @test size(h_loaded.fit.record.run.draws) == (400, length(parameter_names(fit_int_b; scale = :model)))
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
            steps = :global, category_levels = 0:2); method = :mmle)
        f_mr_int = fit(mfrm_spec(tbl_mf; person = :person, score = :score, facets = (rater = :rater, item = :item),
            steps = :global, category_levels = 0:2, interactions = ((:rater, :item),)); method = :mmle)
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
