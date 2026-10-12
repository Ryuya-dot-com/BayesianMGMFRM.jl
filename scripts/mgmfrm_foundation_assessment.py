"""Fixed 32-block assessment. Immutable inputs, persistent workers, paired summaries."""
import argparse
from collections import Counter
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import shutil
import statistics as st
import subprocess
import sys
import time

import numpy as np
import psutil
import scipy
from scipy.stats import beta

from mgmfrm_foundation_fixed_facet_input import assessment_pair
from paired_rating_resource_guard import run_guarded

REPO = Path(__file__).resolve().parents[1]
CONDITIONS = [(p, s) for p in ('R0', 'R1') for s in (.25, .5, 1.)]
read = lambda p: json.loads(p.read_text())
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()


def save(path, value):
    with path.open('x') as f:
        json.dump(value, f, indent=2, allow_nan=False)
        f.write('\n')


def mean_se(values):
    return dict(n=len(values), mean=st.mean(values) if values else None,
                replication_mcse=st.stdev(values)/math.sqrt(len(values)) if len(values)>1 else None)


def rmse_se(mses):
    m = mean_se(mses)
    r = math.sqrt(m['mean']) if mses else None
    return dict(n=m['n'], rmse=r, replication_mcse=m['replication_mcse']/(2*r)
                if r and m['replication_mcse'] is not None else None)


def paired_rmse(left, right):
    if len(left) != len(right):
        raise ValueError('Paired blocks required')
    a, b = rmse_se(left)['rmse'], rmse_se(right)['rmse']
    se = mean_se([y/(2*b)-x/(2*a) for x, y in zip(left, right)])['replication_mcse'] if a and b else None
    return dict(n=len(left), difference=b-a if left else None, replication_mcse=se)


def binomial_envelope(k, unresolved, n):
    """Pointwise exact-binomial envelope across all resolutions, never simultaneous."""
    if not 0 <= k <= k+unresolved <= n or n < 1:
        raise ValueError('Invalid planned denominator')
    lo = float(beta.ppf(.025, k, n-k+1)) if k else 0.
    hi = float(beta.ppf(.975, k+unresolved+1, n-k-unresolved)) if k+unresolved<n else 1.
    return dict(planned=n, count=k, unresolved=unresolved,
                descriptive_bounds=[k/n, (k+unresolved)/n], pointwise_95_envelope=[lo, hi])


def coverage(truth, quantiles, eligible):
    qs = {q['probability']: q for q in quantiles}
    lo, hi = qs[.05], qs[.95]
    width = hi['estimate']-lo['estimate']
    finite = all(isinstance(q['mcse'], (int, float)) and math.isfinite(q['mcse']) and q['mcse']>=0 for q in (lo, hi))
    resolved = eligible and finite and width>0 and max(lo['mcse'],hi['mcse'])/width<=.05
    near = finite and any(abs(truth-q['estimate'])<=2*q['mcse'] for q in (lo, hi))
    return dict(width=width, coverage='unresolved' if not resolved or near else
                'covered' if lo['estimate']<=truth<=hi['estimate'] else 'not_covered')


def attempt_result(root, plan, a):
    out = root/'attempts'/a['id']
    row = dict(id=a['id'], block=a['block'], panel=a['panel'], sd=a['log_discrimination_sd'],
               status='unstarted', qualified=False, quantities={}, person_errors={})
    if (out/'started.json').exists():
        row['status'] = 'incomplete'
    if (out/'failure.json').exists():
        row.update(status='failed', failure=read(out/'failure.json'))
    if not (out/'completion.json').exists():
        return row
    c, e, l = [read(out/p) for p in ('core/review.json', 'extra.json', 'loading-review.json')]
    assert read(out/'completion.json')['completed'] is True
    assert read(out/'started.json')['plan_sha256']==sha(root/'plan.json')
    data = read(REPO/a['input'])
    assert sha(REPO/a['input']) == a['input_sha256']
    assert data['scope']==plan['scope'] and data['assessment_id']==plan['assessment_id']
    assert (data['block'], data['condition'], data['person_seed'], data['score_seed']) == (
        a['block'], a['panel'], a['person_seed'], a['score_seed'])
    sample_hash = sha(out/'samples.jls')
    for review in (c, e, l):
        assert review['input_sha256']==a['input_sha256'] and review['samples_sha256']==sample_hash
        assert review['target_identity']==a['target_identity']
    assert e['core_review_sha256']==sha(out/'core/review.json')
    assert sha(out/'core/values.bin')==c['values']['sha256']
    assert c['values']['shape']==[4000,150] and c['values']['format']=='little_endian_float64'
    assert c['values']['order']=='column_major'
    qualified = e['primary_quantities_qualified'] and all(r['qualified90'] for r in l['rows'])
    assert len(l['rows'])==5 and len(e['rows'])==111
    row.update(status='completed', qualified=qualified, core_qualified=c['qualified'],
               extra_qualified=e['primary_quantities_qualified'],
               loading_qualified=sum(r['qualified90'] for r in l['rows']),
               diagnostic=c['diagnostic'], execution=read(out/'execution.json'))
    values = np.fromfile(out/'core/values.bin', dtype='<f8').reshape((4000,150), order='F')
    assert np.isfinite(values).all()
    quantities = row['quantities']
    def add(name, estimate, truth, sd, quantiles, eligible, mean_mcse=None):
        quantities[name] = dict(estimate=estimate, truth=truth, error=estimate-truth,
            posterior_sd=sd, mean_mcse=mean_mcse, qualified=eligible,
            **coverage(truth, quantiles, eligible))
    for j, (name, truth, precision) in enumerate(zip(c['names'], c['truths'], c['precision']['rows'])):
        assert name==precision['parameter']
        add(name,float(values[:,j].mean()),truth,float(values[:,j].std(ddof=1)),precision['quantiles'],qualified)
    theta = np.asarray(data['raw_truth'][:100]).reshape(50,2)
    mu = theta.mean(axis=0); loga = np.asarray(data['raw_truth'][109:114])
    truth = np.concatenate((mu,(theta-mu).ravel(),loga,[loga[i]-loga[j] for i,j in ((0,1),(2,3),(2,4),(3,4))]))
    for r, t in zip(e['rows'], truth):
        if r['parameter'] in quantities:
            assert abs(quantities[r['parameter']]['truth']-t)<1e-12
        add(r['parameter'],r['estimate'],float(t),r['posterior_sd'],r['precision']['quantiles'],
            qualified and r['qualified'],r['precision']['mean_mcse'])
    for r in l['rows']:
        add(r['parameter'],r['estimate'],r['truth'],r['posterior_sd'],r['precision']['quantiles'],
            qualified and r['qualified90'],r['precision']['mean_mcse'])
    row['person_errors'] = {f"{r['block']}:D{r['dimension']}":r for r in e['error_mcse']}
    return row


def summarize(root, destination):
    plan = read(root/'plan.json'); n = plan['blocks']
    rows = [attempt_result(root,plan,a) for a in plan['attempts']]
    assert len(rows)==6*n and len({r['id'] for r in rows})==6*n
    summaries=[]; groups={}
    names=sorted({name for r in rows for name in r['quantities']})
    for panel, sd in CONDITIONS:
        group=[r for r in rows if (r['panel'],r['sd'])==(panel,sd)]
        assert sorted(r['block'] for r in group)==list(range(1,n+1))
        groups[panel,sd]={r['block']:r for r in group}
        failures=sum(r['status']=='failed' or (r['status']=='completed' and not r['qualified']) for r in group)
        pending=sum(r['status'] in ('unstarted','incomplete') for r in group)
        qrows={}
        for name in names:
            available=[r['quantities'][name] for r in group if name in r['quantities']]
            eligible=[q for q in available if q['qualified']]
            k=sum(q['coverage']=='covered' for q in available)
            u=n-sum(q['coverage']!='unresolved' for q in available)
            cov=binomial_envelope(k,u,n)
            cov['margin_comparison']={str(m): ('within_pointwise_envelope' if
                cov['pointwise_95_envelope'][0]>=.9-m/100 and cov['pointwise_95_envelope'][1]<=.9+m/100
                else 'not_established') for m in plan['classification_margins_pp']}
            qrows[name]=dict(bias=mean_se([q['error'] for q in eligible]),
                rmse=rmse_se([q['error']**2 for q in eligible]),
                posterior_sd=mean_se([q['posterior_sd'] for q in eligible]),
                interval_width=mean_se([q['width'] for q in eligible]),coverage90=cov)
        person={key:rmse_se([r['person_errors'][key]['mse'] for r in group if r['qualified']])
                for key in sorted({k for r in group for k in r['person_errors']})}
        summaries.append(dict(panel=panel,sd=sd,statuses=dict(Counter(r['status'] for r in group)),
            qualified=sum(r['qualified'] for r in group),failure=binomial_envelope(failures,pending,n),
            quantities=qrows,person_rmse=person))
    contrasts=[]
    pairs=[((p,.5),(p,s)) for p in ('R0','R1') for s in (.25,1.)]
    pairs += [(('R0',s),('R1',s)) for s in (.25,.5,1.)]
    for left,right in pairs:
        a,b=groups[left],groups[right]
        ids=[i for i in range(1,n+1) if a[i]['qualified'] and b[i]['qualified']]
        quantities={}
        for name in names:
            x=[a[i]['quantities'][name] for i in ids]; y=[b[i]['quantities'][name] for i in ids]
            quantities[name]={key:mean_se([v[key]-u[key] for u,v in zip(x,y)])
                              for key in ('estimate','error','posterior_sd','width')}
        person={key:paired_rmse([a[i]['person_errors'][key]['mse'] for i in ids],
                               [b[i]['person_errors'][key]['mse'] for i in ids])
                for key in sorted({k for r in rows for k in r['person_errors']})}
        contrasts.append(dict(baseline=left,alternative=right,planned=n,eligible_blocks=ids,
                              quantities=quantities,person_rmse_difference=person))
    save(destination,dict(plan_sha256=sha(root/'plan.json'),planned_fits=6*n,
        statuses=dict(Counter(r['status'] for r in rows)),qualified=sum(r['qualified'] for r in rows),
        rows=rows,conditions=summaries,contrasts=contrasts,scientific_acceptance=False,
        interpretation='Continuous summaries condition on full focal numerical qualification. '
        'Replication MCSE uses independent blocks; paired changes share block IDs. '
        'Coverage envelopes are pointwise, conditional on correct classifications, not simultaneous '
        'calibration acceptance. Two-MCSE boundary screens do not bound MCMC misclassification. '
        'Failures and unfinished attempts retain planned denominators. No heldout prediction claim.'))


def prepare(root, julia):
    root.mkdir(); (root/'inputs').mkdir()
    n=32; assessment_id=root.name
    for block in range(1,n+1):
        for payload in assessment_pair(assessment_id,block,20261004020000+10*block+1,20261004020000+10*block+2):
            save(root/'inputs'/f"B{block:02}-{payload['condition']}.json",payload)
    save(root/'design.json',dict(schema='mgmfrm.foundation_fixed_facet_assessment.v1',
        assessment_id=assessment_id,scope='prospective_fixed_facet_assessment',blocks=n,evaluation_credit=1,
        scientific_acceptance=False,execution_allowed=True,independent_scientific_review='unassigned',
        authorization='User authorized additional estimation through statistical validation on existing local resources.',
        controls_policy='Four chains, 1000 warmup + 1000 draws; unchanged foundation controls.',
        retries=0,redraws=0,extensions=0,classification_margins_pp=[2.5,5.,7.5],
        primary_eligibility='Existing core and extra gates plus all five positive-loading 90% precision screens.',
        limits=dict(wall_seconds=None,rss_bytes=8*1024**3,output_bytes=8*1024**3,maximum_workers=2,
                    second_worker_min_available_bytes=5*1024**3,first_worker_max_rss_bytes=3500*1024**2),
        hardware=dict(platform=platform.platform(),cpu_count=psutil.cpu_count(),
                      memory=dict(psutil.virtual_memory()._asdict()),disk_free=shutil.disk_usage(root).free),
        python_environment=dict(python=platform.python_version(),numpy=np.__version__,scipy=scipy.__version__,psutil=psutil.__version__)))
    subprocess.run([julia,'--startup-file=no','--project=.',str(REPO/'scripts/mgmfrm_foundation_assessment.jl'),
                    'prepare',str(root)],cwd=REPO,check=True)


def workers(root):
    plan=read(root/'plan.json'); plan_hash=sha(root/'plan.json')
    for path,digest in plan['source_sha256'].items():
        assert sha(REPO/path)==digest,path
    base=[plan['julia_binary'],'--startup-file=no','--project=.',str(REPO/'scripts/mgmfrm_foundation_assessment.jl'),
          'worker',str(root)]
    with (root/'worker-1.log').open('x') as log1, (root/'worker-2.log').open('x') as log2:
        first=subprocess.Popen(base+['1'],stdout=log1,stderr=subprocess.STDOUT,cwd=REPO)
        peak=0; second=None; receipt=None
        while first.poll() is None:
            assert sha(root/'plan.json')==plan_hash,'Plan changed'
            try:
                peak=max(peak,psutil.Process(first.pid).memory_info().rss)
            except psutil.NoSuchProcess:
                pass
            completed=(root/'attempts'/plan['attempts'][0]['id']/'completion.json').exists()
            available=psutil.virtual_memory().available
            if second is None and completed and peak<=plan['limits']['first_worker_max_rss_bytes'] and available>=plan['limits']['second_worker_min_available_bytes']:
                receipt=dict(mode='measured_parallel',first_peak_rss=peak,available_bytes=available)
                save(root/'parallel-decision.json',receipt)
                second=subprocess.Popen(base+['2'],stdout=log2,stderr=subprocess.STDOUT,cwd=REPO)
            time.sleep(1)
        if first.returncode:
            raise RuntimeError(f'Worker 1 stopped: {first.returncode}; inspect log')
        if second is None:
            save(root/'parallel-decision.json',dict(mode='serial',first_peak_rss=peak,
                 available_bytes=psutil.virtual_memory().available))
            second=subprocess.Popen(base+['2'],stdout=log2,stderr=subprocess.STDOUT,cwd=REPO)
        if second.wait():
            raise RuntimeError('Worker 2 stopped; inspect log')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=('prepare','run','workers','summarize'))
    parser.add_argument('root',type=Path);parser.add_argument('--julia');parser.add_argument('--output',type=Path)
    args=parser.parse_args();root=args.root.resolve()
    if args.action=='prepare':
        if not args.julia: parser.error('--julia required')
        prepare(root,args.julia)
    elif args.action=='summarize':
        if args.output is None: parser.error('--output required (never overwrites)')
        summarize(root,args.output)
    elif args.action=='workers':
        workers(root)
    else:
        plan=read(root/'plan.json')
        for key in ('JULIA_NUM_THREADS','OPENBLAS_NUM_THREADS','JULIA_NUM_PRECOMPILE_TASKS'):
            os.environ[key]='1'
        os.environ['JULIA_PKG_PRECOMPILE_AUTO']='0'
        receipt=run_guarded([sys.executable,str(Path(__file__).resolve()),'workers',str(root)],
            root/'guard',cwd=str(REPO),output_root=root,poll_seconds=1,wall_seconds=None,
            rss_bytes=plan['limits']['rss_bytes'],output_bytes=plan['limits']['output_bytes'])
        summarize(root,root/'summary.json')
        print(json.dumps(receipt),flush=True)
        sys.exit(0 if receipt['status']=='completed' else 1)
