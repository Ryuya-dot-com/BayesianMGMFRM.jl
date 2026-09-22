"""Plan MCSE and cost from the retained core pilot pair; never run a sampler."""
import argparse
import csv
import json
import math
from pathlib import Path
import statistics

import mgmfrm_core_pilot as pilot

Z = statistics.NormalDist().inv_cdf(1-.05/(2*313))


def project(rows, multipliers, efficiency=(1.,1.), reserve=.5):
    """ESS per retained draw must stay at the supplied fraction of pilot efficiency."""
    values=(*multipliers,*efficiency,reserve)
    if any(isinstance(v,bool) or not isinstance(v,(int,float)) or not math.isfinite(v) or v<=0 for v in values):
        raise ValueError('Finite positive multipliers, efficiencies and reserve are required')
    if len(multipliers)!=2 or len(efficiency)!=2 or reserve>1 or not rows:
        raise ValueError('Two backends, nonempty rows and reserve <= 1 are required')
    projected=[]
    for row in rows:
        errors=[row['julia_mcse'],row['cmdstan_mcse']];tolerance=row['tolerance']
        if any(isinstance(v,bool) or not isinstance(v,(int,float)) or not math.isfinite(v) or v<0 for v in errors) or isinstance(tolerance,bool) or not isinstance(tolerance,(int,float)) or not math.isfinite(tolerance) or tolerance<=0:
            raise ValueError('Available MCSE and positive tolerances are required')
        error=math.sqrt(sum(e*e/(factor*rate) for e,factor,rate in zip(errors,multipliers,efficiency)))
        ratio=Z*error/tolerance
        projected.append(dict(parameter=row['parameter'],role=row['role'],statistic=row['statistic'],
            combined_mcse_reference=error,adjusted_halfwidth_over_tolerance=ratio,
            inside_precision_budget=ratio<=reserve))
    return projected


def reference(directory):
    c=pilot.read(directory/'contract.json');p=pilot.read(directory/'preflight/checked.json')
    original=Path(c['reuse_pilot']['directory'])
    # Validate historical evidence against its archived recipe, not today's edited worker.
    for root in (original,directory):
        recipe=pilot.read(root/'contract.json')
        assert pilot.digest(root/'contract.json')==pilot.read(root/'preflight/checked.json')['contract_sha256']
        assert pilot.digest(recipe['observed_path'])==recipe['observed_sha256']
        for name,expected in recipe['source_sha256'].items():
            assert pilot.digest(root/'frozen-source'/name)==expected,name
    pilot.checked_reuse(c,p)
    fits=[pilot.read(original/'advancedhmc/result.json'),pilot.read(directory/'cmdstan/result.json')]
    for root,backend,fit in zip((original,directory),pilot.BACKENDS,fits):
        assert fit['computationally_qualified'] and fit['backend']==backend
        assert fit['contract_sha256']==pilot.digest(root/'contract.json')
        assert fit['cache_sha256']==pilot.digest(root/backend/'fit.jls')
    comparison=pilot.read(directory/'comparison.json')
    assert pilot.compare_rows(p['focal'],fits)==comparison
    tables=[{r['parameter']:r for r in fit['rows']} for fit in fits]
    rows=[]
    for row in comparison['rows']:
        stat=row['statistic'];pair=[table[row['parameter']] for table in tables]
        errors=[r['mcse']['mean_mcse'] if stat=='mean' else next(q['mcse'] for q in r['mcse']['quantiles'] if q['probability']==stat) for r in pair]
        rows.append(dict(parameter=row['parameter'],role=row['role'],statistic=stat,
            julia_mcse=errors[0],cmdstan_mcse=errors[1],tolerance=row['tolerance']))
    costs=[pilot.read(root/backend/'guard-receipt.json')['seconds'] for root,backend in zip((original,directory),pilot.BACKENDS)]
    return c,rows,costs


def create_plan(directory, output):
    c,rows,costs=reference(directory)
    baseline=project(rows,(1.,1.))
    maximum=max(r['adjusted_halfwidth_over_tolerance'] for r in baseline)
    equal=math.ceil((maximum/.5)**2)
    assert len(rows)==313 and sum(r['role']=='primary' for r in rows)==303
    scenarios=[]
    for efficiency in (1.,.75,.5):
        for factor in (1,2,4,8,10,12,16,20):
            result=project(rows,(factor,factor),(efficiency,efficiency))
            scenarios.append(dict(draw_multiplier=factor,ess_per_draw_relative_to_pilot=efficiency,
                retained_per_chain=1000*factor,retained_per_backend=4000*factor,
                max_adjusted_halfwidth_over_tolerance=max(r['adjusted_halfwidth_over_tolerance'] for r in result),
                statistics_inside_precision_budget=sum(r['inside_precision_budget'] for r in result),
                whole_workflow_linear_reference_minutes=sum(costs)*factor/60))
    candidate=project(rows,(equal,equal))
    bounds=[dict(reserve_fraction=r,equal_length_minimum_multiplier=math.ceil((maximum/r)**2)) for r in (1.,.5,.375,.25)]
    plan=dict(candidate_id=c['candidate_id'],purpose='precision_and_resource_design_only',
        reference_directory=str(directory),reference_comparison_sha256=pilot.digest(directory/'comparison.json'),
        comparison_statistics=313,primary_quantity_statistics=303,secondary_ability_statistics=10,
        z=Z,precision_reserve_fraction=.5,baseline_max_halfwidth_over_tolerance=maximum,
        algebra='predicted variance = pilot_mcse_julia^2/(length_julia*efficiency_julia) + pilot_mcse_cmdstan^2/(length_cmdstan*efficiency_cmdstan)',
        assumptions=[
            'MCMC CLT and the retained asymptotic mean/quantile MCSE estimates are adequate; diagnostics remain necessary.',
            'Within each scenario, ESS per retained draw is a fixed fraction of the pilot value; longer chains do not guarantee this.',
            'Pilot-based tolerances/scales are planning references. The actual unchanged comparison rule recalculates scales from new fits.',
            'The half-allowance budget reserves space for the estimated difference. In an idealized normal-error calculation with zero backend difference and fixed known scales, it allows the same simultaneous 95% error event to imply agreement.',
            'This conditional calculation is not power estimation or a finite-sample guarantee. Existing point differences are not held fixed or used to select statistics.',
            'Whole-workflow time times length is a sensitivity reference, not an upper bound or a timing model validated at long length. Warmup/loading/compilation have not been separated.'
        ],
        statistical_reference='https://mc-stan.org/docs/reference-manual/analysis.html#effective-sample-size',
        reserve_scenarios=bounds,scenarios=scenarios,
        proposed_pair=dict(chains=4,warmup_per_chain=1000,retained_per_chain=1000*equal,
            retained_per_backend=4000*equal,fit_calls=2,new_independent_rng_required=True,
            old_samples_combined=False,model_data_prior_and_comparison_rule_unchanged=True,
            whole_workflow_linear_reference_minutes=sum(costs)*equal/60,
            full_probability_tensor_bytes=4000*equal*1250*4*8,
            probability_tensor_with_256_draw_batches_bytes=256*1250*4*8),
        decision='Keep a fixed-length equal-size pair as a design candidate; do not launch before long-fit resource evidence and an executable frozen contract.',
        existing_fit_limit_seconds=1800,existing_limits_changed=False,
        execution_allowed=False,new_sampler_runs=0,scientific_acceptance=False)
    output.mkdir(parents=True,exist_ok=False)
    pilot.write(output/'plan.json',plan)
    for name,records in (('scenario-costs.csv',scenarios),('candidate-statistic-budgets.csv',candidate)):
        with (output/name).open('x',newline='') as stream:
            writer=csv.DictWriter(stream,fieldnames=list(records[0]));writer.writeheader();writer.writerows(records)
    return plan


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();plan=create_plan(args.reference.resolve(),args.output.resolve())
    print(json.dumps(plan['proposed_pair'],indent=2))
