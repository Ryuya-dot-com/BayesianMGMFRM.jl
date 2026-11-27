using Test
using Random
using LinearAlgebra
using Statistics
using BayesianMGMFRM
using BayesianMGMFRM.Distributions: Normal, LogNormal, Cauchy, TDist, LocationScale, truncated
using BayesianMGMFRM.ForwardDiff
using BayesianMGMFRM.LogDensityProblems
using BayesianMGMFRM.JSON3

@testset "CR8: DFF interaction priors, Fair Average, pair bias, and custom design handoff" begin
    # Construct a connected 10-person x 4-item x 3-rater 0:3 dataset with an injected R1 x I1 severity spike
    p_col = String[]
    i_col = String[]
    r_col = String[]
    s_col = Int[]
    for p in 1:10, (ii, it) in enumerate(("I1", "I2", "I3", "I4")), (ri, rt) in enumerate(("R1", "R2", "R3"))
        mod(p + ii + ri, 4) == 0 && continue
        base_sc = clamp(round(Int, 1.5 + 0.35 * (p - 5.5) - 0.3 * (ii - 2.5) - 0.25 * (ri - 2.0)), 0, 3)
        # Inject strong R1 severity specifically on I1 (lower observed scores in cell (R1, I1))
        sc = (rt == "R1" && it == "I1") ? 0 : (rt == "R1" && it == "I4") ? 3 : base_sc
        push!(p_col, "P$(lpad(p, 2, '0'))")
        push!(i_col, it)
        push!(r_col, rt)
        push!(s_col, sc)
    end
    tbl = (; person = p_col, item = i_col, rater = r_col, score = s_col)

    # -----------------------------------------------------------------------
    # 1. CR8-1: Interaction Scale Priors (No Silent Default, Zero-Supporting
    #    Half-Normal & Half-t(df=4), Funnel Warning on df <= 2, CmdStan 2.39)
    # -----------------------------------------------------------------------
    @testset "Interaction zero-supporting scale priors and CmdStan 2.39 parity" begin
        # Missing interaction prior must throw ArgumentError (no silent default)
        @test_throws ArgumentError mfrm_spec(
            tbl; person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3, interactions = [(:rater, :item)], prior = :default)
        @test_throws ArgumentError mfrm_spec(
            tbl; person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3, interactions = [(:rater, :step)], prior = :default)

        hn_int = truncated(Normal(0.0, 0.5), 0.0, Inf)
        ht4_int = truncated(LocationScale(0.0, 0.4, TDist(4.0)), 0.0, Inf)
        hc_int = truncated(Cauchy(0.0, 0.5), 0.0, Inf)
        base_psd = (person = truncated(Normal(0.0, 1.0), 0.0, Inf), facets = (item = 1.0, rater = 1.0), step = 1.0)

        t_hn = mfrm_spec(
            tbl; person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3,
            interactions = [(:rater, :item) => hn_int],
            prior_sd = base_psd, intercept = Normal(0.0, 2.5))

        t_ht = mfrm_spec(
            tbl; person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3,
            interactions = [(:rater, :item) => ht4_int, (:rater, :step) => hn_int],
            prior_sd = base_psd, intercept = Normal(0.0, 2.5))

        t_hc = mfrm_spec(
            tbl; person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3,
            interactions = [(:rater, :item) => hc_int],
            prior_sd = base_psd, intercept = Normal(0.0, 2.5))

        ds_hn = design_summary(t_hn)
        b_hn = only(filter(b -> b.block_role === :facet_facet_interaction, ds_hn.prior_summary.structural_blocks))
        @test b_hn.scale_prior.family === :HalfNormal
        @test b_hn.scale_prior.zero_supporting
        @test b_hn.scale_prior.second_moment_finite
        # 3 raters x 4 items -> iso_kr = sqrt(12 / 6) = sqrt(2); marginal cell RMS = s = 0.5; tetrad contrast SD = 2 * iso_kr * s = sqrt(2)
        @test isapprox(b_hn.marginal_sd, 0.5; rtol = 1e-12)
        @test isapprox(b_hn.implied_tetrad_contrast_sd, 2.0 * sqrt(2.0) * 0.5; rtol = 1e-12)
        @test b_hn.conditional_median_tetrad_contrast_sd > 0.0
        @test !any(w -> occursin("heavy-tailed", w), ds_hn.warnings)

        ds_ht = design_summary(t_ht)
        b_ht = only(filter(b -> b.block_role === :facet_facet_interaction, ds_ht.prior_summary.structural_blocks))
        b_st = only(filter(b -> b.block_role === :facet_step_interaction, ds_ht.prior_summary.structural_blocks))
        @test b_ht.scale_prior.family === :HalfStudentT
        @test b_ht.scale_prior.df == 4.0
        @test b_ht.scale_prior.zero_supporting
        @test isfinite(b_ht.implied_tetrad_contrast_sd) && b_ht.implied_tetrad_contrast_sd > 0.0
        @test b_st.scale_prior.family === :HalfNormal
        @test isfinite(b_st.implied_tetrad_contrast_sd) && b_st.implied_tetrad_contrast_sd > 0.0

        # Half-Cauchy (df = 1 <= 2) emits explicit funnel warning and infinite marginal tetrad SD
        ds_hc = design_summary(t_hc)
        b_hc = only(filter(b -> b.block_role === :facet_facet_interaction, ds_hc.prior_summary.structural_blocks))
        @test !b_hc.scale_prior.second_moment_finite
        @test b_hc.implied_tetrad_contrast_sd === Inf
        @test isfinite(b_hc.conditional_median_tetrad_contrast_sd)
        @test any(w -> occursin("heavy-tailed", w) && occursin("funnel", w), ds_hc.warnings)

        # Doubly centered sum-to-zero invariance + ForwardDiff + restore_mrcml + CmdStan 2.39 parity
        stan_chk = BayesianMGMFRM.cmdstan_backend_check(; include_paths = true)
        for (tag, tgt) in (("hn", t_hn), ("ht4_and_step", t_ht))
            t_rest = BayesianMGMFRM.AdditiveFacets.restore_mrcml(BayesianMGMFRM.AdditiveFacets.record(tgt))
            D_dim = LogDensityProblems.dimension(tgt)
            pts = [
                zeros(Float64, D_dim),
                [0.18 * sin(0.65 * j) for j in 1:D_dim],
                vcat([0.12 * cos(0.4 * j) for j in 1:(D_dim - 3)], [-1.6, -0.4, 0.35]),
            ]
            # Verify doubly centered sum-to-zero property on unfolded interaction cells
            u_chk = BayesianMGMFRM.AdditiveFacets._mrcml_unpack(tgt, pts[2])
            bm_int = only(filter(bm -> bm.kind === :facet_facet_interaction, tgt.operator.block_meta))
            G_mat = reshape(u_chk.xi_model[bm_int.model_range], length(bm_int.levels2), length(bm_int.levels1))'
            @test maximum(abs.(sum(G_mat; dims = 1))) <= 1e-14
            @test maximum(abs.(sum(G_mat; dims = 2))) <= 1e-14

            j_lps = Float64[]
            j_grads = Vector{Float64}[]
            for q in pts
                lp, g = LogDensityProblems.logdensity_and_gradient(tgt, q)
                lp_r = BayesianMGMFRM.GlassBox.logposterior(t_rest, q)
                g_fd = ForwardDiff.gradient(x -> BayesianMGMFRM.GlassBox.logposterior(tgt, x), q)
                @test abs(lp - lp_r) <= 1e-13
                @test maximum(abs.(g .- g_fd)) <= 1e-11
                push!(j_lps, lp)
                push!(j_grads, g)
            end

            if stan_chk.runtime_ready
                mktempdir() do dir
                    make_prog = BayesianMGMFRM._cmdstan_configured_program("MAKE", ("make", "gmake"))
                    stem = joinpath(dir, "mrcml_cr8_$(tag)")
                    write(stem * ".stan", BayesianMGMFRM.MRCML.stan_code(tgt))
                    BayesianMGMFRM._cmdstan_run(Cmd(`$make_prog -f makefile $stem`; dir = stan_chk.cmdstan_root), :model_compile)
                    exe = BayesianMGMFRM._cmdstan_executable_path(stem)
                    d_path = joinpath(dir, "data.json")
                    p_path = joinpath(dir, "pts.json")
                    o_path = joinpath(dir, "out.csv")
                    sd_json = Dict(k => (v isa AbstractMatrix ? [collect(r) for r in eachrow(v)] : v)
                        for (k, v) in BayesianMGMFRM.GlassBox.stan_data(tgt))
                    write(d_path, JSON3.write(sd_json))
                    write(p_path, JSON3.write((; params_r = pts)))
                    BayesianMGMFRM._cmdstan_run(
                        `$exe log_prob unconstrained_params=$p_path jacobian=1 data file=$d_path output file=$o_path sig_figs=18 refresh=0`,
                        :density_check)
                    csv = BayesianMGMFRM._cmdstan_read_csv(o_path, length(pts))
                    for r in eachindex(pts)
                        @test abs(csv.values[r, 1] - j_lps[r]) <= 1e-12
                        @test maximum(abs.(csv.values[r, 2:end] .- j_grads[r])) <= 1e-11
                    end
                end
            end
        end
    end

    # -----------------------------------------------------------------------
    # 2. CR8-2: Fair Average Score & Pair-Level Residual / DFF Bias Table
    # -----------------------------------------------------------------------
    @testset "Fair Average Score and Table-14 pair bias (:secondary_residual_screen vs :joint_interaction_model)" begin
        spec_main = mfrm_spec(
            tbl; person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3, prior = :default)
        fit_main = fit(spec_main; chains = 2, warmup = 150, ndraws = 150, seed = 202611255, progress = false)

        fa_rater = diagnostics(fit_main; kind = :fair_average, by = :rater, level = 0.90)
        fa_rater_z = diagnostics(fit_main; kind = :fair_average, by = :rater, baseline = :zero_origin, level = 0.90)
        fa_person = diagnostics(fit_main; kind = :fair_average, by = :person, level = 0.90)
        @test fa_rater.schema == "bayesianmgmfrm.mrcml_fair_average.v1"
        @test fa_rater.baseline === :sample_mean
        @test fa_rater_z.baseline === :zero_origin
        @test length(fa_rater.rows) == 3
        for row in fa_rater.rows
            @test 0.0 <= row.fair_average_lower <= row.fair_average_mean <= row.fair_average_upper <= 3.0
            @test 0.0 <= row.plugin_fair_average <= 3.0
            @test isfinite(row.fair_average_mcse_mean) && row.fair_average_mcse_mean >= 0.0
        end
        # Higher rater severity logit must correspond to strictly lower Fair Average score
        r_ord = sort(fa_rater.rows; by = r -> r.logit_mean)
        @test issorted([r.fair_average_mean for r in r_ord]; rev = true)
        # Higher person ability logit must correspond to strictly higher Fair Average score
        p_ord = sort(fa_person.rows; by = r -> r.logit_mean)
        @test issorted([r.fair_average_mean for r in p_ord])

        # Mixed-category Fair Average guard: requires explicit step_group when `by != step_owner`
        tbl_mix = (;
            person = tbl.person,
            item = tbl.item,
            rater = tbl.rater,
            score = [it in ("I1", "I2") ? min(sc, 2) : sc for (it, sc) in zip(tbl.item, tbl.score)],
        )
        spec_mix = mfrm_spec(
            tbl_mix; person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = Dict("I1" => 0:2, "I2" => 0:2, "I3" => 0:3, "I4" => 0:3),
            prior = :default)
        fit_mix = fit(spec_mix; chains = 2, warmup = 100, ndraws = 100, seed = 202611256, progress = false)
        @test_throws ArgumentError diagnostics(fit_mix; kind = :fair_average, by = :rater)
        fa_mix_item = diagnostics(fit_mix; kind = :fair_average, by = :item)
        fa_mix_r_i1 = diagnostics(fit_mix; kind = :fair_average, by = :rater, step_group = "I1")
        fa_mix_r_i4 = diagnostics(fit_mix; kind = :fair_average, by = :rater, step_group = "I4")
        @test only(filter(r -> r.level == "I1", fa_mix_item.rows)).max_category == 2
        @test only(filter(r -> r.level == "I4", fa_mix_item.rows)).max_category == 3
        @test all(r -> r.max_category == 2 && r.fair_average_upper <= 2.0, fa_mix_r_i1.rows)
        @test all(r -> r.max_category == 3 && r.fair_average_upper <= 3.0, fa_mix_r_i4.rows)

        # Secondary post-hoc residual screen on main-effects fit
        pb_screen = diagnostics(fit_main; kind = :pair_bias, pair = (:rater, :item), level = 0.90)
        pb_alias = BayesianMGMFRM.dff_report(fit_main; pair = (:rater, :item), level = 0.90)
        @test pb_screen.schema == "bayesianmgmfrm.mrcml_pair_bias.v1"
        @test pb_screen.analysis_mode === :secondary_residual_screen
        @test pb_alias.analysis_mode === :secondary_residual_screen
        @test length(pb_screen.rows) == 12
        cell_r1_i1_scr = only(filter(r -> r.level_1 == "R1" && r.level_2 == "I1", pb_screen.rows))
        @test cell_r1_i1_scr.joint_interaction_logit_mean === missing
        # Injected R1 x I1 severe spike -> observed score < expected -> score_residual < 0, approx_severity_bias_logit > 0
        @test cell_r1_i1_scr.score_residual_mean < 0.0
        @test cell_r1_i1_scr.approx_severity_bias_logit_mean > 0.5
        @test cell_r1_i1_scr.prob_score_residual_lt_0 > 0.90
        @test isapprox(pb_alias.rows[1].approx_severity_bias_logit_mean, pb_screen.rows[1].approx_severity_bias_logit_mean; atol = 1e-12)

        # Jointly fitted DFF interaction model separates joint_interaction_logit_* from post-interaction residual
        spec_joint = mfrm_spec(
            tbl; person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3,
            interactions = [(:rater, :item) => truncated(LocationScale(0.0, 0.5, TDist(4.0)), 0.0, Inf)],
            prior_sd = (person = truncated(Normal(0.0, 1.0), 0.0, Inf), facets = (item = 1.0, rater = 1.0), step = 1.0),
            intercept = Normal(0.0, 2.5))
        fit_joint = fit(spec_joint; chains = 2, warmup = 180, ndraws = 180, seed = 202611257, progress = false)
        pb_joint = diagnostics(fit_joint; kind = :pair_bias, pair = (:rater, :item), level = 0.90)
        @test pb_joint.analysis_mode === :joint_interaction_model
        cell_r1_i1_jnt = only(filter(r -> r.level_1 == "R1" && r.level_2 == "I1", pb_joint.rows))
        @test isfinite(cell_r1_i1_jnt.joint_interaction_logit_mean)
        @test cell_r1_i1_jnt.joint_interaction_logit_mean > 0.3
        @test cell_r1_i1_jnt.prob_interaction_gt_0 > 0.85
        @test isfinite(cell_r1_i1_jnt.joint_interaction_mcse_mean)
        @test isfinite(cell_r1_i1_jnt.baseline_main_effects_expected_mean)
    end

    # -----------------------------------------------------------------------
    # 3. Residual A & B: Custom TAM design handoff identification & report support status
    # -----------------------------------------------------------------------
    @testset "Custom TAM design handoff identification and Supported 1D MFRM report metadata" begin
        A = zeros(Float64, 3, 2, 3)
        for i in 1:3
            A[i, 2, i] = -1.0
        end
        resp = Float64[1 0 0; 1 1 0; 0 0 0; 1 1 1; 1 0 1; 0 1 0; 1 1 0; 0 0 1]
        tam_t = BayesianMGMFRM.MRCML.from_tam(
            A, resp;
            pid = ["P$p" for p in 1:8],
            item_names = ["I1", "I2", "I3"],
            parameter_names = ["item[\"I1\"]", "item[\"I2\"]", "item[\"I3\"]"],
            xsi_fixed = [1 -0.5],
            prior = Normal(0.0, 1.0),
            person_prior_sd = truncated(Normal(0.0, 1.0), 0.0, Inf))
        fit_tam = fit(tam_t; chains = 2, warmup = 80, ndraws = 80, seed = 202611258, progress = false)
        ho_tam = BayesianMGMFRM.PortableHandoff.export_handoff(fit_tam; scale = :model)
        @test String(ho_tam.record.prior_and_reference.identification) == "mrcml_design_matrix"
        @test String(ho_tam.record.prior_and_reference.facet_identification) == "mrcml_design_matrix"
        fp_i1 = only(filter(r -> r.name == "item[\"I1\"]", ho_tam.record.fixed_parameters))
        @test isapprox(fp_i1.value, -0.5; atol = 1e-12)

        # Standard Supported 1D MFRM reports carry `api.status === :supported`
        spec_sup = mfrm_spec(
            tbl; person = :person, score = :score, facets = (item = :item, rater = :rater),
            steps = :item, category_levels = 0:3, prior = :default)
        fit_sup = fit(spec_sup; chains = 2, warmup = 80, ndraws = 80, seed = 202611259, progress = false)
        @test BayesianMGMFRM.fit_report(fit_sup).api.status === :supported
        @test predictive_check(fit_sup; ndraws = 25, seed = 1).api.status === :supported
        @test prior_predictive_check(spec_sup; ndraws = 25, seed = 2).api.status === :supported
        @test BayesianMGMFRM.predictive_probabilities(fit_sup; rows = [1, 2]).api.status === :supported
        @test BayesianMGMFRM.fit_report(fit_tam).api.status === :experimental_fitted_workflow
        ext = Base.get_extension(BayesianMGMFRM, :BayesianMGMFRMCairoMakieExt)
        if ext !== nothing
            @test ext._additive_model_title_prefix(BayesianMGMFRM.fit_report(fit_sup)) == "Supported 1D MFRM"
            @test ext._additive_model_title_prefix(BayesianMGMFRM.fit_report(fit_tam)) == "Experimental scalar model"
        end
    end
end
