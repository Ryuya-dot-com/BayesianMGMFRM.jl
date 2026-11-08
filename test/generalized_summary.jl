module GeneralizedSummaryChecks
using Test, BayesianMGMFRM, Statistics
const B=BayesianMGMFRM
const E=B.Experimental
include("mgmfrm_correlated_2d_fixtures.jl")

function specification(family; K=4, dimensions=2)
    cells=[(p,i,r) for p in 1:3 for i in 1:4 for r in 1:2]
    data=FacetData((; person=first.(cells),item=getindex.(cells,2),rater=last.(cells),
        score=[mod(p+i+r,K) for (p,i,r) in cells]);
        person=:person,item=:item,rater=:rater,score=:score,category_levels=0:K-1)
    family===:gmfrm && return mfrm_spec(data;family,thresholds=:partial_credit,discrimination=:rater)
    q=dimensions==1 ? trues(4,1) : Bool[1 0;1 1;0 1;0 1]
    return mfrm_spec(data;family,thresholds=:partial_credit,dimensions,q_matrix=q)
end

# Fixed deterministic traces exercise algebra, ordering and IO, not MCMC calibration.
function run_record(t)
    initial=initial_params(t); nparams=length(initial); ndraws=20; chains=2; n=ndraws*chains
    draws=[.4sin(i*.81+j*.17)+.1cos(i*.33-j*.21) for i in 1:n,j in 1:nparams]
    logdensities=[B.LogDensityProblems.logdensity(t,x) for x in eachrow(draws)]
    controls=(;ndraws,chains,warmup=0,step_size=.1,target_accept=.8,max_depth=4,
        max_energy_error=1000.,init_jitter=0.,ad_backend=:ForwardDiff,
        gradient_backend=B._gradient_backend_kind(:ForwardDiff),metric=:diagonal)
    chain_ids=repeat(1:chains;inner=ndraws); iterations=repeat(1:ndraws,chains)
    stats=NamedTuple[B._advancedhmc_stat_row((;log_density=logdensities[i],step_size=.1,
        acceptance_rate=.75,hamiltonian_energy=Float64(i)),chain_ids[i],iterations[i]) for i in 1:n]
    chain_acceptance=fill(.75,chains)
    return (;checked=B._check_diagnostic_thresholds(1.01,400),nparams,initial,
        initial_logdensity=B.LogDensityProblems.logdensity(t,initial),total_draws=n,draws,
        logdensities,chain_ids,iterations,chain_acceptance,sampler_stats=stats,controls,
        sampler_rows=B._generalized_candidate_sampler_rows(logdensities,iterations,chain_acceptance,stats,controls,:advancedhmc),
        backend=:advancedhmc,sampler=:nuts,split_chains_requested=true,actual_split=true,warmup_stats=NamedTuple[])
end

function raw_fit(family; K=4)
    spec=specification(family;K)
    t=family===:gmfrm ? B._gmfrm_promotion_candidate_logdensity(spec) : B._mgmfrm_guarded_local_fit_logdensity(spec)
    run=run_record(t)
    surface=family===:gmfrm ? B._gmfrm_promotion_candidate_diagnostic_surface(t,run) :
        B._mgmfrm_guarded_local_fit_diagnostic_surface(t,run)
    constructor=family===:gmfrm ? B._gmfrm_fit_from_sampler_diagnostics : B._mgmfrm_fit_from_sampler_diagnostics
    return constructor(t.design,t.prior,surface)
end

function normalized_fit(; slopes=nothing, K=4, source=false)
    spec=specification(:mgmfrm;K,dimensions=slopes===nothing ? 2 : 1)
    p=E.NormalizedMGMFRMPrior(;prior_model=source ? :source : :exchangeable,
        source_rater=source ? first(spec.data.rater_levels) : nothing,
        person_sd=.7,rater_sd=.4,item_sd=.6,log_discrimination_sd=.3,log_consistency_sd=.35,step_sd=.5)
    model=slopes===nothing ? spec : E.slope_restriction(spec;item_slopes=slopes,rater_consistency=:fixed_one)
    t=B._normalized_mgmfrm_target(model,p)
    record=(;schema="bayesianmgmfrm.normalized_fixed_q_samples.v2",spec=deepcopy(t.base.design.spec),
        prior=B._mgmfrm_normalized_prior_record(t),target_identity=B._mgmfrm_normalized_prior_identity(t),run=run_record(t))
    record=merge(record,(;content_hash=B._mgmfrm_normalized_sample_hash(record)))
    return E.NormalizedMGMFRMFit(record;expected_identity=record.target_identity)
end

report_options(fit)=fit isa Union{B.GMFRMFit,B.MGMFRMFit} ?
    (;include_calibration=false,include_category_functioning=false,include_rater_homogeneity=false) : (;)

function check_fit(fit; directory=nothing)
    c=B._generalized_slope_context(fit); spec=c.design.spec
    raw=posterior_summary(fit); direct=B.direct_posterior_summary(fit)
    before=deepcopy(c.direct)
    @test isequal(posterior_summary(fit;scale=:raw),raw)
    @test isequal(posterior_summary(fit;scale=:model),direct)
    @test isequal(posterior_summary(fit;scale=:model,lower=.1,upper=.9),B.direct_posterior_summary(fit;lower=.1,upper=.9))
    summary=posterior_summary(fit;estimand=:adjacent_logit_slope,lower=.1,upper=.9)
    precision=posterior_mcse(fit;estimand=:adjacent_logit_slope,probabilities=(.1,.5,.9))
    @test length(summary)==length(spec.data.item_levels)*length(spec.data.rater_levels)*spec.dimensions
    @test all(r->r.likelihood_scale==(spec.family===:gmfrm ? 1.0 : 1.7),summary)
    for (row,mcse) in zip(summary,precision)
        i=findfirst(==(row.item),spec.data.item_levels);r=findfirst(==(row.rater),spec.data.rater_levels)
        d=findfirst(==(row.dimension),spec.dimension_labels)
        observation=findfirst(n->spec.data.item[n]==i && spec.data.rater[n]==r,1:spec.data.n)
        vals=Float64[]
        for draw in eachrow(c.direct)
            a=copy(draw); b=copy(draw)
            person=spec.data.person[observation]
            b[c.design.blocks[:person][(person-1)*spec.dimensions+d]]+=.25
            logits(x)=spec.family===:gmfrm ? B._gmfrm_source_linear_predictors!(zeros(length(spec.data.category_levels)),c.design,x,observation) :
                B._mgmfrm_source_linear_predictors!(zeros(length(spec.data.category_levels)),c.design,nothing,x,observation)
            push!(vals,(diff(logits(b))[1]-diff(logits(a))[1])/.25)
        end
        @test row.mean≈mean(vals) atol=2e-14
        @test row.lower≈quantile(vals,.1) atol=2e-14
        @test row.upper≈quantile(vals,.9) atol=2e-14
        @test row.parameter==mcse.parameter && row.fixed==mcse.fixed
        @test row.joint_draws_used && row.unit===:log_odds_per_ability_unit
        if row.fixed
            @test mcse.mcse_status===:structurally_fixed
            @test mcse.mean_mcse==0 && !mcse.convergence_review_required
        else
            @test mcse.convergence_review_required && !mcse.precision_threshold_applied
        end
    end
    @test isequal(c.direct,before)
    @test_throws ArgumentError posterior_summary(fit;scale=:logit)
    @test_throws ArgumentError posterior_summary(fit;estimand=:wrong)
    @test_throws ArgumentError posterior_summary(fit;scale=:raw,estimand=:adjacent_logit_slope)
    @test_throws ArgumentError posterior_mcse(fit;estimand=:adjacent_logit_slope,parameter_space=:raw_unconstrained)
    @test_throws ArgumentError posterior_summary(fit;estimand=:adjacent_logit_slope,lower=.8,upper=.2)
    if directory!==nothing
        report=fit_report(fit;view=:public,include_posterior_predictive=false,include_artifact=false,
            include_waic=false,include_loo=false,include_effective_slopes=true,
            posterior_lower=.1,posterior_upper=.9,report_options(fit)...)
        @test report.effective_slopes.status===:computed
        @test length(report.effective_slopes.rows)==length(summary)
        @test any(r->r.section===:effective_slopes,fit_report_sections(report))
        @test occursin("adjacent",fit_report_markdown(report))
        path=joinpath(directory,"report.json")
        receipt=save_report(path,report;return_receipt=true)
        restored=load_report(path;expected_sha256=receipt.sha256)
        @test length(restored["effective_slopes"]["rows"])==length(summary)
        @test restored["effective_slopes"]["rows"][1]["mean"]≈first(summary).mean
        cache=joinpath(directory,"fit.jls")
        save_fit_cache(cache,fit)
        restored_fit=load_fit_cache(cache)
        @test isequal(posterior_summary(restored_fit;estimand=:adjacent_logit_slope),posterior_summary(fit;estimand=:adjacent_logit_slope))
    end
    return summary
end

@testset "Generalized scale and joint adjacent-logit slopes (no fitting)" begin
    fits=[raw_fit(:gmfrm;K=2),raw_fit(:gmfrm),raw_fit(:mgmfrm),normalized_fit(),
        normalized_fit(source=true),normalized_fit(slopes=:fixed_one;K=2),normalized_fit(slopes=:estimated_positive)]
    t=MGMFRMCorrelated2DFixtures.target()
    record=MGMFRMCorrelated2DFixtures.synthetic_record(t)
    push!(fits,E.CorrelatedMGMFRMFit(record;expected_identity=record.target_identity))
    for fit in fits
        mktempdir() do dir
            check_fit(fit;directory=dir)
        end
    end
    # Positive dependence demonstrates why a product of means is a different estimand.
    fit=raw_fit(:mgmfrm);c=B._generalized_slope_context(fit)
    row=first(posterior_summary(fit;estimand=:adjacent_logit_slope))
    ai=first(c.design.blocks[:item_dimension_discrimination]);ci=first(c.design.blocks[:rater_consistency])
    @test !isapprox(row.mean,1.7mean(c.direct[:,ai])*mean(c.direct[:,ci]);atol=1e-5)
    fit.chain_ids[1]=2
    @test_throws ArgumentError posterior_summary(fit;estimand=:adjacent_logit_slope)
end
end
