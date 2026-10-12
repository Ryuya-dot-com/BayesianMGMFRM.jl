"""Lightweight closeout checks: stale evidence, incomplete runs and unknown costs."""
import copy
from pathlib import Path
from tempfile import TemporaryDirectory
import sys
import unittest
from unittest.mock import patch
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
import mgmfrm_foundation_prediction_closeout as H


def fixture(root, continuation):
    plan = dict(stage='pilot', blocks=1, planned_fits=3,
        attempts=[dict(id=str(i)) for i in range(3)], limits=dict(rss_bytes=100, output_bytes=200))
    rows = [dict(id=str(i), status='completed', primary_qualified=i == 0,
        attempt_seconds=10 if i == 0 else None, attempt_cpu_seconds=8 if i == 0 else None,
        execution=dict(fit_seconds=7, fit_cpu_seconds=6)) for i in range(2)]
    rows.append(dict(id='2', status='failed', failure=dict(retry=False, phase='sampling',
        classification='external_storage_interruption', attempt_seconds=None, attempt_cpu_seconds=None)))
    summary = dict(stage='pilot', planned_fits=3, rows=rows, statuses=dict(completed=2, failed=1),
        scientific_acceptance=False, panels=[dict(qualified=False) for _ in range(6)])
    guard = dict(status='completed', exit_code=0, launched=True, output_root=str(root),
        command=[sys.executable, str(Path(H.C.__file__).resolve()), 'supervise',
                 str(root), str(continuation), '--phase', 'run'],
        limits=dict(wall_seconds=None, batch_deadline=None, rss_bytes=100, output_bytes=200,
                    allow_descendant_groups=False, poll_seconds=1))
    return plan, summary, guard


class Closeout(unittest.TestCase):
    def test_unfinished_pilot_does_not_write_or_scan_outputs(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); c = root/'continuations'/'one'; c.mkdir(parents=True)
            with patch.object(H.C, 'check') as check:
                with self.assertRaises(H.PilotPending): H.closeout(root, c, c/'closeout.json')
            check.assert_not_called()
            self.assertFalse((c/'closeout.json').exists())

    def test_old_root_summary_is_not_used(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); c = root/'continuations'/'one'; c.mkdir(parents=True)
            H.C.save(root/'summary.json', dict(statuses=dict(completed=240)))
            with self.assertRaises(H.PilotPending): H.closeout(root, c, c/'closeout.json')

    def test_guard_rejects_failure_survivors_and_wrong_phase(self):
        root = Path('/tmp/pilot').resolve(); c = root/'continuations'/'one'; plan, _, guard = fixture(root, c)
        H.check_guard(guard, root, c, plan, 'run')
        for key, value in [('status', 'unjoined_descendants'), ('exit_code', 1),
                           ('cleanup', dict(observed_live_survivors=[123]))]:
            bad = copy.deepcopy(guard); bad[key] = value
            with self.assertRaises(AssertionError): H.check_guard(bad, root, c, plan, 'run')
        with self.assertRaises(AssertionError): H.check_guard(guard, root, c, plan, 'recover')

    def test_terminal_requires_actual_rows_and_all_ids(self):
        plan, summary, _ = fixture(Path('/tmp/pilot'), Path('/tmp/pilot/continuations/one'))
        H.check_terminal(summary, plan)
        for status in ['incomplete', 'unstarted']:
            bad = copy.deepcopy(summary); bad['rows'][0]['status'] = status
            with self.assertRaises(AssertionError): H.check_terminal(bad, plan)
        bad = copy.deepcopy(summary); bad['rows'][1]['id'] = '0'
        with self.assertRaises(AssertionError): H.check_terminal(bad, plan)
        bad = copy.deepcopy(summary); bad['rows'][2]['failure']['retry'] = True
        with self.assertRaises(AssertionError): H.check_terminal(bad, plan)

    def test_relocation_preserves_one_repository_prefix_and_command(self):
        base = Path('/new/repo'); root = base/'results/pilot'; c = root/'continuations/one'
        plan, _, guard = fixture(root, c)
        old = Path('/old/repo')
        guard['output_root'] = str(old/root.relative_to(base))
        guard['command'][1] = str(old/'scripts'/Path(H.C.__file__).name)
        guard['command'][3] = guard['output_root']
        guard['command'][4] = str(old/c.relative_to(base))
        with patch.object(H, 'REPO', base):
            result = H.check_guard(guard, root, c, plan, 'run')
            self.assertTrue(result['relocated'])
            self.assertEqual(result['recorded_repository'], str(old))
            for index, value in [(1, str(old/'other'/Path(H.C.__file__).name)),
                                 (3, str(old/'different/pilot')), (4, str(c)),
                                 (1, str(old/'scripts/../scripts'/Path(H.C.__file__).name)),
                                 (5, '--other')]:
                bad = copy.deepcopy(guard); bad['command'][index] = value
                with self.assertRaises(AssertionError): H.check_guard(bad, root, c, plan, 'run')

    def test_roundoff_is_limited_to_named_aggregates(self):
        saved = dict(conditions=[dict(sd=.25, qualified=1, metrics={H.P.METRICS[0]:
            dict(mean=.9, within_over_replication_mcse=1.6349403540782865,
                 mcse_ratio_screen='exceeds_budget')})],
            rows=[dict(estimate=.9)], source_sha256=dict(file='abc'))
        fresh = copy.deepcopy(saved)
        fresh['conditions'][0]['metrics'][H.P.METRICS[0]]['within_over_replication_mcse'] += 7.2e-13
        result = H.compare_summaries(saved, fresh)
        self.assertEqual(result['changed_float_count'], 1)
        self.assertGreater(result['maximum_absolute_difference'], 0)
        changes = [(('conditions', 0, 'sd'), .25+1e-15),
                   (('conditions', 0, 'qualified'), True),
                   (('conditions', 0, 'metrics', H.P.METRICS[0], 'mean'), .9+1e-8),
                   (('conditions', 0, 'metrics', H.P.METRICS[0], 'mean'), float('nan')),
                   (('conditions', 0, 'metrics', H.P.METRICS[0], 'mcse_ratio_screen'), 'within_budget'),
                   (('rows', 0, 'estimate'), .9+1e-15), (('source_sha256', 'file'), 'def')]
        for path, value in changes:
            bad = copy.deepcopy(saved); target = bad
            for key in path[:-1]: target = target[key]
            target[path[-1]] = value
            with self.assertRaises(AssertionError): H.compare_summaries(saved, bad)

    def test_planning_requires_discrete_decisions_to_match(self):
        a = dict(ready=True, selected_blocks=32, comparisons={'0.01': 32},
                 rows=[dict(sample_variance=.001, required_planned_blocks={'0.01': 11})])
        b = copy.deepcopy(a); b['rows'][0]['sample_variance'] += 1e-16
        self.assertEqual(H.planning_decisions(a), H.planning_decisions(b))
        b['rows'][0]['required_planned_blocks']['0.01'] = 12
        self.assertNotEqual(H.planning_decisions(a), H.planning_decisions(b))

    def test_live_worker_or_unavailable_observation_blocks_closeout(self):
        with patch.object(H.P.psutil, 'process_iter', return_value=[]):
            self.assertEqual(H.check_no_workers()['status'], 'no_matching_live_workers')
        process = SimpleNamespace(pid=123, info=dict(cmdline=['julia', str(H.C.RUNNER)]))
        with patch.object(H.P.psutil, 'process_iter', return_value=[process]):
            with self.assertRaisesRegex(AssertionError, 'still live'): H.check_no_workers()
        with patch.object(H.P.psutil, 'process_iter', side_effect=H.P.psutil.AccessDenied(123)):
            with self.assertRaises(H.P.psutil.AccessDenied): H.check_no_workers()

    def test_missing_costs_and_failed_costs_are_not_dropped(self):
        _, summary, _ = fixture(Path('/tmp/pilot'), Path('/tmp/pilot/continuations/one'))
        result = H.costs(summary['rows'])
        self.assertEqual(result['attempt_totals']['attempt_seconds'],
                         dict(known_sum=10, known_count=1, missing_ids=['1', '2']))
        self.assertEqual(result['fitting_seconds_sum'], 14)
        summary['rows'][2]['failure']['attempt_seconds'] = 3
        self.assertEqual(H.costs(summary['rows'])['attempt_totals']['attempt_seconds']['known_sum'], 13)
        summary['rows'][0]['attempt_seconds'] = float('nan')
        with self.assertRaises(AssertionError): H.costs(summary['rows'])

    def test_recompute_detects_changes_and_valid_receipt_never_launches(self):
        with TemporaryDirectory() as tmp:
            base = Path(tmp).resolve(); root = base/'pilot'; c = root/'continuations'/'one'
            (c/'run-guard').mkdir(parents=True); (c/'recover-guard').mkdir()
            plan, summary, guard = fixture(root, c)
            H.C.save(root/'plan.json', plan); summary['plan_sha256'] = H.C.sha(root/'plan.json')
            H.C.save(c/'plan.json', dict(disk_reserve_bytes=5))
            H.C.save(c/'summary.json', summary); H.C.save(c/'run-guard/guard-receipt.json', guard)
            recovery = copy.deepcopy(guard); recovery['command'][-1] = 'recover'
            H.C.save(c/'recover-guard/guard-receipt.json', recovery)
            H.C.save(c/'recovery-receipt.json', dict(status='completed'))
            H.C.save(c/'run-disk-receipt.json', dict(failure=None, observations=3,
                reserve_bytes=5, minimum_observed_free_bytes=10))
            for name in H.CODE_SOURCES:
                f = base/name; f.parent.mkdir(exist_ok=True); f.write_text('fixture code')
            def recompute(_, path): H.C.save(path, summary)
            with patch.object(H, 'REPO', base), \
                 patch.object(H.C, 'check', return_value=(plan, dict(disk_reserve_bytes=5))), \
                 patch.object(H.P, 'summarize', side_effect=recompute) as compute, \
                 patch.object(H.P.psutil, 'process_iter', return_value=[]), \
                 patch.object(H.P, 'planning', return_value=dict(ready=False)):
                compute.side_effect = lambda _, path: H.C.save(path, dict(summary, uniform_reference_nll=999))
                with self.assertRaisesRegex(AssertionError, 'differs'):
                    H.closeout(root, c, c/'closeout.json')
                self.assertFalse((c/'closeout.json').exists())
                compute.side_effect = recompute
                result = H.closeout(root, c, c/'closeout.json')
                self.assertTrue(result['pilot_closed'])
                self.assertFalse(result['main_launch_allowed'])
                self.assertFalse(result['baseline_planning_calculation']['ready'])
                self.assertEqual(result['numerical_ineligible_ids'], ['1'])
                self.assertEqual(result['failures'][0]['classification'], 'external_storage_interruption')
                digest = H.C.sha(c/'closeout.json')
                with self.assertRaises(FileExistsError): H.closeout(root, c, c/'closeout.json')
                self.assertEqual(H.C.sha(c/'closeout.json'), digest)


if __name__ == '__main__': unittest.main()
