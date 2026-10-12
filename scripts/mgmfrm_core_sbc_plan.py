"""Check and collect one prospective core SBC setting; never generate or fit."""
import argparse,copy,hashlib,json
from pathlib import Path
from scipy.stats import norm
from mgmfrm_core_rank_review import rank_band_indices
from mgmfrm_core_sbc_review import summarize,classification_error_sensitivity,classification_error_power_bound

PROFILE=dict(schema='core.prospective_sbc_setting.v1',
    candidate_id='independent_2d_raw_primary_01',generation_mode='prior',
    prior=dict(person_sd=1.,rater_sd=1.,item_sd=1.,log_discrimination_sd=.5,
               log_consistency_sd=.5,step_sd=1.),
    backend='advancedhmc',sampling_coordinates='orthogonal_person_mean_item_offset',
    controls=dict(chains=4,warmup=1000,ndraws=4000,step_size=.03,target_accept=.9,
        max_depth=12,metric='diagonal',ad_backend='ForwardDiff',init_jitter=.1,
        split_chains=True,rhat_threshold=1.01,ess_threshold=400.,progress=False),
    initialization=dict(base_raw=[0.]*128,truth_used=False),
    criteria=dict(chains=4,rhat=1.01,ess=400.,ebfmi=.3,allow_treedepth_hits=False),
    diagnostics='Recompute raw/model/all 150 quantities and all 17 location quantities; complete retained telemetry; same pilot criteria',
    conditional_moments='Report all nine location residual means/MCSE and diagnostics separately; no claim that the prior-002 concern is resolved',
    classification_method='rank_band',band_multiplier=2.,quantile_ess_floor=400.,
    band_policy='ESS below 400 or unavailable becomes an unbounded band; otherwise existing ess_binomial construction',
    sensitivity=dict(band_multiplier=4.,role='descriptive paired comparison; no additional confirmatory flags'),
    power_assumptions=dict(unresolved_rate=.05,error_rate=.001,minimum_power=.8,
        error_definition='Probability of resolved AND wrong per planned dataset, under null AND each alternative',
        dataset_independence_required=True,bounds_verified_for_mgmfrm=False),
    family_alpha=.05,family_size=600,planned_datasets=274,
    attempt_policy=dict(redraw=False,retry=False,extend_draws=False,replace_ids=False,
        drop_failed_or_absent=False,truth_dependent_stopping=False,
        failed_or_absent='Keep every planned ID unresolved; preserve fit/diagnostic/scoring failures',
        wall_timeout_seconds=None),
    interpretation='Conditional sensitivity design, not a certified-power or calibrated-posterior acceptance protocol',
    scientific_acceptance=False,calibration_verified=False)


def identity(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()


def digest(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def reference_power(n, *, error_rate=.001, unresolved_rate=.05):
    alternatives=[('location_shift',float(norm.cdf(.5)),.5,'high'),
                  ('sd_deficit',float(2*norm.cdf(.7*norm.ppf(.95))-1),.9,'low')]
    return [dict(control=name,**classification_error_power_bound(n,p,unresolved_rate=unresolved_rate,
        error_rate=error_rate,direction=direction,nominal=nominal,family_size=600))
        for name,p,nominal,direction in alternatives]


def proposal(names, source_sha256):
    plan=copy.deepcopy(PROFILE)
    plan.update(names=list(names),source_sha256=dict(source_sha256),
        jobs=[dict(id=f'joint-{i:03}',truth_seed=9460000+i,score_seed=9470000+i,fit_seed=9480000+i)
              for i in range(1,275)])
    validate(plan)
    return plan


def validate(plan, *, repository=None):
    """One concrete profile, not a general study configuration language."""
    if set(plan)!=set(PROFILE)|{'names','jobs','source_sha256'}:
        raise ValueError('Missing or unknown execution setting fields')
    if identity({k:plan[k] for k in PROFILE})!=identity(PROFILE):
        raise ValueError('This checker binds the declared profile; changed settings need a separate version')
    names=plan['names'];jobs=plan['jobs']
    if (not isinstance(names,list) or len(names)!=150 or
            any(not isinstance(n,str) or not n.strip() for n in names) or len(set(names))!=150):
        raise ValueError('Exactly 150 unique named quantities required')
    if not isinstance(jobs,list) or len(jobs)!=plan['planned_datasets']:
        raise ValueError('The entire declared roster is required')
    if [j['id'] for j in jobs]!=[f'joint-{i:03}' for i in range(1,275)]:
        raise ValueError('The declared ordered dataset IDs must be retained')
    seeds=[]
    for job in jobs:
        if set(job)!={'id','truth_seed','score_seed','fit_seed'}:
            raise ValueError('Three explicit RNG seeds per dataset required')
        seeds.extend(job[k] for k in ('truth_seed','score_seed','fit_seed'))
    if any(type(s) is not int or not 0<=s<2**32 for s in seeds) or len(set(seeds))!=len(seeds):
        raise ValueError('Distinct nonnegative UInt32-compatible seeds required')
    sources=plan['source_sha256']
    if not isinstance(sources,dict) or not sources:
        raise ValueError('Source and environment hashes required')
    for name,expected in sources.items():
        path=Path(name)
        if (path.is_absolute() or '..' in path.parts or not isinstance(expected,str)
                or len(expected)!=64 or any(c not in '0123456789abcdef' for c in expected)):
            raise ValueError('Repository-relative paths and SHA256 hashes required')
        if repository is not None and digest(Path(repository)/path)!=expected:
            raise ValueError(f'Bound source changed: {name}')
    power=reference_power(plan['planned_datasets'],error_rate=plan['power_assumptions']['error_rate'],
        unresolved_rate=plan['power_assumptions']['unresolved_rate'])
    if min(r['detection_probability_lower_bound'] for r in power)<plan['power_assumptions']['minimum_power']:
        raise ValueError('Conditional reference power does not meet the declared design')
    return dict(plan_identity=identity(plan),planned=274,quantity_count=150,
        total_draws_per_fit=16000,reference_power=power,
        bounds_verified_for_mgmfrm=False,sampler_launched=False,scientific_acceptance=False)


def collect(plan, records):
    """Bind declared band construction to full-roster aggregation.

The Julia adapter must independently bind data, fit, diagnostics and exported
draws. This checks its declared settings, not the origin of arbitrary numbers.
"""
    checked=validate(plan);records=list(records)
    for record in records:
        if record['plan_identity']!=checked['plan_identity']:
            raise ValueError('Attempt belongs to a different execution setting')
        for row in record['rows'] or []:
            for band in row['rank_bands']:
                ess=band['ess']
                if ess is not None and (not isinstance(ess,(int,float)) or ess<plan['quantile_ess_floor']):
                    raise ValueError('Insufficient quantile ESS must be declared unavailable')
                expected=rank_band_indices(16000,band['probability'],ess=ess,multiplier=plan['band_multiplier'])
                if identity({k:band[k] for k in expected})!=identity(expected):
                    raise ValueError('Rank band does not match the declared draw count/ESS/width')
                if ((band['lower'] is None)!=(band['lower_index']==0) or
                        (band['upper'] is None)!=(band['upper_index']==16001)):
                    raise ValueError('Rank endpoint sentinels disagree with the declared band')
    summary=summarize(records,ids=[j['id'] for j in plan['jobs']],names=plan['names'],
        alpha=plan['family_alpha'],classification_method=plan['classification_method'])
    return dict(plan_identity=checked['plan_identity'],nominal_reference=summary,
        error_rate_sensitivity=classification_error_sensitivity(summary,error_rate=plan['power_assumptions']['error_rate']),
        bounds_verified_for_mgmfrm=False,scientific_acceptance=False)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('plan',type=Path)
    parser.add_argument('--records',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();plan=json.loads(args.plan.read_text())
    checked=validate(plan,repository=Path(__file__).resolve().parents[1])
    result=collect(plan,json.loads(args.records.read_text())) if args.records else checked
    with args.output.open('x') as stream:json.dump(result,stream,indent=2,allow_nan=False);stream.write('\n')
