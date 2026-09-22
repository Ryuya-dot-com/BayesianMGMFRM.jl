"""Owned Python workers exercise the real bounded preflight journal, without fits."""
import argparse
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
import mgmfrm_core_preflight as F

ROOT = None


class PreflightChecks(unittest.TestCase):
    def setup_batch(self, **options):
        root = ROOT/self._testMethodName
        plan = dict(ids=['a', 'b'])
        jobs = [dict(job_id=x, dataset_id=x, fold=None, split_seed=None) for x in ['a', 'b']]
        c = F.prepare(root, plan, jobs, **options)
        return root, c

    def outcome_command(self, c, job, status='preflight_passed', change=''):
        code = f'''import json,hashlib
from pathlib import Path
r=Path({c['directory']!r});out=r/{job['job_id']!r}
for n in ['preflight.json','prepared.jls']:(out/n).write_text('fixture')
d=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
v=dict(contract_sha256=d(r/'contract.json'),job_id={job['job_id']!r},dataset_id={job['dataset_id']!r},fold=None,status={status!r},new_sampler_runs=0,scientific_acceptance=False,artifact_sha256={{n:d(out/n) for n in ['preflight.json','prepared.jls']}})
{change}
(out/'result.json').write_text(json.dumps(v))
'''
        return [sys.executable, '-c', code]

    def run_fixture(self, code, **options):
        root, c = self.setup_batch(**options)
        with patch.object(F, 'command', side_effect=code):
            result = F.run(root)
        self.assertEqual(result, F.inspect(root))
        self.assertEqual(result['planned'], 2)
        with self.assertRaises(FileExistsError):
            F.run(root)
        return root, result

    def test_completion_and_rejection(self):
        root, r = self.run_fixture(lambda c,j:self.outcome_command(c,j,
            'preflight_passed' if j['job_id']=='a' else 'pre_fit_rejected'))
        self.assertEqual([x['status'] for x in r['rows']], ['preflight_passed','pre_fit_rejected'])
        before = {str(p):F.P.digest(p) for p in root.rglob('*') if p.is_file()}
        F.inspect(root)
        self.assertEqual(before, {str(p):F.P.digest(p) for p in root.rglob('*') if p.is_file()})

    def test_nonzero_stops_remaining(self):
        _,r=self.run_fixture(lambda c,j:[sys.executable,'-c','raise SystemExit(7)'])
        self.assertEqual([x['status'] for x in r['rows']], ['command_failed','not_started'])

    def test_wall_limit(self):
        _,r=self.run_fixture(lambda c,j:[sys.executable,'-c','import time;time.sleep(10)'], seconds=.3)
        self.assertEqual(r['rows'][0]['status'],'wall_limit')
        self.assertTrue(r['rows'][0]['worker_termination_confirmed'])
        self.assertEqual(r['rows'][1]['status'],'not_started')

    def test_sigterm(self):
        _,r=self.run_fixture(lambda c,j:[sys.executable,'-c',
            'import os,signal,time;os.kill(os.getppid(),signal.SIGTERM);time.sleep(10)'])
        self.assertEqual(r['rows'][0]['status'],'interrupted')
        self.assertTrue(r['rows'][0]['worker_termination_confirmed'])
        self.assertEqual(r['rows'][1]['status'],'not_started')

    def test_missing_result(self):
        _,r=self.run_fixture(lambda c,j:[sys.executable,'-c','pass'])
        self.assertEqual(r['rows'][0]['status'],'evidence_unresolved')
        self.assertEqual(r['rows'][1]['status'],'not_started')

    def test_wrong_result_identity(self):
        _,r=self.run_fixture(lambda c,j:self.outcome_command(c,j,change="v['dataset_id']='wrong'"))
        self.assertEqual(r['rows'][0]['status'],'evidence_unresolved')

    def test_incomplete_json(self):
        _,r=self.run_fixture(lambda c,j:[sys.executable,'-c',
            f"from pathlib import Path;Path({str(Path(c['directory'])/j['job_id']/'result.json')!r}).write_text('{{')"])
        self.assertEqual(r['rows'][0]['status'],'evidence_unresolved')

    def test_unknown_crash_and_guard_only_recovery(self):
        root,c=self.setup_batch()
        job=c['jobs'][0];args=self.outcome_command(c,job)
        F.publish(root/'batch-started.json',dict(contract_sha256=F.P.digest(root/'contract.json')))
        F.publish(root/'a-started.json',dict(contract_sha256=F.P.digest(root/'contract.json'),job=job,command=args))
        unknown=F.inspect(root)
        self.assertEqual(unknown['rows'][0]['status'],'started_unresolved')
        self.assertFalse(unknown['rows'][0]['worker_termination_confirmed'])
        F.P.launch(c,'a',args,seconds=3)
        recovered=F.inspect(root)
        self.assertEqual(recovered['rows'][0]['status'],'preflight_passed')
        self.assertEqual(recovered['rows'][1]['status'],'not_started')
        self.assertFalse((root/'a-terminal.json').exists())
        with self.assertRaises(FileExistsError):F.run(root)

    def test_post_completion_artifact_change(self):
        root,r=self.run_fixture(self.outcome_command)
        (root/'a'/'prepared.jls').write_text('changed')
        self.assertEqual(F.inspect(root)['rows'][0]['status'],'evidence_unresolved')

    def test_changed_contract_and_source(self):
        root,c=self.setup_batch()
        c['source_sha256']['scripts/mgmfrm_core_evaluation.jl']='0'*64
        (root/'contract.json').write_text(json.dumps(c))
        with self.assertRaises(ValueError):F.run(root)
        self.assertFalse((root/'batch-started.json').exists())

    def test_publish_never_replaces(self):
        root,c=self.setup_batch()
        before=(root/'contract.json').read_bytes()
        with self.assertRaises(FileExistsError):F.publish(root/'contract.json',{})
        self.assertEqual(before,(root/'contract.json').read_bytes())
        self.assertEqual(list(root.glob('.pending-*')),[])

    def test_controller_exception_preserves_roster(self):
        root,c=self.setup_batch()
        with patch.object(F.P,'launch',side_effect=RuntimeError('injected controller failure')):
            with self.assertRaises(RuntimeError):F.run(root)
        r=F.inspect(root)
        self.assertEqual([x['status'] for x in r['rows']],['started_unresolved','not_started'])
        self.assertFalse(r['rows'][0]['worker_termination_confirmed'])
        with self.assertRaises(FileExistsError):F.run(root)

    def test_truncated_guard_receipt(self):
        root,c=self.setup_batch()
        job=c['jobs'][0]
        F.publish(root/'a-started.json',dict(contract_sha256=F.P.digest(root/'contract.json'),
            job=job,command=self.outcome_command(c,job)))
        (root/'a').mkdir()
        (root/'a'/'guard-receipt.json').write_text('{')
        r=F.inspect(root)
        self.assertEqual(r['rows'][0]['status'],'evidence_unresolved')
        self.assertFalse(r['rows'][0]['worker_termination_confirmed'])
        self.assertEqual(r['rows'][1]['status'],'not_started')

    def test_expired_batch_keeps_unstarted_slots(self):
        root,c=self.setup_batch(batch_seconds=.1)
        with patch.object(F.time,'monotonic',side_effect=[0,1]):r=F.run(root)
        self.assertEqual([x['status'] for x in r['rows']],['not_started','not_started'])
        self.assertFalse((root/'a-started.json').exists())

    def test_terminal_record_change(self):
        root,r=self.run_fixture(self.outcome_command)
        changed=dict(r['rows'][0],dataset_id='wrong')
        (root/'a-terminal.json').write_text(json.dumps(changed))
        self.assertEqual(F.inspect(root)['rows'][0]['status'],'evidence_unresolved')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory',required=True,type=Path)
    ROOT=parser.parse_args().directory.resolve()
    ROOT.mkdir(parents=True,exist_ok=False)
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(PreflightChecks))
    F.publish(ROOT/'verification.json',dict(tests=result.testsRun,failures=len(result.failures),
        errors=len(result.errors),new_sampler_runs=0,cv_refits=0))
    raise SystemExit(0 if result.wasSuccessful() else 1)
