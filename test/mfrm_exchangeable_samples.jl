isdefined(@__MODULE__, :MFRMExchangeableRaterChecks) || include("mfrm_exchangeable_raters.jl")
module MFRMExchangeableSampleChecks
using Test, BayesianMGMFRM, Serialization, Statistics, SHA
using ..MFRMExchangeableRaterChecks: specification, target, reference, SCALES
const B = BayesianMGMFRM
include("test_groups.jl")

function synthetic_record(t, spec, backend)
    initial = initial_params(t)
    draws = [0.2sin(d+p) for d in 1:8, p in eachindex(initial)]
    logdensities = [B.LogDensityProblems.logdensity(t,row) for row in eachrow(draws)]
    chain_ids, iterations = repeat(1:2;inner=4), repeat(1:4;outer=2)
    controls = (;ndraws=4,chains=2,warmup=0,step_size=0.1,target_accept=0.8,
        max_depth=2,max_energy_error=1000.0,init_jitter=0.0,metric=:diagonal)
    controls = merge(controls,backend===:advancedhmc ?
        (;ad_backend=:ForwardDiff,gradient_backend=:ad) :
        (;ad_backend=:stan_reverse_mode,gradient_backend=:stan_autodiff,execution=:cmdstan_cli,thinning=1))
    stats = NamedTuple[B._advancedhmc_stat_row((;log_density=logdensities[d],
        step_size=0.1,acceptance_rate=0.75,hamiltonian_energy=Float64(d)),chain_ids[d],iterations[d]) for d in 1:8]
    backend===:cmdstan && (stats=NamedTuple[merge(s,(;stan_lp=s.log_density)) for s in stats])
    chain_acceptance=fill(0.75,2)
    run=(;checked=B._check_diagnostic_thresholds(1.01,400),nparams=length(initial),initial,
        initial_logdensity=B.LogDensityProblems.logdensity(t,initial),total_draws=8,
        draws,logdensities,chain_ids,iterations,chain_acceptance,sampler_stats=stats,controls,
        sampler_rows=B._generalized_candidate_sampler_rows(logdensities,iterations,chain_acceptance,stats,controls,backend),
        backend,sampler=:nuts,split_chains_requested=true,actual_split=true)
    record=(;schema="bayesianmgmfrm.exchangeable_rater_mfrm_samples.v1",spec,
        prior=B._mfrm_exchangeable_rater_record(t),target_identity=B._mfrm_exchangeable_rater_identity(t),run)
    return rehash(record)
end
rehash(r)=merge(r,(;content_hash=B._mgmfrm_normalized_sample_hash(r)))

function check_result(result,t,directory)
    record,run=result.record,result.record.run
    identity=record.target_identity
    correlated=t.base isa B._MFRMFixedQCorrelated2DLogDensity
    @test !result.public_fit && result.rater_prior===:normalized_zero_sum_normal
    @test result.model === (correlated ? :mfrm_correlated_2d_exchangeable_raters : :mfrm_fixed_q_exchangeable_raters)
    @test identity == B._mfrm_exchangeable_rater_identity(t)
    @test record.prior == B._mfrm_exchangeable_rater_record(t)
    @test result.parameter_names == B._mfrm_fixed_q_parameter_names(t.base)
    @test isequal(result.model_coordinates,B._mfrm_fixed_q_model_coordinates(t.base,run.draws))
    @test [r.mean for r in result.posterior_summary] ≈ vec(mean(run.draws;dims=1))
    @test result.diagnostics.summary.flag !== :ok
    @test all(row->row.fixed ? !row.quality_gate_applicable : true,
        [merge(row,(;fixed=c.fixed)) for (row,c) in zip(result.diagnostics.model_parameter_rows,result.model_coordinates)])
    for (x,lp) in zip(eachrow(run.draws),run.logdensities)
        @test lp ≈ B.LogDensityProblems.logdensity(t,x) atol=1e-8
    end
    if correlated
        @test last(result.parameter_spaces) === :fisher_z
        @test last(result.diagnostics.parameter_rows).parameter_space === :fisher_z
        @test last(result.diagnostics.model_parameter_rows).parameter_space === :correlation
        @test last(result.model_coordinates).values == tanh.(run.draws[:,end])
    end
    path=joinpath(directory,"samples.jls")
    B._save_mfrm_exchangeable_rater_samples(path,result)
    bytes=read(path)
    loaded=B._load_mfrm_exchangeable_rater_samples(path;expected_identity=identity)
    @test isequal(Base.structdiff(loaded,(;record=nothing)),Base.structdiff(result,(;record=nothing)))
    @test isequal(loaded.record.run,run)
    @test loaded.record.target_identity == identity
    @test_throws ArgumentError B._save_mfrm_exchangeable_rater_samples(path,result)
    @test_throws ArgumentError B._load_mfrm_exchangeable_rater_samples(path;expected_identity=record.prior.base_identity)
    for loader in (B._load_mfrm_fixed_q_samples,B._load_mfrm_correlated_2d_samples,B._load_mgmfrm_normalized_prior_samples)
        @test_throws ArgumentError loader(path;expected_identity=identity)
    end
    @test_throws ArgumentError load_fit_cache(path)
    @test read(path)==bytes
    # Derived views are rebuilt, never accepted as authoritative saved summaries.
    altered=merge(result,(;posterior_summary=NamedTuple[],diagnostics=(;flag=:ok)))
    B._save_mfrm_exchangeable_rater_samples(path,altered;overwrite=true)
    @test isequal(B._load_mfrm_exchangeable_rater_samples(path;expected_identity=identity).diagnostics,result.diagnostics)
    changed=copy(run.draws);changed[1,end]+=0.5
    wrong_spec=deepcopy(record.spec)
    (correlated ? wrong_spec.base_spec : wrong_spec).dimension_labels[1]="changed"
    bads=[merge(record,(;content_hash="wrong")),merge(record,(;spec=wrong_spec)),
        rehash(merge(record,(;schema="bayesianmgmfrm.fixed_q_mfrm_samples.v2"))),
        rehash(merge(record,(;prior=merge(record.prior,(;rater_scale_convention=:marginal_sd))))),
        rehash(merge(record,(;prior=merge(record.prior,(;scales=merge(record.prior.scales,(;rater_kernel_sd=0.9))))))),
        rehash(merge(record,(;run=merge(run,(;draws=changed))))),
        rehash(merge(record,(;run=merge(run,(;chain_ids=reverse(run.chain_ids))))))]
    if hasproperty(run,:warmup_stats) && run.warmup_stats !== nothing && !isempty(run.warmup_stats)
        push!(bads,rehash(merge(record,(;run=merge(run,(;warmup_stats=run.warmup_stats[2:end]))))))
    end
    if run.backend===:cmdstan
        stats=copy(run.sampler_stats);stats[1]=merge(stats[1],(;stan_lp=stats[1].stan_lp+0.5))
        push!(bads,rehash(merge(record,(;run=merge(run,(;sampler_stats=stats))))))
    end
    if correlated
        push!(bads,merge(record,(;spec=B.Experimental.correlated(record.spec.base_spec;lkj_eta=7))))
    end
    bytes=read(path)
    for bad in bads
        @test_throws ArgumentError B._restore_mfrm_exchangeable_rater_samples(bad;expected_identity=identity)
        @test_throws ArgumentError B._save_mfrm_exchangeable_rater_samples(path,(;record=bad);overwrite=true)
        @test read(path)==bytes
    end
    for saver in (B._save_mfrm_fixed_q_samples,B._save_mfrm_correlated_2d_samples)
        @test_throws ArgumentError saver(path,result;overwrite=true)
        @test read(path)==bytes
    end
    return loaded
end

@testset "exchangeable result reconstruction and integrity (synthetic)" begin
    for (D,K,mixed,correlated) in ((2,2,false,false),(3,4,false,false),(2,4,true,false),
            (2,2,false,true),(2,4,false,true)), backend in (:advancedhmc,:cmdstan)
        spec=specification(3,K;D,mixed)
        model=correlated ? B.Experimental.correlated(spec;lkj_eta=3) : spec
        t=target(spec,correlated)
        record=synthetic_record(t,model,backend)
        result=B._restore_mfrm_exchangeable_rater_samples(record;expected_identity=record.target_identity)
        mktempdir(dir->check_result(result,t,dir))
    end
end

@testset "exchangeable sampler guards and named CmdStan columns" begin
    for correlated in (false,true)
        t=target(specification(),correlated)
        n=B.LogDensityProblems.dimension(t)
        x=[0.1sin(i) for i in 1:n]
        @test B._cmdstan_generalized_initial(t,x) == B._cmdstan_generalized_initial(t.base,x)
        mktempdir() do directory
            for backend in (:advancedhmc,:cmdstan)
                extra=backend===:cmdstan ? (;cmdstan_cache_dir=joinpath(directory,"never-compile")) : (;)
                for invalid in ((;ndraws=0),(;warmup=-1),(;chains=0),(;step_size=0),
                        (;metric=:absent),(;target_accept=1.2),(;max_depth=0))
                    @test_throws ArgumentError B._mfrm_exchangeable_rater_sample(t;backend,extra...,invalid...)
                end
                for bad in ([0.0],fill(NaN,n),fill(Inf,n))
                    @test_throws ArgumentError B._mfrm_exchangeable_rater_sample(t,bad;backend,extra...)
                end
            end
            @test !ispath(joinpath(directory,"never-compile"))
            @test_throws ArgumentError B._mfrm_exchangeable_rater_sample(t;backend=:julia)
            p=B.LogDensityProblems.dimension(reference(t))
            pointwise=B._mfrm_fixed_q_pointwise(reference(t),x[1:p])
            names=["beta.$i" for i in 1:p]; correlated && push!(names,"zrho")
            header=["lp__","accept_stat__","stepsize__","treedepth__","n_leapfrog__","divergent__","energy__",names...,
                ["log_lik.$i" for i in eachindex(pointwise)]...]
            values=[B.LogDensityProblems.logdensity(t,x),0.8,0.03,1,1,0,10,x...,pointwise...]
            path=joinpath(directory,"synthetic.csv")
            write_csv()=write(path,join(reverse(header),',')*"\n"*join(reverse(values),',')*"\n")
            write_csv()
            parsed=B._cmdstan_generalized_chain_result(path,t,2,1)
            @test parsed.draws==reshape(x,1,:)
            @test only(parsed.logps) ≈ first(values)
            for index in (1,8,length(values))
                old=values[index];values[index]+=0.5;write_csv()
                @test_throws CmdStanError B._cmdstan_generalized_chain_result(path,t,2,1)
                values[index]=old
            end
            values[1]=B.LogDensityProblems.logdensity(t.base,x);write_csv()
            @test_throws CmdStanError B._cmdstan_generalized_chain_result(path,t,2,1)
        end
    end
end

function check_sampling(correlated,backend,directory)
    spec=specification(3,correlated ? 4 : 2)
    t=target(spec,correlated)
    identity=B._mfrm_exchangeable_rater_identity(t)
    initial=initial_params(t);correlated && (initial[end]=0.25)
    # Only derived numerical views are stale; canonical design and scales prevail.
    t.base.blueprint.parameter_names[1]="stale"
    reference(t).base.design.spec.q_matrix .= true
    extra=backend===:cmdstan ? (;cmdstan_cache_dir=joinpath(directory,"compile")) : (;)
    result=B._mfrm_exchangeable_rater_sample(t,initial;backend,ndraws=12,warmup=10,chains=2,
        seed=20260917,step_size=0.03,max_depth=4,init_jitter=0.02,record_warmup=correlated,extra...)
    canonical=target(spec,correlated)
    @test result.record.target_identity == identity
    @test !in("stale",result.parameter_names)
    @test size(result.record.run.draws)==(24,length(initial))
    @test result.record.run.initial == initial
    @test result.record.run.backend === backend
    @test all(r.coverage === (correlated ? :recorded : :not_recorded) for r in result.warmup_diagnostics)
    loaded=check_result(result,canonical,directory)
    B._write_json_record(joinpath(directory,"result.json"),(;julia_version=string(VERSION),
        prior=result.record.prior,target_identity=identity,backend,
        posterior=result.model_posterior_summary,diagnostics=result.diagnostics,warmup=result.warmup_diagnostics,
        file_sha256=bytes2hex(sha256(read(joinpath(directory,"samples.jls")))) ,scientific_acceptance=false))
    return loaded
end

if test_flag("BAYESIANMGMFRM_EXCHANGEABLE_SAMPLING_TESTS")
    @testset "exchangeable sampling and replay (operability only)" begin
        backend=Symbol(get(ENV,"BAYESIANMGMFRM_EXCHANGEABLE_BACKEND","advancedhmc"))
        root=get(ENV,"BAYESIANMGMFRM_EXCHANGEABLE_SAMPLES_OUTPUT",nothing)
        for correlated in (false,true)
            run=dir->check_sampling(correlated,backend,dir)
            root===nothing ? mktempdir(run) : run(mkpath(joinpath(root,"$backend-$correlated")))
        end
    end
end
end
