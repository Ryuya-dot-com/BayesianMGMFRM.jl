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

@inline _grouped_sd_slot(sr::UnitRange{Int}, grp::Int) = length(sr) == 1 ? first(sr) : sr[grp]

function _grouped_mmle!(gradient,u::AbstractVector{TU},parts,quad,br,sr,offset) where {TU<:Real}
    T = promote_type(TU, eltype(offset))
    isnothing(gradient) || fill!(gradient,zero(T))
    d = first(br)-1
    nll = zero(T)
    for a in parts
        s_slot = _grouped_sd_slot(sr, a.group)
        local_u = T[u[1:d]; dot(a.x,view(u,br)); u[s_slot]]
        local_g = isnothing(gradient) ? nothing : zeros(T, d+2)
        sc = hasproperty(a, :scratch) ? a.scratch : nothing
        nll += _mrcml_mmle_nll_and_grad!(local_g,local_u,a.op,length(a.persons),a.ids,
            a.owner,a.support,a.category,a.weights,quad,0.,1.,d+1,d+2,offset,sc)
        if !isnothing(gradient)
            gradient[1:d] .+= view(local_g,1:d)
            gradient[br] .+= T.(a.x) .* local_g[d+1]
            gradient[s_slot] += local_g[d+2]
        end
    end
    return nll
end

function _grouped_louis(u, parts, quad, br, sr, patterns; calibration=false)
    d = first(br)-1
    H = zeros(length(u),length(u))
    conditional = calibration ? zeros(d,d) : nothing
    meat = calibration ? zero(H) : nothing
    for a in parts
        sd_slot = _grouped_sd_slot(sr,a.group)
        local_u = [u[1:d]; dot(a.x,view(u,br)); u[sd_slot]]
        local_H = _mrcml_louis(local_u,a.op,a.ids,a.owner,a.support,a.category,
                               a.weights,quad,0.0,1.0,d+1,d+2,a.scratch,patterns; calibration)
        J = spzeros(d+2,length(u))
        for i in 1:d
            J[i,i] = 1.0
        end
        J[d+1,br] = a.x
        J[d+2,sd_slot] = 1.0
        if calibration
            conditional .+= local_H.conditional
            meat .+= J' * local_H.meat * J
            H .+= J' * local_H.observed * J
        else
            H .+= J' * local_H * J
        end
    end
    return calibration ? (; observed=Symmetric(H), conditional, meat) : Symmetric(H)
end

function _grouped_person_scores(t,parts,eta,beta,sds,quad)
    scores = Vector{NamedTuple}(undef,length(t.people))
    for a in parts
        mu = dot(a.x,beta)
        sd = length(sds) == 1 ? sds[1] : sds[a.group]
        scaled = merge(quad,(;nodes=quad.std_nodes .* sd,sd))
        scores[a.persons] = _mrcml_person_scores_from_calibration(eta,a.op,t.people[a.persons],
            a.ids,a.owner,a.support,t.categories,a.category,a.weights;
            method=:mmle,quad=scaled,mu_hat=mu,sigma_hat=sd)
    end
    return scores
end

function _grouped_names(pop,scale)
    eq_sd = Bool(get(pop, :equal_sd, false))
    if eq_sd
        sd_names = [scale === :raw ? "log_population_sd" : "population_sd"]
    else
        prefix = scale === :raw ? "log_population_sd" : "population_sd"
        sd_names = ["$prefix[$(repr(g))]" for g in pop.groups]
    end
    return vcat(["population[$(m.name)]" for m in pop.mean_terms], sd_names)
end

function _grouped_summary(pop,u,br,sr,cov; sandwich_cov = nothing)
    beta, sd = u[br], exp.(u[sr])
    eq_sd = length(sr) == 1
    coefficients = [
        (;
            term = m.name,
            estimate = beta[i],
            se = sqrt(max(cov[br[i], br[i]], 0.0)),
            (sandwich_cov === nothing ? (;) : (; sandwich_se = sqrt(max(sandwich_cov[br[i], br[i]], 0.0))))...,
        ) for (i, m) in enumerate(pop.mean_terms)
    ]
    groups = [
        begin
            k = eq_sd ? 1 : i
            sd_k = sd[k]
            (;
                group = g,
                sd = sd_k,
                se = sd_k * sqrt(max(cov[sr[k], sr[k]], 0.0)),
                (sandwich_cov === nothing ? (;) : (; sandwich_se = sd_k * sqrt(max(sandwich_cov[sr[k], sr[k]], 0.0))))...,
            )
        end for (i, g) in enumerate(pop.groups)
    ]
    p_sd = [sd[eq_sd ? 1 : g] for g in pop.group_index]
    return (; design = deepcopy(pop), equal_sd = eq_sd, coefficients, groups,
              person_mean = pop.X * beta, person_sd = p_sd)
end

function _mrcml_person_law(summary,p)
    if hasproperty(summary,:population)
        return summary.population.person_mean[p], summary.population.person_sd[p]
    end
    return summary.population_mean,summary.population_sd
end
