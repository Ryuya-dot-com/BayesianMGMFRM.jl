"""Bounded tests: only owned Python processes, no samplers or network access."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import sys
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("guard", Path(__file__).resolve().parents[1] / "scripts/paired_rating_resource_guard.py")
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)
ROOT = None


class ResourceGuardChecks(unittest.TestCase):
    def run_job(self, code, **changes):
        controls = dict(wall_seconds=3, rss_bytes=128 * 1024**2,
                        output_bytes=1024**2, poll_seconds=0.03, grace_seconds=0.1)
        controls.update(changes)
        directory = ROOT / self._testMethodName
        result = guard.run_guarded([sys.executable, "-c", code], directory, **controls)
        self.assertEqual(result, json.loads((directory / "guard-receipt.json").read_text()))
        self.assertLess(result["seconds"], 7)
        self.assertEqual(result.get("cleanup", {}).get("observed_live_survivors", []), [])
        return result

    def test_completion(self):
        result = self.run_job("print('completed')")
        self.assertEqual(result["status"], "completed")
        self.assertEqual(result["exit_code"], 0)

    def test_nonzero_exit(self):
        result = self.run_job("raise SystemExit(7)")
        self.assertEqual(result["status"], "command_failed")
        self.assertEqual(result["exit_code"], 7)

    def test_stubborn_wall_limit(self):
        result = self.run_job("import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); print('ready',flush=True); time.sleep(20)", wall_seconds=0.6)
        self.assertEqual(result["status"], "wall_limit")
        self.assertTrue(result["cleanup"]["kill_sent"])

    def test_descendant_rss(self):
        child = "import time; x=bytearray(80*1024**2); time.sleep(20)"
        result = self.run_job(f"import subprocess,sys,time; subprocess.Popen([sys.executable,'-c',{child!r}]); time.sleep(20)", rss_bytes=70 * 1024**2)
        self.assertEqual(result["status"], "rss_limit")
        self.assertGreater(result["peak_observed_rss_bytes"], 70 * 1024**2)
        self.assertGreaterEqual(len(result["observed_pids"]), 2)

    def test_parent_exits_with_child(self):
        child = "import time; time.sleep(20)"
        result = self.run_job(f"import subprocess,sys,time; subprocess.Popen([sys.executable,'-c',{child!r}]); time.sleep(0.3)")
        self.assertEqual(result["status"], "unjoined_descendants")
        self.assertGreaterEqual(len(result["observed_pids"]), 2)

    def test_separate_descendant_group_rejected_by_default(self):
        child = "import time; time.sleep(20)"
        result = self.run_job(f"import subprocess,sys,time; subprocess.Popen([sys.executable,'-c',{child!r}],start_new_session=True); time.sleep(20)")
        self.assertEqual(result['status'], 'observation_unavailable')
        self.assertGreaterEqual(len(result['observed_pids']),2)

    def test_opted_in_separate_group_completion(self):
        child = "import time; time.sleep(0.2)"
        result = self.run_job(f"import subprocess,sys; subprocess.run([sys.executable,'-c',{child!r}],start_new_session=True,check=True)", allow_descendant_groups=True)
        self.assertEqual(result['status'],'completed')
        self.assertGreaterEqual(len(result['observed_pids']),2)

    def test_opted_in_separate_group_rss_stop(self):
        child = "import time; x=bytearray(80*1024**2); time.sleep(20)"
        result = self.run_job(f"import subprocess,sys; subprocess.run([sys.executable,'-c',{child!r}],start_new_session=True)", allow_descendant_groups=True, rss_bytes=70*1024**2)
        self.assertEqual(result['status'],'rss_limit')

    def test_opted_in_stubborn_separate_group_cleanup(self):
        child = "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(20)"
        result = self.run_job(f"import subprocess,sys; subprocess.run([sys.executable,'-c',{child!r}],start_new_session=True)", allow_descendant_groups=True, wall_seconds=0.6)
        self.assertEqual(result['status'],'wall_limit')
        self.assertTrue(result['cleanup']['kill_sent'])

    def test_opted_in_parent_exits_before_separate_child(self):
        child = "import time; time.sleep(20)"
        result = self.run_job(f"import subprocess,sys,time; subprocess.Popen([sys.executable,'-c',{child!r}],start_new_session=True); time.sleep(0.3)", allow_descendant_groups=True)
        self.assertEqual(result['status'],'unjoined_descendants')

    def test_output_limit(self):
        result = self.run_job("from pathlib import Path; import time; Path('large.bin').write_bytes(b'x'*(2*1024**2)); time.sleep(20)")
        self.assertEqual(result["status"], "output_limit")

    def test_log_limit(self):
        result = self.run_job("import sys,time; sys.stdout.write('x'*(2*1024**2)); sys.stdout.flush(); time.sleep(20)")
        self.assertEqual(result["status"], "output_limit")

    def test_final_output_after_last_poll(self):
        original = guard._tree_bytes
        calls = 0
        def size(root, receipt):
            nonlocal calls
            calls += 1
            if calls == 2:  # Model a file written after the last in-loop measurement.
                time.sleep(0.2)
                return 0
            return original(root, receipt)
        with patch.object(guard, "_tree_bytes", side_effect=size):
            result = self.run_job("from pathlib import Path; Path('large.bin').write_bytes(b'x'*(2*1024**2))")
        self.assertEqual(result["status"], "output_limit")
        self.assertGreater(result["final_output_bytes"], 1024**2)

    def test_observation_failure_after_launch(self):
        with patch.object(guard, "_snapshot", side_effect=guard.ObservationUnavailable("injected observer failure")):
            result = self.run_job("import time; time.sleep(20)")
        self.assertEqual(result["status"], "observation_unavailable")
        self.assertTrue(result["launched"])

    def test_preflight_failure_never_launches(self):
        with patch.object(guard, "_probe", side_effect=guard.ObservationUnavailable("injected preflight failure")), patch.object(guard.subprocess, "Popen") as launch:
            result = self.run_job("raise RuntimeError('must not launch')")
            launch.assert_not_called()
        self.assertEqual(result["status"], "observation_unavailable")
        self.assertFalse(result["launched"])

    def test_shared_deadline(self):
        result = self.run_job("raise RuntimeError('must not launch')", batch_deadline=time.monotonic() - 1)
        self.assertEqual(result["status"], "wall_limit_before_launch")
        self.assertFalse(result["launched"])

    def test_shared_output_budget(self):
        directory = ROOT / "shared-budget"
        directory.mkdir()
        (directory / "first-job-output").write_bytes(b'x' * 2048)
        result = guard.run_guarded([sys.executable, "-c", "raise RuntimeError('must not launch')"], directory / "second-job",
                                  wall_seconds=2, rss_bytes=128*1024**2, output_bytes=1024, output_root=directory)
        self.assertEqual(result["status"], "output_limit_before_launch")
        self.assertFalse(result["launched"])

    def test_interrupt_cleans_worker(self):
        result = self.run_job("import os,signal,time; time.sleep(0.2); os.kill(os.getppid(),signal.SIGTERM); time.sleep(20)")
        self.assertEqual(result["status"], "interrupted")
        self.assertIn("cleanup", result)

    def test_symlink_is_unmeasurable(self):
        result = self.run_job("import os,time; os.symlink('command.log','link'); time.sleep(20)")
        self.assertEqual(result["status"], "observation_unavailable")

    def test_walk_permission_failure(self):
        def denied(*args, **kwargs):
            kwargs["onerror"](PermissionError("injected unreadable directory"))
        with patch.object(guard.os, "walk", side_effect=denied):
            with self.assertRaises(guard.ObservationUnavailable):
                guard._tree_bytes(ROOT, ROOT / "receipt")

    def test_group_permission_is_not_absence(self):
        with patch.object(guard.os, "killpg", side_effect=PermissionError("injected group probe denial")), patch.object(guard.psutil, "pids", return_value=[os.getpid()]), patch.object(guard.os, "getpgid", return_value=12345):
            self.assertTrue(guard._group_exists(12345))

    @unittest.skipUnless(sys.platform == "darwin", "Darwin zombie-group regression")
    def test_unreaped_zombie_group(self):
        worker = guard.subprocess.Popen([sys.executable, "-c", "pass"], start_new_session=True)
        try:
            owned = guard.psutil.Process(worker.pid)
            end = time.monotonic() + 2
            while owned.status() != guard.psutil.STATUS_ZOMBIE and time.monotonic() < end:
                time.sleep(0.01)
            self.assertEqual(owned.status(), guard.psutil.STATUS_ZOMBIE)
            self.assertFalse(guard._group_exists(worker.pid))
        finally:
            worker.wait(timeout=3)

    def test_no_overwrite_and_invalid_controls(self):
        directory = ROOT / self._testMethodName
        directory.mkdir()
        controls = dict(wall_seconds=1, rss_bytes=128*1024**2, output_bytes=1024)
        with self.assertRaises(FileExistsError):
            guard.run_guarded([sys.executable, "-c", "pass"], directory, **controls)
        for key, value in (("wall_seconds", float("nan")), ("rss_bytes", True), ("output_bytes", -1), ("poll_seconds", 2)):
            with self.assertRaises(ValueError):
                guard.run_guarded([sys.executable, "-c", "pass"], directory / key, **(controls | {key: value}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", required=True)
    parser.add_argument("--mode", choices=("preflight", "full"), required=True)
    args = parser.parse_args()
    ROOT = Path(args.directory).resolve()
    ROOT.mkdir(parents=True, exist_ok=False)
    if args.mode == "preflight":
        marker = ROOT / "unexpected-launch"
        result = guard.run_guarded([sys.executable, "-c", f"from pathlib import Path; Path({str(marker)!r}).touch()"],
                                  ROOT / "default-sandbox", wall_seconds=2, rss_bytes=128*1024**2, output_bytes=1024**2)
        assert result["status"] == "observation_unavailable" and not result["launched"] and not marker.exists(), result
        print(json.dumps(dict(expected_fail_closed=True, receipt=result)))
    else:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(ResourceGuardChecks)
        start = time.monotonic()
        outcome = unittest.TextTestRunner(verbosity=2).run(suite)
        result = dict(tests=outcome.testsRun, failures=len(outcome.failures), errors=len(outcome.errors), seconds=time.monotonic()-start,
                      new_sampler_runs=0, worker_scope="Only Python children created by this suite; memory payload <=80 MiB; each job <=3 s + bounded cleanup")
        (ROOT / "verification.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result))
        raise SystemExit(0 if outcome.wasSuccessful() else 1)
