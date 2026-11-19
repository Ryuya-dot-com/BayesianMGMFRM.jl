# Outcome patterns are descriptive evidence, separate from structural rank.
function response_patterns(t)
    usage=NamedTuple[];constant=NamedTuple[];issues=NamedTuple[]
    groups=[Int[] for _ in t.group_levels]
    for n in eachindex(t.group);push!(groups[t.group[n]],n);end
    function issue(code,facet,level,step_level,categories,n,message)
        push!(issues,(;code,severity=:warning,facet,level=deepcopy(level),
            step_owner=t.owner,step_level=deepcopy(step_level),categories=copy(categories),
            n_observations=n,message))
    end
    owners=[(:person,t.people,t.person);[(b.name,b.levels,b.index) for b in t.facets]]
    for (g,ix) in enumerate(groups)
        support=t.supports[g];labels=t.categories[support];level=t.group_levels[g]
        counts=zeros(Int,length(support))
        for n in ix;counts[t.category[n]-first(support)+1]+=1;end
        absent=findall(==(0),counts)
        interior=[labels[j] for j in absent if 1<j<length(labels)]
        endpoints=[labels[j] for j in absent if j==1 || j==length(labels)]
        push!(usage,(;step_owner=t.owner,level=deepcopy(level),categories=copy(labels),counts,
            n_observations=length(ix),unused_interior=interior,unused_endpoints=endpoints))
        isempty(ix) && continue # Missing owner levels already fail the design screen.
        group_constant=length(ix)>=2 && count(>(0),counts)==1
        context="steps :$(t.owner)=$(repr(level)) ($(length(ix)) ratings)"
        for (code,cats) in ((:unused_interior_category,interior),(:unobserved_declared_endpoint,endpoints))
            isempty(cats) || issue(code,t.owner,level,level,cats,length(ix),
                "[$code] $context: declared categories $cats are unused. Support is retained; inspect threshold prior sensitivity and category-count PPC.")
        end
        # With global steps, also report an entirely constant dataset.
        these=t.owner===:global ? [owners;[(:global,Any[:global],ones(Int,length(t.person)))]] : owners
        for (name,levels,index) in these
            buckets=Dict{Int,Vector{Int}}()
            for n in ix;push!(get!(Vector{Int},buckets,index[n]),t.category[n]);end
            for j in sort!(collect(keys(buckets)))
                ys=buckets[j]
                length(ys)>=2 && all(==(first(ys)),ys) || continue
                score=t.categories[first(ys)]
                position=score==first(labels) ? :minimum : score==last(labels) ? :maximum : :interior
                push!(constant,(;facet=name,level=deepcopy(levels[j]),step_owner=t.owner,
                    step_level=deepcopy(level),n_observations=length(ys),score,position))
                # One whole-group warning already covers its constant subgroups.
                group_constant && name!==t.owner && continue
                issue(:constant_score_pattern,name,levels[j],level,[score],length(ys),
                    "[constant_score_pattern] facet :$name=$(repr(levels[j])) within steps :$(t.owner)=$(repr(level)): all $(length(ys)) ratings are $score ($position). Inspect assignment, prior sensitivity and replicated variation; this is not an exclusion or quality verdict.")
            end
        end
    end
    (;schema="bayesianmgmfrm.additive_response_patterns.v1",category_usage=usage,
      constant_patterns=constant,issues,warnings=[r.message for r in issues],
      minimum_constant_observations=2,conditioning=:within_steps_owner,
      scientific_acceptance=false)
end
function warn_patterns(t)
    audit=response_patterns(t)
    isempty(audit.issues) || @warn "Observed rating patterns need review; see validate_design(spec).response_patterns for individual IDs and counts. Data and categories are retained." warnings=audit.warnings
    nothing
end

# Rendering options do not modify computed posterior summaries or qualification.
function interval_style(rows;reference=nothing,interval_colors=nothing)
    if reference===nothing
        interval_colors===nothing || throw(ArgumentError("interval_colors requires an explicit reference"))
        return nothing
    end
    reference isa Real && !(reference isa Bool) && isfinite(reference) ||
        throw(ArgumentError("reference must be a finite real value in the selected parameter units"))
    reference=Float64(reference)
    isfinite(reference) || throw(ArgumentError("reference must be representable as a finite Float64 plot coordinate"))
    palette=interval_colors===nothing ? (contains=:gray55,excludes=:steelblue4) : interval_colors
    palette isa NamedTuple && Set(keys(palette))==Set((:contains,:excludes)) ||
        throw(ArgumentError("interval_colors must be (contains=..., excludes=...)"))
    states=Symbol[]
    for r in rows
        all(x->x isa Real && !(x isa Bool) && isfinite(x),(r.lower,r.upper)) && r.lower<=r.upper ||
            throw(ArgumentError("reference coloring requires finite ordered interval bounds"))
        push!(states,r.structurally_fixed ? :fixed : r.lower<=reference<=r.upper ? :contains : :excludes)
    end
    (;reference,palette,states,
      colors=[s===:fixed ? :gray30 : getproperty(palette,s) for s in states],
      markers=[s===:fixed ? :diamond : s===:contains ? :circle : :rect for s in states])
end
