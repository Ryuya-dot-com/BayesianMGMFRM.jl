"""Analytic oracle checks independent of piecewise partition construction."""
from pathlib import Path
import sys
import unittest
from scipy.stats import norm,lognorm
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from mgmfrm_core_classifier_review import classification_error_mass

PS=(.05,.5,.95)
REF={p:float(norm.ppf(p)) for p in PS}

def quantiles(shift=0.,se=0.):
    return [dict(probability=p,estimate=q+shift,mcse=se) for p,q in REF.items()]

class ClassifierOracle(unittest.TestCase):
    def test_exact_posterior(self):
        r=classification_error_mass(quantiles(),reference_quantiles=REF,cdf=norm.cdf)
        for f,p in (('below_median',.5),('covered_90',.9)):
            self.assertAlmostEqual(r[f]['known_true'],p)
            self.assertAlmostEqual(r[f]['known_false'],1-p)
            self.assertEqual(r[f]['resolved_wrong'],0)
            self.assertEqual(r[f]['unresolved'],0)

    def test_shift_against_closed_form(self):
        r=classification_error_mass(quantiles(shift=.5),reference_quantiles=REF,cdf=norm.cdf)
        self.assertAlmostEqual(r['below_median']['false_positive'],norm.cdf(.5)-.5)
        self.assertEqual(r['below_median']['false_negative'],0)
        self.assertAlmostEqual(r['covered_90']['false_positive'],norm.cdf(REF[.95]+.5)-.95)
        self.assertAlmostEqual(r['covered_90']['false_negative'],norm.cdf(REF[.05]+.5)-.05)

    def test_guard_against_closed_form(self):
        r=classification_error_mass(quantiles(se=.1),reference_quantiles=REF,cdf=norm.cdf)
        self.assertEqual(r['below_median']['resolved_wrong'],0)
        self.assertAlmostEqual(r['below_median']['unresolved'],norm.cdf(.2)-norm.cdf(-.2))
        self.assertEqual(r['covered_90']['resolved_wrong'],0)
        self.assertAlmostEqual(r['covered_90']['unresolved'],sum(norm.cdf(REF[p]+.2)-norm.cdf(REF[p]-.2) for p in (.05,.95)))

    def test_unavailable_and_imprecise_are_unresolved(self):
        for se in (None,2.):
            r=classification_error_mass(quantiles(se=se),reference_quantiles=REF,cdf=norm.cdf)
            for f in r:
                self.assertAlmostEqual(r[f]['unresolved'],1)
                self.assertEqual(r[f]['resolved_wrong'],0)

    def test_skewed_reference_and_invalid_inputs(self):
        distribution=lognorm(s=1.)
        ref={p:float(distribution.ppf(p)) for p in PS}
        qs=[dict(probability=p,estimate=q,mcse=.01) for p,q in ref.items()]
        r=classification_error_mass(qs,reference_quantiles=ref,cdf=distribution.cdf)
        self.assertEqual(r['covered_90']['resolved_wrong'],0)
        for bad in ({.05:-1.,.5:0.},dict(REF,extra=1),{.05:1.,.5:0.,.95:2.}):
            with self.assertRaises(ValueError):classification_error_mass(qs,reference_quantiles=bad,cdf=norm.cdf)
        with self.assertRaises(ValueError):classification_error_mass(qs,reference_quantiles=ref,cdf=norm.cdf)
        with self.assertRaises(ValueError):classification_error_mass(qs,reference_quantiles=ref,cdf=lambda _:float('nan'))

    def test_tail_representative_is_not_rounded_back_onto_guard(self):
        distribution=lognorm(s=1.)
        ref={p:float(distribution.ppf(p)) for p in PS}
        qs=[dict(probability=p,estimate=q,mcse=s) for p,q,s in (
            (.05,.24235423505124104,.0217887541289932),
            (.5,1.0166162920315718,.22092959140124785),
            (.95,5.949489212628503,1.0651924961628576))]
        r=classification_error_mass(qs,reference_quantiles=ref,cdf=distribution.cdf,multiplier=4.)
        med=qs[1];a=med['estimate']-4*med['mcse'];b=med['estimate']+4*med['mcse']
        self.assertAlmostEqual(r['below_median']['unresolved'],distribution.cdf(b)-distribution.cdf(a))
        self.assertAlmostEqual(r['below_median']['known_true'],distribution.cdf(a))

if __name__=='__main__':unittest.main()
