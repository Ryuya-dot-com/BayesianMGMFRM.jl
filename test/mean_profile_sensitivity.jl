module MeanProfileSensitivityTests
using Test, BayesianMGMFRM, Statistics, Serialization
const B = BayesianMGMFRM
const E = B.Experimental
include("common_prediction_fixtures.jl")

# Fixed-value records for contract/arithmetic tests, never posterior samples.
function profile_fit(; K=4, location=0., shape=.1, item_sd=.6, step_sd=.5,
        person_sd=.7, rater_sd=.4, loading_sd=.3, consistency_sd=.2,
        shift=0., ndraws=20, policy=:fixed_one, profiled=true, renamed=false)
    old = F.synthetic_record(F.target(; K); ndraws)
    spec = mfrm_spec(old.spec.data; family=:mgmfrm, dimensions=1,
        thresholds=:partial_credit, q_matrix=trues(4, 1),
        dimension_labels=[renamed ? "Other" : "Ability"])
    model = E.slope_restriction(spec; item_slopes=policy, rater_consistency=:fixed_one)
    base = E.NormalizedMGMFRMPrior(; prior_model=:exchangeable,
        person_sd, rater_sd, item_sd, step_sd,
        log_discrimination_sd=loading_sd, log_consistency_sd=consistency_sd)
    prior = profiled ? E.MeanProfilePrior(model, base;
        item_means=Dict(i => location*i for i in 1:4),
        step_means=Dict(i => shape*i.*((1:K-1).-K/2) for i in 1:4),
        category_levels=0:K-1, units=:raw) : base
    old.run.draws[:, 1] .+= shift
    target = B._normalized_mgmfrm_target(model, prior)
    return normalized_fixture(old; target)
end

@testset "Explicit profile scope preserves arithmetic, roster and provenance" begin
    a = profile_fit()
    b = profile_fit(location=.2, shape=.3, item_sd=.8, step_sd=.9, shift=.4, ndraws=30)
    estimands = ["Performance difference" => ("person[1]", "person[2]"),
        "Judge difference" => ("rater[3]", "rater[1]")]
    args = (; planned_prior_ids=["Reference", "Alternative", "Failed", "Missing"],
        estimands, dataset_id="fixed-value-test-only",
        observation_ids=["row-$i" for i in 1:a.record.spec.data.n],
        failures=["Failed" => "Artificial failure for denominator checking"])
    result = B.prior_sensitivity(["Reference"=>a, "Alternative"=>b];
        args..., vary=:mean_profile, interval=.95)
    @test result.scope === :normalized_d1_fixed_mean_profile
    @test getproperty.(result.ledger, :status) == [:warning, :warning, :failed, :missing]
    @test length(result.changes) == 2
    for (entry, fit) in zip(result.ledger[1:2], (a, b))
        e = entry.evaluation
        raw = fit.record.run.draws
        expected = [raw[:, 1]-raw[:, 2], -2raw[:, 4]-raw[:, 5]]
        @test e.prior == fit.record.prior
        @test e.target_identity == fit.record.target_identity
        @test e.source_sample_hash == fit.record.content_hash
        @test e.chain_ids == fit.record.run.chain_ids
        @test e.iterations == fit.record.run.iterations
        @test e.sampling_warning
        for (row, values) in zip(e.rows, expected)
            @test row.values ≈ values atol=1e-13 rtol=1e-13
            @test row.mean ≈ mean(values)
            @test row.lower ≈ quantile(values, .025)
            @test row.upper ≈ quantile(values, .975)
        end
    end
    for (c, alt, ref) in zip(result.changes,
            result.ledger[2].evaluation.rows, result.ledger[1].evaluation.rows)
        @test c.mean_shift == alt.mean-ref.mean
        @test c.mean_shift_mcse_upper_bound == alt.mcse.mean_mcse+ref.mcse.mean_mcse
        @test !c.paired_draws && c.cross_fit_covariance === :unknown
    end
    missing = B.prior_sensitivity(["Alternative"=>b]; args..., vary=:mean_profile)
    @test !missing.baseline_available && isempty(missing.changes)
    @test missing.ledger[1].status === :missing
    @test result.scientific_acceptance === :not_established && result.new_fits == 0
    plot = B.prior_sensitivity_plot_data(result; points=128)
    @test length(plot.panels) == 2
    @test all(p -> p.density_coordinate === :identity, plot.panels)
    @test all(p -> getproperty.(p.curves, :marker) ==
        [:density, :density, :unavailable, :unavailable], plot.panels)
    mktempdir() do dir
        path = joinpath(dir, "profiles.jls")
        B.save_prior_sensitivity(path, result)
        @test isequal(B.load_prior_sensitivity(path), result)
        @test_throws ArgumentError B.save_prior_sensitivity(path, result)
        bad = deepcopy(result)
        bad.ledger[1].evaluation.prior.mean_profile.step_means[1][1] += .1
        @test_throws ArgumentError B.save_prior_sensitivity(joinpath(dir, "bad.jls"), bad)
    end
    # Default remains the former narrow scope, even for profile fits.
    @test_throws ArgumentError B.prior_sensitivity(["Reference"=>a, "Alternative"=>b]; args...)
    @test_throws ArgumentError B.prior_sensitivity(["Reference"=>a]; args..., vary=:anything)
    for alternative in (profile_fit(person_sd=.8), profile_fit(rater_sd=.5),
            profile_fit(loading_sd=.8), profile_fit(consistency_sd=.8),
            profile_fit(renamed=true), profile_fit(K=3),
            profile_fit(profiled=false), profile_fit(profiled=false, policy=:estimated_positive))
        @test_throws ArgumentError B.prior_sensitivity(
            ["Reference"=>a, "Alternative"=>alternative]; args..., vary=:mean_profile)
    end
    # Same declared high-category model; this is a fixed fixture, not convergence evidence.
    high = profile_fit(K=25)
    other = profile_fit(K=25, shape=.2, step_sd=.8)
    high_result = B.prior_sensitivity(["Reference"=>high, "Alternative"=>other];
        args..., vary=:mean_profile)
    @test high_result.ledger[1].evaluation.prior.mean_profile.category_levels == collect(0:24)
    @test length(high_result.changes) == 2
    @test_throws ArgumentError B.prior_sensitivity(["Reference"=>a, "Alternative"=>high];
        args..., vary=:mean_profile)
    global artificial_result = result
end
end
