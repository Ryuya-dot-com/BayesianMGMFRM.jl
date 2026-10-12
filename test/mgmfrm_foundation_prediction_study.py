"""Panel-level aggregation checks; no sampler or saved research data required."""
import math
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
import mgmfrm_foundation_prediction_study as P

POLICY = dict(panel_mcse_max=.005/3, observed_jensen_gap_max=.005,
              sum_absolute_half_difference_max=.01, sum_absolute_prefix_difference_max=.01)


def fixture():
    return [dict(id=f'fold-{f}', block=1, condition='R0', sd=.5, fold=f, seed=100+f,
        status='completed', primary_qualified=True,
        scores=[dict(metric=m, estimate=f/15, status='first_order_candidate',
                     diagnostic=dict(flag='ok'), mcse=.0002) for m in P.METRICS],
        monte_carlo_error=dict(curvature=dict(rows=[dict(observed_jensen_gap=.0001) for _ in P.METRICS]),
            resolution=dict(rows=[dict(late_minus_early=(-1)**f*.0002,
                prefix_minus_full=[.0003, .0001, 0.]) for _ in P.METRICS]))) for f in range(1, 6)]


def pilot_summary():
    def metrics(): return {P.METRICS[0]: dict(n=8, sample_variance=.0004)}
    return dict(stage='pilot', planned_fits=240, statuses=dict(completed=240),
        conditions=[dict(condition=c, sd=s, planned=8, metrics=metrics()) for c, s in P.CONDITIONS],
        contrasts=[dict(baseline=['R0', .5], alternative=['R1', .5], planned=8, metrics=metrics()) for _ in range(7)])


class PredictionStudy(unittest.TestCase):
    def test_sum_folds_not_average_and_independent_stream_mcse(self):
        r = P.panel_result(fixture(), POLICY)
        self.assertTrue(r['qualified']); self.assertFalse(r['failure_known'])
        self.assertAlmostEqual(r['metrics'][0]['estimate'], 1.)
        self.assertAlmostEqual(r['metrics'][0]['mcse'], math.sqrt(5)*.0002)
        self.assertAlmostEqual(r['metrics'][0]['sum_absolute_half_difference'], .001)
        reverse = P.panel_result(list(reversed(fixture())), POLICY)
        self.assertEqual(reverse['qualified'], r['qualified'])
        self.assertAlmostEqual(reverse['metrics'][0]['estimate'], r['metrics'][0]['estimate'])

    def test_missing_failed_and_diagnostic_warning_are_distinct(self):
        for status, known in [('unstarted', False), ('incomplete', False), ('failed', True), ('completed', True)]:
            rows = fixture(); rows[2].update(status=status, primary_qualified=False, scores=None)
            r = P.panel_result(rows, POLICY)
            self.assertFalse(r['complete']); self.assertFalse(r['qualified'])
            self.assertEqual(r['failure_known'], known)
            self.assertEqual(r['usable_folds'], 4); self.assertIsNone(r['metrics'])

    def test_numerical_failures_keep_descriptive_scores(self):
        for key in POLICY:
            p = dict(POLICY); p[key] = 1e-9
            r = P.panel_result(fixture(), p)
            self.assertTrue(r['complete']); self.assertFalse(r['qualified']); self.assertTrue(r['failure_known'])
            self.assertAlmostEqual(r['metrics'][0]['estimate'], 1.)

    def test_missing_mcse_or_curvature_never_implies_precision(self):
        rows = fixture(); rows[0]['scores'][0]['mcse'] = None
        self.assertFalse(P.panel_result(rows, POLICY)['qualified'])
        rows = fixture(); rows[0]['monte_carlo_error']['curvature']['rows'][0]['observed_jensen_gap'] = None
        self.assertFalse(P.panel_result(rows, POLICY)['qualified'])

    def test_duplicate_fold_or_rng_rejected(self):
        rows = fixture(); rows[1]['fold'] = 1
        with self.assertRaises(AssertionError): P.panel_result(rows, POLICY)
        rows = fixture(); rows[1]['seed'] = rows[0]['seed']
        with self.assertRaises(AssertionError): P.panel_result(rows, POLICY)
        with self.assertRaises(AssertionError): P.panel_result(fixture()[:4], POLICY)

    def test_replication_and_mcmc_uncertainty_are_separate(self):
        s = P.summary_stats([1., 2., 3.], [.003]*3)
        self.assertEqual(s['mean'], 2.)
        self.assertAlmostEqual(s['replication_mcse'], 1/math.sqrt(3))
        self.assertAlmostEqual(s['within_mcmc_mcse'], .003/math.sqrt(3))
        self.assertIsNone(P.summary_stats([], [])['sample_variance'])
        self.assertIsNone(P.summary_stats([1.], [None])['within_mcmc_mcse'])

    def test_main_planning_uses_paired_variance_and_eligibility(self):
        s = pilot_summary()
        s['contrasts'][0]['metrics'][P.METRICS[0]].update(n=4, sample_variance=.0064)
        p = P.planning(s)
        self.assertTrue(p['ready']); self.assertEqual(p['selected_blocks'], 128)
        self.assertEqual(p['comparisons'], {'0.005': 512, '0.01': 128, '0.02': 32})

    def test_unfinished_pilot_cannot_select_main_N(self):
        s = pilot_summary(); s['statuses'] = dict(completed=239, incomplete=1)
        with self.assertRaises(AssertionError): P.planning(s)

    def test_too_few_qualified_panels_leave_planning_unresolved(self):
        s = pilot_summary(); s['conditions'][0]['metrics'][P.METRICS[0]]['n'] = 2
        p = P.planning(s)
        self.assertFalse(p['ready']); self.assertIsNone(p['selected_blocks'])


if __name__ == '__main__': unittest.main()
