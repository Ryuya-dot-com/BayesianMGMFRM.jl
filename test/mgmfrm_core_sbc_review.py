"""Arithmetic and failure-accounting checks; no fitted calibration claims."""
from fractions import Fraction
from itertools import product
import math
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
import mgmfrm_core_sbc_review as S


def row(truth, se=0., median=0.):
    return dict(parameter='x', truth=truth, precision=dict(quantiles=[
        dict(probability=p, estimate=q, mcse=se) for p,q in ((.05,-1.),(.5,median),(.95,1.))]))


class SBCReview(unittest.TestCase):
    def test_boundary_and_unavailable_precision(self):
        self.assertEqual(S.classify(row(-.5)),dict(below_median=True,covered_90=True))
        self.assertEqual(S.classify(row(2.)),dict(below_median=False,covered_90=False))
        self.assertEqual(S.classify(row(0.)),dict(below_median=None,covered_90=True))
        self.assertIsNone(S.classify(row(-1.))['covered_90'])
        for se in (None,float('nan'),-.1,.2):
            self.assertEqual(S.classify(row(.5,se)),dict(below_median=None,covered_90=None))
        self.assertIsNone(S.classify(row(.01,.01))['below_median'])
        self.assertIsNone(S.classify(row(.99,.01))['covered_90'])
        self.assertTrue(S.classify(row(.5,.01))['covered_90'])

    def test_failure_and_direction(self):
        records=[dict(id=str(i),qualified=True,rows=[row(-2.)]) for i in range(40)]
        result=S.summarize(records,ids=[r['id'] for r in records],names=['x'])
        tests=result['rows'][0]['tests']
        self.assertTrue(tests['below_median_high']['detected_departure'])
        self.assertTrue(tests['covered_90_low']['detected_departure'])
        self.assertFalse(tests['below_median_low']['detected_departure'])
        self.assertFalse(tests['covered_90_high']['detected_departure'])
        over=[dict(id=str(i),qualified=True,rows=[row(.5)]) for i in range(100)]
        high=S.summarize(over,ids=[r['id'] for r in over],names=['x'])['rows'][0]['tests']
        self.assertTrue(high['covered_90_high']['detected_departure'])
        self.assertTrue(high['below_median_low']['detected_departure'])
        self.assertFalse(high['covered_90_low']['detected_departure'])
        failed=S.summarize([dict(id=r['id'],qualified=False,rows=None) for r in records],ids=result['ids'],names=['x'])
        self.assertEqual(failed['planned'],40)
        self.assertTrue(all(t['unresolved']==40 and not t['detected_departure'] and
                            t['full_denominator_bounds']==[0.,1.] for t in failed['rows'][0]['tests'].values()))
        self.assertFalse(result['calibration_verified'])

    def test_every_unresolved_completion_is_conservative(self):
        for observations in product((-2.,-.5,.5,2.,None), repeat=3):
            records=[dict(id=str(i),qualified=x is not None,rows=None if x is None else [row(x)])
                     for i,x in enumerate(observations)]
            partial=S.summarize(records,ids=['0','1','2'],names=['x'],alpha=.2)['rows'][0]['tests']
            unknown=[i for i,x in enumerate(observations) if x is None]
            for values in product((-2.,-.5,.5,2.),repeat=len(unknown)):
                completed=list(records)
                for i,x in zip(unknown,values):completed[i]=dict(id=str(i),qualified=True,rows=[row(x)])
                full=S.summarize(completed,ids=['0','1','2'],names=['x'],alpha=.2)['rows'][0]['tests']
                for key in full:
                    lo,hi=partial[key]['one_sided_p_value_bounds']
                    p=full[key]['one_sided_p_value_bounds'][0]
                    self.assertLessEqual(lo,p+1e-14);self.assertGreaterEqual(hi,p-1e-14)

    def test_power_against_exact_rational_enumeration(self):
        for n,p,p0 in product((1,8,37,100),(Fraction(1,5),Fraction(1,2),Fraction(9,10)),(Fraction(1,2),Fraction(9,10))):
            r=S.rejection_power(n,float(p),nominal=float(p0),family_size=8)
            exact=sum((math.comb(n,k)*p**k*(1-p)**(n-k) for k in range(n+1)
                       if k<=r['lower_critical'] or k>=r['upper_critical']),Fraction())
            self.assertAlmostEqual(r['power'],float(exact),places=13)
            self.assertLessEqual(r['null_rejection_probability'],.05/4+1e-14)
            null=[math.comb(n,k)*p0**k*(1-p0)**(n-k) for k in range(n+1)]
            lo,hi=r['lower_critical'],r['upper_critical']
            cutoff=Fraction(1,160)
            self.assertLessEqual(sum(null[:lo+1]),cutoff)
            self.assertLessEqual(sum(null[hi:]),cutoff)
            if lo<n:self.assertGreater(sum(null[:lo+2]),cutoff)
            if hi>0:self.assertGreater(sum(null[hi-1:]),cutoff)

    def test_validation(self):
        record=dict(id='a',qualified=True,rows=[row(0.)])
        for records,names in (([record,record],['x']),([record],['x','x']),([record],['y']),
                              ([dict(record,qualified=1)],['x']),([dict(record,rows=None)],['x'])):
            with self.assertRaises(ValueError):S.summarize(records,ids=['a'],names=names)
        for ids in ([],['a','a'],['b']):
            with self.assertRaises(ValueError):S.summarize([record],ids=ids,names=['x'])
        malformed=row(0.);malformed['precision']['quantiles'].append(dict(malformed['precision']['quantiles'][0]))
        with self.assertRaises(ValueError):S.classify(malformed)
        with self.assertRaises(ValueError):S.classify(row(0.,median=2.))
        for truth in (None,float('nan'),float('inf'),True):
            with self.assertRaises(ValueError):S.classify(row(truth))
        for n in (0,True,1.5):
            with self.assertRaises(ValueError):S.rejection_power(n,.7,nominal=.9,family_size=4)

    def test_absent_attempts_keep_the_declared_denominator(self):
        result=S.summarize([dict(id='b',qualified=True,rows=[row(-2.)])],ids=['a','b','c'],names=['x'])
        self.assertEqual(result['planned'],3)
        self.assertEqual(result['absent_ids'],['a','c'])
        self.assertEqual(result['rows'][0]['tests']['below_median_low']['full_denominator_bounds'],[1/3,1.])
        result=S.summarize([],ids=['a','b','c'],names=['x'])
        self.assertTrue(all(t['unresolved']==3 and not t['detected_departure'] for t in result['rows'][0]['tests'].values()))

    def test_random_unresolved_bound_by_exact_multinomial_enumeration(self):
        # Enumerate known successes, known failures and unknowns independently
        # of the helper's binomial reduction. Hide successes/failures in all
        # feasible proportions on a rational grid, including adverse endpoints.
        for n,p,u in product((1,5,10),(Fraction(1,4),Fraction(3,4)),
                             (Fraction(0),Fraction(1,4),Fraction(1,2),Fraction(1))):
            a_min, a_max = max(Fraction(),p+u-1), min(p,u)
            allocations = {a_min,a_max,(a_min+a_max)/2}
            for direction in ('low','high'):
                r=S.unresolved_rate_power_bound(n,float(p),unresolved_rate=float(u),
                    direction=direction,nominal=.5,family_size=4,alpha=.4)
                powers=[]
                for a in allocations:
                    success,failure=p-a,1-p-u+a
                    exact=Fraction()
                    for k in range(n+1):
                        for m in range(n-k+1):
                            flagged=(k>=r['critical_count'] if direction=='high' else k+m<=r['critical_count'])
                            if flagged:
                                exact+=math.comb(n,k)*math.comb(n-k,m)*success**k*u**m*failure**(n-k-m)
                    powers.append(float(exact))
                self.assertAlmostEqual(min(powers),r['detection_probability_lower_bound'],places=13)
                self.assertFalse(r['cap_on_realized_unknown_count_assumed'])
                self.assertFalse(r['resolved_classification_error_included'])
        for u in (-.1,1.1,True,None,float('nan')):
            with self.assertRaises(ValueError):
                S.unresolved_rate_power_bound(10,.7,unresolved_rate=u,direction='high',nominal=.5,family_size=4)
        with self.assertRaises(ValueError):
            S.unresolved_rate_power_bound(10,.7,unresolved_rate=.1,direction='both',nominal=.5,family_size=4)

    def test_adversarial_unresolved_bound_by_all_count_completions(self):
        p=Fraction(1,3)
        for n in range(1,10):
            critical=S.rejection_power(n,float(p),nominal=.5,family_size=4,alpha=.4)
            for m in range(n+1):
                exact=Fraction()
                for total in range(n+1):
                    # Hide at most m outcomes, choosing success/failure counts adversarially.
                    unavoidable=all(total-hidden_success+hidden<=critical['lower_critical'] or
                                    total-hidden_success>=critical['upper_critical']
                        for hidden in range(m+1)
                        for hidden_success in range(max(0,hidden-(n-total)),min(hidden,total)+1))
                    if unavoidable:exact+=math.comb(n,total)*p**total*(1-p)**(n-total)
                bound=S.unresolved_power_bound(n,float(p),max_unresolved=m,nominal=.5,family_size=4,alpha=.4)
                self.assertAlmostEqual(bound['detection_probability_lower_bound'],float(exact),places=13)
        for m in (-1,True,11):
            with self.assertRaises(ValueError):S.unresolved_power_bound(10,.7,max_unresolved=m,nominal=.9,family_size=4)


if __name__=='__main__':unittest.main()
