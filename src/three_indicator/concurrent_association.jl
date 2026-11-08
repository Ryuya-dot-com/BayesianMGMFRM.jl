include("plackett.jl")
include("plackett_table.jl")
const ASSOCIATION_SCHEMA="bayesianmgmfrm.concurrent_ac_model.v1"

"""Mathematical target with a global marginal-preserving A–C Plackett association.

The last unconstrained coordinate is log(psi), with an independent normalized
Normal(0, log_sd) prior. No change to the original target, its priors, or binary
conditional law. Shared fitted and predictive operations preserve this observation law.
"""
struct AssociationTarget{T<:Target}
    base::T
    log_sd::Float64
    function AssociationTarget(base::Target;log_sd)
        require(log_sd isa Real && !(log_sd isa Bool) && isfinite(log_sd) && log_sd>0,
            "declare a finite positive association_log_sd for log(psi) ~ Normal(0, sd)")
        sd=Float64(log_sd)
        require(isfinite(sd) && sd>0,"association prior SD must be representable in Float64")
        new{typeof(base)}(base,sd)
    end
end
L.dimension(t::AssociationTarget)=t.base.size+1
L.capabilities(::Type{<:AssociationTarget})=L.LogDensityOrder{1}()
initial(t::AssociationTarget)=vcat(initial(t.base),0.)
function association_point(t,q)
    require(length(q)==L.dimension(t),"invalid association parameter dimension")
    require(eltype(q)<:AbstractFloat,"association target accepts floating-point coordinates; use its analytic gradient")
    require(all(isfinite,q),"finite association coordinates required")
    view(q,1:t.base.size),q[end]
end
association_prior(t,ell)=-log(t.log_sd)-log(2pi)/2-(ell/t.log_sd)^2/2
function association_rows(t,q,z,ell)
    a=zeros(9);b=zeros(9);base=t.base;d=base.data
    n->begin
        logits!(a,base,z,n,1);logits!(b,base,z,n,2)
        Plackett.cell(a,b,d.y[n,1],d.y[n,2],ell)
    end
end
function pointwise(t::AssociationTarget,q)
    native,ell=association_point(t,q);b=t.base;z=reconstruct(b,native)
    cells=association_rows(t,q,z,ell);row=zeros(2);out=zeros(b.data.N)
    for n in eachindex(out)
        logits!(row,b,z,n,3)
        out[n]=cells(n).lp+row[b.data.y[n,3]]-M.lognormalizer(row)
    end
    out
end
function components(t::AssociationTarget,q)
    native,ell=association_point(t,q)
    (;likelihood=sum(pointwise(t,q)),ordinary_prior=ordinary_prior(t.base,native),
        hyper_prior=hyper_prior(t.base,native[t.base.hyper_indices]),association_prior=association_prior(t,ell))
end
function L.logdensity(t::AssociationTarget,q::AbstractVector{<:Real})
    require(length(q)==L.dimension(t),"invalid association parameter dimension")
    all(isfinite,q) || return -Inf
    try
        value=sum(values(components(t,q)))
        isfinite(value) ? value : -Inf
    catch e
        e isa C.UnrepresentableProposal || e isa PosDefException || rethrow()
        -Inf
    end
end
function L.logdensity_and_gradient(t::AssociationTarget,q::AbstractVector{<:Real})
    require(length(q)==L.dimension(t),"invalid association parameter dimension")
    all(isfinite,q) || return (-Inf,zeros(L.dimension(t)))
    try
        native,ell=association_point(t,Float64.(q));z=reconstruct(t.base,native)
        scores=likelihood_scores(t.base,native,z;association=association_rows(t,q,z,ell))
        value,g=gradient(t.base,native,z;scores)
        value+=association_prior(t,ell)
        g=vcat(g,scores[2].ac_log_psi[]-(ell/t.log_sd)/t.log_sd)
        isfinite(value) && all(isfinite,g) ? (value,g) : (-Inf,zeros(L.dimension(t)))
    catch e
        e isa C.UnrepresentableProposal || e isa PosDefException || rethrow()
        (-Inf,zeros(L.dimension(t)))
    end
end
function coordinates(t::AssociationTarget,q)
    native,ell=association_point(t,q)
    merge(coordinates(t.base,native),(;ac_log_psi=ell))
end
function contract(t::AssociationTarget)
    merge(contract(t.base),(;observation=:plackett_ac_times_binary,
        association=(;coordinate=:ac_log_psi,family=:normal,mean=0.,sd=t.log_sd,
            measure=:log_psi,independent_of_original_prior=true,shared_across_cohorts=true),
        gradient=:analytic_plackett_and_large_blocks_forwarddiff_small_factors,
        fitting=true,posterior_reporting=true,prior_predictive=true,
        stan_source="src/stan/concurrent_ac.stan",scientific_acceptance=false))
end
check_target(t::AssociationTarget)=(check_target(t.base);t)
function save_model(path,t::AssociationTarget)
    require(!ispath(path),"preserve existing output");check_target(t);b=t.base
    body=(;schema=ASSOCIATION_SCHEMA,rows=b.input.rows,source_sha256=b.input.source_sha256,
        prior=prior_spec(b.prior),interaction=b.interaction,association=:plackett,association_log_sd=t.log_sd)
    mkpath(dirname(abspath(path)))
    mktemp(dirname(abspath(path))) do temporary,io
        write(io,JSON3.write(body));close(io);hardlink(temporary,path)
    end
    (;path=abspath(path),sha256=bytes2hex(sha256(read(path))),kind=:model_specification,posterior=false)
end
function load_association(path;expected_sha256)
    bytes=read(path);require(bytes2hex(sha256(bytes))==expected_sha256,"model specification checksum mismatch")
    x=JSON3.read(bytes)
    require(x.schema==ASSOCIATION_SCHEMA && x.association=="plackett","unsupported association model schema/law")
    AssociationTarget(Target(Input(x.rows;source_sha256=x.source_sha256);
        prior=resolve_prior(x.prior),interaction=Symbol(x.interaction));log_sd=x.association_log_sd)
end
function stan_data(t::AssociationTarget)
    data=stan_data(t.base);data["association_log_sd"]=t.log_sd;data
end

# Shared geometry is explicit; no property forwarding can drop the appended coordinate.
native_target(t)=t
native_target(t::AssociationTarget)=t.base
modeldata(t)=t.data
modeldata(t::AssociationTarget)=t.base.data
observation(t)=:independent_three_responses
observation(t::AssociationTarget)=:plackett_ac_times_binary
observation_warnings(t)=String[]
observation_warnings(t::AssociationTarget)=["A single residual A/C association is shared across cohorts; it does not establish causal halo or cohort invariance."]
function reconstruct(t::AssociationTarget,q)
    native,ell=association_point(t,q)
    merge(reconstruct(t.base,native),(;ac_log_psi=ell))
end
logits!(buffer,t::AssociationTarget,z,n,a)=logits!(buffer,t.base,z,n,a)
function check_observation_contract(m)
    if !hasproperty(m,:observation)
        require(!hasproperty(m,:association),"association specification needs its observation law")
        return :independent_three_responses
    end
    require(m.observation in (:plackett_ac_times_binary,"plackett_ac_times_binary"),"unknown concurrent observation law")
    require(hasproperty(m,:association),"association prior specification missing")
    a=m.association
    require(a.coordinate in (:ac_log_psi,"ac_log_psi") && a.family in (:normal,"normal") &&
        a.measure in (:log_psi,"log_psi") && a.mean==0 && a.sd isa Real && !(a.sd isa Bool) &&
        isfinite(a.sd) && a.sd>0 && a.independent_of_original_prior===true &&
        a.shared_across_cohorts===true,"association prior/coordinate contract differs")
    :plackett_ac_times_binary
end
