function fit_generalizability(person_name,person,facet_names,facet_columns,facet_values,score_names,score_values,child,parent,method,plans,nplans,weights,interval)
    G=BayesianMGMFRM.Generalizability
    strings(x)=x===nothing ? String[] : x isa AbstractString ? [String(x)] : collect(String,x)
    facet_names=strings(facet_names);facet_columns=strings(facet_columns);score_names=strings(score_names)
    child=strings(child);parent=strings(parent);plans=_as_int_vec(plans)
    weights=weights isa Number ? [Float64(weights)] : Float64.(weights)
    n=length(person);C=length(score_names);F=length(facet_names)
    names=Symbol.(facet_names);scores=Symbol.(score_names)
    # Preserve user IDs; wire columns are positional and never substituted for labels.
    columns=Pair{Symbol,Any}[Symbol(person_name)=>collect(person)]
    for j in 1:F;push!(columns,Symbol(facet_columns[j])=>collect(facet_values[(j-1)*n+1:j*n]));end
    for j in 1:C;push!(columns,scores[j]=>Float64.(score_values[(j-1)*n+1:j*n]));end
    table=Dict(columns)
    facets=(; (names[j]=>Symbol(facet_columns[j]) for j in 1:F)...)
    nesting=isempty(child) ? (;) : (;Symbol(only(child))=>Symbol(only(parent)))
    target=G.model(table;scores,person=Symbol(person_name),facets,nesting,prior=:none)
    fit=BayesianMGMFRM.fit(target;method=Symbol(method))
    ds=NamedTuple[]
    plan_matrix=reshape(Int.(plans),Int(nplans),F)
    for p in eachrow(plan_matrix)
        counts=(; (names[j]=>p[j] for j in 1:F)...)
        d=BayesianMGMFRM.reliability(fit;counts,weights,interval)
        count_fields=(; (Symbol("count_",names[j])=>p[j] for j in 1:F)...)
        for row in d.rows,metric in (:G,:Phi,:relative_sem,:absolute_sem)
            push!(ds,merge((;score=row.score,metric=String(metric)),count_fields,getproperty(row,metric)))
        end
    end
    cs=G.component_summary(fit;interval)
    BayesianMGMFRM.JSON3.write((;report=G.report(fit).record,components=cs.rows,dstudy=ds,
        component_vcov=cs.sampling_covariance===nothing ? nothing : vec(cs.sampling_covariance)))
end
