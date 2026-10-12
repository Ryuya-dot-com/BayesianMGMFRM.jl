"""Analytic interval-mass checks for the exact normal classifier oracle."""
from pathlib import Path
import sys
import unittest
from scipy.stats import norm
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from mgmfrm_location_oracle_review import normal_classifier_risk, review


def exact_bands():
    return [dict(probability=p, lower=float(norm.ppf(p)), upper=float(norm.ppf(p))) for p in (.05,.5,.95)]


class LocationOracle(unittest.TestCase):
    def test_exact_quantiles_and_unbounded(self):
        for r in normal_classifier_risk(exact_bands()).values():
            self.assertAlmostEqual(r['correct'],1.)
            self.assertAlmostEqual(r['wrong']+r['unresolved'],0.)
        bands=[dict(probability=p, lower=None, upper=None) for p in (.05,.5,.95)]
        for r in normal_classifier_risk(bands).values():
            self.assertAlmostEqual(r['unresolved'],1.)

    def test_wrong_median_and_coverage_by_interval_arithmetic(self):
        bands=exact_bands()
        bands[1].update(lower=.1,upper=.3)
        r=normal_classifier_risk(bands)['below_median']
        self.assertAlmostEqual(r['wrong'],norm.cdf(.1)-.5)
        self.assertAlmostEqual(r['unresolved'],norm.cdf(.3)-norm.cdf(.1))
        bands=exact_bands()
        bands[0].update(lower=-1.,upper=-.8)
        bands[2].update(lower=1.,upper=1.2)
        r=normal_classifier_risk(bands)['covered_90']
        self.assertAlmostEqual(r['wrong'],norm.cdf(-1.)-.05+.95-norm.cdf(1.2))
        self.assertAlmostEqual(r['unresolved'],norm.cdf(-.8)-norm.cdf(-1.)+norm.cdf(1.2)-norm.cdf(1.))
        self.assertAlmostEqual(sum(r.values()),1.)

    def test_failed_diagnostics_and_low_ess_are_not_successes(self):
        values=[float(norm.ppf((i+.5)/1000)) for i in range(1000)]
        record=dict(qualified=False,z_columns=[values,values],truth_z=[.2,-2.],
                    precision=dict(rows=[dict(quantiles=[dict(probability=p,ess=1000.) for p in (.05,.5,.95)])]*2))
        r=review(record)
        for row in r['rows']:
            self.assertTrue(all(v is None for v in row['actual_truth_classification'].values()))
            self.assertTrue(all(v['unresolved']==1. for v in row['conditional_risk'].values()))
        record['qualified']=True
        record['precision']['rows'][0]['quantiles'][1]['ess']=399.
        self.assertEqual(review(record)['rows'][0]['conditional_risk']['below_median']['unresolved'],1.)
        self.assertFalse(r['dataset_averaged_error_bound_verified'])


if __name__=='__main__':
    unittest.main()
