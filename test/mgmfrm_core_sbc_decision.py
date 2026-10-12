"""Decision safeguards and conditional interval coverage, without any fits."""
import copy
import math
import sys
import unittest
from fractions import Fraction as F
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
import mgmfrm_core_sbc_decision as D
import mgmfrm_core_sbc_plan as P
from mgmfrm_core_rank_review import rank_bands


class Decision(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan = P.proposal([f'x{i}' for i in range(150)], {'source.py': '0'*64})
        bands = rank_bands(range(16000), quantile_ess={p: 8000. for p in (.05, .5, .95)})
        cls.rowsets = {truth: [dict(parameter=name, truth=truth, rank_bands=bands)
                             for name in cls.plan['names']]
                       for truth in (3000., 10000., 20000.)}

    def snapshot(self, *, complete=False, biased=False):
        records = []
        ledger = []
        for i, job in enumerate(self.plan['jobs']):
            if complete or i == 0:
                truth = 20000. if biased else 3000. if i < 137 else 10000. if i < 247 else 20000.
                ledger.append(dict(id=job['id'], status='completed', qualified=True))
                records.append(dict(id=job['id'], plan_identity=P.identity(self.plan),
                                    qualified=True, rows=self.rowsets[truth]))
            elif i == 1:
                ledger.append(dict(id=job['id'], status='failed', qualified=False))
                records.append(dict(id=job['id'], plan_identity=P.identity(self.plan),
                                    qualified=False, rows=None))
            else:
                ledger.append(dict(id=job['id'], status='not_started'))
        return dict(P.collect(self.plan, records), records=records, ledger=ledger)

    def test_incomplete_roster_never_becomes_acceptance(self):
        report = D.assess(self.plan, self.snapshot())
        self.assertEqual(report['screen_state'], 'incomplete')
        self.assertEqual(report['failed_ids'], ['joint-002'])
        self.assertEqual(len(report['unstarted_ids']), 272)
        event = report['rows'][0]['events']['below_median']
        self.assertEqual(event['unresolved'], 273)
        self.assertEqual(event['unresolved_reasons'],
                         dict(failed=1, not_started=272, classification_unresolved=0))
        self.assertFalse(report['scientific_acceptance'])

    def test_complete_nonrejection_and_detected_departure_stay_conditional(self):
        for biased, state, count in ((False, 'conditional_no_departure_detected', 0),
                                     (True, 'conditional_departure_detected', 300)):
            with self.subTest(biased=biased):
                report = D.assess(self.plan, self.snapshot(complete=True, biased=biased))
                self.assertEqual(report['screen_state'], state)
                self.assertEqual(len(report['conditional_flags']), count)
                self.assertTrue(report['fixed_roster_accounted'])
                self.assertFalse(report['scientific_acceptance'])
                self.assertIsNone(report['acceptance_margins'])
                self.assertIn('mgmfrm_classification_error_bound_unverified', report['hold_reasons'])

    def test_changed_summary_missing_ledger_and_false_qualification_rejected(self):
        original = self.snapshot()
        for change in ('count', 'roster', 'qualified', 'pending', 'status', 'acceptance'):
            bad = copy.deepcopy(original)
            if change == 'count': bad['nominal_reference']['rows'][0]['tests']['below_median_low']['covered'] += 1
            elif change == 'roster': bad['ledger'].pop()
            elif change == 'qualified': bad['ledger'][1]['qualified'] = True
            elif change == 'pending': bad['ledger'][0]['status'] = 'not_started'
            elif change == 'status': bad['ledger'][1]['status'] = 'discarded'
            else: bad['scientific_acceptance'] = True
            with self.subTest(change=change), self.assertRaises(ValueError):
                D.assess(self.plan, bad)

    def test_complete_all_failed_is_not_a_clean_screen(self):
        snap = self.snapshot()
        snap['records'] = [dict(id=j['id'], plan_identity=P.identity(self.plan), qualified=False, rows=None)
                           for j in self.plan['jobs']]
        snap['ledger'] = [dict(id=j['id'], status='failed', qualified=False) for j in self.plan['jobs']]
        snap.update(P.collect(self.plan, snap['records']))
        report = D.assess(self.plan, snap)
        self.assertEqual(report['screen_state'], 'no_resolved_outcomes')
        self.assertEqual(report['rows'][0]['events']['covered_90']['conditional_probability_envelope'], [0., 1.])

    def test_unqualified_and_unreadable_slots_remain_unresolved(self):
        snap = self.snapshot()
        snap['records'][0].update(qualified=False, rows=None)
        snap['ledger'][0]['qualified'] = False
        snap['ledger'][1]['status'] = 'evidence_unresolved'
        snap.update(P.collect(self.plan, snap['records']))
        report = D.assess(self.plan, snap)
        self.assertEqual(report['rows'][0]['events']['covered_90']['unresolved'], 274)
        self.assertIn('source_evidence_unresolved', report['hold_reasons'])

    def test_intervals_cover_under_outcome_dependent_missingness_and_errors(self):
        # Independent rational multinomial enumeration, not simulation. Each
        # (known true, unknown, ideal probability) mechanism permits arbitrary
        # outcome dependence and at most .05 resolved-and-wrong probability.
        n = 7
        tail = .1
        mechanisms = [(F(9,20), F(0), F(1,2)), (F(11,20), F(0), F(1,2)),
                      (F(1,4), F(1,5), F(1,2)), (F(11,20), F(1,5), F(1,2)),
                      (F(0), F(1), F(1,2)), (F(0), F(0), F(1,20)),
                      (F(1), F(0), F(19,20))]
        for known, unknown, ideal in mechanisms:
            misses = F()
            for s in range(n+1):
                for u in range(n-s+1):
                    chance = (math.comb(n,s)*math.comb(n-s,u)*known**s*unknown**u
                              *(1-known-unknown)**(n-s-u))
                    lo, hi = D.probability_envelope(s,u,n,tail_alpha=tail,error_rate=.05)
                    if float(ideal) < lo-1e-14 or float(ideal) > hi+1e-14:
                        misses += chance
            self.assertLessEqual(misses, F(1,5))
        for s in range(8):
            for u in range(8-s):
                lo, hi = D.probability_envelope(s,u,7,tail_alpha=tail,error_rate=.05)
                for completed in range(s,s+u+1):
                    inner = D.probability_envelope(completed,0,7,tail_alpha=tail,error_rate=.05)
                    self.assertLessEqual(lo, inner[0])
                    self.assertGreaterEqual(hi, inner[1])

    def test_illustrations_use_fixed_design_and_no_empirical_oracle_claim(self):
        limits = D.design_limits(self.plan)
        self.assertEqual(limits['critical_counts']['below_median']['high'], 169)
        self.assertEqual(limits['critical_counts']['covered_90']['low'], 225)
        for audit in limits['oracle_error_audit_illustrations']:
            alpha = F(1,20*audit['simultaneous_events'])
            n = audit['minimum_n_if_zero_errors']
            # High-precision rational tail at e=.001 proves integer minimality.
            self.assertLessEqual(F(999,1000)**n, alpha)
            self.assertGreater(F(999,1000)**(n-1), alpha)
        self.assertFalse(limits['illustrations_are_acceptance_margins'])

    def test_invalid_counts_and_bounds(self):
        for values in ((True,0,7), (-1,0,7), (5,3,7), (0,0,0)):
            with self.assertRaises(ValueError):
                D.probability_envelope(*values,tail_alpha=.01,error_rate=.001)
        for e in (True, -.1, .1, float('nan')):
            with self.assertRaises(ValueError):
                D.probability_envelope(1,0,7,tail_alpha=.01,error_rate=e)


if __name__ == '__main__':
    unittest.main()
