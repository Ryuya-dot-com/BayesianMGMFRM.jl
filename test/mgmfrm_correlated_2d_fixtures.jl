module MGMFRMCorrelated2DFixtures
using BayesianMGMFRM
const B = BayesianMGMFRM

function target(; K=4, raters=3, eta=2)
    cells=[(p,i,r) for p in 1:3 for i in 1:4 for r in 1:raters]
    data=FacetData((;person=first.(cells),item=getindex.(cells,2),rater=last.(cells),
        score=[mod(p+i+r,K) for (p,i,r) in cells]);
        person=:person,item=:item,rater=:rater,score=:score,category_levels=0:(K-1))
    spec=mfrm_spec(data;family=:mgmfrm,dimensions=2,
        q_matrix=Bool[1 0;0 1;1 0;0 1],dimension_labels=["First","Second"])
    return B._mgmfrm_free_latent_correlation_2d_logdensity(spec;lkj_eta=eta,
        prior=B._SourceFixturePrior(;person_sd=0.7,rater_sd=0.4,item_sd=0.6,
            log_discrimination_sd=0.3,log_consistency_sd=0.2,step_sd=0.5))
end

rehash(r)=merge(r,(;content_hash=B._mgmfrm_normalized_sample_hash(r)))
restore(r)=B._restore_mgmfrm_correlated_2d_samples(r;expected_identity=r.target_identity)

function synthetic_record(t;backend=:advancedhmc,chains=2,ndraws=20,z=x->1.1sin(x))
    initial=initial_params(t); n=chains*ndraws
    draws=[0.2sin(d+p) for d in 1:n,p in eachindex(initial)]
    draws[:,end].=z.(1:n)
    logdensities=[B.LogDensityProblems.logdensity(t,x) for x in eachrow(draws)]
    chain_ids=repeat(1:chains;inner=ndraws);iterations=repeat(1:ndraws;outer=chains)
    controls=(;ndraws,chains,warmup=0,step_size=0.1,target_accept=0.8,
        max_depth=2,max_energy_error=1000.0,init_jitter=0.0,metric=:diagonal)
    controls=merge(controls,backend===:advancedhmc ? (;ad_backend=:ForwardDiff,gradient_backend=:ad) :
        (;ad_backend=:stan_reverse_mode,gradient_backend=:stan_autodiff,execution=:cmdstan_cli,thinning=1))
    stats=NamedTuple[B._advancedhmc_stat_row((;log_density=logdensities[d],step_size=0.1,
        acceptance_rate=0.75,hamiltonian_energy=Float64(d)),chain_ids[d],iterations[d]) for d in 1:n]
    backend===:cmdstan && (stats=NamedTuple[merge(s,(;stan_lp=s.log_density)) for s in stats])
    acceptance=fill(0.75,chains)
    run=(;checked=B._check_diagnostic_thresholds(1.01,400),nparams=length(initial),initial,
        initial_logdensity=B.LogDensityProblems.logdensity(t,initial),total_draws=n,
        draws,logdensities,chain_ids,iterations,chain_acceptance=acceptance,sampler_stats=stats,controls,
        sampler_rows=B._generalized_candidate_sampler_rows(logdensities,iterations,acceptance,stats,controls,backend),
        backend,sampler=:nuts,split_chains_requested=true,actual_split=chains>=2 && ndraws>=4,
        warmup_stats=NamedTuple[])
    return rehash((;schema="bayesianmgmfrm.correlated_mgmfrm_samples.v1",spec=deepcopy(t.base.design.spec),
        prior=(;scales=B._source_fixture_prior_values(t.prior.source_prior),lkj_eta=t.prior.lkj_eta),
        target_identity=B._mgmfrm_correlated_2d_identity(t),run))
end

const controls=(;ndraws=12,warmup=10,chains=2,seed=92141,step_size=0.03,max_depth=4,init_jitter=0.02)
end
