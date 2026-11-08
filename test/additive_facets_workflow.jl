using Test, BayesianMGMFRM, Random, Statistics, Serialization

@testset "Named additive workflow boundaries" begin
    @test AF.label_encoding(2).kind==:integer
    @test AF.label_encoding(2.0).kind==:float
    @test AF.label_encoding(:label).kind==:symbol
    @test AF.label_encoding("label").kind==:string
    for F in (0,1,4,6), K in (2,3,4)
        data,options=additive_fixture(F;K)
        t=mfrm_spec(data;options...);raw=randn(MersenneTwister(17),12,t.dimension)
        m=AF.model_draws(t,raw)
        @test m.names==parameter_names(t;scale=:model)
        for (s,q) in enumerate(eachrow(raw))
            v=coordinates(t,q);at=1
            @test m.values[s,1:length(v.person)]==v.person;at+=length(v.person)
            for b in t.facets
                @test m.values[s,at:at+length(b.levels)-1]==v.facets[b.name];at+=length(b.levels)
            end
            @test m.values[s,at:end]==[v.steps[g,k] for g in axes(v.steps,1) for k in axes(v.steps,2)]
        end
        subset=Dict(k=>v[1:2] for (k,v) in data if k!=options.score)
        p=AF.prediction_target(t,subset)
        @test p.people==t.people
        @test [b.levels for b in p.facets]==[b.levels for b in t.facets]
        @test predictive_probabilities(p,raw[1,:])==predictive_probabilities(t,raw[1,:])[1:2,:]
        subset[options.person]=[999,999]
        @test_throws ArgumentError AF.prediction_target(t,subset)
        @test_throws ArgumentError fit(t;ndraws=10,warmup=10,chains=2,seed=true)
    end
    data,options=additive_fixture(2)
    data[:input_2]=copy(data[:input_1])
    @test_throws ArgumentError fit(mfrm_spec(data;options...);ndraws=10,warmup=10,chains=2,seed=1)
end

# Called with the actual saved pilot, so downstream validation never re-fits.
function additive_fitted_checks(f,output)
    @testset "Actual named additive lifecycle" begin
        t=getdesign(f);r=f.record.run;raw=r.draws;m=AF.model_draws(t,raw)
        @test parameter_names(f)==m.names
        @test sampler_controls(f)==r.controls
        @test validate_design(f).identified
        @test contract(f).fit_available
        @test posterior_summary(f).rows[1].mean≈mean(raw[:,1])*t.person_sd
        @test posterior_summary(f;scale=:raw).rows[1].mean≈mean(raw[:,1])
        for j in eachindex(m.names)
            row=posterior_summary(f;parameters=[m.names[j]]).rows[1]
            @test row.mean≈mean(m.values[:,j])
            @test row.lower≈quantile(m.values[:,j],.025)
            @test row.upper≈quantile(m.values[:,j],.975)
        end
        @test_throws ArgumentError posterior_summary(f;parameters=["not present"])
        @test_throws ArgumentError posterior_summary(f;scale=:unknown)
        @test_throws ArgumentError posterior_mcse(f;probabilities=(1.1,))
        @test_throws ArgumentError qualify(f;min_bfmi=NaN)
        @test_throws ArgumentError BayesianMGMFRM.posterior_contrast(f;left=m.names[1],right=m.names[1])
        c=BayesianMGMFRM.posterior_contrast(f;left=m.names[1],right=m.names[2])
        @test c.result.mean≈mean(m.values[:,1]-m.values[:,2])
        @test c.result.lower≈quantile(m.values[:,1]-m.values[:,2],.025)
        @test isequal(c.result.precision,only(posterior_mcse(
            reshape(m.values[:,1]-m.values[:,2],:,1);chains=r.controls.chains,
            parameter_names=["contrast"],probabilities=((1-.95)/2,.5,(1+.95)/2))))
        pick=[1,7,2]
        pred=predictive_probabilities(f;rows=pick)
        direct=Array{Float64}(undef,length(pick),length(t.categories),size(raw,1))
        for (i,q) in enumerate(eachrow(raw));direct[:,:,i]=predictive_probabilities(t,q)[pick,:];end
        @test pred.mean≈dropdims(mean(direct;dims=3);dims=3)
        for j in 1:3,k in eachindex(t.categories)
            @test pred.lower[j,k]≈quantile(direct[j,k,:],.025)
            @test pred.upper[j,k]≈quantile(direct[j,k,:],.975)
        end
        subset=Dict(col=>v[pick] for (col,v) in t.table if col!=t.columns.score)
        new=predictive_probabilities(f;data=subset)
        @test new.mean==pred.mean
        @test new.selected_columns==subset
        short=deepcopy(subset);pop!(short[t.columns.person])
        @test_throws ArgumentError predictive_probabilities(f;data=short)
        @test all(abs.(sum(pred.mean;dims=2).-1).<1e-12)
        if t.columns.performance!==nothing
            bad=deepcopy(subset)
            bad[t.columns.performance][1]=t.table[t.columns.performance][2]
            @test_throws ArgumentError predictive_probabilities(f;data=bad)
        end
        subset[t.columns.person][1]=999
        @test_throws ArgumentError predictive_probabilities(f;data=subset)
        @test_throws ArgumentError predictive_probabilities(f;rows=[0])
        saved=joinpath(output,"roundtrip.jls");save_fit(saved,f)
        @test_throws ArgumentError save_fit(saved,f)
        again=load_fit(saved)
        @test again.record.content_hash==f.record.content_hash
        @test again.record.run.draws==raw
        @test again.record.run.chain_ids==r.chain_ids
        @test again.record.run.iterations==r.iterations
        @test contract(again).record==contract(t).record
        @test posterior_summary(again)==posterior_summary(f)
        @test_throws ArgumentError load_fit(saved;unknown=true)
        altered=deepcopy(f);altered.record.run.draws[1,1]+=.1
        @test_throws ArgumentError posterior_summary(altered)
        @test_throws ArgumentError save_fit(joinpath(output,"corrupt.jls"),altered)
        rep=fit_report(f)
        receipt=save_report(joinpath(output,"report.json"),rep;return_receipt=true)
        @test_throws ArgumentError save_report(joinpath(output,"report.json"),rep)
        @test_throws ArgumentError load_report(receipt.path;expected_sha256="0"^64)
        portable=load_report(receipt.path;expected_sha256=receipt.sha256)
        @test portable.source_sample_content_hash==f.record.content_hash
        @test portable.api.facet_names==string.([b.name for b in t.facets])
        @test length(portable.input_labels)==length(t.table)
        @test portable.qualification.qualified==qualify(f).qualified
        @test_throws ArgumentError load_report(receipt.path;unknown=true)
        @test portable.scientific_acceptance==false
    end
end

module AdditiveWorkflowTelemetryFixture
using BayesianMGMFRM
include("fixtures/experimental_diagnostic_record.jl")
end

@testset "Deterministic fitted additive operations (not posterior evidence)" begin
    data,options=additive_fixture(2)
    t=mfrm_spec(data;options...)
    base=AdditiveWorkflowTelemetryFixture.diagnostic_record(:RaterGroupEffects;ndraws=12).run
    initial=zeros(t.dimension)
    draws=[.12sin(.91s+.37j) for s in 1:base.total_draws,j in 1:t.dimension]
    densities=[logposterior(t,q) for q in eachrow(draws)]
    stats=[merge(s,(;log_density=densities[i])) for (i,s) in enumerate(base.sampler_stats)]
    run=merge(base,(;nparams=t.dimension,initial,initial_logdensity=logposterior(t,initial),
        draws,logdensities=densities,sampler_stats=stats,
        sampler_rows=BayesianMGMFRM._generalized_candidate_sampler_rows(densities,
            base.iterations,base.chain_acceptance,stats,base.controls,:advancedhmc)))
    target=AF.record(t)
    body=(;schema=AF.FIT_SCHEMA,target,target_identity=BayesianMGMFRM._cache_hash(target),run,
        producer=(;fixture=:manufactured_coordinates_and_telemetry))
    f=AF.Fit(merge(body,(;content_hash=BayesianMGMFRM._cache_hash(body))))
    mktempdir() do out
        additive_fitted_checks(f,out)
    end
end

