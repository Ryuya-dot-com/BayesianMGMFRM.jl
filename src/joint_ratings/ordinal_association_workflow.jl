using Random, Statistics, Serialization, SHA, JSON3
import BayesianMGMFRM as B
import ..JointRatingWorkflow as W

const SCHEMA="bayesianmgmfrm.ordinal_association_samples.v1"
const PRIOR_KEYS=(:task_sd,:rater_sd,:step_sd,:response_log_sd_mean,
    :response_log_sd_sd,:person_lkj_eta,:response_lkj_eta,:intercept_sd,
    :person_log_sd_mean,:person_log_sd_sd,:lambda_sd)

"""
    contract()

Experimental two-criterion ordinal association model. Unit coefficients;
estimated person SDs, explicit criterion means, centered task effects and
correlated response effects. Lambda is a uniform adjacent log odds ratio,
not a Pearson correlation or a psychological halo. No predictors, new-level
prediction, time effects, scientific default prior or acceptance are supplied.
Native samples require their producing source and environment; JSON is a report.
"""
contract()=(;status=:experimental,criteria=2,common_category_count=true,
    minimum_categories=3,distinct_threshold_groups=true,coefficients=:fixed_unit,
    explicit_prior_required=true,person_sd=:estimated,task_effects=:sum_zero,
    criterion_means=:explicit,association=:uniform_adjacent_log_odds,
    missing_ratings=:marginalized_joint_table,missingness=:assumed_ignorable,
    predictors=false,samplers=(:advancedhmc,),scientific_acceptance=false,
    prediction=:existing_rating_event_conditional_probabilities,
    native_cache=:trusted_same_source_and_environment,json=:report_only)

"""
    model(rows; criteria, prior)

Use the JointRatings row/criterion schema, with separate threshold groups and
the same full support size (at least three categories). Omit missing rows.
Response IDs identify productions; event IDs identify a rater's assessment of
a production. They are separate namespaces, and a singleton event is retained.

Declare exactly `task_sd`, two `rater_sd`, two `step_sd`, two
`response_log_sd_mean`, two `response_log_sd_sd`, `person_lkj_eta`,
`response_lkj_eta`, `intercept_sd`, `person_log_sd_mean`, `person_log_sd_sd`
and `lambda_sd`. Criterion vectors and step groups follow sorted IDs. SDs must
be positive. Intercepts have independent N(0,intercept_sd²) priors. Both person
log SDs have independent N(person_log_sd_mean,person_log_sd_sd²) priors.
Lambda has N(0,lambda_sd²). All priors are proper and normalized in the sampled
white/log-SD/Fisher-z coordinates; no prior is silently adopted.

The likelihood is proportional to exp(U₁(k)+U₂(l)+lambda*(k-c)*(l-c)),
c=(K-1)/2, normalized over K² cells. Nonzero lambda changes the margins.
Person sample means are integrated during sampling and conditionally restored,
not constrained to zero. Validation does not establish model adequacy.
"""
function model(rows;criteria,prior)
    prior isa NamedTuple && Set(keys(prior))==Set(PRIOR_KEYS) ||
        throw(ArgumentError("declare exactly $PRIOR_KEYS"))
    for k in (:intercept_sd,:person_log_sd_mean,:person_log_sd_sd,:lambda_sd)
        S.finite_number(prior[k]) && (k==:person_log_sd_mean || prior[k]>0) ||
            throw(ArgumentError("$k must be finite; widths must be positive"))
    end
    baseprior=NamedTuple{S.PRIOR_KEYS}(Tuple(k==:beta_sd ? () : prior[k] for k in S.PRIOR_KEYS))
    base=S.Target(rows;criteria,prior=baseprior)
    base.sizes[5]>=3 && base.sizes[6]==2 ||
        throw(ArgumentError("require at least three categories and distinct threshold groups"))
    Target(C.Target(base,Float64(prior.lambda_sd));intercept_sd=Float64(prior.intercept_sd),
        log_sd_mean=Float64(prior.person_log_sd_mean),log_sd_sd=Float64(prior.person_log_sd_sd))
end

function target_record(t::Target)
    h=t.layout;base=h.original.base
    original=S.target_record(base)
    pr=merge(Base.structdiff(base.prior,(;beta_sd=nothing)),
        (;intercept_sd=t.intercept_sd,person_log_sd_mean=t.log_sd_mean,
          person_log_sd_sd=t.log_sd_sd,lambda_sd=h.original.lambda_sd))
    r=(;schema="bayesianmgmfrm.ordinal_association_target.v1",rows=original.rows,
        criteria=original.criteria,prior=pr,contract=contract())
    canonical=model(r.rows;criteria=r.criteria,prior=r.prior)
    isequal(t.estimated_scale,true) && isequal(h.original.events,canonical.layout.original.events) &&
        all(f->isequal(getfield(h,f),getfield(canonical.layout,f)),
            (:hp,:ht,:person,:task,:difference,:tail)) ||
        throw(ArgumentError("derived target layout changed"))
    r
end
function from_record(r)
    t=model(r.rows;criteria=r.criteria,prior=r.prior)
    isequal(target_record(t),r) || throw(ArgumentError("unsupported target specification"))
    t
end
initial(t::Target)=from_original(t,C.initial(t.layout.original);
    sd=(exp(t.log_sd_mean),exp(t.log_sd_mean)))
function B._check_source_fixture_raw_vector(t::Target,q::AbstractVector)
    length(q)==L.dimension(t) && all(isfinite,q) || throw(ArgumentError("invalid coordinates"))
    nothing
end

function source_signature()
    root=pkgdir(B);files=Dict{String,String}()
    for (directory,_,names) in walkdir(joinpath(root,"src")), name in sort(names)
        p=joinpath(directory,name);files[relpath(p,root)]=bytes2hex(sha256(read(p)))
    end
    files["Project.toml"]=bytes2hex(sha256(read(joinpath(root,"Project.toml"))))
    project=Base.active_project()
    manifest=project===nothing ? nothing : joinpath(dirname(project),"Manifest.toml")
    (;source_hash=B._cache_hash(files),julia=string(VERSION),platform=Sys.MACHINE,
        project=project===nothing ? nothing : bytes2hex(sha256(read(project))),
        manifest=manifest!==nothing && isfile(manifest) ? bytes2hex(sha256(read(manifest))) : nothing)
end

function model_draws(t::Target,draws,locations)
    h=t.layout;base=h.original.base;P,T=base.sizes;lv=base.levels
    template=W.model_draws(base,permutedims(S.initial(base)))
    names=vcat(replace.(template.names,"task["=>"word["),["lambda"],
        ["speaker_sd[$(repr(c))]" for c in lv.criterion],
        ["intercept[$(repr(c))]" for c in lv.criterion],["centered_profile_correlation"])
    positive=union(template.positive,Set(["speaker_sd[$(repr(c))]" for c in lv.criterion]))
    size(locations)==(size(draws,1),2) && all(isfinite,locations) ||
        throw(ArgumentError("one finite pair of conditional coordinates per joint draw required"))
    values=zeros(size(draws,1),length(names))
    for i in axes(draws,1)
        x=view(draws,i,:);r=representative(t,x);v=r.coordinates;cond=conditional(t,r.g)
        mean=cond.mean+cond.root*view(locations,i,:);theta=r.theta.+mean
        word=base.prior.task_sd*reshape(x[h.task],2,T-1)*h.ht';intercept=r.g.d-mean
        values[i,:]=[vec(theta);vec(word);vec(v.rater);vec(v.steps);vec(v.response);v.beta;
            v.response_sd;v.person_correlation;v.response_correlation;v.lambda;r.g.sd;intercept;
            cor(theta[1,:],theta[2,:])]
    end
    (;names,values,positive,fixed=template.fixed)
end
function raw_names(t)
    h=t.layout;base=h.original.base
    old=vcat(["$name[$j]" for (name,block) in pairs(base.blocks) for j in eachindex(block)],["lambda"])
    vcat(["person_contrast_white[$j]" for j in eachindex(h.person)],
        ["word_contrast_white[$j]" for j in eachindex(h.task)],
        ["location_sum_white[$j]" for j in 1:2],old[H.tail(h)],
        ["log_speaker_sd[$j]" for j in 1:2])
end

# Internal construction also permits an audited, source-bound historical bridge.
# The bridge must verify its original producer before passing any saved run.
function _record(t,run,locations;provenance,warnings)
    m=model_draws(t,run.draws,locations)
    target=target_record(t)
    body=(;schema=SCHEMA,target,target_identity=B._cache_hash(target),source=source_signature(),
        provenance=deepcopy(provenance),warnings=String.(warnings),run,locations=copy(locations),
        model_effects_hash=B._cache_hash((;names=m.names,values=m.values)))
    merge(body,(;content_hash=B._cache_hash(body)))
end
function restore(record)
    record isa NamedTuple && keys(record)==(:schema,:target,:target_identity,:source,
        :provenance,:warnings,:run,:locations,:model_effects_hash,:content_hash) && record.schema==SCHEMA ||
        throw(ArgumentError("unsupported ordinal association sample record"))
    B._cache_hash(Base.structdiff(record,(;content_hash=nothing)))==record.content_hash ||
        throw(ArgumentError("sample checksum mismatch"))
    isequal(record.source,source_signature()) || throw(ArgumentError("source or environment changed"))
    B._cache_hash(record.target)==record.target_identity || throw(ArgumentError("target identity mismatch"))
    t=from_record(record.target)
    B._check_generalized_sample_run(t,record.run)
    length(record.run.warmup_stats)==record.run.controls.warmup*record.run.controls.chains ||
        throw(ArgumentError("complete warmup telemetry required"))
    B._warmup_diagnostic_rows(record.run.warmup_stats,record.run.controls,record.run.backend)
    m=model_draws(t,record.run.draws,record.locations)
    all(isfinite,m.values) && B._cache_hash((;names=m.names,values=m.values))==record.model_effects_hash ||
        throw(ArgumentError("restored model effects changed"))
    t
end

"""
    fit(target; ndraws, warmup, chains, seed, reconstruction_seed, kwargs...)

Run AdvancedHMC with an analytic gradient. Explicit independent seeds identify
sampling and conditional-location restoration. Store both raw joint draws and
the two conditional white values per draw; reloading never regenerates them.
Controls include `target_accept=.9`, `max_depth=10`, `step_size=.03`,
`init_jitter=.1`, `metric=:diagonal`, `chain_execution=:serial`,
`max_parallel_chains=chains` and `progress=false`. There is no automatic refit,
extension or scientific acceptance. Inspect `report` and save the result.
"""
function fit(target::Target;ndraws::Int,warmup::Int,chains::Int,seed,reconstruction_seed,
        target_accept=.9,max_depth=10,step_size=.03,init_jitter=.1,metric=:diagonal,
        chain_execution=:serial,max_parallel_chains=chains,progress=false)
    all(s->s isa Integer && !(s isa Bool) && s>=0,(seed,reconstruction_seed)) &&
        seed!=reconstruction_seed || throw(ArgumentError("distinct nonnegative integer seeds required"))
    t=from_record(target_record(target))
    run=B._run_generalized_candidate_advancedhmc(t,initial(t);ndraws,warmup,chains,seed,
        target_accept,max_depth,step_size,init_jitter,metric,chain_execution,max_parallel_chains,
        ad_backend=:analytic,progress,record_warmup=true)
    locations=randn(MersenneTwister(reconstruction_seed),run.total_draws,2)
    result=_record(t,run,locations;provenance=(;operation=:fit,seed,reconstruction_seed),
        warnings=["Experimental model; scientific prior choice, fit and sensitivity require assessment."])
    restore(result)
    result
end

"""`save_result(path, result)` validates and saves without overwrite. Trusted native format only."""
function save_result(path::AbstractString,result)
    restore(result)
    B._save_serialized_record(path,result;overwrite=false)
end
"""`load_result(path)` validates source/environment, joint pairing and every density; no RNG or fit."""
function load_result(path::AbstractString)
    result=open(deserialize,path)
    restore(result)
    result
end

function diagnostics(t,run,m,locations)
    diagnose(values,names;fixed=Set{String}(),space=:model)=B._candidate_mcmc_diagnostic_rows(
        values,names,run.controls.chains;parameter_space=space,structurally_fixed_parameters=fixed,
        split_chains=run.split_chains_requested,rhat_threshold=run.checked.rhat_threshold,
        ess_threshold=run.checked.ess_threshold)
    (;raw=diagnose(run.draws,raw_names(t);space=:white_log_sd_fisher_z),
      model=diagnose(m.values,m.names;fixed=m.fixed),
      conditional=diagnose(locations,["conditional_location_white[$i]" for i in 1:2];space=:conditional),
      sampler=run.sampler_rows,warmup=B._warmup_diagnostic_rows(run.warmup_stats,run.controls,run.backend))
end
function envelope(record,operation,payload)
    (;schema="bayesianmgmfrm.ordinal_association_report.v1",operation,api=contract(),
      model=deepcopy(record.target),target_identity=record.target_identity,
      source_sample_content_hash=record.content_hash,provenance=deepcopy(record.provenance),
      warnings=copy(record.warnings),result=payload)
end

"""
    report(result; parameters=nothing, interval=.95)

Summarize named person profiles, person/response correlations and SDs, criterion
means, lambda and centered-profile correlation. `parameters` selects exact
stored names (e.g. `word[...]`, `rater[...]`) for summaries/MCSE; diagnostics
always retain every raw, model and conditional-location parameter. Intervals
are equal-tailed. Mean and endpoint MCSE are reported, never auto-qualified.
Whole-source sampler/warmup warnings and saved contextual limitations remain.
Population correlation, finite-profile correlation, response correlation and
the local log odds ratio answer different questions; none establishes causality.
"""
function report(record;parameters=nothing,interval=.95)
    S.finite_number(interval) && 0<interval<1 || throw(ArgumentError("interval must be in (0,1)"))
    t=restore(record);run=record.run;m=model_draws(t,run.draws,record.locations)
    selected=parameters===nothing ? filter(m.names) do n
        startswith(n,"theta[") || startswith(n,"rho_") || startswith(n,"response_sd[") ||
        startswith(n,"speaker_sd[") || startswith(n,"intercept[") ||
        n in ("lambda","centered_profile_correlation")
    end : collect(parameters)
    !isempty(selected) && allunique(selected) && all(n->n in m.names,selected) ||
        throw(ArgumentError("select distinct stored parameter names"))
    ix=[only(findall(==(n),m.names)) for n in selected];values=m.values[:,ix]
    lo=(1-Float64(interval))/2;hi=1-lo
    posterior=B._posterior_summary_rows(values,selected;lower=lo,upper=hi,intervals=(interval,),
        reference=0.,rope=nothing,rope_probability_threshold=.95)
    posterior=[row.parameter in m.positive ? merge(row,(;reference=missing,
        probability_positive=missing,probability_negative=missing,probability_equal=missing,
        probability_of_direction=missing,direction=:not_applicable_positive_scale)) : row for row in posterior]
    envelope(record,:parameters,(;posterior,interval_method=:equal_tailed,
        mcse=B._posterior_mcse_rows(values,selected,run.controls.chains;
            probabilities=(lo,.5,hi),parameter_space=:model,structurally_fixed_parameters=m.fixed),
        diagnostics=diagnostics(t,run,m,record.locations),controls=run.controls,
        parameter_names=m.names,focal_precision_qualification=:not_assessed,scientific_acceptance=false))
end

"""
    contrast(result; facet, criterion, left, right, interval=.95, rope=nothing)

Same-criterion `:person` or `:rater` difference, left minus right, with equal-tailed
interval, MCSE and all source diagnostics. Positive means higher canonical trait
for persons, greater severity for raters. Exact string IDs are required. This is
not a raw-score or across-criterion contrast. No refit or conditional RNG occurs.
"""
function contrast(record;facet,criterion,left,right,interval=.95,rope=nothing)
    t=restore(record);base=t.layout.original.base
    facet in (:person,:rater) && left!=right &&
        all(S.J.nonempty_id,(criterion,left,right)) && criterion in base.levels.criterion &&
        left in base.levels[facet] && right in base.levels[facet] || throw(ArgumentError("invalid contrast IDs"))
    m=model_draws(t,record.run.draws,record.locations);stem=facet===:person ? "theta" : "rater"
    a=only(findall(==("$stem[$(repr(left)),$(repr(criterion))]"),m.names))
    b=only(findall(==("$stem[$(repr(right)),$(repr(criterion))]"),m.names))
    envelope(record,:contrast,(;facet,criterion,left,right,units=:unit_logit,
        direction=only(c.direction for c in base.data.criteria if c.criterion==criterion),
        positive_difference=facet===:person ? :higher_canonical_trait : :greater_severity,
        summary=B.posterior_contrast(m.values[:,a],m.values[:,b];chains=record.run.controls.chains,interval,rope),
        diagnostics=diagnostics(t,record.run,m,record.locations),
        focal_precision_qualification=:not_assessed,scientific_acceptance=false))
end

"""
    event_probabilities(result; rating_event_id, interval=.95)

Joint category probabilities at one existing rating event, conditional on fitted
effects. Returns canonical cells with both original raw labels, equal-tailed
intervals and MCSE. A singleton still has a full joint table. This is an in-sample
conditional description, not heldout prediction or a product of marginals.
"""
function event_probabilities(record;rating_event_id,interval=.95)
    S.finite_number(interval) && 0<interval<1 || throw(ArgumentError("interval must be in (0,1)"))
    t=restore(record);a=t.layout.original;base=a.base;K=base.sizes[5]
    indices=findall(e->base.data.rows[e[1]].rating_event_id==rating_event_id,a.events)
    length(indices)==1 || throw(ArgumentError("unknown rating_event_id"))
    n,ya,yb=a.events[only(indices)];run=record.run
    values=zeros(run.total_draws,K*K);p=zeros(K,K);la=zeros(K);lb=zeros(K);da=zeros(K);db=zeros(K)
    for i in axes(values,1)
        v=representative(t,view(run.draws,i,:)).coordinates
        C.category_logits!(la,a,v,n,1);C.category_logits!(lb,a,v,n,2)
        C.pair_terms!(p,da,db,la,lb,v.lambda,ya,yb)
        values[i,:]=vec(p)
    end
    labels=[c.direction==:higher_is_more ? c.levels : reverse(c.levels) for c in base.data.criteria]
    cells=[(;canonical=(i-1,j-1),raw=(labels[1][i],labels[2][j])) for j in 1:K for i in 1:K]
    names=["cell[$(c.canonical[1]),$(c.canonical[2])]" for c in cells];lo=(1-interval)/2;hi=1-lo
    m=model_draws(t,run.draws,record.locations)
    envelope(record,:event_probabilities,(;rating_event_id,cells,
        observed_canonical=(ya,yb),conditioning=:existing_fitted_effects,
        posterior=B._posterior_summary_rows(values,names;lower=lo,upper=hi,intervals=(interval,),
            reference=0.,rope=nothing,rope_probability_threshold=.95),
        mcse=B._posterior_mcse_rows(values,names,run.controls.chains;probabilities=(lo,.5,hi),parameter_space=:joint_probability),
        diagnostics=diagnostics(t,run,m,record.locations),scientific_acceptance=false))
end

"""`save_report(path, report)` writes portable JSON without overwrite; it contains no replayable posterior."""
function save_report(path::AbstractString,report)
    (ispath(path) || islink(path)) && throw(ArgumentError("preserve existing report: $path"))
    report.schema=="bayesianmgmfrm.ordinal_association_report.v1" || throw(ArgumentError("wrong report schema"))
    mkpath(dirname(path))
    mktemp(dirname(path)) do tmp,io
        JSON3.write(io,(;schema="bayesianmgmfrm.ordinal_association_json.v1",
            encoding="Nonfinite numbers use explicit objects; missing is null; report only.",data=W.jsonsafe(report)))
        close(io);hardlink(tmp,path)
    end
    path
end
