"""Saved-window sensitivity, never treating the longest window as ground truth."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from mgmfrm_core_rank_review import rank_bands, classify_rank_bands
from mgmfrm_location_oracle_review import normal_classifier_risk

EVENTS=('below_median','covered_90')


def transitions(left,right):
    if len(left)!=150 or len(right)!=150:
        raise ValueError('All 150 quantities required')
    result={event:dict(same_resolved=0,opposite_resolved=0,resolved_to_unresolved=0,
                      unresolved_to_resolved=0,both_unresolved=0) for event in EVENTS}
    for a,b in zip(left,right):
        if a['parameter']!=b['parameter']:
            raise ValueError('Quantity order mismatch')
        for event in EVENTS:
            x,y=a['classification'][event],b['classification'][event]
            if (x is not None and type(x) is not bool) or (y is not None and type(y) is not bool):
                raise ValueError('Boolean event or explicit unknown required')
            key=('both_unresolved' if x is None and y is None else
                 'unresolved_to_resolved' if x is None else
                 'resolved_to_unresolved' if y is None else
                 'same_resolved' if x==y else 'opposite_resolved')
            result[event][key]+=1
    return result


def analyze(root):
    repo=Path(__file__).resolve().parents[1]
    read=lambda p:json.loads(p.read_text())
    digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    plan=read(root/'plan.json')
    assert read(root/'completion.json')['input_and_sources_unchanged']
    for file,h in plan['input_sha256'].items():assert digest(repo/file)==h
    jobs=[];quantile_checks=0;boundary_checks=0
    for job in plan['jobs']:
        original=repo/job['path']
        r=read(original/'review.json');o=read(original/'oracle-input.json')
        x=read(root/(job['id']+'.json'))
        values=np.fromfile(original/'values.bin',dtype='<f8').reshape(4000,150,order='F')
        matrix=np.column_stack((values,np.array(o['z_columns']).T))
        assert x['names'][:150]==r['names'] and x['truths'][:150]==r['truths']
        windows=[]
        for s in x['results']:
            lo,hi=s['first_iteration'],s['last_iteration']
            indices=np.concatenate([np.arange(c*1000+lo-1,c*1000+hi) for c in range(4)])
            assert (indices+1).tolist()==s['selected_rows']
            selected=matrix[indices,:]
            estimates=np.quantile(selected,[.05,.5,.95],axis=0).T
            reported=np.array([[q['estimate'] for q in p['quantiles']] for p in s['precision']['rows']])
            np.testing.assert_allclose(estimates,reported,atol=1e-10,rtol=1e-12)
            quantile_checks+=estimates.size
            if s['id']=='full1000':
                for p,gold in zip(s['precision']['rows'],r['precision']['rows']+o['precision']['rows']):
                    assert p==gold
            for multiplier in (2.,4.):
                rows=[];oracle=[]
                for j,p in enumerate(s['precision']['rows']):
                    ess={q['probability']:q['ess'] if q['ess'] is not None and q['ess']>=400 else None
                         for q in p['quantiles']}
                    bands=rank_bands(selected[:,j],quantile_ess=ess,multiplier=multiplier)
                    ordered=np.sort(selected[:,j]);n=len(ordered)
                    for b in bands:
                        assert b['lower']==(None if b['lower_index']==0 else ordered[b['lower_index']-1])
                        assert b['upper']==(None if b['upper_index']==n+1 else ordered[b['upper_index']-1])
                        boundary_checks+=2
                    row=dict(parameter=p['parameter'],bands=bands,
                        classification=classify_rank_bands(dict(truth=x['truths'][j],rank_bands=bands)))
                    if j<150:
                        rows.append(row)
                    else:
                        oracle.append(dict(row,conditional_risk_before_gate=normal_classifier_risk(bands)))
                qs=[q['ess'] for p in s['precision']['rows'][:150] for q in p['quantiles']]
                windows.append(dict(id=s['id'],draws_per_chain=hi-lo+1,multiplier=multiplier,
                    all_focal_diagnostics_ok=s['all_focal_diagnostics_ok'],
                    diagnostic_warnings=[m['parameter'] for m in s['metrics'][:150] if m['flag']!='ok'],
                    quantile_ess_below_floor=sum(e is not None and e<400 for e in qs),
                    quantile_ess_missing=sum(e is None for e in qs),rows=rows,oracle=oracle,
                    counts={event:{key:sum(r['classification'][event] is value for r in rows)
                        for key,value in [('true',True),('false',False),('unresolved',None)]} for event in EVENTS}))
        comparisons=[]
        for multiplier in (2.,4.):
            by_id={w['id']:w for w in windows if w['multiplier']==multiplier}
            for left,right in (('first250','full1000'),('first500','full1000'),('last500','full1000'),('first500','last500')):
                comparisons.append(dict(left=left,right=right,multiplier=multiplier,
                    counts=transitions(by_id[left]['rows'],by_id[right]['rows'])))
        jobs.append(dict(id=job['id'],original_full_fit_qualified=r['qualified'],
            windows=windows,comparisons=comparisons))
    return dict(jobs=jobs,quantile_values_verified=quantile_checks,boundary_values_verified=boundary_checks,
        input_and_source_sha256={str(p.relative_to(repo)):digest(p) for p in
            [Path(__file__),Path(__file__).with_name('mgmfrm_core_rank_review.py'),
             Path(__file__).with_name('mgmfrm_location_oracle_review.py'),root/'plan.json']},
        new_fits=0,scope='All slice classifications and exact pivot risks are before a global diagnostic gate; focal checks alone are not that gate.',
        longer_window_is_ground_truth=False,windows_are_independent=False,
        disagreements_are_error_rates=False,scientific_acceptance=False)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory',type=Path)
    args=parser.parse_args()
    result=analyze(args.directory.resolve())
    with (args.directory/'analysis.json').open('x') as stream:
        json.dump(result,stream,indent=2,allow_nan=False);stream.write('\n')
    for job in result['jobs']:
        print(job['id'])
        for w in job['windows']:
            if w['multiplier']==2.:
                print(w['id'],'focal_pass',w['all_focal_diagnostics_ok'],'low_ESS',w['quantile_ess_below_floor'],w['counts'])
        for c in job['comparisons']:
            if c['multiplier']==2.:print(c['left'],c['right'],c['counts'])
