import math
import sys
import unittest
from pathlib import Path

import numpy as np
from scipy.special import log_ndtr

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from mgmfrm_core_item_conditional import D, ItemConditional, item_conditional


class ConditionalChecks(unittest.TestCase):
    def test_normal_without_data_including_tails(self):
        c = ItemConditional(np.empty((0, 4)), np.empty((0, 4)), np.array([], dtype=int), prior_sd=1.7)
        for z in (-8, -2, 0, 1.4, 8):
            result = c.cdf(1.7*z)
            self.assertAlmostEqual(result['mode'], 0., places=12)
            self.assertAlmostEqual(result['log_cdf'], float(log_ndtr(z)), places=9)
            self.assertLess(result['estimated_quadrature_error'], 1e-8)

    def test_full_dgp_density_difference_and_score(self):
        raw = D.recovery_raw('R0', 9330001)
        observed, _ = D.generate(raw, 9330002)
        rows = observed['observations']
        c = item_conditional(raw, rows, 'I3')

        def full_logdensity(b):
            values = raw.copy(); values[106] = b
            state = D.state(values)
            likelihood = math.fsum(D.log_probabilities(state, D.PERSONS.index(r['person']),
                D.ITEMS.index(r['item']), D.RATERS.index(r['rater']))[r['score']-1] for r in rows)
            return likelihood-.5*b*b

        for b in (-1.2, 0., 1.4):
            self.assertAlmostEqual(c.log_density(b)-c.log_density(.2),
                                   full_logdensity(b)-full_logdensity(.2), places=10)
            finite_difference = (c.log_density(b+1e-5)-c.log_density(b-1e-5))/2e-5
            self.assertAlmostEqual(c.score(b), finite_difference, places=6)
        result = c.cdf(0.)
        tighter = c.cdf(0., epsabs=1e-12, epsrel=1e-10)
        self.assertLess(abs(result['cdf']-tighter['cdf']), 1e-9)
        self.assertLess(c.cdf(-.2)['cdf'], result['cdf'])
        self.assertLess(result['cdf'], c.cdf(.2)['cdf'])
        shuffled = item_conditional(raw, rows[::-1], 'I3')
        self.assertAlmostEqual(shuffled.cdf(0.)['cdf'], result['cdf'], places=11)
        with self.assertRaises(ValueError):
            item_conditional(raw, rows[:-1], 'I5')
        with self.assertRaises(ValueError):
            c.cdf(float('nan'))


if __name__ == '__main__':
    unittest.main()
