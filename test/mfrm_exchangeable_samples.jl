isdefined(@__MODULE__, :MFRMExchangeableRaterChecks) || include("mfrm_exchangeable_raters.jl")
module MFRMExchangeableSampleChecks
using Test, BayesianMGMFRM, Serialization, Statistics, SHA, Random
using ..MFRMExchangeableRaterChecks: specification, target, reference, SCALES
const B = BayesianMGMFRM
include("test_groups.jl")

function synthetic_record(t, spec, backend; ndraws=4, chains=2)
    initial = initial_params(t)
    total_draws = ndraws * chains
    draws = [0.2sin(d+p) for d in 1:total_draws, p in eachindex(initial)]
    logdensities = [B.LogDensityProblems.logdensity(t,row) for row in eachrow(draws)]
    chain_ids, iterations = repeat(1:chains;inner=ndraws), repeat(1:ndraws;outer=chains)
    controls = (;ndraws,chains,warmup=0,step_size=0.1,target_accept=0.8,
        max_depth=2,max_energy_error=1000.0,init_jitter=0.0,metric=:diagonal)
    controls = merge(controls,backend===:advancedhmc ?
        (;ad_backend=:ForwardDiff,gradient_backend=:ad) :
        (;ad_backend=:stan_reverse_mode,gradient_backend=:stan_autodiff,execution=:cmdstan_cli,thinning=1))
    stats = NamedTuple[B._advancedhmc_stat_row((;log_density=logdensities[d],
        step_size=0.1,acceptance_rate=0.75,hamiltonian_energy=Float64(d)),chain_ids[d],iterations[d]) for d in 1:total_draws]
    backend===:cmdstan && (stats=NamedTuple[merge(s,(;stan_lp=s.log_density)) for s in stats])
    chain_acceptance=fill(0.75,chains)
    run=(;checked=B._check_diagnostic_thresholds(1.01,400),nparams=length(initial),initial,
        initial_logdensity=B.LogDensityProblems.logdensity(t,initial),total_draws,
        draws,logdensities,chain_ids,iterations,chain_acceptance,sampler_stats=stats,controls,
        sampler_rows=B._generalized_candidate_sampler_rows(logdensities,iterations,chain_acceptance,stats,controls,backend),
        backend,sampler=:nuts,split_chains_requested=true,actual_split=chains>=2 && ndraws>=4)
    record = if t isa B._MFRMExchangeableRatersLogDensity
        (;schema="bayesianmgmfrm.exchangeable_rater_mfrm_samples.v1",spec,
            prior=B._mfrm_exchangeable_rater_record(t),target_identity=B._mfrm_exchangeable_rater_identity(t),run)
    elseif t isa B._MFRMFixedQCorrelated2DLogDensity
        (;schema="bayesianmgmfrm.correlated_fixed_q_mfrm_samples.v1",base_spec=spec.base_spec,
            prior=B._mfrm_correlated_2d_prior_record(t),target_identity=B._mfrm_correlated_2d_identity(t),run)
    else
        (;schema="bayesianmgmfrm.fixed_q_mfrm_samples.v2",spec,
            prior=B._mfrm_fixed_q_prior_record(t),target_identity=B._mfrm_fixed_q_identity(t),run)
    end
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

@testset "fixed-coefficient fit MCSE (synthetic, no sampling)" begin
    cases = [(2,4,false,c,e,b) for c in (false,true) for e in (false,true) for b in (:advancedhmc,:cmdstan)]
    append!(cases, [(2,2,false,false,false,:advancedhmc),
        (2,2,false,true,true,:cmdstan), (3,4,true,false,true,:advancedhmc)])
    for (D,K,mixed,correlated,exchangeable,backend) in cases
        spec = specification(3,K;D,mixed)
        model = correlated ? B.Experimental.correlated(spec;lkj_eta=3) : spec
        prior = exchangeable ? B.Experimental.ExchangeablePrior(;SCALES...) : MFRMPrior()
        t = B._fixed_q_prior_target(model,prior)
        record = synthetic_record(t,model,backend;ndraws=32)
        fit_type = exchangeable ? B._ExchangeableMFRMFit : correlated ? B._CorrelatedMFRMFit : B.MultidimensionalMFRMFit
        fit = fit_type(record;expected_identity=record.target_identity)
        original = IOBuffer(); serialize(original,fit.record)
        Random.seed!(83); expected_random=rand(); Random.seed!(83)
        rows = posterior_mcse(fit;probabilities=(0.1,0.9))
        @test rand() == expected_random
        @test isequal(rows,posterior_mcse(fit;probabilities=(0.1,0.9),parameter_space=:direct_constrained))
        direct = B.direct_posterior_summary(fit;lower=0.1,upper=0.9,intervals=())
        @test getproperty.(rows,:parameter) == getproperty.(direct,:parameter)
        @test all(r.n_chains==2 && r.draws_per_chain==32 && !r.precision_threshold_applied for r in rows)
        for (row,summary) in zip(rows,direct)
            @test (row.block,row.dimension,row.fixed,row.derived) ==
                (summary.block,summary.dimension,summary.fixed,summary.derived)
            @test isequal(row.dimension_label,summary.dimension_label)
            @test row.quantiles[1].estimate ≈ summary.lower
            @test row.quantiles[2].estimate ≈ summary.upper
            @test row.mcse_status === (row.fixed ? :structurally_fixed : :available)
            @test row.convergence_review_required == !row.fixed
            row.fixed && @test row.mean_mcse == row.sd_mcse == 0.0
            @test row.parameter_space === (row.block === :latent_correlation ? :correlation :
                row.block in (:item_dimension_discrimination,:rater_consistency) ? :dimensionless : :unit_logit)
        end
        base = exchangeable ? reference(t) : correlated ? t.base : t
        # Compute the reconstructed rater directly from free draws, preserving chains.
        values = -vec(sum(record.run.draws[:,base.blueprint.blocks[:rater_free]];dims=2))
        rater = only(filter(r->r.block===:rater && r.derived,rows))
        manual = only(posterior_mcse(reshape(values,:,1);chains=2,probabilities=(0.1,0.9)))
        for field in (:mean_mcse,:sd_mcse,:quantiles,:mcse_status)
            @test isequal(getproperty(rater,field),getproperty(manual,field))
        end
        raw = posterior_mcse(fit;parameter_space=:raw_unconstrained,probabilities=())
        expected_raw = posterior_mcse(record.run.draws;chains=2,probabilities=())
        @test getproperty.(raw,:parameter) == B._mfrm_fixed_q_parameter_names(t)
        @test isequal(getproperty.(raw,:mean_mcse),getproperty.(expected_raw,:mean_mcse))
        @test all(r.parameter_space===:unit_logit for r in raw[1:end-Int(correlated)])
        if correlated
            rho = only(filter(r->r.block===:latent_correlation,rows))
            manual_rho = only(posterior_mcse(reshape(tanh.(record.run.draws[:,end]),:,1);
                chains=2,probabilities=(0.1,0.9)))
            @test last(raw).parameter_space === :fisher_z
            @test rho.parameter != last(raw).parameter
            for field in (:mean_mcse,:sd_mcse,:quantiles)
                @test isequal(getproperty(rho,field),getproperty(manual_rho,field))
            end
        end
        K==2 && @test all(r.fixed && r.mean_mcse==0 for r in rows if r.block===:item_steps)
        mktempdir() do directory
            path=joinpath(directory,"fit.jls")
            save_fit_cache(path,fit)
            bytes=read(path)
            restored=load_fit_cache(path)
            @test isequal(rows,posterior_mcse(restored;probabilities=(0.1,0.9)))
            @test read(path)==bytes
        end
        for (chains,ndraws,status) in ((1,32,:insufficient_chains),(2,4,:insufficient_draws))
            short=synthetic_record(t,model,backend;chains,ndraws)
            result=fit_type(short;expected_identity=short.target_identity)
            @test all(r.fixed ? r.mcse_status===:structurally_fixed :
                r.mcse_status===status && ismissing(r.mean_mcse) for r in posterior_mcse(result))
        end
        @test_throws ArgumentError posterior_mcse(fit;parameter_space=:identified)
        @test_throws ArgumentError posterior_mcse(fit;probabilities=(1.0,))
        for field in (:chain_ids,:iterations)
            bad=deepcopy(fit); getproperty(bad.record.run,field)[1]=99
            @test_throws ArgumentError posterior_mcse(bad)
            # Even a recomputed digest cannot legitimize an invalid chain layout.
            bad_record=rehash(bad.record)
            @test_throws ArgumentError fit_type(bad_record;expected_identity=record.target_identity)
        end
        after = IOBuffer(); serialize(after,fit.record)
        @test take!(after) == take!(original)
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
