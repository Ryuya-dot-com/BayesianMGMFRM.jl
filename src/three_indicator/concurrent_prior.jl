"""
    ConcurrentPrior(preset::Symbol; kwargs...)

Override numerical settings of `:reference`, `:steps` or `:combined` for the
experimental concurrent 9/9/2 model. Pass this object as `prior` to `getdesign`.
Families and identification stay fixed: Gaussian effects, half-normal population
SDs and LKJ correlations. The preliminary-only model does not accept this type.

Supported keywords are `sd_scale` (six half-normal scales: speaker, word, rater,
recording, time, language), `step_sd_scale` (rater-step population SD scale),
`slope_log_sd`, `intercept_sd` (three Gaussian SDs), `cohort_sd`, `beta_sd` (three
Gaussian SDs), `lkj_eta`, `step_mean` (eight centered transition means shared by
the ordinal outcomes), `step_coordinate_sd`, `pair_sd_scale`, and `pair_lkj_eta`.
Triples follow accentedness, comprehension difficulty, transcription error.
Scales and LKJ shapes must be finite and positive. Means need not be ordered.

The logit multiplier is one. Step SD is on orthonormal contrast coordinates,
not eight independent steps; slope SD is a centered log-slope kernel scale.
Population SD hyperpriors are not marginal SDs of the reconstructed centered or
convolved effects. `contract(target)` reports the resolved settings. Presets are
starting values, not scientifically recommended priors. Arbitrary distribution
objects, hard ordering, and nonzero general effect means are unsupported.
"""
struct Prior
    preset::Symbol
    sd_scale::NTuple{6,Float64}
    step_sd_scale::Float64
    slope_log_sd::Float64
    intercept_sd::NTuple{3,Float64}
    cohort_sd::Float64
    beta_sd::NTuple{3,Float64}
    lkj_eta::Float64
    step_mean::NTuple{8,Float64}
    step_coordinate_sd::Float64
    pair_sd_scale::Float64
    pair_lkj_eta::Float64

    function Prior(preset::Symbol; kwargs...)
        defaults=prior_defaults(preset)
        require(all(k->k in keys(defaults),keys(kwargs)),"unknown concurrent prior setting")
        x=merge(defaults,(;kwargs...))
        scales=prior_tuple(x.sd_scale,6,:sd_scale)
        intercept=prior_tuple(x.intercept_sd,3,:intercept_sd)
        beta=prior_tuple(x.beta_sd,3,:beta_sd)
        means=prior_tuple(x.step_mean,8,:step_mean;positive=false)
        require(abs(sum(means))<=64eps(Float64)*max(1.,maximum(abs,means)),
            "step_mean must sum to zero; do not hide an intercept shift in step means")
        new(preset,scales,prior_number(x.step_sd_scale,:step_sd_scale),
            prior_number(x.slope_log_sd,:slope_log_sd),intercept,
            prior_number(x.cohort_sd,:cohort_sd),beta,prior_number(x.lkj_eta,:lkj_eta),
            means,prior_number(x.step_coordinate_sd,:step_coordinate_sd),
            prior_number(x.pair_sd_scale,:pair_sd_scale),prior_number(x.pair_lkj_eta,:pair_lkj_eta))
    end
end
function prior_number(x,key;positive=true)
    require(x isa Real && !(x isa Bool) && isfinite(x),"$key must be a finite real number, not Bool")
    y=Float64(x)
    require(isfinite(y) && (!positive || y>0),"$key must be representable and positive for a scale/shape")
    y
end
function prior_tuple(x,n,key;positive=true)
    require((x isa Tuple || x isa AbstractVector) && length(x)==n,"$key requires $n entries")
    Tuple(prior_number(v,key;positive) for v in x)
end
function prior_defaults(preset)
    r=M.prior_record(preset)
    merge(Base.structdiff(r,(;name=nothing,step_ordered=nothing)),(;pair_sd_scale=.5,pair_lkj_eta=2.))
end
prior_parameters(p::Prior)=(;(k=>getfield(p,k) for k in fieldnames(Prior) if k!==:preset)...)
function prior_record(p::Prior)
    values=prior_parameters(p);defaults=prior_defaults(p.preset)
    (;name=all(k->values[k]==defaults[k],keys(values)) ? p.preset : :custom,values...,step_ordered=false)
end
prior_record(p)=M.prior_record(p)
pair_sd_scale(p)=p isa Prior ? p.pair_sd_scale : .5
pair_lkj_eta(p)=p isa Prior ? p.pair_lkj_eta : 2.
step_coordinate_sd(p)=p isa Prior ? p.step_coordinate_sd : 1.
const PRIOR_SCHEMA="bayesianmgmfrm.concurrent_prior.v1"
prior_spec(p::Prior)=(;schema=PRIOR_SCHEMA,preset=p.preset,parameters=prior_parameters(p))
prior_spec(p)=M.prior_record(p).name
resolve_prior(p::Prior)=p
function resolve_prior(p)
    if p isa NamedTuple || p isa JSON3.Object
        if hasproperty(p,:schema)
            require(Set(Symbol.(keys(p)))==Set((:schema,:preset,:parameters)) && p.schema==PRIOR_SCHEMA,
                "unsupported concurrent prior record")
            preset=Symbol(p.preset)
            require(Set(Symbol.(keys(p.parameters)))==Set(keys(prior_defaults(preset))),
                "concurrent prior record must retain every numeric setting")
            return Prior(preset;(Symbol(k)=>v for (k,v) in pairs(p.parameters))...)
        end
    end
    M.resolve_prior(p isa AbstractString ? Symbol(p) : p)
end
