# Common-plan expected scores, conditional on known facet levels.
const FAIR_REFERENCE_SCHEMA = "bayesianmgmfrm.fair_reference.v1"
const FAIR_REFERENCE_BASIS_SCHEMA = "bayesianmgmfrm.fair_reference_basis.v1"
const FAIR_REFERENCE_INTERACTION_BASIS_SCHEMA = "bayesianmgmfrm.fair_reference_basis.v2"
const FAIR_REFERENCE_BLOCKS = (:facet_main, :steps, :population_mean,
    :facet_facet_interaction, :focal_dff_interaction, :facet_step_interaction)

function _fair_reference_interactions(op)
    terms = NamedTuple[]
    for b in op.block_meta
        if b.kind === :facet_step_interaction
            push!(terms,(;kind=:steps,roles=[b.f1],levels=[deepcopy(b.levels1)],
                n_steps=b.n_steps,parameters=op.model_names[b.model_range]))
        elseif b.kind in (:facet_facet_interaction,:focal_dff_interaction)
            pars = if b.kind === :focal_dff_interaction
                map([(a,g) for a in b.levels1 for g in b.levels2]) do (a,g)
                    i=findfirst(x->isequal(x,a),b.focal_levels);j=findfirst(x->isequal(x,g),b.compare_groups)
                    i===nothing || j===nothing ? nothing : op.model_names[b.model_range[(i-1)*length(b.compare_groups)+j]]
                end
            else
                op.model_names[b.model_range]
            end
            push!(terms,(;kind=:location,roles=[b.f1,b.f2],levels=deepcopy([b.levels1,b.levels2]),parameters=pars))
        end
    end
    terms
end

function _fair_reference_contexts(t,terms,facets)
    roles=unique([r for term in terms for r in term.roles if !(r in getproperty.(facets,:name))])
    map(roles) do role
        candidates=filter(c->c.name===role,t.spec_record.context_facets)
        length(candidates)==1 || throw(ArgumentError("reference interaction role $role has no reporting context"))
        c=only(candidates)
        values=map(eachindex(t.people)) do p
            ix=c.index[findall(==(p),t.person)]
            allequal(ix) || throw(ArgumentError("reference context $role must be constant within each person"))
            deepcopy(c.levels[first(ix)])
        end
        (;name=role,values)
    end
end

function _fair_reference_condition(b,plan,mode)
    terms=get(b,:interactions,NamedTuple[])
    if isempty(terms)
        mode===nothing || throw(ArgumentError("this model has no reference interactions"))
        return merge(plan,(;adjustments=nothing))
    end
    mode in (:fitted,:zero) || throw(ArgumentError("choose interaction_effects=:fitted or :zero"))
    mode===:zero && return merge(plan,(;adjustments=nothing))
    adjustments=map(eachindex(b.people)) do p
        map(eachindex(plan.weights)) do j
            location=String[];steps=[String[] for _ in 1:length(plan.categories)-1]
            for term in terms
                ix=map(eachindex(term.roles)) do k
                    role=term.roles[k];f=findfirst(x->x.name===role,b.facets)
                    value=if f===nothing
                        c=only(filter(x->x.name===role,get(b,:contexts,NamedTuple[])))
                        c.values[p]
                    else
                        b.facets[f].levels[plan.indices[f][j]]
                    end
                    i=findfirst(x->isequal(x,value),term.levels[k])
                    i===nothing && throw(ArgumentError("unknown reference interaction level for $role"))
                    i
                end
                if term.kind===:location
                    n=term.parameters[(ix[1]-1)*length(term.levels[2])+ix[2]]
                    n===nothing || push!(location,n)
                else
                    term.n_steps==length(steps) || throw(ArgumentError("reference interaction steps do not match category support"))
                    for h in eachindex(steps);push!(steps[h],term.parameters[(ix[1]-1)*term.n_steps+h]);end
                end
            end
            (;location,steps)
        end
    end
    merge(plan,(;adjustments))
end

function _fair_reference_context_report(b)
    [(;name=c.name,rows=[(;person_id=label_encoding(b.people[p].level),value=deepcopy(c.values[p]),
        value_id=label_encoding(c.values[p])) for p in eachindex(b.people)]) for c in get(b,:contexts,NamedTuple[])]
end

function _fair_reference_interaction_warnings(b,mode)
    mode===nothing && return String[]
    [mode===:fitted ? "Fitted interactions are retained in expected scores." :
        "Interactions are set to zero only for reporting; ability estimates still come from the fitted interaction model. This is not a refit without interactions or a causal bias correction.";
        isempty(get(b,:contexts,NamedTuple[])) ? String[] : ["Each person's observed group/context is held fixed; the common reference plan does not standardize group membership."]]
end

function fair_reference_basis(t::AbstractTarget)
    t isa MRCMLTarget || throw(ArgumentError("common-plan Fair Average requires a structured Bayesian MRCML fit"))
    op = t.operator
    get(t.spec_record, :source, nothing) === :structured_mfrm_spec &&
        all(b -> b.kind in FAIR_REFERENCE_BLOCKS, op.block_meta) ||
        throw(ArgumentError("common-plan Fair Average requires structured facets, steps and supported interactions; LLTM/custom designs require their own reference conditioning"))
    random = filter(b -> get(b,:iid_population,false),op.block_meta)
    t.owner in getproperty.(random,:name) && throw(ArgumentError("shared effects cannot own reference thresholds"))
    (t.owner === :global || t.step_owner_spec isa Symbol && t.owner in [b.name for b in t.facets]) ||
        throw(ArgumentError("common-plan Fair Average requires global or single-facet-owned steps"))
    facets = [(; name=b.name, levels=deepcopy(b.levels),
        parameters=op.model_names[only(filter(m -> m.kind === :facet_main && m.name === b.name, op.block_meta)).model_range]) for b in t.facets if !(b.name in getproperty.(random,:name))]
    step_blocks = filter(b -> b.kind === :steps, op.block_meta)
    steps = [(; level=deepcopy(t.group_levels[g]), categories=copy(t.categories[t.supports[g]]),
        parameters=op.model_names[step_blocks[g].model_range]) for g in eachindex(step_blocks)]
    intercepts = filter(b -> b.kind === :population_mean, op.block_meta)
    pnames = names(t,:model)
    observed_rows = [Int[] for _ in t.people]
    for (n,p) in enumerate(t.person); push!(observed_rows[p],n); end
    people = map(eachindex(t.people)) do j
        ix = observed_rows[j]
        same = allequal(t.supports[t.group[n]] for n in ix)
        (; level=deepcopy(t.people[j]),parameter=pnames[j],n_observations=length(ix),
            observed_average=same ? mean(t.categories[t.category[n]] for n in ix) : missing,
            observed_categories=same ? copy(t.categories[t.supports[t.group[first(ix)]]]) : nothing)
    end
    interactions=_fair_reference_interactions(op)
    contexts=_fair_reference_contexts(t,interactions,facets)
    (; schema=isempty(interactions) ? FAIR_REFERENCE_BASIS_SCHEMA : FAIR_REFERENCE_INTERACTION_BASIS_SCHEMA,
        kernel=:additive, facets, steps, owner=t.owner, people,interactions,contexts,
        shared=[let pb=only(filter(x->x.name===b.name,t.prior_blocks))
            (;name=b.name,sd_parameter=pb.hyper_idx>0 ? "residual_sd[$(b.name)]" : nothing,sd=pb.marginal_sd)
        end for b in random],
        intercept=isempty(intercepts) ? nothing : only(op.model_names[only(intercepts).model_range]))
end

function _fair_reference_plan(basis, table)
    roles = Symbol[b.name for b in basis.facets]
    isempty(roles) && throw(ArgumentError("a common reference plan requires at least one non-shared facet"))
    :Weight in roles && throw(ArgumentError("reference plans reserve the column name Weight"))
    cols = if table isa AbstractDict
        cs = Symbol[Symbol(k) for k in Base.keys(table)]
        allunique(cs) || throw(ArgumentError("reference_plan contains duplicate column names after Symbol normalization"))
        cs
    elseif table isa AbstractVector && !isempty(table) && first(table) isa NamedTuple
        all(r -> r isa NamedTuple && Base.keys(r) == Base.keys(first(table)), table) ||
            throw(ArgumentError("reference_plan rows must share the same column names"))
        collect(Symbol, Base.keys(first(table)))
    elseif table isa AbstractVector && !isempty(table) && first(table) isa AbstractDict
        row_syms(r) = begin
            cs = Symbol[Symbol(k) for k in Base.keys(r)]
            allunique(cs) || throw(ArgumentError("reference_plan contains duplicate column names after Symbol normalization"))
            Set(cs)
        end
        k0 = row_syms(first(table))
        all(r -> r isa AbstractDict && row_syms(r) == k0, table) ||
            throw(ArgumentError("reference_plan rows must share the same column names"))
        collect(Symbol, k0)
    else
        Symbol.(propertynames(table))
    end
    Set(cols) in (Set(roles), Set([roles; :Weight])) ||
        throw(ArgumentError("reference_plan must contain every facet role and optional Weight only: $roles"))
    values = [B._column(table, role) for role in roles]
    J = length(first(values))
    J > 0 && all(v -> length(v) == J, values) || throw(ArgumentError("reference_plan must have nonempty equal-length columns"))
    indices = [map(v) do x
        i = findfirst(y -> isequal(x,y), b.levels)
        i === nothing && throw(ArgumentError("unknown reference level $(repr(x)) for $(b.name)"))
        i
    end for (v,b) in zip(values,basis.facets)]
    keys = [Tuple(ix[j] for ix in indices) for j in 1:J]
    allunique(keys) || throw(ArgumentError("duplicate reference cells: combine their weights"))
    w0 = :Weight in cols ? B._column(table, :Weight) : ones(J)
    length(w0) == J && all(w -> w isa Real && !(w isa Bool) && isfinite(w) && w > 0, w0) ||
        throw(ArgumentError("reference weights must be finite and positive"))
    w = Float64.(w0)
    all(isfinite,w) && minimum(w)>0 || throw(ArgumentError("reference weights must be representable as positive Float64 values"))
    w ./= maximum(w); w ./= sum(w)
    minimum(w)>0 || throw(ArgumentError("reference weight ratios are too extreme"))
    owner = findfirst(==(Symbol(basis.owner)), roles)
    groups = owner === nothing ? ones(Int,J) : [only(findall(s -> isequal(s.level, values[owner][j]), basis.steps)) for j in 1:J]
    cats = basis.steps[first(groups)].categories
    all(g -> basis.steps[g].categories == cats, groups) || throw(ArgumentError(
        "reference cells must share a category score scale; choose a common-support subset"))
    plan = [(; (roles[k] => deepcopy(values[k][j]) for k in eachindex(roles))..., Weight=Float64(w0[j]), NormalizedWeight=w[j]) for j in 1:J]
    (; rows=plan, indices, groups, weights=w, categories=copy(cats))
end

function _fair_reference_values(basis, plan, model_values, parameter_names;
        shared_effects=nothing, interaction_effects=nothing, quadrature=nothing)
    plan=_fair_reference_condition(basis,plan,interaction_effects)
    col = Dict(n => j for (j,n) in enumerate(parameter_names))
    generalized = get(basis,:kernel,:additive) === :mgmfrm
    shared = get(basis,:shared,NamedTuple[])
    isempty(shared) ? (shared_effects === nothing || throw(ArgumentError("this model has no shared effects"))) :
        (shared_effects in (:zero,:marginal_new) || throw(ArgumentError("choose shared_effects=:zero or :marginal_new")))
    required = [reduce(vcat,(generalized ? b.parameters : [b.parameter] for b in basis.people)); reduce(vcat,(b.parameters for b in basis.facets));
        reduce(vcat,(s.parameters for s in basis.steps)); basis.intercept === nothing ? String[] : [basis.intercept]]
    generalized && append!(required,[basis.consistency;reduce(vcat,basis.loadings);
        get(basis,:softmin_kappa,nothing)===nothing ? String[] : [basis.softmin_kappa]])
    shared_effects === :marginal_new && append!(required,filter(!isnothing,getproperty.(shared,:sd_parameter)))
    interaction_effects===:fitted && append!(required,[n for term in basis.interactions for n in term.parameters if n!==nothing])
    all(haskey(col,n) for n in required) || throw(ArgumentError("common-plan scores require all person, facet and step draws"))
    S = size(model_values,1)
    all(isfinite,model_values) || throw(ArgumentError("nonfinite posterior coordinates"))
    scores = zeros(promote_type(eltype(model_values),Float64),S,length(basis.people))
    nodes,weights = shared_effects === :marginal_new ? (quadrature.nodes,quadrature.weights) : ([0.],[1.])
    for s in 1:S, j in eachindex(plan.weights)
        shift = basis.intercept === nothing ? 0.0 : model_values[s,col[basis.intercept]]
        for (k,b) in enumerate(basis.facets)
            shift -= model_values[s,col[b.parameters[plan.indices[k][j]]]]
        end
        tau = [model_values[s,col[n]] for n in basis.steps[plan.groups[j]].parameters]
        sigma = shared_effects === :marginal_new ? sqrt(sum((b.sd_parameter===nothing ? b.sd : model_values[s,col[b.sd_parameter]])^2 for b in shared)) : 0.
        for (p,b) in enumerate(basis.people)
            adjustment=plan.adjustments===nothing ? nothing : plan.adjustments[p][j]
            person_shift=shift-(adjustment===nothing ? 0. : sum((model_values[s,col[n]] for n in adjustment.location);init=0.))
            person_tau=adjustment===nothing ? tau : [tau[h]+sum((model_values[s,col[n]] for n in adjustment.steps[h]);init=0.) for h in eachindex(tau)]
            alpha = 1.
            eta = if generalized
                i,r = plan.indices[1][j],plan.indices[2][j]
                a = [model_values[s,col[n]] for n in basis.loadings[i]]
                theta = [model_values[s,col[b.parameters[d]]] for d in basis.active_dims[i]]
                c_r = model_values[s,col[basis.consistency[r]]]
                if basis.item_slope_scope === :entire_linear_predictor
                    alpha = basis.logit_scale * c_r * only(a)
                    only(theta)+person_shift
                else
                    m_act = length(a)
                    u_pi = if m_act == 1
                        a[1] * theta[1]
                    elseif Symbol(get(basis, :aggregation, :additive)) === :softmin
                        kap = model_values[s, col[basis.softmin_kappa]]
                        xs = -kap .* (a .* theta)
                        mx = maximum(xs)
                        -(mx + log(sum(exp.(xs .- mx))) - log(Float64(m_act))) / kap
                    else
                        acc = dot(a, theta)
                        get(basis, :cross_loading_average, false) === true ? (acc / Float64(m_act)) : acc
                    end
                    if Symbol(get(basis, :rater_slope_scope, :entire_linear_predictor)) === :ability_only
                        alpha = basis.logit_scale
                        c_r * u_pi + person_shift
                    else
                        alpha = basis.logit_scale * c_r
                        u_pi + person_shift
                    end
                end
            else
                model_values[s,col[b.parameter]] + person_shift
            end
            scores[s,p] += plan.weights[j] * sum(weights[q] * _adjacent_expected_score(alpha*(eta+sigma*nodes[q]),alpha.*person_tau,plan.categories) for q in eachindex(nodes))
        end
    end
    scores
end

fair_reference_draws(t, raw) = model_draws(t,raw)
fair_reference_warnings(t) = design(t).warnings

function _fair_reference_evaluate(basis,plan,values,names;shared_effects=nothing,interaction_effects=nothing,
        quadrature_orders=(61,121),quadrature_tolerance=1e-7)
    if shared_effects !== :marginal_new
        return (;values=_fair_reference_values(basis,plan,values,names;shared_effects,interaction_effects),integration=nothing)
    end
    length(quadrature_orders)==2 && all(n->n isa Integer && n>=3,quadrature_orders) && quadrature_orders[1]<quadrature_orders[2] ||
        throw(ArgumentError("quadrature_orders must contain two increasing integers >= 3"))
    isfinite(quadrature_tolerance) && quadrature_tolerance>0 || throw(ArgumentError("quadrature_tolerance must be positive"))
    results=[_fair_reference_values(basis,plan,values,names;shared_effects,interaction_effects,
        quadrature=B.FrequentistMFRM.gauss_hermite_normal(n)) for n in quadrature_orders]
    err=maximum(abs.(results[2]-results[1]))
    err<=quadrature_tolerance || throw(ArgumentError("shared-effect quadrature difference $err exceeds $quadrature_tolerance; increase quadrature_orders"))
    (;values=results[2],integration=(;orders=collect(quadrature_orders),tolerance=quadrature_tolerance,max_score_difference=err))
end

function _fair_reference_summary(v; chains, interval, threshold=nothing, strict=false)
    c = B.posterior_contrast(v,zeros(length(v)); chains,interval)
    event = if threshold === nothing
        nothing
    else
        threshold isa Real && !(threshold isa Bool) && isfinite(threshold) || throw(ArgumentError("threshold/margin must be finite"))
        indicator = strict ? v .> threshold : v .>= threshold
        m = only(B._posterior_mcse_rows(reshape(Float64.(indicator),:,1),["event"],chains;
            probabilities=(),parameter_space=:indicator))
        (; threshold=Float64(threshold), operator=strict ? :greater : :greater_equal,
            count=count(indicator), probability=mean(indicator), mcse=m.mean_mcse,
            status=ismissing(m.mean_mcse) ? m.mcse_status : :available)
    end
    (; mean=c.mean,median=c.median,sd=c.sd,lower=c.lower,upper=c.upper,
        mcse_mean=c.precision.mean_mcse,mcse_lower=c.precision.quantiles[1].mcse,
        mcse_upper=c.precision.quantiles[end].mcse,mcse_status=c.precision.mcse_status,
        rhat=c.contrast_diagnostics.rank_normalized_rhat,ess_bulk=c.contrast_diagnostics.bulk_ess,
        ess_tail=c.contrast_diagnostics.tail_ess,event)
end

function _mrcml_fair_reference(t, f; reference_plan=nothing, level=.95, threshold=nothing, comparisons=nothing,
        shared_effects=nothing,interaction_effects=nothing,quadrature_orders=(61,121),quadrature_tolerance=1e-7)
    reference_plan === nothing && throw(ArgumentError(
        "common-plan Fair Average on $(typeof(f)) requires an explicit `reference_plan` (for example, `reference_plan = [(item = ..., rater = ...)]`) because expected scores depend on the reference facet profile."))
    interval_bounds(level)
    basis = fair_reference_basis(t)
    plan = _fair_reference_plan(basis,reference_plan)
    m = fair_reference_draws(t,f.record.run.draws)
    evaluated = _fair_reference_evaluate(basis,plan,vcat(m.values,mean(m.values;dims=1)),m.names;
        shared_effects,interaction_effects,quadrature_orders,quadrature_tolerance)
    values = evaluated.values[1:end-1,:]
    plugin = vec(evaluated.values[end,:])
    chains = f.record.run.controls.chains
    rows = map(eachindex(basis.people)) do p
        b = basis.people[p]
        observed = b.observed_categories == plan.categories ? b.observed_average : missing
        summary = _fair_reference_summary(view(values,:,p);chains,interval=level,threshold)
        label = count(x->string(x.level)==string(b.level),basis.people)>1 ? repr(b.level) : string(b.level)
        (; person=b.level,person_id=label_encoding(b.level),person_label=label,
            n_observations=b.n_observations,observed_average=observed,
            adjustment_mean=ismissing(observed) ? missing : summary.mean-observed,
            plugin_mean=plugin[p],summary...)
    end
    contrasts = comparisons === nothing ? NamedTuple[] : map(collect(comparisons)) do c
        Set(propertynames(c)) == Set((:left,:right,:margin)) || throw(ArgumentError("each comparison needs left, right and margin"))
        ids = [findfirst(b -> isequal(b.level,x),basis.people) for x in (c.left,c.right)]
        all(!isnothing,ids) && ids[1] != ids[2] || throw(ArgumentError("comparisons require two distinct known person IDs"))
        (; left=c.left,right=c.right,left_id=label_encoding(c.left),right_id=label_encoding(c.right),margin=c.margin,
            _fair_reference_summary(values[:,ids[1]]-values[:,ids[2]];chains,interval=level,threshold=c.margin,strict=true)...)
    end
    warnings = [fair_reference_warnings(t);_fair_reference_interaction_warnings(basis,interaction_effects);
        "Intervals describe common-plan expected scores, not future realized ratings. Whole-fit warnings remain applicable.";
        "Reference weights standardize the reporting plan; they are not likelihood or survey weights."]
    rep = (;schema=FAIR_REFERENCE_SCHEMA,kind=:fair_average,target=:common_plan_expected_average,
        conditioning=shared_effects===nothing ? :known_facet_levels : shared_effects,
        interaction_effects,held_contexts=_fair_reference_context_report(basis),
        integration=evaluated.integration,by=:person,interval=Float64(level),reference_plan=plan.rows,
        reference_ids=[(; (b.name=>label_encoding(b.levels[plan.indices[k][j]]) for (k,b) in enumerate(basis.facets))...) for j in eachindex(plan.rows)],
        category_levels=plan.categories,rows,contrasts,n_draws=size(values,1),chains,
        draws_per_chain=size(values,1)÷chains,qualification=B.qualify(f),warnings,
        source_sample_content_hash=f.record.content_hash,target_identity=f.record.target_identity,
        diagnostic_thresholds=(;rhat=1.01,ess=400),
        interval_target=:posterior_expected_score)
    check_fair_reference_report(rep)
end

function check_fair_reference_report(r)
    target=string(r.interval_target)
    r.schema == FAIR_REFERENCE_SCHEMA && string(r.target)=="common_plan_expected_average" &&
        target in ("posterior_expected_score","wald_expected_score","conditional_posterior_expected_score") || throw(ArgumentError("invalid Fair Average target"))
    interval_bounds(r.interval)
    if target=="posterior_expected_score"
        r.chains>0 && r.draws_per_chain>0 && r.n_draws==r.chains*r.draws_per_chain || throw(ArgumentError("invalid draw counts"))
    else
        r.n_draws==0 || throw(ArgumentError("frequentist reports cannot claim MCMC draws"))
    end
    !isempty(r.reference_plan) && all(p -> isfinite(p.NormalizedWeight) && p.NormalizedWeight>0,r.reference_plan) &&
        isapprox(sum(p.NormalizedWeight for p in r.reference_plan),1;atol=1e-12,rtol=0) || throw(ArgumentError("invalid reference weights"))
    !isempty(r.rows) && allunique([(string(p.person_id.kind),p.person_id.value) for p in r.rows]) || throw(ArgumentError("invalid person rows"))
    length(r.reference_ids)==length(r.reference_plan) || throw(ArgumentError("missing reference ID records"))
    lo,hi=extrema(r.category_levels)
    for (rows,a,b) in ((r.rows,lo,hi),(r.contrasts,lo-hi,hi-lo)), v in rows
        a-1e-10<=v.mean<=b+1e-10 || throw(ArgumentError("invalid score estimate"))
        if target=="wald_expected_score"
            (v.lower===nothing || ismissing(v.lower)) ?
                (v.upper===nothing || ismissing(v.upper) || throw(ArgumentError("invalid missing interval"))) :
                (v.lower<=v.mean<=v.upper || throw(ArgumentError("invalid Wald interval")))
            v.event===nothing || throw(ArgumentError("Wald intervals do not define posterior events"))
        else
            a-1e-10<=v.lower<=v.median<=v.upper<=b+1e-10 || throw(ArgumentError("invalid score intervals"))
        end
        if v.event !== nothing
            0<=v.event.probability<=1+1e-12 || throw(ArgumentError("invalid posterior event"))
            target!="posterior_expected_score" || (0<=v.event.count<=r.n_draws && isapprox(v.event.probability,v.event.count/r.n_draws;atol=1e-12,rtol=0)) ||
                throw(ArgumentError("invalid posterior event"))
        end
    end
    r
end
