using BayesianMGMFRM
using BayesianMGMFRM.GlassBox
using BayesianMGMFRM.Legacy
using Distributions: Normal, LogNormal
using ForwardDiff
using LinearAlgebra
using LogDensityProblems
using Random
using Statistics
using Test

const _SIM = BayesianMGMFRM.ScaleIdentifiedMGMFRM
const _EXP = BayesianMGMFRM.Experimental

function _cr4_make_spec(;
        P::Int = 6,
        items = ["I$i" for i in 1:5],
        raters = ["R$r" for r in 1:3],
        K::Int = 4,
        q_matrix::AbstractMatrix{Bool} = Bool[1 0; 1 0; 0 1; 0 1; 0 1],
        seed::Int = 20261122)
    rng = MersenneTwister(seed)
    persons = ["P$p" for p in 1:P]
    p_col = String[]
    i_col = eltype(items)[]
    r_col = eltype(raters)[]
    y_col = Int[]
    for p in persons, it in items, rt in raters
        push!(p_col, p)
        push!(i_col, it)
        push!(r_col, rt)
        push!(y_col, rand(rng, 0:(K - 1)))
    end
    fd = FacetData((; person = p_col, item = i_col, rater = r_col, score = y_col);
        person = :person, item = :item, rater = :rater, score = :score,
        category_levels = 0:(K - 1))
    return mfrm_spec(fd;
        family = :mgmfrm,
        dimensions = size(q_matrix, 2),
        thresholds = :partial_credit,
        q_matrix = Bool.(q_matrix))
end

@testset "CR4: Multiplicative Scale-Identified MGMFRM, Family Harmonization & CmdStan 2.39.0 Parity" begin
    # -----------------------------------------------------------------------
    # 1. Family Contract Harmonization (`4.2`) & Structural Guards
    # -----------------------------------------------------------------------
    @testset "GMFRM vs MGMFRM vs MFRM contract harmonization and input guards" begin
        sp_mgm = _cr4_make_spec()
        sp_gm = mfrm_spec(sp_mgm.data; family = :gmfrm, thresholds = :partial_credit, discrimination = :rater)
        sp_mf = mfrm_spec(sp_mgm.data; family = :mfrm, thresholds = :partial_credit)

        c_mgm = model_family_contract(sp_mgm)
        c_gm  = model_family_contract(sp_gm)
        c_mf  = model_family_contract(sp_mf)

        @test c_mgm.logit_scale == 1.7
        @test c_mgm.step_owner === :item
        @test c_mgm.loading_scope === :ability_only
        @test c_mgm.available_scale_identifications == (:geometric_mean_one, :anchor_item, :prior_only)

        @test c_gm.logit_scale == 1.0
        @test c_gm.step_owner === :rater
        @test c_gm.loading_scope === :entire_linear_predictor
        @test c_gm.available_scale_identifications == (:prior_only,)

        @test c_mf.logit_scale == 1.0
        @test c_mf.step_owner === :item
        @test c_mf.loading_scope === :unit_slope
        @test c_mf.available_scale_identifications == (:unit_slope,)

        tgt_geo = _EXP.scale_identified_target(sp_mgm; log_loading_sd = 0.25)
        ct_geo = contract(tgt_geo)
        @test ct_geo.logit_scale == 1.7
        @test ct_geo.step_owner === :item
        @test ct_geo.loading_scope === :ability_only
        @test ct_geo.rater_consistency_scope === :entire_linear_predictor
        @test ct_geo.scale_identification === :geometric_mean_one
        @test ct_geo.location_identification === :zero_mean_population
        @test ct_geo.available_scale_identifications == (:geometric_mean_one, :anchor_item, :prior_only)
        @test ct_geo.label_permutation_invariant
        @test !ct_geo.prior_asymmetry_detected
        @test _EXP.surface_contract(tgt_geo) == ct_geo
        @test _EXP.surface_contract(sp_mgm; prior = tgt_geo.prior) == ct_geo

        # Reject invalid Q (0 pure items on dim 1), invalid logit_scale, and cross-loaded anchor items
        sp_nopure = _cr4_make_spec(; items = ["I1", "I2", "I3"], q_matrix = Bool[1 1; 1 1; 0 1])
        @test_throws ArgumentError _EXP.scale_identified_target(sp_nopure)
        @test_throws ArgumentError _EXP.ScaleIdentifiedMGMFRMPrior(; logit_scale = 1.5)
        @test_throws ArgumentError _EXP.ScaleIdentifiedMGMFRMPrior(;
            scale_identification = :geometric_mean_one, anchor_items = ["I1", "I3"])
        @test_throws ArgumentError _EXP.ScaleIdentifiedMGMFRMPrior(;
            log_loading_sd = 0.25, log_discrimination_sd = 0.25)

        sp_mixed = _cr4_make_spec(; q_matrix = Bool[1 0; 1 0; 0 1; 0 1; 1 1])
        @test_throws ArgumentError _EXP.scale_identified_target(sp_mixed;
            scale_identification = :anchor_item, anchor_items = ["I5", "I3"])
        @test_throws ArgumentError _EXP.scale_identified_target(sp_mixed;
            scale_identification = :anchor_item, anchor_items = ["I3", "I1"])
        @test_throws ArgumentError _EXP.scale_identified_target(sp_gm)
    end

    # -----------------------------------------------------------------------
    # 2. Exact Subspace + LogNormal Jacobian Cancellation & Constraints
    # -----------------------------------------------------------------------
    @testset "Normalized prior, exact Jacobian cancellation, and model-space identities" begin
        sp_mixed = _cr4_make_spec(; P = 5, items = ["I1", "I2", "I3", "I4", "I5"],
            raters = ["R1", "R2", "R3"], K = 4, q_matrix = Bool[1 0; 1 0; 0 1; 0 1; 1 1])
        sp_edge = _cr4_make_spec(; P = 4, items = ["I1", "I2", "I3", "I4"],
            raters = ["R1"], K = 2, q_matrix = Bool[1 0; 0 1; 0 1; 1 1])

        configs = [
            _EXP.scale_identified_target(sp_mixed;
                scale_identification = :geometric_mean_one,
                location_identification = :zero_mean_population,
                logit_scale = 1.7, log_loading_sd = 0.25,
                ability_logsd_prior = LogNormal(0.1, 0.8)),
            _EXP.scale_identified_target(sp_mixed;
                scale_identification = :geometric_mean_one,
                location_identification = :centered_items_free_mean,
                logit_scale = 1.0, rater_consistency = :fixed_one,
                log_loading_sd = 0.35, ability_mean_sd = 1.2),
            _EXP.scale_identified_target(sp_mixed;
                scale_identification = :anchor_item, anchor_items = Dict(1 => "I2", 2 => "I4"),
                location_identification = :centered_items_free_mean,
                logit_scale = 1.7, log_loading_sd = 0.30),
            _EXP.scale_identified_target(sp_edge;
                scale_identification = :geometric_mean_one,
                location_identification = :centered_items_free_mean),
        ]

        for (ci, tgt) in enumerate(configs)
            rng = MersenneTwister(500 + ci)
            for _ in 1:4
                q = randn(rng, LogDensityProblems.dimension(tgt)) .* 0.65
                c = coordinates(tgt, q)
                # Exact normalized constrained/subspace prior + log-abs-det Jacobian == raw white prior
                lp_sub = _SIM.constrained_subspace_logprior(tgt, c)
                @test abs((lp_sub + c.log_jacobian) - logprior(tgt, q)) <= 1e-13
                @test abs(logprior(tgt, q) + loglikelihood(tgt, q) - logposterior(tgt, q)) <= 1e-13

                # Exact structural constraints
                if tgt.prior.scale_identification === :geometric_mean_one
                    for d in 1:tgt.D
                        pitems = tgt.pure_items_by_dim[d]
                        @test abs(sum(c.log_loading[i, d] for i in pitems)) <= 1e-14
                        @test isapprox(prod(c.loading[i, d] for i in pitems), 1.0; atol = 1e-13)
                    end
                else
                    for d in 1:tgt.D
                        @test c.loading[tgt.anchor_item_indices[d], d] == 1.0
                    end
                end

                if tgt.prior.location_identification === :zero_mean_population
                    @test all(iszero, c.ability_mean)
                else
                    for d in 1:tgt.D
                        @test abs(sum(c.item[i] for i in tgt.pure_items_by_dim[d])) <= 1e-14
                    end
                end

                @test abs(sum(c.rater)) <= 1e-14
                @test abs(sum(c.log_consistency)) <= 1e-14
                @test isapprox(prod(c.consistency), 1.0; atol = 1e-13)
                for i in 1:tgt.I
                    @test abs(sum(view(c.steps, i, :))) <= 1e-14
                end

                # Exact identity: a^std_{id} == tilde_a_{id} * sigma_{theta_d}
                for (i, d) in tgt.active_pairs
                    @test abs(c.standardized_loading[i, d] - c.loading[i, d] * c.ability_sd[d]) <= 1e-14
                end
            end
        end
    end

    # -----------------------------------------------------------------------
    # 3. Item-Label & Rater-Label Permutation Invariance (`<= 1e-13`)
    # -----------------------------------------------------------------------
    @testset "Exact item-label and rater-label permutation invariance on :geometric_mean_one" begin
        rng = MersenneTwister(2026112204)
        orig_items = ["I1", "I2", "I3", "I4", "I5", "I6"]
        orig_q = Bool[
            1 0;  # I1 pure dim 1
            1 0;  # I2 pure dim 1
            1 0;  # I3 pure dim 1
            0 1;  # I4 pure dim 2
            0 1;  # I5 pure dim 2
            1 1;  # I6 cross-loaded
        ]
        orig_raters = ["R1", "R2", "R3", "R4"]
        persons = ["P1", "P2"]

        # Generate rating rows as unordered records, then declare two permuted level orderings
        p_col = String[]; i_col = String[]; r_col = String[]; y_col = Int[]
        for p in persons, it in orig_items, rt in orig_raters
            push!(p_col, p); push!(i_col, it); push!(r_col, rt); push!(y_col, rand(rng, 0:3))
        end

        perm_item_idx = [3, 6, 1, 5, 2, 4] # ["I3", "I6", "I1", "I5", "I2", "I4"]
        perm_items = orig_items[perm_item_idx]
        perm_q = orig_q[perm_item_idx, :]
        perm_rater_idx = [3, 1, 4, 2]      # ["R3", "R1", "R4", "R2"]
        perm_raters = orig_raters[perm_rater_idx]

        # Build FacetData with explicit level orders via prepended order-seeding or Categorical-free remapping:
        # FacetData orders string levels in appearance/sorted order unless integer codes are used,
        # so map labels to integer IDs 1..I and 1..R representing the two label permutations!
        i_map_orig = Dict(lbl => k for (k, lbl) in enumerate(orig_items))
        i_map_perm = Dict(lbl => k for (k, lbl) in enumerate(perm_items))
        r_map_orig = Dict(lbl => k for (k, lbl) in enumerate(orig_raters))
        r_map_perm = Dict(lbl => k for (k, lbl) in enumerate(perm_raters))

        fd_orig = FacetData((
            person = p_col,
            item = [i_map_orig[x] for x in i_col],
            rater = [r_map_orig[x] for x in r_col],
            score = y_col,
        ); person = :person, item = :item, rater = :rater, score = :score, category_levels = 0:3)

        fd_perm = FacetData((
            person = p_col,
            item = [i_map_perm[x] for x in i_col],
            rater = [r_map_perm[x] for x in r_col],
            score = y_col,
        ); person = :person, item = :item, rater = :rater, score = :score, category_levels = 0:3)

        sp_orig = mfrm_spec(fd_orig; family = :mgmfrm, dimensions = 2, thresholds = :partial_credit, q_matrix = orig_q)
        sp_perm = mfrm_spec(fd_perm; family = :mgmfrm, dimensions = 2, thresholds = :partial_credit, q_matrix = perm_q)

        for loc_mode in (:zero_mean_population, :centered_items_free_mean)
            pr = _EXP.ScaleIdentifiedMGMFRMPrior(;
                scale_identification = :geometric_mean_one,
                location_identification = loc_mode,
                logit_scale = 1.7,
                log_loading_sd = 0.25,
                item_sd = 1.1,
                rater_sd = 0.8,
                log_consistency_sd = 0.45,
                step_sd = 0.9,
            )
            t_o = _EXP.scale_identified_target(sp_orig, pr)
            t_p = _EXP.scale_identified_target(sp_perm, pr)
            @test LogDensityProblems.dimension(t_o) == LogDensityProblems.dimension(t_p)

            # Construct exact orthogonal transport maps in BigFloat -> Float64 for pure-item & rater blocks
            helmert_big(J::Int) = [i <= k ? inv(sqrt(BigFloat(k) * BigFloat(k + 1))) :
                (i == k + 1 ? -BigFloat(k) / sqrt(BigFloat(k) * BigFloat(k + 1)) : BigFloat(0))
                for i in 1:J, k in 1:(J - 1)]
            O_pure = map(1:2) do d
                orig_pure_lbls = [orig_items[i] for i in t_o.pure_items_by_dim[d]]
                perm_pure_lbls = [perm_items[i] for i in t_p.pure_items_by_dim[d]]
                Id = length(orig_pure_lbls)
                C_d = helmert_big(Id)
                P_d = [orig_pure_lbls[j] == perm_pure_lbls[i] ? BigFloat(1) : BigFloat(0) for i in 1:Id, j in 1:Id]
                Q_d_big = C_d' * P_d * C_d
                Q_d = Float64.(Q_d_big)
                @test isapprox(Q_d' * Q_d, Matrix{Float64}(I, Id - 1, Id - 1); atol = 1e-14)
                Q_d_big
            end
            C_r_big = helmert_big(4)
            P_r_big = [orig_raters[j] == perm_raters[i] ? BigFloat(1) : BigFloat(0) for i in 1:4, j in 1:4]
            O_r_big = C_r_big' * P_r_big * C_r_big
            O_r = Float64.(O_r_big)
            @test isapprox(O_r' * O_r, Matrix{Float64}(I, 3, 3); atol = 1e-14)

            for seed in (11, 22, 33)
                q_o = randn(MersenneTwister(seed), LogDensityProblems.dimension(t_o)) .* 0.5
                q_p = copy(q_o)

                for d in 1:2
                    q_p[t_p.pure_loading_ranges[d]] .= Float64.(O_pure[d] * BigFloat.(q_o[t_o.pure_loading_ranges[d]]))
                end
                # Single cross-loaded item "I6" has 2 active loadings (dim 1, dim 2) in identical dim order
                q_p[t_p.cross_loading_range] .= q_o[t_o.cross_loading_range]

                if loc_mode === :zero_mean_population
                    for (i_new, lbl) in enumerate(perm_items)
                        i_old = i_map_orig[lbl]
                        q_p[t_p.item_free_range[i_new]] = q_o[t_o.item_free_range[i_old]]
                    end
                else
                    for d in 1:2
                        q_p[t_p.pure_item_ranges[d]] .= Float64.(O_pure[d] * BigFloat.(q_o[t_o.pure_item_ranges[d]]))
                    end
                    q_p[t_p.cross_item_range] .= q_o[t_o.cross_item_range]
                end

                q_p[t_p.rater_range] .= Float64.(O_r_big * BigFloat.(q_o[t_o.rater_range]))
                q_p[t_p.consistency_range] .= Float64.(O_r_big * BigFloat.(q_o[t_o.consistency_range]))
                for (i_new, lbl) in enumerate(perm_items)
                    i_old = i_map_orig[lbl]
                    q_p[t_p.step_ranges[i_new]] .= q_o[t_o.step_ranges[i_old]]
                end

                @test maximum(abs.(pointwise_loglikelihood(t_o, q_o) .- pointwise_loglikelihood(t_p, q_p))) <= 1e-14
                @test abs(logprior(t_o, q_o) - logprior(t_p, q_p)) <= 1e-13
                @test abs(loglikelihood(t_o, q_o) - loglikelihood(t_p, q_p)) <= 1e-13
                @test abs(logposterior(t_o, q_o) - logposterior(t_p, q_p)) <= 1e-13
            end
        end
    end

    # -----------------------------------------------------------------------
    # 4. ForwardDiff (`<= 1e-12`) & Native CmdStan 2.39.0 Parity (`<= 1e-12`)
    # -----------------------------------------------------------------------
    @testset "Analytical gradient vs ForwardDiff and native CmdStan 2.39.0 fixed-point parity" begin
        sp_1d_4k = _cr4_make_spec(; P = 6, items = ["I1", "I2", "I3", "I4"],
            raters = ["R1", "R2", "R3"], K = 4, q_matrix = trues(4, 1), seed = 701)
        sp_1d_bin = _cr4_make_spec(; P = 5, items = ["I1", "I2", "I3"],
            raters = ["R1", "R2"], K = 2, q_matrix = trues(3, 1), seed = 702)
        sp_2d_pure = _cr4_make_spec(; P = 6, items = ["I1", "I2", "I3", "I4", "I5"],
            raters = ["R1", "R2", "R3", "R4"], K = 4, q_matrix = Bool[1 0; 1 0; 0 1; 0 1; 0 1], seed = 703)
        sp_2d_mix = _cr4_make_spec(; P = 6, items = ["I1", "I2", "I3", "I4", "I5"],
            raters = ["R1", "R2", "R3"], K = 3, q_matrix = Bool[1 0; 1 0; 0 1; 0 1; 1 1], seed = 704)
        sp_singleton = _cr4_make_spec(; P = 4, items = ["I1", "I2", "I3", "I4"],
            raters = ["R1"], K = 3, q_matrix = Bool[1 0; 0 1; 0 1; 1 1], seed = 705)

        parity_targets = [
            ("d1_geo_zero_17", _EXP.scale_identified_target(sp_1d_4k;
                scale_identification = :geometric_mean_one, location_identification = :zero_mean_population,
                logit_scale = 1.7, log_loading_sd = 0.25)),
            ("d1_geo_cent_10_bin", _EXP.scale_identified_target(sp_1d_bin;
                scale_identification = :geometric_mean_one, location_identification = :centered_items_free_mean,
                logit_scale = 1.0, rater_consistency = :fixed_one, log_loading_sd = 0.35)),
            ("d2_geo_zero_17", _EXP.scale_identified_target(sp_2d_pure;
                scale_identification = :geometric_mean_one, location_identification = :zero_mean_population,
                logit_scale = 1.7, log_loading_sd = 0.25)),
            ("d2_geo_cent_10", _EXP.scale_identified_target(sp_2d_pure;
                scale_identification = :geometric_mean_one, location_identification = :centered_items_free_mean,
                logit_scale = 1.0, log_loading_sd = 0.30, ability_mean_sd = 1.2)),
            ("d2_mix_geo_cent_17", _EXP.scale_identified_target(sp_2d_mix;
                scale_identification = :geometric_mean_one, location_identification = :centered_items_free_mean,
                logit_scale = 1.7, log_loading_sd = 0.30)),
            ("d2_anc_zero_17", _EXP.scale_identified_target(sp_2d_pure;
                scale_identification = :anchor_item, anchor_items = ["I2", "I4"],
                location_identification = :zero_mean_population, logit_scale = 1.7, log_loading_sd = 0.25)),
            ("d2_mix_anc_cent_10", _EXP.scale_identified_target(sp_2d_mix;
                scale_identification = :anchor_item, anchor_items = Dict(1 => "I1", 2 => "I3"),
                location_identification = :centered_items_free_mean, logit_scale = 1.0, log_loading_sd = 0.40)),
            ("d2_singleton_r1", _EXP.scale_identified_target(sp_singleton;
                scale_identification = :geometric_mean_one, location_identification = :centered_items_free_mean,
                logit_scale = 1.7, log_loading_sd = 0.25)),
        ]

        stan_chk = BayesianMGMFRM.cmdstan_backend_check(; include_paths = true)
        has_stan = stan_chk.runtime_ready

        max_fd_err = 0.0
        max_stan_lp_err = 0.0
        max_stan_grad_err = 0.0

        mktempdir() do dir
            exe_path = if has_stan
                make_prog = BayesianMGMFRM._cmdstan_configured_program("MAKE", ("make", "gmake"))
                stem = joinpath(dir, "mgmfrm_cr4_ref")
                write(stem * ".stan", _SIM.stan_code())
                BayesianMGMFRM._cmdstan_run(Cmd(`$make_prog -f makefile $stem`; dir = stan_chk.cmdstan_root), :model_compile)
                BayesianMGMFRM._cmdstan_executable_path(stem)
            else
                nothing
            end

            for (idx_t, (label, tgt)) in enumerate(parity_targets)
                D_dim = LogDensityProblems.dimension(tgt)
                pts = [
                    zeros(Float64, D_dim),
                    [0.25 * sin(0.6 * j) for j in 1:D_dim],
                    randn(MersenneTwister(1900 + 13 * idx_t), D_dim) .* 0.55,
                    randn(MersenneTwister(2900 + 17 * idx_t), D_dim) .* 0.45,
                ]
                j_lps = Float64[]
                j_grads = Vector{Float64}[]
                for q in pts
                    lp, g = logdensity_and_gradient(tgt, q)
                    g_fd = ForwardDiff.gradient(x -> logposterior(tgt, x), q)
                    @test abs(lp - logposterior(tgt, q)) <= 1e-13
                    fd_err = maximum(abs.(g .- g_fd))
                    fd_err > max_fd_err && (max_fd_err = fd_err)
                    @test fd_err <= 1e-12
                    push!(j_lps, lp)
                    push!(j_grads, g)

                    # Verify SamplingTarget bijection, exact Jacobian, and analytical gradient
                    # for both default `:auto` (PRS centered/noncentered) and volume-preserving `:noncentered`
                    st = _SIM.SamplingTarget(tgt)
                    u_pt = _SIM.from_raw(st, q)
                    @test maximum(abs.(_SIM.to_raw(st, u_pt) .- q)) <= 1e-13
                    lp_u, g_u = LogDensityProblems.logdensity_and_gradient(st, u_pt)
                    g_u_fd = ForwardDiff.gradient(z -> LogDensityProblems.logdensity(st, z), u_pt)
                    @test maximum(abs.(g_u .- g_u_fd)) <= 1e-12
                    J_st = ForwardDiff.jacobian(z -> _SIM.to_raw(st, z), u_pt)
                    @test abs((lp_u - lp) - logabsdet(J_st)[1]) <= 1e-13
                    st_ncp = _SIM.SamplingTarget(tgt; person_coordinates = :noncentered)
                    u_ncp = _SIM.from_raw(st_ncp, q)
                    @test abs(logabsdet(ForwardDiff.jacobian(z -> _SIM.to_raw(st_ncp, z), u_ncp))[1]) <= 1e-13
                end

                if exe_path !== nothing
                    d_path = joinpath(dir, "$(label)_data.json")
                    p_path = joinpath(dir, "$(label)_pts.json")
                    o_path = joinpath(dir, "$(label)_out.csv")
                    write(d_path, BayesianMGMFRM.JSON3.write(stan_data(tgt)))
                    write(p_path, BayesianMGMFRM.JSON3.write((; params_r = pts)))
                    BayesianMGMFRM._cmdstan_run(
                        `$exe_path log_prob unconstrained_params=$p_path jacobian=1 data file=$d_path output file=$o_path sig_figs=18 refresh=0`,
                        :density_check,
                    )
                    csv = BayesianMGMFRM._cmdstan_read_csv(o_path, length(pts))
                    @test csv.header == ["lp__"; ["g_q.$i" for i in 1:D_dim]]
                    for r in eachindex(pts)
                        lp_err = abs(csv.values[r, 1] - j_lps[r])
                        gr_err = maximum(abs.(csv.values[r, 2:end] .- j_grads[r]))
                        lp_err > max_stan_lp_err && (max_stan_lp_err = lp_err)
                        gr_err > max_stan_grad_err && (max_stan_grad_err = gr_err)
                        @test lp_err <= 1e-12
                        @test gr_err <= 1e-12
                    end
                end
            end
        end
        @test max_fd_err <= 1e-12
        println("CR4 Parity Metrics: has_stan=$has_stan, max_fd_err=$(max_fd_err), max_stan_lp_err=$(max_stan_lp_err), max_stan_grad_err=$(max_stan_grad_err)")
        if has_stan
            @test max_stan_lp_err <= 1e-12
            @test max_stan_grad_err <= 1e-12
        end
    end

    # -----------------------------------------------------------------------
    # 5. Layer-1, Layer-2, Experimental & PortableHandoff Lifecycle Smoke Test
    # -----------------------------------------------------------------------
    @testset "Layer-1/Layer-2 lifecycle, persistence, and PortableHandoff roundtrip" begin
        sp = _cr4_make_spec(; P = 6, items = ["I1", "I2", "I3", "I4"],
            raters = ["R1", "R2", "R3"], K = 3, q_matrix = Bool[1 0; 1 0; 0 1; 0 1], seed = 888)
        pr_geo = _EXP.ScaleIdentifiedMGMFRMPrior(; scale_identification = :geometric_mean_one, log_loading_sd = 0.25)
        pr_anc = _EXP.ScaleIdentifiedMGMFRMPrior(; scale_identification = :anchor_item, anchor_items = ["I2", "I4"], log_loading_sd = 0.25)

        tgt = _EXP.scale_identified_target(sp, pr_geo)
        tgt_alt = with_options(tgt; logit_scale = 1.0)
        @test contract(tgt_alt).logit_scale == 1.0
        @test validate_design(tgt).passed && validate_design(tgt).identified
        @test design_summary(tgt).n_observations == sp.data.n
        @test length(prior_draw(tgt; seed = 7)) == LogDensityProblems.dimension(tgt)
        sim = simulate(tgt; seed = 8)
        @test length(sim.scores) == sp.data.n
        ppc_prior = _EXP.prior_predictive_check(sp; prior = pr_geo, ndraws = 8, seed = 9)
        @test size(ppc_prior.replicated_scores) == (8, sp.data.n)

        f_geo = _EXP.fit(sp; prior = pr_geo, chains = 2, warmup = 30, ndraws = 30, seed = 91)
        f_anc = fit(_EXP.scale_identified_target(sp, pr_anc); chains = 2, warmup = 30, ndraws = 30, seed = 92)

        q0 = initial_params(f_geo)
        @test logprior(f_geo, q0) + loglikelihood(f_geo, q0) ≈ logposterior(f_geo, q0) atol = 1e-12
        @test sum(pointwise_loglikelihood(f_geo, q0)) ≈ loglikelihood(f_geo, q0) atol = 1e-12
        @test size(pointwise_loglikelihood(f_geo).log_density) == (60, sp.data.n)

        ps = posterior_summary(f_geo; scale = :model, interval = 0.90)
        pnames = [r.parameter for r in ps.rows]
        @test "ability_sd[dim=1]" in pnames
        @test "loading[I1, dim=1]" in pnames
        @test "standardized_loading[I1, dim=1]" in pnames
        @test only(filter(r -> r.parameter == "ability_mean[dim=1]", ps.rows)).structurally_fixed
        @test only(filter(r -> r.parameter == "loading[I2, dim=1]", posterior_summary(f_anc).rows)).structurally_fixed
        @test !only(filter(r -> r.parameter == "standardized_loading[I2, dim=1]", posterior_summary(f_anc).rows)).structurally_fixed

        @test length(posterior_mcse(f_geo; scale = :model)) == length(pnames)
        @test qualify(f_geo).telemetry_complete
        @test facet_summary(f_geo; facet = :standardized_loading).n_levels == 4
        @test length(category_summary(f_geo).categories) == 3

        c_load = contrast(f_geo; facet = :standardized_loading, left = "I2", right = "I1", dimension = 1, level = 0.90)
        c_direct = contrast(f_geo; left = "standardized_loading[I2, dim=1]", right = "standardized_loading[I1, dim=1]", level = 0.90)
        @test c_load.mean == c_direct.mean
        @test isfinite(predict(f_geo; rows = [1, 2]).mean[1, 1])
        @test event_probabilities(f_geo; rows = [1, 2]).schema == _SIM.PREDICTION_SCHEMA
        @test predictive_check(f_geo; seed = 5, ndraws = 10).n_replications == 10
        @test isfinite(waic(f_geo).elpd_waic)
        @test isfinite(psis_loo(f_geo).elpd_loo)
        @test criteria(f_geo).psis_loo.elpd_loo ≈ psis_loo(f_geo).elpd_loo atol = 1e-12
        @test ranking(f_geo; dimension = 1, top_k = 2).n_levels == 6
        @test 0.0 <= reliability(f_geo; dimension = 1).reliability <= 1.0
        @test classification(f_geo; dimension = 1, cutoff = 0.0).cohort.n_people == 6
        @test isfinite(compare_models("geo" => f_geo, "anc" => f_anc).rows[1].elpd)

        mktempdir() do dir
            fit_path = joinpath(dir, "cr4_fit.jls")
            save_fit(fit_path, f_geo)
            f_loaded = load_fit(fit_path)
            @test posterior_summary(f_loaded; scale = :model, interval = 0.90).rows == ps.rows

            rep_path = joinpath(dir, "cr4_report.json")
            rcpt = save_report(rep_path, f_geo; return_receipt = true)
            rep_loaded = load_report(rep_path; expected_sha256 = rcpt.sha256)
            @test String(rep_loaded.schema) == _SIM.REPORT_SCHEMA

            h_obj = BayesianMGMFRM.PortableHandoff.export_handoff(f_geo; scale = :model, include_log_lik = true, include_log_prior = true)
            h_path = joinpath(dir, "cr4_handoff.json")
            h_rcpt = save_report(h_path, h_obj; return_receipt = true)
            h_loaded = load_report(h_path; expected_sha256 = h_rcpt.sha256)
            @test isapprox(posterior_summary(h_loaded; parameters = ["standardized_loading[I1, dim=1]"]).rows[1].mean,
                only(filter(r -> r.parameter == "standardized_loading[I1, dim=1]", ps.rows)).mean; atol = 1e-12)
        end
    end
end
