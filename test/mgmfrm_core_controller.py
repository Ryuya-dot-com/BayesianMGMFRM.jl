"""Controller integration using owned Python workers, never a sampler."""
import argparse
import copy
import json
import os
from pathlib import Path
import signal
import shutil
import sys
import time
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import mgmfrm_core_controller as C


def fixture_command(plan,run,phase,job=None,*,behavior='normal'):
    payload=dict(plan=str(plan),run=str(run),phase=phase,job=job,behavior=behavior)
    return [sys.executable,str(Path(__file__).resolve()),'--worker',json.dumps(payload)]


def worker(p):
    plan=Path(p['plan']);run=Path(p['run']);phase=p['phase'];j=p['job'];behavior=p['behavior']
    out=run/phase if j is None else run/j['job_id']/phase
    h=C.P.digest(plan)
    if phase=='prepare':
        C.F.publish(out/'prepared.json',dict(contract_sha256=h,
            rows=[dict(job_id=x['job_id']) for x in C.P.read(plan)['jobs']]))
        return
    if phase=='collect':
        C.F.publish(out/'collection.json',dict(contract_sha256=h,scientific_acceptance=False,scope='python_fixture'))
        return
    if behavior=='sleep':time.sleep(10)
    if behavior=='terminate':os.kill(os.getppid(),signal.SIGTERM);time.sleep(10)
    if behavior=='nonzero':raise SystemExit(7)
    if behavior=='overflow':(out/'payload').write_bytes(b'x'*2**20);return
    if behavior=='missing':return
    if behavior=='broken':(out/'worker-result.json').write_text('{');return
    if behavior.startswith('fixture:'):
        template=Path(behavior.removeprefix('fixture:'))
        for name in ['attempt.json','attempt.jls']:shutil.copyfile(template/name,out/name)
        status=C.P.read(out/'attempt.json')['status'];names=['attempt.json','attempt.jls']
    elif phase=='fit' and behavior!='rejected':
        (out/'fit.jls').write_text('controlled non-Julia cache fixture '+j['job_id'])
        C.F.publish(out/'fit-result.json',dict(job_id=j['job_id'],contract_sha256=h,
            reference={**C.reference(out/'fit.jls'),'seed':j['fit_seed']}))
        names=['fit.jls','fit-result.json'];status='fit_saved_not_yet_scored'
    else:
        status='pre_fit_rejected' if behavior=='rejected' else behavior if behavior in C.ATTEMPTS else 'prepared'
        C.F.publish(out/'attempt.json',dict(id=j['dataset_id'],fold=j['fold'],status=status))
        (out/'attempt.jls').write_text('controlled non-Julia attempt fixture')
        names=['attempt.json','attempt.jls']
    value=dict(job_id=j['job_id'],dataset_id=j['dataset_id'],condition=j['condition'],fold=j['fold'],
        fit_seed=j['fit_seed'],phase=phase,contract_sha256=h,status=status,scientific_acceptance=False,
        artifact_sha256={n:C.P.digest(out/n) for n in names})
    if behavior=='wrong_id':value['dataset_id']='wrong'
    C.F.publish(out/'worker-result.json',value)


ROOT=PLAN=None


class ControllerChecks(unittest.TestCase):
    def setup_case(self,**limits):
        root=ROOT/self._testMethodName;root.mkdir()
        c=copy.deepcopy(C.P.read(PLAN));c['directory']=str(root)
        c['resources'].update(fit_wall_seconds=3,score_wall_seconds=3,prepare_wall_seconds=3,
            collection_wall_seconds=3,batch_wall_seconds=20,rss_bytes=128*2**20,shared_output_bytes=4*2**20)
        c['resources'].update(limits)
        plan=root/'plan.json';C.F.publish(plan,c)
        return c,plan,root/'run'

    def execute(self,behavior=None,**limits):
        c,plan,run=self.setup_case(**limits)
        def cmd(p,r,s,j=None):return fixture_command(p,r,s,j,behavior='normal' if behavior is None else behavior(s,j))
        with patch.object(C,'command',side_effect=cmd):result=C._execute(c,plan,run,fixture=True)
        self.assertEqual(len(result['rows']),12)
        with self.assertRaises(FileExistsError):C._execute(c,plan,run,fixture=True)
        return c,plan,run,result

    def test_unreviewed_public_entry(self):
        dest=ROOT/self._testMethodName
        with patch.object(C,'launch') as launch:
            with self.assertRaises(ValueError):C.run(PLAN,dest)
            launch.assert_not_called()
        self.assertFalse(dest.exists())

    def test_all_slots_warnings_rejection_and_shared_limits(self):
        def behavior(s,j):
            if j is None:return 'normal'
            if s=='fit' and j['job_id']=='R0-pair001-full':return 'rejected'
            if s=='score' and j['job_id']=='R1-pair001-full':return 'mcse_unavailable'
            if s=='score' and j['job_id']=='R0-pair001-fold1':return 'diagnostic_warning'
            return 'normal'
        c,p,r,v=self.execute(behavior)
        self.assertEqual([x['status'] for x in v['rows'][:3]],['pre_fit_rejected','mcse_unavailable','diagnostic_warning'])
        self.assertTrue(all(x['status']=='prepared' for x in v['rows'][3:]))
        self.assertEqual(v['collection']['status'],'completed')
        receipts=[C.P.read(x) for x in r.rglob('guard-receipt.json')]
        self.assertEqual(len(receipts),25)
        self.assertEqual(len({x['limits']['batch_deadline'] for x in receipts}),1)
        self.assertEqual({x['output_root'] for x in receipts},{c['directory']})
        self.assertEqual({x['limits']['output_bytes'] for x in receipts},{4*2**20})
        before={str(x):C.P.digest(x) for x in r.rglob('*') if x.is_file()}
        self.assertEqual(v,C.inspect(r))
        self.assertEqual(before,{str(x):C.P.digest(x) for x in r.rglob('*') if x.is_file()})

    def test_shared_deadline_stops_remaining(self):
        _,p,r,v=self.execute(lambda s,j:'sleep' if s=='fit' else 'normal',batch_wall_seconds=.6)
        self.assertIn(v['rows'][0]['status'],['wall_limit','wall_limit_before_launch'])
        self.assertTrue(all(x['status']=='not_started' for x in v['rows'][1:]))
        self.assertEqual(v['collection']['status'],'not_started')

    def test_shared_output_stops_remaining(self):
        _,p,r,v=self.execute(lambda s,j:'overflow' if s=='fit' else 'normal',shared_output_bytes=512*2**10)
        self.assertEqual(v['rows'][0]['status'],'output_limit')
        self.assertTrue(all(x['status']=='not_started' for x in v['rows'][1:]))

    def test_nonzero_retained(self):
        _,p,r,v=self.execute(lambda s,j:'nonzero' if s=='fit' else 'normal')
        self.assertEqual(v['rows'][0]['status'],'command_failed')
        self.assertTrue(v['rows'][0]['termination_recorded'])
        self.assertEqual(v['collection']['status'],'not_started')

    def test_sigterm_retained(self):
        _,p,r,v=self.execute(lambda s,j:'terminate' if s=='fit' else 'normal')
        self.assertEqual(v['rows'][0]['status'],'interrupted')
        self.assertTrue(v['rows'][0]['termination_recorded'])
        self.assertTrue(all(x['status']=='not_started' for x in v['rows'][1:]))

    def test_score_failure_keeps_cache_and_stops(self):
        _,p,r,v=self.execute(lambda s,j:'scoring_error' if s=='score' else 'normal')
        self.assertEqual(v['rows'][0]['status'],'scoring_error')
        self.assertTrue((r/'R0-pair001-full/fit/fit.jls').exists())
        self.assertTrue(all(x['status']=='not_started' for x in v['rows'][1:]))

    def test_missing_score_not_successful_fit(self):
        _,p,r,v=self.execute(lambda s,j:'missing' if s=='score' else 'normal')
        self.assertEqual(v['rows'][0]['status'],'evidence_unresolved')
        self.assertEqual(v['rows'][0]['stages'][0]['status'],'fit_saved_not_yet_scored')

    def test_partial_json(self):
        _,p,r,v=self.execute(lambda s,j:'broken' if s=='fit' else 'normal')
        self.assertEqual(v['rows'][0]['status'],'evidence_unresolved')

    def test_wrong_id(self):
        _,p,r,v=self.execute(lambda s,j:'wrong_id' if s=='fit' else 'normal')
        self.assertEqual(v['rows'][0]['status'],'evidence_unresolved')

    def test_parent_gap_and_unconfirmed_worker(self):
        c,p,r=self.setup_case()
        original=C.P.guard.run_guarded
        def broken(command,directory,**kw):
            if Path(directory).name=='fit':raise RuntimeError('Injected controller failure before receipt')
            return original(command,directory,**kw)
        with patch.object(C,'command',side_effect=fixture_command),patch.object(C.P.guard,'run_guarded',side_effect=broken):
            with self.assertRaises(RuntimeError):C._execute(c,p,r,fixture=True)
        v=C.inspect(r)
        self.assertEqual(v['rows'][0]['status'],'started_unresolved')
        self.assertFalse(v['rows'][0]['termination_recorded'])
        self.assertTrue(all(x['status']=='not_started' for x in v['rows'][1:]))
        with self.assertRaises(FileExistsError):C._execute(c,p,r,fixture=True)

    def test_changed_artifact_and_missing_plan(self):
        _,p,r,v=self.execute(lambda s,j:'scoring_error' if s=='score' else 'normal')
        (r/'R0-pair001-full/fit/fit.jls').write_text('changed after snapshot')
        self.assertEqual(C.inspect(r)['rows'][0]['status'],'evidence_unresolved')
        p.unlink()
        v=C.inspect(r)
        self.assertEqual(len(v['rows']),12)
        self.assertTrue(all(x['status']=='evidence_unresolved' for x in v['rows']))


if __name__=='__main__':
    if sys.argv[1]=='--worker':worker(json.loads(sys.argv[2]));raise SystemExit(0)
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('plan',type=Path);parser.add_argument('directory',type=Path)
    args=parser.parse_args();PLAN=args.plan.resolve();ROOT=args.directory.resolve();ROOT.mkdir(parents=True,exist_ok=False)
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ControllerChecks))
    C.F.publish(ROOT/'verification.json',dict(tests=result.testsRun,errors=len(result.errors),failures=len(result.failures),
        new_sampler_runs=0,cv_refits=0,scope='owned_python_fixture'))
    raise SystemExit(0 if result.wasSuccessful() else 1)
