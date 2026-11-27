# Included in PortableHandoff. The same record drives tidy rows, summaries and JSON.
using LinearAlgebra, Random
using Distributions: Normal, TDist

const PV_SCHEMA = "bayesianmgmfrm.grouped_plausible_values.v1"
struct PlausibleValues{T}
    record::T
end

function _pv_design(d)
    enc = B.AdditiveFacets.label_encoding
    first_cov = size(d.X,2) - length(d.covariates) + 1
    eq_sd = Bool(get(d, :equal_sd, false))
    return (;people=enc.(d.people), groups=enc.(d.groups), group_index=copy(d.group_index),
        reference_index=only(findall(==(d.reference),d.groups)),
        covariate_names=String.(collect(d.covariates)),
        covariates=[collect(d.X[p,first_cov:end]) for p in eachindex(d.people)],
        (eq_sd ? (; equal_sd = true) : (;))...)
end

function _pv_label(label)
    kind = String(label.kind)
    kind == "string" && return String(label.value)
    kind == "symbol" && return Symbol(label.value)
    kind == "integer" || throw(ArgumentError("invalid PV label kind"))
    # The portable representation retains the type spelling and every decimal digit.
    small = tryparse(Int,label.value)
    return isnothing(small) ? parse(BigInt,label.value) : small
end

const plausible_values = B.plausible_values

function B.plausible_values(f::B.FrequentistMFRM.Fit; n_imputations::Integer, seed::Integer)
    r = B.FrequentistMFRM.checked(f)
    r.problem.method === :mmle && hasproperty(r.summary,:population) ||
        throw(ArgumentError("plug-in PVs require a grouped scalar MRCML MMLE fit"))
    !(n_imputations isa Bool) && 1 <= n_imputations <= typemax(Int) ||
        throw(ArgumentError("n_imputations must be a positive integer"))
    !(seed isa Bool) && 0 <= seed <= typemax(Int) || throw(ArgumentError("invalid seed"))
    grid = B._mrcml_person_grid(r)
    people = eachindex(r.problem.person_levels)
    theta = [Vector{Float64}(undef,length(people)) for _ in 1:n_imputations]
    rng = Xoshiro(seed)
    for p in people
        cumulative = cumsum(view(grid.probabilities,p,:))
        cumulative ./= last(cumulative)
        for values in theta
            h = searchsortedlast(cumulative,rand(rng)) + 1
            values[p] = grid.nodes[p,h]
        end
    end
    d = r.summary.population.design
    c = B.coordinates(f)
    q = B.qualify(f)
    qualification = (;q.qualified,q.converged,q.gradient_gate_passed,q.hessian_gate_passed,q.boundary_gate_passed)
    return PlausibleValues((;schema=PV_SCHEMA,method="conditional_mmle",source_hash=r.content_hash,
        qualification,design=_pv_design(d),seed=Int(seed),quadrature=String(r.summary.quadrature),
        quad_points=r.summary.quad_points,theta_lim=r.summary.theta_lim,
        parameter_names=B.parameter_names(f;scale=:model),fixed_measurement=sort!(collect(r.mrcml_operator.fixed_model_names)),
        calibration=vcat(c.structural_model,c.population.coefficients,c.population.group_sd),
        draws=[(;imputation=i,chain=nothing,iteration=nothing,theta=v,parameters=nothing)
               for (i,v) in enumerate(theta)]))
end

function B.plausible_values(f::B.AdditiveFacets.Fit)
    t = B.AdditiveFacets.checked(f;full=true)
    t isa B.MRCML.Target && hasproperty(t.spec_record,:population) ||
        throw(ArgumentError("joint PVs require a grouped scalar MRCML Bayesian fit"))
    run = f.record.run
    m = B.AdditiveFacets.model_draws(t,run.draws)
    P = length(t.people)
    q = B.qualify(f)
    qualification = (;q.qualified,q.parameter_gate_passed,q.sampler_gate_passed,q.telemetry_complete)
    return PlausibleValues((;schema=PV_SCHEMA,method="joint_posterior",source_hash=f.record.content_hash,
        qualification,design=_pv_design(t.spec_record.population),seed=nothing,
        parameter_names=m.names[P+1:end],fixed_measurement=sort!(collect(t.operator.fixed_model_names)),calibration=nothing,
        draws=[(;imputation=i,chain=run.chain_ids[i],iteration=run.iterations[i],
                 theta=m.values[i,1:P],parameters=m.values[i,P+1:end]) for i in axes(m.values,1)]))
end

"""Iterate one row per imputation and person with original person/group labels and joint draw IDs."""
function pv_rows(pv::PlausibleValues)
    r = pv.record
    ids = _pv_label.(r.design.people)
    groups = _pv_label.(r.design.groups)[r.design.group_index]
    return ((;s.imputation,s.chain,s.iteration,person=ids[p],group=groups[p],theta=s.theta[p])
            for s in r.draws for p in eachindex(ids))
end

"""Check the rectangular person/parameter arrays, typed roster, draw IDs and conditioning mode."""
function checked_pvs(r)
    valid(x) = x isa Real && !(x isa Bool) && isfinite(x)
    integers(x) = x isa Integer && !(x isa Bool) && x >= 1
    r.schema == PV_SCHEMA && occursin(r"^[0-9a-f]{64}$",r.source_hash) &&
        r.qualification.qualified isa Bool || throw(ArgumentError("invalid PV provenance"))
    d = r.design
    P, G, K = length(d.people), length(d.groups), length(d.covariate_names)
    n_sd = Bool(get(d, :equal_sd, false)) ? 1 : G
    joint = r.method == "joint_posterior"
    joint || r.method == "conditional_mmle" || throw(ArgumentError("unknown PV method"))
    N = length(r.parameter_names)
    P > 0 && G >= 2 && N >= (G - 1) + K + n_sd && integers(d.reference_index) && d.reference_index <= G &&
        allunique(_pv_label.(d.people)) && allunique(_pv_label.(d.groups)) &&
        allunique(d.covariate_names) && length(d.group_index)==P && all(integers,d.group_index) &&
        Set(d.group_index)==Set(1:G) && length(d.covariates)==P &&
        all(x->length(x)==K && all(valid,x),d.covariates) ||
        throw(ArgumentError("invalid PV roster or parameter layout"))
    calibration_ok(v) = !isnothing(v) && length(v)==N && all(valid,v) && all(>(0),v[end-n_sd+1:end])
    (joint ? isnothing(r.calibration) && isnothing(r.seed) :
        calibration_ok(r.calibration) && r.seed isa Integer && !(r.seed isa Bool) && r.seed >= 0) ||
        throw(ArgumentError("invalid PV calibration"))
    !isempty(r.draws) || throw(ArgumentError("no PV imputations"))
    for (i,s) in enumerate(r.draws)
        s.imputation==i && length(s.theta)==P && all(valid,s.theta) ||
            throw(ArgumentError("invalid person draw at imputation $i"))
        ids_ok = joint ? integers(s.chain) && integers(s.iteration) && calibration_ok(s.parameters) :
            isnothing(s.chain) && isnothing(s.iteration) && isnothing(s.parameters)
        ids_ok || throw(ArgumentError("invalid parameter pairing at imputation $i"))
    end
    joint && !allunique((s.chain,s.iteration) for s in r.draws) &&
        throw(ArgumentError("duplicate chain and iteration in joint PVs"))
    return PlausibleValues(r)
end

function save_pvs(path,pv::PlausibleValues)
    checked_pvs(pv.record)
    (ispath(path) || islink(path)) && throw(ArgumentError("refusing to overwrite PV bundle"))
    mkpath(dirname(abspath(path)))
    mktemp(dirname(abspath(path))) do tmp,io
        JSON3.write(io,pv.record)
        close(io)
        hardlink(tmp,path)
    end
    return path
end

"""
    PortableHandoff.group_contrast(pvs; group, reference, level=0.95)

Compare two named population means at the same covariates. For joint PVs use
each draw's regression contrast and return an equal-tailed credible interval.
For plug-in PVs fit an unweighted regression with a separate group intercept
and common covariate slopes in each imputation. Pool the independent-person
HC2 variances with Rubin's large-complete-sample rule. The resulting interval
is conditional on calibration and population hyperparameters. `mcse_imputation`
measures only finite-imputation uncertainty in the pooled point estimate.
"""
function group_contrast(pv::PlausibleValues; group,reference,level=0.95)
    level isa Real && 0 < level < 1 || throw(ArgumentError("level must be between 0 and 1"))
    r, d = pv.record, pv.record.design
    groups = _pv_label.(d.groups)
    g, h = findfirst(==(group),groups), findfirst(==(reference),groups)
    !isnothing(g) && !isnothing(h) && g!=h || throw(ArgumentError("select two distinct modeled groups"))
    G = length(groups)
    M = length(r.draws)
    tail = (1-level)/2
    meta = (;group,reference,level,source_qualified=r.qualification.qualified,n_draws=M)
    if r.method == "joint_posterior"
        others = filter(!=(d.reference_index),1:G)
        n_sd_g = Bool(get(d, :equal_sd, false)) ? 1 : G
        start = length(r.parameter_names)-(G-1)-n_sd_g-length(d.covariate_names)
        at(s,i) = i==d.reference_index ? 0.0 : s.parameters[start+findfirst(==(i),others)]
        differences = [at(s,g)-at(s,h) for s in r.draws]
        return (;meta...,method=:joint_posterior,estimate=mean(differences),
                lower=quantile(differences,tail),upper=quantile(differences,1-tail))
    end
    M >= 2 || throw(ArgumentError("Rubin pooling needs at least two imputations"))
    X = hcat(Float64.(d.group_index .== permutedims(collect(1:G))),
             Float64[d.covariates[p][k] for p in eachindex(d.people), k in eachindex(d.covariate_names)])
    rank(X)==size(X,2) || throw(ArgumentError("complete-data regression is rank deficient"))
    F = qr(X)
    Q = Matrix(F.Q)
    c = zeros(size(X,2)); c[g]=1; c[h]=-1
    weights = Q * (F.R' \ c)
    remaining = 1 .- vec(sum(abs2,Q;dims=2))
    all(>(eps(Float64)*size(X,2)),remaining) || throw(ArgumentError("HC2 variance is undefined at unit leverage"))
    estimates = Float64[]; within = Float64[]
    for s in r.draws
        y = collect(Float64,s.theta)
        residual = y - Q*(Q'*y)
        push!(estimates,dot(weights,y))
        push!(within,sum(abs2.(weights .* residual) ./ remaining))
    end
    W, V = mean(within), var(estimates)
    extra = (1+1/M)*V
    total = W+extra
    df = extra==0 ? Inf : (M-1)*(1+W/extra)^2
    critical = quantile(isinf(df) ? Normal() : TDist(df),1-tail)
    estimate = mean(estimates)
    return (;meta...,method=:conditional_mmle_rubin,estimate,within=W,between=V,total_variance=total,
            df,mcse_imputation=sqrt(V/M),lower=estimate-critical*sqrt(total),upper=estimate+critical*sqrt(total))
end
