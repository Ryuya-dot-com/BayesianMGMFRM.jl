using Test
using BayesianMGMFRM
using JSON3
using Random
using SHA
using Statistics

const _SA_T = BayesianMGMFRM.StanAdapter
const _PH_T = BayesianMGMFRM.PortableHandoff

function _write_synthetic_cmdstan_csv(path::AbstractString, chain_id::Int, ndraws::Int; seed::Int = 20261118)
    rng = Random.MersenneTwister(seed + 1000 * chain_id)
    cols = [
        "lp__", "accept_stat__", "stepsize__", "treedepth__", "n_leapfrog__", "divergent__", "energy__",
        "theta.1", "theta.2", "theta.3", "theta.4",
        "rater.2", "rater.3",
        "item.2", "item.3",
        "step.1", "step.2",
        "log_lik.1", "log_lik.2", "log_lik.3", "log_lik.4", "log_lik.5", "log_lik.6",
        "log_prior", "log_prior_wide",
    ]
    open(path, "w") do io
        println(io, "# stan_version_major = 2")
        println(io, "# stan_version_minor = 39")
        println(io, "# stan_version_patch = 0")
        println(io, "# method = sample (Default)")
        println(io, "#   sample")
        println(io, "#     num_samples = $ndraws")
        println(io, "#     num_warmup = 100")
        println(io, "#     adapt")
        println(io, "#       delta = 0.9")
        println(io, "#     algorithm = hmc (Default)")
        println(io, "#       nuts")
        println(io, "#         max_depth = 10")
        println(io, "#   random")
        println(io, "#     seed = $seed")
        println(io, "#     id = $chain_id")
        println(io, join(cols, ","))
        for s in 1:ndraws
            th = [-0.8 + 0.15 * randn(rng), -0.2 + 0.15 * randn(rng), 0.35 + 0.15 * randn(rng), 0.95 + 0.15 * randn(rng)]
            rt = [0.25 + 0.10 * randn(rng), -0.30 + 0.10 * randn(rng)]
            it = [0.20 + 0.10 * randn(rng), -0.20 + 0.10 * randn(rng)]
            st1 = -0.45 + 0.08 * randn(rng)
            st2 = -st1
            lls = [-0.9 - 0.15 * abs(randn(rng)) for _ in 1:6]
            lp_prior = -0.5 * (sum(abs2, th) + sum(abs2, rt) + sum(abs2, it) + st1^2)
            lp_wide = -0.5 * (sum(abs2, th) / 4.0 + sum(abs2, rt) / 4.0 + sum(abs2, it) / 4.0 + st1^2 / 4.0) - 6.0 * log(2.0)
            lp_tot = lp_prior + sum(lls)
            energy = -lp_tot + 4.5 + 0.8 * randn(rng)
            vals = Float64[
                lp_tot, 0.91, 0.08, 3.0, 7.0, 0.0, energy,
                th..., rt..., it..., st1, st2, lls..., lp_prior, lp_wide,
            ]
            println(io, join([string(v) for v in vals], ","))
        end
    end
    return path
end

@testset "StanAdapter & PortableHandoff freeze (FF4b)" begin
    mktempdir() do dir
        csvs = [_write_synthetic_cmdstan_csv(joinpath(dir, "ch_$c.csv"), c, 250) for c in 1:4]
        roles = (
            parameters = (
                person = ["theta.1", "theta.2", "theta.3", "theta.4"],
                rater = ["rater.1", "rater.2", "rater.3"],
                item = ["item.1", "item.2", "item.3"],
                thresholds = ["step.1", "step.2"],
            ),
            fixed = (
                rater = ["rater.1" => 0.0],
                item = ["item.1" => 0.0],
            ),
            log_lik = (
                columns = ["log_lik.$i" for i in 1:6],
                unit = :rating,
                dataset_id = "synth_6",
                observation_ids = ["obs_$i" for i in 1:6],
            ),
            log_prior = "log_prior",
            alt_log_priors = (wide_prior = "log_prior_wide",),
        )

        # Explicit role guards (zero guessing)
        @test_throws ArgumentError _SA_T.import_csv(csvs; roles = (;))
        @test_throws ArgumentError _SA_T.import_csv(csvs; roles = (parameters = (person = ["nonexistent_col"],),))

        sf = _SA_T.import_csv(csvs; roles)
        @test sf isa _SA_T.Fit
        @test occursin("StanAdapter.Fit", sprint(show, sf))

        # Layer-2 & Layer-1 inspection on StanAdapter.Fit
        c = contract(sf)
        @test c.explicit_roles_required == true
        @test c.arbitrary_stan_parser == false
        @test c.implicit_variable_guessing == false
        @test design_summary(sf).total_draws == 1000
        @test validate_design(sf).passed == true
        @test length(parameter_names(sf; scale = :model)) == 12
        @test length(parameter_names(sf; scale = :raw)) == 10
        @test sampler_controls(sf).chains == 4

        q = qualify(sf)
        @test q.qualified == true
        @test qualify(sf; min_ess = 2000.0).qualified == false
        @test q.telemetry_complete == true
        @test diagnostics(sf).schema == "bayesianmgmfrm.stan_adapter_diagnostics.v1"

        ps = posterior_summary(sf; interval = 0.90)
        @test length(ps.rows) == 12
        @test only([r for r in ps.rows if r.parameter == "rater.1"]).structurally_fixed == true
        @test length(posterior_mcse(sf)) == 12

        fs = facet_summary(sf; facet = :rater)
        @test fs.n_levels == 3
        ct = contrast(sf; left = "rater.2", right = "rater.3", rope = (-0.1, 0.1))
        @test isfinite(ct.result.mean)

        rk = ranking(sf; facet = :person, top_k = 2)
        @test rk.n_levels == 4
        @test rk.rows[4].mean < rk.rows[1].mean
        # Fixed anchors refused in cohort ranking
        @test_throws ArgumentError ranking(sf; parameters = ["rater.1", "rater.2"])

        rel = reliability(sf; facet = :person)
        @test 0.0 < mean(rel.reliability) < 1.0

        cls = classification(sf; cutoff = 0.0, pass_probability = 0.7)
        @test cls.cohort.n_people == 4

        w = waic(sf)
        l = psis_loo(sf)
        cr = criteria(sf)
        @test isfinite(w.elpd_waic) && isfinite(l.elpd_loo)
        @test cr.scores.psis_loo.elpd_loo == l.elpd_loo
        @test size(pointwise_loglikelihood_matrix(sf)) == (1000, 6)
        @test length(logprior(sf)) == 1000
        @test length(loglikelihood(sf)) == 1000
        @test length(logposterior(sf)) == 1000

        # Model comparison & observation_binding guard
        csvs2 = [_write_synthetic_cmdstan_csv(joinpath(dir, "ch2_$c.csv"), c, 250; seed = 20261119) for c in 1:4]
        sf2 = _SA_T.import_csv(csvs2; roles)
        cmp = compare_models(["ModelA" => sf, "ModelB" => sf2]; criterion = :psis_loo)
        @test cmp.schema == _SA_T.COMPARISON_SCHEMA
        @test length(cmp.rows) == 2
        @test cmp.rows[1].elpd_difference == 0.0

        roles_diff_obs = merge(roles, (; log_lik = merge(roles.log_lik, (; observation_ids = ["x_$i" for i in 1:6]))))
        sf_diff = _SA_T.import_csv(csvs2; roles = roles_diff_obs)
        @test_throws ArgumentError compare_models(["ModelA" => sf, "DiffObs" => sf_diff]; criterion = :psis_loo)

        roles_perf = merge(roles, (; log_lik = merge(roles.log_lik, (; unit = :performance))))
        sf_perf = _SA_T.import_csv(csvs; roles = roles_perf)
        @test_throws ArgumentError waic(sf_perf)
        @test haskey(criteria(sf_perf).scores, :psis_loo) && !haskey(criteria(sf_perf).scores, :waic)

        # PSIS prior-sensitivity reweighting
        sens1 = prior_sensitivity(sf, :wide_prior)
        @test sens1.schema == _SA_T.PRIOR_SENSITIVITY_SCHEMA
        @test isfinite(sens1.pareto_k)
        sens2 = prior_sensitivity(sf, "identity_shift" => logprior(sf))
        @test sens2.status === :reliable
        @test maximum(abs(r.mean_shift) for r in sens2.rows) < 1e-12
        sens3 = prior_sensitivity(sf, nt -> -0.5 * (
            (nt.var"theta.1"^2 + nt.var"theta.2"^2 + nt.var"theta.3"^2 + nt.var"theta.4"^2 +
             nt.var"rater.2"^2 + nt.var"rater.3"^2 + nt.var"item.2"^2 + nt.var"item.3"^2 + nt.var"step.1"^2) / 4.0) - 6.0 * log(2.0))
        @test sens3.pareto_k ≈ sens1.pareto_k atol = 1e-12

        # Generative verb refusals
        for fn in (coordinates, logdensity_and_gradient, stan_data, predictive_check, event_probabilities, category_summary)
            @test_throws ArgumentError fn(sf)
        end

        # Persistence: native .jls & portable JSON reports
        jls_path = joinpath(dir, "stan_fit.jls")
        save_fit(jls_path, sf)
        @test_throws ArgumentError save_fit(jls_path, sf)
        sf_reloaded = load_fit(jls_path)
        @test sf_reloaded.record.content_hash == sf.record.content_hash

        rep_path = joinpath(dir, "stan_rep.json")
        rec_rep = save_report(rep_path, fit_report(sf; include_draws = true); return_receipt = true)
        loaded_rep = load_report(rep_path; expected_sha256 = rec_rep.sha256)
        @test String(loaded_rep.schema) == _SA_T.REPORT_SCHEMA

        cmp_path = joinpath(dir, "stan_cmp.json")
        rec_cmp = save_report(cmp_path, cmp; return_receipt = true)
        @test String(load_report(cmp_path; expected_sha256 = rec_cmp.sha256).schema) == _SA_T.COMPARISON_SCHEMA

        sens_path = joinpath(dir, "stan_sens.json")
        rec_sens = save_report(sens_path, sens1; return_receipt = true)
        @test String(load_report(sens_path; expected_sha256 = rec_sens.sha256).schema) == _SA_T.PRIOR_SENSITIVITY_SCHEMA

        # PortableHandoff bit-exact IEEE-754 round-trip & tamper detection
        ho = _PH_T.export_handoff(sf; scale = :model, include_log_lik = true, include_log_prior = true)
        @test ho isa _PH_T.Handoff
        ho_path = joinpath(dir, "handoff_sf.json")
        ho_rec = save_report(ho_path, ho; return_receipt = true)
        @test_throws ArgumentError load_report(ho_path) # expected_sha256 is mandatory!
        @test_throws ArgumentError load_report(ho_path; expected_sha256 = "0"^64)

        ho_loaded = load_report(ho_path; expected_sha256 = ho_rec.sha256)
        @test ho_loaded isa _PH_T.Handoff
        # Exact 0.0 ULP bit-for-bit equality
        @test ho_loaded.fit.record.run.draws == sf.record.run.draws
        @test ho_loaded.fit.record.run.logdensities == sf.record.run.logdensities
        @test ho_loaded.fit.record.log_lik == sf.record.log_lik
        @test ho_loaded.fit.record.log_prior == sf.record.log_prior
        @test psis_loo(ho_loaded).elpd_loo == l.elpd_loo
        @test contrast(ho_loaded; left = "rater.2", right = "rater.3").result.mean == ct.result.mean

        # Internal payload tamper detection even if outer file SHA-256 is recomputed
        tampered_obj = JSON3.read(read(ho_path, String), Dict{String, Any})
        tampered_obj["draws"][1][1] = Float64(tampered_obj["draws"][1][1]) + 1e-6
        tampered_path = joinpath(dir, "handoff_tampered.json")
        write(tampered_path, JSON3.write(tampered_obj))
        tampered_sha = bytes2hex(SHA.sha256(read(tampered_path)))
        @test_throws ArgumentError load_report(tampered_path; expected_sha256 = tampered_sha)

        # Export handoff from native MFRMFit and AdditiveFacets.Fit
        tbl = (
            person = repeat(["P1", "P2", "P3", "P4"], inner = 4),
            rater = repeat(["R1", "R2"], outer = 8),
            item = repeat(["I1", "I2"], inner = 2, outer = 4),
            score = [0, 1, 1, 2, 0, 0, 1, 1, 1, 1, 2, 2, 1, 2, 2, 2],
        )
        fd = FacetData(tbl; person = :person, rater = :rater, item = :item, score = :score, category_levels = [0, 1, 2])
        mf = fit(mfrm_spec(fd); chains = 2, warmup = 30, ndraws = 30, seed = 42)
        ho_mf = _PH_T.export_handoff(mf; scale = :model, include_log_lik = true, include_log_prior = true)
        p_mf = joinpath(dir, "ho_mf.json")
        r_mf = save_report(p_mf, ho_mf; return_receipt = true)
        ho_mf_re = load_report(p_mf; expected_sha256 = r_mf.sha256)
        @test ho_mf_re.fit.record.run.draws == ho_mf.fit.record.run.draws
        @test psis_loo(ho_mf_re).elpd_loo ≈ criteria(mf; criteria = (:psis_loo,)).psis_loo.elpd_loo atol = 1e-12

        af_spec = mfrm_spec(tbl; person = :person, score = :score,
            facets = (rater = :rater, item = :item), steps = :global, category_levels = 0:2,
            prior_sd = (person = 1.0, facets = (rater = 1.0, item = 1.0), step = 1.0))
        af_fit = fit(af_spec; chains = 2, warmup = 30, ndraws = 30, seed = 43)
        ho_af = _PH_T.export_handoff(af_fit; scale = :model, include_log_lik = true, include_log_prior = true)
        p_af = joinpath(dir, "ho_af.json")
        r_af = save_report(p_af, ho_af; return_receipt = true)
        ho_af_re = load_report(p_af; expected_sha256 = r_af.sha256)
        @test ho_af_re.fit.record.run.draws == ho_af.fit.record.run.draws

        # CairoMakie figure checks if extension is loaded
        if Base.get_extension(BayesianMGMFRM, :BayesianMGMFRMCairoMakieExt) !== nothing
            io_buf = IOBuffer()
            @test BayesianMGMFRM.plot(sf; kind = :posterior, annotation_io = io_buf) !== nothing
            @test BayesianMGMFRM.plot(sf; kind = :diagnostics, parameters = ["theta.1", "rater.2"], annotation_io = io_buf) !== nothing
            @test BayesianMGMFRM.plot(loaded_rep; kind = :diagnostics, parameters = ["theta.1"], annotation_io = io_buf) !== nothing
            @test BayesianMGMFRM.plot(sf; kind = :wright, annotation_io = io_buf) !== nothing
            @test BayesianMGMFRM.plot(cmp; kind = :comparison, annotation_io = io_buf) !== nothing
            @test BayesianMGMFRM.plot(sens1; kind = :prior_sensitivity, annotation_io = io_buf) !== nothing
        end

        # Live CmdStan 2.39+ seed-reproducibility smoke check if available
        if cmdstan_backend_check().runtime_ready
            stan_code = """
            data {
              int<lower=1> N;
              array[N] int<lower=0, upper=1> y;
            }
            parameters {
              real theta;
            }
            model {
              theta ~ normal(0, 1);
              y ~ bernoulli_logit(theta);
            }
            generated quantities {
              vector[N] log_lik;
              real log_prior = normal_lpdf(theta | 0, 1);
              for (n in 1:N) log_lik[n] = bernoulli_logit_lpmf(y[n] | theta);
            }
            """
            stan_file = joinpath(dir, "mini_bern.stan")
            write(stan_file, stan_code)
            sdata = Dict("N" => 6, "y" => [1, 0, 1, 1, 0, 1])
            sroles = (
                parameters = (person = ["theta"],),
                log_lik = (columns = ["log_lik.$i" for i in 1:6], unit = :rating, observation_ids = ["y$i" for i in 1:6]),
                log_prior = "log_prior",
            )
            f_run1 = _SA_T.fit_stan(stan_file, sdata; roles = sroles, chains = 2, warmup = 60, ndraws = 60, seed = 20261118)
            f_run2 = _SA_T.fit_stan(stan_file, sdata; roles = sroles, chains = 2, warmup = 60, ndraws = 60, seed = 20261118)
            # Exact 0.0 ULP reproducibility across identical seeds!
            @test f_run1.record.run.draws == f_run2.record.run.draws
            @test f_run1.record.run.logdensities == f_run2.record.run.logdensities
            @test f_run1.record.log_lik == f_run2.record.log_lik
            @test f_run1.record.provenance.stan_source_sha256 == f_run2.record.provenance.stan_source_sha256
        end
    end
end
