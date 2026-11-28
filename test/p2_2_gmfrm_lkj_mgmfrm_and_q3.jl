using Test
using BayesianMGMFRM
using BayesianMGMFRM.GlassBox
import Distributions: Normal, LogNormal, TDist, LocationScale, truncated
using ForwardDiff
using LinearAlgebra
using LogDensityProblems
using Random
using Statistics

const _P22_SIM = BayesianMGMFRM.ScaleIdentifiedMGMFRM
const _P22_EXP = BayesianMGMFRM.Experimental

@testset "Fisher-z tails retain their density without correlation clipping" begin
    for z in (0.0, -0.5, 0.5, -10.0, 10.0, -20.0, 20.0, -100.0, 100.0)
        # Independent high-precision identity, avoiding the Float64 tanh boundary.
        reference = Float64(-2log(cosh(BigFloat(z))))
        @test _P22_SIM._logsech2(z) ≈ reference atol = 3e-14 rtol = 0
        @test ForwardDiff.derivative(_P22_SIM._logsech2, z) ≈ -2tanh(z) atol = 1e-14
    end
end

function _p22_make_balanced_table(; P::Int = 16, I::Int = 4, R::Int = 3, K::Int = 4, seed::Int = 20261125)
    rng = MersenneTwister(seed)
    persons = String[]
    items = String[]
    raters = String[]
    scores = Int[]
    perf_ids = String[]
    assess_ids = String[]
    for p in 1:P
        r_pair = mod1.((p, p + 1), R)
        perf_id = "Perf_$(lpad(p, 2, '0'))"
        for r in r_pair
            ass_id = "Ass_$(lpad(p, 2, '0'))_R$r"
            for i in 1:I
                push!(persons, "P$(lpad(p, 2, '0'))")
                push!(items, "I$i")
                push!(raters, "R$r")
                push!(scores, rand(rng, 0:(K - 1)))
                push!(perf_ids, perf_id)
                push!(assess_ids, ass_id)
            end
        end
    end
    # Ensure every category in 0:(K-1) appears for every item and rater
    idx = 1
    for i in 1:I, k in 0:(K - 1)
        scores[mod1(idx, length(scores))] = k
        idx += 1
    end
    return (;
        person = persons,
        item = items,
        rater = raters,
        score = scores,
        performance = perf_ids,
        assessment = assess_ids,
    )
end

@testset "P2-2: Unified Layer-1 Dispatch, GMFRM, LKJ ScaleIdentifiedMGMFRM & 1D Yen Q3 Diagnostics" begin
    # -----------------------------------------------------------------------
    # 1. Layer-1 Dispatch & Root Export Freeze (41 exports)
    # -----------------------------------------------------------------------
    @testset "Layer-1 mfrm_spec / fit dispatch and paradigm guards" begin
        @test length(filter(s -> s !== :BayesianMGMFRM, names(BayesianMGMFRM))) == 41

        tbl = _p22_make_balanced_table(; P = 10, I = 4, R = 3, K = 4, seed = 101)
        Q2 = Bool[1 0; 1 0; 0 1; 0 1]

        # Paradigm-exclusivity guards
        @test_throws ArgumentError mfrm_spec(tbl;
            person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3, slope = :rater)
        @test_throws ArgumentError mfrm_spec(tbl;
            person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3, slope = :rater, prior = :none)
        @test_throws ArgumentError mfrm_spec(tbl;
            person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3, q_matrix = Q2, prior = :none)

        # Table-based Layer-1 GMFRM (rater, item, both; global, item, rater steps)
        t_gm_r = mfrm_spec(tbl;
            person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :rater, category_levels = 0:3, slope = :rater, prior = :default)
        @test t_gm_r isa _P22_SIM.Target
        @test t_gm_r.prior.family_tag === :gmfrm
        @test t_gm_r.prior.ability_sd_family === :half_normal
        @test t_gm_r.step_owner === :rater
        @test t_gm_r.prior.item_slopes === :fixed_one
        @test t_gm_r.prior.rater_consistency === :estimated_positive
        @test_throws ArgumentError fit(t_gm_r; method = :mmle)

        t_gm_i = mfrm_spec(tbl;
            person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3, slope = :item, prior = :default)
        @test t_gm_i.prior.item_slopes === :estimated_positive
        @test t_gm_i.prior.item_slope_scope === :entire_linear_predictor
        @test t_gm_i.prior.rater_consistency === :fixed_one
        @test t_gm_i.step_owner === :item

        # Table-based Layer-1 LKJ-correlated 2D ScaleIdentifiedMGMFRM
        t_mg_lkj = mfrm_spec(tbl;
            person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3, q_matrix = Q2,
            dimension_labels = ["Accuracy", "Fluency"],
            correlation = :lkj, lkj_eta = 2.0, prior = :default)
        @test t_mg_lkj isa _P22_SIM.Target
        @test t_mg_lkj.prior.family_tag === :mgmfrm
        @test t_mg_lkj.prior.latent_correlation === :lkj
        @test t_mg_lkj.prior.lkj_eta == 2.0
        @test t_mg_lkj.prior.ability_sd_family === :half_normal
        @test "latent_correlation[dim=1, dim=2]" in parameter_names(t_mg_lkj; scale = :model)

        explicit = _P22_SIM.Prior(; step_owner = :rater)
        @test mfrm_spec(tbl; q_matrix = Q2, category_levels = 0:3, prior = explicit).step_owner === :rater
        @test_throws ArgumentError mfrm_spec(tbl; q_matrix = Q2, category_levels = 0:3,
            prior = explicit, steps = :item)
        @test_throws ArgumentError mfrm_spec(tbl; q_matrix = Q2, category_levels = 0:3,
            prior = explicit, correlation = :lkj)
        @test_throws ArgumentError mfrm_spec(tbl; category_levels = 0:3,
            prior = :default, slope = :rater, correlation = :lkj)

        # FacetData isometric bridges for GMFRM and MGMFRM
        fd = FacetData(tbl; person = :person, item = :item, rater = :rater, score = :score, category_levels = 0:3)
        t_fd_gm = mfrm_spec(fd; family = :gmfrm, prior = :default, slope = :rater, steps = :global)
        @test t_fd_gm isa _P22_SIM.Target && t_fd_gm.step_owner === :global
        t_fd_mg = mfrm_spec(fd; family = :mgmfrm, dimensions = 2, q_matrix = Q2, correlation = :lkj, prior = :default)
        @test t_fd_mg isa _P22_SIM.Target && t_fd_mg.prior.latent_correlation === :lkj
        @test_throws ArgumentError mfrm_spec(fd; family = :mgmfrm, dimensions = 2,
            q_matrix = Q2, prior = explicit, steps = :item)
        @test_throws ArgumentError mfrm_spec(fd; family = :mgmfrm, dimensions = 2,
            q_matrix = Q2, prior = explicit, correlation = :lkj)
    end

    @testset "Q3 respects separate assessments of the same person and rater" begin
        original = _p22_make_balanced_table(; P = 8)
        repeated = map((x, k) -> k in (:performance, :assessment) ? vcat(x, x .* "_second") : vcat(x, x),
            values(original), keys(original))
        tbl = NamedTuple{keys(original)}(repeated)
        base = (; person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3, prior = :default)
        for (events, expected) in (((; assessment = :assessment), :assessment_id),
                ((; performance = :performance), :performance_and_rater),
                ((;), :person_and_other_facets))
            source = isempty(events) ? original : tbl
            t = mfrm_spec(source; base..., events...)
            item = only(filter(b -> b.name === :item, t.facets))
            other = filter(b -> b.name !== :item, t.facets)
            cells = BayesianMGMFRM.AdditiveFacets._build_q3_unit_cells(t, item, other, :event)
            @test cells.U == length(unique(source.assessment))
            @test cells.max_cell == 1
            @test cells.binding === expected
        end
    end

    # -----------------------------------------------------------------------
    # 2. ForwardDiff, SamplingTarget Jacobians & Live CmdStan 2.39.0 Parity (<= 1e-12)
    # -----------------------------------------------------------------------
    @testset "ForwardDiff, SamplingTarget & CmdStan 2.39.0 fixed-point parity (<= 1e-12)" begin
        tbl_5 = _p22_make_balanced_table(; P = 6, I = 5, R = 3, K = 4, seed = 202)
        tbl_6 = _p22_make_balanced_table(; P = 6, I = 6, R = 3, K = 3, seed = 203)
        fd_5 = FacetData(tbl_5; person = :person, item = :item, rater = :rater, score = :score, category_levels = 0:3)
        fd_6 = FacetData(tbl_6; person = :person, item = :item, rater = :rater, score = :score, category_levels = 0:2)

        sp_2d_mix = mfrm_spec(fd_5; family = :mgmfrm, dimensions = 2, q_matrix = Bool[1 0; 1 0; 0 1; 0 1; 1 1])
        sp_3d = mfrm_spec(fd_6; family = :mgmfrm, dimensions = 3, q_matrix = Bool[1 0 0; 1 0 0; 0 1 0; 0 1 0; 0 0 1; 0 0 1])

        hn1 = truncated(Normal(0.0, 1.0), 0.0, Inf)
        ht4 = truncated(LocationScale(0.0, 0.85, TDist(4.0)), 0.0, Inf)
        ln05 = LogNormal(0.0, 0.5)

        targets = [
            ("mg2d_geo_lkj2_hn_free", _P22_SIM.model(sp_2d_mix; prior = _P22_SIM.Prior(;
                scale_identification = :geometric_mean_one, location_identification = :centered_items_free_mean,
                ability_sd_prior = hn1, latent_correlation = :lkj, lkj_eta = 2.0))),
            ("mg2d_geo_lkj1_ht4_zero", _P22_SIM.model(sp_2d_mix; prior = _P22_SIM.Prior(;
                scale_identification = :geometric_mean_one, location_identification = :zero_mean_population,
                ability_sd_prior = ht4, latent_correlation = :lkj, lkj_eta = 1.0, logit_scale = 1.0))),
            ("mg2d_anc_lkj35_ln_free", _P22_SIM.model(sp_2d_mix; prior = _P22_SIM.Prior(;
                scale_identification = :anchor_item, anchor_items = [1, 3],
                location_identification = :centered_items_free_mean,
                ability_sd_prior = ln05, latent_correlation = :lkj, lkj_eta = 3.5))),
            ("mg3d_geo_lkj2_hn_free", _P22_SIM.model(sp_3d; prior = _P22_SIM.Prior(;
                scale_identification = :geometric_mean_one, location_identification = :centered_items_free_mean,
                ability_sd_prior = hn1, latent_correlation = :lkj, lkj_eta = 2.0))),
            ("mg3d_geo_lkj15_ht_zero", _P22_SIM.model(sp_3d; prior = _P22_SIM.Prior(;
                scale_identification = :geometric_mean_one, location_identification = :zero_mean_population,
                ability_sd_prior = ht4, rater_consistency = :fixed_one,
                latent_correlation = :lkj, lkj_eta = 1.5, logit_scale = 1.0))),
            ("gmfrm_rater_global_hn", _P22_SIM.gmfrm_model(fd_5; slope = :rater, steps = :global, ability_sd_prior = hn1)),
            ("gmfrm_rater_item_hn", _P22_SIM.gmfrm_model(fd_5; slope = :rater, steps = :item, ability_sd_prior = hn1)),
            ("gmfrm_rater_rater_ht", _P22_SIM.gmfrm_model(fd_5; slope = :rater, steps = :rater, ability_sd_prior = ht4)),
            ("gmfrm_item_item_hn", _P22_SIM.gmfrm_model(fd_5; slope = :item, steps = :item, ability_sd_prior = hn1)),
            ("gmfrm_both_rater_ln", _P22_SIM.gmfrm_model(fd_5; slope = :both, steps = :rater, ability_sd_prior = ln05)),
        ]

        stan_chk = BayesianMGMFRM.cmdstan_backend_check(; include_paths = true)
        has_stan = stan_chk.runtime_ready
        max_fd_err = 0.0
        max_stan_lp_err = 0.0
        max_stan_grad_err = 0.0

        mktempdir() do dir
            exe_path = nothing
            lkj_ref_exe = nothing
            if has_stan
                make_prog = BayesianMGMFRM._cmdstan_configured_program("MAKE", ("make", "gmake"))
                stem = joinpath(dir, "p22_mgmfrm")
                write(stem * ".stan", _P22_SIM.stan_code())
                BayesianMGMFRM._cmdstan_run(Cmd(`$make_prog -f makefile $stem`; dir = stan_chk.cmdstan_root), :model_compile)
                exe_path = BayesianMGMFRM._cmdstan_executable_path(stem)

                # Independent Stan built-in `cholesky_factor_corr[D]` reference check
                lkj_ref_stem = joinpath(dir, "lkj_builtin_ref")
                write(lkj_ref_stem * ".stan", """
                data {
                  int<lower=2, upper=3> D;
                  real<lower=0> eta;
                }
                parameters {
                  cholesky_factor_corr[D] L_Omega;
                }
                model {
                  target += lkj_corr_cholesky_lpdf(L_Omega | eta);
                }
                """)
                BayesianMGMFRM._cmdstan_run(Cmd(`$make_prog -f makefile $lkj_ref_stem`; dir = stan_chk.cmdstan_root), :model_compile)
                lkj_ref_exe = BayesianMGMFRM._cmdstan_executable_path(lkj_ref_stem)

                for (D_chk, eta_chk) in ((2, 2.0), (2, 0.8), (3, 2.0), (3, 1.5))
                    n_cpc = div(D_chk * (D_chk - 1), 2)
                    # Note: Stan's built-in `cholesky_factor_corr` maps unconstrained y via z = tanh(y),
                    # identical to our Fisher-z parameterization! Verify constant difference == 0 to 1e-13!
                    sp_chk = D_chk == 2 ? sp_2d_mix : sp_3d
                    t_chk = _P22_SIM.model(sp_chk; prior = _P22_SIM.Prior(;
                        latent_correlation = :lkj, lkj_eta = eta_chk))
                    pts_cpc = [
                        zeros(Float64, n_cpc),
                        n_cpc == 1 ? [0.42] : collect(range(-0.6, 0.7; length = n_cpc)),
                        randn(MersenneTwister(900 + D_chk), n_cpc) .* 0.8,
                    ]
                    d_ref = joinpath(dir, "lkj_d$(D_chk)_$(eta_chk).json")
                    p_ref = joinpath(dir, "lkj_pts_$(D_chk)_$(eta_chk).json")
                    o_ref = joinpath(dir, "lkj_out_$(D_chk)_$(eta_chk).csv")
                    write(d_ref, BayesianMGMFRM.JSON3.write((; D = D_chk, eta = eta_chk)))
                    write(p_ref, BayesianMGMFRM.JSON3.write((; params_r = pts_cpc)))
                    BayesianMGMFRM._cmdstan_run(
                        `$lkj_ref_exe log_prob unconstrained_params=$p_ref jacobian=1 data file=$d_ref output file=$o_ref sig_figs=18 refresh=0`,
                        :density_check,
                    )
                    csv_ref = BayesianMGMFRM._cmdstan_read_csv(o_ref, length(pts_cpc))
                    q_zero = zeros(Float64, LogDensityProblems.dimension(t_chk))
                    lp0_target = logprior(t_chk, q_zero)
                    for (ri, q_c) in enumerate(pts_cpc)
                        lp_j = t_chk.lkj_log_normalizer
                        k_c = 0
                        for i_d in 2:D_chk
                            log_rem = 0.0
                            for _ in 1:(i_d - 1)
                                k_c += 1
                                z_ij = tanh(q_c[k_c])
                                log_delta = log1p(-z_ij * z_ij)
                                lp_j += log_delta + 0.5 * log_rem
                                log_rem += log_delta
                            end
                            lp_j += 0.5 * ((D_chk - i_d) + 2.0 * eta_chk - 2.0) * log_rem
                        end
                        @test abs(csv_ref.values[ri, 1] - lp_j) <= 1e-13
                        q_full = copy(q_zero)
                        q_full[t_chk.corr_z_range] .= q_c
                        @test abs((logprior(t_chk, q_full) - lp0_target) - (csv_ref.values[ri, 1] - csv_ref.values[1, 1])) <= 1e-13
                    end
                end
            end

            for (idx_t, (label, tgt)) in enumerate(targets)
                D_dim = LogDensityProblems.dimension(tgt)
                pts = [
                    zeros(Float64, D_dim),
                    randn(MersenneTwister(3100 + 13 * idx_t), D_dim) .* 0.55,
                    randn(MersenneTwister(4100 + 17 * idx_t), D_dim) .* 0.45,
                ]
                if tgt.prior.latent_correlation === :lkj
                    for z in (-20.0, 20.0)
                        tail = copy(pts[2])
                        tail[tgt.corr_z_range] .= z
                        push!(pts, tail)
                    end
                end
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

                    # Verify SamplingTarget (including 2D Givens mean orthogonalization!)
                    st = _P22_SIM.SamplingTarget(tgt)
                    u_pt = _P22_SIM.from_raw(st, q)
                    @test maximum(abs.(_P22_SIM.to_raw(st, u_pt) .- q)) <= 1e-13
                    lp_u, g_u = LogDensityProblems.logdensity_and_gradient(st, u_pt)
                    g_u_fd = ForwardDiff.gradient(z -> LogDensityProblems.logdensity(st, z), u_pt)
                    @test maximum(abs.(g_u .- g_u_fd)) <= 1e-12
                    J_st = ForwardDiff.jacobian(z -> _P22_SIM.to_raw(st, z), u_pt)
                    @test abs((lp_u - lp) - logabsdet(J_st)[1]) <= 1e-12

                    st_ncp = _P22_SIM.SamplingTarget(tgt; person_coordinates = :noncentered)
                    if tgt.prior.location_identification === :centered_items_free_mean
                        @test st_ncp.use_givens_mean
                    end
                    u_ncp = _P22_SIM.from_raw(st_ncp, q)
                    @test abs(logabsdet(ForwardDiff.jacobian(z -> _P22_SIM.to_raw(st_ncp, z), u_ncp))[1]) <= 1e-12

                    # Verify positive definiteness and unit diagonal of implied correlation matrix
                    coords = coordinates(tgt, q)
                    if tgt.prior.latent_correlation === :lkj
                        Omega = coords.correlation_matrix
                        @test maximum(abs.(diag(Omega) .- 1.0)) <= 1e-13
                        # Near +/-1 the full matrix can round to singular while its
                        # generating Cholesky factor still has positive diagonals.
                        if maximum(abs, q[tgt.corr_z_range]) < 10
                            @test minimum(eigvals(Symmetric(Omega))) > 0.0
                        else
                            @test all(>(0), diag(coords.cholesky_L))
                        end
                    end
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
        println("P2-2 Parity Metrics: has_stan=$has_stan, max_fd_err=$(max_fd_err), max_stan_lp_err=$(max_stan_lp_err), max_stan_grad_err=$(max_stan_grad_err)")
        @test max_fd_err <= 1e-12
        if has_stan
            @test max_stan_lp_err <= 1e-12
            @test max_stan_grad_err <= 1e-12
        end
    end

    # -----------------------------------------------------------------------
    # 3. 1D Yen's Q3 / Adjusted Q3* Residual Correlation & PPC Diagnostics
    # -----------------------------------------------------------------------
    @testset "1D MRCML diagnostics(kind = :residual_correlation) detects halo and 2D misspecification" begin
        # Freeze the three simulated rating tables so both Julia versions assess
        # the same observations. These come from 0cea3251 run on Julia 1.13.4 with
        # MersenneTwister(2026112503) and a shared event SD of 0.95 for halo.
        fixture = joinpath(@__DIR__, "fixtures", "q3_simulated_ratings.csv")
        lines = readlines(fixture)
        @test first(lines) == "person,item,rater,assessment,null_score,halo_score,twodim_score"
        rows = [split(line, ',') for line in Iterators.drop(lines, 1)]
        @test length(rows) == 288
        design = (; person = first.(rows), item = getindex.(rows, 2),
            rater = getindex.(rows, 3), assessment = getindex.(rows, 4))
        tbl_null = (; design..., score = parse.(Int, getindex.(rows, 5)))
        tbl_halo = (; design..., score = parse.(Int, getindex.(rows, 6)))
        tbl_2d = (; design..., score = parse.(Int, getindex.(rows, 7)))

        fit_1d = function(t_in, sd)
            sp = mfrm_spec(t_in;
                person = :person, score = :score, facets = (item = :item, rater = :rater),
                steps = :global, category_levels = 0:3, assessment = :assessment, prior = :default)
            return fit(sp; chains = 2, warmup = 150, ndraws = 150, seed = sd, progress = false)
        end

        f_null = fit_1d(tbl_null, 301)
        f_halo = fit_1d(tbl_halo, 302)
        f_2d = fit_1d(tbl_2d, 303)

        rc_null = diagnostics(f_null; kind = :residual_correlation, seed = 401)
        rc_halo = diagnostics(f_halo; kind = :residual_correlation, seed = 402)
        rc_2d = diagnostics(f_2d; kind = :residual_correlation, seed = 403)

        @test rc_null.unit === :event
        @test length(rc_null.rows) == 6
        @test rc_null.global_summary.ppp_mean_q3 >= 0.05
        @test rc_halo.global_summary.mean_q3_obs > 0.15
        @test rc_halo.global_summary.ppp_mean_q3 < 0.05
        @test rc_2d.global_summary.max_adjusted_q3_obs > 0.20
        @test minimum(r.adjusted_q3_mean for r in rc_2d.rows) < -0.15
        @test rc_2d.global_summary.ppp_max_abs_adjusted_q3 < 0.05

        # Cross-family compare_models on identical rating observations (2D LKJ vs 1D MRCML)
        Q2 = Bool[1 0; 1 0; 0 1; 0 1]
        sp_mg2 = mfrm_spec(tbl_2d;
            person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3, q_matrix = Q2,
            correlation = :lkj, lkj_eta = 2.0, prior = :default)
        f_mg2 = fit(sp_mg2; chains = 2, warmup = 150, ndraws = 150, seed = 304, progress = false)
        cmp = compare_models("MGMFRM_2D_LKJ" => f_mg2, "MRCML_1D" => f_2d)
        @test length(cmp.rows) == 2
        @test cmp.rows[1].model_label == "MGMFRM_2D_LKJ"

        # Mismatched dataset must throw ArgumentError
        @test_throws ArgumentError compare_models("MGMFRM_2D_LKJ" => f_mg2, "Other_1D" => f_null)
    end

    # -----------------------------------------------------------------------
    # 4. Weighted Sufficient Score, CR5 Thin-Bridge Check & PortableHandoff
    # -----------------------------------------------------------------------
    @testset "Weighted sufficient score W_p, CR5 thin bridges, and LKJ PortableHandoff" begin
        # Thin-bridge design: R1-R2 connected to R3-R4 through a single person P4
        ps_tb = ["P1", "P1", "P2", "P2", "P3", "P3", "P4", "P4", "P5", "P5", "P6", "P6"]
        rs_tb = ["R1", "R2", "R1", "R2", "R1", "R2", "R2", "R3", "R3", "R4", "R3", "R4"]
        tbl_tb = (;
            person = vcat(ps_tb, ps_tb),
            rater  = vcat(rs_tb, rs_tb),
            item   = vcat(fill("I1", 12), fill("I2", 12)),
            score  = [0, 1, 1, 2, 2, 1, 1, 0, 0, 2, 1, 2, 1, 0, 2, 1, 1, 2, 0, 1, 2, 0, 2, 1],
        )
        t_gm_tb = mfrm_spec(tbl_tb;
            person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:2, slope = :rater, prior = :default)
        val_tb = validate_design(t_gm_tb)
        @test val_tb.passed && val_tb.identified
        @test any(b -> b.facet === :rater && b.bottleneck_shared_interior_persons == 1, val_tb.connectedness.thin_bridges)
        @test any(iss -> iss.code === :thin_facet_bridge, val_tb.issues)

        f_gm = fit(t_gm_tb; chains = 2, warmup = 60, ndraws = 60, seed = 501, progress = false)
        wss_gm = diagnostics(f_gm; kind = :weighted_sufficient_score)
        @test wss_gm.dimension == 1
        @test length(wss_gm.rows) == 6
        @test all(isfinite(r.weighted_sufficient_mean) && r.weighted_sufficient_lower <= r.weighted_sufficient_mean <= r.weighted_sufficient_upper for r in wss_gm.rows)

        # PortableHandoff round-trip on 2D LKJ ScaleIdentifiedMGMFRM
        tbl_mg = _p22_make_balanced_table(; P = 8, I = 4, R = 3, K = 3, seed = 502)
        t_mg = mfrm_spec(tbl_mg;
            person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:2, q_matrix = Bool[1 0; 1 0; 0 1; 0 1],
            correlation = :lkj, lkj_eta = 2.0, prior = :default)
        f_mg = fit(t_mg; chains = 2, warmup = 60, ndraws = 60, seed = 503, progress = false)

        corr_sum = facet_summary(f_mg; facet = :latent_correlation)
        @test corr_sum.n_levels == 1
        @test corr_sum.rows[1].parameter == "latent_correlation[dim=1, dim=2]"
        @test -1.0 <= corr_sum.rows[1].mean <= 1.0

        wss_d2 = diagnostics(f_mg; kind = :weighted_sufficient_score, dimension = 2)
        @test wss_d2.dimension == 2 && length(wss_d2.rows) == 8

        mktempdir() do dir
            ho_path = joinpath(dir, "mg_lkj_handoff.json")
            ho = PortableHandoff.export_handoff(f_mg; scale = :model, include_log_lik = true)
            @test ho.record.prior_summary.ability_sd.family == "HalfNormal"
            @test lowercase(string(ho.record.prior_summary.latent_correlation)) == "lkj"
            PortableHandoff.save_handoff(ho_path, ho)
            re_ho = PortableHandoff.load_handoff(ho_path)
            @test re_ho.record.draws_ieee754_sha256 == ho.record.draws_ieee754_sha256
            @test re_ho.record.handoff_bundle_sha256 == ho.record.handoff_bundle_sha256
        end
    end

    # -----------------------------------------------------------------------
    # 5. Multi-Angle Q-Matrix, Design-Matrix Rank, Softmin, Ability-Only Scope,
    #    Draw-Specific Orthogonal SamplingTarget, & Prior Sensitivity
    # -----------------------------------------------------------------------
    @testset "Multi-angle Q-matrix, design matrices, softmin, rater_slope_scope & prior_sensitivity" begin
        @test length(filter(s -> s !== :BayesianMGMFRM, names(BayesianMGMFRM))) == 41
        @test length(filter(s -> s !== :GlassBox, names(BayesianMGMFRM.GlassBox))) == 29

        tbl5 = _p22_make_balanced_table(; P = 10, I = 5, R = 3, K = 4, seed = 601)
        fd5 = FacetData(tbl5; person = :person, item = :item, rater = :rater, score = :score, category_levels = 0:3)
        Q5 = Bool[1 0; 1 0; 0 1; 0 1; 1 1]

        # 5a. Table vs FacetData default prior unification + label-keyed permuted Q-matrix safety
        t_tbl_def = mfrm_spec(tbl5;
            person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3, q_matrix = Q5,
            dimension_labels = ["Accuracy", "Fluency"], prior = :default)
        t_fd_def = mfrm_spec(fd5;
            family = :mgmfrm, q_matrix = Q5, dimension_labels = ["Accuracy", "Fluency"], prior = :default)
        @test _P22_SIM.target_identity(t_tbl_def) == _P22_SIM.target_identity(t_fd_def)

        q_pairs_perm = [
            "I5" => [1, 1],
            "I3" => [0, 1],
            "I1" => [1, 0],
            "I4" => [0, 1],
            "I2" => [1, 0],
        ]
        t_named_pairs = mfrm_spec(tbl5;
            person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3, q_matrix = q_pairs_perm,
            dimension_labels = ["Accuracy", "Fluency"], prior = :default)
        t_named_nt = mfrm_spec(tbl5;
            person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3,
            q_matrix = (items = ["I5", "I4", "I3", "I2", "I1"],
                        matrix = Bool[1 1; 0 1; 0 1; 1 0; 1 0],
                        dimensions = ["Accuracy", "Fluency"]),
            prior = :default)
        @test _P22_SIM.target_identity(t_named_pairs) == _P22_SIM.target_identity(t_tbl_def)
        @test _P22_SIM.target_identity(t_named_nt) == _P22_SIM.target_identity(t_tbl_def)
        @test_throws ArgumentError mfrm_spec(tbl5;
            q_matrix = ["I1" => [1, 0], "I2" => [1, 0]], category_levels = 0:3, prior = :default)
        @test_throws ArgumentError mfrm_spec(tbl5;
            q_matrix = ["I1" => [1, 0], "I1" => [1, 0], "I2" => [1, 0], "I3" => [0, 1], "I4" => [0, 1]],
            category_levels = 0:3, prior = :default)

        # 5b. Design-matrix bridge: upfront rejection of dimension-nested raters + SPQR detection of step rank deficiency
        dm5 = BayesianMGMFRM.MRCML.design_matrices(t_tbl_def)
        @test dm5.location_step_rank.full_rank === true
        @test dm5.A_pattern == dm5.A_model * dm5.J_model
        @test dm5.Q == Q5
        @test !dm5.intercept_slope_invariant
        fb_it = BayesianMGMFRM.GlassBox.facet_basis(t_tbl_def, :item)
        @test size(fb_it.basis_matrix) == (5, 3) # (2-1) + (2-1) pure Helmert + 1 cross item
        ct_rows = BayesianMGMFRM.GlassBox.constraint_table(t_tbl_def)
        @test sum(r.n_free_parameters for r in ct_rows) == LogDensityProblems.dimension(t_tbl_def)

        # Dimension-nested rater panel (R1,R2 only on Dim-1 items; R3,R4 only on Dim-2 items) is rejected upfront
        p_nest = String[]; i_nest = String[]; r_nest = String[]; y_nest = Int[]
        rng_n = MersenneTwister(602)
        for p in 1:8
            for (it, rts) in (("I1", ("R1", "R2")), ("I2", ("R1", "R2")), ("I3", ("R3", "R4")), ("I4", ("R3", "R4")))
                for rt in rts
                    push!(p_nest, "P$p"); push!(i_nest, it); push!(r_nest, rt)
                    push!(y_nest, rand(rng_n, 0:2))
                end
            end
        end
        for (k_i, k_v) in enumerate((0, 1, 2)); y_nest[k_i] = k_v; end
        tbl_nest = (; person = p_nest, item = i_nest, rater = r_nest, score = y_nest)
        @test_throws ArgumentError mfrm_spec(tbl_nest;
            person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :global, category_levels = 0:2, q_matrix = Bool[1 0; 1 0; 0 1; 0 1], prior = :default)

        # Connected structural design with a constant-0 item: structural A_pattern is full rank,
        # while CR5 score-conditioned connectedness flags :score_conditioned_disconnected
        y_const_i5 = [it == "I5" ? 0 : sc for (it, sc) in zip(tbl5.item, tbl5.score)]
        tbl_const_i5 = (; person = tbl5.person, item = tbl5.item, rater = tbl5.rater, score = y_const_i5)
        t_const_i5 = mfrm_spec(tbl_const_i5;
            person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3, q_matrix = Q5, prior = :default)
        val_const_i5 = validate_design(t_const_i5)
        @test val_const_i5.location_step_design_rank.full_rank === true
        @test val_const_i5.connectedness.score_conditioned_connected === false
        @test val_const_i5.domain_scoped_regime.regime_passed === false
        @test :score_conditioned_disconnected in val_const_i5.domain_scoped_regime.reasons

        # 5c. GMFRM unlocked options (:anchor_item, rater_slope_scope = :ability_only) + MGMFRM :softmin & CmdStan parity
        t_gm_anc = mfrm_spec(tbl5;
            person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3, slope = :both,
            scale_identification = :anchor_item, anchor_items = ["I1"],
            rater_slope_scope = :ability_only, prior = :default)
        @test t_gm_anc.prior.scale_identification === :anchor_item
        @test t_gm_anc.prior.rater_slope_scope === :ability_only
        @test BayesianMGMFRM.MRCML.design_matrices(t_gm_anc).intercept_slope_invariant === true

        # Between-item Q must reject :softmin (kappa unidentified when all |D_i| == 1)
        @test_throws ArgumentError mfrm_spec(tbl5;
            person = :person, score = :score, facets = (item = :item, rater = :rater),
            q_matrix = Bool[1 0; 1 0; 0 1; 0 1; 0 1], category_levels = 0:3,
            aggregation = :softmin, prior = :default)

        t_sm_est = mfrm_spec(tbl5;
            person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3, q_matrix = Q5,
            correlation = :lkj, lkj_eta = 2.0,
            rater_slope_scope = :ability_only,
            aggregation = :softmin, prior = :default)
        t_sm_fix = with_options(t_sm_est; softmin_kappa = 3.5, rater_slope_scope = :entire_linear_predictor)
        t_avg = with_options(t_tbl_def; cross_loading_average = true, rater_slope_scope = :ability_only)
        @test "softmin_kappa" in parameter_names(t_sm_est; scale = :model)
        @test "softmin_kappa" in t_sm_fix.fixed_model_names

        stan_chk2 = BayesianMGMFRM.cmdstan_backend_check(; include_paths = true)
        exe2 = nothing
        mktempdir() do dir2
            if stan_chk2.runtime_ready
                make_prog = BayesianMGMFRM._cmdstan_configured_program("MAKE", ("make", "gmake"))
                stem2 = joinpath(dir2, "p22_softmin_check")
                write(stem2 * ".stan", _P22_SIM.stan_code())
                BayesianMGMFRM._cmdstan_run(Cmd(`$make_prog -f makefile $stem2`; dir = stan_chk2.cmdstan_root), :model_compile)
                exe2 = BayesianMGMFRM._cmdstan_executable_path(stem2)
            end

            for (lbl, tgt) in (("gm_anc_abil", t_gm_anc), ("sm_est_lkj", t_sm_est), ("sm_fix_lkj", t_sm_fix), ("add_avg_abil", t_avg))
                # Record/restore identity
                tgt_re = _P22_SIM.restore_target(_P22_SIM.target_record(tgt))
                @test _P22_SIM.target_identity(tgt_re) == _P22_SIM.target_identity(tgt)

                q_pt = [0.22 * sin(0.9 * j + 0.3) for j in 1:LogDensityProblems.dimension(tgt)]
                c_pt = coordinates(tgt, q_pt)
                @test abs(_P22_SIM.constrained_subspace_logprior(tgt, c_pt) + c_pt.log_jacobian - logprior(tgt, q_pt)) <= 1e-12

                lp_an, g_an = LogDensityProblems.logdensity_and_gradient(tgt, q_pt)
                g_fd = ForwardDiff.gradient(x -> LogDensityProblems.logdensity(tgt, x), q_pt)
                @test maximum(abs.(g_an .- g_fd)) <= 1e-11

                # Draw-specific orthogonal SamplingTarget bijection + gradient parity
                st_d = _P22_SIM.SamplingTarget(tgt; person_coordinates = :noncentered)
                u_pt = _P22_SIM.from_raw(st_d, q_pt)
                q_back, lj_st = _P22_SIM._to_raw_with_logjac(st_d, u_pt)
                @test lj_st == 0.0
                @test maximum(abs.(q_back .- q_pt)) <= 1e-13
                lp_st, g_st = LogDensityProblems.logdensity_and_gradient(st_d, u_pt)
                g_st_fd = ForwardDiff.gradient(u -> LogDensityProblems.logdensity(st_d, u), u_pt)
                @test abs(lp_st - lp_an) <= 1e-12
                @test maximum(abs.(g_st .- g_st_fd)) <= 1e-11

                if exe2 !== nothing
                    d_p = joinpath(dir2, "$(lbl)_data.json")
                    p_p = joinpath(dir2, "$(lbl)_pts.json")
                    o_p = joinpath(dir2, "$(lbl)_out.csv")
                    write(d_p, BayesianMGMFRM.JSON3.write(stan_data(tgt)))
                    write(p_p, BayesianMGMFRM.JSON3.write((; params_r = [q_pt])))
                    BayesianMGMFRM._cmdstan_run(`$exe2 log_prob unconstrained_params=$p_p jacobian=1 data file=$d_p output file=$o_p sig_figs=18 refresh=0`, :density_check)
                    csv2 = BayesianMGMFRM._cmdstan_read_csv(o_p, 1)
                    @test abs(csv2.values[1, 1] - lp_an) <= 1e-12
                    @test maximum(abs.(csv2.values[1, 2:end] .- g_an)) <= 1e-11
                end
            end
        end

        # 5d. Fit softmin + check facet_summary(centered=...), fair_average parity, compare_models, & prior_sensitivity
        f_sm = fit(t_sm_est; chains = 2, warmup = 60, ndraws = 60, seed = 605, progress = false)
        f_add = fit(t_avg; chains = 2, warmup = 60, ndraws = 60, seed = 606, progress = false)

        fs_abs = facet_summary(f_sm; facet = :person)
        fs_cen = facet_summary(f_sm; facet = :person, centered = true)
        @test fs_abs.person_scale === :absolute
        @test fs_cen.person_scale === :centered_deviation
        @test length(fs_abs.rows) == length(fs_cen.rows)

        fa_sm = diagnostics(f_sm; kind = :fair_average, reference_plan = (item = ["I1", "I5"], rater = ["R1", "R2"]))
        @test length(fa_sm.rows) == 10 && all(r -> isfinite(r.mean), fa_sm.rows)

        cmp_sm = compare_models(:softmin => f_sm, :additive_avg => f_add)
        @test length(cmp_sm.rows) == 2

        ps_one = prior_sensitivity(f_sm, "wider_loadings" => (log_loading_sd = 0.5, lkj_eta = 3.0);
            parameters = ["softmin_kappa", "latent_correlation[dim=1, dim=2]"])
        @test isfinite(ps_one.pareto_k)
        @test length(ps_one.rows) == 2
        ps_suite = prior_sensitivity(f_sm, [
            "tighter_kappa" => (softmin_log_kappa_sd = 0.75,),
            "lognormal_sd" => (ability_sd_prior = LogNormal(0.0, 0.5),),
        ]; parameters = ["softmin_kappa"])
        @test ps_suite.n_variants == 2
        # Structural equation change must be rejected in importance-reweighting prior_sensitivity
        @test_throws ArgumentError prior_sensitivity(f_sm, (logit_scale = 1.0,))
        @test_throws ArgumentError prior_sensitivity(f_sm, (rater_slope_scope = :entire_linear_predictor,))
    end
end
