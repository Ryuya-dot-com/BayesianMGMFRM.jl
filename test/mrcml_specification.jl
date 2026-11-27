module MRCMLSpecificationTests
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

@testset "MRCML specification, constraints and gradients" begin
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

end
end
