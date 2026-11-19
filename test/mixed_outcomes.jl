using Test, BayesianMGMFRM, Distributions, ForwardDiff, LinearAlgebra, Random, Statistics, SHA
import LogDensityProblems as L
import BayesianMGMFRM: fit

function mixed_speaking_fixture()
    # 6 speakers x 2 clips = 12 performances, 4 listeners -> 24 events
    speakers = String[]; clips = String[]; listeners = String[]
    rate = Float64[]; accent = Float64[]; comp = Int[]
    intel = Vector{Union{Missing,Int}}(); trials = Int[]; cond = String[]
    rng = MersenneTwister(20261117)
    all_listeners = ["L1", "L2", "L3", "L4"]
    for s_i in 1:6, c_i in 1:2
        spk = "S$s_i"; clp = "S$(s_i)_C$(c_i)"
        r_val = round(3.0 + 0.35 * (s_i - 3.5) + (c_i == 1 ? -0.3 : 0.3); digits = 3)
        # Assign 2 distinct listeners per clip so every speaker, clip, and listener is well connected
        pair = [all_listeners[mod1(s_i + c_i - 1, 4)], all_listeners[mod1(s_i + c_i + 1, 4)]]
        for (li_pos, lst) in enumerate(pair)
            push!(speakers, spk); push!(clips, clp); push!(listeners, lst)
            push!(rate, r_val)
            # Include exact 0.0 and 100.0 endpoints on ZOIB alongside interior values
            ev_id = length(speakers)
            acc_v = ev_id == 1 ? 0.0 : ev_id == 6 ? 100.0 : clamp(round(52.0 + 9.0 * (s_i - 3.5) - 4.0 * li_pos + 6.0 * randn(rng); digits = 1), 5.0, 95.0)
            push!(accent, acc_v)
            push!(comp, clamp(round(Int, 3.0 + 0.55 * (s_i - 3.5) - 0.3 * li_pos + 0.6 * randn(rng)), 1, 5))
            nt = isodd(ev_id) ? 10 : 12
            push!(trials, nt)
            # Partial-outcome mask (C5): every 4th event omits transcription (`without` condition)
            if mod(ev_id, 4) == 0
                push!(cond, "without")
                push!(intel, missing)
            else
                push!(cond, "with")
                p_c = 1.0 / (1.0 + exp(-(0.7 + 0.45 * (s_i - 3.5) - 0.25 * li_pos)))
                push!(intel, rand(rng, Binomial(nt, p_c)))
            end
        end
    end
    return (; speaker = speakers, clip = clips, listener = listeners, rate,
              accent, comp, intel, words_total = trials, condition = cond)
end

@testset "Mixed-outcome joint targets: scalar reductions, ForwardDiff gradients, identification, and owner-aware prediction" begin
    A = BayesianMGMFRM.AdditiveFacets
    d = mixed_speaking_fixture()

    # 1. Exact M=1 scalar reductions (<= 1e-14) to BoundedTarget, CountTarget, and ExplanatoryTarget
    @testset "Exact M=1 scalar reductions" begin
        function scalar_equiv_name(n::String, oname::String)
            n == "intercept[$oname].white" && return "coefficient[intercept].white"
            n == "log_precision[$oname].white" && return "log_precision.white"
            n == "endpoint_logit[$oname].white" && return "endpoint_logit.white"
            n == "upper_logit[$oname].white" && return "upper_logit.white"
            if startswith(n, "steps[$oname,")
                return replace(replace(n, "steps[$oname," => "steps[:global,"), ".white" => "")
            end
            return replace(n, "[$oname," => "[")
        end

        # 1a. M=1 ZOIB vs BoundedTarget
        spec_b = mfrm_spec(d;
            person = :speaker, score = :accent,
            facets = (recording = :clip, listener = :listener),
            performance = :clip,
            observation = (family = :zero_one_inflated_beta, bounds = (0.0, 100.0)),
            observation_prior = (precision = LogNormal(log(10.0), 0.4), endpoint_logit = Normal(-2.0, 0.8), upper_logit = Normal(0.1, 0.8)),
            population = (person = LogNormal(log(0.7), 0.35), recording = 0.3, listener = LogNormal(log(0.4), 0.35)),
            intercept = Normal(0.2, 1.2),
            decompose = (rate = (between = :mean_rate, within = :rate_change),),
            predictors = (response = (mean_rate = Normal(0.0, 0.8), rate_change = Normal(0.0, 0.8)),),
        )
        spec_m_b = mfrm_spec(d;
            person = :speaker,
            facets = (recording = :clip, listener = :listener),
            performance = :clip,
            outcomes = (accent = (
                family = :zero_one_inflated_beta, score = :accent, bounds = (0.0, 100.0),
                intercept = Normal(0.2, 1.2), precision = LogNormal(log(10.0), 0.4),
                endpoint_logit = Normal(-2.0, 0.8), upper_logit = Normal(0.1, 0.8),
            ),),
            population = (person = LogNormal(log(0.7), 0.35), recording = 0.3, listener = LogNormal(log(0.4), 0.35)),
            decompose = (rate = (between = :mean_rate, within = :rate_change),),
            predictors = (response = (mean_rate = Normal(0.0, 0.8), rate_change = Normal(0.0, 0.8)),),
        )
        @test spec_m_b isa A.MixedOutcomeTarget
        @test spec_b.dimension == spec_m_b.dimension
        names_b = parameter_names(spec_b; scale = :raw)
        names_m_b = [scalar_equiv_name(n, "accent") for n in parameter_names(spec_m_b; scale = :raw)]
        @test Set(names_b) == Set(names_m_b)
        perm_b = [findfirst(==(n), names_b) for n in names_m_b]
        rng_chk = MersenneTwister(41)
        for _ in 1:4
            q = 0.6 .* randn(rng_chk, spec_b.dimension)
            q_m = q[perm_b]
            @test logprior(spec_m_b, q_m) ≈ logprior(spec_b, q) atol = 1e-14 rtol = 1e-14
            @test pointwise_loglikelihood(spec_m_b, q_m) ≈ pointwise_loglikelihood(spec_b, q) atol = 1e-14 rtol = 1e-14
            v_b, g_b = logdensity_and_gradient(spec_b, q)
            v_m, g_m = logdensity_and_gradient(spec_m_b, q_m)
            @test v_m ≈ v_b atol = 1e-14 rtol = 1e-14
            @test maximum(abs.(g_m .- g_b[perm_b])) <= 1e-14
        end

        # 1b. M=1 Beta-Binomial vs CountTarget (on observed transcription subset)
        obs_ix = findall(!ismissing, d.intel)
        d_cnt = (; speaker = d.speaker[obs_ix], clip = d.clip[obs_ix], listener = d.listener[obs_ix],
                   intel = Int[d.intel[i] for i in obs_ix], words_total = d.words_total[obs_ix], rate = d.rate[obs_ix])
        spec_c = mfrm_spec(d_cnt;
            person = :speaker, score = :intel,
            facets = (recording = :clip, listener = :listener),
            observation = (family = :beta_binomial, trials = :words_total),
            observation_prior = (precision = LogNormal(log(15.0), 0.45),),
            population = (person = LogNormal(log(0.6), 0.35), recording = 0.25, listener = LogNormal(log(0.4), 0.35)),
            intercept = Normal(0.5, 1.0),
            predictors = (response = (rate = Normal(0.0, 0.7),),),
        )
        spec_m_c = mfrm_spec(d_cnt;
            person = :speaker,
            facets = (recording = :clip, listener = :listener),
            outcomes = (intel = (
                family = :beta_binomial, score = :intel, trials = :words_total,
                intercept = Normal(0.5, 1.0), precision = LogNormal(log(15.0), 0.45),
            ),),
            population = (person = LogNormal(log(0.6), 0.35), recording = 0.25, listener = LogNormal(log(0.4), 0.35)),
            predictors = (response = (rate = Normal(0.0, 0.7),),),
        )
        @test spec_c.dimension == spec_m_c.dimension
        names_c = parameter_names(spec_c; scale = :raw)
        names_m_c = [scalar_equiv_name(n, "intel") for n in parameter_names(spec_m_c; scale = :raw)]
        @test Set(names_c) == Set(names_m_c)
        perm_c = [findfirst(==(n), names_c) for n in names_m_c]
        for _ in 1:4
            q = 0.6 .* randn(rng_chk, spec_c.dimension)
            q_m = q[perm_c]
            @test logprior(spec_m_c, q_m) ≈ logprior(spec_c, q) atol = 1e-14 rtol = 1e-14
            @test pointwise_loglikelihood(spec_m_c, q_m) ≈ pointwise_loglikelihood(spec_c, q) atol = 1e-14 rtol = 1e-14
            v_c, g_c = logdensity_and_gradient(spec_c, q)
            v_m, g_m = logdensity_and_gradient(spec_m_c, q_m)
            @test v_m ≈ v_c atol = 1e-14 rtol = 1e-14
            @test maximum(abs.(g_m .- g_c[perm_c])) <= 1e-14
        end

        # 1c. M=1 Ordinal vs ExplanatoryTarget
        spec_o = mfrm_spec(d;
            person = :speaker, score = :comp,
            facets = (recording = :clip, listener = :listener),
            steps = :global, category_levels = 1:5,
            prior_sd = (step = 0.9, facets = (;)),
            population = (person = LogNormal(log(0.75), 0.35), recording = 0.3, listener = LogNormal(log(0.4), 0.35)),
            intercept = Normal(-0.1, 1.0),
            predictors = (response = (rate = Normal(0.0, 0.6),),),
        )
        spec_m_o = mfrm_spec(d;
            person = :speaker,
            facets = (recording = :clip, listener = :listener),
            outcomes = (comp = (
                family = :ordinal, score = :comp, categories = 1:5, step_sd = 0.9,
                intercept = Normal(-0.1, 1.0),
            ),),
            population = (person = LogNormal(log(0.75), 0.35), recording = 0.3, listener = LogNormal(log(0.4), 0.35)),
            predictors = (response = (rate = Normal(0.0, 0.6),),),
        )
        @test spec_o.dimension == spec_m_o.dimension
        names_o = parameter_names(spec_o; scale = :raw)
        names_m_o = [scalar_equiv_name(n, "comp") for n in parameter_names(spec_m_o; scale = :raw)]
        @test Set(names_o) == Set(names_m_o)
        perm_o = [findfirst(==(n), names_o) for n in names_m_o]
        for _ in 1:4
            q = 0.6 .* randn(rng_chk, spec_o.dimension)
            q_m = q[perm_o]
            @test logprior(spec_m_o, q_m) ≈ logprior(spec_o, q) atol = 1e-14 rtol = 1e-14
            @test pointwise_loglikelihood(spec_m_o, q_m) ≈ pointwise_loglikelihood(spec_o, q) atol = 1e-14 rtol = 1e-14
            v_o, g_o = logdensity_and_gradient(spec_o, q)
            v_m, g_m = logdensity_and_gradient(spec_m_o, q_m)
            @test v_m ≈ v_o atol = 1e-14 rtol = 1e-14
            @test maximum(abs.(g_m .- g_o[perm_o]) ./ max.(1.0, abs.(g_o[perm_o]))) <= 1e-14
        end
    end

    # 2. Multi-outcome heterogeneous ForwardDiff gradient parity (1D/2D/3D LKJ, free LogNormal & Normal loadings, partial masks, higher_is_less)
    outcomes_3 = (
        accent = (
            family = :zero_one_inflated_beta, score = :accent, bounds = (0.0, 100.0),
            direction = :higher_is_less,
            intercept = Normal(0.0, 1.5), precision = LogNormal(log(12.0), 0.45),
            endpoint_logit = Normal(-2.2, 0.9), upper_logit = Normal(0.0, 0.9),
        ),
        comp = (
            family = :ordinal, score = :comp, categories = 1:5, step_sd = 1.0,
            intercept = Normal(0.0, 1.5),
        ),
        intel = (
            family = :beta_binomial, score = :intel, trials = :words_total,
            intercept = Normal(0.8, 1.5), precision = LogNormal(log(18.0), 0.45),
        ),
    )
    pop_2d_3d = (
        person = (
            dimensions = (:pronunciation, :intelligibility),
            sds = (pronunciation = LogNormal(log(0.8), 0.35), intelligibility = LogNormal(log(0.7), 0.35)),
            correlation = LKJ(2, 2.2),
            loadings = (
                accent = (1.0, 0.0),
                comp = (LogNormal(0.0, 0.35), Normal(0.2, 0.3)),
                intel = (0.0, 1.0),
            ),
        ),
        recording = (sd = LogNormal(log(0.35), 0.35), loadings = (accent = 1.0, comp = LogNormal(0.0, 0.3), intel = 0.8)),
        listener = (
            dimensions = (:acc_sev, :comp_sev, :int_sev),
            sds = (acc_sev = LogNormal(log(0.45), 0.35), comp_sev = LogNormal(log(0.4), 0.35), int_sev = 0.35),
            correlation = LKJ(3, 1.8),
            loadings = (
                accent = (1.0, 0.0, 0.0),
                comp = (0.0, 1.0, 0.0),
                intel = (0.0, 0.0, 1.0),
            ),
        ),
    )
    spec_joint = mfrm_spec(d;
        person = :speaker,
        facets = (recording = :clip, listener = :listener),
        performance = :clip,
        outcomes = outcomes_3,
        population = pop_2d_3d,
        decompose = (rate = (between = :mean_rate, within = :rate_change),),
        predictors = (
            response = (
                mean_rate = Normal(0.0, 0.8),
                rate_change = (accent = Normal(0.0, 0.8), comp = Normal(0.0, 0.8), intel = nothing),
            ),
        ),
    )
    @test validate_design(spec_joint).identified
    rng_fd = MersenneTwister(99)
    for pt in (zeros(spec_joint.dimension), 0.5 .* randn(rng_fd, spec_joint.dimension), 1.4 .* randn(rng_fd, spec_joint.dimension))
        val, grad = logdensity_and_gradient(spec_joint, pt)
        fd_grad = ForwardDiff.gradient(x -> L.logdensity(spec_joint, x), pt)
        rel_err = maximum(abs.(grad .- fd_grad) ./ max.(1.0, abs.(fd_grad)))
        @test isfinite(val)
        @test rel_err <= 1e-11
    end

    # Round-trip record / restore & Stan data export
    rec_j = A.record(spec_joint)
    restored_j = A.restore(rec_j)
    q_rt = prior_draw(spec_joint; seed = 7)
    @test logposterior(restored_j, q_rt) ≈ logposterior(spec_joint, q_rt) atol = 1e-14
    sdata = stan_data(spec_joint)
    @test sdata["E"] == 24 && sdata["M"] == 3 && sdata["D"] == spec_joint.dimension

    # 3. Structural identification & C1/C2/C5/C7 refusal gates
    @testset "Identification and refusal counterexamples" begin
        # C1: Fractional counts refused
        d_frac = merge(d, (; intel = Any[i == 1 ? 3.5 : d.intel[i] for i in eachindex(d.intel)]))
        @test_throws ArgumentError mfrm_spec(d_frac; person = :speaker, facets = (recording = :clip, listener = :listener), outcomes = outcomes_3, population = (person = 0.7, recording = 0.3, listener = 0.4))

        # C5: Completely unobserved event refused
        d_empty = merge(d, (;
            accent = Union{Missing,Float64}[i == 2 ? missing : d.accent[i] for i in eachindex(d.accent)],
            comp = Union{Missing,Int}[i == 2 ? missing : d.comp[i] for i in eachindex(d.comp)],
            intel = Union{Missing,Int}[i == 2 ? missing : d.intel[i] for i in eachindex(d.intel)],
        ))
        @test_throws ArgumentError mfrm_spec(d_empty; person = :speaker, facets = (recording = :clip, listener = :listener), outcomes = outcomes_3, population = (person = 0.7, recording = 0.3, listener = 0.4))

        # Scale confounding: estimated LogNormal SD + all free loadings (no fixed anchor)
        bad_scale_pop = (
            person = (sd = LogNormal(0.0, 0.4), loadings = (accent = LogNormal(0.0, 0.3), comp = LogNormal(0.0, 0.3), intel = LogNormal(0.0, 0.3))),
            recording = 0.3, listener = 0.4,
        )
        spec_bad_scale = mfrm_spec(d; person = :speaker, facets = (recording = :clip, listener = :listener), outcomes = outcomes_3, population = bad_scale_pop)
        @test !validate_design(spec_bad_scale).identified
        @test_throws ArgumentError fit(spec_bad_scale; chains = 2, warmup = 10, ndraws = 10, seed = 1)

        # Rotational confounding: unconstrained Normal cross-loading in upper triangle
        bad_rot_pop = (
            person = (
                dimensions = (:d1, :d2),
                sds = (d1 = 1.0, d2 = 1.0),
                correlation = LKJ(2, 2.0),
                loadings = (accent = (1.0, Normal(0.0, 0.5)), comp = (Normal(0.0, 0.5), 1.0), intel = (0.0, 1.0)),
            ),
            recording = 0.3, listener = 0.4,
        )
        spec_bad_rot = mfrm_spec(d; person = :speaker, facets = (recording = :clip, listener = :listener), outcomes = outcomes_3, population = bad_rot_pop)
        @test !validate_design(spec_bad_rot).identified

        # C2: Confounded hierarchy (speaker == clip 1-to-1) refused by Frobenius covariance-Gram screen
        d_conf = merge(d, (; clip = copy(d.speaker)))
        spec_conf = mfrm_spec(d_conf; person = :speaker, facets = (recording = :clip, listener = :listener), outcomes = outcomes_3, population = (person = 0.7, recording = 0.3, listener = 0.4))
        @test !validate_design(spec_conf).identified

        # C2: Free LKJ correlation between two dimensions when NO speaker observes both outcomes (disjoint sub-study cohorts) is refused,
        # whereas when the same speaker observes `accent` on odd events and `intel` on even events, speaker correlation IS identified!
        d_same_spk_split_ev = (;
            speaker = d.speaker, clip = d.clip, listener = d.listener, words_total = d.words_total,
            accent = Union{Missing,Float64}[isodd(i) ? d.accent[i] : missing for i in eachindex(d.accent)],
            intel = Union{Missing,Int}[iseven(i) ? coalesce(d.intel[i], 5) : missing for i in eachindex(d.intel)],
        )
        d_disjoint_spk = (;
            speaker = d.speaker, clip = d.clip, listener = d.listener, words_total = d.words_total,
            accent = Union{Missing,Float64}[d.speaker[i] in ("S1", "S2", "S3") ? d.accent[i] : missing for i in eachindex(d.accent)],
            intel = Union{Missing,Int}[d.speaker[i] in ("S4", "S5", "S6") ? coalesce(d.intel[i], 5) : missing for i in eachindex(d.intel)],
        )
        out_disj = (
            accent = outcomes_3.accent,
            intel = outcomes_3.intel,
        )
        pop_disj = (
            person = (
                dimensions = (:d_acc, :d_int),
                sds = (d_acc = 0.8, d_int = 0.8),
                correlation = LKJ(2, 2.0),
                loadings = (accent = (1.0, 0.0), intel = (0.0, 1.0)),
            ),
            recording = 0.3, listener = 0.4,
        )
        @test validate_design(mfrm_spec(d_same_spk_split_ev; person = :speaker, facets = (recording = :clip, listener = :listener), outcomes = out_disj, population = pop_disj)).identified
        spec_disj = mfrm_spec(d_disjoint_spk; person = :speaker, facets = (recording = :clip, listener = :listener), outcomes = out_disj, population = pop_disj)
        @test !validate_design(spec_disj).identified
    end

    # 4. Short fitted workflow: paired PPC, Gauss-Hermite integration, sensitivity, and known vs. new owners (C6)
    @testset "Joint workflow, paired PPC, Gauss-Hermite profile LOO, and owner-aware prediction" begin
        spec_2d = mfrm_spec(d;
            person = :speaker,
            facets = (recording = :clip, listener = :listener),
            performance = :clip,
            outcomes = outcomes_3,
            population = (
                person = (
                    dimensions = (:pron, :intel_dim),
                    sds = (pron = LogNormal(log(0.7), 0.35), intel_dim = LogNormal(log(0.7), 0.35)),
                    correlation = LKJ(2, 2.0),
                    loadings = (accent = (1.0, 0.0), comp = (1.0, 0.0), intel = (0.0, 1.0)),
                ),
                recording = LogNormal(log(0.35), 0.35),
                listener = LogNormal(log(0.4), 0.35),
            ),
            decompose = (rate = (between = :mean_rate, within = :rate_change),),
            predictors = (response = (mean_rate = Normal(0.0, 0.8), rate_change = Normal(0.0, 0.8)),),
        )
        spec_1d = mfrm_spec(d;
            person = :speaker,
            facets = (recording = :clip, listener = :listener),
            performance = :clip,
            outcomes = outcomes_3,
            population = (
                person = LogNormal(log(0.7), 0.35),
                recording = LogNormal(log(0.35), 0.35),
                listener = LogNormal(log(0.4), 0.35),
            ),
            decompose = (rate = (between = :mean_rate, within = :rate_change),),
            predictors = (response = (mean_rate = Normal(0.0, 0.8), rate_change = Normal(0.0, 0.8)),),
        )

        # Prior predictive check includes paired_cells
        pp_chk = prior_predictive_check(spec_2d; ndraws = 12, seed = 11)
        @test !isempty(pp_chk.cells) && !isempty(pp_chk.paired_cells)

        f2 = fit(spec_2d; chains = 2, warmup = 35, ndraws = 30, seed = 201)
        f1 = fit(spec_1d; chains = 2, warmup = 35, ndraws = 30, seed = 202)

        # Posterior summary, fit_report (with missing values in input table!), and contrast
        frep = fit_report(f2; parameters = ["residual_sd[person,pron]", "correlation[person,pron,intel_dim]"], include_draws = true)
        @test length(frep.summary.rows) == 2
        con = contrast(f2; left = "person[\"S1\",pron]", right = "person[\"S2\",pron]")
        @test con.unit === :latent_owner_dimension_unit

        # Joint paired posterior predictive check
        ppc = predictive_check(f2; ndraws = 16, seed = 33)
        @test Set(r.metric for r in ppc.paired_cells) == Set((:pearson_r, :spearman_rho, :centered_covariance))
        @test all(r -> r.observed !== nothing, ppc.paired_cells)

        # Event-wise and Held-performance Gauss-Hermite PSIS-LOO + loo_refit_plan
        ce2 = criteria(f2; unit = :event)
        ce1 = criteria(f1; unit = :event)
        cmp_ev = compare_models("2D speaker" => ce2, "1D speaker" => ce1; criterion = :psis_loo, independent_model_rng = true)
        @test cmp_ev.difference ≈ ce2.elpd - ce1.elpd atol = 1e-10

        pll_perf = pointwise_loglikelihood(f2; unit = :performance, integrate = :recording)
        @test pll_perf.quadrature_passed
        @test pll_perf.quadrature_error <= pll_perf.quadrature_tolerance

        cp2 = criteria(f2; unit = :performance, integrate = :recording)
        cp1 = criteria(f1; unit = :performance, integrate = :recording)
        cmp_pf = compare_models("2D speaker" => cp2, "1D speaker" => cp1; criterion = :psis_loo, independent_model_rng = true)
        @test cmp_pf.difference ≈ cp2.elpd - cp1.elpd atol = 1e-10

        plan = loo_refit_plan(f2, "S1_C1"; unit = :performance, integrate = :recording)
        @test validate_design(plan.target).identified
        f_refit = fit(plan.target; chains = 2, warmup = 25, ndraws = 25, seed = 299)
        cp2_ref = criteria(f2; unit = :performance, integrate = :recording, refits = ["S1_C1" => f_refit], independent_refit_rng = true)
        @test first(cp2_ref.rows).method === :direct_refit

        # Scientific prior sensitivity
        lp_fac = logprior(f2; components = :factors)
        @test any(x -> x.id == "correlation[person]", lp_fac.factors)
        psens = prior_sensitivity(f2;
            powers = ["corr_tight" => (factors = ["correlation[person]"], alpha = 1.2)],
            estimands = [
                "rho_spk" => "correlation[person,pron,intel_dim]",
                "acc_r1" => (row = 1, outcome = :accent, metric = :expected_score),
                "comp_r1_c5" => (row = 1, outcome = :comp, category = 5),
            ],
        )
        @test length(psens.cases) == 1 && length(first(psens.cases).rows) == 3

        # C6: Known-owner vs. New-owner prediction contracts
        pred_known = predict(f2; rows = [1, 2, 3])
        @test pred_known.mode === :known_owners

        # Unseen speaker or recording under mode=:known_owners MUST throw ArgumentError (refusing zero substitution!)
        new_data = (;
            speaker = ["S_NEW_1", "S_NEW_1"],
            clip = ["CLIP_NEW_1", "CLIP_NEW_2"],
            listener = ["L1", "L2"],
            rate = [3.1, 3.5],
            words_total = [12, 12],
        )
        @test_throws ArgumentError predict(f2; data = new_data, mode = :known_owners)
        # New speaker without declaring recording in new_owners MUST throw hierarchy error
        @test_throws ArgumentError predict(f2; data = new_data, mode = :new_owners, new_owners = (:person,), seed = 501)
        # Stored training ID supplied inside new_owners MUST throw
        bad_new = merge(new_data, (; speaker = ["S1", "S1"]))
        @test_throws ArgumentError predict(f2; data = bad_new, mode = :new_owners, new_owners = (:person, :recording), seed = 501)

        pred_new_spk = predict(f2; data = new_data, mode = :new_owners, new_owners = (:person, :recording), seed = 501, include_predictive = true)
        @test pred_new_spk.mode === :new_owners
        @test hasproperty(pred_new_spk, :predictive_cells) && length(pred_new_spk.predictive_cells) == 6

        # Known speaker, new recording (`new_owners = (:recording,)`)
        new_rec_data = (;
            speaker = ["S1", "S1"],
            clip = ["S1_NEW_CLIP", "S1_NEW_CLIP"],
            listener = ["L1", "L2"],
            rate = [3.2, 3.2],
            words_total = [10, 10],
        )
        obs_ix = findall(!ismissing, d.intel)
        d_cnt = (; speaker = d.speaker[obs_ix], clip = d.clip[obs_ix], listener = d.listener[obs_ix],
                   intel = Int[d.intel[i] for i in obs_ix], words_total = d.words_total[obs_ix])
        f1_nodecomp = fit(mfrm_spec(d_cnt;
            person = :speaker, facets = (recording = :clip, listener = :listener), performance = :clip,
            outcomes = (intel = (family = :binomial, score = :intel, trials = :words_total, intercept = Normal(1.8, 0.5)),),
            population = (person = 1.6, recording = 0.8, listener = 0.2),
        ); chains = 2, warmup = 25, ndraws = 30, seed = 601)
        pred_new_rec = predict(f1_nodecomp; data = new_rec_data, mode = :new_owners, new_owners = (:recording,), seed = 602)
        @test pred_new_rec.mode === :new_owners

        # Verify Jensen shift on nonlinear logistic link: with positive intercept (~1.8) and large population SD (person=1.6, recording=0.8),
        # E[sigmoid(eta + b_new)] < sigmoid(eta + 0) strictly!
        zero_plugin_means = [mean(1.0 ./ (1.0 .+ exp.(-(only(A.coordinates(getdesign(f1_nodecomp), q).coefficients) - A.coordinates(getdesign(f1_nodecomp), q).owners[:listener].projected[1, 1])))) for q in eachrow(f1_nodecomp.record.run.draws)]
        naive_zero_mean = mean(zero_plugin_means)
        new_spk_binom = predict(f1_nodecomp;
            data = (; speaker = ["S_FRESH"], clip = ["C_FRESH"], listener = ["L1"], words_total = [10]),
            mode = :new_owners, new_owners = (:person, :recording), seed = 777)
        integrated_mean = only(r.mean for r in new_spk_binom.cells if r.metric === :expected_proportion)
        @test abs(integrated_mean - naive_zero_mean) > 0.015

        # Scalar CountTarget mode=:new_owners also works and refuses unknown IDs under mode=:known_owners
        f_scalar_cnt = fit(mfrm_spec(d_cnt;
            person = :speaker, score = :intel, facets = (recording = :clip, listener = :listener), performance = :clip,
            observation = (family = :binomial, trials = :words_total),
            population = (person = 0.8, recording = 0.4, listener = 0.3),
            intercept = Normal(0.5, 1.0),
        ); chains = 2, warmup = 20, ndraws = 25, seed = 801)
        @test_throws ArgumentError predict(f_scalar_cnt; data = (; speaker = ["S_UNSEEN"], clip = ["C_UNSEEN"], listener = ["L1"], words_total = [10]))
        p_scalar_new = predict(f_scalar_cnt;
            data = (; speaker = ["S_UNSEEN"], clip = ["C_UNSEEN"], listener = ["L1"], words_total = [10]),
            mode = :new_owners, new_owners = (:person, :recording), seed = 802)
        @test p_scalar_new.mode === :new_owners

        # Persistence round-trip
        mktempdir() do tmp
            fit_p = joinpath(tmp, "mixed_fit.jls")
            save_fit(fit_p, f2)
            f2_re = load_fit(fit_p)
            @test qualify(f2_re).qualified == qualify(f2).qualified

            ppc_p = joinpath(tmp, "mixed_ppc.json")
            ppc_rec = save_report(ppc_p, ppc; return_receipt = true)
            ppc_re = load_report(ppc_p; expected_sha256 = ppc_rec.sha256)
            @test length(ppc_re.paired_cells) == length(ppc.paired_cells)

            pred_p = joinpath(tmp, "mixed_new_pred.json")
            pred_rec = save_report(pred_p, pred_new_spk; return_receipt = true)
            pred_re = load_report(pred_p; expected_sha256 = pred_rec.sha256)
            @test Symbol(pred_re.mode) === :new_owners

            cmp_p = joinpath(tmp, "mixed_cmp.json")
            cmp_rec = save_report(cmp_p, cmp_pf; return_receipt = true)
            cmp_re = load_report(cmp_p; expected_sha256 = cmp_rec.sha256)
            @test cmp_re.difference ≈ cmp_pf.difference atol = 1e-12
        end
    end
end
