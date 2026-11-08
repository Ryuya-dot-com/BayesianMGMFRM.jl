module RaterItemInteractionExample
using BayesianMGMFRM
const RI=BayesianMGMFRM.Experimental.RaterItemInteractions

"""Fixed artificial teaching data and illustrative priors; no generation or fitting."""
function inputs()
    ratings=include(joinpath(@__DIR__,"first_analysis_ratings.jl"))
    data=FacetData(ratings;person=:person,item=:item,rater=:rater,score=:score,category_levels=0:3)
    prior=RI.Prior(person_sd=1.5,item_sd=1.,rater_sd=1.,step_sd=1.,
        interaction_logmean=log(.3),interaction_logsd=.7)
    RI.model(data;prior)
end

"""
Run explicitly with `julia --project rater_item_interactions.jl OUTPUT_DIRECTORY`.
Or add `--saved-fit PATH` after the output directory to review without refitting.
The output directory must not exist. Example margins/priors are not recommendations.
"""
function main(args=ARGS)
    length(args) in (1,3) || throw(ArgumentError("Supply a new output directory, optionally followed by --saved-fit PATH."))
    length(args)==3 && args[2]!="--saved-fit" && throw(ArgumentError("Unknown option."))
    out=abspath(args[1]);ispath(out) && throw(ArgumentError("Preserve existing output directory."))
    target=inputs()
    mkpath(out)
    result=length(args)==3 ? RI.load_result(args[3]) : RI.fit(target;
        chains=4,warmup=1000,ndraws=2000,seed=2026102301,target_accept=.95,max_depth=12)
    # Reject another model/data/prior instead of interpreting it as this example.
    result.target_identity==RI.target_identity(target) ||
        throw(ArgumentError("The saved result does not match this example."))
    RI.save_result(joinpath(out,"fit.jls"),result)
    report=RI.report(result;practical_threshold=.3,interval=.95)
    comparison=RI.contrast(result;left="R2",right="R1",item="I1",practical_threshold=.3,interval=.95)
    RI.save_report(joinpath(out,"report.json"),report)
    RI.save_report(joinpath(out,"contrast.json"),comparison)
    println("Artificial teaching data; experimental jointly fitted interaction model.")
    println("Positive differences mean R2 is more severe than R1. Practical margin: 0.3 unit logits (illustrative).")
    println("Whole-fit numerical screen passed: ",report.diagnostics.qualified)
    for (label,s) in (("Overall",comparison.overall),("Additional on I1",comparison.additional),("Total on I1",comparison.total_at_item))
        println(label,": mean=",s.mean,", 95% interval=[",s.lower,", ",s.upper,"]")
        println("  Mean MCSE: ",s.precision.mean_mcse,"; endpoint MCSE: ",
            first(s.precision.quantiles).mcse,", ",last(s.precision.quantiles).mcse)
    end
    println("Inspect all diagnostic and MCSE rows before interpretation. An interval including zero does not establish equivalence or fairness.")
    (;result,report,comparison)
end
end

if abspath(PROGRAM_FILE)==@__FILE__
    RaterItemInteractionExample.main()
end
