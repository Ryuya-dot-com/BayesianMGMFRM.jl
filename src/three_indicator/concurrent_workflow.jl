"""Concurrent fitted lifecycle; uses the existing NUTS, diagnostics and MCSE engine."""
module ConcurrentWorkflow
using LinearAlgebra, Statistics, Random, Serialization, JSON3, SHA
import BayesianMGMFRM as B
import ..Concurrent as C
import ..ConcurrentReports as R
import ..ConcurrentCoordinates as K
import ..ThreeIndicatorWorkflow as W
const PLAN_SCHEMA="bayesianmgmfrm.concurrent_fit_plan.v3"
const REPORT_SCHEMA="bayesianmgmfrm.concurrent_posterior_report.v2"
const REPORT_SCHEMAS=(REPORT_SCHEMA,"bayesianmgmfrm.concurrent_posterior_report.v1")
const require=C.require
const POLICY=W.POLICY
const OUTCOMES=("accentedness","comprehension_difficulty","transcription_error")
struct Plan
    record::NamedTuple
end
struct Fit
    plan::Plan
    chains::Vector{NamedTuple}
end
seal(x)=merge(x,(;content_hash=B._cache_hash(x)))
function check_hash(x)
    require(B._cache_hash(Base.structdiff(x,(;content_hash=nothing)))==x.content_hash,"native record content changed")
end
model(t)=(;rows=deepcopy(t.input.rows),source_sha256=t.input.source_sha256,prior=C.prior_spec(t.prior),interaction=t.interaction)
function restore(m)
    base=C.Target(C.Input(m.rows;source_sha256=m.source_sha256);prior=m.prior,interaction=m.interaction)
    if hasproperty(m,:association) || hasproperty(m,:association_log_sd)
        require(hasproperty(m,:association) && hasproperty(m,:association_log_sd) && m.association===:plackett,"incomplete association model")
        return C.AssociationTarget(base;log_sd=m.association_log_sd)
    end
    base
end
model(t::C.AssociationTarget)=merge(model(t.base),(;association=:plackett,association_log_sd=t.log_sd))
B._check_source_fixture_raw_vector(t::Union{C.Target,C.AssociationTarget},q::AbstractVector)=
    require(length(q)==C.L.dimension(t) && all(isfinite,q),"finite concurrent coordinates of the declared size required")
function coordinate_contract(name)
    require(name in (:native,:pair_132),"parameterization must be :native or :pair_132")
    (;name,stored_draws=:sampler,initial_input=:native_model,model_reports=:native_model,
        jitter=:sampler,metric=:sampler,experimental=name===:pair_132)
end
const CHART_WARNING="Experimental pair_132 sampler coordinates: unchanged model/prior; improved mixing or precision is not established."
sampling_target(p,t)=p.record.coordinates.name===:native ? t : K.Target(t)
native_point(p,t,q)=p.record.coordinates.name===:native ? q : K.convert_coordinates(K.Target(t),q)
function execution(c;available_threads=Threads.nthreads(:default))
    B._check_chain_execution(c.chain_execution,c.max_parallel_chains)
    (;mode=c.chain_execution,workers=c.chain_execution===:serial ? 1 :
        min(c.chains,c.max_parallel_chains,available_threads),available_threads,
        rng_partition=:prepared_chain_seeds)
end
function prepare(t;ndraws::Int,warmup::Int,seed,chains::Int=4,target_accept=.9,
        max_depth::Int=10,step_size=.03,init_jitter=.1,initial=nothing,
        chain_execution::Symbol=:serial,max_parallel_chains::Int=chains,parameterization::Symbol=:native)
    C.check_target(t)
    coordinates=coordinate_contract(parameterization)
    kernel=parameterization===:native ? t : K.Target(t)
    require(seed isa Integer && !(seed isa Bool) && 0<=seed<=typemax(Int),"nonnegative Int seed required")
    require(chains>=2 && ndraws>=10,"at least two chains and ten retained draws per chain required")
    step=B._check_fit_controls(ndraws,warmup,chains,step_size)
    accept,energy,jitter=B._check_nuts_controls(target_accept,max_depth,1000.,init_jitter)
    native_initial=initial===nothing ? C.initial(t) : R.point(t,initial)[1]
    q=parameterization===:native ? copy(native_initial) : K.convert_coordinates(kernel,native_initial)
    require(isfinite(C.L.logdensity(kernel,q)),"finite initial density required")
    seeds=rand(MersenneTwister(Int(seed)),0:typemax(Int),chains);require(allunique(seeds),"duplicate chain seeds")
    controls=(;ndraws,warmup,chains,step_size=step,target_accept=accept,max_depth,
        max_energy_error=energy,metric=:diagonal,ad_backend=:analytic,init_jitter=jitter,
        chain_execution,max_parallel_chains)
    Plan(seal((;schema=PLAN_SCHEMA,model=model(t),context=W.context(),policy=POLICY,
        controls,execution=execution(controls),adaptation_plan=B._advancedhmc_adaptation_plan(warmup,:diagonal),
        seed=Int(seed),chain_seeds=seeds,coordinates,native_initial=copy(native_initial),initial=copy(q))))
end
function check_plan(p::Plan)
    x=p.record;check_hash(x)
    require(x.schema==PLAN_SCHEMA && x.context==W.context() && x.policy==POLICY,"plan source/environment/policy differs")
    require(hasproperty(x,:coordinates) && hasproperty(x,:native_initial),"missing coordinate metadata")
    t=restore(x.model);c=x.controls
    require(x.coordinates==coordinate_contract(x.coordinates.name),"coordinate metadata differs")
    kernel=sampling_target(p,t)
    B._check_source_fixture_raw_vector(t,x.native_initial)
    expected=x.coordinates.name===:native ? x.native_initial : K.convert_coordinates(kernel,x.native_initial)
    require(x.initial==expected,"initial coordinate conversion differs")
    require(x.execution==execution(c),"chain execution environment differs")
    require(x.adaptation_plan==B._advancedhmc_adaptation_plan(c.warmup,c.metric),"adaptation schedule differs")
    require(c.chains>=2 && c.ndraws>=10 && length(x.chain_seeds)==c.chains && allunique(x.chain_seeds),"invalid chain layout")
    B._check_fit_controls(c.ndraws,c.warmup,c.chains,c.step_size)
    B._check_nuts_controls(c.target_accept,c.max_depth,c.max_energy_error,c.init_jitter)
    require(c.metric===:diagonal && c.ad_backend===:analytic && c.max_energy_error==1000.,"unsupported sampler policy")
    require(x.chain_seeds==rand(MersenneTwister(x.seed),0:typemax(Int),c.chains),"chain seed schedule differs")
    B._check_source_fixture_raw_vector(t,x.initial)
    require(isfinite(C.L.logdensity(kernel,x.initial)),"initial density is not finite")
    t
end
# The existing observer runs after each adaptation update. Copy metric values
# immediately: the sampler's mutable metric may change at the next window.
function adaptation_observer(c,dimension)
    state=Dict{Symbol,Any}(:metric_change_iterations=>Int[], :observed_iterations=>0,
        :final_inverse_mass=>ones(dimension), :retained_step_size=>nothing, :completed=>false)
    function observe(event)
        if event.phase===:sampling_start
            require(event.metric isa B.AdvancedHMC.DiagEuclideanMetric,"diagonal metric required")
            state[:final_inverse_mass]=copy(event.metric.M⁻¹)
        elseif event.phase===:transition
            stat=event.stat;i=stat.iterations
            require(i==state[:observed_iterations]+1 && stat.is_adapt==(i<=c.warmup),"adaptation observation order differs")
            m=stat.mass_matrix.M⁻¹
            if m!=state[:final_inverse_mass]
                require(i<=c.warmup,"metric changed after warmup")
                push!(state[:metric_change_iterations],i);state[:final_inverse_mass]=copy(m)
            end
            if i>c.warmup
                state[:retained_step_size]===nothing && (state[:retained_step_size]=stat.step_size)
                require(state[:retained_step_size]==stat.step_size,"retained step size changed")
            end
            state[:observed_iterations]=i
        elseif event.phase===:sampling_end
            state[:completed]=true
        end
        nothing
    end
    (;state,observe)
end
adaptation_record(o)=(; (k=>deepcopy(o.state[k]) for k in
    (:metric_change_iterations,:observed_iterations,:final_inverse_mass,:retained_step_size,:completed))...)
function check_adaptation(a,c,plan,dimension)
    require(a.completed && a.observed_iterations==c.warmup+c.ndraws,"incomplete adaptation observation")
    changes=collect(a.metric_change_iterations)
    require(issorted(changes) && allunique(changes) && all(i->i in plan.scheduled_metric_updates,changes),"metric changes outside scheduled windows")
    require(length(a.final_inverse_mass)==dimension && all(x->x isa Real && isfinite(x) && x>0,a.final_inverse_mass),"invalid final inverse mass")
    require(a.retained_step_size isa Real && isfinite(a.retained_step_size) && a.retained_step_size>0,"invalid retained step size")
    isempty(changes) && require(all(==(1),a.final_inverse_mass),"unexplained metric change")
    a
end
function check_chain(p,r,t;full=false)
    check_hash(r);x=p.record;c=x.controls;s=r.run
    require(r.plan_hash==x.content_hash && r.chain isa Int && 1<=r.chain<=c.chains,"chain identity differs")
    require(s.backend===:advancedhmc && s.sampler===:nuts && s.controls.chains==1 &&
        s.controls.rng.seed==x.chain_seeds[r.chain] && s.controls.rng.algorithm===:MersenneTwister &&
        s.controls.rng.replayable && s.controls.gradient_backend===:analytic &&
        s.initial==x.initial && s.split_chains_requested &&
        s.checked==(;rhat_threshold=POLICY.rhat_max,ess_threshold=POLICY.ess_min),"sampler identity differs")
    require(!hasproperty(s.controls,:chain_execution) &&
        all(getproperty(s.controls,k)==getproperty(c,k) for k in keys(c)
            if k ∉ (:chains,:chain_execution,:max_parallel_chains)),"sampler controls differ")
    require(size(s.draws)==(c.ndraws,C.L.dimension(t)) && s.chain_ids==ones(Int,c.ndraws) &&
        s.iterations==collect(1:c.ndraws) && length(s.sampler_stats)==c.ndraws &&
        length(s.warmup_stats)==c.warmup,"incomplete chain or telemetry")
    require(s.controls.adaptation_plan==x.adaptation_plan,"run adaptation plan differs")
    check_adaptation(r.adaptation,c,x.adaptation_plan,C.L.dimension(t))
    require(all(stat->stat.step_size==r.adaptation.retained_step_size,s.sampler_stats),"retained step size record differs")
    require(isfinite(r.sampling_seconds) && r.sampling_seconds>=0,"invalid sampling duration")
    if full
        B._check_generalized_sample_run(sampling_target(p,t),s)
        require([w.iteration for w in s.warmup_stats]==collect(1:c.warmup) &&
            all(w->w.chain==1,s.warmup_stats),"warmup axes differ")
        B._warmup_diagnostic_rows(s.warmup_stats,s.controls,s.backend)
    end
    r
end
function checked(f::Fit;complete=true,full=false)
    t=check_plan(f.plan);ids=[r.chain for r in f.chains]
    require(issorted(ids) && allunique(ids),"ordered unique chain IDs required")
    require(!complete || ids==collect(1:f.plan.record.controls.chains),"complete planned chains required")
    foreach(r->check_chain(f.plan,r,t;full),f.chains);t
end
function execute(p::Plan;directory,progress=false)
    t=check_plan(p);x=p.record
    require(progress isa Union{Bool,B.SamplingProgress},"progress must be Boolean or SamplingProgress")
    progress=progress===true ? B.SamplingProgress() : progress
    require(!(ispath(directory)||islink(directory)),"new fit directory required; preserve previous attempt")
    records=Vector{NamedTuple}(undef,x.controls.chains)
    # Schedule jobs only; each inner serial sampler owns its prepared chain seed.
    schedule=(;mode=x.execution.mode,workers=x.execution.workers,rngs=x.chain_seeds)
    B._with_sampling_progress(progress,x.controls.chains,x.controls.warmup,x.controls.ndraws) do
        mkpath(dirname(abspath(directory)));mkdir(directory)
        B._save_serialized_record(joinpath(directory,"plan.jls"),x)
        B._foreach_sampling_chain(schedule,x.controls.chains,nothing) do chain,unused,cancelled
            stem=joinpath(directory,"chain-$chain")
            observer=adaptation_observer(x.controls,C.L.dimension(t))
            start=time_ns()
            try
                B._save_serialized_record(stem*"-started.jls",(;plan_hash=x.content_hash,chain))
                chain_target=sampling_target(p,x.execution.mode===:threads ? deepcopy(t) : t)
                controls=merge(x.controls,(;chains=1,chain_execution=:serial,max_parallel_chains=1))
                observe=event->begin
                    cancelled===nothing || !cancelled[] || throw(InterruptException())
                    observer.observe(event)
                    if event.phase===:sampling_start
                        B._progress_chain!(progress,chain,x.controls.warmup,x.controls.ndraws)
                    elseif event.phase===:transition && progress isa B.SamplingProgress
                        B._progress_transition!(progress,chain,event.stat.iterations,x.controls.warmup,x.controls.ndraws)
                    end
                    nothing
                end
                run=B._run_generalized_candidate_advancedhmc(chain_target,copy(x.initial);controls...,
                    seed=x.chain_seeds[chain],record_warmup=true,progress=false,
                    _sampling_observer=observe)
                r=seal((;plan_hash=x.content_hash,chain,run,adaptation=adaptation_record(observer),sampling_seconds=(time_ns()-start)/1e9))
                B._save_serialized_record(stem*"-returned.jls",r)
                check_chain(p,r,t;full=true)
                completed=stem*".jls"
                require(!(ispath(completed)||islink(completed)),"completed chain path already exists")
                # Publish the already-validated bytes without a second serialization.
                hardlink(stem*"-returned.jls",completed)
                rm(stem*"-returned.jls");records[chain]=r
            catch err
                B._save_serialized_record(stem*"-failed.jls",(;plan_hash=x.content_hash,chain,message=sprint(showerror,err),adaptation=adaptation_record(observer)))
                rethrow()
            end
        end
    end
    Fit(p,records)
end
function fit(t;directory,progress=false,kwargs...)
    execute(prepare(t;kwargs...);directory,progress)
end
function load(directory;require_complete=true)
    require(require_complete isa Bool,"require_complete must be Boolean")
    p=Plan(open(deserialize,joinpath(directory,"plan.jls")));check_plan(p)
    records=NamedTuple[]
    for c in 1:p.record.controls.chains
        path=joinpath(directory,"chain-$c.jls");isfile(path)||continue
        r=open(deserialize,path);require(r.chain==c,"chain filename differs");push!(records,r)
    end
    f=Fit(p,records);checked(f;complete=require_complete,full=true);f
end
identity(f)=B._cache_hash((;plan=f.plan.record.content_hash,chains=[r.content_hash for r in f.chains]))
function save(path,f::Fit)
    checked(f;complete=false,full=true);B._save_serialized_record(path,f;overwrite=false)
end
function raw_names(t;parameterization=:native)
    coordinate_contract(parameterization)
    reduce(vcat,(["$(k===:pair_q && parameterization===:pair_132 ? :pair_q_132 : k)[$i]" for i in eachindex(v)] for (k,v) in sort(collect(t.blocks);by=x->first(last(x)))))
end
function model_values(t,q)
    z=C.reconstruct(t,q);names=String[];values=Float64[];fixed=Set{String}()
    function add(name,a;constant=false,fixed_rows=Int[])
        for i in CartesianIndices(a)
            n=name*"["*join(Tuple(i),",")*"]";push!(names,n);push!(values,a[i]);(constant || i[1] in fixed_rows)&&push!(fixed,n)
        end
    end
    for key in (:mean,:speaker,:word,:rater,:token,:time,:step,:beta,:word_slope,:rater_slope)
        add(key==:mean ? "effective_cohort_mean" : string(key),getproperty(z,key))
    end
    add("effective_pair",z.pair;constant=t.interaction==:none)
    for c in 1:2;add("l1_$c",z.l1[c];fixed_rows=findall(==(3),C.modeldata(t).rater_group));add("rater_step_$c",z.rater_step[c]);end
    add("sd",z.f.sd);add("step_sd",z.f.step_sd)
    for (b,state) in enumerate(z.f.states)
        cor=state.L*state.L'
        for i in 2:3,j in 1:i-1;add("correlation_$b/$i,$j",[cor[i,j]]);end
    end
    add("pair_sd",z.f.pair_sd;constant=t.interaction==:none)
    if t.interaction==:full
        cor=z.f.pair_state.L*z.f.pair_state.L'
        for i in 2:3,j in 1:i-1;add("pair_correlation_$i,$j",[cor[i,j]]);end
    end
    (;names,values,fixed)
end
raw_names(t::C.AssociationTarget;parameterization=:native)=vcat(raw_names(t.base;parameterization),"ac_log_psi")
function model_values(t::C.AssociationTarget,q)
    native,ell=C.association_point(t,q);r=model_values(t.base,native)
    (;names=vcat(r.names,"ac_log_psi"),values=vcat(r.values,ell),fixed=r.fixed)
end
function draws(t,f;scale=:model,parameters=nothing)
    require(scale in (:raw,:model),"choose :raw or :model coordinates")
    first=scale===:raw ? (;names=raw_names(t;parameterization=f.plan.record.coordinates.name),fixed=Set{String}()) : model_values(t,native_point(f.plan,t,f.chains[1].run.draws[1,:]))
    chosen=parameters===nothing ? first.names : collect(parameters)
    require(!isempty(chosen) && allunique(chosen) && all(n->n in first.names,chosen),"select distinct parameter names")
    ix=[findfirst(==(n),first.names) for n in chosen]
    n=sum(r.run.total_draws for r in f.chains);a=Matrix{Float64}(undef,n,length(ix));i=0
    for chain in f.chains,q in eachrow(chain.run.draws)
        i+=1;a[i,:]=scale===:raw ? q[ix] : model_values(t,native_point(f.plan,t,q)).values[ix]
    end
    (;names=chosen,values=a,fixed=intersect(first.fixed,Set(chosen)))
end
function diagnose(a,names,chains;space,fixed=Set{String}())
    B._candidate_mcmc_diagnostic_rows(a,String.(names),chains;parameter_space=space,
        structurally_fixed_parameters=fixed,split_chains=true,rhat_threshold=POLICY.rhat_max,ess_threshold=POLICY.ess_min)
end
function run_view(f)
    c=f.plan.record.controls
    stats=[merge(s,(;chain=r.chain)) for r in f.chains for s in r.run.sampler_stats]
    warmup=[merge(s,(;chain=r.chain)) for r in f.chains for s in r.run.warmup_stats]
    (;controls=c,sampler_stats=stats,warmup_stats=warmup,backend=:advancedhmc,
        chain_ids=[r.chain for r in f.chains for _ in r.run.chain_ids],
        iterations=[i for r in f.chains for i in r.run.iterations])
end
function diagnostics(f::Fit)
    t=checked(f);c=f.plan.record.controls
    raw=draws(t,f;scale=:raw);rawrows=diagnose(raw.values,raw.names,c.chains;space=:raw_unconstrained)
    m=draws(t,f);run=run_view(f)
    (;coordinates=f.plan.record.coordinates,raw=rawrows,model=diagnose(m.values,m.names,c.chains;space=:effective_model,fixed=m.fixed),
        sampler=[merge(only(r.run.sampler_rows),(;chain=r.chain)) for r in f.chains],
        warmup=B._warmup_diagnostic_rows(run.warmup_stats,c,:advancedhmc),
        thresholds=(;minimum_chains=4),scientific_acceptance=false)
end
function qualify(f::Fit)
    if length(f.chains)!=f.plan.record.controls.chains
        checked(f;complete=false)
        return (;qualified=false,qualification_scope=:incomplete_fit,completed_chains=[r.chain for r in f.chains],
            planned_chains=f.plan.record.controls.chains,focal_precision_qualification=:not_assessed,scientific_acceptance=false)
    end
    B._qualify_experimental_diagnostics(diagnostics(f),run_view(f),
        (;rhat_threshold=POLICY.rhat_max,ess_threshold=POLICY.ess_min),POLICY.bfmi_min)
end
bounds(interval)=B.AdditiveFacets.interval_bounds(interval)
function summary_rows(values,names,chains;interval=.95,space=:effective_model,fixed=Set{String}())
    lo,hi=bounds(interval)
    rows=B._posterior_summary_rows(values,names;lower=lo,upper=hi,intervals=(interval,),reference=0.,rope=nothing,rope_probability_threshold=.95)
    precision=B._posterior_mcse_rows(values,names,chains;probabilities=(lo,.5,hi),parameter_space=space,structurally_fixed_parameters=fixed)
    metrics=diagnose(values,names,chains;space,fixed)
    [(;name=rows[i].parameter,mean=rows[i].mean,sd=rows[i].sd,median=rows[i].median,
        lower=rows[i].lower,upper=rows[i].upper,mcse=precision[i],diagnostics=metrics[i]) for i in eachindex(rows)]
end
function summary(f;scale=:model,parameters=nothing,interval=.95)
    t=checked(f);m=draws(t,f;scale,parameters)
    (;kind=:posterior_parameter_summary,scale,interval,rows=summary_rows(m.values,m.names,f.plan.record.controls.chains;interval,space=scale,fixed=m.fixed),
        source_fit_hash=identity(f),coordinates=f.plan.record.coordinates,meaning=:effective_finite_grid,scientific_acceptance=false)
end
function mcse(f;scale=:model,parameters=nothing,probabilities=(.025,.5,.975))
    t=checked(f);m=draws(t,f;scale,parameters)
    B._posterior_mcse_rows(m.values,m.names,f.plan.record.controls.chains;probabilities,parameter_space=scale,structurally_fixed_parameters=m.fixed)
end
function focal(t;operation=:contrasts,rows=nothing)
    q=C.initial(t)
    if operation===:contrasts
        require(rows===nothing,"contrast rows are fixed by the original protocol")
        d=R.contrast_design(t);template=R.contrasts(t,q)
        evaluate=z->R.contrast_values(t,z,d)
    elseif operation===:observed
        require(rows!==nothing,"select explicit existing rows for posterior probabilities")
        ix=R.indices(rows,C.modeldata(t).N);template=R.observed(t,q;rows=ix)
        evaluate=z->R.observed_values(t,z,ix)
    elseif operation===:eng_reference
        require(rows===nothing,"reference panel does not take row overrides")
        d=R.reference_design(t);template=R.reference(t,q)
        evaluate=z->R.reference_values(t,z,d)
    else
        throw(ArgumentError("unsupported posterior probability operation"))
    end
    (;operation,template,evaluate)
end
function flatten(result,operation)
    names=String[];values=Float64[];units=Symbol[]
    function add(prefix,m)
        for a in 1:3,k in eachindex(m.probabilities[a])
            push!(names,"$prefix/$(OUTCOMES[a])/category[$k]");push!(values,m.probabilities[a][k]);push!(units,:probability)
        end
        for a in 1:2
            push!(names,"$prefix/$(OUTCOMES[a])/expected_score");push!(values,m.expected_ordinal[a]);push!(units,:rating)
        end
        push!(names,"$prefix/correct_probability");push!(values,m.correct_probability);push!(units,:probability)
    end
    if operation===:contrasts
        for (i,r) in enumerate(result),side in (:left,:right,:difference);add("contrast[$i]/$side",getproperty(r,side));end
    elseif operation===:observed
        for r in result;add("event[$(r.target_row)]",r);end
    else
        for (i,r) in enumerate(result.recordings);add("recording[$i]",r);end
        for (i,r) in enumerate(result.speakers);add("speaker_style[$i]",r);end
    end
    (;names,values,units)
end
function focal_draws(t,f,spec)
    first=flatten(spec.evaluate(C.reconstruct(t,native_point(f.plan,t,f.chains[1].run.draws[1,:]))),spec.operation)
    a=Matrix{Float64}(undef,sum(r.run.total_draws for r in f.chains),length(first.names));i=0
    for r in f.chains,q in eachrow(r.run.draws)
        i+=1;a[i,:]=flatten(spec.evaluate(C.reconstruct(t,native_point(f.plan,t,q))),spec.operation).values
    end
    (;names=first.names,units=first.units,values=a)
end
function definitions(template)
    d=R.normalized(template)
    for k in ("content_hash","kind","posterior","scientific_acceptance","point","uncertainty","context","model","model_identity","warnings")
        delete!(d,k)
    end
    stripmeasure(x)=foreach(k->delete!(x,k),("probabilities","correct_probability","expected_ordinal"))
    if haskey(d,"comparisons")
        for x in d["comparisons"],side in ("left","right","difference");delete!(x,side);end
    else
        for key in ("rows","recordings","speakers"),x in get(d,key,[]);stripmeasure(x);end
    end
    d
end
available(x)=x isa Real && isfinite(x)
function posterior(f;operation=:contrasts,rows=nothing,interval=.95)
    t=checked(f);bounds(interval);spec=focal(t;operation,rows);m=focal_draws(t,f,spec)
    rr=summary_rows(m.values,m.names,f.plan.record.controls.chains;interval,space=:conditional_probability)
    estimates=map(rr,m.units) do r,unit
        limit=unit===:probability ? POLICY.probability_mcse_max : POLICY.other_mcse_max
        p=r.mcse;d=r.diagnostics
        precise=p.mcse_status===:available && available(p.mean_mcse) && p.mean_mcse<=limit &&
            all(x->available(x.mcse) && x.mcse<=limit,p.quantiles)
        diagnostic=available(d.rank_normalized_rhat) && d.rank_normalized_rhat<=POLICY.rhat_max &&
            available(d.bulk_ess) && d.bulk_ess>=POLICY.ess_min && available(d.tail_ess) && d.tail_ess>=POLICY.ess_min
        (;r...,unit,mcse_limit=limit,precision_passed=precise,diagnostic_passed=diagnostic)
    end
    full_qualification=qualify(f)
    qualification=(;qualified=full_qualification.qualified,parameter_gate_passed=full_qualification.parameter_gate_passed,
        sampler_gate_passed=full_qualification.sampler_gate_passed,telemetry_complete=full_qualification.telemetry_complete,
        thresholds=full_qualification.thresholds,diagnostics=full_qualification.diagnostics,
        qualification_scope=full_qualification.qualification_scope,focal_precision_qualification=:reported_separately)
    precision=all(r->r.precision_passed,estimates);focal_ok=all(r->r.diagnostic_passed,estimates)
    warnings=filter(x->!startswith(x,"Fixed parameter point:"),collect(spec.template.warnings))
    append!(warnings,f.plan.record.adaptation_plan.warnings)
    f.plan.record.coordinates.experimental && push!(warnings,CHART_WARNING)
    !qualification.qualified && push!(warnings,"Whole-fit numerical diagnostics did not pass; retain this warning when interpreting any focal result.")
    !precision && push!(warnings,"Some focal mean/interval endpoint MCSE values are unavailable or exceed their limits.")
    !focal_ok && push!(warnings,"Some focal convergence diagnostics did not pass.")
    push!(warnings,"Conditional posterior category probabilities; not posterior predictive response intervals or scientific acceptance.")
    body=(;schema=REPORT_SCHEMA,kind="posterior",posterior=true,scientific_acceptance=false,
        model=C.contract(t),source_fit_hash=identity(f),producer=f.plan.record.context,context=W.context(),
        coordinates=f.plan.record.coordinates,controls=f.plan.record.controls,execution=f.plan.record.execution,adaptation_plan=f.plan.record.adaptation_plan,
        adaptation=[(;chain=r.chain,dimension=C.L.dimension(t),r.adaptation...) for r in f.chains],chain_ids=[r.chain for r in f.chains],draws_per_chain=f.plan.record.controls.ndraws,
        definitions=definitions(spec.template),interval,interval_method=:pointwise_equal_tailed,
        conditioning=:joint_draws_existing_effects,rows=estimates,policy=merge(POLICY,(;interval=Float64(interval))),qualification,
        precision_passed=precision,focal_diagnostic_passed=focal_ok,
        numerical_qualified=qualification.qualified && precision && focal_ok,warnings)
    safe=B.Experimental.JointRatings.W.jsonsafe(body);d=R.normalized(safe)
    d["content_hash"]=B._cache_hash(d);check_report(JSON3.read(JSON3.write(d)))
end
function check_report(r)
    C.check_observation_contract(r.model)
    d=R.normalized(r);h=pop!(d,"content_hash",nothing)
    require(R.hashstring(h) && B._cache_hash(d)==h,"posterior report content changed")
    require(r.schema in REPORT_SCHEMAS && r.kind=="posterior" && r.posterior===true && r.scientific_acceptance===false,"unsupported posterior report")
    require(R.hashstring(r.source_fit_hash) && R.hashstring(r.producer.package) && !isempty(r.rows),"posterior source binding required")
    require(r.draws_per_chain==r.controls.ndraws && collect(r.chain_ids)==collect(1:r.controls.chains),"posterior chain layout differs")
    require(r.numerical_qualified===(r.qualification.qualified && r.precision_passed && r.focal_diagnostic_passed),"qualification differs")
    require(r.precision_passed==all(x->x.precision_passed,r.rows) && r.focal_diagnostic_passed==all(x->x.diagnostic_passed,r.rows),"focal flags differ")
    require(!isempty(r.warnings) && allunique([x.name for x in r.rows]),"warnings and unique quantities required")
    require(R.normalized(r.policy)==R.normalized(merge(POLICY,(;interval=Float64(r.interval)))),"precision/diagnostic policy differs")
    bounds(r.interval)
    if r.schema==REPORT_SCHEMA
        require(hasproperty(r,:coordinates),"missing coordinate metadata")
        require(R.normalized(r.coordinates)==R.normalized(coordinate_contract(Symbol(r.coordinates.name))),"report coordinate metadata differs")
        if r.coordinates.experimental
            require(r.model.interaction=="full" && CHART_WARNING in r.warnings,"experimental chart scope/warning differs")
        end
    else
        require(!hasproperty(r,:coordinates),"legacy report cannot carry new coordinate metadata")
    end
    if hasproperty(r,:execution)
        c=r.controls;e=r.execution
        require(e.available_threads isa Integer && e.available_threads>=1 &&
            c.max_parallel_chains isa Integer && c.max_parallel_chains>=1,"invalid execution limits")
        expected=execution((;chains=c.chains,chain_execution=Symbol(c.chain_execution),
            max_parallel_chains=Int(c.max_parallel_chains));available_threads=Int(e.available_threads))
        require(R.normalized(e)==R.normalized(expected),"report chain execution differs")
    else
        require(!hasproperty(r.controls,:chain_execution) && !hasproperty(r.controls,:max_parallel_chains),"missing execution metadata")
    end
    if hasproperty(r,:adaptation_plan) || hasproperty(r,:adaptation)
        require(hasproperty(r,:adaptation_plan) && hasproperty(r,:adaptation),"partial adaptation metadata")
        p=r.adaptation_plan
        require(p.warmup==r.controls.warmup && p.metric==r.controls.metric &&
            p.mass_matrix_adaptation==!isempty(p.scheduled_metric_updates),"adaptation plan/control mismatch")
        require(all(w->w in r.warnings,p.warnings),"adaptation warning lost")
        require([a.chain for a in r.adaptation]==collect(r.chain_ids),"adaptation chain IDs differ")
        foreach(a->check_adaptation(a,r.controls,p,a.dimension),r.adaptation)
    end
    for x in r.rows
        limit=x.unit=="probability" ? POLICY.probability_mcse_max : POLICY.other_mcse_max
        require(x.unit in ("probability","rating") && x.mcse_limit==limit,"quantity units or precision limit differs")
        require(all(available,(x.mean,x.sd,x.median,x.lower,x.upper)) && x.sd>=0 && x.lower<=x.median<=x.upper,"invalid posterior summary")
        p=x.mcse;d=x.diagnostics
        precise=p.mcse_status=="available" && available(p.mean_mcse) && p.mean_mcse<=limit && all(y->available(y.mcse) && y.mcse<=limit,p.quantiles)
        diagnostic=available(d.rank_normalized_rhat) && d.rank_normalized_rhat<=POLICY.rhat_max && available(d.bulk_ess) && d.bulk_ess>=POLICY.ess_min && available(d.tail_ess) && d.tail_ess>=POLICY.ess_min
        require(x.precision_passed===precise && x.diagnostic_passed===diagnostic,"row qualification differs")
        require(p.n_chains==r.controls.chains && p.draws_per_chain==r.controls.ndraws,"precision chain layout differs")
    end
    r
end
function save_report(path,r)
    check_report(r);require(!(ispath(path)||islink(path)),"preserve existing report")
    mkpath(dirname(abspath(path)))
    mktemp(dirname(abspath(path))) do temporary,io
        JSON3.write(io,r);close(io);hardlink(temporary,path)
    end
    (;path=abspath(path),sha256=bytes2hex(sha256(read(path))))
end
function plan_report(p::Plan)
    t=check_plan(p);c=p.record.controls;m=model_values(t,p.record.native_initial)
    (;kind=:prepared_plan,model=C.contract(t),coordinates=p.record.coordinates,controls=c,execution=p.record.execution,adaptation_plan=p.record.adaptation_plan,source=p.record.context,
        chain_seeds=copy(p.record.chain_seeds),initialization=:seeded_normal_jitter_about_declared_point,
        raw_draw_bytes=8*c.ndraws*c.chains*C.L.dimension(t),model_summary_workspace_bytes=8*c.ndraws*c.chains*length(m.names),
        contrast_workspace_bytes=8*c.ndraws*c.chains*552,
        reference_workspace_bytes=8*c.ndraws*c.chains*23*length(findall(==(1),C.modeldata(t).speaker_cell))*(C.modeldata(t).W+1),
        warnings=vcat(p.record.adaptation_plan.warnings,p.record.coordinates.experimental ? [CHART_WARNING] : String[],["Byte counts cover dense numeric arrays, not total peak RAM or archives.",
            "Initialization jitter is not a guarantee of exploration across posterior modes.",
            "The declared design, linking assumptions and priors still need empirical assessment."]),scientific_acceptance=false)
end
end
