"""Closed-form planning checks; no pilot files or samplers are needed."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import mgmfrm_core_precision_plan as P

ROW=dict(parameter='p',role='primary',statistic='mean',julia_mcse=.2,cmdstan_mcse=.1,tolerance=1.)

class PrecisionPlanChecks(unittest.TestCase):
    def test_reference_and_square_root_scaling(self):
        a=P.project([ROW],(1,1))[0];b=P.project([ROW],(4,4))[0]
        self.assertAlmostEqual(a['combined_mcse_reference'],.05**.5)
        self.assertAlmostEqual(b['combined_mcse_reference'],a['combined_mcse_reference']/2)
        self.assertFalse(a['inside_precision_budget']);self.assertTrue(b['inside_precision_budget'])

    def test_efficiency_loss_cancels_longer_chains(self):
        a=P.project([ROW],(1,1))[0];b=P.project([ROW],(2,2),(.5,.5))[0]
        self.assertEqual(a,b)

    def test_unequal_backend_allocation_and_irreducible_floor(self):
        a=P.project([ROW],(1,1e12),reserve=.5)[0]
        self.assertGreaterEqual(a['combined_mcse_reference'],.2)
        self.assertFalse(a['inside_precision_budget'])
        b=P.project([ROW],(4,1))[0]
        self.assertAlmostEqual(b['combined_mcse_reference'],.02**.5)

    def test_all_rows_including_resolved_and_secondary_are_kept(self):
        other={**ROW,'parameter':'secondary','role':'secondary','julia_mcse':.001,'cmdstan_mcse':.001}
        result=P.project([ROW,other],(4,4))
        self.assertEqual([r['parameter'] for r in result],['p','secondary'])
        self.assertNotIn('predicted_agreement',result[0])

    def test_inclusive_budget_boundary(self):
        row={**ROW,'julia_mcse':.5/P.Z,'cmdstan_mcse':0.}
        result=P.project([row],(1,1))[0]
        self.assertAlmostEqual(result['adjusted_halfwidth_over_tolerance'],.5)
        self.assertTrue(result['inside_precision_budget'])

    def test_invalid_or_missing_precision_is_rejected(self):
        for value in (None,float('nan'),float('inf'),-.1,True):
            with self.subTest(value=value),self.assertRaises(ValueError):P.project([{**ROW,'julia_mcse':value}],(1,1))
        for value in (0,None,float('nan'),True):
            with self.subTest(tolerance=value),self.assertRaises(ValueError):P.project([{**ROW,'tolerance':value}],(1,1))
        for args in (((0,1),(1,1),.5),((1,1),(.5,0),.5),((1,1),(1,1),1.1)):
            with self.assertRaises(ValueError):P.project([ROW],*args)
        with self.assertRaises(ValueError):P.project([],(1,1))

if __name__=='__main__':unittest.main(verbosity=2)
