# Computed reports share the public lifecycle; none of these adapters fits a model.
const PRIOR_SCHEMA="bayesianmgmfrm.additive_facet_prior_predictive.v1"
const PREDICTION_SCHEMA="bayesianmgmfrm.additive_facet_prediction.v1"
const REPORT_SCHEMAS=(REPORT_SCHEMA,PPC_SCHEMA,PRIOR_SCHEMA,PREDICTION_SCHEMA,BOUNDED_PPC_SCHEMA,BOUNDED_PREDICTION_SCHEMA,COUNT_PPC_SCHEMA,COUNT_PREDICTION_SCHEMA,MIXED_PPC_SCHEMA,MIXED_PREDICTION_SCHEMA,FAIR_REFERENCE_SCHEMA)

function prior_report(t,counts;seed,interval=.95,owner_counts=nothing,source=:generated)
    lo,hi=interval_bounds(interval);n=length(t.person);K=length(t.categories)
    size(counts,2)==K && size(counts,1)>0 || throw(ArgumentError("prior count dimensions must be draws by categories"))
    all(x->x isa Integer && !(x isa Bool) && 0<=x<=n,counts) && all(sum(counts;dims=2).==n) ||
        throw(ArgumentError("each prior replica must contain exactly the declared number of ratings"))
    mixed=_owned_support(t)
    cells=mixed ? [(g,k) for g in eachindex(t.supports) for k in t.supports[g]] : [(0,k) for k in 1:K]
    values=mixed ? owner_counts : counts
    values!==nothing && size(values)==(size(counts,1),length(cells)) ||
        throw(ArgumentError("mixed supports require counts separated by steps owner"))
    if mixed
        all(x->x isa Integer && !(x isa Bool) && x>=0,values) || throw(ArgumentError("invalid owner counts"))
        for g in eachindex(t.supports)
            ix=findall(c->first(c)==g,cells)
            all(sum(values[:,ix];dims=2).==count(==(g),t.group)) || throw(ArgumentError("owner count totals disagree"))
        end
        for k in 1:K
            ix=findall(c->last(c)==k,cells)
            vec(sum(values[:,ix];dims=2))==counts[:,k] || throw(ArgumentError("aggregate and owner counts disagree"))
        end
    end
    stats(x)=(;mean=mean(x),median=median(x),lower=quantile(x,lo),upper=quantile(x,hi))
    rows=[merge((;category=t.categories[k],n=g==0 ? n : count(==(g),t.group),stats(view(values,:,j))...),
        mixed ? (;owner=t.owner,level=deepcopy(t.group_levels[g])) : (;)) for (j,(g,k)) in enumerate(cells)]
    (;schema=PRIOR_SCHEMA,kind=:prior_predictive,api=contract(t),category_levels=copy(t.categories),
      replicated_counts=copy(counts),count_shape=size(counts),seed=Int(seed),ndraws=size(counts,1),
      design=design(t),rows,interval,n_observations=n,grouping_by_support=mixed,
      target_identity=B._cache_hash(record(t)),source,
      conditioning=:declared_design_not_observed_scores,
      interpretation="Prior category-use simulation, not evidence of prior suitability or calibration.",
      warnings=["Prior predictive intervals describe replicated category counts before conditioning on scores; they are not posterior intervals.",
                "Predictive endpoint MCSE is not assessed; few replicas support only exploratory checks."],
      scientific_acceptance=false)
end

function trace_payload(t,run;scale,parameters)
    m=selected(t,run;scale,parameters)
    series=[(;parameter=name,chain,iterations=copy(run.iterations[ix]),values=copy(m.values[ix,j]))
        for (j,name) in enumerate(m.names) for chain in 1:run.controls.chains
        for ix in (findall(==(chain),run.chain_ids),)]
    (;phase=:retained,parameters=m.names,chains=run.controls.chains,
      draws_per_chain=run.controls.ndraws,scale,series,
      interpretation="Retained iterations only; visual overlap cannot establish convergence.")
end

function check_plot_report(rep)
    rep.schema == FAIR_REFERENCE_SCHEMA && return check_fair_reference_report(rep)
    rep.schema in (MIXED_PPC_SCHEMA,MIXED_PREDICTION_SCHEMA) && return check_mixed_report(rep)
    rep.schema in (BOUNDED_PPC_SCHEMA,BOUNDED_PREDICTION_SCHEMA) && return check_bounded_report(rep)
    rep.schema in (COUNT_PPC_SCHEMA,COUNT_PREDICTION_SCHEMA) && return check_count_report(rep)
    rep.schema in REPORT_SCHEMAS || throw(ArgumentError("unsupported additive report schema"))
    if rep.schema==PRIOR_SCHEMA
        string(rep.kind)=="prior_predictive" && rep.ndraws>0 && rep.n_observations>0 ||
            throw(ArgumentError("invalid prior predictive report"))
        interval_bounds(rep.interval)
        !isempty(rep.rows) && all(r->0<=r.lower<=r.median<=r.upper<=r.n && isfinite(r.mean),rep.rows) ||
            throw(ArgumentError("invalid prior count intervals"))
    elseif rep.schema==PREDICTION_SCHEMA
        string(rep.kind)=="prediction" && string(rep.interval_target)=="posterior_category_probability" ||
            throw(ArgumentError("prediction intervals must describe category probabilities"))
        interval_bounds(rep.interval)
        !isempty(rep.cells) && length(rep.cells)==length(rep.rows)*length(rep.category_levels) ||
            throw(ArgumentError("incomplete prediction cells"))
        for (j,_) in enumerate(rep.rows)
            cells=filter(r->r.position==j,rep.cells)
            length(cells)==length(rep.category_levels) && [r.category for r in cells]==collect(rep.category_levels) &&
                all(r->r.row==rep.rows[j],cells) ||
                throw(ArgumentError("prediction category order disagrees"))
            all(r->0<=r.lower<=r.upper<=1 && 0<=r.mean<=1,cells) &&
                isapprox(sum(r.mean for r in cells),1;atol=1e-10,rtol=0) || throw(ArgumentError("invalid probability summaries"))
            all(r->!r.structural_zero || r.mean==r.lower==r.upper==0,cells) ||
                throw(ArgumentError("structural-zero probability must remain zero"))
        end
    elseif rep.schema==REPORT_SCHEMA && hasproperty(rep,:traces)
        t=rep.traces
        string(t.phase)=="retained" && t.chains>0 && t.draws_per_chain>0 &&
            !isempty(t.parameters) && allunique(t.parameters) || throw(ArgumentError("invalid trace metadata"))
        length(t.series)==length(t.parameters)*t.chains || throw(ArgumentError("incomplete trace series"))
        Set((s.parameter,s.chain) for s in t.series)==Set((p,c) for p in t.parameters for c in 1:t.chains) ||
            throw(ArgumentError("trace parameter/chain identities disagree"))
        for s in t.series
            length(s.values)==length(s.iterations)==t.draws_per_chain && all(isfinite,s.values) &&
                all(x->x isa Integer && !(x isa Bool) && x>0,s.iterations) &&
                all(diff(s.iterations).>0) || throw(ArgumentError("invalid retained trace order or values"))
        end
    end
    rep
end
