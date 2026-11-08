module CriterionCollapseExample
using BayesianMGMFRM
const C=BayesianMGMFRM.Experimental.CriterionCollapse
"""Fixed simulated input and illustrative prior; no random data generation."""
function inputs()
    table=include(joinpath(@__DIR__,"data/criterion_collapse_ordinary.jl"))
    data=FacetData(table;person=:person,item=:item,rater=:rater,score=:score,category_levels=0:2)
    prior=C.Prior(person_precision_shape=3.,person_precision_rate=2.,
        rater_precision_shape=3.,rater_precision_rate=.5,step_sd=1.5,class_alpha=1.,class_beta=1.)
    (;data,prior,target=C.model(data;prior))
end
"""Numerical tolerances for this example only, not classification cutoffs."""
function assessment(report,categories)
    report.source_sample_content_hash==categories.source_sample_content_hash || error("Different fitted samples")
    checks=NamedTuple[]
    function check(name,value,limit)
        available=value isa Real && isfinite(value) && value>=0
        push!(checks,(;name,value,limit,status=!available ? :unavailable : value<=limit ? :pass : :fail))
    end
    for s in report.parameter_summary
        s.parameter=="pi" && continue
        branch=startswith(s.parameter,"branch_shift[")
        check(s.parameter*" mean",s.mean_mcse,branch ? .02 : .05)
        check(s.parameter*" lower",s.interval.lower_mcse,branch ? .05 : .10)
        check(s.parameter*" upper",s.interval.upper_mcse,branch ? .05 : .10)
    end
    for s in report.classes;check("rater $(s.rater) class",s.mean_mcse,.02);end
    for s in categories.rows;check("rater $(s.rater) criterion $(s.criterion) category $(s.category)",s.expected.mean_mcse,.02);end
    (;whole_fit_qualified=report.diagnostics.qualified && categories.diagnostics.qualified,
        focal_checks=checks,numerical_checks_passed=report.diagnostics.qualified &&
        categories.diagnostics.qualified && all(x->x.status===:pass,checks),
        warning="These are numerical tolerances. No class cutoff, calibrated detection, absence of other mechanisms or fairness claim follows.")
end
function main(args=ARGS;chain_execution=:serial,max_parallel_chains=4)
    length(args) in (1,3) || error("Usage: criterion_collapse.jl OUTPUT [--saved-fit PATH]")
    length(args)==3 && args[2]!="--saved-fit" && error("Expected --saved-fit PATH")
    out=args[1];ispath(out) && error("Preserve existing output: $out")
    x=inputs()
    result=length(args)==3 ? C.load_result(args[3]) :
        C.fit(x.target;ndraws=1000,warmup=1000,chains=4,seed=2026102731,
            target_accept=.9,max_depth=10,progress=true,chain_execution,max_parallel_chains)
    result.target_identity==C.target_identity(x.target) || error("Saved fit has different data, categories or prior")
    mkpath(out);C.save_result(joinpath(out,"fit.jls"),result)
    report=C.report(result);categories=C.category_report(result);checked=assessment(report,categories)
    C.save_report(joinpath(out,"report.json"),report)
    C.save_report(joinpath(out,"categories.json"),categories)
    C.save_report(joinpath(out,"assessment.json"),checked)
    comparison=compare_models(result)
    prediction=predictive_check(result;category=1,rater_weights=Dict(1=>-1,2=>-1,3=>1,4=>1),
        model=:all_ordinary,max_count_updates=200_000_000)
    heldout=compare_models(result;criterion=:loo,unit=:performance_rater)
    heldout_receipt=save_report(joinpath(out,"heldout.json"),heldout;return_receipt=true)
    comparison_receipt=save_report(joinpath(out,"comparison.json"),comparison;return_receipt=true)
    prediction_receipt=save_report(joinpath(out,"prediction.json"),prediction;return_receipt=true)
    # Keep receipts separately so computed reports can be checked when reopened.
    open(joinpath(out,"report-receipts.json"),"w") do io
        BayesianMGMFRM.JSON3.write(io,(;comparison=comparison_receipt,prediction=prediction_receipt,heldout=heldout_receipt))
    end
    for row in report.classes
        println("Rater ",row.rater,": P(criterion collapse | ratings) = ",row.mean,"; MCSE = ",row.mean_mcse)
    end
    println("Whole-fit diagnostic pass: ",checked.whole_fit_qualified)
    println("Example focal precision pass: ",all(x->x.status===:pass,checked.focal_checks))
    for row in checked.focal_checks
        row.status===:pass || println(row.name,": ",row.status,"; MCSE ",row.value,"; limit ",row.limit)
    end
    println(report.warning)
    println("Category profiles are saved in categories.json. ",categories.warning)
    println("Log BF ordinary versus any collapse: ",comparison.log_bf_ordinary_vs_any_collapse.estimate,
        "; MCSE: ",comparison.log_bf_ordinary_vs_any_collapse.mcse)
    println("Ordinary-submodel count-contrast upper tail: ",prediction.upper_tail.estimate,
        "; MCSE: ",prediction.upper_tail.mcse)
    println("The earlier focal assessment covers classes/categories. Inspect comparison/prediction diagnostics and MCSE separately. ",prediction.warning)
    println("Held-out profile log-score difference (mixture minus ordinary): ",heldout.difference.estimate,
        "; MCSE: ",heldout.difference.mcse,". Inspect heldout.json for failed profiles and precision limits.")
    (;result,report,categories,assessment=checked,comparison,prediction,heldout)
end
end
abspath(PROGRAM_FILE)==abspath(@__FILE__) && CriterionCollapseExample.main()
