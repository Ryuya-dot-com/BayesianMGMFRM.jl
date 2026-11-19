# Common known-owner posterior prediction; no draw-by-observation cube is stored.
const PPC_SCHEMA="bayesianmgmfrm.additive_facet_posterior_predictive.v1"
function posterior_check(f::Fit;ndraws=500,seed,groupby=nothing,interval=.95)
    t=checked(f)
    t isa MixedOutcomeTarget && return mixed_check(t;fit=f,ndraws,seed,groupby,interval)
    t isa BoundedTarget && return bounded_check(t;fit=f,ndraws,seed,groupby,interval)
    t isa CountTarget && return count_check(t;fit=f,ndraws,seed,groupby,interval)
    lo,hi=interval_bounds(interval)
    ndraws isa Integer && !(ndraws isa Bool) && 1<=ndraws<=typemax(Int) ||
        throw(ArgumentError("ndraws must be a positive integer"))
    seed isa Integer && !(seed isa Bool) && 0<=seed<=typemax(Int) ||
        throw(ArgumentError("seed must be a nonnegative integer representable as Int"))
    groupby===nothing || groupby===:person || groupby in [b.name for b in t.facets] ||
        throw(ArgumentError("groupby must be :person or a declared facet name"))
    ids=groupby===nothing ? ones(Int,length(t.person)) : _owner_index(t,groupby)
    labels=groupby===nothing ? ["all"] : _owner_levels(t,groupby)
    # Raw-score means must never pool different category supports.
    mixed=_owned_support(t)
    if mixed
        if groupby===nothing || groupby===t.owner
            ids=t.group;labels=t.group_levels
        else
            pairs=unique(collect(zip(ids,t.group)));index=Dict(x=>j for (j,x) in enumerate(pairs))
            labels=["$(repr(labels[i])) / $(t.owner)=$(repr(t.group_levels[g]))" for (i,g) in pairs]
            ids=[index[x] for x in zip(ids,t.group)]
        end
    end
    n=length(t.person);K=length(t.categories);den=[count(==(j),ids) for j in eachindex(labels)]
    all(>(0),den) || throw(ArgumentError("posterior predictive groups must have observations"))
    rng=MersenneTwister(Int(seed));indices=rand(rng,axes(f.record.run.draws,1),Int(ndraws))
    cells=mixed ? [(g,k) for g in eachindex(t.supports) for k in t.supports[g]] : [(0,k) for k in 1:K]
    cell_index=Dict(x=>j for (j,x) in enumerate(cells))
    counts=zeros(Int,Int(ndraws),length(cells));means=zeros(Int(ndraws),length(labels))
    for (s,i) in enumerate(indices)
        probs=exp.(logprobs(t,view(f.record.run.draws,i,:)))
        for j in 1:n
            k=_sample_category(t,j,view(probs,j,:),rand(rng))
            counts[s,cell_index[(mixed ? t.group[j] : 0,k)]]+=1;means[s,ids[j]]+=t.categories[k]
        end
        means[s,:]./=den
    end
    stats(x)=(;mean=mean(x),median=median(x),lower=quantile(x,lo),upper=quantile(x,hi))
    rows=[merge((;category=t.categories[k],observed=count(n->t.category[n]==k && (g==0 || t.group[n]==g),eachindex(t.person)),stats(view(counts,:,j))...),
        mixed ? (;owner=t.owner,level=deepcopy(t.group_levels[g])) : (;)) for (j,(g,k)) in enumerate(cells)]
    groups=[(;label=repr(labels[j]),n=den[j],observed=mean(t.categories[t.category[ids.==j]]),
        stats(view(means,:,j))...) for j in eachindex(labels)]
    d=design(t)
    (;schema=PPC_SCHEMA,kind=:posterior_predictive,rows,groups,groupby,interval,
      n_observations=n,ndraws=Int(ndraws),seed=Int(seed),draw_indices=indices,
      n_unique_draws=length(unique(indices)),selection=:uniform_with_replacement,
      category_support=d.category_support,response_patterns=d.response_patterns,grouping_by_support=mixed,
      conditioning=prediction_conditioning(t),source_sample_content_hash=f.record.content_hash,
      target_identity=f.record.target_identity,qualification=qualify(f),
      warnings=[d.warnings;"Pointwise replicated-data intervals are not parameter intervals or proof of adequate fit. Predictive endpoint MCSE is not assessed; small replicate counts are exploratory."],
      scientific_acceptance=false)
end
