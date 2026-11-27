# A whole performance is one predictive unit; its shared residual is integrated once.
const _EXPLANATORY_CRITERIA_SCHEMA="bayesianmgmfrm.explanatory_profile_criteria.v1"
const _EXPLANATORY_COMPARISON_SCHEMA="bayesianmgmfrm.explanatory_profile_comparison.v1"
const _EXPLANATORY_COMPARISON_SCHEMAS=(_EXPLANATORY_CRITERIA_SCHEMA,_EXPLANATORY_COMPARISON_SCHEMA,"bayesianmgmfrm.bounded_rating_criteria.v1","bayesianmgmfrm.bounded_rating_comparison.v1","bayesianmgmfrm.count_rating_criteria.v1","bayesianmgmfrm.count_rating_comparison.v1","bayesianmgmfrm.mixed_event_criteria.v1","bayesianmgmfrm.mixed_event_comparison.v1","bayesianmgmfrm.mixed_profile_criteria.v1","bayesianmgmfrm.mixed_profile_comparison.v1")
_explanatory_score_report(x)=hasproperty(x,:schema) && x.schema in (_EXPLANATORY_CRITERIA_SCHEMA,"bayesianmgmfrm.bounded_rating_criteria.v1","bayesianmgmfrm.count_rating_criteria.v1","bayesianmgmfrm.mixed_event_criteria.v1","bayesianmgmfrm.mixed_profile_criteria.v1")
_explanatory_absent(x)=x===nothing || ismissing(x)

# Bind the held-out observations, independently of the model's latent effects.
function _event_comparison_binding(t, unit, profiles)
    column = getproperty(t.columns, unit)
    column === nothing && throw(ArgumentError("declare the $unit ID column before event scoring"))
    _cache_hash((; unit, column, ids=copy(t.table[column]),
        people=deepcopy(t.people[t.person]), observed=t.categories[t.category],
        supports=[t.categories[t.supports[g]] for g in t.group],
        profiles=[(;p.performance,p.rows) for p in profiles]))
end
_event_comparison_binding(r) = get(r, :comparison_observation_binding, r.observation_binding)

function _mrcml_profile_design(t::AdditiveFacets.MRCMLTarget, unit, integrate)
    unit in (:performance, :assessment) || throw(ArgumentError("declare unit=:performance or :assessment"))
    column=getproperty(t.columns,unit)
    column === nothing && throw(ArgumentError("declare the $unit ID column before event scoring"))
    random=get(t.spec_record,:random_effects,Symbol[])
    candidates=filter(b->b.name in random && b.column===column,t.facets)
    isempty(candidates) ? (integrate===nothing || throw(ArgumentError("no iid shared effect owns this event column"))) :
        (length(candidates)==1 && integrate===only(candidates).name || throw(ArgumentError("integrate must name the iid shared effect owning this event column")))
    block=integrate===nothing ? nothing : only(candidates)
    residual=integrate===nothing ? nothing : only(filter(b->b.name===integrate,t.prior_blocks))
    ids=t.table[column];_,levels=AdditiveFacets._labels(ids,column)
    groups=[findall(isequal(id),ids) for id in levels]
    for rows in groups
        keep=setdiff(eachindex(t.person),rows)
        Set(t.person[keep])==Set(t.person) || throw(ArgumentError("withholding an event removes a person; this comparison requires known persons"))
        all(b->b.name===integrate || Set(b.index[keep])==Set(b.index),t.facets) || throw(ArgumentError("withholding an event removes a facet level; this comparison requires known levels"))
        Set(t.group[keep])==Set(t.group) || throw(ArgumentError("withholding an event removes a step owner"))
    end
    profiles=[(;profile=i,performance=deepcopy(levels[i]),rows=copy(rows),n_ratings=length(rows)) for (i,rows) in enumerate(groups)]
    observations=deepcopy(t.table)
    supports=[copy(t.categories[t.supports[g]]) for g in t.group]
    binding=_event_comparison_binding(t,unit,profiles)
    (;unit,integrate,profiles,observations,supports,observation_binding=binding,
        conditioning=:known_other_owners_observed_covariate_roster,
        integration=integrate===nothing ? :joint_conditional_event_profile : :joint_shared_gaussian,
        multiplier=1,groups,block,residual)
end

function _explanatory_training_target(t::AdditiveFacets.MRCMLTarget,d,id)
    A=AdditiveFacets;j=findfirst(p->isequal(p.performance,id),d.profiles)
    j===nothing && throw(ArgumentError("unknown withheld event ID"))
    keep=setdiff(eachindex(t.person),d.groups[j]);r=A.record(t)
    # Keep the full parameter roster, basis, anchors and priors. Only likelihood rows change.
    op=merge(r.operator,(;n_obs=length(keep),pattern_of_row=r.operator.pattern_of_row[keep]))
    facets=[merge(b,(;index=b.index[keep])) for b in r.facets]
    spec_record=r.spec_record
    if hasproperty(spec_record,:context_facets)
        spec_record=merge(spec_record,(;context_facets=[merge(b,(;index=b.index[keep])) for b in spec_record.context_facets]))
    end
    A.restore_mrcml(merge(r,(;operator=op,facets,spec_record,person=r.person[keep],
        category=r.category[keep],group=r.group[keep],table=Dict(c=>v[keep] for (c,v) in r.table))))
end

function _explanatory_integrals(t::AdditiveFacets.MRCMLTarget,d,run,quads;
        training=t,profiles=eachindex(d.groups))
    # Training keeps the same coordinates; evaluate held-out rows in the full target.
    A=AdditiveFacets
    A.names(training,:raw)==A.names(t,:raw) || throw(ArgumentError("event refit changed parameter coordinates"))
    selected=collect(profiles);coarse=zeros(size(run.draws,1),length(selected));fine=similar(coarse)
    for (s,q) in enumerate(eachrow(run.draws))
        if d.integrate===nothing
            row_ll=A.pointwise(t,q)
            for (g,i) in enumerate(selected);coarse[s,g]=fine[s,g]=sum(row_ll[d.groups[i]]);end
        else
            v=A._mrcml_unpack(t,q);b=d.residual
            sd=b.hyper_idx==0 ? b.marginal_sd : v.hyper_sds[b.name]
            weights=A._diagnostic_logweights(t,q)
            for (g,i) in enumerate(selected)
                rows=d.groups[i];level=d.block.index[first(rows)]
                effect=v.eta_xi[b.eta_range[level]]
                for (out,quad) in zip((coarse,fine),quads)
                    sums=copy(quad.logweights)
                    for j in eachindex(sums),n in rows
                        slots=t.operator.pattern_ranges[t.operator.pattern_of_row[n]]
                        logits=weights[n,1:length(slots)] .+ t.operator.B_pat[slots].*(effect-sd*quad.nodes[j])
                        y=t.category[n]-first(t.supports[t.group[n]])+1
                        sums[j]+=logits[y]-_logsumexp(logits)
                    end
                    out[s,g]=_logsumexp(sums)
                end
            end
        end
    end
    all(isfinite,coarse) && all(isfinite,fine) || throw(ArgumentError("nonfinite event log likelihood"))
    (;coarse,fine)
end

function _explanatory_profile_design(t,unit,integrate)
    A=AdditiveFacets
    t isa A.MRCMLTarget && return _mrcml_profile_design(t,unit,integrate)
    t isa A.ExplanatoryTarget || throw(ArgumentError("profile integration requires an explanatory fit"))
    unit in (:performance,:assessment) || throw(ArgumentError("declare unit=:performance or :assessment explicitly"))
    integrate isa Symbol || throw(ArgumentError("integrate must name the iid shared-event facet"))
    found=findall(b->b.name===integrate,t.facets)
    length(found)==1 || throw(ArgumentError("integrate must name a declared facet"))
    b=t.facets[only(found)];rb=only(r for r in t.residuals if r.name===integrate)
    owner_column=getproperty(t.columns,unit)
    owner_column!==nothing && b.column===owner_column && rb.kind===:iid_population ||
        throw(ArgumentError("integrate requires the declared $unit column and an iid population residual; finite-sum-zero effects are not supported"))
    any(p->p.by===integrate,t.terms) && throw(ArgumentError("performance-specific response coefficients need additional integration; this route integrates one residual only"))
    groups=[findall(==(i),b.index) for i in eachindex(b.levels)]
    all(!isempty,groups) || throw(ArgumentError("every performance needs observed ratings"))
    for rows in groups
        keep=setdiff(eachindex(t.person),rows)
        Set(t.person[keep])==Set(t.person) || throw(ArgumentError("withholding this performance removes a person; new-person prediction is outside this task"))
        for other in t.facets
            other.name===integrate && continue
            Set(other.index[keep])==Set(other.index) || throw(ArgumentError("withholding this performance removes a $(other.name) level; other owners must remain known"))
        end
        Set(t.group[keep])==Set(t.group) || throw(ArgumentError("withholding removes a steps owner"))
    end
    cols=unique([t.columns.person,t.columns.score,values(t.columns.facets)...,
        (t.columns.performance===nothing ? Symbol[] : [t.columns.performance])...,
        (t.columns.assessment===nothing ? Symbol[] : [t.columns.assessment])...])
    observations=Dict(c=>copy(t.table[c]) for c in cols)
    supports=[copy(t.categories[t.supports[t.group[n]]]) for n in eachindex(t.person)]
    profiles=[(;profile=i,performance=deepcopy(b.levels[i]),rows=copy(rows),n_ratings=length(rows)) for (i,rows) in enumerate(groups)]
    binding=_cache_hash((;columns=t.columns,observations,supports,integrate,unit))
    (;unit,integrate,profiles,observations,supports,observation_binding=binding,
      conditioning=:known_other_owners_observed_covariate_roster,
      integration=unit===:performance ? :one_iid_performance_residual_joint_profile : :one_iid_assessment_residual_joint_profile,
      multiplier=1,groups,block=b,residual=rb)
end

function _explanatory_training_target(t,d,id)
    A=AdditiveFacets;idx=findfirst(p->isequal(p.performance,id),d.profiles)
    idx===nothing && throw(ArgumentError("unknown withheld performance ID"))
    keep=setdiff(eachindex(t.person),d.groups[idx]);r=A.record(t)
    # Materialize the original means/deviations. Recomputing them would change the task.
    s=hasproperty(r.specification,:decomposition) ? Base.structdiff(r.specification,(;decomposition=nothing)) : r.specification
    levels=merge(r.levels,(;facets=merge(r.levels.facets,NamedTuple{(d.integrate,)}((filter(!isequal(id),d.block.levels),)))))
    schema=A._explanatory_logscale(t) ? "bayesianmgmfrm.explanatory_facet_design.v4" : (A._expanded_terms(t) || A._owned_support(t)) ? "bayesianmgmfrm.explanatory_facet_design.v3" : "bayesianmgmfrm.explanatory_facet_design.v1"
    A.restore_explanatory(merge(r,(;schema,specification=s,levels,table=Dict(c=>v[keep] for (c,v) in t.table))))
end

"""
    loo_refit_plan(fit::AdditiveFacets.Fit, performance_id;
        unit=:performance, integrate)

Return `target` for an explicit held-performance refit, preserving all common
priors and the original observed predictor means/deviations. `integrate` names
the iid facet associated with the declared performance column (or assessment
column with `unit=:assessment`). Fit `plan.target`
with explicit sampler controls, then supply `performance_id => saved_fit` to
`criteria(...; refits=[...])`. This call starts no fitting or RNG.
"""
function loo_refit_plan(f::AdditiveFacets.Fit,id;unit=nothing,integrate=nothing)
    t=AdditiveFacets.checked(f;full=true)
    if t isa AdditiveFacets.MixedOutcomeTarget
        d=_mixed_profile_design(t,unit,integrate)
        return (;target=_mixed_training_target(t,d,id),performance=deepcopy(id),unit,integrate,
          source_sample_hash=f.record.content_hash,observation_binding=d.observation_binding,
          predictor_conditioning=:original_observed_roster,automatic_refit=false)
    end
    d=_explanatory_profile_design(t,unit,integrate)
    (;target=_explanatory_training_target(t,d,id),performance=deepcopy(id),unit,integrate,
      source_sample_hash=f.record.content_hash,observation_binding=d.observation_binding,
      predictor_conditioning=:original_observed_roster,automatic_refit=false)
end

function loo_refit_plan(r::NamedTuple,id;kwargs...)
    _sample_schema_symbol(r)===:criterion_collapse ||
        throw(ArgumentError("loo_refit_plan requires an explanatory AdditiveFacets.Fit or CriterionCollapse fit"))
    return _CC_MOD.loo_refit_plan(r,id;kwargs...)
end

function _explanatory_transport(from,to,q)
    A=AdditiveFacets;out=zeros(to.dimension)
    for b in from.residuals
        dest=only(r for r in to.residuals if r.name===b.name)
        (b.kind,b.sd,b.logmean,b.logsd,b.scale_kind)==(dest.kind,dest.sd,dest.logmean,dest.logsd,dest.scale_kind) || throw(ArgumentError("residual prior mismatch"))
        old=A._owner_levels(from,b.name);new=A._owner_levels(to,b.name)
        if isempty(b.raw)
            isempty(dest.raw) || throw(ArgumentError("residual active/zero mismatch"))
        elseif b.kind===:iid_population
            for (j,id) in enumerate(old)
                k=findfirst(isequal(id),new);k===nothing && throw(ArgumentError("unknown residual identity"))
                out[dest.raw[k]]=q[b.raw[j]]
            end
        else
            old==new || throw(ArgumentError("finite residual roster changed"));out[dest.raw]=q[b.raw]
        end
        b.hyper==0 || (out[dest.hyper]=q[b.hyper])
    end
    from.group_levels==to.group_levels && from.supports==to.supports || throw(ArgumentError("step support mismatch"))
    for (r,s) in zip(from.steps,to.steps);out[s]=q[r];end
    for term in from.terms
        dest=only(p for p in to.terms if A._term_name(p)==A._term_name(term))
        (term.mean,term.sd)==(dest.mean,dest.sd) || throw(ArgumentError("coefficient prior mismatch"))
        out[dest.raw]=q[term.raw]
    end
    out
end

function _explanatory_quadrature(orders,tolerance,score_tolerance)
    length(orders)==2 && all(n->n isa Integer && !(n isa Bool) && n>=3,orders) && orders[1]<orders[2] ||
        throw(ArgumentError("quadrature_orders needs two increasing integer orders >=3"))
    for x in (tolerance,score_tolerance)
        x isa Real && !(x isa Bool) && isfinite(x) && x>0 || throw(ArgumentError("quadrature tolerances must be finite and positive"))
    end
    map(orders) do n
        e=eigen(SymTridiagonal(zeros(n),sqrt.(Float64.(1:n-1))))
        (;nodes=e.values,logweights=log.(e.vectors[1,:].^2))
    end
end

function _explanatory_integral(eta,tau,ys,quad,sd)
    sums=copy(quad.logweights)
    for j in eachindex(sums)
        for n in eachindex(eta)
            # Local category order permits shared and owner-specific supports.
            value=0.;normalizer=0.;observed=0.;shift=eta[n]-sd*quad.nodes[j]
            for h in eachindex(tau[n])
                value+=shift-tau[n][h]
                normalizer=max(normalizer,value)+log1p(exp(-abs(normalizer-value)))
                h+1==ys[n] && (observed=value)
            end
            sums[j]+=observed-normalizer
        end
    end
    _logsumexp(sums)
end

function _explanatory_integrals(t,d,run,quads;training=t,profiles=eachindex(d.groups))
    A=AdditiveFacets;ids=collect(profiles);S=size(run.draws,1)
    coarse=zeros(S,length(ids));fine=similar(coarse)
    for (s,q) in enumerate(eachrow(run.draws))
        z=training===t ? q : _explanatory_transport(training,t,q);v=coordinates(t,z)
        sd=v.residual_sd[d.integrate]
        for (g,id) in enumerate(ids)
            rows=d.groups[id]
            u_raw=isempty(d.residual.raw) ? 0.0 : z[d.residual.raw[id]]
            eta=[v.person[t.person[n]]+A.response_shift(t,v,n)-sum(v.facets[b.name][b.index[n]] for b in t.facets)+sd*u_raw for n in rows]
            tau=[collect(v.steps[t.group[n],1:length(t.supports[t.group[n]])-1]) for n in rows]
            ys=[t.category[n]-first(t.supports[t.group[n]])+1 for n in rows]
            coarse[s,g]=_explanatory_integral(eta,tau,ys,quads[1],sd)
            fine[s,g]=_explanatory_integral(eta,tau,ys,quads[2],sd)
        end
    end
    all(isfinite,coarse) && all(isfinite,fine) || throw(ArgumentError("nonfinite profile integral"))
    (;coarse,fine)
end

"""
    pointwise_loglikelihood(fit::AdditiveFacets.Fit; unit=:performance,
        integrate, quadrature_orders=(61,121), quadrature_tolerance=1e-7)

With `unit=:assessment`, the declared assessment column defines the held-out
event instead. Standard MRCML uses `integrate=nothing` and sums conditional
rating log densities within each event. For an iid shared-event model, name
that facet with `integrate` to inspect prior-integrated **joint event-profile** factors at all retained
draws. `integrate` is the user-declared iid performance facet, not a hard-coded
role name. Other owners stay known. Returns fine/coarse log-density matrices,
profile/observation bindings and chain order; this allocates draws × profiles.
Factors integrate the performance residual once, retaining regression means.
Use `criteria` for checked PSIS scoring; do not treat these as rating-wise factors.
"""
function _additive_rating_binding(t)
    row_cats = [copy(t.categories[t.supports[t.group[i]]]) for i in eachindex(t.person)]
    payload = (;
        people = [string(t.people[p]) for p in t.person],
        observed = [t.categories[c] for c in t.category],
        row_supports = row_cats,
    )
    return _cache_hash(payload)
end

function _compare_additive_rating_models(pairs_vec::AbstractVector{<:Pair};
        criterion::Symbol = :psis_loo, pareto_k_threshold::Real = 0.7)
    criterion in (:psis_loo, :loo, :waic) ||
        throw(ArgumentError("AdditiveFacets rating-wise compare_models requires criterion in (:psis_loo, :loo, :waic); got $(repr(criterion))"))
    length(pairs_vec) >= 2 || throw(ArgumentError("supply at least two labeled AdditiveFacets.Fit models to compare_models"))
    labels = [strip(string(first(p))) for p in pairs_vec]
    all(!isempty, labels) && allunique(labels) || throw(ArgumentError("distinct nonempty model labels are required"))
    fits = AdditiveFacets.Fit[]
    targets = Any[]
    for p in pairs_vec
        v = last(p)
        v isa AdditiveFacets.Fit || throw(ArgumentError("all compared models must be AdditiveFacets.Fit objects"))
        t = AdditiveFacets.checked(v; full = true)
        t isa Union{AdditiveFacets.Target, AdditiveFacets.MRCMLTarget} ||
            throw(ArgumentError("direct AdditiveFacets compare_models supports conditionally independent rating-wise models (`Target` / `MRCMLTarget`); for hierarchical performance models, pass `criteria(fit; unit = :performance, integrate = ...)` reports to `compare_models`"))
        push!(fits, v)
        push!(targets, t)
    end
    obs0 = _additive_rating_binding(targets[1])
    for (lbl, tk) in zip(labels, targets)
        _additive_rating_binding(tk) == obs0 ||
            throw(ArgumentError("model $(repr(lbl)) does not bind the exact same rating observations and category supports"))
    end
    crit_key = criterion === :loo ? :psis_loo : criterion
    evals = [crit_key === :waic ? waic(fk) : psis_loo(fk; pareto_k_threshold) for fk in fits]
    elpds = [crit_key === :waic ? e.elpd_waic : e.elpd_loo for e in evals]
    pws = [crit_key === :waic ? e.pointwise.elpd_waic : e.pointwise.elpd_loo for e in evals]
    order = sortperm(elpds; rev = true)
    best_idx = order[1]
    N_u = length(pws[best_idx])
    rows = [
        begin
            diff_vec = pws[idx] .- pws[best_idx]
            d_elpd = sum(diff_vec)
            se_d = (idx == best_idx || N_u <= 1) ? 0.0 : sqrt(N_u * var(diff_vec; corrected = true))
            (;
                rank = rnk,
                model_label = labels[idx],
                elpd = elpds[idx],
                p_effective = crit_key === :waic ? evals[idx].p_waic : evals[idx].p_loo,
                elpd_difference = d_elpd,
                se_difference = se_d,
                bad_pareto_k_count = crit_key === :waic ? missing : evals[idx].bad_pareto_k_count,
                max_pareto_k = crit_key === :waic ? missing : evals[idx].max_pareto_k,
                qualified = qualify(fits[idx]).qualified,
                source_content_hash = fits[idx].record.content_hash,
            )
        end for (rnk, idx) in enumerate(order)
    ]
    body = (;
        schema = "bayesianmgmfrm.additive_rating_comparison.v1",
        criterion = crit_key,
        unit = :rating,
        observation_binding = obs0,
        n_units = N_u,
        rows,
        warning = "Rating-wise elpd comparison conditions on known finite-panel levels; inspect pareto_k and whole-fit qualification before substantive model selection.",
    )
    return merge(body, (; report_hash = _cache_hash(body)))
end

function pointwise_loglikelihood(f::AdditiveFacets.Fit;unit=nothing,integrate=nothing,
        quadrature_orders=nothing,quadrature_tolerance=1e-7)
    t=AdditiveFacets.checked(f;full=true)
    if t isa Union{AdditiveFacets.Target,AdditiveFacets.MRCMLTarget,AdditiveFacets.BoundedTarget,AdditiveFacets.CountTarget} &&
            !(t isa AdditiveFacets.MRCMLTarget && unit in (:performance,:assessment))
        (unit in (nothing,:rating) && integrate===nothing && quadrature_orders===nothing) ||
            throw(ArgumentError("finite-panel, MRCML, or scalar bounded/count AdditiveFacets fits evaluate conditional rating-wise log-densities (`unit = :rating`, `integrate = nothing`)"))
        S=size(f.record.run.draws,1)
        pw1=AdditiveFacets.pointwise(t,view(f.record.run.draws,1,:))
        ll=Matrix{Float64}(undef,S,length(pw1))
        ll[1,:].=pw1
        _parallel_ranges(S-1, length(pw1)) do indices
            for i in indices
                s = i + 1
                ll[s,:] .= AdditiveFacets.pointwise(t,view(f.record.run.draws,s,:))
            end
        end
        obs_b=t isa Union{AdditiveFacets.Target,AdditiveFacets.MRCMLTarget} ? _additive_rating_binding(t) : f.record.target_identity
        return (;log_density=ll,observation_binding=obs_b,unit=:rating,integrate=nothing,
            conditioning=t isa Union{AdditiveFacets.Target,AdditiveFacets.MRCMLTarget} ? :known_finite_panel_levels : :known_owners_observed_covariates,
            source_sample_hash=f.record.content_hash,target_identity=f.record.target_identity,
            chain_ids=copy(f.record.run.chain_ids),iterations=copy(f.record.run.iterations),multiplier=1)
    end
    if t isa AdditiveFacets.MixedOutcomeTarget
        if unit===:event && integrate===nothing
            quadrature_orders===nothing || throw(ArgumentError("quadrature_orders applies to unit=:performance integration"))
            S=size(f.record.run.draws,1);E=length(t.person)
            ll=zeros(Float64,S,E)
            for (s,q) in enumerate(eachrow(f.record.run.draws));ll[s,:]=AdditiveFacets.pointwise(t,q);end
            bind=_mixed_observation_binding(t;unit=:event)
            return (;log_density=ll,observation_binding=bind.binding,unit=:event,integrate=nothing,
              conditioning=:known_owners_observed_covariates,source_sample_hash=f.record.content_hash,
              target_identity=f.record.target_identity,chain_ids=copy(f.record.run.chain_ids),
              iterations=copy(f.record.run.iterations),multiplier=1)
        end
        d=_mixed_profile_design(t,unit,integrate)
        q_orders=quadrature_orders===nothing ? (d.owner_block.D_dim==1 ? (31,61) : (21,31)) : quadrature_orders
        quads=_explanatory_quadrature(q_orders,quadrature_tolerance,1e-5)
        x=_mixed_profile_integrals(t,d,f.record.run,quads)
        error=maximum(abs.(x.fine.-x.coarse))
        return (;log_density=x.fine,coarse_log_density=x.coarse,profiles=d.profiles,
          observation_binding=d.observation_binding,unit,integrate,d.conditioning,d.integration,
          quadrature_error=error,quadrature_passed=error<=quadrature_tolerance,
          quadrature_orders=q_orders,quadrature_tolerance,source_sample_hash=f.record.content_hash,
          target_identity=f.record.target_identity,chain_ids=copy(f.record.run.chain_ids),
          iterations=copy(f.record.run.iterations),multiplier=1)
    end
    t isa AdditiveFacets.MRCMLTarget && integrate===nothing && quadrature_orders!==nothing && throw(ArgumentError("MRCML event scores do not use quadrature"))
    q_orders=t isa AdditiveFacets.MRCMLTarget && integrate===nothing ? () : quadrature_orders===nothing ? (61,121) : quadrature_orders
    d=_explanatory_profile_design(t,unit,integrate)
    quads=isempty(q_orders) ? nothing : _explanatory_quadrature(q_orders,quadrature_tolerance,1e-5)
    x=_explanatory_integrals(t,d,f.record.run,quads)
    error=maximum(abs.(x.fine.-x.coarse))
    (;log_density=x.fine,coarse_log_density=x.coarse,profiles=d.profiles,
      observation_binding=d.observation_binding,unit,integrate,d.conditioning,d.integration,
      quadrature_error=error,quadrature_passed=error<=quadrature_tolerance,
      quadrature_orders=q_orders,quadrature_tolerance,source_sample_hash=f.record.content_hash,
      target_identity=f.record.target_identity,chain_ids=copy(f.record.run.chain_ids),
      iterations=copy(f.record.run.iterations),multiplier=1)
end

function _explanatory_check_block(block,S,chains)
    per=S÷chains
    block isa Integer && !(block isa Bool) && block>0 && per%block==0 && per÷block>=2 ||
        throw(ArgumentError("MCSE blocks must divide retained iterations per chain, with at least two blocks"))
    nothing
end
function _explanatory_block_mcse(ll,reff,block,chains;psis=true)
    S,G=size(ll);_explanatory_check_block(block,S,chains)
    values=Float64[]
    for first in 1:block:S
        keep=vcat(1:first-1,first+block:S);value=0.
        for g in 1:G
            l=ll[keep,g]
            value+=psis ? _logsumexp(l.+_SA_MOD._psis_smooth_log_ratios(-l;r_eff=reff[g]).norm_log_weights) : _logsumexp(l)-log(length(l))
        end
        push!(values,value)
    end
    J=length(values)
    (;block,mcse=sqrt((J-1)/J*sum(abs2,values.-mean(values))),blocks=J,
      relative_efficiency=:held_at_original_estimate)
end

_explanatory_profile_metadata(d)=(;d.unit,d.integrate,d.profiles,d.observations,d.supports,
    d.observation_binding,d.conditioning,d.integration,d.multiplier)

"""
    criteria(fit::AdditiveFacets.Fit; unit=:performance, integrate,
        refits=[], independent_refit_rng=false, mcse_blocks=(),
        quadrature_orders=(61,121), quadrature_tolerance=1e-7,
        score_tolerance=1e-5)

Score joint held-performance (or `unit=:assessment`) predictions with integrated PSIS and all original
draws. Supply existing `performance_id => fit` refits; each is checked against
`loo_refit_plan(fit,id;unit,integrate).target`, including unchanged common priors,
materialized features and row identities. This never starts MCMC. Explicitly
declare independent refit RNG streams to combine their Monte Carlo variances.

The total MCSE retains cross-profile shared-draw covariance. It omits PSIS tail-fit
uncertainty; optional contiguous `mcse_blocks` refit the tails as a sensitivity
check (original relative efficiencies held fixed). These are computational errors,
not population SE or CrIs. Failed quadrature, PSIS or focal/whole-fit qualification
remain diagnostic-only, with no qualified total MCSE. No automatic winner, WAIC,
new-owner generalization, empirical acceptance or precision cutoff is supplied.
"""
function criteria(f::AdditiveFacets.Fit;unit=nothing,integrate=nothing,refits=Pair[],
        independent_refit_rng::Bool=false,mcse_blocks=(),quadrature_orders=nothing,
        quadrature_tolerance=1e-7,score_tolerance=1e-5,criteria::Tuple=(:waic,:psis_loo),pareto_k_threshold::Real=0.7)
    A=AdditiveFacets;CC=_CC_MOD;t=A.checked(f;full=true)
    if t isa Union{A.Target,A.MRCMLTarget} && !(t isa A.MRCMLTarget && unit in (:performance,:assessment))
        (unit in (nothing,:rating) && integrate===nothing && isempty(refits) && !independent_refit_rng && isempty(mcse_blocks) && quadrature_orders===nothing) ||
            throw(ArgumentError("finite-panel / MRCML AdditiveFacets targets have conditionally independent rating rows (`unit = :rating`, `integrate = nothing`, no performance refits)"))
        !isempty(criteria) && allunique(criteria) && all(in((:waic,:psis_loo)),criteria) ||
            throw(ArgumentError("choose distinct criteria from (:waic, :psis_loo) for finite-panel / MRCML AdditiveFacets.Fit"))
        scores=map(c->c===:waic ? waic(f) : psis_loo(f;pareto_k_threshold),criteria)
        return NamedTuple{criteria}(scores)
    end
    if t isa A.MixedOutcomeTarget
        if unit===:event && integrate===nothing
            isempty(refits) && !independent_refit_rng && isempty(mcse_blocks) && quadrature_orders===nothing ||
                throw(ArgumentError("event-wise mixed criteria do not accept performance refits, block checks, or quadrature orders"))
            return _mixed_event_criteria(f,t)
        end
        return _mixed_profile_criteria(f,t;unit,integrate,refits,independent_refit_rng,mcse_blocks,
            quadrature_orders,quadrature_tolerance,score_tolerance)
    end
    t isa Union{A.BoundedTarget,A.CountTarget} && return _bounded_criteria(f;unit,integrate,refits,independent_refit_rng,mcse_blocks)
    t isa A.MRCMLTarget && integrate===nothing && quadrature_orders!==nothing && throw(ArgumentError("MRCML event scores do not use quadrature"))
    q_orders=t isa A.MRCMLTarget && integrate===nothing ? () : quadrature_orders===nothing ? (61,121) : quadrature_orders
    d=_explanatory_profile_design(t,unit,integrate);run=f.record.run;S=size(run.draws,1)
    _check_psis_iterations(run.chain_ids,run.iterations)
    run.chain_ids==repeat(1:run.controls.chains;inner=S÷run.controls.chains) || throw(ArgumentError("stored chain order must remain intact"))
    refs=collect(refits);all(r->r isa Pair && last(r) isa A.Fit,refs) && allunique(first.(refs)) || throw(ArgumentError("refits must be unique performance_id => fit pairs"))
    quads=isempty(q_orders) ? nothing : _explanatory_quadrature(q_orders,quadrature_tolerance,score_tolerance)
    allunique(mcse_blocks) || throw(ArgumentError("MCSE block sizes must be distinct"))
    # Validate every reference before evaluating the full likelihood array.
    checked=map(refs) do (id,r)
        expected=_explanatory_training_target(t,d,id);training=A.checked(r;full=true)
        isequal(A.record(training),A.record(expected)) || throw(ArgumentError("refit $id changes training data, predictor values, priors, supports or identities"))
        (;id,fit=r,training,quality=qualify(r))
    end
    for b in mcse_blocks
        _explanatory_check_block(b,S,run.controls.chains)
        for r in checked
            rr=r.fit.record.run;_explanatory_check_block(b,size(rr.draws,1),rr.controls.chains)
        end
    end
    hashes=[f.record.content_hash;[r.fit.record.content_hash for r in checked]]
    allunique(hashes) || throw(ArgumentError("baseline and refit sample records must be distinct"))
    quality=qualify(f);x=_explanatory_integrals(t,d,run,quads)
    rows=NamedTuple[];influences=zeros(size(x.fine));reference_records=NamedTuple[]
    direct_variance=0.;direct_blocks=Dict(b=>0. for b in mcse_blocks)
    for (g,p) in enumerate(d.profiles)
        high=CC._profile_score(x.fine[:,g],-x.fine[:,g],run)
        low=CC._profile_score(x.coarse[:,g],-x.coarse[:,g],run)
        error=maximum(abs.(x.fine[:,g].-x.coarse[:,g]));score_error=abs(high.row.log_score-low.row.log_score)
        quadrature_ok=error<=quadrature_tolerance && score_error<=score_tolerance
        original=merge(high.row,(;quadrature_error=error,quadrature_score_error=score_error,quadrature_passed=quadrature_ok))
        j=findfirst(r->isequal(r.id,p.performance),checked)
        if j===nothing
            eligible=quadrature_ok && high.row.importance_status===:ok && high.row.mcse_status===:available
            push!(rows,(;p...,log_score=high.row.log_score,mcse=eligible ? high.row.mcse : nothing,
                eligible,method=d.integrate===nothing ? :conditional_psis : :integrated_psis,original,reference=nothing))
            influences[:,g]=high.influence
        else
            r=checked[j];rr=r.fit.record.run
            _check_psis_iterations(rr.chain_ids,rr.iterations)
            y=_explanatory_integrals(t,d,rr,quads;training=r.training,profiles=[g])
            fine=vec(y.fine);score=_logsumexp(fine)-log(length(fine))
            score_error=abs(score-(_logsumexp(vec(y.coarse))-log(length(fine))))
            error=maximum(abs.(y.fine.-y.coarse));qok=error<=quadrature_tolerance && score_error<=score_tolerance
            precision=CC._heldout_precision(exp.(fine.-score).-1,rr,true)
            eligible=qok && precision.mcse_status===:available && r.quality.qualified
            reference=(;source_sample_hash=r.fit.record.content_hash,target_identity=r.fit.record.target_identity,
                quality=r.quality,log_score=score,precision...,quadrature_error=error,
                quadrature_score_error=score_error,quadrature_passed=qok,
                original_score_difference=score-high.row.log_score,training_target_verified=true)
            push!(rows,(;p...,log_score=score,mcse=eligible ? precision.mcse : nothing,
                eligible,method=:direct_refit,original,reference))
            push!(reference_records,(;performance=p.performance,reference...))
            if eligible
                direct_variance+=precision.mcse^2
                for b in mcse_blocks
                    direct_blocks[b]+=_explanatory_block_mcse(y.fine,[1.],b,rr.controls.chains;psis=false).mcse^2
                end
            end
        end
    end
    keep=findall(r->r.method!==:direct_refit,rows)
    eligible=all(r->r.eligible,rows) && quality.qualified && (isempty(refs) || independent_refit_rng)
    total=isempty(keep) ? (;mcse=0.,mcse_status=:available,diagnostics=nothing) :
        CC._heldout_precision(vec(sum(influences[:,keep];dims=2)),run,eligible)
    available=eligible && total.mcse_status===:available
    mcse=available ? sqrt(total.mcse^2+direct_variance) : nothing
    blocks=NamedTuple[]
    for b in mcse_blocks
        if available
            ps=isempty(keep) ? 0. : _explanatory_block_mcse(x.fine[:,keep],[rows[g].original.r_eff for g in keep],b,run.controls.chains).mcse
            push!(blocks,(;block=b,mcse=sqrt(ps^2+direct_blocks[b]),status=:available))
        else
            push!(blocks,(;block=b,mcse=nothing,status=:unavailable))
        end
    end
    _prediction_seal((;schema=_EXPLANATORY_CRITERIA_SCHEMA,_explanatory_profile_metadata(d)...,
        comparison_observation_binding=_event_comparison_binding(t,unit,d.profiles),
        criterion=:psis_loo,rows,elpd=sum(r.log_score for r in rows),mcse,
        status=available ? :estimated : :diagnostic_only,
        problem_performances=[r.performance for r in rows if !r.eligible],
        mcse_status=available ? :available : :unavailable,shared_draw_precision=total,
        mcse_blocks=blocks,independent_refit_rng,reference_records,
        source_sample_hash=f.record.content_hash,target_identity=f.record.target_identity,
        prior=deepcopy(t isa A.MRCMLTarget ? t.spec_record : t.specification),
        predictor_columns=t isa A.MRCMLTarget ? Dict{Symbol,Vector}() : Dict(p.column=>copy(t.table[p.column]) for p in t.terms if p.column!==nothing),
        quality,sampling_warning=!quality.qualified,model_warnings=A.design(t).warnings,
        quadrature_orders=q_orders,quadrature_tolerance,score_tolerance,
        sampling_standard_error=nothing,sampling_uncertainty=:unassessed_crossed_design,
        mcse_method=:chain_aware_smoothed_ratio_delta,smoothing_fit_uncertainty=:not_in_delta_estimate,
        scientific_acceptance=:not_established,automatic_ranking=false,new_fits=0))
end

function _check_explanatory_comparison_report(r)
    hasproperty(r,:schema) && r.schema in _MIXED_COMPARISON_SCHEMAS && return _check_mixed_comparison_report(r)
    r.schema in (_BOUNDED_CRITERIA_SCHEMA,_BOUNDED_COMPARISON_SCHEMA,_COUNT_CRITERIA_SCHEMA,_COUNT_COMPARISON_SCHEMA) && return _check_bounded_scores(r)
    hasproperty(r,:schema) && r.schema in _EXPLANATORY_COMPARISON_SCHEMAS || throw(ArgumentError("unsupported explanatory comparison report"))
    r isa NamedTuple && _prediction_check_seal(r,r.schema)
    _explanatory_absent(r.sampling_standard_error) && string(r.sampling_uncertainty)=="unassessed_crossed_design" || throw(ArgumentError("population uncertainty contract changed"))
    r.automatic_ranking===false && r.multiplier==1 || throw(ArgumentError("comparison scale/ranking contract changed"))
    _explanatory_absent(r.mcse) || (r.mcse isa Real && isfinite(r.mcse) && r.mcse>=0) || throw(ArgumentError("invalid MCSE"))
    if r.schema==_EXPLANATORY_CRITERIA_SCHEMA
        length(r.rows)==length(r.profiles)>0 || throw(ArgumentError("profile roster mismatch"))
        all(p->isfinite(p.log_score) && p.log_score<=1e-8,r.rows) || throw(ArgumentError("invalid log predictive score"))
        isapprox(r.elpd,sum(p.log_score for p in r.rows);atol=1e-9,rtol=1e-12) || throw(ArgumentError("score total mismatch"))
        for (p,s) in zip(r.profiles,r.rows)
            p.profile==s.profile && p.performance==s.performance && collect(p.rows)==collect(s.rows) || throw(ArgumentError("profile identity mismatch"))
            !s.eligible && !_explanatory_absent(s.mcse) && throw(ArgumentError("failed profile has qualified MCSE"))
        end
    else
        length(r.models)==2 || throw(ArgumentError("paired comparison requires two models"))
        foreach(_check_explanatory_comparison_report,r.models)
        _event_comparison_binding(r.models[1])==_event_comparison_binding(r.models[2])==r.observation_binding || throw(ArgumentError("comparison observation mismatch"))
        isapprox(r.difference,r.models[1].elpd-r.models[2].elpd;atol=1e-9,rtol=1e-12) || throw(ArgumentError("comparison difference mismatch"))
    end
    r
end

function _compare_explanatory_profiles(models;criterion=:psis_loo,comparison_axis=nothing,
        independent_model_rng::Bool=false)
    any(p->hasproperty(last(p),:schema) && last(p).schema in (_MIXED_EVENT_CRITERIA_SCHEMA,_MIXED_PROFILE_CRITERIA_SCHEMA),models) && return _compare_mixed_scores(models;criterion,comparison_axis,independent_model_rng)
    any(p->hasproperty(last(p),:schema) && last(p).schema in (_BOUNDED_CRITERIA_SCHEMA,_COUNT_CRITERIA_SCHEMA),models) && return _compare_bounded_scores(models;criterion,comparison_axis,independent_model_rng)
    length(models)==2 && all(p->_explanatory_score_report(last(p)),models) || throw(ArgumentError("supply two criteria reports from explanatory fits"))
    criterion===:psis_loo && comparison_axis in (nothing,:model) || throw(ArgumentError("use criterion=:psis_loo and comparison_axis=:model (or omit the axis)"))
    labels=string.(first.(models));allunique(labels) && all(!isempty,labels) || throw(ArgumentError("distinct nonempty model labels are required"))
    a,b=last.(models);foreach(_check_explanatory_comparison_report,(a,b))
    _event_comparison_binding(a)==_event_comparison_binding(b) || throw(ArgumentError("models must score the same observations/supports, in the same order and conditioning"))
    a.unit==b.unit && a.conditioning==b.conditioning || throw(ArgumentError("models must use the same held-out unit and conditioning"))
    for col in intersect(keys(a.observations),keys(b.observations))
        collect(a.observations[col])==collect(b.observations[col]) || throw(ArgumentError("shared observation column $col differs between models"))
    end
    for col in intersect(keys(a.predictor_columns),keys(b.predictor_columns))
        collect(a.predictor_columns[col])==collect(b.predictor_columns[col]) || throw(ArgumentError("shared predictor $col differs between models"))
    end
    hashes=[a.source_sample_hash,b.source_sample_hash,
        [r.source_sample_hash for r in a.reference_records]...,[r.source_sample_hash for r in b.reference_records]...]
    independent_model_rng && !allunique(hashes) && throw(ArgumentError("shared samples cannot be declared independent"))
    available=independent_model_rng && !_explanatory_absent(a.mcse) && !_explanatory_absent(b.mcse)
    rows=[(;profile=x.profile,performance=x.performance,n_ratings=x.n_ratings,
        primary=x.log_score,baseline=y.log_score,difference=x.log_score-y.log_score,
        mcse=independent_model_rng && !_explanatory_absent(x.mcse) && !_explanatory_absent(y.mcse) ? hypot(x.mcse,y.mcse) : nothing,
        eligible=x.eligible && y.eligible,reference_used=string(x.method)=="direct_refit" || string(y.method)=="direct_refit") for (x,y) in zip(a.rows,b.rows)]
    blocks=[(;block=x.block,mcse=available && !_explanatory_absent(x.mcse) && !_explanatory_absent(y.mcse) ? hypot(x.mcse,y.mcse) : nothing)
        for x in a.mcse_blocks for y in b.mcse_blocks if x.block==y.block]
    _prediction_seal((;schema=_EXPLANATORY_COMPARISON_SCHEMA,names=collect(labels),models=[a,b],
        observation_binding=_event_comparison_binding(a),unit=a.unit,integrate=a.integrate,
        conditioning=a.conditioning,multiplier=1,criterion=:psis_loo,
        difference=a.elpd-b.elpd,mean_difference=(a.elpd-b.elpd)/length(rows),rows,
        direction=:primary_minus_baseline,mcse=available ? hypot(a.mcse,b.mcse) : nothing,
        status=available ? :estimated : :diagnostic_only,mcse_blocks=blocks,independent_model_rng,
        sampling_standard_error=nothing,sampling_uncertainty=:unassessed_crossed_design,
        scientific_acceptance=:not_established,automatic_ranking=false,new_fits=0))
end
