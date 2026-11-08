module CategoryStreamingChecks
using BayesianMGMFRM, Test, Statistics, Random
import ..CommonPredictionRefitChecks, ..CommonPredictionKfoldChecks
const B=BayesianMGMFRM
const R=CommonPredictionRefitChecks

function same_summary(a,b)
    if a isa NamedTuple && b isa NamedTuple
        return keys(a)==keys(b) && all(k->k===:draws_hash || same_summary(a[k],b[k]),keys(a))
    elseif a isa Tuple && b isa Tuple
        return length(a)==length(b) && all(same_summary(x,y) for (x,y) in zip(a,b))
    elseif a isa AbstractArray && b isa AbstractArray
        return size(a)==size(b) && all(same_summary(x,y) for (x,y) in zip(a,b))
    elseif a isa AbstractFloat && b isa AbstractFloat
        return isequal(a,b) || isapprox(a,b;atol=1e-12,rtol=1e-10)
    end
    return isequal(a,b)
end

function native_step_checks()
    @testset "Pointwise thresholds agree with uncached native logits" begin
        for c in CommonPredictionKfoldChecks.fixture_cases()
            ctx=B.PredictionObservationAdapter._context(c.fit,nothing,nothing,Random.default_rng())
            ctx.spec.family===:mgmfrm || continue
            d=ctx.design;data=d.spec.data;li=B._mgmfrm_source_loading_index_matrix(d)
            for j in (1,size(ctx.direct,1))
                v=collect(ctx.direct[j,:]);eta=zeros(length(data.category_levels))
                reference=map(1:data.n) do row
                    B._mgmfrm_source_linear_predictors!(eta,d,v,row,li)
                    eta[data.category[row]]-B._logsumexp(eta)
                end
                @test isequal(B._mgmfrm_source_pointwise_loglikelihood(d,v,li),reference)
            end
        end
    end
end

function checks()
@testset "Streaming category summaries preserve dense predictions" begin
    cases=[c.fit for c in CommonPredictionKfoldChecks.fixture_cases()]
    @test length(unique(typeof.(cases)))==8
    # Exercise each larger-facet orientation and an unobserved declared category.
    for (rater,item) in (([1,2,3,1,2,3],[1,1,1,2,2,2]),([1,1,1,2,2,2],[1,2,3,1,2,3]))
        data=FacetData((;person=[1,1,2,2,3,3],rater,item,score=[0,1,1,0,1,0]);
            person=:person,rater=:rater,item=:item,score=:score,category_levels=0:2)
        push!(cases,R.reporting_fit(:mfrm;data,ndraws=20,chains=2,warmup=0))
    end
    for fit in cases
        data=B.PredictionObservationAdapter._fit_data(fit)
        ids=["rating-$n" for n in 1:data.n]
        dense=B.prediction_observations(fit;dataset_id="streaming-fixture",observation_ids=ids)
        workspace=B._category_usage_workspace(data,40,length(data.category_levels))
        result=B.category_report(fit;dataset_id="streaming-fixture",observation_ids=ids,max_prediction_cells=workspace)
        @test result.observation_binding==dense.observation_binding
        @test result.chain_ids==dense.chain_ids && result.iterations==dense.iterations
        @test result.source_sample_hash==dense.source_sample_hash
        @test !result.refit_performed && !result.automatic_category_collapse
        @test result.n_retained_draws==40
        for row in result.usage_rows
            ns=row.facet===:overall ? collect(1:data.n) : findall(==(row.level_index),getproperty(data,row.facet))
            k=findfirst(==(row.category),data.category_levels)
            values=vec(mean(dense.probabilities[:,ns,k];dims=2))
            @test same_summary(row.expected,B._category_report_summary(values,2,.95;space=:probability))
            @test row.n_observations==length(ns) && row.observed_count==count(==(k),data.category[ns])
        end
        @test B._prediction_check_seal(result,"bayesianmgmfrm.category_report.v1")===nothing
        @test_throws ArgumentError B.category_report(fit;dataset_id="streaming-fixture",observation_ids=ids,max_prediction_cells=workspace-1)
    end
    fit=first(cases);ids=["r$n" for n in 1:fit.design.spec.data.n]
    bad=deepcopy(fit);reverse!(bad.chain_ids)
    @test_throws ArgumentError B.category_report(bad;dataset_id="bad",observation_ids=ids)
    @test_throws ArgumentError B.category_report(fit;dataset_id="bad",observation_ids=fill("same",length(ids)))
    @test_throws ArgumentError B.category_report(fit;dataset_id="bad",observation_ids=ids,max_prediction_cells=true)
    context=B.PredictionObservationAdapter._context(fit,nothing,nothing,Random.default_rng())
    context.direct[1,1]=Inf
    contract,_=B._category_report_steps(B._recovery_context(fit))
    @test_throws ArgumentError B._category_usage_rows(context,contract,B._category_functioning_controls(.95,5,.01,.8),.95)
end
end
end
