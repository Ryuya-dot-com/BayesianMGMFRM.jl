"""Known answers, prior moments, RNG separation and failure retention; no MCMC."""
import json
import math
from pathlib import Path
import statistics
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import mgmfrm_core_reference as R


class CoreReferenceChecks(unittest.TestCase):
    def test_zero_and_adjacent_logit_known_answers(self):
        q = [0.0]*128
        self.assertEqual(R.log_probabilities(R.state(q), 0, 0, 0), [-math.log(4)]*4)
        q[0] = 1.0
        logs = R.log_probabilities(R.state(q), 0, 0, 0)
        for a,b in zip(logs, logs[1:]):
            self.assertAlmostEqual(b-a, 1.7)
        q[109] = math.log(2.0)
        logs = R.log_probabilities(R.state(q), 0, 0, 0)
        self.assertAlmostEqual(logs[3]-logs[0], 10.2)
        self.assertEqual(R.log_probabilities(R.state(q), 0, 2, 0), [-math.log(4)]*4)

    def test_step_and_last_rater_constraints(self):
        q = [0.0]*128
        q[118] = 1.0
        logs = R.log_probabilities(R.state(q), 0, 0, 0)
        self.assertAlmostEqual(logs[0], logs[3])
        self.assertAlmostEqual(logs[1], logs[2])
        self.assertAlmostEqual(logs[0]-logs[1], 1.7)
        q[100:104] = [0.2,-0.1,0.1,-0.05]
        q[114:118] = [0.1,0.2,-0.1,0.05]
        values = R.state(q)
        self.assertAlmostEqual(sum(values['severity']), 0)
        self.assertAlmostEqual(math.prod(values['consistency']), 1)
        self.assertAlmostEqual(values['severity'][-1], -0.15)
        for row in values['steps']:
            self.assertAlmostEqual(sum(row),0)

    def test_joint_prior_moments_and_coordinate_order(self):
        self.assertEqual(len(R.RAW_NAMES),128)
        self.assertEqual(R.RAW_NAMES[:4],('person[P1,dim=1]', 'person[P1,dim=2]',
                                       'person[P10,dim=1]', 'person[P10,dim=2]'))
        values = [R.prior_raw(9219200+i) for i in range(5000)]
        for index, variance in ((0,1),(1,1),(100,1),(104,1),(109,.25),(114,.25),(118,1)):
            column = [row[index] for row in values]
            self.assertLess(abs(statistics.mean(column)), .07*math.sqrt(variance))
            self.assertLess(abs(statistics.variance(column)/variance-1),.1)
        self.assertLess(abs(statistics.correlation([r[0] for r in values],[r[1] for r in values])),.07)
        self.assertLess(abs(statistics.variance([-sum(r[100:104]) for r in values])-4),.4)
        self.assertLess(abs(statistics.variance([-sum(r[114:118]) for r in values])-1),.1)

    def test_fixed_truth_and_score_rng_are_separate(self):
        raw = R.prior_raw(9219201)
        observed, truth = R.generate(raw,9219301)
        again = R.generate(raw,9219301)
        changed, second = R.generate(raw,9219302)
        self.assertEqual((observed,truth),again)
        self.assertEqual(truth['raw'],second['raw'])
        self.assertEqual(truth['log_probabilities'],second['log_probabilities'])
        self.assertNotEqual(observed,changed)
        self.assertEqual(len(observed['observations']),1250)
        cells = {(r['person'],r['item'],r['rater']) for r in observed['observations']}
        self.assertEqual(len(cells),1250)

    def test_recovery_persons_and_paired_condition_contrast(self):
        a = R.recovery_raw('R0',9232101)
        b = R.recovery_raw('R1',9232101)
        changed = R.recovery_raw('R0',9232102)
        self.assertEqual([i for i in range(128) if a[i] != b[i]], [109,110])
        self.assertNotEqual(a[:100],changed[:100])
        self.assertEqual(a[100:],changed[100:])
        s = R.state(a)
        self.assertEqual(s['difficulty'],[-1.,-.5,0.,.5,1.])
        self.assertEqual(s['severity'],[-.8,-.4,0.,.4,.8])
        self.assertEqual(s['log_consistency'],[-.4,-.2,0.,.2,.4])
        self.assertEqual(s['steps'],[[0.,-.8,0.,.8]]*5)
        for actual,expected in zip(s['loading'],[.7,1.3,.7,1.,1.3]):
            self.assertAlmostEqual(actual,expected)
        # A finite sample is not artificially centered or rescaled.
        for d in (0,1):
            self.assertNotEqual(statistics.mean(a[d:100:2]),0.)
            self.assertNotEqual(statistics.stdev(a[d:100:2]),1.)
        oa,ta = R.generate(a,9232201)
        ob,tb = R.generate(b,9232201)
        for ra,rb,pa,pb in zip(oa['observations'],ob['observations'],ta['log_probabilities'],tb['log_probabilities']):
            if ra['item'] in ('I3','I4','I5'):
                self.assertEqual(ra,rb)
                self.assertEqual(pa,pb)
        for condition,seed in (('R2',1),('R0',True),('R0',-1)):
            with self.assertRaises(ValueError): R.recovery_raw(condition,seed)

    def test_recovery_cli_mode_and_failed_seed_preservation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            command=[sys.executable,R.__file__,'--directory',str(root/'valid'),
                     '--mode','recovery','--condition','R1','--person-seed','9232101',
                     '--score-seed','9232201']
            self.assertEqual(subprocess.run(command,capture_output=True).returncode,0)
            receipt=json.loads((root/'valid/generation.json').read_text())
            self.assertEqual(receipt['mode'],'recovery')
            self.assertEqual(receipt['response_datasets'],1)
            self.assertEqual(json.loads((root/'valid/truth.json').read_text())['raw'],R.recovery_raw('R1',9232101))
            command[3]=str(root/'failed');command[-1]='9232101'
            self.assertNotEqual(subprocess.run(command,capture_output=True).returncode,0)
            receipt=json.loads((root/'failed/generation.json').read_text())
            self.assertEqual(receipt['status'],'generation_failed')
            self.assertEqual(receipt['redraws'],0)
            command[3]=str(root/'mixed')
            self.assertNotEqual(subprocess.run(command+['--truth-seed','1'],capture_output=True).returncode,0)
            self.assertFalse((root/'mixed').exists())

    def test_cdf_boundaries_and_missing_categories_are_kept(self):
        self.assertEqual([R.inverse_cdf([.25]*4,u) for u in (0,.25,.5,.75)], [1,2,3,4])
        self.assertEqual(R.inverse_cdf([0,0,0,1],0),4)
        self.assertEqual(R.inverse_cdf([1,0,0,0],math.nextafter(1,0)),1)
        raw = [1000.0]*100+[0.0]*28
        observed,truth = R.generate(raw,9219401)
        self.assertEqual({r['score'] for r in observed['observations']},{4})
        self.assertEqual(len(truth['log_probabilities']),1250)

    def test_invalid_inputs_and_overflow_are_not_clipped(self):
        for raw in ([0]*127, [float('nan')]*128, [True]*128):
            with self.assertRaises(ValueError): R.state(raw)
        for x in (1000,-1000):
            raw = [0.0]*128; raw[109]=x
            with self.assertRaises((ValueError, OverflowError)): R.generate(raw,1)
        with self.assertRaises(ValueError): R.prior_raw(True)
        with self.assertRaises(ValueError): R.inverse_cdf([.1]*4,.5)

    def test_cli_preserves_failed_attempt_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            raw=[0.0]*128;raw[109]=1000
            supplied=root/'input.json'
            supplied.write_text(json.dumps(dict(raw=raw,raw_names=R.RAW_NAMES)))
            command=[sys.executable,R.__file__,'--directory',str(root/'attempt'),
                     '--mode','fixed','--truth',str(supplied),'--score-seed','9219501']
            result=subprocess.run(command,capture_output=True)
            self.assertNotEqual(result.returncode,0)
            receipt=root/'attempt/generation.json'
            original=receipt.read_bytes()
            self.assertEqual(json.loads(original)['status'],'generation_failed')
            self.assertEqual(json.loads(original)['redraws'],0)
            self.assertTrue((root/'attempt/raw-truth.json').is_file())
            self.assertFalse((root/'attempt/observed.json').exists())
            self.assertNotEqual(subprocess.run(command,capture_output=True).returncode,0)
            self.assertEqual(receipt.read_bytes(),original)


if __name__ == '__main__':
    unittest.main(verbosity=2)
