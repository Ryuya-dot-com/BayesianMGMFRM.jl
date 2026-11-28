module _TestP21ExchangeSchemaAndGroupDFF

using Test
using LinearAlgebra, Statistics, Random, SHA, JSON3
using BayesianMGMFRM
using BayesianMGMFRM.ValidationSuite
import BayesianMGMFRM.GlassBox as GB
import Distributions as D
import ForwardDiff
import LogDensityProblems as LDP

@testset "P2-1: Exchange Schema v1.0 Adapter & Unified MRCML Group-Impact + DFF" begin
    # 1. Synthetic connected 2-group rating fixture (zero external filesystem dependencies)
    rng = MersenneTwister(20261125)
    n_p = 24
    n_r = 4
    n_c = 3
    p_group = [p <= 12 ? 0 : 1 for p in 1:n_p]
    true_theta = [0.6 * p_group[p] + 0.7 * randn(rng) for p in 1:n_p]
    true_rater = [0.35, -0.25, 0.10, -0.20]
    true_crit = [-0.30, 0.05, 0.25]
    true_steps = [-0.65, 0.05, 0.60] # 4 categories (0:3)
    true_dff_r1 = 0.85

    p_col = Int[]; r_col = Int[]; c_col = Int[]; s_col = Int[]; g_col = Int[]
    for p in 1:n_p
        rs = [mod1(p + k - 1, n_r) for k in 1:3]
        for r in rs, c in 1:n_c
            dff_shift = (r == 1 && p_group[p] == 1) ? true_dff_r1 : 0.0
            eta = true_theta[p] - (true_rater[r] + dff_shift) - true_crit[c]
            lvec = [0.0, eta - true_steps[1], 2 * eta - (true_steps[1] + true_steps[2]),
                    3 * eta - sum(true_steps)]
            mmax = maximum(lvec)
            probs = exp.(lvec .- mmax)
            probs ./= sum(probs)
            u = rand(rng)
            y = findfirst(>=(u), cumsum(probs)) - 1
            push!(p_col, p); push!(r_col, r); push!(c_col, c); push!(s_col, y); push!(g_col, p_group[p])
        end
    end
    tbl = (; person = p_col, rater = r_col, criterion = c_col, score = s_col, group = g_col)
    roster = (; person = collect(1:n_p), group = p_group)

    @testset "ValidationSuite Exchange Schema v1.0 bundled synthetic round-trip" begin
        @test :load_exchange_manifest in ValidationSuite.contract().groups.benchmark_and_cross_engine
        @test :write_exchange_run in ValidationSuite.contract().groups.benchmark_and_cross_engine

        mktempdir() do study_dir
            in_dir = joinpath(study_dir, "inputs", "0001_synth_dff")
            tr_dir = joinpath(study_dir, "truth", "0001_synth_dff")
            mkpath(in_dir); mkpath(tr_dir)
            in_csv = joinpath(in_dir, "input.csv")
            open(in_csv, "w") do io
                println(io, "person,rater,criterion,score,group")
                for i in eachindex(s_col)
                    println(io, "$(p_col[i]),$(r_col[i]),$(c_col[i]),$(s_col[i]),$(g_col[i])")
                end
            end
            sha_in = bytes2hex(sha256(read(in_csv)))

            # True Fair(M) on 0:3 scale
            true_fair = [BayesianMGMFRM.AdditiveFacets._adjacent_expected_score(th, true_steps, collect(0.0:3.0)) for th in true_theta]
            open(joinpath(tr_dir, "truth.json"), "w") do io
                JSON3.write(io, Dict(
                    "case_id" => "0001_synth_dff",
                    "person_ability" => true_theta,
                    "true_fair_m" => true_fair,
                    "rater_severity" => true_rater,
                    "criterion_difficulty" => true_crit,
                    "dff_target_rater" => 1,
                    "dff_effect" => true_dff_r1,
                ))
            end
            open(joinpath(study_dir, "manifest.csv"), "w") do io
                println(io, "case_id,rep,seed,track,scenario,model,n_persons,n_raters,n_criteria,n_steps,raters_per_person,n_obs,ability_sd,shared_sd,impact,dff_effect,has_bias_group,has_validation_panel,input_relpath,input_sha256")
                println(io, "0001_synth_dff,1,1,B,dff_alt_r3,RSM,$n_p,$n_r,$n_c,3,3,$(length(s_col)),0.7,0.0,0.6,$true_dff_r1,true,false,inputs/0001_synth_dff/input.csv,$sha_in")
            end

            man = load_exchange_manifest(study_dir)
            @test man.n_cases == 1
            cdata = load_exchange_case(man.cases[1].case_dir; manifest_row = man.cases[1])
            @test cdata.input_sha256 == sha_in
            @test cdata.has_groups && cdata.n_persons == n_p && cdata.truth !== nothing

            # Tampered SHA-256 is rejected
            bad_row = merge(man.cases[1], (; input_sha256 = "0"^64))
            @test_throws ArgumentError load_exchange_case(man.cases[1].case_dir; manifest_row = bad_row)

            # Frequentist focal DFF scan -> Exchange Schema v1.0 output
            scan = BayesianMGMFRM.MRCML.focal_dff_scan(
                cdata.table;
                person = :person,
                score = :score,
                facets = (rater = :rater, criterion = :criterion),
                steps = :global,
                category_levels = cdata.category_levels,
                population = (roster = cdata.roster, person = :person, group = :group, reference = 0, equal_sd = true),
                dff_facet = :rater,
                targets = [1],
            )
            run_mmle = joinpath(study_dir, "runs", "mrcml_mmle", "0001_synth_dff")
            w_res = write_exchange_run(
                run_mmle, scan.null_fit;
                case_id = cdata.case_id, input_sha256 = cdata.input_sha256,
                estimator = "MRCML_MML_pop_LRT", model = "RSM", contrast_rows = scan.rows,
            )
            @test w_res.converged
            v_res = validate_exchange_run(run_mmle; require_contrast = true)
            @test v_res.valid && isempty(v_res.issues)
            ev_res = evaluate_exchange_case(run_mmle, cdata.truth)
            @test isfinite(ev_res.person_rmse) && isfinite(ev_res.fair_m_rmse)
            @test ev_res.dff !== nothing && isfinite(ev_res.dff.estimate) && isfinite(ev_res.dff.se)
            cmp_self = compare_exchange_runs(run_mmle, run_mmle)
            @test cmp_self.rater.max_abs_diff == 0.0 && cmp_self.contrast.estimate_diff == 0.0

            # Also verify ungrouped FrequentistMFRM.Spec (MMLE & JMLE) Exchange Schema v1.0 round-trip
            sp_ug = mfrm_spec(cdata.table; person = :person, score = :score,
                facets = (rater = :rater, criterion = :criterion),
                steps = :global, category_levels = cdata.category_levels, prior = :none)
            fit_ug_mml = fit(sp_ug; method = :mmle)
            fit_ug_jml = fit(sp_ug; method = :jmle, extreme_adjustment = 0.0)
            run_ug_mml = joinpath(study_dir, "runs", "ug_mml", "0001_synth_dff")
            run_ug_jml = joinpath(study_dir, "runs", "ug_jml", "0001_synth_dff")
            write_exchange_run(run_ug_mml, fit_ug_mml; case_id = cdata.case_id, input_sha256 = cdata.input_sha256,
                estimator = "MRCML_MML", model = "RSM")
            write_exchange_run(run_ug_jml, fit_ug_jml; case_id = cdata.case_id, input_sha256 = cdata.input_sha256,
                estimator = "MRCML_JML", model = "RSM")
            @test validate_exchange_run(run_ug_mml).valid
            @test validate_exchange_run(run_ug_jml).valid
        end
    end

    @testset "MRCML population HalfNormal/Half-t priors, equal_sd, and analytic gradients" begin
        for sp_dist in (
                D.LogNormal(-0.1, 0.45),
                D.truncated(D.Normal(0.0, 1.0), 0.0, Inf),
                D.truncated(D.TDist(4.0), 0.0, Inf),
                D.truncated(D.LocationScale(0.0, 0.8, D.TDist(4.0)), 0.0, Inf),
            ),
            eq_sd in (false, true),
            p_coord in (:noncentered, :centered)

            pop = (;
                roster, person = :person, group = :group, reference = 0,
                coefficient_prior = D.Normal(0.1, 1.5),
                sd_prior = sp_dist,
                person_coordinates = p_coord,
                equal_sd = eq_sd,
            )
            t = mfrm_spec(
                tbl;
                person = :person, score = :score,
                facets = (rater = :rater, criterion = :criterion),
                steps = :global, category_levels = 0:3,
                population = pop,
                interactions = ((:rater, :group) => D.truncated(D.LocationScale(0.0, 0.5, D.TDist(4.0)), 0.0, Inf),),
                prior_sd = (facets = (rater = 1.0, criterion = 1.0), step = 1.0),
            )
            @test length(t.spec_record.population.logsd) == (eq_sd ? 1 : 2)
            q = prior_draw(t; seed = 42)
            lp_f64, g_f64 = LDP.logdensity_and_gradient(t, q)
            lp_big = LDP.logdensity(t, BigFloat.(q))
            g_fd = ForwardDiff.gradient(x -> LDP.logdensity(t, x), q)
            @test isfinite(lp_f64)
            # The Float64 kernel sums 216 observations; Julia 1.10.8 differs
            # from the rounded BigFloat result by up to 9 ULPs on this fixture.
            reference = Float64(lp_big)
            @test abs(lp_f64 - reference) <= 16 * eps(abs(reference))
            @test maximum(abs, g_f64 .- g_fd) <= 1e-11

            # Persistence record round-trip
            t_rest = BayesianMGMFRM.AdditiveFacets.restore(BayesianMGMFRM.AdditiveFacets.record(t))
            lp_r, g_r = LDP.logdensity_and_gradient(t_rest, q)
            @test lp_r == lp_f64 && g_r == g_f64

            # Grouped volume-preserving Givens orthogonalization exactness (when noncentered)
            if p_coord === :noncentered
                gt = BayesianMGMFRM.AdditiveFacets._maybe_mrcml_givens_target(t)
                @test gt !== nothing
                u_back = BayesianMGMFRM.AdditiveFacets._givens_from_raw(gt, q)
                q_fwd = BayesianMGMFRM.AdditiveFacets._givens_to_raw(gt, u_back)
                @test maximum(abs, q_fwd .- q) <= 1e-13
                J_giv = ForwardDiff.jacobian(x -> BayesianMGMFRM.AdditiveFacets._givens_to_raw(gt, x), u_back)
                @test abs(logabsdet(J_giv)[1]) <= 1e-13
                lp_g, gr_g = LDP.logdensity_and_gradient(gt, u_back)
                gr_g_fd = ForwardDiff.gradient(x -> LDP.logdensity(gt, x), u_back)
                @test abs(lp_g - lp_f64) <= 1e-12
                @test maximum(abs, gr_g .- gr_g_fd) <= 1e-11
            end
        end
    end

    @testset "Unified frequentist & Bayesian rater×group DFF estimands, sandwich SEs & LRT" begin
        # 1) Frequentist doubly centered Kronecker-Helmert vs rest-of-panel scaling
        spec_dc_f = mfrm_spec(
            tbl;
            person = :person, score = :score,
            facets = (rater = :rater, criterion = :criterion),
            steps = :global, category_levels = 0:3,
            population = (roster = roster, person = :person, group = :group, reference = 0, equal_sd = true),
            interactions = ((:rater, :group),),
            prior = :none,
        )
        fit_dc_f = fit(spec_dc_f; method = :mmle)
        @test fit_dc_f.record.summary.converged
        c_pc = contrast(fit_dc_f; interaction = (:rater, :group), focal = 1, group = 1, reference = 0, estimand = :panel_centered)
        c_rp = contrast(fit_dc_f; interaction = (:rater, :group), focal = 1, group = 1, reference = 0, estimand = :vs_rest_of_panel)
        c_rp_snd = contrast(fit_dc_f; interaction = (:rater, :group), focal = 1, group = 1, reference = 0, estimand = :vs_rest_of_panel, se_type = :sandwich)
        @test c_rp.estimate ≈ (n_r / (n_r - 1)) * c_pc.estimate atol = 1e-12
        @test c_rp.observed_se ≈ (n_r / (n_r - 1)) * c_pc.observed_se atol = 1e-12
        @test c_rp_snd.se == c_rp.sandwich_se && isfinite(c_rp_snd.se) && c_rp_snd.se > 0.0

        # Group impact contrast with observed & sandwich SEs
        c_grp = contrast(fit_dc_f; group = 1, reference = 0)
        c_grp_snd = contrast(fit_dc_f; group = 1, reference = 0, se_type = :sandwich)
        @test c_grp.estimate == c_grp_snd.estimate
        @test isfinite(c_grp.observed_se) && isfinite(c_grp.sandwich_se)

        # Plausible values on equal_sd = true MMLE fit
        pvs_f = plausible_values(fit_dc_f; n_imputations = 5, seed = 7)
        @test isfinite(contrast(pvs_f; group = 1, reference = 0).estimate)

        # 2) Frequentist focal split-rater 1-df LRT & nesting check
        scan_all = BayesianMGMFRM.MRCML.focal_dff_scan(
            tbl;
            person = :person, score = :score,
            facets = (rater = :rater, criterion = :criterion),
            steps = :global, category_levels = 0:3,
            population = (roster = roster, person = :person, group = :group, reference = 0, equal_sd = true),
            dff_facet = :rater,
        )
        @test length(scan_all.rows) == n_r
        @test all(r -> r.df == 1 && isfinite(r.stat) && r.stat >= 0.0 && isfinite(r.observed_se) && isfinite(r.sandwich_se), scan_all.rows)

        # Check the fitted focal alternative's observed information and model SEs
        # against AD on the grouped marginal score at the same optimum and grid.
        focal = first(scan_all.rows).target_rater
        alt = scan_all.alt_fits[focal].record
        f_spec = mfrm_spec(tbl; person=:person, score=:score, facets=(rater=:rater,criterion=:criterion),
            steps=:global, category_levels=0:3,
            population=(;roster, person=:person, group=:group, reference=0, equal_sd=true),
            interactions=((;pair=(:rater,:group),focal),), prior=:none)
        fm = BayesianMGMFRM.FrequentistMFRM
        quad = fm.build_quadrature(scan_all.quadrature,scan_all.quad_points;sd=1.0)
        pop = f_spec.spec_record.population
        parts = fm._population_parts(f_spec,pop,ones(length(f_spec.person)))
        d = size(f_spec.operator.A_free,2)
        br = d+1:d+size(pop.X,2)
        sr = last(br)+1:length(alt.u_free)
        h_ad = ForwardDiff.jacobian(alt.u_free) do z
            g = similar(z)
            fm._grouped_mmle!(g,z,parts,quad,br,sr,f_spec.operator.c_pat)
            g
        end
        cov_ad = inv(Symmetric(h_ad))
        @test maximum(abs,inv(alt.covariance.free_covariance) - h_ad) <= 1e-11
        @test maximum(abs,sqrt.(diag(alt.covariance.free_covariance)) - sqrt.(diag(cov_ad))) <= 1e-10

        # Cannot split all raters simultaneously in focal mode (zero invariant anchors left)
        @test_throws ArgumentError mfrm_spec(
            tbl; person = :person, score = :score,
            facets = (rater = :rater, criterion = :criterion),
            steps = :global, category_levels = 0:3,
            population = (roster = roster, person = :person, group = :group, reference = 0),
            interactions = ((; pair = (:rater, :group), focal = collect(1:n_r)),),
            prior = :none,
        )

        # 3) Short Bayesian NUTS fit with HalfNormal equal_sd + Half-t(df=4) doubly centered DFF
        spec_b = mfrm_spec(
            tbl;
            person = :person, score = :score,
            facets = (rater = :rater, criterion = :criterion),
            steps = :global, category_levels = 0:3,
            population = (
                roster = roster, person = :person, group = :group, reference = 0,
                coefficient_prior = D.Normal(0.0, 2.5),
                sd_prior = D.truncated(D.Normal(0.0, 1.0), 0.0, Inf),
                equal_sd = true,
            ),
            interactions = ((:rater, :group) => D.truncated(D.LocationScale(0.0, 0.5, D.TDist(4.0)), 0.0, Inf),),
            prior_sd = (facets = (rater = 1.0, criterion = 1.0), step = 1.0),
        )
        fit_b = fit(spec_b; chains = 2, warmup = 60, ndraws = 60, seed = 91)
        cb_pc = contrast(fit_b; interaction = (:rater, :group), focal = 1, group = 1, reference = 0, estimand = :panel_centered)
        cb_rp = contrast(fit_b; interaction = (:rater, :group), focal = 1, group = 1, reference = 0, estimand = :vs_rest_of_panel)
        @test cb_rp.mean ≈ (n_r / (n_r - 1)) * cb_pc.mean atol = 1e-12
        cb_all = contrast(fit_b; interaction = (:rater, :group), group = 1, reference = 0)
        @test length(cb_all.rows) == n_r
        pb = diagnostics(fit_b; kind = :pair_bias, pair = (:rater, :group))
        @test pb.analysis_mode === :joint_interaction_model && pb.n_cells == 2 * n_r
        pvs_b = plausible_values(fit_b)
        @test isfinite(contrast(fit_b; group = 1, reference = 0).estimate)
        @test contrast(fit_b; group = 1, reference = 0).estimate ≈ contrast(pvs_b; group = 1, reference = 0).estimate atol = 1e-12
    end
end

end # module _TestP21ExchangeSchemaAndGroupDFF
