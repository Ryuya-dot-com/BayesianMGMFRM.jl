"""Check integer scans against the existing scalar, independently tested worksheet."""
from pathlib import Path
import sys
import unittest

import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from mgmfrm_foundation_replication_budget import power_bounds, first_count
from mgmfrm_foundation_acceptance_review import acceptance_design


class ReplicationBudget(unittest.TestCase):
    def test_vectorized_tails_match_scalar_worksheet(self):
        ns=[1,2,100,274,1045,2355,4066,4067,4100,4200,18074,91304]
        for margin,u,e in ((.025,0.,0.),(.05,.01,.001),(.05,.04,.001),(.075,.05,.001)):
            args=dict(margin=margin,unresolved_rate=u,error_rate=e)
            actual=power_bounds(ns,**args)
            expected=[acceptance_design(n,quantities=150,**args)[
                'nominal_joint_acceptance_probability_lower_bound'] for n in ns]
            np.testing.assert_allclose(actual,expected,atol=1e-12,rtol=0)

    def test_scan_does_not_assume_monotone_power(self):
        args=dict(margin=.05,unresolved_rate=.01,error_rate=.001)
        r=first_count(**args)
        self.assertEqual(r['first_count'],4067)
        self.assertLess(r['maximum_bound_at_any_smaller_count'],.8)
        self.assertLess(acceptance_design(4100,quantities=150,**args)[
            'nominal_joint_acceptance_probability_lower_bound'],.8)
        self.assertEqual(r['rounded_design']['n'],4200)
        small=dict(margin=.075,unresolved_rate=0.,error_rate=0.,quantities=1)
        r=first_count(**small,scan_limit=1000)
        n=r['first_count']
        bounds=[acceptance_design(i,**small)['nominal_joint_acceptance_probability_lower_bound']
                for i in range(1,n+1)]
        self.assertLess(max(bounds[:-1]),.8)
        self.assertGreaterEqual(bounds[-1],.8)

    def test_unseparated_capped_and_invalid_searches(self):
        args=dict(margin=.05,unresolved_rate=.05,error_rate=.001)
        self.assertEqual(first_count(**args)['status'],'no_worst_case_separation')
        args['unresolved_rate']=.01
        self.assertEqual(first_count(**args,scan_limit=100)['status'],'not_found_within_scan')
        for ns in ([],[True],[0],[1.5],[[1]]):
            with self.assertRaises(ValueError):power_bounds(ns,**args)
        for value in (True,0,1.5):
            with self.assertRaises(ValueError):first_count(**args,scan_limit=value)


if __name__=='__main__':
    unittest.main()
