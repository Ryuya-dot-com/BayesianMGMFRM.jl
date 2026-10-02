"""Archive losslessness and batch failure accounting; dummy bytes are not fitted evidence."""
import lzma,sys,tempfile,unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import mgmfrm_core_sbc_cohort as C
from sbc_test_support import prepare_fixture
R=C.R


def setup(root):
    plan,launch=prepare_fixture(root,[f'joint-{i:03}' for i in range(1,275)])
    (root/'inputs').mkdir()
    R.write(root/'cohort.json',dict(schema='core.sbc.cohort.v1',plan_identity=launch['plan_identity'],
        launch_sha256=R.S.digest(root/'launch.json'),controller_sha256=R.S.digest(C.SOURCE)))
    return plan


def fixture(root,id,status='completed'):
    directory=root/id;directory.mkdir();raw=directory/'fit.jls'
    raw.write_bytes(b'Explicit non-fit test bytes\x00\xff'*4096)
    R.write(directory/'fit-result.json',dict(reference=dict(sha256=R.S.digest(raw))))
    R.write(directory/'completed.json',dict(id=id,status=status,plan_identity=R.S.identity(R.read(root/'execution-setting.json'))))
    return raw


class Cohort(unittest.TestCase):
    def test_exact_restore_and_corrupt_evidence_stays_unresolved(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(C,'FILTERS',[dict(id=lzma.FILTER_LZMA2,preset=1,dict_size=1024*1024)]):
            root=Path(tmp)/'cohort';setup(root);raw=fixture(root,'joint-001');expected=raw.read_bytes()
            receipt=C.archive_fit(root,'joint-001')
            self.assertFalse(raw.exists());self.assertTrue(receipt['exact_original_bytes_verified'])
            self.assertEqual(C.archive_fit(root,'joint-001'),receipt)
            with C.materialized(root,'joint-001') as restored:
                self.assertEqual((restored/'joint-001/fit.jls').read_bytes(),expected)
                location=restored
            self.assertFalse(location.exists())
            archive=root/'joint-001/fit.jls.xz';archive.write_bytes(archive.read_bytes()[:-7])
            result=C.collect(root)
            self.assertEqual(result['ledger'][0]['status'],'evidence_unresolved')
            self.assertEqual(result['nominal_reference']['planned'],274)
            self.assertEqual(result['nominal_reference']['rows'][0]['tests']['covered_90_low']['unresolved'],274)
            self.assertEqual(list(root.glob('.restore-*')),[])

    def test_failed_archive_preserves_original_and_missing_completion(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)/'cohort';setup(root);raw=fixture(root,'joint-001');expected=raw.read_bytes()
            archive=raw.with_suffix('.jls.xz');archive.write_bytes(b'truncated archive')
            with self.assertRaises(lzma.LZMAError):C.archive_fit(root,'joint-001')
            self.assertEqual(raw.read_bytes(),expected)
            self.assertFalse((raw.parent/'archive.json').exists())
            (root/'joint-002').mkdir()
            self.assertEqual(C.collect(root)['ledger'][1]['status'],'started_without_completion')

    def test_serial_failure_no_retry_and_no_replacement(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)/'cohort';setup(root)
            def fail(command,**kwargs):
                fixture(root,command[-1],status='failed')
                self.assertNotIn('timeout',kwargs)
                return SimpleNamespace(returncode=7)
            with patch.object(C.subprocess,'run',side_effect=fail) as run:
                with self.assertRaises(RuntimeError):C.run_batch(root,'first',['joint-001','joint-002'])
                self.assertEqual(run.call_count,1)
            self.assertEqual(R.read(root/'batches/first/completed.json')['unstarted'],['joint-002'])
            with self.assertRaises(ValueError):C.run_batch(root,'retry',['joint-001'])
            with C.locked(root):
                with self.assertRaises(BlockingIOError):C.run_batch(root,'parallel',['joint-002'])
            result=C.collect(root)
            self.assertEqual(result['ledger'][0]['status'],'failed')
            self.assertEqual(result['ledger'][1]['status'],'not_started')
            self.assertFalse((root/'batches/retry').exists())

    def test_two_explicit_slots_archive_serially_and_controller_binding(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(C,'FILTERS',[dict(id=lzma.FILTER_LZMA2,preset=1,dict_size=1024*1024)]):
            root=Path(tmp)/'cohort';setup(root);seen=[]
            def complete(command,**kwargs):
                if seen:self.assertFalse((root/seen[-1]/'fit.jls').exists())
                seen.append(command[-1]);fixture(root,command[-1])
                return SimpleNamespace(returncode=0)
            with patch.object(C.subprocess,'run',side_effect=complete):C.run_batch(root,'first',['joint-001','joint-002'])
            self.assertEqual(seen,['joint-001','joint-002'])
            self.assertEqual(R.read(root/'batches/first/completed.json')['unstarted'],[])
            metadata=R.read(root/'cohort.json');metadata['controller_sha256']='0'*64
            (root/'cohort.json').write_text(__import__('json').dumps(metadata))
            with self.assertRaises(ValueError):C.context(root)


if __name__=='__main__':unittest.main()
