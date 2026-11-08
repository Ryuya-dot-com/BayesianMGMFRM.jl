module JointRatingsTests
using Test, JSON3, LinearAlgebra, BayesianMGMFRM
import LogDensityProblems as L
const J=BayesianMGMFRM.Experimental.JointRatings
const S=J.JointRatingStatic
include("joint_ratings_fixture.jl")

function finite_checks()
    tests=@testset "JointRatings package boundary and fixed arithmetic" begin
    @test :JointRatings in BayesianMGMFRM.Experimental.surface_contract().reader_facing_bindings
    @test :JointRatings ∉ names(BayesianMGMFRM)
    @test BayesianMGMFRM.Experimental.surface_contract().candidate_surfaces.joint_ratings == J.contract()
    t=static_fixture(;K=4,shared=false,predictors=true)
    rows=[merge(r,NamedTuple{Tuple(t.predictor_names)}(Tuple(t.X[i,:]))) for (i,r) in enumerate(t.data.rows)]
    built=J.model(rows;criteria=t.data.criteria,prior=t.prior,predictor_columns=t.predictor_names)
    @test S.target_record(t)==S.target_record(built)
    @test_throws ArgumentError J.fit(t;backend=:unsupported)
    @test_throws ArgumentError J.fit(t;backend=:cmdstan)
    @test_throws ArgumentError J.fit(t;compiled=(;path="not-a-binary"))
    @test hasmethod(J.fit,Tuple{typeof(t)})
    for n in (0,1,4)
        v=Float64.(1:n);z=J.Numerics._zero_sum(v)
        @test sum(z)≈0 atol=1e-14
        @test sum(abs2,z)≈sum(abs2,v) atol=1e-14
    end
    x=J.Numerics.marginal_pcm(0.,1.,[0.];atol=1e-8,maxevals=10000)
    @test x.values[1:2]≈[.5,.5] atol=1e-10
    @test x.estimated_error<=1e-8
    q=S.initial(t);q[t.blocks.correlation].=[20.,-20.]
    @test isfinite(L.logdensity(t,q))
    @test S.coordinates(t,q).correlation_status.response.partial_saturation
    @test_throws ArgumentError J.Numerics.checked_count(true,"count")
    for name in (:model,:fit,:load_result,:save_result,:report,:contrast,:predict,:score,:save_report,:verified_stan,:contract)
        @test Base.Docs.doc(getfield(J,name))!==nothing
    end
    @test occursin("not an error bound",string(Base.Docs.doc(J.score)))
    @test occursin("No fitting",string(Base.Docs.doc(J.model)))
    contrast_checks()
end

    return tests.n_passed
end

# Manufactured coordinates only: no posterior simulation or fitting.
function contrast_checks()
    for K in (2,4), shared in (false,true)
        t=static_fixture(;K,shared,predictors=false)
        criteria=[merge(c,(;direction=:higher_is_less)) for c in reverse(t.data.criteria)]
        # Unusual IDs are literal labels, never executable parameter expressions.
        rows=[merge(r,(;person=r.person=="p1" ? "speaker[\"A\"]" : r.person)) for r in t.data.rows]
        t=J.model(rows;criteria,prior=t.prior)
        draws=reduce(vcat,permutedims.(static_points(t)[1:3]))
        for facet in (:person,:rater), criterion in ("a","b")
            ids=getproperty(t.levels,facet);left,right=first(ids),last(ids)
            got=J._contrast_draws(t,draws;facet,criterion,left,right)
            c=findfirst(==(criterion),t.levels.criterion)
            expected=[begin
                v=S.coordinates(t,q)
                facet===:person ? [v.theta[c,1],v.theta[c,end]] : [v.rater[1,c],v.rater[end,c]]
            end for q in eachrow(draws)]
            @test got.left==first.(expected) && got.right==last.(expected)
            @test got.criterion.direction===:higher_is_less
            @test got.criterion.criterion==criterion
            reverse_pair=J._contrast_draws(t,draws;facet,criterion,left=right,right=left)
            @test reverse_pair.left-reverse_pair.right==-(got.left-got.right)
        end
        base=(;facet=:person,criterion="a",left=first(t.levels.person),right=last(t.levels.person))
        for bad in ((;facet=:task),(;criterion="missing"),(;criterion=1),(;left=1),
            (;left="missing"),(;right=""),(;right=base.left),(;facet="person"))
            @test_throws ArgumentError J._contrast_draws(t,draws;merge(base,bad)...)
        end
        # Artificial diagnostic inputs only; these are not posterior samples.
        B=BayesianMGMFRM
        run=(;draws=repeat(draws,8,1),controls=(;chains=2,warmup=1,max_depth=5),
            split_chains_requested=true,checked=(;rhat_threshold=1.01,ess_threshold=400.),
            backend=:advancedhmc,sampler_rows=[(;chain=1,n_divergences=1)],
            warmup_stats=[(;chain=c,iteration=1,divergent=c==1,tree_depth=5,
                nonfinite_logdensity=c==2) for c in 1:2])
        m=J.W.model_draws(t,run.draws)
        diagnostic=J.W._source_diagnostics(t,run)
        @test keys(diagnostic)==(:status,:controls,:raw_diagnostics,:model_diagnostics,:sampler,:warmup)
        @test diagnostic.status===:engineering_only && diagnostic.controls==run.controls
        names=["$name[$j]" for (name,block) in pairs(t.blocks) for j in eachindex(block)]
        @test isequal(diagnostic.raw_diagnostics,B._candidate_mcmc_diagnostic_rows(
            run.draws,names,2;parameter_space=:white_log_sd_fisher_z,
            split_chains=true,rhat_threshold=1.01,ess_threshold=400.))
        @test isequal(diagnostic.model_diagnostics,B._candidate_mcmc_diagnostic_rows(
            m.values,m.names,2;parameter_space=:model,structurally_fixed_parameters=m.fixed,
            split_chains=true,rhat_threshold=1.01,ess_threshold=400.))
        @test diagnostic.sampler==run.sampler_rows
        @test [x.n_divergences for x in diagnostic.warmup]==[1,0]
        @test [x.n_nonfinite_logdensity for x in diagnostic.warmup]==[0,1]
        @test all(x->x.n_max_treedepth==1,diagnostic.warmup)
        @test isequal(diagnostic,J.W._source_diagnostics(t,run,m))
        @test count(x->!x.quality_gate_applicable,diagnostic.model_diagnostics)==length(m.fixed)
    end
end

# Explicit external saved inputs keep historical research files out of the package.
function saved_checks(input,output)
    results=NamedTuple[]
    tests=@testset "JointRatings saved fit, report and original qualification replay" begin
        for case in 1:2
            sample=J.load_result(joinpath(input,"case-$case.jls"))
            native=joinpath(output,"case-$case.jls")
            J.save_result(native,sample)
            reopened=J.load_result(native)
            @test isequal(sample,reopened)
            @test_throws ArgumentError J.save_result(native,sample)
            parameters=J.report(reopened;lower=.005,upper=.995,intervals=(.99,))
            @test parameters.model==sample.target
            @test parameters.result.prior==sample.target.prior
            @test parameters.result.interval_controls==(;lower=.005,upper=.995,intervals=(.99,))
            @test !parameters.api.scientific_acceptance && !parameters.api.stable_api
            J.save_report(joinpath(output,"parameters-$case.json"),parameters)
            json=JSON3.read(read(joinpath(output,"parameters-$case.json"),String)).data
            @test json.model==JSON3.read(JSON3.write(J.W.jsonsafe(sample.target)))
            @test json.result.sampler==JSON3.read(JSON3.write(J.W.jsonsafe(parameters.result.sampler)))
            for mode in (:existing,:new),kind in (:prediction,:score)
                old=JSON3.read(read(joinpath(input,"$kind-$case-$mode.json"),String))
                rows=[(; (Symbol(k)=>v for (k,v) in pairs(r))...) for r in old.request.rows]
                operation=kind===:prediction ? J.predict : J.score
                report=kind===:prediction ? operation(reopened,rows;response_effect=mode,
                    quadrature_atol=old.request.quadrature_atol,quadrature_maxevals=old.request.quadrature_maxevals) :
                    operation(reopened,rows;response_effect=mode)
                result=report.result
                @test report.model==sample.target
                @test report.source_sample_content_hash==sample.content_hash
                @test report.target_identity==sample.target_identity
                @test result.request_identity==old.request_identity
                @test result.summary.computationally_qualified==0
                @test !result.source_diagnostics.qualified
                @test isequal(result.source_diagnostics.raw_diagnostics,parameters.result.raw_diagnostics)
                @test isequal(result.source_diagnostics.model_diagnostics,parameters.result.model_diagnostics)
                @test isequal(result.source_diagnostics.sampler,parameters.result.sampler)
                @test isequal(result.source_diagnostics.warmup,parameters.result.warmup)
                @test result.parameter_chain_ids==sample.run.chain_ids
                @test result.parameter_iterations==sample.run.iterations
                if kind===:score
                    @test only(result.rows).log_predictive_density≈only(old.rows).log_predictive_density atol=1e-12
                    @test only(result.rows).integration_ok==only(old.rows).integration_ok
                    @test only(result.rows).maximum_log_order_difference≈only(old.rows).maximum_log_order_difference atol=1e-12
                    @test only(result.rows).mcse_status===:insufficient_draws
                    @test !result.heldout_validation && !result.summary.dataset_joint_score
                    @test result.summary.sum_mcse_status===:not_computed
                else
                    @test [r.mean for r in result.posterior]≈[r.mean for r in old.posterior] atol=1e-12
                    @test [r.raw_category for r in result.columns]==[r.raw_category for r in old.columns]
                    @test result.request.intervals==(.9,.99)
                    @test all(d->!d.computationally_qualified,result.decisions)
                end
                path=joinpath(output,"$kind-$case-$mode.json")
                J.save_report(path,report)
                portable=JSON3.read(read(path,String)).data
                @test portable==JSON3.read(JSON3.write(J.W.jsonsafe(report)))
                @test_throws ArgumentError J.save_report(path,report)
                push!(results,(;case,kind,mode,path=basename(path),qualified=result.summary.computationally_qualified))
            end
        end
        record=J.load_result(joinpath(input,"case-2.jls"))
        old=JSON3.read(read(joinpath(input,"score-2-new.json"),String))
        rows=[(; (Symbol(k)=>v for (k,v) in pairs(r))...) for r in old.request.rows]
        @test_throws ArgumentError J.predict(record,rows;response_effect=:new)
        @test_throws ArgumentError J.score(record,[merge(rows[1],(;person="unknown"))];response_effect=:new)
        @test_throws ArgumentError J.score(record,[merge(rows[1],(;score=999))];response_effect=:new)
        corrupt=merge(record,(;content_hash="changed"))
        @test_throws ArgumentError J.report(corrupt)
        @test_throws ArgumentError J.save_result(joinpath(output,"corrupt.jls"),corrupt)
        @test !ispath(joinpath(output,"corrupt.jls"))
    end
    return (;assertions=tests.n_passed,results,
        new_fits=0,new_random_outcomes=0,new_predictive_draws=0)
end
end
