module ScoreInformationChecks
using BayesianMGMFRM, Test, Statistics, Serialization, JSON3
const B=BayesianMGMFRM
include("fixtures/reporting_fit.jl")

function oracle(theta, offset, steps, beta=1.)
    # Independently assembled cumulative logits; no package probability helper.
    logits=[beta*(k*(theta-offset)-sum(steps[1:k])) for k in 0:length(steps)]
    z=maximum(logits); p=exp.(logits.-z); p./sum(p)
end

const OPTIONS=(;include_prior_predictive=false,include_posterior_predictive=false,
    include_category_functioning=false,include_rater_homogeneity=false,
    include_calibration=false,include_waic=false,include_loo=false,include_artifact=false)

function checks(output)
@testset "Scalar score and conditional information" begin
    for steps in ([0.],[-.7,.7],[-1.,.2,.8]), theta in (-4.,0.,3.), beta in (.4,1.,2.)
        terms=(;offset=[.3],axis=[1.],scale=[beta],steps=[(;values=[x]) for x in steps])
        levels=collect(0:length(steps))
        result=B._score_information_draws(terms,theta,levels)
        p=oracle(theta,.3,steps,beta)
        h=1e-4
        derivative=(-log.(oracle(theta+2h,.3,steps,beta))+8log.(oracle(theta+h,.3,steps,beta))-
            8log.(oracle(theta-h,.3,steps,beta))+log.(oracle(theta-2h,.3,steps,beta)))/(12h)
        @test only(result.expected) ≈ sum(levels.*p) atol=2e-14
        @test only(result.information) ≈ sum(p.*derivative.^2) atol=2e-9 rtol=2e-9
        shifted=B._score_information_draws(terms,theta,levels.+10)
        @test only(shifted.expected) ≈ only(result.expected)+10
        @test shifted.information==result.information
    end
    binary=(;offset=[0.],axis=[1.],scale=[1.],steps=[(;values=[0.])])
    @test only(B._score_information_draws(binary,0.,[0,1]).information)==.25
    @test only(B._score_information_draws(binary,0.,[0,1]).expected)==.5
    for theta in (-700.,700.)
        v=B._score_information_draws(binary,theta,[0,1])
        @test all(isfinite,v.expected) && all(isfinite,v.information)
        @test 0<=only(v.information)<1e-250
    end
    for thresholds in (:partial_credit,:rating_scale)
        fit=reporting_fit(:mfrm;thresholds,chains=2,ndraws=20,warmup=0)
        ids=["rating-$i" for i in 1:fit.design.spec.data.n]
        ratings=[(;id="one",item=1,rater=1,repetitions=2),(;id="two",item=2,rater=2,repetitions=1)]
        kwargs=(;dataset_id="fixed-fixture",observation_ids=ids,ratings,ability_grid=[-2.,0.,2.])
        before=B._cache_hash(fit)
        r=B.score_information_report(fit;kwargs...)
        @test r.n_ratings==3 && r.n_retained_draws==40
        @test length(r.rating_rows)==6 && length(r.test_rows)==3
        @test r.chain_ids==fit.chain_ids && r.iterations==fit.iterations
        @test r.ability_units===:unit_logit && r.information_units===:inverse_squared_unit_logit
        @test r.source_draws_hash==B._cache_hash((;fit.draws,fit.chain_ids,fit.iterations))
        @test r.step_contract.owner== (thresholds===:partial_credit ? :item : :global)
        @test B._prediction_check_seal(r,"bayesianmgmfrm.score_information_report.v1")===nothing
        context=B._recovery_context(fit);_,steps=B._category_report_steps(context)
        profiles=B._category_profiles([(;c.id,c.item,c.rater,dimension=1,kwargs.ability_grid) for c in ratings],context.spec,40,10000)
        for row in r.test_rows
            values=[B._score_information_draws(B._category_profile_terms(context,steps,p),row.ability,r.category_levels) for p in profiles]
            for (name,field) in ((:expected_score,:expected),(:information,:information))
                total=2getproperty(values[1],field)+getproperty(values[2],field)
                summary=getproperty(row,name)
                @test summary.mean≈mean(total)
                @test summary.sd≈std(total)
                @test summary.lower≈quantile(total,.025) && summary.upper≈quantile(total,.975)
                @test summary.mcse!==nothing
            end
        end
        prediction=B.prediction_observations(fit;dataset_id=kwargs.dataset_id,observation_ids=ids)
        @test r.observation_binding==prediction.observation_binding
        # Public report/export keeps conditions, detailed MCSE and global warnings.
        request=(;kwargs.dataset_id,kwargs.observation_ids,score_information=(;ratings,kwargs.ability_grid))
        report=fit_report(fit;OPTIONS...,reporting=request,view=:public,require_complete=true)
        @test report.score_information.status===:computed
        @test report.score_information.result.sampling_warning==r.sampling_warning
        @test report.score_information.source_result_hash==r.content_hash
        @test length(fit_report_rows(report,:score_information;row_field=:test_rows))==3
        @test length(report.score_information.design_rows)==2
        @test occursin("Conditional expected scores",fit_report_markdown(report))
        directory=joinpath(output,String(thresholds))
        save_fit_report_bundle(directory,report;require_complete=true)
        restored=load_fit_report_bundle(directory;require_complete=true)
        @test restored["score_information"]["result"]["n_ratings"]==3
        @test restored["score_information"]["result"]["test_rows"][1]["information"]["mcse"]!==nothing
        @test B._cache_hash(fit)==before
        @test !haskey(B._saved_reporting_request(fit,(;score_information=nothing)),:score_information)
        for bad in ([0.,0.],[0.,Inf],[0.,NaN],[0.],Any[-1.,true])
            @test_throws ArgumentError B.score_information_report(fit;kwargs...,ability_grid=bad)
        end
        @test_throws ArgumentError B.score_information_report(fit;kwargs...,max_curve_cells=1)
        @test_throws ArgumentError B.score_information_report(fit;kwargs...,observation_ids=reverse(fill("same",length(ids))))
        for reps in (0,-1,1.5,true)
            @test_throws ArgumentError B.score_information_report(fit;kwargs...,ratings=[merge(first(ratings),(;repetitions=reps))])
        end
        @test_throws ArgumentError B.score_information_report(fit;kwargs...,ratings=[first(ratings),first(ratings)])
        @test_throws ArgumentError B.score_information_report(fit;kwargs...,ratings=[merge(first(ratings),(;rater="unknown"))])
        @test_throws ArgumentError B._saved_reporting_request(fit,(;score_information=(;ratings)))
    end
end
end
end
