module CmdStanAdaptationSamplingChecks
using Test, Random, JSON3, BayesianMGMFRM
include("../scripts/mgmfrm_adaptation_record.jl")
const A = MGMFRMAdaptationRecord
const B = BayesianMGMFRM

function run_checks(directory)
    runtime=B.cmdstan_backend_check(;require_ready=true,include_paths=true)
    cells=[(p,i,r) for p in 1:3 for i in 1:4 for r in 1:3]
    data=FacetData((;person=first.(cells),item=getindex.(cells,2),rater=last.(cells),
        score=[mod(sum(c),3) for c in cells]);person=:person,item=:item,rater=:rater,
        score=:score,category_levels=0:2)
    spec=mfrm_spec(data;family=:mgmfrm,dimensions=2,q_matrix=Bool[1 0;1 0;0 1;0 1],
        thresholds=:partial_credit)
    prior=B.Experimental.GeneralizedPrior(person_sd=1.3,item_sd=.7)
    target=B._mgmfrm_guarded_local_fit_logdensity(spec;prior=B._source_fixture_prior(prior))
    initial=[.03sin(i) for i in eachindex(B.initial_params(target))]
    # Compile once afresh for the sampler-level pairs. Every call verifies the
    # observed executable hash; no unverified compiled-cache reuse is enabled.
    compiled=B._cmdstan_compile_model(runtime,:mgmfrm;cache_dir=joinpath(directory,"kernel-build"))
    @testset "Native CmdStan output recording preserves trajectories" begin
        for metric in (:diagonal,:dense,:unit), warmup in (0,200)
            name="$(metric)-$(warmup)"
            destination=joinpath(directory,name);mkdir(destination)
            record=Dict{Symbol,Any}(:status=>:started,:scope=>:synthetic_engineering_kernel,
                :chains=>Dict{Symbol,Any}[],:coordinates=>A.coordinate_record(target,:raw))
            observer=event->A.observe_cmdstan!(record,destination,event)
            function sample(rng,observer)
                B._cmdstan_sample_chains(compiled.path,B._cmdstan_mgmfrm_data(target),
                    initial,rng,x->B.LogDensityProblems.logdensity(target,x),
                    (p,c,n)->B._cmdstan_mgmfrm_chain_result(p,target,c,n;warmup);
                    expected_sha256=compiled.sha256,ndraws=8,warmup,chains=2,step_size=.03,
                    target_accept=.8,max_depth=3,metric=B._cmdstan_metric(metric),init_jitter=.1,
                    progress=false,record_warmup=true,_sampling_observer=observer)
            end
            plain_rng,observed_rng=MersenneTwister(924302),MersenneTwister(924302)
            plain,observed=sample(plain_rng,nothing),sample(observed_rng,observer)
            @test isequal(plain,observed)
            @test rand(plain_rng,10)==rand(observed_rng,10)
            @test length(record[:chains])==2
            initial_rng=MersenneTwister(924302)
            @test B._cmdstan_chain_seeds(initial_rng,2)==observed.chain_seeds
            @test first(record[:chains])[:initial_raw]==B._advancedhmc_initial(copy(initial),initial_rng,.1)
            for chain in record[:chains]
                c=chain[:chain]
                @test chain[:completed]
                @test chain[:seed]==observed.chain_seeds[c]
                @test chain[:csv].sha256==A.digest(joinpath(destination,chain[:csv].path))
                @test length(chain[:rows])==warmup+8
                @test all(r->ismissing(r.metric_used),chain[:rows][1:warmup])
                @test chain[:metric_history]===:not_recorded
                @test chain[:retained_kernel].adapted==(warmup>0)
                retained=filter(r->r.chain==c,observed.sampler_stats)
                @test getproperty.(chain[:rows][warmup+1:end],:step_size)==getproperty.(retained,:step_size)
                @test getproperty.(chain[:rows][warmup+1:end],:stan_lp)==getproperty.(retained,:stan_lp)
                @test ("save_metric=1" in chain[:command])==(warmup>0)
                @test (chain[:metric_json]!==nothing)==(warmup>0)
                @test JSON3.read(read(joinpath(destination,chain[:initial_file].path),String)).beta==chain[:initial_raw]
            end
            record[:status]=:engineering_kernel_complete
            A.write_record(destination,record)
        end
    end
    @testset "Native CmdStan public fit recording and cache linkage" begin
        options=(;prior,init=initial,backend=:cmdstan,seed=924303,ndraws=8,warmup=200,
            chains=2,max_depth=3,metric=:diagonal,init_jitter=.1,step_size=.03)
        plain=B.Experimental.fit(spec;options...,cmdstan_cache_dir=joinpath(directory,"plain-build"))
        destination=joinpath(directory,"public-recorded")
        observed=A.fit_recorded(destination,spec;options...)
        @test isequal(plain.draws,observed.draws)
        @test isequal(plain.log_posterior,observed.log_posterior)
        @test isequal(plain.sampler_stats,observed.sampler_stats)
        @test isequal(Base.structdiff(plain.sampler_controls,(;cmdstan_executable_sha256=nothing)),
            Base.structdiff(observed.sampler_controls,(;cmdstan_executable_sha256=nothing)))
        # Fresh builds may have different binary hashes; retain both identities.
        B.save_fit_cache(joinpath(directory,"plain-fit.jls"),plain)
        saved=JSON3.read(read(joinpath(destination,"adaptation.json"),String))
        @test saved.status=="complete"
        @test saved.backend=="cmdstan"
        @test saved.fit_cache.sha256==A.digest(joinpath(destination,"fit.jls"))
        @test isequal(load_fit_cache(joinpath(destination,"fit.jls")).draws,observed.draws)
        @test saved.coordinates.sampling=="raw"
        @test saved.coordinates.sampling_names==observed.diagnostic_surface.raw_parameter_names
        @test saved.controls.cmdstan_version==runtime.cmdstan_version
        @test all(c->c.executable_sha256==observed.sampler_controls.cmdstan_executable_sha256,saved.chains)
        @test all(c->c.seed==observed.sampler_controls.rng.chain_seeds[c.chain],saved.chains)
        @test all(c->c.completed && length(c.rows)==208,saved.chains)
    end
    B._write_json_record(joinpath(directory,"test-runtime.json"),(;julia=string(VERSION),
        cmdstan_version=runtime.cmdstan_version,kernel_executable_sha256=compiled.sha256,
        paired_kernel_conditions=6,paired_public_fit_conditions=1,scientific_acceptance=false))
end

if abspath(PROGRAM_FILE)==(@__FILE__) && !isempty(ARGS)
    directory=abspath(only(ARGS));mkdir(directory)
    run_checks(directory)
else
    mktempdir(run_checks)
end
end
