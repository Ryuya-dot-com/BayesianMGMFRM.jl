# Reuse the preceding density checks and their canonical fixture when run standalone.
isdefined(@__MODULE__, :MFRMCorrelated2DChecks) || include("mfrm_correlated_2d.jl")
module MFRMCorrelated2DSampleChecks

using Test, BayesianMGMFRM, Serialization, Statistics, SHA
using ..MFRMCorrelated2DChecks: specification, PRIOR
const B = BayesianMGMFRM
include("test_groups.jl")

@testset "correlated coordinate transport and rejection (no sampling)" begin
    for categories in (2,4)
        target = B._MFRMFixedQCorrelated2DLogDensity(specification(categories); prior=PRIOR)
        n = B.LogDensityProblems.dimension(target)
        x = [0.1sin(i) for i in 1:n]; x[end] = 0.4
        payload = B._cmdstan_generalized_initial(target,x)
        @test payload == (; beta=x[1:end-1],zrho=0.4)
        @test B._cmdstan_generalized_initial(target.base,x[1:end-1]) == (;beta=x[1:end-1])
        rows = B._mfrm_fixed_q_model_coordinates(target,reshape(x,1,:))
        @test last(rows).values == [tanh(0.4)] && last(rows).parameter_space === :correlation
        @test !last(rows).fixed && last(rows).derived
        for bad in (zeros(0,n),zeros(2,n-1),fill(NaN,2,n))
            @test_throws ArgumentError B._mfrm_fixed_q_model_coordinates(target,bad)
        end
        mktempdir() do dir
            for backend in (:advancedhmc,:cmdstan)
                options = backend === :cmdstan ? (;cmdstan_cache_dir=joinpath(dir,"never-compile")) : (;)
                for invalid in ((;ndraws=0),(;warmup=-1),(;chains=0),(;step_size=0),
                        (;metric=:unknown),(;target_accept=1.2),(;max_depth=0))
                    @test_throws ArgumentError B._mfrm_correlated_2d_sample(target; backend,invalid...,options...)
                end
                for initial in ([0.0],fill(NaN,n),fill(Inf,n))
                    @test_throws ArgumentError B._mfrm_correlated_2d_sample(target,initial;backend,options...)
                end
            end
            @test !ispath(joinpath(dir,"never-compile"))
        end
        @test_throws ArgumentError B._mfrm_correlated_2d_sample(target;backend=:julia)
        @test_throws ArgumentError B.Experimental.fit(target)
        pointwise = B._mfrm_fixed_q_pointwise(target.base,x[1:end-1])
        lp = B.LogDensityProblems.logdensity(target,x)
        # Place zrho first and reverse the columns to check named, not positional, mapping.
        header = ["lp__","accept_stat__","stepsize__","treedepth__","n_leapfrog__","divergent__","energy__",
            "zrho",["beta.$i" for i in 1:(n-1)]...,["log_lik.$i" for i in eachindex(pointwise)]...]
        values = [lp,0.8,0.03,1,1,0,10,x[end],x[1:end-1]...,pointwise...]
        mktempdir() do dir
            path = joinpath(dir,"synthetic.csv")
            write_csv() = write(path,join(reverse(header),',')*"\n"*join(reverse(values),',')*"\n")
            write_csv()
            parsed = B._cmdstan_generalized_chain_result(path,target,2,1)
            @test parsed.draws == reshape(x,1,:) && parsed.logps ≈ [lp]
            @test only(parsed.stats).chain == 2 && only(parsed.stats).stan_lp == lp
            for index in (1,8,length(values)) # wrong prior, rho coordinate, or pointwise likelihood
                original=values[index]; values[index]+=0.5; write_csv()
                @test_throws CmdStanError B._cmdstan_generalized_chain_result(path,target,2,1)
                values[index]=original
            end
            header[8]="absent_zrho";write_csv()
            @test_throws CmdStanError B._cmdstan_generalized_chain_result(path,target,2,1)
        end
    end
end

function check_samples(categories,backend,directory)
    target = B._MFRMFixedQCorrelated2DLogDensity(specification(categories);prior=PRIOR,lkj_eta=categories+1)
    identity = B._mfrm_correlated_2d_identity(target)
    initial = initial_params(target); initial[end]=0.25
    record_warmup = categories == 4
    options = backend === :cmdstan ? (;cmdstan_cache_dir=joinpath(directory,"compile")) : (;)
    # Mutated numerical views must be rebuilt from the validated base design and prior.
    target.blueprint.parameter_names[1]="stale"
    target.base.base.design.spec.q_matrix .= true
    result = B._mfrm_correlated_2d_sample(target,initial;backend,ndraws=12,warmup=10,chains=2,
        seed=20260917,step_size=0.03,max_depth=4,init_jitter=0.02,record_warmup,options...)
    record,run=result.record,result.record.run
    target = B._MFRMFixedQCorrelated2DLogDensity(record.base_spec;prior=PRIOR,lkj_eta=categories+1)
    @test record.schema == "bayesianmgmfrm.correlated_fixed_q_mfrm_samples.v1"
    @test record.target_identity == identity && record.prior == B._mfrm_correlated_2d_prior_record(target)
    @test record.base_spec.family === :mfrm && !hasproperty(record,:spec)
    @test !result.public_fit && result.model === :mfrm_fixed_q_correlated_2d
    @test result.parameter_names == target.blueprint.parameter_names
    @test result.parameter_spaces == [fill(:unit_logit,length(initial)-1);:fisher_z]
    @test size(run.draws) == (24,length(initial)) && run.initial == initial
    @test run.backend === backend && run.sampler === :nuts && run.controls.rng.seed == 20260917
    @test run.chain_ids == repeat(1:2;inner=12) && run.iterations == repeat(1:12;outer=2)
    @test all(row.coverage === (record_warmup ? :recorded : :not_recorded) for row in result.warmup_diagnostics)
    @test result.diagnostics.summary.flag !== :ok # Short operability runs do not certify MCMC quality.
    @test [row.mean for row in result.posterior_summary] ≈ vec(mean(run.draws;dims=1))
    @test last(result.diagnostics.parameter_rows).parameter_space === :fisher_z
    @test last(result.diagnostics.model_parameter_rows).parameter_space === :correlation
    @test last(result.model_coordinates).values == tanh.(run.draws[:,end])
    @test last(result.model_posterior_summary).mean ≈ mean(tanh.(run.draws[:,end]))
    @test all(row.parameter_space === :dimensionless for row in result.model_coordinates if row.fixed &&
        row.block in (:item_dimension_discrimination,:rater_consistency))
    for (x,lp) in zip(eachrow(run.draws),run.logdensities)
        @test lp ≈ B.LogDensityProblems.logdensity(target,x) atol=1e-8
        @test lp ≈ sum(B._mfrm_fixed_q_pointwise(target.base,x[1:end-1]))+logprior(target,x) atol=1e-8
    end
    if backend === :cmdstan
        @test all(isapprox(stat.stan_lp,lp;atol=1e-8) for (stat,lp) in zip(run.sampler_stats,run.logdensities))
    end
    path=joinpath(directory,"samples.jls")
    B._save_mfrm_correlated_2d_samples(path,result)
    bytes=read(path)
    loaded=B._load_mfrm_correlated_2d_samples(path;expected_identity=identity)
    # FacetSpec has reference equality; compare its validated identity separately.
    same_result(a,b) = isequal(Base.structdiff(a,(;record=nothing)),Base.structdiff(b,(;record=nothing))) &&
        isequal(Base.structdiff(a.record,(;base_spec=nothing)),Base.structdiff(b.record,(;base_spec=nothing))) &&
        design_identity(getdesign(a.record.base_spec;preview=true)).value ==
            design_identity(getdesign(b.record.base_spec;preview=true)).value
    @test same_result(loaded,result)
    @test_throws ArgumentError B._save_mfrm_correlated_2d_samples(path,result)
    @test_throws ArgumentError B._load_mfrm_correlated_2d_samples(path;expected_identity="wrong")
    @test_throws ArgumentError B._load_mfrm_fixed_q_samples(path;expected_identity=identity)
    @test_throws ArgumentError B._load_mgmfrm_normalized_prior_samples(path;expected_identity=identity)
    @test_throws ArgumentError load_fit_cache(path)
    @test read(path)==bytes
    B._save_mfrm_correlated_2d_samples(path,result;overwrite=true)
    @test same_result(B._load_mfrm_correlated_2d_samples(path;expected_identity=identity),loaded)
    rehash(r)=merge(r,(;content_hash=B._mgmfrm_normalized_sample_hash(r)))
    changed=copy(run.draws);changed[1,end]+=0.5
    changed_spec=deepcopy(record.base_spec);changed_spec.dimension_labels[1]="changed"
    bads=[merge(record,(;content_hash="wrong")),merge(record,(;base_spec=changed_spec)),
        rehash(merge(record,(;schema="bayesianmgmfrm.fixed_q_mfrm_samples.v2"))),
        rehash(merge(record,(;prior=merge(record.prior,(;correlation=merge(record.prior.correlation,(;lkj_eta=7))))))),
        rehash(merge(record,(;prior=merge(record.prior,(;correlation=merge(record.prior.correlation,(;density_measure=:d_rho))))))),
        rehash(merge(record,(;run=merge(run,(;draws=changed))))),
        rehash(merge(record,(;run=merge(run,(;chain_ids=reverse(run.chain_ids))))))]
    if record_warmup
        push!(bads,rehash(merge(record,(;run=merge(run,(;warmup_stats=run.warmup_stats[2:end]))))))
    end
    if backend === :cmdstan
        stats=copy(run.sampler_stats);stats[1]=merge(stats[1],(;stan_lp=stats[1].stan_lp+0.5))
        push!(bads,rehash(merge(record,(;run=merge(run,(;sampler_stats=stats))))))
    end
    for bad in bads
        @test_throws ArgumentError B._restore_mfrm_correlated_2d_samples(bad;expected_identity=identity)
        @test_throws ArgumentError B._save_mfrm_correlated_2d_samples(path,(;record=bad);overwrite=true)
        @test read(path)==bytes
    end
    @test_throws ArgumentError B._save_mfrm_fixed_q_samples(path,result;overwrite=true)
    @test read(path)==bytes
    B._write_json_record(joinpath(directory,"result.json"),(;julia_version=string(VERSION),
        target_identity=identity, prior=record.prior,backend,
        posterior=result.model_posterior_summary,diagnostics=result.diagnostics,
        warmup=result.warmup_diagnostics,file_sha256=bytes2hex(sha256(bytes)),scientific_acceptance=false))
end

@testset "correlated fixed-Q sampling and replay (operability only)" begin
    backends=test_flag("BAYESIANMGMFRM_CMDSTAN_TESTS") ? (:advancedhmc,:cmdstan) : (:advancedhmc,)
    for backend in backends, categories in (2,4)
        output=get(ENV,"BAYESIANMGMFRM_CORRELATED_SAMPLES_OUTPUT",nothing)
        check=dir->check_samples(categories,backend,dir)
        output === nothing ? mktempdir(check) : check(mkpath(joinpath(output,"$backend-$categories")))
    end
end
end
