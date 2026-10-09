"""Counterexamples and probability invariances for the four-facet derivation."""
import math
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import four_facet_identification_audit as A


def probabilities(adjacent):
    logits = [0.0]
    for value in adjacent:
        logits.append(logits[-1]+value)
    weights = [math.exp(x-max(logits)) for x in logits]
    return [x/sum(weights) for x in weights]


class FourFacetIdentification(unittest.TestCase):
    def test_exact_design_cases(self):
        result = A.audit()
        cases = {x['case']: x for x in result['cases']}
        self.assertEqual(len(cases), 13)
        self.assertEqual(cases['crossed_scalar']['nullity'], 0)
        self.assertEqual(cases['multidimensional_global_criterion_constraint']['nullity'], 1)
        self.assertEqual(cases['unconstrained_steps_alias_criterion']['nullity'], 2)
        self.assertEqual(cases['composite_plus_redundant_task']['nullity'], 2)

    def test_permutation_and_relabelling(self):
        rows = A.cells(3, 3, 2, 2)
        original = A.design(rows, 3, 3, 2, [0, 0], H=2)
        renamed = [(2-p, (t+1) % 3, 1-r, 1-c) for p, t, r, c in reversed(rows)]
        changed = A.design(renamed, 3, 3, 2, [0, 0], H=2)
        self.assertEqual(A.rank(original), A.rank(changed))

    def test_multidimensional_origin_null_vector(self):
        rows = A.cells(3, 3, 2, 4)
        matrix = A.design(rows, 3, 3, 2, [0, 0, 1, 1])
        # Shift all persons by +1 in trait 1 and -1 in trait 2; shift
        # criterion difficulties by [1,1,-1,-1], preserving their global sum.
        null = [1]*3 + [-1]*3 + [0]*3 + [1, 1, -1]
        self.assertTrue(all(sum(x*y for x, y in zip(row, null)) == 0 for row in matrix))

    def test_additive_and_composite_probabilities_match(self):
        theta, task, criterion, rater = .4, -.3, .7, -.2
        for steps in ([0], [-.6, .1, .5]):
            eta = [1.7*(theta-task-criterion-rater-step) for step in steps]
            composite = [1.7*(theta-(task+criterion)-rater-step) for step in steps]
            for left, right in zip(probabilities(eta), probabilities(composite)):
                self.assertAlmostEqual(left, right, places=14)

    def test_two_identifying_gauges_preserve_probabilities(self):
        theta = [[-.2, .3], [.4, -.5], [.7, .8]]
        criterion = [.1, -.1, -.6, .6]  # zero sum within each trait
        means = [sum(row[d] for row in theta)/len(theta) for d in range(2)]
        centered = [[x-means[d] for d, x in enumerate(row)] for row in theta]
        shifted = [value-means[c//2] for c, value in enumerate(criterion)]
        for p, t, r, c in A.cells(3, 3, 2, 4):
            nuisance = [-.3, .1, .2][t] + [-.2, .2][r]
            old = [1.7*(theta[p][c//2]-criterion[c]-nuisance-step) for step in [-.4, .4]]
            new = [1.7*(centered[p][c//2]-shifted[c]-nuisance-step) for step in [-.4, .4]]
            for left, right in zip(probabilities(old), probabilities(new)):
                self.assertAlmostEqual(left, right, places=14)


if __name__ == '__main__':
    unittest.main()
