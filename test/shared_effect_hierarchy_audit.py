"""Independent mathematical checks; no fitting, package import or dependencies."""
from fractions import Fraction as F
from pathlib import Path
import math
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import shared_effect_hierarchy_audit as A


class SharedEffectHierarchyTests(unittest.TestCase):
    def test_covariance_rank_and_missing_replication(self):
        cases = A.covariance_audit()
        self.assertEqual([x['nullity'] for x in cases], [0, 0, 1, 1, 1, 0, 2])
        # Full covariance rank alone misses a halo cell with only one indicator.
        self.assertEqual(cases[5]['off_diagonal_rank'], 2)
        for p, c, cc in ((0, 0, 0), (0, 0, 1), (0, 1, 1), (1, 0, 1)):
            k = A.kernels((0,0,0,0,c), (p,0,0,1,cc), 2, 2)
            self.assertEqual(k['person_task'], sum(k[v] for v in A.TRAITS))

    def test_orthonormal_coordinates_and_normalization(self):
        for n in (1, 2, 3, 7):
            H = A.helmert(n)
            for j in range(n-1):
                self.assertAlmostEqual(sum(row[j] for row in H), 0)
                for k in range(n-1):
                    self.assertAlmostEqual(sum(row[j]*row[k] for row in H), j == k)
            for i in range(n):
                for j in range(n):
                    self.assertAlmostEqual(sum(a*b for a,b in zip(H[i], H[j])), (i == j)-1/n)
        # R=2 has one free coordinate, distributed as N(0, tau^2/2).
        tau = .8
        mass = A.normal_expectation(lambda z: math.exp(
            A.zero_sum_logpdf([tau*z/math.sqrt(2)], tau) + .5*z*z + .5*A.LOG2PI
        ) * tau/math.sqrt(2))
        self.assertAlmostEqual(mass, 1, places=12)
        self.assertEqual(A.zero_sum_logpdf([], tau), 0)
        # Orthonormal product basis: every interaction row and column sums to zero.
        for R, C in ((3, 2), (2, 4), (3, 1)):
            hr, hc = A.helmert(R), A.helmert(C)
            basis = [[hr[r][i]*hc[c][j] for r in range(R) for c in range(C)]
                     for i in range(R-1) for j in range(C-1)]
            for v in basis:
                for r in range(R):
                    self.assertAlmostEqual(sum(v[r*C:(r+1)*C]), 0)
                for c in range(C):
                    self.assertAlmostEqual(sum(v[c::C]), 0)
            for n in range(R*C):
                for m in range(R*C):
                    expected = ((n//C == m//C)-1/R)*((n%C == m%C)-1/C)
                    self.assertAlmostEqual(sum(v[n]*v[m] for v in basis), expected)

    def test_scale_density_transport_and_gradient(self):
        self.assertEqual(len(A.scale_audit()), 9)
        # A product of R normal pdfs contains one excess -log(tau).
        s = [.2, -.3, .1]
        differences = []
        for tau in (.4, 1.7):
            naive = -len(s)*(.5*A.LOG2PI + math.log(tau)) - sum(x*x for x in s)/(2*tau*tau)
            differences.append(A.zero_sum_logpdf(s[:-1], tau)-naive)
        self.assertAlmostEqual(differences[1]-differences[0], math.log(1.7/.4))
        # Zero-sum relabeling has unit absolute chart Jacobian.
        self.assertAlmostEqual(A.zero_sum_logpdf(s[:-1], .8), A.zero_sum_logpdf(s[1:], .8))

    def test_population_completion_is_an_extra_assumption(self):
        for R in (2, 3, 7):
            P = [[F(i == j)-F(1,R) for j in range(R)] for i in range(R)]
            # Add an independent panel mean: centered covariance becomes iid.
            for i in range(R):
                for j in range(R):
                    self.assertEqual(P[i][j]+F(1,R), int(i == j))
            self.assertNotEqual(P[0][0], 1-F(1,R+1))
            # Transform independent (new rater 1, new rater 2, old panel mean).
            variances = [F(1), F(1), F(1,R)]
            transform = [[1, 0, -1], [0, 1, -1]]
            for i in range(2):
                for j in range(2):
                    covariance = sum(transform[i][k]*transform[j][k]*variances[k] for k in range(3))
                    self.assertEqual(covariance, int(i == j)+F(1,R))

    def test_joint_scoring_oracles(self):
        values = A.score_oracle([[math.log(p)]*2 for p in (.1,.9)])
        self.assertAlmostEqual(values['joint'], math.log(.41))
        self.assertAlmostEqual(values['sum_marginal'], math.log(.25))
        fixed = A.score_oracle([[math.log(.2), math.log(.7)]]*3)
        self.assertAlmostEqual(fixed['joint'], fixed['sum_marginal'])
        extreme = A.score_oracle([[-1000., -1001.], [-1002., -1003.]])
        self.assertTrue(all(math.isfinite(x) for x in extreme.values()))
        for sigma in (0, .3, 1., 2.):
            prob = lambda z: 1/(1+math.exp(-sigma*z))
            p1 = A.normal_expectation(prob)
            p11 = A.normal_expectation(lambda z: prob(z)**2)
            p10 = A.normal_expectation(lambda z: prob(z)*(1-prob(z)))
            self.assertAlmostEqual(p1, .5, places=12)
            self.assertAlmostEqual(2*p11+2*p10, 1, places=12)
            self.assertAlmostEqual(p11, A.normal_expectation(lambda z: prob(z)**2, 4096), places=12)
            if sigma:
                self.assertGreater(p11, p1*p1)
            else:
                self.assertAlmostEqual(p11, .25)

    def test_invalid_oracle_inputs(self):
        for tau in (0, -1, math.inf, math.nan):
            with self.assertRaises(ValueError):
                A.zero_sum_logpdf([0], tau)
        for rows in ([], [[]], [[0], [0,1]], [[math.nan]], [[math.inf]]):
            with self.assertRaises(ValueError):
                A.score_oracle(rows)
        with self.assertRaises(ValueError):
            A.normal_expectation(lambda z: z, 3)


if __name__ == '__main__':
    unittest.main()
