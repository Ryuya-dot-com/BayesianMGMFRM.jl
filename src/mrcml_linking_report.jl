const _WAVE_LINK_SCHEMA = "bayesianmgmfrm.scalar_wave_linking.v1"

# Person IDs belong to their own wave. Only IDs of the requested facet join waves.
function _wave_link_graph(p1, l1, p2, l2)
    a, people1 = AdditiveFacets._labels(p1,:source_person)
    b, people2 = AdditiveFacets._labels(p2,:receiving_person)
    ids = _stable_levels(Iterators.flatten((l1,l2)),:link_level)
    index = Dict(id=>i for (i,id) in enumerate(ids))
    function incidence(people, observations, offset, parent)
        counts = zeros(Int,length(ids))
        for (p,id) in zip(people,observations)
            j = index[id]
            _anchor_link_union!(parent,j,offset+p)
            counts[j] += 1
        end
        counts
    end
    n = length(ids)
    offset = n+length(people1)
    first_graph = collect(1:offset)
    joint = collect(1:offset+length(people2))
    c1 = incidence(a,l1,n,first_graph)
    joint[1:offset] .= first_graph
    second_graph = collect(1:n+length(people2))
    c2 = incidence(b,l2,n,second_graph)
    incidence(b,l2,offset,joint)
    function membership(parent,counts)
        components = Dict{Int,Int}()
        [counts[j]==0 ? missing : get!(components,_anchor_link_root!(parent,j),length(components)+1)
         for j in eachindex(ids)]
    end
    comp1 = membership(first_graph,c1)
    comp2 = membership(second_graph,c2)
    comp = membership(joint,c1+c2)
    rows = [(;level=id, label=AdditiveFacets.label_encoding(id), preliminary_n=c1[j], receiving_n=c2[j],
             preliminary_component=comp1[j],receiving_component=comp2[j],combined_component=comp[j])
            for (j,id) in enumerate(ids)]
    (;rows, preliminary_people=length(people1),receiving_people=length(people2),
      preliminary_observations=length(a),receiving_observations=length(b),
      preliminary_components=length(unique(skipmissing(comp1))),receiving_components=length(unique(skipmissing(comp2))),
      combined_components=length(unique(comp)),shared_levels=count(j->c1[j]>0 && c2[j]>0,eachindex(ids)))
end

function _link_interval(estimate,se,z)
    estimate = isfinite(estimate) ? estimate : missing
    ok = !ismissing(se) && isfinite(se)
    (;estimate,se=ok ? se : missing,posterior_sd=missing,
      lower=ok ? estimate-z*se : missing,upper=ok ? estimate+z*se : missing)
end

function _wave_link_input(f::FrequentistMFRM.Fit, block, interval)
    r = FrequentistMFRM.checked(f)
    s = r.summary
    hasproperty(r,:mrcml_operator) || throw(ArgumentError("use a scalar MRCML equating fit"))
    p = r.problem
    facet = _wave_link_block(p.facets,block)
    z = Distributions.quantile(Distributions.Normal(),(1+interval)/2)
    measures = Dict(row.parameter=>_link_interval(row.estimate,row.se,z) for row in r.facet_measures)
    panel = if hasproperty(s,:population)
        pop = s.population
        compared = filter(!=(pop.design.reference),pop.design.groups)
        contrasts = map(eachindex(compared)) do i
            c = pop.coefficients[i]
            conditional = hasproperty(s,:calibration) ? s.calibration.contrasts[i].conditional_se : c.se
            (;group=compared[i],reference=pop.design.reference,term=c.term,
                conditional=_link_interval(c.estimate,conditional,z),summary=_link_interval(c.estimate,c.se,z))
        end
        (;status=:group_contrasts,summary=missing,contrasts)
    elseif s.method === :jmle
        (;status=:no_population_mean,summary=missing)
    else
        (;status=s.estimate_mean ? :estimated : :fixed,summary=_link_interval(s.population_mean,s.population_mean_se,z))
    end
    conditional_se = get(get(s,:calibration,(;)),:conditional_se,missing)
    (;op=r.mrcml_operator, spec=s, step_owner=p.step_owner, people=p.person_levels[p.person_idx],levels=facet.levels[facet.index],
      measures,panel,conditional_se,warnings=copy(r.warnings),qualified=qualify(f).qualified,method=s.method,source_hash=r.content_hash)
end

function _wave_link_input(f::AdditiveFacets.Fit, block, interval)
    t = AdditiveFacets.checked(f)
    t isa AdditiveFacets.MRCMLTarget || throw(ArgumentError("use a scalar MRCML equating fit"))
    facet = _wave_link_block(t.facets,block)
    names = ["$block[$(repr(id))]" for id in facet.levels]
    intercept = get(t.spec_record,:population_intercept,false)
    intercept && push!(names,"population_mean")
    rows = posterior_summary(f;parameters=names,interval).rows
    probs = AdditiveFacets.interval_bounds(interval)
    mc = posterior_mcse(f;parameters=names,probabilities=probs)
    measures = Dict(r.parameter=>(;estimate=r.mean,se=missing,posterior_sd=r.sd,r.lower,r.upper,
        mean_mcse=m.mean_mcse,lower_mcse=first(m.quantiles).mcse,upper_mcse=last(m.quantiles).mcse,
        mcse_status=m.mcse_status) for (r,m) in zip(rows,mc))
    panel = intercept ? (;status=:estimated,summary=measures["population_mean"]) :
                        (;status=:fixed,summary=(;estimate=0.,se=missing,posterior_sd=missing,lower=missing,upper=missing))
    (;op=t.operator,spec=t.spec_record,step_owner=t.step_owner_spec,people=t.people[t.person],levels=facet.levels[facet.index],
      measures,panel,conditional_se=missing,warnings=AdditiveFacets.design(t).warnings,qualified=qualify(f).qualified,method=:bayesian,source_hash=f.record.content_hash)
end

function _wave_link_block(facets,block)
    i = findfirst(f->f.name===block,facets)
    isnothing(i) && throw(ArgumentError("unknown receiving facet $block"))
    facets[i]
end

_link_label(x) = x isa Tuple ? map(AdditiveFacets.label_encoding,x) : AdditiveFacets.label_encoding(x)

"""
    anchor_linking_summary(first_wave, receiving_fit; block, reference, person=:person, level=block, interval=.95)

Report a scalar two-wave link for a fitted structured facet. Supply one row per
observed first-wave rating, the first-wave person and facet columns, and a
dictionary of preliminary main-effect locations on the same unit and sign
convention. Receiving rows, constraints, estimates and qualification come from
the fit. Person identities are wave-specific. The graph joins matching observed
facet IDs and describes overlap even for levels whose locations can change.

An estimated displacement is the receiving location minus the supplied first-wave
point. Its Wald or equal-tailed posterior interval treats that point as fixed.
Hard equalities, implied fixed members, and updates of shared Gaussian calibration
parameters have no separately estimated displacement. Remaining degrees of freedom
are conditional on external coordinates; those coordinates are counted separately.
For grouped MMLE, `panel.contrasts` contains each group versus its reference at
equal covariates. Each row has a `conditional` Wald interval and a `summary`
interval including any independent two-stage calibration variance. Both use
the requested interval level. Interpret them with `qualified` and the linking
assumptions.
"""
function anchor_linking_summary(first_wave, f::Union{FrequentistMFRM.Fit,AdditiveFacets.Fit};
        block::Symbol,reference::AbstractDict,person::Symbol=:person,level::Symbol=block,interval=.95)
    AdditiveFacets.interval_bounds(interval)
    p1 = _column(first_wave,person)
    l1 = _column(first_wave,level)
    length(p1)==length(l1) && !isempty(l1) && all(AdditiveFacets._valid_facet_label,l1) ||
        throw(ArgumentError("first-wave rows require aligned, observed person and facet IDs"))
    all(p->AdditiveFacets._valid_facet_label(first(p)) && last(p) isa Real &&
           !(last(p) isa Bool) && isfinite(Float64(last(p))), pairs(reference)) ||
        throw(ArgumentError("reference must map facet IDs to finite first-wave logit locations"))
    input = _wave_link_input(f,block,interval)
    s, op = input.spec,input.op
    fixed = get(s,:fixed_calibration,(;))
    cal = get(s,:calibration,(;))
    !isempty(fixed) || !isempty(cal) || throw(ArgumentError("receiving model requires a named linking calibration"))
    any(b->b.kind===:facet_main && b.name===block,op.block_meta) ||
        throw(ArgumentError("a structured main-effect block is required"))
    anchors = get(fixed,:anchors,())
    groups = get(fixed,:groups,())
    coords = get(cal,:coordinates,())
    hard = Dict(r.level=>r.value for r in anchors if r.kind===:hard && r.block===block)
    soft = Dict(r.level=>r.estimate for r in coords if r.block===block)
    members = Set(id for g in groups if g.block===block for id in g.levels)
    graph = _wave_link_graph(p1,l1,input.people,input.levels)
    shared = NamedTuple[]
    for row in graph.rows
        row.preliminary_n>0 && row.receiving_n>0 || continue
        id = row.level
        nm = "$block[$(repr(id))]"
        value = input.measures[nm]
        baseline = get(reference,id,missing)
        role = haskey(soft,id) ? :shared_calibration : haskey(hard,id) ? :hard_anchor :
            nm in op.fixed_model_names ? :implied_fixed : id in members ? :group_member : :free
        estimated = role in (:group_member,:free) && !ismissing(baseline)
        shift = if estimated
            merge(value,(;estimate=value.estimate-baseline,lower=value.lower-baseline,upper=value.upper-baseline))
        else
            missing
        end
        push!(shared,(;row...,role,preliminary=baseline,transferred=get(soft,id,get(hard,id,missing)),
                      receiving=value,displacement=shift))
    end
    dimensions = map(filter(b->b.kind in (:facet_main,:steps),op.block_meta)) do b
        steps = b.kind===:steps
        external = count(r->steps ? r.block===:steps && isequal(r.level,b.group_level) : r.block===b.name,coords)
        n = length(b.model_range)
        free = length(b.eta_range)
        (;block=steps ? :steps : b.name,owner_level=steps ? _link_label(b.group_level) : missing,
          locations=n,conditional_free_df=free,conditional_constraint_rank=n-free,transferred_df=external,
          centered_step_df=steps ? n-1 : missing,additional_step_constraints=steps ? n-1-free : missing)
    end
    group_rows = map(collect(groups)) do g
        compare = g.block===block && all(id->haskey(reference,id),g.levels)
        total = compare ? sum(id->Float64(reference[id]),g.levels) : missing
        baseline = g.statistic===:mean ? total/length(g.levels) : total
        bm = only(b for b in op.block_meta if b.kind===:facet_main && b.name===g.block)
        indices = findall(in(Set(g.levels)), bm.levels)
        member_df = rank(Matrix(op.J_model[bm.model_range[indices],bm.eta_range]))
        (;g...,member_free_df=member_df,level_labels=_link_label.(g.levels),preliminary_statistic=baseline,imposed_change=g.value-baseline)
    end
    mode = !isempty(cal) ? :uncertain_calibration : !isempty(groups) ? :group_constraint : :fixed_calibration
    (;schema=_WAVE_LINK_SCHEMA,block,mode,method=input.method,qualified=input.qualified,warnings=input.warnings,interval=Float64(interval),
      interval_kind=input.method===:bayesian ? :equal_tailed_posterior : :observed_information_wald,
      receiving_fit_hash=input.source_hash,preliminary_input_hash=_cache_hash((;person_ids=p1,facet_ids=l1,reference)),
      connectivity=graph,step_owner=input.step_owner,dimensions,groups=group_rows,
      (haskey(fixed,:interaction_dimensions) ? (;interaction_dimensions=deepcopy(fixed.interaction_dimensions)) : (;))...,
      anchors=[(;r...,label=_link_label(r.level)) for r in anchors],
      transferred_coordinates=[(;r...,label=_link_label(r.level)) for r in coords],
      panel=input.panel,panel_conditional_se=input.conditional_se,common_parameters=shared,
      displacement_uncertainty=:conditional_on_preliminary_point,
      common_reference_shift=:confounded_with_panel_location,
      connectivity_scope=:observed_person_by_facet_incidence)
end
