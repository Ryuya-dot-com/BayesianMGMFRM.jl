"""Lightweight schedule/roster safeguards; no sampler or pilot imports."""
from collections import Counter
import copy
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
import mgmfrm_foundation_efficiency_design as D


class EfficiencyDesignTests(unittest.TestCase):
    def test_coverage_and_finite_denominator(self):
        rows = D.schedule()
        self.assertEqual(len(rows), 32)
        self.assertEqual(Counter(r['case'] for r in rows), dict.fromkeys(D.BALANCED+D.STRESS, 4))
        self.assertEqual({(c.split('-')[1], c.split('-')[2]) for c in D.BALANCED},
                         {(c, s) for c in ('R0', 'R1') for s in ('025', '050', '100')})
        self.assertEqual({c[-1] for c in D.BALANCED}, set('12345'))

    def test_pair_order_is_counterbalanced(self):
        rows = D.schedule()
        for case in D.BALANCED+D.STRESS:
            pair1 = [r['backend'] for r in rows if r['case'] == case and r['repetition'] == 1]
            pair2 = [r['backend'] for r in rows if r['case'] == case and r['repetition'] == 2]
            self.assertEqual(pair1, pair2[::-1])
        self.assertEqual([r['case'] for r in rows[:16:2]], [r['case'] for r in rows[16::2]][::-1])

    def test_seed_ranges_and_disjoint_stream_identifiers(self):
        rows = D.schedule()
        seeds = [r['seed'] for r in rows] + [s for r in rows for s in (r['cmdstan_chain_seeds'] or [])]
        self.assertEqual(len(seeds), len(set(seeds)))
        self.assertTrue(all(0 < s < 2**31 for s in seeds))

    def test_roster_preserves_cross_block_aliases_but_rejects_omissions(self):
        review = {b: [dict(parameter=f'q{i}') for i in range(n)] for b, n in D.COUNTS.items()}
        self.assertEqual(len(D.quantity_roster(review)), 292)
        for block in D.COUNTS:
            broken = copy.deepcopy(review)
            broken[block].pop()
            with self.assertRaises(ValueError):
                D.quantity_roster(broken)
            broken = copy.deepcopy(review)
            broken[block][-1] = broken[block][0]
            with self.assertRaises(ValueError):
                D.quantity_roster(broken)

    def test_existing_receipt_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)/'design.json'
            output.write_text('preserved evidence\n')
            with self.assertRaises(ValueError):
                D.prepare(Path(temporary), output)
            self.assertEqual(output.read_text(), 'preserved evidence\n')

    def test_global_weights_are_not_replaced_by_equal_or_renormalized_weights(self):
        weights = [1/1000]*98 + [1/1500]*152
        total = D.weight_sum(dict(weights=weights))
        self.assertAlmostEqual(total, 0.19933333333333333)
        self.assertNotEqual(total, 0.2)
        for changed in ([1/1250]*250, [w/total for w in weights], weights[:-1]):
            with self.assertRaises(ValueError):
                D.weight_sum(dict(weights=changed))


if __name__ == '__main__':
    unittest.main()
