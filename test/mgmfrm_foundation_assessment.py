"""No fitting: pairing, unresolved denominators and nonlinear RMSE aggregation."""
import json
import math
from pathlib import Path
import sys
import tempfile

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import mgmfrm_foundation_assessment as a
from scipy.stats import binomtest

p=a.assessment_pair('check-01',1,20261004020011,20261004020012)
assert all(x['evaluation_credit']==1 and not x['scientific_acceptance'] for x in p)
assert p[0]['raw_truth'][:100]==p[1]['raw_truth'][:100]
assert [r for r in p[0]['observations'] if r['item']=='I3']==[r for r in p[1]['observations'] if r['item']=='I3']
other=a.assessment_pair('check-01',2,20261004020021,20261004020022)
assert p[0]['raw_truth'][:100]!=other[0]['raw_truth'][:100]
for name,block in (('../bad',1),('ok',True),('ok',0)):
    try:
        a.assessment_pair(name,block,1,2)
    except ValueError:
        pass
    else:
        raise AssertionError('Invalid ID/block accepted')
assert a.mean_se([1.,3.])==dict(n=2,mean=2.,replication_mcse=1.)
assert a.mean_se([2.])['replication_mcse'] is None
assert a.rmse_se([1.,9.])['rmse']==math.sqrt(5.)  # Not mean([1,3]).
paired=a.paired_rmse([1.,9.],[4.,36.])
assert paired['difference']==math.sqrt(5.)
assert math.isclose(paired['replication_mcse'],2/math.sqrt(5.))
assert a.paired_rmse([],[])['replication_mcse'] is None
assert a.binomial_envelope(0,32,32)['pointwise_95_envelope']==[0.,1.]
assert a.binomial_envelope(0,0,32)['pointwise_95_envelope'][1]>.10
for n in (8,32):
    for k in (0,1,n-1,n):
        ci=binomtest(k,n).proportion_ci(method='exact')
        assert all(math.isclose(x,y,abs_tol=1e-10) for x,y in zip(
            a.binomial_envelope(k,0,n)['pointwise_95_envelope'],(ci.low,ci.high)))
qs=[dict(probability=.05,estimate=-1.,mcse=.01),dict(probability=.95,estimate=1.,mcse=.01)]
assert a.coverage(0.,qs,True)['coverage']=='covered'
assert a.coverage(.99,qs,True)['coverage']=='unresolved'
assert a.coverage(0.,qs,False)['coverage']=='unresolved'
with tempfile.TemporaryDirectory() as d:
    root=Path(d);attempts=[]
    for block in (1,2):
        for j,(panel,sd) in enumerate(a.CONDITIONS):
            attempts.append(dict(id=f'{block}-{j}',block=block,panel=panel,log_discrimination_sd=sd))
    a.save(root/'plan.json',dict(blocks=2,attempts=attempts,classification_margins_pp=[2.5,5.,7.5]))
    out=root/'attempts'/'1-0';out.mkdir(parents=True)
    a.save(out/'failure.json',dict(phase='sampling'))
    out=root/'attempts'/'2-0';out.mkdir()
    a.save(out/'started.json',{})
    a.summarize(root,root/'summary.json')
    summary=a.read(root/'summary.json')
    assert summary['statuses']==dict(failed=1,incomplete=1,unstarted=10)
    assert summary['conditions'][0]['failure']['descriptive_bounds']==[.5,1.]
    assert len(summary['contrasts'])==7
    assert all(c['planned']==2 and c['eligible_blocks']==[] for c in summary['contrasts'])
    original=a.attempt_result
    def synthetic(root,plan,attempt):
        block=attempt['block'];sd=attempt['log_discrimination_sd']
        error=(2*block-1)*sd/.5
        good=not (attempt['panel']=='R0' and sd==.25 and block==1)
        return dict(id=attempt['id'],block=block,panel=attempt['panel'],sd=sd,
            status='completed',qualified=good,quantities=dict(q=dict(estimate=error,truth=0.,
                error=error,posterior_sd=1.,width=2.,qualified=good,
                coverage='covered' if good else 'unresolved')),
            person_errors={'person:D1':dict(mse=error**2)})
    a.attempt_result=synthetic
    try:
        a.summarize(root,root/'synthetic.json')
    finally:
        a.attempt_result=original
    summary=a.read(root/'synthetic.json')
    assert summary['conditions'][1]['person_rmse']['person:D1']['rmse']==math.sqrt(5.)
    assert summary['contrasts'][0]['eligible_blocks']==[2]
    assert summary['contrasts'][0]['quantities']['q']['error']['replication_mcse'] is None
    delta=summary['contrasts'][1]['person_rmse_difference']['person:D1']
    assert delta['difference']==math.sqrt(5.) and math.isclose(delta['replication_mcse'],2/math.sqrt(5.))
print('Assessment pairing, MCSE, RMSE, coverage and failure-denominator checks passed.')
