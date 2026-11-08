function _count_update!(mass,p,j)
    isfinite(p) && 0<=p<=1 || throw(ArgumentError("Invalid category probability"))
    # Descending updates preserve the previous polynomial without a second array.
    for c in j:-1:1
        mass[c+1]=(1-p)*mass[c+1]+p*mass[c]
    end
    mass[1]*=1-p
    nothing
end

function _category_count_values(t,draws;rater,group,category,max_count_updates)
    max_count_updates isa Integer && !(max_count_updates isa Bool) && max_count_updates>0 ||
        throw(ArgumentError("max_count_updates must be a positive integer"))
    category isa Integer && !(category isa Bool) || throw(ArgumentError("category must be a declared integer score"))
    d=t.data;r=_level(rater,d.rater_levels,"rater");g=_level(group,d.optional_levels[:group],"group")
    k=_level(category,d.category_levels,"category")
    ids=findall(n->d.rater[n]==r && d.optional[:group][n]==g,1:d.n)
    n=length(ids);S=size(draws,1);K=length(d.category_levels)
    n>0 || throw(ArgumentError("Selected rater/group cell has no observations"))
    size(draws,2)==L.dimension(t) && S>=2 && all(isfinite,draws) ||
        throw(ArgumentError("Expected at least two finite, complete coordinate draws"))
    updates=big(S)*n*(n+3)÷2
    updates<=max_count_updates || throw(ArgumentError("Exact count recurrence exceeds max_count_updates; raise the explicit budget rather than drop draws or observations"))
    observed=count(i->d.category[i]==k,ids)
    values=zeros(S,4);mass=zeros(n+1);a=zeros(K);max_mass_error=0.
    for (s,q) in enumerate(eachrow(draws))
        v=coordinates(t,q);fill!(mass,0.);mass[1]=1.;expected=0.
        for (j,i) in enumerate(ids)
            z=_weights!(a,v,d,i);p=exp(a[k]-z)
            _count_update!(mass,p,j);expected+=p
        end
        error=abs(sum(mass)-1);max_mass_error=max(max_mass_error,error)
        all(isfinite,mass) && error<=max(1e-12,16n*eps(Float64)) ||
            throw(ArgumentError("Predictive count mass failed normalization"))
        values[s,1]=expected
        values[s,2]=observed==n ? 1. : sum(view(mass,1:observed+1))
        values[s,3]=observed==0 ? 1. : sum(view(mass,observed+1:n+1))
        values[s,4]=mass[observed+1]
    end
    fixed=Set{String}()
    observed==n && push!(fixed,"lower_tail")
    observed==0 && push!(fixed,"upper_tail")
    (;values,names=["expected_count","lower_tail","upper_tail","observed_mass"],fixed,
      observations=ids,n_observations=n,observed_count=observed,max_mass_error,
      count_updates=Int(updates),workspace_cells=4S+n+1+K)
end

function _count_summaries(x,chains;split_chains=true,rhat_threshold=1.01,ess_threshold=400.)
    precision=B._posterior_mcse_rows(x.values,x.names,chains;probabilities=(),
        parameter_space=:conditional_count_function,structurally_fixed_parameters=x.fixed)
    diagnostics=B._candidate_mcmc_diagnostic_rows(x.values,x.names,chains;
        parameter_space=:conditional_count_function,structurally_fixed_parameters=x.fixed,
        split_chains,rhat_threshold,ess_threshold)
    [ (;quantity=Symbol(name),mean=mean(view(x.values,:,j)),mean_mcse=precision[j].mean_mcse,
        mcse_status=name in x.fixed ? :structurally_fixed :
            !ismissing(precision[j].mean_mcse) ? :available : precision[j].mcse_status,
        mcse_method=precision[j].mcse_method,diagnostics=diagnostics[j]) for (j,name) in enumerate(x.names) ]
end

"""
    category_predictive_check(result; rater, group, category,
                              max_count_updates=50_000_000)

Check one observed rater/group category count using every retained joint draw.
Returns the expected count and inclusive probabilities P(Nrep<=Nobs),
P(Nrep>=Nobs), and P(Nrep==Nobs), with chain-aware mean MCSE, focal diagnostics
and whole-fit warnings. The two inclusive tails sum to 1 plus the point mass;
they are not complements, a two-sided p-value or calibrated rejection rules.

Conditional on each draw, the selected rating indicators are independent with
their row-specific category probabilities. Their Poisson-binomial distribution
is integrated exactly by a positive coefficient recurrence, then averaged over
draws. This retains posterior dependence and heterogeneity; substituting average
probabilities or a single binomial distribution changes the calculation.
Prediction repeats the same people/items/rater/group allocation. No new levels,
shared response/class effects, conditional-probability intervals or count
quantile intervals are provided. No fitting, predictive RNG or subsampling occurs.

The recurrence uses O(S*n^2) work and 4*S+n+1+K Float64 workspace cells, excluding
coordinate reconstruction, sample validation and diagnostics. The explicit
count-update budget is S*n*(n+3)/2; exceeding it raises an error. Small sampled
probabilities may underflow; a constant sampled function has unavailable MCSE,
not proof of zero probability. Support-fixed inclusive tails are labelled fixed.
Choose discrepancies before inspection where possible; selected follow-ups are
exploratory. This does not identify centrality, bias or fairness. Save the report
with `save_report`; inspect numerical precision and global warnings separately.
"""
function category_predictive_check(result;rater,group,category,max_count_updates::Integer=50_000_000)
    t=_restore(result);run=result.run
    x=_category_count_values(t,run.draws;rater,group,category,max_count_updates)
    summaries=_count_summaries(x,run.controls.chains;split_chains=run.split_chains_requested,
        rhat_threshold=run.checked.rhat_threshold,ess_threshold=run.checked.ess_threshold)
    diagnostics=RI._diagnostics(t,run,_draws(t,run.draws))
    body=(;kind=:rater_group_category_predictive_check,scope=SCOPE,
        target_identity=result.target_identity,source_sample_content_hash=result.content_hash,prior=_prior(t.prior),
        rater,group,category,conditioning=:same_people_items_rater_group_and_allocation,
        observation_indices=x.observations,n_observations=x.n_observations,observed_count=x.observed_count,
        expected_count=summaries[1],lower_tail=summaries[2],upper_tail=summaries[3],observed_mass=summaries[4],
        total_draws=size(run.draws,1),chains=run.controls.chains,chain_ids=copy(run.chain_ids),iterations=copy(run.iterations),
        method=:conditional_poisson_binomial_recurrence,max_count_updates,count_updates=x.count_updates,
        workspace_cells=x.workspace_cells,max_mass_error=x.max_mass_error,evaluated_draws_hash=B._cache_hash(x.values),
        diagnostics,sampling_warning=!diagnostics.qualified,
        mcse_warning=any(r->!(r.mcse_status in (:available,:structurally_fixed)),summaries),
        precision_threshold_applied=false,
        warning="Exploratory conditional predictive tails, not calibrated p-values or automatic misfit, centrality, bias or fairness decisions. Inspect focal MCSE/diagnostics and whole-fit warnings; multiple selected checks do not control multiplicity.")
    merge(body,(;content_hash=B._cache_hash(body)))
end
