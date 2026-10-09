"""Independent finite-outcome and Gaussian-integral checks of the worksheet."""
from fractions import Fraction as F
from itertools import product
import math
from pathlib import Path
import sys
import unittest

from scipy.integrate import quad
from scipy.stats import norm
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
import mgmfrm_foundation_acceptance_review as W
from mgmfrm_core_sbc_error_budget import mechanisms, exact_tail


def exact_acceptance(n, s, u, lower, upper):
    return sum((F(math.comb(n, k)*math.comb(n-k, h))*s**k*u**h*(1-s-u)**(n-k-h)
                for k in range(n+1) for h in range(n-k+1)
                if k >= lower and k+h <= upper), F())


class FoundationWorksheet(unittest.TestCase):
    def test_iut_null_and_adverse_power_by_rational_enumeration(self):
        # Wider median margin permits informative small-n exact enumeration.
        # Test the helper's components
        # at exact eighths, independently of binomial CDF implementation.
        from mgmfrm_core_sbc_review import classification_error_power_bound as bound
        for n, hidden, errors in product((7, 12), (0, 1, 2), (0, 1)):
            sides = [bound(n, .5, unresolved_rate=hidden/8, error_rate=errors/8,
                direction=d, nominal=p, family_size=2, alpha=.1)
                for d, p in (('high', .25), ('low', .75))]
            lo, hi = [s['critical_count'] for s in sides]
            for p in (1, 2, 4, 6, 7):
                powers = [exact_acceptance(n, s, u, lo, hi)
                          for s, u in set(mechanisms(p, hidden, errors))]
                if p != 4:
                    self.assertLessEqual(max(powers), F(1, 20))
                else:
                    lower = max(0., 1-sum(1-s['detection_probability_lower_bound'] for s in sides))
                    self.assertGreaterEqual(float(min(powers))+1e-14, lower)
                    for side in sides:
                        actual = min(exact_tail(n, s, u, side['critical_count'], side['direction'])
                                     for s, u in set(mechanisms(p, hidden, errors)))
                        self.assertAlmostEqual(float(actual), side['detection_probability_lower_bound'], places=13)

    def test_production_thresholds_against_direct_binomial_sums(self):
        for u, e in ((0., 0.), (.01, .001), (.05, .001)):
            r = W.acceptance_design(274, quantities=150, margin=.05,
                                   unresolved_rate=u, error_rate=e)
            for row in r['events']:
                for side in row['components']:
                    c, p = side['critical_count'], side['null_reference_probability']
                    tail = lambda k: sum(math.comb(274, j)*p**j*(1-p)**(274-j)
                        for j in range(275) if (j >= k if side['direction']=='high' else j <= k))
                    self.assertLessEqual(tail(c), .05+1e-14)
                    self.assertGreater(tail(c+(-1 if side['direction']=='high' else 1)), .05)
            self.assertEqual(r['event_count'], 300)
            self.assertFalse(r['assumptions_verified'])
            self.assertFalse(r['count_region_nonempty_at_zero_unknowns'])
        self.assertFalse(r['nominal_worst_mechanism_separated'])

    def test_range_quantiles_against_independent_normal_integral(self):
        for row in W.scale_review()['widths']:
            n, tau = row['block_size'], row['kernel_sd']
            for width, expected in ((row['all_pairs_absolute_bound_95'], .95),
                    (row['pairwise_95'][1], row['all_pairs_probability_at_pairwise_bound'])):
                actual = quad(lambda x: n*norm.pdf(x)*(norm.cdf(x+width/tau)-norm.cdf(x))**(n-1),
                              -math.inf, math.inf, epsabs=1e-11)[0]
                self.assertAlmostEqual(actual, expected, places=9)

    def test_invalid_inputs(self):
        base = dict(quantities=150, margin=.05, unresolved_rate=.01, error_rate=.001)
        for key, values in dict(quantities=(0, True), margin=(0., .1, float('nan')),
                                unresolved_rate=(-.1,), error_rate=(.1,), alpha=(.5, True)).items():
            for value in values:
                with self.assertRaises(ValueError):
                    W.acceptance_design(274, **(base | {key: value}))


if __name__ == '__main__':
    unittest.main()
