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

@testset "CR3: Isometric 1D Bayesian MFRM (`prior = :default`), Diagnostics & CmdStan Parity" begin
    # -----------------------------------------------------------------------
    # 1. Label-Permutation Invariance & Singleton/Binary Edge-Case Handling
    # -----------------------------------------------------------------------
    @testset "Label-permutation invariance on binary (0:1) and 4-category (0:3) PCM" begin
        # (a) 1-item, 2-rater binary (0:1) panel (`L_item = 1` singleton facet, `H = 1` binary step)
        tbl_bin = (
            person = [1, 1, 2, 2, 3, 3, 4, 4, 5, 6],
            item   = fill("ItemOnly", 10),
            rater  = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
            score  = [1, 0, 1, 1, 0, 0, 1, 0, 1, 0],
        )
        sp_bin_a = mfrm_spec(tbl_bin; person = :person, score = :score,
            facets = (item = :item, rater = :rater), steps = :global,
            category_levels = 0:1, prior = :default,
            levels = (person = collect(1:6), facets = (item = ["ItemOnly"], rater = ["R1", "R2"])))
        sp_bin_b = mfrm_spec(tbl_bin; person = :person, score = :score,
            facets = (item = :item, rater = :rater), steps = :global,
            category_levels = 0:1, prior = :default,
            levels = (person = collect(1:6), facets = (item = ["ItemOnly"], rater = ["R2", "R1"])))

        @test contract(sp_bin_a).status === :supported
        @test contract(sp_bin_a).location_mode === :zero_mean_population
        @test sp_bin_a.person_hyper_idx > 0
        @test design_summary(sp_bin_a).prior_summary.person.family === :HalfNormal
        @test isapprox(design_summary(sp_bin_a).prior_summary.person.scale, 1.0; atol = 1e-12)
        @test "population_mean" in parameter_names(sp_bin_a; scale = :model)
        @test "residual_sd[person]" in parameter_names(sp_bin_a; scale = :model)
        @test !validate_design(sp_bin_a).prior_symmetry.prior_asymmetry_detected
        @test !validate_design(sp_bin_b).prior_symmetry.prior_asymmetry_detected

        # Swapping ["R1", "R2"] -> ["R2", "R1"] negates the 1D Helmert contrast coordinate
        for seed in (11, 29, 47)
            qa = randn(MersenneTwister(seed), LogDensityProblems.dimension(sp_bin_a))
            qb = copy(qa)
            r_blk_a = only(filter(b -> b.name === :rater, sp_bin_a.prior_blocks))
            r_blk_b = only(filter(b -> b.name === :rater, sp_bin_b.prior_blocks))
            qb[only(r_blk_b.raw_range)] = -qa[only(r_blk_a.raw_range)]
            @test abs(logprior(sp_bin_a, qa) - logprior(sp_bin_b, qb)) <= 1e-14
            @test abs(loglikelihood(sp_bin_a, qa) - loglikelihood(sp_bin_b, qb)) <= 1e-14
            @test abs(logposterior(sp_bin_a, qa) - logposterior(sp_bin_b, qb)) <= 1e-14
        end

        # (b) 4-category (0:3), 4-item, 3-rater PCM (`steps = :item`)
        rng = MersenneTwister(20261122)
        persons = repeat(["P$p" for p in 1:3], inner = 12)
        items   = repeat(["I1", "I2", "I3", "I4"], inner = 3, outer = 3)
        raters  = repeat(["R1", "R2", "R3"], outer = 12)
        scores  = rand(rng, 0:3, 36)
        tbl_pcm = (; person = persons, item = items, rater = raters, score = scores)

        orig_r = ["R1", "R2", "R3"]
        perm_r = ["R3", "R1", "R2"]
        orig_i = ["I1", "I2", "I3", "I4"]
        perm_i = ["I3", "I1", "I4", "I2"]

        sp_orig = mfrm_spec(tbl_pcm; person = :person, score = :score,
            facets = (item = :item, rater = :rater), steps = :item,
            category_levels = 0:3, prior = :default,
            levels = (person = ["P$p" for p in 1:3], facets = (item = orig_i, rater = orig_r)))
        sp_perm = mfrm_spec(tbl_pcm; person = :person, score = :score,
            facets = (item = :item, rater = :rater), steps = :item,
            category_levels = 0:3, prior = :default,
            levels = (person = ["P$p" for p in 1:3], facets = (item = perm_i, rater = perm_r)))

        sym_o = validate_design(sp_orig).prior_symmetry
        sym_p = validate_design(sp_perm).prior_symmetry
        @test !sym_o.prior_asymmetry_detected && !sym_p.prior_asymmetry_detected
        @test isapprox(sym_o.max_to_min_variance_ratio, 1.0; atol = 1e-14)
        for ba in sym_o.block_audits
            @test isapprox(ba.min_marginal_variance, 1.0; atol = 1e-14)
            @test isapprox(ba.max_marginal_variance, 1.0; atol = 1e-14)
        end

        # Transport arbitrary unconstrained q_orig -> q_perm via exact isometric basis orthogonal map
        C_r = BayesianMGMFRM.MRCML.helmert_basis(3)
        C_i = BayesianMGMFRM.MRCML.helmert_basis(4)
        P_r = [orig_r[j] == perm_r[i] ? 1.0 : 0.0 for i in 1:3, j in 1:3]
        P_i = [orig_i[j] == perm_i[i] ? 1.0 : 0.0 for i in 1:4, j in 1:4]
        Q_r = C_r' * P_r * C_r # orthogonal 2x2
        Q_i = C_i' * P_i * C_i # orthogonal 3x3
        @test isapprox(Q_r' * Q_r, Matrix{Float64}(I, 2, 2); atol = 1e-14)
        @test isapprox(Q_i' * Q_i, Matrix{Float64}(I, 3, 3); atol = 1e-14)

        b_map_o = Dict(b.name => b for b in sp_orig.prior_blocks)
        b_map_p = Dict(b.name => b for b in sp_perm.prior_blocks)
        for seed in (101, 202, 303)
            qo = randn(MersenneTwister(seed), LogDensityProblems.dimension(sp_orig))
            qp = copy(qo)
            qp[b_map_p[:item].raw_range] .= Q_i * qo[b_map_o[:item].raw_range]
            qp[b_map_p[:rater].raw_range] .= Q_r * qo[b_map_o[:rater].raw_range]
            # Step blocks follow permuted item order `perm_i`
            for (g_new, ilbl) in enumerate(perm_i)
                g_old = only(findall(==(ilbl), orig_i))
                qp[b_map_p[Symbol("steps_", g_new)].raw_range] .= qo[b_map_o[Symbol("steps_", g_old)].raw_range]
            end
            @test abs(logprior(sp_orig, qo) - logprior(sp_perm, qp)) <= 1e-13
            @test abs(loglikelihood(sp_orig, qo) - loglikelihood(sp_perm, qp)) <= 1e-13
            @test abs(logposterior(sp_orig, qo) - logposterior(sp_perm, qp)) <= 1e-13
        end

        # FacetData bridge & `:over_anchored_reference_prior_risk` declaration on legacy FacetSpec
        fd = FacetData(tbl_pcm; person = :person, item = :item, rater = :rater, score = :score, category_levels = 0:3)
        fd_iso = mfrm_spec(fd; prior = :default)
        fd_iso2 = mfrm_spec(fd; identification = :isometric)
        @test fd_iso isa BayesianMGMFRM.AdditiveFacets.MRCMLTarget
        @test fd_iso2 isa BayesianMGMFRM.AdditiveFacets.MRCMLTarget
        @test parameter_names(fd_iso; scale = :model) == parameter_names(fd_iso2; scale = :model)

        fd_legacy = mfrm_spec(fd)
        @test fd_legacy isa FacetSpec
        id_rows = identification_declarations(fd_legacy)
        @test any(r -> r.rule === :over_anchored_reference_prior_risk, id_rows)

        # Paradigm-exclusivity guards
        @test_throws ArgumentError mfrm_spec(tbl_pcm; person = :person, score = :score,
            facets = (item = :item, rater = :rater), steps = :item, category_levels = 0:3,
            prior = :default, prior_sd = (person = 1.0, facets = (item = 1.0, rater = 1.0), step = 1.0))
        @test_throws ArgumentError mfrm_spec(fd; identification = :reference, prior = :default)
    end

    # -----------------------------------------------------------------------
    # 2. ForwardDiff & Native CmdStan 2.39.0 Fixed-Point Parity (<= 1e-12)
    # -----------------------------------------------------------------------
    @testset "ForwardDiff & CmdStan 2.39.0 fixed-point log_prob and gradient parity" begin
        tbl_bin = (
            person = [1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 8],
            item   = fill(1, 14),
            rater  = [1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2],
            score  = [1, 0, 1, 1, 1, 0, 0, 0, 1, 1, 1, 0, 1, 1],
        )
        t_bin = mfrm_spec(tbl_bin; person = :person, score = :score,
            facets = (item = :item, rater = :rater), steps = :global,
            category_levels = 0:1, prior = :default)

        rng = MersenneTwister(9091)
        tbl_pcm = (
            person = repeat(1:8, inner = 12),
            item   = repeat(1:4, inner = 3, outer = 8),
            rater  = repeat(1:3, outer = 32),
            score  = rand(rng, 0:3, 96),
        )
        t_pcm = mfrm_spec(tbl_pcm; person = :person, score = :score,
            facets = (item = :item, rater = :rater), steps = :item,
            category_levels = 0:3, prior = :default)

        test_targets = [("binary_1item_2rater", t_bin), ("pcm_4cat_4item_3rater", t_pcm)]
        stan_chk = cmdstan_backend_check(; include_paths = true)
        has_stan = stan_chk.runtime_ready

        mktempdir() do dir
            exe_path = if has_stan
                make_prog = BayesianMGMFRM._cmdstan_configured_program("MAKE", ("make", "gmake"))
                stem = joinpath(dir, "mrcml_cr3_ref")
                write(stem * ".stan", BayesianMGMFRM.MRCML.stan_code(t_pcm))
                BayesianMGMFRM._cmdstan_run(Cmd(`$make_prog -f makefile $stem`; dir = stan_chk.cmdstan_root), :model_compile)
                BayesianMGMFRM._cmdstan_executable_path(stem)
            else
                nothing
            end

            for (label, tgt) in test_targets
                D_dim = LogDensityProblems.dimension(tgt)
                pts = [
                    zeros(Float64, D_dim),
                    [0.25 * sin(0.7 * j) for j in 1:D_dim],
                    randn(MersenneTwister(1777 + D_dim), D_dim) .* 0.6,
                    vcat(fill(0.35, D_dim - 1), [0.85]),
                    vcat(fill(-0.30, D_dim - 1), [-0.75]),
                ]
                j_lps = Float64[]
                j_grads = Vector{Float64}[]
                for q in pts
                    lp, g = logdensity_and_gradient(tgt, q)
                    g_fd = ForwardDiff.gradient(x -> logposterior(tgt, x), q)
                    @test abs(lp - logposterior(tgt, q)) <= 1e-13
                    @test maximum(abs.(g .- g_fd)) <= 1e-12
                    push!(j_lps, lp)
                    push!(j_grads, g)
                end

                if exe_path !== nothing
                    d_path = joinpath(dir, "$(label)_data.json")
                    p_path = joinpath(dir, "$(label)_pts.json")
                    o_path = joinpath(dir, "$(label)_out.csv")
                    sd_json = Dict(k => (v isa AbstractMatrix ? [collect(r) for r in eachrow(v)] : v) for (k, v) in stan_data(tgt))
                    write(d_path, BayesianMGMFRM.JSON3.write(sd_json))
                    write(p_path, BayesianMGMFRM.JSON3.write((; params_r = pts)))
                    BayesianMGMFRM._cmdstan_run(
                        `$exe_path log_prob unconstrained_params=$p_path jacobian=1 data file=$d_path output file=$o_path sig_figs=18 refresh=0`,
                        :density_check,
                    )
                    csv = BayesianMGMFRM._cmdstan_read_csv(o_path, length(pts))
                    @test csv.header == ["lp__"; ["g_q.$i" for i in 1:D_dim]]
                    for r in eachindex(pts)
                        @test abs(csv.values[r, 1] - j_lps[r]) <= 1e-12
                        @test maximum(abs.(csv.values[r, 2:end] .- j_grads[r])) <= 1e-12
                    end
                end
            end
        end
    end

    # -----------------------------------------------------------------------
    # 3. Practitioner Contrast, Reliability & Posterior-Integrated vs Plug-in Fit
    # -----------------------------------------------------------------------
    @testset "Ergonomic contrast, population reliability & Bayesian vs plug-in Infit/Outfit" begin
        rng = MersenneTwister(4242)
        P_n = 16
        th_true = randn(rng, P_n) .* 1.1 .+ 1.2
        r_sev = [-0.6, 0.0, 0.6]
        i_dif = [-0.4, 0.4]
        p_col = Int[]; i_col = String[]; r_col = String[]; y_col = Int[]
        for p in 1:P_n, (ii, il) in enumerate(["I1", "I2"]), (ri, rl) in enumerate(["R1", "R2", "R3"])
            eta = th_true[p] - i_dif[ii] - r_sev[ri]
            l0, l1, l2 = 0.0, eta + 0.5, 2.0 * eta
            mx = max(l0, l1, l2)
            ps = [exp(l0 - mx), exp(l1 - mx), exp(l2 - mx)]
            ps ./= sum(ps)
            u = rand(rng)
            y = u <= ps[1] ? 0 : u <= ps[1] + ps[2] ? 1 : 2
            push!(p_col, p); push!(i_col, il); push!(r_col, rl); push!(y_col, y)
        end
        spec = mfrm_spec((; person = p_col, item = i_col, rater = r_col, score = y_col);
            person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:2, prior = :default)
        af_fit = fit(spec; chains = 2, warmup = 150, ndraws = 150, seed = 77)

        # Contrast by facet + label AND by 1-based index on string-labeled facets
        c_lbl = contrast(af_fit; facet = :rater, left = "R3", right = "R1", level = 0.95)
        c_idx = contrast(af_fit; facet = :rater, left = 3, right = 1, level = 0.95)
        @test c_lbl.mean == c_idx.mean
        @test c_lbl.eti == (c_lbl.lower, c_lbl.upper)
        @test c_lbl.mean > 0.0
        @test 0.0 <= c_lbl.prob_positive <= 1.0
        @test isfinite(c_lbl.mean_mcse) && isfinite(c_lbl.lower_mcse) && isfinite(c_lbl.upper_mcse)

        # Finite-cohort posterior functional: MCSE, without proxy credible/population intervals
        rel_p = reliability(af_fit; facet = :person, level = 0.95)
        @test 0.0 <= rel_p.reliability <= 1.0
        @test ismissing(rel_p.reliability_lower) && ismissing(rel_p.reliability_upper)
        @test ismissing(rel_p.population_marginal_reliability)
        @test rel_p.population_status === :requires_population_and_design_marginalization
        @test rel_p.mcse.status === :available
        rel_r = reliability(af_fit; facet = :rater, level = 0.95)
        @test ismissing(rel_r.population_marginal_reliability)

        # Posterior-integrated vs posterior-mean plug-in Infit/Outfit
        fs_r = diagnostics(af_fit; kind = :fit_statistics, by = :rater, level = 0.95, seed = 123)
        @test fs_r.schema == "bayesianmgmfrm.mrcml_fit_statistics.v1"
        @test fs_r.plugin_caveat === :posterior_mean_shrinkage_attenuates_mnsq_below_one
        @test length(fs_r.rows) == 3
        for row in fs_r.rows
            @test 0.0 < row.infit_mnsq_lower <= row.infit_mnsq_mean <= row.infit_mnsq_upper
            @test 0.0 < row.outfit_mnsq_lower <= row.outfit_mnsq_mean <= row.outfit_mnsq_upper
            @test 0.0 <= row.ppp_infit <= 1.0 && 0.0 <= row.ppp_outfit <= 1.0
            @test row.plugin_infit_mnsq > 0.0 && row.plugin_outfit_mnsq > 0.0
            @test row.plugin_caveat === :posterior_mean_shrinkage_attenuates_mnsq_below_one
        end
        # Because posterior-mean abilities shrink toward 0, average plug-in Infit MNSQ across persons is attenuated below posterior-integrated Infit MNSQ
        fs_p = diagnostics(af_fit; kind = :fit_statistics, by = :person, level = 0.95, seed = 123)
        @test length(fs_p.rows) == P_n
        @test mean(r.plugin_infit_mnsq for r in fs_p.rows) < mean(r.infit_mnsq_mean for r in fs_p.rows)

        # ModelOperationMatrix marks `:scalar_mrcml_design` as `:supported`
        mat_row = only(r for r in BayesianMGMFRM.ModelOperationMatrix.audit().rows if r.route === :scalar_mrcml_design)
        @test mat_row.tier === :supported && mat_row.status === :supported
    end
end
