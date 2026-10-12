"""Continuation boundary checks; saved-fit replay is also mandatory before recovery."""
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
import mgmfrm_foundation_prediction_continue as C


class Continuation(unittest.TestCase):
    def test_disk_reserve_boundary_and_observation_error(self):
        with patch.object(C.shutil, 'disk_usage', return_value=SimpleNamespace(free=C.RESERVE)):
            self.assertEqual(C.disk_check(Path('.'), C.RESERVE), C.RESERVE)
        with patch.object(C.shutil, 'disk_usage', return_value=SimpleNamespace(free=C.RESERVE-1)):
            with self.assertRaisesRegex(RuntimeError, 'Disk reserve reached'):
                C.disk_check(Path('.'), C.RESERVE)
        with patch.object(C.shutil, 'disk_usage', side_effect=OSError('unavailable')):
            with self.assertRaises(OSError): C.disk_check(Path('.'), C.RESERVE)

    def test_unrecorded_directory_cannot_be_treated_as_unstarted(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp); (root/'attempts'/'a').mkdir(parents=True)
            with patch.object(C.P, 'attempt_result', return_value=dict(id='a', status='unstarted')):
                with self.assertRaisesRegex(AssertionError, 'Unrecorded'):
                    C.inventory(root, dict(attempts=[dict(id='a')]))

    def test_saved_input_rejects_changed_samples_counts_and_target(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp); out = root/'attempts'/'a'; out.mkdir(parents=True)
            C.save(root/'plan.json', {})
            (out/'samples.jls').write_bytes(b'unchanged sample fixture')
            a = dict(id='a', seed=123, target_identity='target')
            C.save(out/'started.json', dict(attempt=a, plan_sha256=C.sha(root/'plan.json')))
            execution = dict(counts=[2000]*4, samples_sha256=C.sha(out/'samples.jls'), target_identity='target')
            C.save(out/'execution.json', execution)
            self.assertEqual(C.saved_inputs(root, dict(attempts=[a]), 'a'), a)
            for key, bad in [('counts', [2000, 2000, 2000, 1999]),
                             ('samples_sha256', 'wrong'), ('target_identity', 'wrong')]:
                changed = dict(execution); changed[key] = bad
                def read(path):
                    return changed if path.name == 'execution.json' else C.P.read(path)
                with patch.object(C, 'read', side_effect=read):
                    with self.assertRaises(AssertionError):
                        C.saved_inputs(root, dict(attempts=[a]), 'a')

    def test_mismatched_started_attempt_rejected(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp); out = root/'attempts'/'a'; out.mkdir(parents=True)
            C.save(root/'plan.json', {})
            C.save(out/'started.json', dict(attempt=dict(id='a', seed=99), plan_sha256=C.sha(root/'plan.json')))
            C.save(out/'execution.json', {})
            with self.assertRaises(AssertionError):
                C.saved_inputs(root, dict(attempts=[dict(id='a', seed=100)]), 'a')

    def test_midrun_disk_failure_propagates_to_outer_guard(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp); continuation = root/'continuation'; continuation.mkdir()
            C.save(continuation/'plan.json', {})
            p = dict(julia_binary='unused', attempts=[dict(id='a', block=1)])
            c = dict(disk_reserve_bytes=C.RESERVE, projected_remaining_bytes=1, unstarted_ids=['a'])
            process = SimpleNamespace(pid=123, poll=lambda: None)
            with patch.object(C, 'check', return_value=(p, c)), \
                 patch.object(C.psutil, 'Process', return_value=SimpleNamespace(create_time=lambda: 1)), \
                 patch.object(C.subprocess, 'Popen', return_value=process) as launch, \
                 patch.object(C, 'disk_check', side_effect=[C.RESERVE+1, RuntimeError('Disk reserve reached')]):
                with self.assertRaisesRegex(RuntimeError, 'Disk reserve reached'):
                    C.supervise(root, continuation, 'recover')
            self.assertEqual(launch.call_count, 1)
            receipt = C.read(continuation/'recover-disk-receipt.json')
            self.assertIn('Disk reserve reached', receipt['failure'])
            self.assertEqual(receipt['reserve_bytes'], C.RESERVE)

    def test_low_disk_prevents_process_launch(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp); continuation = root/'continuation'; continuation.mkdir()
            C.save(continuation/'plan.json', {})
            with patch.object(C, 'check', return_value=({}, dict(disk_reserve_bytes=C.RESERVE))), \
                 patch.object(C.psutil, 'Process', return_value=SimpleNamespace(create_time=lambda: 1)), \
                 patch.object(C.subprocess, 'Popen') as launch, \
                 patch.object(C, 'disk_check', side_effect=RuntimeError('Disk reserve reached')):
                with self.assertRaises(RuntimeError): C.supervise(root, continuation, 'recover')
            launch.assert_not_called()

    def test_evidence_save_never_overwrites(self):
        with TemporaryDirectory() as tmp:
            path = Path(tmp)/'receipt.json'; C.save(path, dict(original=True)); digest = C.sha(path)
            with self.assertRaises(FileExistsError): C.save(path, dict(original=False))
            self.assertEqual(C.sha(path), digest)

    def test_outer_guard_cleans_child_after_disk_monitor_exception(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            program = '\n'.join([
                'import pathlib, subprocess, sys',
                f'sys.path.insert(0, {str(C.REPO/"scripts")!r})',
                'import mgmfrm_foundation_prediction_continue as C',
                'child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])',
                f'pathlib.Path({str(root/"child.pid")!r}).write_text(str(child.pid))',
                f'C.disk_check(pathlib.Path({str(root)!r}), sys.maxsize)',
            ])
            result = C.P.run_guarded([sys.executable, '-c', program], root/'guard',
                wall_seconds=None, rss_bytes=1024**3, output_bytes=1024**2,
                poll_seconds=.1, output_root=root)
            self.assertIn(result['status'], ('unjoined_descendants', 'command_failed'))
            self.assertNotEqual(result['exit_code'], 0)
            self.assertIn('Disk reserve reached', (root/'guard/command.log').read_text())
            self.assertEqual(result.get('cleanup', {}).get('observed_live_survivors', []), [])
            try:
                child = C.psutil.Process(int((root/'child.pid').read_text()))
                self.assertEqual(child.status(), C.psutil.STATUS_ZOMBIE)
            except C.psutil.NoSuchProcess:
                pass


if __name__ == '__main__': unittest.main()
