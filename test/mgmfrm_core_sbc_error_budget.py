"""Check error-budget bounds against rational joint outcome enumeration."""
from fractions import Fraction as F
from itertools import product
from pathlib import Path
import math,sys,unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import mgmfrm_core_sbc_review as S


def exact_tail(n,success,unknown,critical,direction):
    total=F()
    for s in range(n+1):
        for u in range(n-s+1):
            reject=s>=critical if direction=='high' else s+u<=critical
            if reject:
                total+=math.comb(n,s)*math.comb(n-s,u)*success**s*unknown**u*(1-success-unknown)**(n-s-u)
    return total


def mechanisms(p,u,e):
    # Eighths: success/failure may each be correct, wrong, or unresolved.
    for hidden_success in range(min(p,u)+1):
        for hidden_failure in range(min(8-p,u-hidden_success)+1):
            for false_negative in range(min(p-hidden_success,e)+1):
                for false_positive in range(min(8-p-hidden_failure,e-false_negative)+1):
                    yield F(p-hidden_success-false_negative+false_positive,8),F(hidden_success+hidden_failure,8)


class ErrorBudget(unittest.TestCase):
    def test_rational_joint_mechanisms_and_null_error(self):
        for n,u,e,direction in product((7,12),(0,1,2),(0,1,2),('low','high')):
            for p in (2,4,6):
                result=S.classification_error_power_bound(n,p/8,unresolved_rate=u/8,
                    error_rate=e/8,direction=direction,nominal=.5,family_size=4,alpha=.4)
                powers=[exact_tail(n,s,h,result['critical_count'],direction) for s,h in set(mechanisms(p,u,e))]
                self.assertAlmostEqual(float(min(powers)),result['detection_probability_lower_bound'],places=13)
                if p==4:self.assertLessEqual(max(powers),F(1,10))
                self.assertFalse(result['error_bound_verified'])

    def test_zero_error_recovers_previous_bound(self):
        for n,p,u,direction in product((1,8,274),(.2,.7),(.0,.05),('low','high')):
            old=S.unresolved_rate_power_bound(n,p,unresolved_rate=u,direction=direction,nominal=.5,family_size=600)
            new=S.classification_error_power_bound(n,p,unresolved_rate=u,error_rate=0.,direction=direction,nominal=.5,family_size=600)
            for key in ('critical_count','adverse_event_probability','detection_probability_lower_bound'):
                self.assertEqual(old[key],new[key])

    def test_summary_adjustment_matches_design_and_keeps_unknowns(self):
        n=50;ids=[str(i) for i in range(n)]
        # Deterministic bands let truths encode every success count, without draws.
        bands=[dict(probability=p,lower=x,upper=x) for p,x in ((.05,-1),(.5,0),(.95,1))]
        for successes in range(n+1):
            for missing in (0,min(3,n-successes)):
                records=[dict(id=str(i),qualified=i<n-missing,
                    rows=[dict(parameter='x',truth=-2. if i<successes else 2.,rank_bands=bands)] if i<n-missing else None) for i in range(n)]
                summary=S.summarize(records,ids=ids,names=['x'],classification_method='rank_band')
                original=summary['rows'][0]['tests'];zero=S.classification_error_sensitivity(summary,error_rate=0.)
                guarded=S.classification_error_sensitivity(summary,error_rate=.05)
                for key,t in original.items():
                    self.assertEqual(zero['rows'][0]['tests'][key]['one_sided_p_value'],t['one_sided_p_value_bounds'][1])
                    self.assertGreaterEqual(guarded['rows'][0]['tests'][key]['one_sided_p_value'],t['one_sided_p_value_bounds'][1])
                for direction in ('low','high'):
                    r=S.classification_error_power_bound(n,.5,unresolved_rate=.1,error_rate=.05,
                        nominal=.5,direction=direction,family_size=4)
                    flag=successes>=r['critical_count'] if direction=='high' else successes+missing<=r['critical_count']
                    self.assertEqual(guarded['rows'][0]['tests']['below_median_'+direction]['detected_departure'],flag)
                self.assertFalse(guarded['scientific_acceptance'])

    def test_invalid_settings(self):
        for e in (-.1,.5,True,None,float('nan')):
            with self.assertRaises(ValueError):S.classification_error_power_bound(20,.7,unresolved_rate=.05,error_rate=e,direction='high',nominal=.5,family_size=600)
        for p in (-.1,1.1,True,None):
            with self.assertRaises(ValueError):S.classification_error_power_bound(20,p,unresolved_rate=.05,error_rate=.001,direction='high',nominal=.5,family_size=600)
        for e in (-.1,.1,True,None,float('nan')):
            with self.assertRaises(ValueError):S.classification_error_sensitivity({},error_rate=e)


if __name__=='__main__':unittest.main()
