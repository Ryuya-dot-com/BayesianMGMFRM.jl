using BayesianMGMFRM, Random

all(==("--figures"), ARGS) ||
    error("Usage: julia --project=. examples/normalized_mgmfrm.jl [--figures]")
"--figures" in ARGS && (@eval using CairoMakie)
E = BayesianMGMFRM.Experimental
cells = [(p, i, r) for p in 1:3 for i in 1:4 for r in 1:3]
data = FacetData((; person=first.(cells), item=getindex.(cells,2), rater=last.(cells),
    score=[mod(p+i+r,4) for (p,i,r) in cells]);
    person=:person, item=:item, rater=:rater, score=:score, category_levels=0:3)
spec = mfrm_spec(data; family=:mgmfrm, dimensions=2,
    q_matrix=Bool[1 0; 1 0; 0 1; 0 1], dimension_labels=["reasoning", "communication"])
# Illustrative scales, not a scientifically selected prior.
prior = E.NormalizedMGMFRMPrior(; prior_model=:exchangeable,
    person_sd=.8, rater_sd=.6, item_sd=.9,
    log_discrimination_sd=.3, log_consistency_sd=.4, step_sd=.7)
check = E.prior_predictive_check(spec; prior, ndraws=100, rng=MersenneTwister(24))
display(first(predictive_check_summary(check)))
println("Short workflow demonstration: 10 warmup + 12 retained draws per chain; insufficient for inference.")
result = E.fit(spec; prior, sampling_coordinates=:orthogonal_person_mean_item_offset,
    chains=2, warmup=10, ndraws=12, max_depth=3, seed=24, record_warmup=true)
status = diagnostics(result; view=:public)
println("Whole-fit MCMC status: ", status.summary.flag)
display(sampler_diagnostics(result; phase=:warmup))
display(first(BayesianMGMFRM.direct_posterior_summary(result)))
display(first(posterior_mcse(result)))
directory = mktempdir(mkpath("results/normalized_mgmfrm"); cleanup=false)
path = joinpath(directory,"fit.jls")
save_fit_cache(path,result)
restored = load_fit_cache(path)
@assert isequal(fit_metadata(restored),fit_metadata(result))
@assert isequal(posterior_summary(restored),posterior_summary(result))
@assert isequal(diagnostics(restored),diagnostics(result))
@assert isequal(posterior_mcse(restored),posterior_mcse(result))
figures = "--figures" in ARGS ? (;
    posterior=(;block=:person,dimension="reasoning"),
    diagnostics=(;block=:item_dimension_discrimination,dimension="reasoning")) : nothing
report_path = joinpath(directory,"report")
save_fit_report_bundle(report_path,restored; figures, require_complete=true,
    include_prior_predictive=true, prior_predictive_ndraws=100, seed=24)
reopened = load_fit_report_bundle(report_path; require_complete=true)
@assert reopened["diagnostics"]["summary"]["passed"] == status.summary.passed
println("Saved and verified: ", relpath(directory))
println("Report completeness does not remove MCMC warnings. Figures and summaries depend on the specified prior.")
