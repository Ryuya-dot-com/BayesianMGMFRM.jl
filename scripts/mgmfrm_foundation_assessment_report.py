"""Read-only interpretation of a frozen assessment snapshot; never changes fit eligibility."""
import argparse
import datetime as dt
import hashlib
import math
from pathlib import Path
import re
import statistics as st

import mgmfrm_foundation_assessment as A


def finite(x):
    return isinstance(x,(int,float)) and not isinstance(x,bool) and math.isfinite(x)


def ratio(a,b):
    return a/b if finite(a) and finite(b) and a>=0 and b>0 else None


def maximum(values):
    return max((x for x in values if finite(x)),default=None)


def transition_times(log, attempt):
    events={}
    pattern=re.compile(r'^(\S+) '+re.escape(attempt)+r' chain (\d+) (start|end|transition (\d+))$')
    for line in log.splitlines():
        match=pattern.fullmatch(line)
        if match:
            stamp,chain,event,_=match.groups()
            key=(int(chain),event)
            if key in events: raise ValueError('Repeated chain event')
            events[key]=dt.datetime.fromisoformat(stamp)
    warmup=retained=0.
    for chain in range(1,5):
        start,end=(events[chain,k] for k in ('start','end'))
        middle,final=(events[chain,k] for k in ('transition 1000','transition 2000'))
        if not start<=middle<final<=end: raise ValueError('Invalid event ordering')
        warmup+=(middle-start).total_seconds()
        retained+=(final-middle).total_seconds()
    return dict(warmup_log_seconds=warmup,retained_log_seconds=retained)


def analyze(root,snapshot,output):
    plan=A.read(root/'plan.json');summary=A.read(snapshot)
    assert summary['plan_sha256']==A.sha(root/'plan.json')
    for path,digest in plan['source_sha256'].items():
        assert A.sha(A.REPO/path)==digest,path
    sources={str(snapshot):A.sha(snapshot)}
    completed=[r for r in summary['rows'] if r['status']=='completed']
    first={w:next(a['id'] for a in plan['attempts'] if (a['block']-1)%2+1==w) for w in (1,2)}
    logs={w:(root/f'worker-{w}.log').read_text() for w in (1,2)}
    costs=[]
    for row in completed:
        out=root/'attempts'/row['id'];records={}
        for name in ('started.json','execution.json','completion.json','core/review.json','extra.json','loading-review.json'):
            p=out/name;records[name]=A.read(p);sources[str(p)]=A.sha(p)
        started,execution=records['started.json'],records['execution.json']
        core,extra,loading=(records[name] for name in ('core/review.json','extra.json','loading-review.json'))
        assert started['plan_sha256']==summary['plan_sha256']
        assert execution['samples_sha256']==A.sha(out/'samples.jls')
        assert execution['counts']==[2000]*4
        for review in (core,extra,loading):
            assert review['samples_sha256']==execution['samples_sha256']
            assert review['target_identity']==execution['target_identity']
        diagnostics=core['focal']+core['location']+core['residuals']
        diagnostics += [r['diagnostic'] for r in extra['rows']+loading['rows']]
        minimum=lambda key:min((r for r in diagnostics if finite(r[key])),key=lambda r:r[key],default=None)
        worker=(row['block']-1)%2+1
        times=transition_times(logs[worker],row['id'])
        fit=execution['elapsed_seconds']
        start_time=dt.datetime.fromisoformat(started['created_utc']).replace(tzinfo=dt.timezone.utc).timestamp()
        total=(out/'completion.json').stat().st_mtime-start_time
        post=(out/'completion.json').stat().st_mtime-(out/'execution.json').stat().st_mtime
        assert total>=fit>0 and post>=0
        min_bulk=minimum('bulk_ess');ess=min_bulk['bulk_ess'] if min_bulk else None
        costs.append(dict(id=row['id'],qualified=row['qualified'],first_in_worker=row['id']==first[worker],
            fit_seconds=fit,**times,attempt_wall_seconds_from_timestamps=total,
            post_execution_seconds_from_timestamps=post,
            fit_outside_transition_windows_seconds=fit-sum(times.values()),
            retained_leapfrog_steps=execution['retained_leapfrog_steps'],
            retained_steps_per_draw=execution['retained_leapfrog_steps']/4000,
            minimum_bulk_ess=min_bulk,minimum_tail_ess=minimum('tail_ess'),
            maximum_rhat=maximum(r['rank_normalized_rhat'] for r in diagnostics),
            unavailable_diagnostic_rows=sum(any(not finite(r[k]) for k in ('bulk_ess','tail_ess','rank_normalized_rhat')) for r in diagnostics),
            bulk_ess_per_fit_second=ratio(ess,fit) if row['qualified'] else None,
            bulk_ess_per_retained_log_second=ratio(ess,times['retained_log_seconds']) if row['qualified'] else None,
            bulk_ess_per_attempt_wall_second=ratio(ess,total) if row['qualified'] else None,
            max_extra_mean_mcse_over_sd=maximum(ratio(r['precision']['mean_mcse'],r['posterior_sd']) for r in extra['rows']),
            max_loading_mean_mcse_over_sd=maximum(ratio(r['precision']['mean_mcse'],r['posterior_sd']) for r in loading['rows']),
            prediction_unqualified=sum(not r['qualified'] for r in extra['prediction']),
            max_probability_mean_mcse=maximum(r['mean_mcse'] for r in extra['prediction']),
            divergences=core['diagnostic']['n_divergences'],depth_hits=core['diagnostic']['n_max_treedepth'],
            rmse_mcmc_se={k:r['rmse_mcse'] for k,r in row['person_errors'].items()}))
    by_id={r['id']:r for r in completed}
    attempts={(a['block'],a['panel'],a['log_discrimination_sd']):a['id'] for a in plan['attempts']}
    mcmc_contrasts=[]
    for c in summary['contrasts']:
        cells=[]
        for block in c['eligible_blocks']:
            a=by_id[attempts[(block,*c['baseline'])]];b=by_id[attempts[(block,*c['alternative'])]]
            cells.append(dict(block=block,person_rmse={key:dict(
                difference=b['person_errors'][key]['rmse']-a['person_errors'][key]['rmse'],
                combined_mcmc_se=math.hypot(a['person_errors'][key]['rmse_mcse'],b['person_errors'][key]['rmse_mcse']))
                for key in a['person_errors']}))
        mcmc_contrasts.append(dict(baseline=c['baseline'],alternative=c['alternative'],rows=cells))
    calibration=[]
    for margin in plan['classification_margins_pp']:
        possible=[]
        for k in range(plan['blocks']+1):
            lo,hi=A.binomial_envelope(k,0,plan['blocks'])['pointwise_95_envelope']
            if .9-margin/100<=lo and hi<=.9+margin/100:possible.append(k)
        calibration.append(dict(margin_pp=margin,planned=plan['blocks'],possible_success_counts_if_all_resolved=possible))
    groups=[]
    for cold in (True,False):
        selected=[r for r in costs if r['first_in_worker']==cold]
        groups.append(dict(first_in_worker=cold,n=len(selected),
            median_fit_seconds=st.median(r['fit_seconds'] for r in selected) if selected else None,
            median_post_execution_seconds=st.median(r['post_execution_seconds_from_timestamps'] for r in selected) if selected else None))
    monitor=A.read(root/'reattached-monitor.json')
    A.save(output,dict(created_utc=dt.datetime.now(dt.timezone.utc).isoformat(),
        plan_sha256=summary['plan_sha256'],snapshot_sha256=A.sha(snapshot),script_sha256=A.sha(Path(__file__)),
        log_prefixes={str(root/f'worker-{w}.log'):dict(bytes=len(log.encode()),sha256=hashlib.sha256(log.encode()).hexdigest())
                      for w,log in logs.items()},
        source_sha256=sources,statuses=summary['statuses'],qualified=summary['qualified'],
        costs=costs,cost_groups=groups,within_block_mcmc_contrasts=mcmc_contrasts,
        calibration_feasibility=calibration,monitor_snapshot=monitor,
        scientific_acceptance=False,interpretation='Descriptive completed-at-snapshot analysis; completion order is not a random sample. '
        'Replication MCSE remains in the frozen summary; within-block MCMC SE is a separate first-order approximation. '
        'ESS rates are conditional on numerical qualification and retain unqualified rows if present. '
        'Transition timing uses logged boundaries; fit timing includes warmup/setup and may include compilation. '
        'File-timestamp phase timing is approximate. First/warm fits use different data and are not a compilation speed benchmark. '
        'Calibration feasibility is pointwise and assumes no unresolved cases; it is not global acceptance. '
        'Predictive rows remain in-sample.'))


def self_check():
    assert ratio(None,1.) is None and ratio(1.,0.) is None and ratio(2.,4.)==.5
    assert maximum([None,float('nan')]) is None
    lines=[]
    for c in range(1,5):
        for second,event in ((0,'start'),(2,'transition 1000'),(5,'transition 2000'),(5,'end')):
            lines.append(f'2026-10-04T00:00:0{second}.000 test chain {c} {event}')
    log='\n'.join(lines)
    assert transition_times(log,'test')==dict(warmup_log_seconds=8.,retained_log_seconds=12.)
    for invalid in (log+'\n'+lines[0], '\n'.join(lines[:-1])):
        try:transition_times(invalid,'test')
        except (KeyError,ValueError):pass
        else:raise AssertionError('Incomplete or repeated events accepted')
    print('Phase timing check passed; no fitting.')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-check',action='store_true')
    parser.add_argument('--root',type=Path);parser.add_argument('--snapshot',type=Path);parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    if args.self_check:self_check()
    else:
        if any(p is None for p in (args.root,args.snapshot,args.output)):parser.error('--root, --snapshot and --output required')
        analyze(args.root,args.snapshot,args.output)
