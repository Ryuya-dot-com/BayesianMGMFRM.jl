"""Runner failure accounting and export binding; synthetic bytes are not fits."""
import copy,json,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
from types import SimpleNamespace
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import run_mgmfrm_core_sbc as R
from sbc_test_support import prepare_fixture
S=R.S


class Runner(unittest.TestCase):
    def test_prepare_failure_and_no_retry(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)/'run';prepare_fixture(root,['joint-001'])
            with patch.object(R,'preflight'),patch.object(R.subprocess,'run',return_value=SimpleNamespace(returncode=12)):
                with self.assertRaises(RuntimeError):R.run_one(root,'joint-001')
            receipt=R.read(root/'joint-001/completed.json')
            self.assertEqual(receipt['status'],'failed')
            self.assertEqual(receipt['phase'],'generation')
            with self.assertRaises(FileExistsError):R.run_one(root,'joint-001')
            with self.assertRaises(ValueError):R.run_one(root,'joint-002')
            result=R.collect(root)
            self.assertEqual(len(result['ledger']),274)
            self.assertEqual(result['ledger'][0]['status'],'failed')
            self.assertEqual(result['nominal_reference']['rows'][0]['tests']['below_median_high']['unresolved'],274)
            self.assertFalse(result['scientific_acceptance'])

    def test_runtime_failure_does_not_claim_or_generate(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)/'run';prepare_fixture(root,['joint-001'])
            with patch.object(R,'preflight',side_effect=RuntimeError('Missing worker dependency')), \
                    patch.object(R.subprocess,'run') as run:
                with self.assertRaisesRegex(RuntimeError,'Missing worker dependency'):
                    R.run_one(root,'joint-001')
                run.assert_not_called()
            self.assertFalse((root/'joint-001').exists())
            self.assertFalse((root/'inputs').exists())
            self.assertEqual(R.collect(root)['ledger'][0]['status'],'not_started')

    def test_preflight_rejects_changed_snapshot_before_loading(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)/'run';prepare_fixture(root,['joint-001'])
            cv=root/'runtime-source/scripts/mgmfrm_core_cv_review.jl'
            self.assertEqual(R.S.digest(cv),R.read(root/'launch.json')['worker_sha256'][str(cv.relative_to(root/'runtime-source'))])
            cv.write_text('changed dependency')
            with patch.object(R.subprocess,'run') as run:
                with self.assertRaisesRegex(ValueError,'Snapshot changed'):
                    R.preflight(root)
                run.assert_not_called()

    def test_started_without_completion_stays_unresolved(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)/'run';prepare_fixture(root,['joint-001'])
            (root/'joint-001').mkdir()
            result=R.collect(root)
            self.assertEqual(result['ledger'][0]['status'],'started_without_completion')
            self.assertEqual(len(result['nominal_reference']['absent_ids']),274)
            launch=R.read(root/'launch.json');launch['worker_sha256']['scripts/run_mgmfrm_core_sbc.py']='0'*64
            (root/'launch.json').write_text(json.dumps(launch))
            with self.assertRaises(ValueError):R.context(root)

    def test_complete_export_binding_and_ess_floor(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);id='joint-001';directory=root/id;directory.mkdir()
            inputs=root/'inputs'/id;inputs.mkdir(parents=True)
            plan=S.proposal([f'x{i}' for i in range(150)],{'test.py':'0'*64})
            launch=dict(plan_identity=S.identity(plan),setting_sha256='a'*64)
            hashes={}
            for k,name in R.FILES.items():
                (inputs/name).write_text('{}');hashes[k]=S.digest(inputs/name)
            R.write(directory/'generation-receipt.json',dict(id=id,plan_identity=launch['plan_identity'],hashes=hashes))
            (directory/'fit.jls').write_bytes(b'explicit non-fit test fixture')
            R.write(directory/'location-moments.json',{})
            draws=np.broadcast_to(np.arange(16000.)[:,None],(16000,150)).copy(order='F')
            (directory/'quantities.f64').write_bytes(draws.tobytes(order='F'))
            precision=dict(n_chains=4,draws_per_chain=4000,total_draws=16000,
                rows=[dict(parameter=name,quantiles=[dict(probability=p,ess=399. if j==0 else 800.)
                    for p in (.05,.5,.95)]) for j,name in enumerate(plan['names'])])
            result=dict(id=id,plan_identity=launch['plan_identity'],setting_sha256=launch['setting_sha256'],
                reference=dict(seed=plan['jobs'][0]['fit_seed'],sha256=S.digest(directory/'fit.jls')),
                input_hashes=hashes,names=plan['names'],truths=[-1.]*150,qualification=dict(qualified=True),
                precision=precision,export_record=dict(names=plan['names'],shape=[16000,150],
                    format='little_endian_float64',order='column_major',sha256=S.digest(directory/'quantities.f64')),
                location_moments_sha256=S.digest(directory/'location-moments.json'))
            def replace(value):
                (directory/'worker-result.json').write_text(json.dumps(value))
                (directory/'completed.json').write_text(json.dumps(dict(id=id,plan_identity=launch['plan_identity'],
                    status='completed',worker_result_sha256=S.digest(directory/'worker-result.json'))))
            replace(result)
            record,sensitivity=R.convert_result(root,plan,launch,id)
            self.assertEqual(len(record['rows']),150)
            self.assertTrue(all(b['lower'] is None and b['upper'] is None for b in record['rows'][0]['rank_bands']))
            self.assertIsNone(sensitivity[0]['below_median'])
            self.assertTrue(sensitivity[1]['below_median'])
            for case in ('seed','shape','names','precision','truth'):
                bad=copy.deepcopy(result)
                if case=='seed':bad['reference']['seed']+=1
                elif case=='shape':bad['export_record']['shape']=[4000,150]
                elif case=='names':bad['names']=list(reversed(bad['names']))
                elif case=='precision':bad['precision']['rows'][0]['quantiles'].pop()
                else:bad['truths'][0]=True
                replace(bad)
                with self.assertRaises(ValueError):R.convert_result(root,plan,launch,id)
            replace(result);(directory/'quantities.f64').write_bytes(b'changed')
            with self.assertRaises(ValueError):R.convert_result(root,plan,launch,id)


if __name__=='__main__':unittest.main()
