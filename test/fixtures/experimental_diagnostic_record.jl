# Deterministic coordinates and telemetry: not posterior draws or MCMC evidence.
function diagnostic_target(kind)
    B = BayesianMGMFRM
    mod = getproperty(B.Experimental, kind)
    rows = [(; person="p$p", item="i$i", rater="r$r", score=Base.mod(p+r+i,3),
        group=p<=2 ? "A" : "B") for p in 1:4 for i in 1:2 for r in 1:3]
    table = (; (k=>getproperty.(rows,k) for k in (:person,:item,:rater,:score))...)
    if kind === :RaterGroupEffects
        table = merge(table, (;group=getproperty.(rows,:group)))
        d = B.FacetData(table; person=:person,item=:item,rater=:rater,score=:score,
            group=:group,category_levels=0:2)
        prior = mod.Prior(person_sd=.9,group_mean_sd=1.4,item_sd=.7,rater_sd=.6,
            step_sd=.8,interaction_logmean=log(.5),interaction_logsd=.6)
    elseif kind === :RaterItemInteractions
        d = B.FacetData(table; person=:person,item=:item,rater=:rater,score=:score,category_levels=0:2)
        prior = mod.Prior(person_sd=.9,item_sd=.7,rater_sd=.6,step_sd=.8,
            interaction_logmean=log(.5),interaction_logsd=.6)
    else
        d = B.FacetData(table; person=:person,item=:item,rater=:rater,score=:score,category_levels=0:2)
        prior = mod.Prior(person_precision_shape=3.,person_precision_rate=2.,
            rater_precision_shape=3.,rater_precision_rate=.5,step_sd=1.5,class_alpha=1.,class_beta=1.)
    end
    return mod, mod.model(d;prior)
end

function diagnostic_record(kind; chains=4, ndraws=60)
    B = BayesianMGMFRM
    mod, t = diagnostic_target(kind)
    initial = mod.initial(t)
    n = chains * ndraws
    draws = [.12sin(.91s+.37j)+.08cos(1.37s+.61j) for s in 1:n,j in eachindex(initial)]
    ld = [B.LogDensityProblems.logdensity(t,q) for q in eachrow(draws)]
    chain_ids = repeat(1:chains;inner=ndraws)
    iterations = repeat(1:ndraws;outer=chains)
    controls = (;ndraws,chains,warmup=0,step_size=.1,target_accept=.8,max_depth=10,
        max_energy_error=1000.,init_jitter=0.,metric=:diagonal,
        ad_backend=:ForwardDiff,gradient_backend=:ad)
    stats = NamedTuple[B._advancedhmc_stat_row((;log_density=ld[s],step_size=.1,
        acceptance_rate=.75,hamiltonian_energy=Float64(isodd(s)),
        numerical_error=false,tree_depth=1),chain_ids[s],iterations[s]) for s in 1:n]
    acceptance = fill(.75,chains)
    run = (;checked=B._check_diagnostic_thresholds(1.5,1),nparams=length(initial),initial,
        initial_logdensity=B.LogDensityProblems.logdensity(t,initial),total_draws=n,
        draws,logdensities=ld,chain_ids,iterations,chain_acceptance=acceptance,sampler_stats=stats,controls,
        sampler_rows=B._generalized_candidate_sampler_rows(ld,iterations,acceptance,stats,controls,:advancedhmc),
        backend=:advancedhmc,sampler=:nuts,split_chains_requested=true,actual_split=chains>=2 && ndraws>=4,
        warmup_stats=NamedTuple[])
    target = mod._target_record(t)
    body = (;schema=mod.SCHEMA,target,target_identity=B._cache_hash(target),scope=mod.SCOPE,run)
    return merge(body,(;content_hash=B._cache_hash(body)))
end
