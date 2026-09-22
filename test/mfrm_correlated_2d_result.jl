module MFRMCorrelated2DResultChecks
using Test, BayesianMGMFRM, Random, Statistics
const B = BayesianMGMFRM
include("fixtures/correlated_fixed_q_result.jl")
include("fixtures/fixed_q_cache.jl")
include("fixtures/fixed_q_prior_report.jl")
include("../scripts/public_language_gate.jl")

@testset "correlated fixed-Q results (synthetic, no sampling)" begin
    for categories in (2, 4), backend in (:advancedhmc, :cmdstan)
        cells = [(p, i, r) for p in 1:2 for i in 1:4 for r in 1:2]
        data = FacetData((; person = first.(cells), item = getindex.(cells, 2),
            rater = last.(cells), score = [mod(sum(cell), categories) for cell in cells]);
            person = :person, item = :item, rater = :rater, score = :score,
            category_levels = 0:(categories - 1))
        spec = mfrm_spec(data; family = :mfrm, dimensions = 2, thresholds = :partial_credit,
            q_matrix = Bool[1 0; 1 0; 0 1; 0 1], dimension_labels = ["First", "Second"])
        correlated = B.Experimental.correlated(spec; lkj_eta = 3)
        @test correlated isa B.Experimental.CorrelatedMFRMSpec
        @test correlated.base_spec !== spec
        @test correlated.base_spec.q_matrix !== spec.q_matrix
        @test B.Experimental.surface_contract(correlated).latent_correlation === :free_2d
        @test B.Experimental.surface_contract(:mfrm).latent_correlation === :identity_fixed
        @test occursin("LKJ eta = 3", sprint(show, correlated))
        @test_throws ArgumentError B.Experimental.correlated(spec; lkj_eta = 1.5)
        @test_throws ArgumentError B.Experimental.fit(correlated; init = [NaN])
        @test_throws ArgumentError B.Experimental.fit(correlated; backend = :turing)
        @test_throws ArgumentError B.Experimental.fit(correlated; experimental = true)
        bad = deepcopy(spec); bad.q_matrix[1,2] = true
        @test_throws ArgumentError B.Experimental.correlated(bad)
        # The copied design is also revalidated at fit time, before any sampler runs.
        changed = deepcopy(correlated); changed.base_spec.q_matrix[1,2] = true
        @test_throws ArgumentError B.Experimental.fit(changed)
        @test spec.q_matrix == Bool[1 0; 1 0; 0 1; 0 1]
        target = B._MFRMFixedQCorrelated2DLogDensity(spec; prior = MFRMPrior(), lkj_eta = 3)
        initial = initial_params(target)
        draws = [initial[p] + 0.35 * sin(d + p) + 0.2 for d in 1:8, p in eachindex(initial)]
        logdensities = [B.LogDensityProblems.logdensity(target, row) for row in eachrow(draws)]
        chain_ids, iterations = repeat(1:2; inner = 4), repeat(1:4; outer = 2)
        controls = (; ndraws = 4, chains = 2, warmup = 0, step_size = 0.1,
            target_accept = 0.8, max_depth = 2, max_energy_error = 1000.0,
            init_jitter = 0.0, metric = :diagonal)
        controls = merge(controls, backend === :advancedhmc ?
            (; ad_backend = :ForwardDiff, gradient_backend = :ad) :
            (; ad_backend = :stan_reverse_mode, gradient_backend = :stan_autodiff,
                execution = :cmdstan_cli, thinning = 1))
        stats = NamedTuple[B._advancedhmc_stat_row((; log_density = logdensities[d],
            step_size = 0.1, acceptance_rate = 0.75, hamiltonian_energy = Float64(d)),
            chain_ids[d], iterations[d]) for d in 1:8]
        backend === :cmdstan && (stats = NamedTuple[merge(stat, (; stan_lp = stat.log_density)) for stat in stats])
        chain_acceptance = fill(0.75, 2)
        run = (; checked = B._check_diagnostic_thresholds(1.01, 400), nparams = length(initial), initial,
            initial_logdensity = B.LogDensityProblems.logdensity(target, initial), total_draws = 8,
            draws, logdensities, chain_ids, iterations, chain_acceptance, sampler_stats = stats, controls,
            sampler_rows = B._generalized_candidate_sampler_rows(logdensities, iterations,
                chain_acceptance, stats, controls, backend), backend, sampler = :nuts,
            split_chains_requested = true, actual_split = true)
        record = (; schema = "bayesianmgmfrm.correlated_fixed_q_mfrm_samples.v1", base_spec = spec,
            prior = B._mfrm_correlated_2d_prior_record(target),
            target_identity = B._mfrm_correlated_2d_identity(target), run)
        record = merge(record, (; content_hash = B._mgmfrm_normalized_sample_hash(record)))
        result = B._restore_mfrm_correlated_2d_samples(record; expected_identity = record.target_identity)
        mktempdir(directory -> check_correlated_fixed_q_result(result, directory))
        fit = B._mfrm_correlated_2d_fit(result)
        check_fixed_q_cache(fit)
        check_fixed_q_prior_report(fit)
        public = fit_report(fit; require_complete = true)
        @test public.schema == "bayesianmgmfrm.fit_report_public.v1"
        @test public.metadata.correlation.latent_correlation === :free_2d
        @test !hasproperty(public.metadata.correlation, :fitting_available)
        @test public.metadata.fitting_available
        @test public.diagnostics.summary.flag == diagnostics(fit).summary.flag
        @test public.rating_design.status === :computed
        @test isempty(PublicLanguageGate.runtime_public_report_language_violations(["report" => public]))
        @test isempty(PublicLanguageGate.runtime_language_violations(["fit" => sprint(show, fit)]))
        @test isempty(PublicLanguageGate.runtime_language_violations(["spec" => sprint(show, correlated)]))
        for name in (:correlated, :CorrelatedMFRMSpec, :CorrelatedMFRMFit)
            help = sprint(show, MIME("text/plain"), Base.Docs.doc(getfield(B.Experimental, name)))
            @test isempty(PublicLanguageGate.runtime_language_violations(["help" => help]))
            binding_help = sprint(show, MIME("text/plain"), Base.Docs.doc(Base.Docs.Binding(B.Experimental, name)))
            @test isempty(PublicLanguageGate.runtime_language_violations(["help binding" => binding_help]))
        end
        mktempdir() do directory
            save_fit_report_bundle(directory, fit; require_complete = true)
            reopened = load_fit_report_bundle(directory; require_complete = true)
            @test reopened["schema"] == public.schema
            @test reopened["direct_posterior"]["correlation_rows"] == B._json_export_value(public.direct_posterior.correlation_rows)
            @test !occursin("private_reference", read(joinpath(directory, "fit_report.md"), String))
        end
    end
end
end
