from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from mgmfrm_foundation_precision_analysis import transitions, EVENTS


class PrecisionSlices(unittest.TestCase):
    def test_full_roster_transition_accounting_and_guards(self):
        pairs=[(True,True),(True,False),(False,None),(None,True),(None,None)]*30
        row=lambda j,v:dict(parameter=f'q{j}',classification={e:v for e in EVENTS})
        left=[row(j,a) for j,(a,_) in enumerate(pairs)]
        right=[row(j,b) for j,(_,b) in enumerate(pairs)]
        counts=transitions(left,right)
        for event in EVENTS:
            self.assertEqual(set(counts[event].values()),{30})
            self.assertEqual(sum(counts[event].values()),150)
        with self.assertRaises(ValueError):transitions(left[:-1],right)
        with self.assertRaises(ValueError):transitions(left,right[::-1])
        right[0]['classification'][EVENTS[0]]=1
        with self.assertRaises(ValueError):transitions(left,right)


if __name__=='__main__':
    unittest.main()
