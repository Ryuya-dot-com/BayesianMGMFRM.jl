import importlib.util
import math
from pathlib import Path
import unittest
from fractions import Fraction

path=Path(__file__).resolve().parents[1]/'scripts/mgmfrm_core_coverage_review.py'
spec=importlib.util.spec_from_file_location('coverage_review',path)
C=importlib.util.module_from_spec(spec);spec.loader.exec_module(C)


def exact_cdf(k,n,numerator,denominator=10):
    p=Fraction(numerator,denominator)
    return float(sum((math.comb(n,j)*p**j*(1-p)**(n-j) for j in range(k+1)),Fraction()))


class CoverageReview(unittest.TestCase):
    def test_power_and_minimum_from_rational_probabilities(self):
        d=C.design();self.assertEqual((d['n'],d['critical_covered']),(37,28))
        for r in [*d['all_smaller_n'],d]:
            n,k=r['n'],r['critical_covered']
            self.assertAlmostEqual(r['null_rejection_probability'],exact_cdf(k,n,9),places=13)
            self.assertAlmostEqual(r['power'],exact_cdf(k,n,7),places=13)
            self.assertLessEqual(exact_cdf(k,n,9),.01)
            self.assertGreater(exact_cdf(k+1,n,9),.01)
            if n<37:self.assertLess(r['power'],.8)
        self.assertGreaterEqual(d['power'],.8)

    def test_unresolved_cannot_create_a_flag(self):
        known=C.coverage([True]*28+[False]*9,family_size=5)
        unknown=C.coverage([True]*28+[False]*8+[None],family_size=5)
        self.assertTrue(known['detected_undercoverage'])
        self.assertFalse(unknown['detected_undercoverage'])
        self.assertEqual(unknown['planned'],37)
        self.assertEqual(unknown['full_denominator_bounds'],[28/37,29/37])
        self.assertIsNone(unknown['estimate'])
        self.assertIsNone(unknown['plug_in_mcse'])

    def test_missing_envelope_contains_all_completions(self):
        for n in range(1,9):
            for s in range(n+1):
                for m in range(n-s+1):
                    r=C.coverage([True]*s+[None]*m+[False]*(n-s-m),family_size=5)
                    for completed in range(s,s+m+1):
                        full=C.coverage([True]*completed+[False]*(n-completed),family_size=5)
                        for field in ('pointwise_exact_interval_envelope','family_exact_interval_envelope','one_sided_p_value_bounds'):
                            self.assertLessEqual(r[field][0],full[field][0]+1e-14)
                            self.assertGreaterEqual(r[field][1]+1e-14,full[field][1])
                        if r['detected_undercoverage']:self.assertTrue(full['detected_undercoverage'])

    def test_extremes_are_uncertain(self):
        for value in (True,False):
            r=C.coverage([value]*37)
            self.assertTrue(r['zero_empirical_variance'])
            self.assertEqual(r['plug_in_mcse'],0)
            lo,hi=r['pointwise_exact_interval_envelope'];self.assertGreater(hi,lo)
            self.assertFalse(r['scientific_acceptance'])
        r=C.coverage([None]*37)
        self.assertEqual(r['family_exact_interval_envelope'],[0.,1.])
        self.assertFalse(r['detected_undercoverage'])

    def test_more_parameters_cannot_relax_the_screen(self):
        for s in range(38):
            v=[True]*s+[False]*(37-s)
            single=C.coverage(v);family=C.coverage(v,family_size=5)
            if family['detected_undercoverage']:self.assertTrue(single['detected_undercoverage'])
            self.assertLessEqual(family['family_exact_interval_envelope'][0],single['family_exact_interval_envelope'][0])
            self.assertGreaterEqual(family['family_exact_interval_envelope'][1],single['family_exact_interval_envelope'][1])

    def test_invalid_inputs(self):
        for values in ([],[1],[0.],[float('nan')],['covered']):
            with self.assertRaises(ValueError):C.coverage(values)
        for kwargs in ({'family_size':True},{'family_size':0},{'alpha':1},{'nominal':float('nan')}):
            with self.assertRaises(ValueError):C.coverage([True],**kwargs)
        for kwargs in ({'alternative':.9},{'alternative':0},{'power':1},{'power':True}):
            with self.assertRaises(ValueError):C.design(**kwargs)


if __name__=='__main__':unittest.main()
