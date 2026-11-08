module RaterGroupExample
using BayesianMGMFRM
const RG=BayesianMGMFRM.Experimental.RaterGroupEffects
"""One saved simulated dataset; illustrative priors, no new generation."""
function inputs()
    table=include(joinpath(@__DIR__,"data/rater_group_positive.jl"))
    data=FacetData(table;person=:person,item=:item,rater=:rater,group=:group,score=:score,category_levels=0:2)
    prior=RG.Prior(person_sd=.9,group_mean_sd=1.4,item_sd=.7,rater_sd=.6,
        step_sd=.8,interaction_logmean=log(.5),interaction_logsd=.6)
    (;data,prior,target=RG.model(data;prior))
end
"""Numerical checks for this teaching example; limits are not scientific decision thresholds."""
function assessment(c)
    s=c.difference_in_differences
    limits=(;mean_mcse=.01,endpoint_mcse=.02,event_mcse=.005,rhat=1.01,ess=400.)
    function check(quantity,value,limit;minimum=false)
        available=value isa Real && !(value isa Bool) && isfinite(value) && value>=0
        passed=available && (minimum ? value>=limit : value<=limit)
        (;quantity,value,limit,comparison=minimum ? :at_least : :at_most,
          status=!available ? :unavailable : passed ? :pass : :fail)
    end
    d=s.contrast_diagnostics
    checks=NamedTuple[check(:focal_rhat,d.rank_normalized_rhat,limits.rhat),
        check(:focal_bulk_ess,d.bulk_ess,limits.ess;minimum=true),
        check(:focal_tail_ess,d.tail_ess,limits.ess;minimum=true),
        check(:mean_mcse,s.precision.mean_mcse,limits.mean_mcse),
        check(:lower_endpoint_mcse,first(s.precision.quantiles).mcse,limits.endpoint_mcse),
        check(:upper_endpoint_mcse,last(s.precision.quantiles).mcse,limits.endpoint_mcse)]
    append!(checks,[check(Symbol(join(("event",row.event,"mcse"),'_')),row.mean_mcse,limits.event_mcse) for row in s.event_rows])
    focal_status=d.status
    passed=c.diagnostics.qualified && focal_status===:available && all(row->row.status===:pass,checks)
    (;source_sample_content_hash=c.source_sample_content_hash,target_identity=c.target_identity,
      evaluated_draws_hash=c.evaluated_draws_hash,
      estimand=(;kind=:rater_gap_group_difference,c.left,c.right,c.group,c.reference_group,
          c.unit,s.interval,c.practical_threshold),
      whole_fit_qualified=c.diagnostics.qualified,focal_status,limits,checks,
      numerical_checks_passed=passed,
      warning="Numerical checks do not establish model fit, equivalence, absence of bias or fairness. Unavailable precision is not a pass.")
end
function main(args=ARGS)
    length(args) in (1,3) || error("Usage: rater_group_effects.jl OUTPUT [--saved-fit PATH]")
    out=args[1];ispath(out) && error("Preserve existing output: $out")
    length(args)==3 && args[2]!="--saved-fit" && error("Expected --saved-fit PATH")
    x=inputs()
    result=length(args)==3 ? RG.load_result(args[3]) :
        RG.fit(x.target;ndraws=2000,warmup=1000,chains=4,seed=73,target_accept=.95,max_depth=12,progress=true)
    result.target_identity==RG.target_identity(x.target) || error("Saved fit has a different input or prior.")
    mkpath(out)
    RG.save_result(joinpath(out,"fit.jls"),result)
    report=RG.report(result;reference_group="A",practical_threshold=.3)
    contrast=RG.contrast(result;left="R1",right="R2",group="B",reference_group="A",practical_threshold=.3)
    RG.save_report(joinpath(out,"report.json"),report)
    RG.save_report(joinpath(out,"contrast.json"),contrast)
    categories=RG.category_report(result)
    RG.save_report(joinpath(out,"categories.json"),categories)
    # An exploratory cell noticed in the descriptive report, not a confirmatory test.
    predictive=RG.category_predictive_check(result;rater="R2",group="A",category=1)
    RG.save_report(joinpath(out,"predictive.json"),predictive)
    checked=assessment(contrast)
    RG.save_report(joinpath(out,"assessment.json"),checked)
    for (name,value) in (("R1-R2 gap at B",contrast.at_group),
            ("R1-R2 gap at A",contrast.at_reference_group),
            ("Change in gap (B-A)",contrast.difference_in_differences))
        println(name,": ",round(value.mean;digits=4)," [95% interval ",
            round(value.lower;digits=4),", ",round(value.upper;digits=4),"]")
    end
    println("Whole-fit diagnostics passed: ",checked.whole_fit_qualified)
    println("Focal diagnostic status: ",checked.focal_status)
    println("Example numerical limits: ",checked.limits)
    for row in checked.checks
        println(row.quantity,": ",row.value,"; ",row.comparison," ",row.limit," -> ",row.status)
    end
    println("All example numerical checks passed: ",checked.numerical_checks_passed)
    println("Group change and within-group gaps answer different questions. ",checked.warning)
    println("Observed/expected category and score rows: categories.json. Expected-value intervals are not fit tests.")
    println("Exploratory R2/A/category 1 count check: predictive.json; inclusive lower/upper tails = ",
        predictive.lower_tail.mean," / ",predictive.upper_tail.mean,
        "; their MCSE = ",predictive.lower_tail.mean_mcse," / ",predictive.upper_tail.mean_mcse)
    println(predictive.warning)
    (;result,report,contrast,assessment=checked,categories,predictive)
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    RaterGroupExample.main()
end
