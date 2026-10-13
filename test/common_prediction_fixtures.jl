include("fixtures/reporting_fit.jl")
include("fixtures/prediction_fixed_fits.jl")
include("mgmfrm_correlated_2d_fixtures.jl")
const F=MGMFRMCorrelated2DFixtures

function normalized_fixture(record; model=:exchangeable, target=nothing)
    scales = record.prior.scales
    t = target === nothing ? B._MGMFRMNormalizedPriorLogDensity(record.spec; prior_model=model, scales,
        source_rater=model === :source ? last(record.spec.data.rater_levels) : nothing) : target
    old = record.run
    initial = initial_params(t)
    draws = old.draws[:, 1:length(initial)]
    logdensities = [B.LogDensityProblems.logdensity(t, row) for row in eachrow(draws)]
    stats = NamedTuple[merge(s, (; log_density=lp),
        old.backend === :cmdstan ? (; stan_lp=lp) : (;)) for (s, lp) in zip(old.sampler_stats, logdensities)]
    run = merge(old, (; draws, nparams=length(initial), initial,
        initial_logdensity=B.LogDensityProblems.logdensity(t, initial), logdensities,
        sampler_stats=stats, sampler_rows=B._generalized_candidate_sampler_rows(logdensities,
            old.iterations, old.chain_acceptance, stats, old.controls, old.backend)))
    r = (; schema="bayesianmgmfrm.normalized_fixed_q_samples.v2", spec=deepcopy(t.base.design.spec),
        prior=B._mgmfrm_normalized_prior_record(t), target_identity=B._mgmfrm_normalized_prior_identity(t), run)
    r = merge(r, (; content_hash=B._mgmfrm_normalized_sample_hash(r)))
    return B.Experimental.NormalizedMGMFRMFit(r; expected_identity=r.target_identity)
end
