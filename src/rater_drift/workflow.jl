"""RW1 chain execution and restoration. Loading, planning and reporting never sample.

Injected runners always require an artificial plan. Native records preserve
completed chains and returned invalid outputs; they are not restart checkpoints.
"""
module RaterDriftWorkflow
using Serialization, LinearAlgebra, Statistics
const R=parentmodule(@__MODULE__).RaterDriftRecords
const M=R.M
const B=R.B
const POLICY=(;rhat_max=1.01,bulk_ess_min=400.,tail_ess_min=400.,bfmi_min=.3)
const PLAN_SCHEMA="bayesianmgmfrm.rw1_chain_plan.v1"
const CHAIN_SCHEMA="bayesianmgmfrm.rw1_chain.v1"
B._check_source_fixture_raw_vector(t::M.Target,q::AbstractVector)=M.coordinates(t,q)

function check_hash(r)
    B._cache_hash(Base.structdiff(r,(;content_hash=nothing)))==r.content_hash ||
        throw(ArgumentError("record checksum mismatch"))
end
finite(x)=x isa Real && !(x isa Bool) && isfinite(x)
positive(x)=finite(x) && x>0

"""Bind explicit controls, distinct starts/seeds and named contrasts before fitting.

Precision limits are caller-declared absolute MCSE limits in severity units;
they are not adopted scientific defaults. No outcome/truth generator is invoked.
"""
function prepare(t;controls,initial_points,chain_seeds,reference,panel_weights,
        epsilon,interval,precision,fixture=false)
    fixture isa Bool || throw(ArgumentError("invalid fixture flag"))
    plan=R.seal((;schema=PLAN_SCHEMA,kind=fixture ? :deterministic_fixture : :posterior,
        target=R.target_record(t),context=R.context(),workflow_sha256=R.digest(@__FILE__),
        controls=deepcopy(controls),initial_points=deepcopy(initial_points),
        chain_seeds=copy(chain_seeds),reference,panel_weights=copy(panel_weights),
        epsilon,interval,precision,policy=POLICY))
    check_plan(plan);plan
end

function check_plan(plan)
    plan.schema==PLAN_SCHEMA && plan.kind in (:posterior,:deterministic_fixture) ||
        throw(ArgumentError("unsupported chain plan"))
    check_hash(plan)
    plan.context==R.context() && plan.workflow_sha256==R.digest(@__FILE__) ||
        throw(ArgumentError("source or original environment changed"))
    plan.policy==POLICY || throw(ArgumentError("diagnostic policy changed"))
    t=R.target(plan.target);c=plan.controls
    keys(c)==(:ndraws,:warmup,:step_size,:target_accept,:max_depth,:metric,:ad_backend) ||
        throw(ArgumentError("unexpected sampler controls"))
    all(x->x isa Int,(c.ndraws,c.warmup,c.max_depth)) && c.ndraws>=10 &&
        finite(c.step_size) && finite(c.target_accept) || throw(ArgumentError("invalid sampler controls"))
    B._check_fit_controls(c.ndraws,c.warmup,1,c.step_size)
    B._check_nuts_controls(c.target_accept,c.max_depth,1000.,0.)
    c.metric===:diagonal && c.ad_backend===:ForwardDiff ||
        throw(ArgumentError("this connection uses diagonal ForwardDiff NUTS"))
    length(plan.initial_points)==length(plan.chain_seeds)==4 &&
        all(s->s isa Int && s>=0,plan.chain_seeds) && length(unique(plan.chain_seeds))==4 &&
        length(unique(plan.initial_points))==4 || throw(ArgumentError("four distinct starts/seeds required"))
    for q in plan.initial_points
        q isa Vector{Float64} && isfinite(M.L.logdensity(t,q)) || throw(ArgumentError("invalid initial point"))
    end
    plan.reference isa String && plan.reference in t.time_labels || throw(ArgumentError("unknown reference label"))
    finite(plan.interval) && 0<plan.interval<1 && positive(plan.epsilon) ||
        throw(ArgumentError("invalid interval or practical tolerance"))
    length(plan.panel_weights)==t.R && all(w->finite(w) && w>=0,plan.panel_weights) &&
        isapprox(sum(plan.panel_weights),1.;atol=1e-12,rtol=0) || throw(ArgumentError("invalid fixed panel weights"))
    keys(plan.precision)==(:mean_mcse_max,:endpoint_mcse_max) && all(positive,plan.precision) ||
        throw(ArgumentError("declare positive absolute focal MCSE limits"))
    t
end

function run_controls(plan,c)
    p=plan.controls
    (;ndraws=p.ndraws,warmup=p.warmup,chains=1,step_size=Float64(p.step_size),
      target_accept=Float64(p.target_accept),max_depth=p.max_depth,max_energy_error=1000.,
      metric=p.metric,ad_backend=p.ad_backend,gradient_backend=B._gradient_backend_kind(p.ad_backend),
      rng=(;algorithm=:MersenneTwister,seed=plan.chain_seeds[c],replayable=true),init_jitter=0.)
end

function check_chain(plan,record;t=check_plan(plan))
    check_hash(record)
    record.schema==CHAIN_SCHEMA && record.kind===plan.kind && record.plan_hash==plan.content_hash &&
        record.chain isa Int && 1<=record.chain<=4 || throw(ArgumentError("chain/plan identity differs"))
    c=record.chain;r=record.run
    r.controls==run_controls(plan,c) && r.initial==plan.initial_points[c] &&
        r.backend===:advancedhmc && r.sampler===:nuts && r.split_chains_requested===true &&
        r.checked==(;rhat_threshold=POLICY.rhat_max,ess_threshold=POLICY.bulk_ess_min) ||
        throw(ArgumentError("seed, start, controls or sampler differs"))
    B._check_generalized_sample_run(t,r)
    r.warmup_stats isa AbstractVector || throw(ArgumentError("warmup telemetry required"))
    B._warmup_diagnostic_rows(r.warmup_stats,r.controls,r.backend)
    all(s->s.numerical_error isa Bool && s.tree_depth isa Int && s.tree_depth>=0 &&
        s.n_steps isa Int && s.n_steps>=0,r.sampler_stats) || throw(ArgumentError("invalid retained telemetry"))
    # Same-environment restoration must preserve the exact target evaluation.
    M.L.logdensity(t,r.initial)==r.initial_logdensity &&
        all(M.L.logdensity(t,q)==v for (q,v) in zip(eachrow(r.draws),r.logdensities)) ||
        throw(ArgumentError("stored densities differ in the original environment"))
    finite(record.sampling_seconds) && record.sampling_seconds>=0 || throw(ArgumentError("invalid runtime"))
    record
end

"""Run four serial chains in a new directory, with no retries or draw extension.

Actual execution requires a posterior plan and sampling_authorized=true. A test
runner requires an artificial plan even if the authorization flag is supplied.
Use load_completed after a failure; this function never resumes a partial run.
"""
function run_chains(plan,directory;sampling_authorized=false,
        _runner=B._run_generalized_candidate_advancedhmc)
    fixture=_runner!==B._run_generalized_candidate_advancedhmc
    plan.kind== (fixture ? :deterministic_fixture : :posterior) ||
        throw(ArgumentError("runner and plan kind differ"))
    fixture || sampling_authorized===true || throw(ArgumentError("sampling is not authorized by this call"))
    t=check_plan(plan)
    Threads.nthreads()==1 && BLAS.get_num_threads()==1 || throw(ArgumentError("one Julia/BLAS thread required"))
    (ispath(directory) || islink(directory)) && throw(ArgumentError("use a new directory; no automatic retry"))
    mkpath(dirname(directory));mkdir(directory)
    B._save_serialized_record(joinpath(directory,"plan.jls"),plan;overwrite=false)
    records=NamedTuple[]
    for c in 1:4
        prefix=joinpath(directory,"chain-$c")
        B._save_serialized_record(prefix*"-started.jls",(;plan_hash=plan.content_hash,chain=c,kind=plan.kind))
        started=time_ns()
        try
            p=plan.controls
            run=_runner(t,copy(plan.initial_points[c]);p...,chains=1,max_energy_error=1000.,
                seed=plan.chain_seeds[c],init_jitter=0.,split_chains=true,
                rhat_threshold=POLICY.rhat_max,ess_threshold=POLICY.bulk_ess_min,
                progress=false,record_warmup=true)
            record=R.seal((;schema=CHAIN_SCHEMA,kind=plan.kind,plan_hash=plan.content_hash,
                chain=c,run,sampling_seconds=(time_ns()-started)/1e9))
            B._save_serialized_record(prefix*"-returned.jls",record;overwrite=false)
            check_chain(plan,record;t)
            B._save_serialized_record(prefix*".jls",record;overwrite=false)
            push!(records,record)
        catch err
            B._save_serialized_record(prefix*"-failed.jls",
                (;plan_hash=plan.content_hash,chain=c,message=sprint(showerror,err));overwrite=false)
            rethrow()
        end
    end
    (;plan,chains=records)
end

function load_completed(directory;require_complete=true)
    plan=open(deserialize,joinpath(directory,"plan.jls"));t=check_plan(plan)
    records=NamedTuple[]
    for c in 1:4
        path=joinpath(directory,"chain-$c.jls")
        isfile(path) || continue
        r=check_chain(plan,open(deserialize,path);t)
        r.chain==c || throw(ArgumentError("chain filename/identity differs"))
        push!(records,r)
    end
    require_complete && length(records)!=4 && throw(ArgumentError("four completed chains required"))
    (;plan,chains=records)
end

diagnostic_ok(d)=positive(d.rank_normalized_rhat) && d.rank_normalized_rhat<POLICY.rhat_max &&
    positive(d.bulk_ess) && d.bulk_ess>=POLICY.bulk_ess_min &&
    positive(d.tail_ess) && d.tail_ess>=POLICY.tail_ess_min
function sampler_summary(record)
    fields=(:acceptance_rate,:log_density,:hamiltonian_energy,:hamiltonian_energy_error,
        :max_hamiltonian_energy_error,:step_size,:nom_step_size)
    invalid=count(s->any(k->!finite(getproperty(s,k)),fields) ||
        !(positive(s.step_size) && positive(s.nom_step_size)),record.run.sampler_stats)
    merge(only(record.run.sampler_rows),(;chain=record.chain,n_invalid_sampler_values=invalid))
end
sampler_ok(s)=s.n_nonfinite_logdensity===0 && s.n_divergences===0 && s.n_invalid_sampler_values===0 &&
    positive(s.e_bfmi) && s.e_bfmi>=POLICY.bfmi_min
function precision_ok(summary,policy)
    p=summary.precision
    finite(p.mean_mcse) && 0<=p.mean_mcse<=policy.mean_mcse_max &&
        all(q->finite(q.mcse) && 0<=q.mcse<=policy.endpoint_mcse_max,p.quantiles[[1,3]])
end

"""Audit all raw/model coordinates, telemetry and paired trajectory precision.

Fixtures cannot qualify. Retained divergence/invalid-energy/low-BFMI failures
remain failures even if a focal interval is precise. Warmup and tree-depth
warnings remain visible. This is numerical qualification, not scientific support.
"""
function report(saved)
    plan=saved.plan;t=check_plan(plan)
    length(saved.chains)==4 && [c.chain for c in saved.chains]==collect(1:4) ||
        throw(ArgumentError("four ordered complete chains required"))
    foreach(c->check_chain(plan,c;t),saved.chains)
    raw=reduce(vcat,[c.run.draws for c in saved.chains]);T=length(t.time_ticks)
    states=[M.coordinates(t,q) for q in eachrow(raw)]
    severity=reduce(vcat,[permutedims(vec(s.severity)) for s in states])
    model=reduce(vcat,[permutedims([s.theta;vec(s.severity);t.K>2 ? vec(s.steps) : Float64[];s.sigma]) for s in states])
    names=[["theta[$p]" for p in 1:t.P];["severity[$r,$j]" for j in 1:T for r in 1:t.R];
        t.K>2 ? ["step[$r,$k]" for k in 1:t.K-1 for r in 1:t.R] : String[];
        t.static ? String[] : ["innovation_sd[$r]" for r in 1:t.R]]
    diagnose(a,n,space)=B._candidate_mcmc_diagnostic_rows(a,n,4;parameter_space=space,
        split_chains=true,rhat_threshold=POLICY.rhat_max,ess_threshold=POLICY.bulk_ess_min)
    raw_diagnostics=diagnose(raw,["q[$j]" for j in axes(raw,2)],:raw)
    model_diagnostics=diagnose(model,names,:original_model)
    ref=only(findall(==(plan.reference),t.time_labels));design=M.design_review(t;reference=ref)
    trajectory=NamedTuple[]
    for j in 1:T, r in 0:t.R
        a=r==0 ? severity[:,(j-1)*t.R+1:j*t.R]*plan.panel_weights : severity[:,(j-1)*t.R+r]
        b=r==0 ? severity[:,(ref-1)*t.R+1:ref*t.R]*plan.panel_weights : severity[:,(ref-1)*t.R+r]
        fixed=t.static || j==ref
        status=r==0 ? R.panel_status(t,plan.panel_weights,j,ref,design) :
            t.static ? "static_constraint" : j==ref ? "reference" : design.status[r,j]
        summary=fixed ? nothing : B.posterior_contrast(a,b;chains=4,interval=plan.interval,
            rope=(-plan.epsilon,plan.epsilon))
        push!(trajectory,(;rater=r==0 ? nothing : t.rater_labels[r],scope=r==0 ? :panel : :judge,
            time=t.time_labels[j],tick=t.time_ticks[j],design_status=status,structurally_fixed=fixed,
            summary,precision_passed=fixed ? nothing : precision_ok(summary,plan.precision),
            diagnostic_passed=fixed ? nothing : diagnostic_ok(summary.contrast_diagnostics)))
    end
    sampler=sampler_summary.(saved.chains)
    warmup=[merge(only(B._warmup_diagnostic_rows(c.run.warmup_stats,c.run.controls,c.run.backend)),
        (;chain=c.chain)) for c in saved.chains]
    focal=filter(x->!x.structurally_fixed,trajectory)
    parameter_passed=all(diagnostic_ok,[raw_diagnostics;model_diagnostics]) && all(x->x.diagnostic_passed,focal)
    sampler_passed=all(sampler_ok,sampler);precision_passed=all(x->x.precision_passed,focal)
    (;schema="bayesianmgmfrm.rw1_chain_report.v1",kind=plan.kind,posterior=plan.kind===:posterior,
      plan_hash=plan.content_hash,chain_hashes=[c.content_hash for c in saved.chains],
      numerical_qualified=plan.kind===:posterior && parameter_passed && sampler_passed && precision_passed,
      parameter_passed,sampler_passed,precision_passed,statistical_acceptance=false,public_api=true,
      context=plan.context,policy=plan.policy,precision_policy=plan.precision,
      target=plan.target,reference=plan.reference,panel_weights=plan.panel_weights,
      interval_method=:pointwise_equal_tailed,interval_mass=plan.interval,epsilon=plan.epsilon,
      conditioning=:retrospective_existing_performances_and_judges,forecast=false,causal_effect=false,
      design,trajectory,raw_diagnostics,model_diagnostics,sampler,warmup,
      n_max_treedepth=sum(s.n_max_treedepth for s in sampler),
      chain_ids=repeat(1:4;inner=plan.controls.ndraws),iterations=repeat(1:plan.controls.ndraws;outer=4),
      sampling_seconds=[c.sampling_seconds for c in saved.chains])
end
end
