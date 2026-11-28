# A scoped worked example; including this file starts no estimation or generation.
module RepeatedModerationExample
using BayesianMGMFRM, Statistics
using BayesianMGMFRM.GlassBox
using BayesianMGMFRM.Legacy
using Distributions: Normal, LogNormal
const B=BayesianMGMFRM

function options()
    (person=:speaker,performance=:talk,score=:rating,
     facets=(presentation=:talk,assessor=:judge,prompt=:prompt),steps=:global,category_levels=0:3,
     decompose=(rate=(between=:mean_rate,within=:rate_change),),
     predictors=(person=(mean_rate=Normal(0,.6),),assessor=(experience=Normal(0,.6),),
                 response=(rate_change=Normal(0,.6),)),
     population=(person=LogNormal(log(.6),.45),presentation=LogNormal(log(.4),.45),assessor=LogNormal(log(.35),.45)),
     prior_sd=(facets=(prompt=0.,),step=.45),intercept=Normal(0,.8))
end

function specification(ratings)
    opts=options()
    prepared=contract(mfrm_spec(ratings;opts...)).record.table
    # Use stored means over distinct performances, never averages over rating rows.
    prepared[:experience_between]=prepared[:experience].*prepared[:mean_rate]
    prepared[:experience_within]=prepared[:experience].*prepared[:rate_change]
    predictors=merge(opts.predictors,(response=(rate_change=Normal(0,.6),
        experience_between=Normal(0,.6),experience_within=Normal(0,.6)),))
    mfrm_spec(prepared;opts...,predictors)
end

function report(fit)
    target=getdesign(fit)
    coefficient_names=filter(n->startswith(n,"coefficient["),parameter_names(fit))
    # Native joint chain blocks are retained; coordinates is the public mathematical map.
    joint=reduce(vcat,(permutedims(coordinates(target,q).coefficients) for q in eachrow(fit.record.run.draws)))
    beta(name)=joint[:,only(findall(==("coefficient[$name]"),coefficient_names))]
    b=beta("person,mean_rate");w=beta("response,rate_change")
    db=beta("response,experience_between");dw=beta("response,experience_within")
    emin,emax=extrema(contract(fit).record.table[:experience])
    emin<=-1 && emax>=1 || throw(ArgumentError("This worked example requires the declared experience range [-1,1]."))
    chains=sampler_controls(fit).chains
    summarize(x)=B.posterior_contrast(x,zeros(length(x));chains,interval=.95)
    focal=NamedTuple[];curve=NamedTuple[]
    for e in (-1.,0.,1.)
        for (kind,x) in ((:between,b.+db.*e),(:within,w.+dw.*e),(:within_minus_between,(w.-b).+(dw.-db).*e))
            push!(focal,(;kind,experience=e,summary=summarize(x)))
        end
    end
    for e in range(-1.,1.;length=101)
        for (kind,x) in ((:between,b.+db.*e),(:within,w.+dw.*e),(:within_minus_between,(w.-b).+(dw.-db).*e))
            lo,med,hi=quantile(x,[.025,.5,.975])
            push!(curve,(;kind,experience=e,lower=lo,median=med,upper=hi))
        end
    end
    parameters=[n for n in parameter_names(fit) if startswith(n,"coefficient[") ||
        startswith(n,"residual_sd[") && n!="residual_sd[prompt]"]
    base=fit_report(fit;parameters)
    merge(base,(moderation=(;focal,curve,interaction_difference=summarize(dw.-db),
        direction=:within_minus_between,interval=.95,
        rate_unit=:supplied_source_unit,experience_unit=:supplied_centered_rater_unit,
        band=:pointwise_not_simultaneous,prediction=:conditional_logit_slopes_not_new_rater_predictions,
        computation=:paired_joint_draws,chains,draws_per_chain=length(b)÷chains,
        source_sample_content_hash=base.source_sample_content_hash,
        warnings=["One artificial correctly specified example; not empirical, causal, recovery or prior-robustness evidence.",
            "Experience varies across ten raters; replicated rating rows do not increase the number of raters.",
            "Only e=-1,0,1 receive focal MCSE screens; the full curve is not simultaneously qualified."]),))
end
end
