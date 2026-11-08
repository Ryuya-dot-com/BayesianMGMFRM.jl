"""Private no-state workflow; loading/planning/reporting never runs transitions.

Native archives bind complete coordinates, telemetry and the original environment.
Artificial runners cannot create posterior evidence. No public API registration.
"""
module ThreeIndicatorWorkflow
using BayesianMGMFRM, JSON3, SHA, Serialization, LinearAlgebra, Statistics
include("three_indicator_observation.jl")
const M=ThreeIndicatorObservation
const B=BayesianMGMFRM
const POLICY=(;rhat_max=1.01,ess_min=400.,bfmi_min=.3,interval=.95,
    probability_mcse_max=.005,other_mcse_max=.02)
const SCHEMA="bayesianmgmfrm.three_indicator_workflow.v1"
const BLOCKS=("speaker","word","rater","token","time","l1")
digest(p)=bytes2hex(sha256(read(p)))
seal(x)=merge(x,(;content_hash=B._cache_hash(x)))
require(x,msg)=x || throw(ArgumentError(msg))
finite(x)=x isa Real && !(x isa Bool) && isfinite(x)
positive(x)=finite(x) && x>0
function check_hash(x)
    require(B._cache_hash(Base.structdiff(x,(;content_hash=nothing)))==x.content_hash,"record checksum mismatch")
end
function context()
    project=Base.active_project();require(project!==nothing,"explicit environment required")
    manifest=joinpath(dirname(project),"Manifest.toml");require(isfile(manifest),"retained Manifest required")
    root=dirname(dirname(pathof(B)))
    sources=sort([joinpath(d,f) for branch in ("src","ext") for (d,_,fs) in walkdir(joinpath(root,branch)) for f in fs if endswith(f,".jl")])
    (;julia=string(VERSION),kernel=string(Sys.KERNEL),arch=string(Sys.ARCH),
      threads=Threads.nthreads(),blas_threads=BLAS.get_num_threads(),
      project=digest(project),manifest=digest(manifest),
      package=B._cache_hash([(;path=relpath(f,root),sha256=digest(f)) for f in sources]),
      sources=[(;path=f,sha256=digest(joinpath(@__DIR__,f))) for f in
        ("three_indicator_observation.jl","mgmfrm_lkj_cholesky_candidate.jl","three_indicator_workflow.jl")])
end
B._check_source_fixture_raw_vector(t::M.Target,q::AbstractVector)=M.reconstruct(t,q)

# Inspect the complete gradient after ForwardDiff has assembled every chunk.
struct FiniteGradient{T}
    target::T
end
M.L.dimension(t::FiniteGradient)=M.L.dimension(t.target)
M.L.capabilities(::Type{<:FiniteGradient})=M.L.LogDensityOrder{1}()
function M.L.logdensity_and_gradient(t::FiniteGradient,q::AbstractVector)
    value,gradient=M.L.logdensity_and_gradient(t.target,q)
    if !isfinite(value) || !all(isfinite,gradient)
        return oftype(value,-Inf),zero(gradient)
    end
    value,gradient
end
M.L.logdensity(t::FiniteGradient,q::AbstractVector)=first(M.L.logdensity_and_gradient(t,q))
function B._logdensity_gradient_target(t::M.Target,q::AbstractVector,backend::Symbol)
    result=invoke(B._logdensity_gradient_target,Tuple{Any,AbstractVector,Symbol},t,q,backend)
    merge(result,(;target=FiniteGradient(result.target)))
end

function prepare(input;controls,initial_points,chain_seeds,focal,fixture=false,prior=M.REFERENCE_PRIOR)
    require(fixture isa Bool,"fixture must be Boolean")
    plan=seal((;schema=SCHEMA,kind=fixture ? :deterministic_fixture : :posterior,
        input_json=JSON3.write(input),prior=M.resolve_prior(prior),context=context(),policy=POLICY,
        controls=deepcopy(controls),initial_points=deepcopy(initial_points),
        chain_seeds=copy(chain_seeds),focal=deepcopy(focal)))
    check_plan(plan);plan
end
function check_plan(plan)
    check_hash(plan)
    require(plan.schema==SCHEMA && plan.kind in (:deterministic_fixture,:posterior),"unsupported plan")
    require(plan.context==context() && plan.policy==POLICY,"source/environment/policy changed")
    input=JSON3.read(plan.input_json)
    B.Experimental.ThreeIndicator.inspect_input(input)
    t=M.Target(input;prior=plan.prior);d=t.data;c=plan.controls
    require(keys(c)==(:ndraws,:warmup,:step_size,:target_accept,:max_depth,:metric,:ad_backend),"unexpected sampler controls")
    require(all(x->x isa Int,(c.ndraws,c.warmup,c.max_depth)) && c.ndraws>=10,"invalid iteration controls")
    B._check_fit_controls(c.ndraws,c.warmup,1,c.step_size)
    B._check_nuts_controls(c.target_accept,c.max_depth,1000.,0.)
    require(c.metric===:diagonal && c.ad_backend===:ForwardDiff,"first workflow uses diagonal ForwardDiff NUTS")
    require(length(plan.initial_points)==length(plan.chain_seeds)==4 &&
        length(unique(plan.initial_points))==length(unique(plan.chain_seeds))==4 &&
        all(s->s isa Int && s>=0,plan.chain_seeds),"four distinct starts/seeds required")
    for q in plan.initial_points
        require(q isa Vector{Float64} && isfinite(M.L.logdensity(t,q)),"invalid initial coordinates")
    end
    f=plan.focal
    require(keys(f)==(:panel_label,:events,:weights,:speaker_pairs,:listener_pairs),"unexpected focal fields")
    require(f.panel_label isa String && !isempty(f.panel_label),"named fixed panel required")
    require(!isempty(f.events) && all(e->e isa Int && 1<=e<=d.N,f.events) && length(unique(f.events))==length(f.events),"invalid panel events")
    require(length(f.events)==length(f.weights) && all(w->finite(w)&&w>=0,f.weights) &&
        isapprox(sum(f.weights),1.;atol=1e-12,rtol=0),"invalid fixed panel weights")
    require(!isempty(f.speaker_pairs) && !isempty(f.listener_pairs),"declare speaker and listener contrasts")
    for p in f.speaker_pairs
        require(keys(p)==(:label,:left,:right) && p.label isa String && !isempty(p.label) &&
            all(s->s isa Int && 1<=s<=d.S,(p.left,p.right)) && p.left!=p.right,"invalid speaker contrast")
    end
    for p in f.listener_pairs
        require(keys(p)==(:label,:left,:right,:l1,:time) && p.label isa String && !isempty(p.label) &&
            all(r->r isa Int && 1<=r<=d.R,(p.left,p.right)) && p.left!=p.right &&
            p.l1 isa Int && 1<=p.l1<=3 && finite(p.time),"invalid listener contrast")
    end
    require(length(unique([p.label for p in f.speaker_pairs]))==length(f.speaker_pairs) &&
        length(unique([p.label for p in f.listener_pairs]))==length(f.listener_pairs),"duplicate contrast labels")
    t
end
function run_controls(p,c)
    s=p.controls
    (;ndraws=s.ndraws,warmup=s.warmup,chains=1,step_size=Float64(s.step_size),
      target_accept=Float64(s.target_accept),max_depth=s.max_depth,max_energy_error=1000.,
      metric=s.metric,ad_backend=s.ad_backend,gradient_backend=:ad,
      rng=(;algorithm=:MersenneTwister,seed=p.chain_seeds[c],replayable=true),init_jitter=0.)
end
function check_chain(p,r;t=check_plan(p))
    check_hash(r)
    require(r.schema==SCHEMA && r.kind===p.kind && r.plan_hash==p.content_hash && r.chain isa Int && 1<=r.chain<=4,"chain identity differs")
    s=r.run
    require(s.controls==run_controls(p,r.chain) && s.initial==p.initial_points[r.chain] &&
        s.backend===:advancedhmc && s.sampler===:nuts && s.split_chains_requested===true &&
        s.checked==(;rhat_threshold=POLICY.rhat_max,ess_threshold=POLICY.ess_min),"sampler provenance differs")
    B._check_generalized_sample_run(t,s)
    require(s.warmup_stats isa AbstractVector && length(s.warmup_stats)==p.controls.warmup,"complete warmup telemetry required")
    require([w.iteration for w in s.warmup_stats]==collect(1:p.controls.warmup) &&
        all(w->w.chain==1 && w.divergent isa Bool && w.nonfinite_logdensity isa Bool && w.tree_depth isa Int,s.warmup_stats),"invalid warmup axes/telemetry")
    B._warmup_diagnostic_rows(s.warmup_stats,s.controls,s.backend)
    require(all(a->a.numerical_error isa Bool && a.tree_depth isa Int && a.tree_depth>=0 && a.n_steps isa Int && a.n_steps>=0,s.sampler_stats),"invalid retained telemetry")
    require(M.L.logdensity(t,s.initial)==s.initial_logdensity,"initial density differs in original environment")
    # AdvancedHMC stores the AD value; ordinary Float64 evaluation can round differently.
    # Keep the generic direct-density check above and exact equality on the producing path.
    density = if p.kind===:posterior
        ad=B._logdensity_gradient_target(t,s.initial,s.controls.ad_backend).target
        q->first(M.L.logdensity_and_gradient(ad,collect(q)))
    else
        q->M.L.logdensity(t,q)
    end
    require(all(density(q)==v for (q,v) in zip(eachrow(s.draws),s.logdensities)),
        "density differs on original producing path")
    require(finite(r.sampling_seconds) && r.sampling_seconds>=0,"invalid runtime")
    r
end

"""Four serial chains; retain completed/returned/failed records. Never resume MCMC.

An explicit posterior plan and sampling_authorized=true are required for the
real runner. An injected runner only accepts an artificial plan, regardless of
that flag. This is an execution boundary, not a request for renewed user approval.
"""
function run_chains(p,directory;sampling_authorized=false,_runner=B._run_generalized_candidate_advancedhmc)
    fixture=_runner!==B._run_generalized_candidate_advancedhmc
    require(p.kind== (fixture ? :deterministic_fixture : :posterior),"runner and plan kind differ")
    require(fixture || sampling_authorized===true,"sampling not enabled for this call")
    t=check_plan(p);require(Threads.nthreads()==BLAS.get_num_threads()==1,"one Julia/BLAS thread required")
    require(!(ispath(directory)||islink(directory)),"new directory required; preserve prior attempt")
    mkpath(dirname(directory));mkdir(directory)
    B._save_serialized_record(joinpath(directory,"plan.jls"),p)
    records=NamedTuple[]
    for c in 1:4
        path=joinpath(directory,"chain-$c")
        B._save_serialized_record(path*"-started.jls",(;plan_hash=p.content_hash,chain=c,kind=p.kind))
        start=time_ns()
        try
            run=_runner(t,copy(p.initial_points[c]);p.controls...,chains=1,max_energy_error=1000.,
                seed=p.chain_seeds[c],init_jitter=0.,split_chains=true,rhat_threshold=POLICY.rhat_max,
                ess_threshold=POLICY.ess_min,progress=false,record_warmup=true)
            r=seal((;schema=SCHEMA,kind=p.kind,plan_hash=p.content_hash,chain=c,run,sampling_seconds=(time_ns()-start)/1e9))
            B._save_serialized_record(path*"-returned.jls",r);check_chain(p,r;t)
            B._save_serialized_record(path*".jls",r);push!(records,r)
        catch err
            B._save_serialized_record(path*"-failed.jls",(;plan_hash=p.content_hash,chain=c,message=sprint(showerror,err)))
            rethrow()
        end
    end
    (;plan=p,chains=records)
end
function load_completed(directory;require_complete=true)
    p=open(deserialize,joinpath(directory,"plan.jls"));t=check_plan(p);records=NamedTuple[]
    for c in 1:4
        path=joinpath(directory,"chain-$c.jls");isfile(path)||continue
        r=check_chain(p,open(deserialize,path);t);require(r.chain==c,"chain filename differs")
        push!(records,r)
    end
    require(!require_complete || length(records)==4,"four complete chains required")
    (;plan=p,chains=records)
end

"""Named original-model coordinates; only known algebraic constants are exempt."""
function model_values(t,q,z=M.reconstruct(t,q))
    names=String[];values=Float64[];fixed=Set{String}()
    function add(name,a;constant=false)
        for i in CartesianIndices(a)
            label=name*"["*join(Tuple(i),",")*"]"
            push!(names,label);push!(values,a[i]);constant && push!(fixed,label)
        end
    end
    for k in (:speaker,:word,:rater,:token,:time,:word_slope,:rater_slope,:step,:intercept,:beta,:sd,:step_sd)
        add(string(k),getproperty(z,k))
    end
    for c in 1:2;add("l1_$c",z.l1[c]);add("rater_step_$c",z.rater_step[c]);end
    add("cohort_reference",z.cohort[1,:];constant=true);add("cohort",z.cohort[2:end,:])
    add("binary_step",[0.];constant=true)
    for b in 1:6
        cov=Diagonal(z.sd[:,b])*z.states[b].R*Diagonal(z.sd[:,b])
        add("covariance_"*BLOCKS[b],[cov[i,j] for j in 1:3 for i in j:3])
        add("correlation_"*BLOCKS[b],[z.states[b].R[i,j] for j in 1:2 for i in j+1:3])
    end
    (;names,values,fixed)
end
function focal_values(t,p,q,z=M.reconstruct(t,q))
    d=t.data;f=p.focal;rows=NamedTuple[]
    add(name,value,scale)=push!(rows,(;name,value=Float64(value),scale,
        mcse_limit=scale===:probability ? POLICY.probability_mcse_max : POLICY.other_mcse_max))
    probs=exp.(M.category_logprobs(t,q,z));avg=vec(f.weights'*probs[f.events,:])
    for a in 1:3
        offset=(0,9,18)[a]
        for k in 1:d.K[a];add("panel_probability[$a,$k]",avg[offset+k],:probability);end
        a<=2 && add("panel_expected_rating[$a]",dot(1:9,avg[offset+1:offset+9]),:rating)
    end
    add("panel_correct_probability",avg[19],:probability)
    condition(s,a)=d.speaker_cell[s]==1 ? 0. : z.beta[d.speaker_cell[s]-1,a]
    for pair in f.speaker_pairs,a in 1:3
        l,r=pair.left,pair.right
        add("speaker/$(pair.label)/$a",z.speaker[l,a]+condition(l,a)-z.speaker[r,a]-condition(r,a),:location)
    end
    for pair in f.listener_pairs,a in 1:3
        l,r=pair.left,pair.right
        value=z.rater[l,a]-z.rater[r,a]+z.cohort[d.rater_group[l],a]-z.cohort[d.rater_group[r],a]+
            pair.time*(z.time[l,a]-z.time[r,a])+sum(d.l1_contrast[pair.l1,c]*(z.l1[c][l,a]-z.l1[c][r,a]) for c in 1:2)
        add("listener/$(pair.label)/$a",value,:location)
    end
    for b in 1:6,j in 1:2,i in j+1:3
        add("correlation/$(BLOCKS[b])/$i,$j",z.states[b].R[i,j],:correlation)
    end
    rows
end
diagnostic_ok(d)=positive(d.rank_normalized_rhat) && d.rank_normalized_rhat<=POLICY.rhat_max &&
    positive(d.bulk_ess) && d.bulk_ess>=POLICY.ess_min && positive(d.tail_ess) && d.tail_ess>=POLICY.ess_min
function sampler_row(record)
    s=record.run
    fields=(:acceptance_rate,:log_density,:hamiltonian_energy,:hamiltonian_energy_error,:max_hamiltonian_energy_error,:step_size,:nom_step_size)
    invalid=count(a->any(k->!finite(getproperty(a,k)),fields) || !(positive(a.step_size)&&positive(a.nom_step_size)),s.sampler_stats)
    merge(only(s.sampler_rows),(;chain=record.chain,n_invalid_sampler_values=invalid))
end
function report(saved)
    p=saved.plan;t=check_plan(p)
    require(length(saved.chains)==4 && [c.chain for c in saved.chains]==collect(1:4),"four ordered complete chains required")
    foreach(c->check_chain(p,c;t),saved.chains)
    raw=reduce(vcat,[c.run.draws for c in saved.chains]);n=size(raw,1)
    first_model=model_values(t,raw[1,:]);first_focal=focal_values(t,p,raw[1,:])
    model=Matrix{Float64}(undef,n,length(first_model.values));focal=Matrix{Float64}(undef,n,length(first_focal))
    for i in 1:n
        q=view(raw,i,:);z=M.reconstruct(t,q)
        model[i,:]=model_values(t,q,z).values;focal[i,:]=getproperty.(focal_values(t,p,q,z),:value)
    end
    diagnose(a,names,space;fixed=Set{String}())=B._candidate_mcmc_diagnostic_rows(a,names,4;
        parameter_space=space,structurally_fixed_parameters=fixed,split_chains=true,
        rhat_threshold=POLICY.rhat_max,ess_threshold=POLICY.ess_min)
    primitive=diagnose(raw,["q[$j]" for j in axes(raw,2)],:primitive)
    original=diagnose(model,first_model.names,:original_model;fixed=first_model.fixed)
    rows=map(eachindex(first_focal)) do j
        info=first_focal[j]
        s=B.posterior_contrast(focal[:,j],zeros(n);chains=4,interval=POLICY.interval)
        precision=s.precision
        ok=finite(precision.mean_mcse) && 0<=precision.mean_mcse<=info.mcse_limit &&
            all(a->finite(a.mcse) && 0<=a.mcse<=info.mcse_limit,precision.quantiles[[1,3]])
        (;name=info.name,scale=info.scale,mcse_limit=info.mcse_limit,
            mean=s.mean,sd=s.sd,median=s.median,lower=s.lower,upper=s.upper,
            precision,diagnostics=s.contrast_diagnostics,precision_passed=ok,diagnostic_passed=diagnostic_ok(s.contrast_diagnostics))
    end
    sampler=sampler_row.(saved.chains)
    warmup=[merge(only(B._warmup_diagnostic_rows(c.run.warmup_stats,c.run.controls,c.run.backend)),(;chain=c.chain)) for c in saved.chains]
    parameters=all(d->!d.quality_gate_applicable||diagnostic_ok(d),[primitive;original]) && all(r->r.diagnostic_passed,rows)
    telemetry=all(s->s.n_nonfinite_logdensity==0 && s.n_divergences==0 && s.n_invalid_sampler_values==0 && positive(s.e_bfmi) && s.e_bfmi>=POLICY.bfmi_min,sampler)
    precision=all(r->r.precision_passed,rows)
    seal((;schema=SCHEMA,kind=p.kind,posterior=p.kind===:posterior,plan_hash=p.content_hash,
        chain_hashes=[c.content_hash for c in saved.chains],context=p.context,policy=POLICY,
        focal_definitions=p.focal,labels=t.data.labels,metadata=t.data.metadata,prior=M.prior_record(t.prior),
        conditioning=:fixed_existing_event_panel,identification=:not_established_by_fixed_design_rank,
        interval_method=:pointwise_equal_tailed,correlations=:marginal_pre_projection,
        numerical_qualified=p.kind===:posterior && parameters && telemetry && precision,
        parameter_passed=parameters,sampler_passed=telemetry,precision_passed=precision,
        statistical_acceptance=false,public_api=true,primitive,original,rows,sampler,warmup,
        listener_support=B.Experimental.ThreeIndicator._listener_support(t.data,p.focal),
        n_max_treedepth=sum(s.n_max_treedepth for s in sampler),
        chain_ids=repeat(1:4;inner=p.controls.ndraws),iterations=repeat(1:p.controls.ndraws;outer=4),
        sampling_seconds=[c.sampling_seconds for c in saved.chains]))
end
function save_report(path,r)
    check_hash(r);require(!(ispath(path)||islink(path)),"preserve existing report")
    mkpath(dirname(path))
    mktemp(dirname(path)) do tmp,io
        write(io,JSON3.write(B._json_export_value(r))*"\n");close(io);hardlink(tmp,path)
    end
    (;path=abspath(path),sha256=digest(path),kind=r.kind,content_hash=r.content_hash)
end
end
