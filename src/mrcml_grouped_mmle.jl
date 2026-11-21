# People with the same population law share the existing scalar integration kernel.
# All strata use the same measurement coordinates in a single optimization.
function _population_parts(t, pop, weights)
    groups = Dict{Tuple,Vector{Int}}()
    for p in eachindex(t.people)
        key = (pop.group_index[p], Tuple(pop.X[p,:]))
        push!(get!(groups,key,Int[]),p)
    end
    observations = [Int[] for _ in t.people]
    for (n,p) in enumerate(t.person)
        push!(observations[p],n)
    end
    return map(collect(groups)) do entry
        (group,x),persons = entry
        rows = reduce(vcat,observations[persons])
        ids = reduce(vcat,[fill(i,length(observations[p])) for (i,p) in enumerate(persons)])
        op = B.MRCML._with_fields(t.operator; n_obs=length(rows),
                                 pattern_of_row=t.operator.pattern_of_row[rows])
        (;group,x=collect(Float64,x),persons,ids,op,owner=t.group[rows],
          support=t.supports,category=t.category[rows],weights=weights[rows])
    end
end

function _grouped_mmle!(gradient,u,parts,quad,br,sr,offset)
    isnothing(gradient) || fill!(gradient,0.)
    d = first(br)-1
    nll = zero(eltype(u))
    for a in parts
        local_u = vcat(view(u,1:d),dot(a.x,view(u,br)),u[sr[a.group]])
        local_g = isnothing(gradient) ? nothing : zeros(d+2)
        nll += _mrcml_mmle_nll_and_grad!(local_g,local_u,a.op,length(a.persons),a.ids,
            a.owner,a.support,a.category,a.weights,quad,0.,1.,d+1,d+2,offset)
        if !isnothing(gradient)
            gradient[1:d] .+= view(local_g,1:d)
            gradient[br] .+= a.x .* local_g[d+1]
            gradient[sr[a.group]] += local_g[d+2]
        end
    end
    return nll
end

function _grouped_calibration(t,parts,eta,beta,sds,quad)
    info = zeros(length(eta),length(eta))
    scores = Vector{NamedTuple}(undef,length(t.people))
    for a in parts
        mu,sd = dot(a.x,beta),sds[a.group]
        info .+= _mrcml_mmle_conditional_info(eta,mu,sd,a.op,length(a.persons),a.ids,
                     a.owner,a.support,a.category,a.weights,quad)
        scaled = merge(quad,(;nodes=quad.std_nodes .* sd,sd))
        scores[a.persons] = _mrcml_person_scores_from_calibration(eta,a.op,t.people[a.persons],
            a.ids,a.owner,a.support,t.categories,a.category,a.weights;
            method=:mmle,quad=scaled,mu_hat=mu,sigma_hat=sd)
    end
    return info,scores
end

function _grouped_names(pop,scale)
    prefix = scale === :raw ? "log_population_sd" : "population_sd"
    return vcat(["population[$(m.name)]" for m in pop.mean_terms],
                ["$prefix[$(repr(g))]" for g in pop.groups])
end

function _grouped_summary(pop,u,br,sr,cov)
    beta,sd = u[br], exp.(u[sr])
    coefficients = [(;term=m.name,estimate=beta[i],se=sqrt(cov[br[i],br[i]]))
                    for (i,m) in enumerate(pop.mean_terms)]
    groups = [(;group=g,sd=sd[i],se=sd[i]*sqrt(cov[sr[i],sr[i]]))
              for (i,g) in enumerate(pop.groups)]
    return (;design=deepcopy(pop),coefficients,groups,person_mean=pop.X*beta,
             person_sd=sd[pop.group_index])
end

function _mrcml_person_law(summary,p)
    if hasproperty(summary,:population)
        return summary.population.person_mean[p], summary.population.person_sd[p]
    end
    return summary.population_mean,summary.population_sd
end
