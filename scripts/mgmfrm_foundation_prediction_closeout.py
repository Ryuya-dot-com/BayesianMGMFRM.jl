"""Validate the continuation's final pilot summary; never start or select a new fit.

The original root summary is an interruption snapshot. This command consumes only
the continuation summary, recomputes it from saved outputs, and records costs with
unknown durations kept missing. Planning is informational until the comparison
protocol and main implementation are frozen separately.
"""
import argparse
from collections import Counter
import math
from pathlib import Path
import platform
import sys
from tempfile import TemporaryDirectory

import mgmfrm_foundation_prediction_continue as C

P = C.P
REPO = C.REPO
CODE_SOURCES = ('scripts/mgmfrm_foundation_prediction_closeout.py',
                'test/mgmfrm_foundation_prediction_closeout.py')


class PilotPending(RuntimeError):
    pass


def check_guard(guard, root, continuation, plan, phase):
    assert guard['status'] == 'completed' and guard['exit_code'] == 0 and guard['launched'] is True
    assert guard.get('cleanup', {}).get('observed_live_survivors', []) == []
    recorded_script = Path(guard['command'][1])
    assert recorded_script.is_absolute() and '..' not in recorded_script.parts
    recorded_repo = recorded_script.parent.parent
    assert recorded_script == recorded_repo/'scripts'/Path(C.__file__).name
    recorded_root, recorded_continuation = root, continuation
    expected_script = Path(C.__file__).resolve()
    if Path(guard['output_root']) != root:
        # Only one repository-prefix relocation is allowed; C.check binds its contents.
        recorded_root = recorded_repo/root.relative_to(REPO)
        recorded_continuation = recorded_repo/continuation.relative_to(REPO)
        expected_script = recorded_script
    assert guard['output_root'] == str(recorded_root)
    assert guard['command'][1:] == [str(expected_script), 'supervise',
                                    str(recorded_root), str(recorded_continuation), '--phase', phase]
    limits = guard['limits']
    assert limits['wall_seconds'] is None and limits['batch_deadline'] is None
    assert limits['rss_bytes'] == plan['limits']['rss_bytes']
    assert limits['output_bytes'] == plan['limits']['output_bytes']
    assert limits['allow_descendant_groups'] is False and 0 < limits['poll_seconds'] <= 1
    return dict(recorded_repository=str(recorded_repo), recorded_interpreter=guard['command'][0],
                relocated=recorded_root != root)


def compare_summaries(saved, fresh):
    """Allow roundoff only in named aggregates, never identities, inputs or decisions."""
    differences = []
    summary_fields = {'mean', 'replication_mcse', 'sample_variance',
                      'within_mcmc_mcse', 'within_over_replication_mcse'}
    panel_fields = {'estimate', 'mcse', 'observed_jensen_gap',
                    'sum_absolute_half_difference', 'sum_absolute_prefix_differences'}

    def aggregate(path):
        return (len(path) == 5 and path[0] in ('conditions', 'contrasts')
                and path[2] == 'metrics' and path[3] in P.METRICS and path[4] in summary_fields) or \
               (len(path) in (5, 6) and path[0] == 'panels' and path[2] == 'metrics'
                and path[4] in panel_fields
                and (len(path) == 5 or path[4] == 'sum_absolute_prefix_differences'))

    def walk(a, b, path=()):
        message = f'Final summary differs at {path}'
        assert type(a) is type(b), message
        if isinstance(a, dict):
            assert a.keys() == b.keys(), message
            for key in a: walk(a[key], b[key], path+(key,))
        elif isinstance(a, list):
            assert len(a) == len(b), message
            for i, (x, y) in enumerate(zip(a, b)): walk(x, y, path+(i,))
        elif isinstance(a, float):
            assert math.isfinite(a) and math.isfinite(b), message
            if a != b:
                assert aggregate(path) and math.isclose(a, b, rel_tol=1e-12, abs_tol=1e-14), message
                differences.append(dict(path=list(path), saved=a, recomputed=b, absolute_difference=abs(a-b)))
        else:
            assert a == b, message

    walk(saved, fresh)
    return dict(relative_tolerance=1e-12, absolute_tolerance=1e-14,
                scope='Named panel/condition/contrast aggregates only; all other values and types exact.',
                changed_float_count=len(differences),
                maximum_absolute_difference=max((d['absolute_difference'] for d in differences), default=0),
                differences=differences)


def planning_decisions(calculation):
    return {k: [{field: value for field, value in row.items() if field != 'sample_variance'}
                for row in v] if k == 'rows' else v for k, v in calculation.items()}


def check_no_workers():
    names = {Path(p).name for p in (C.__file__, P.__file__, C.RUNNER, P.RUNNER)}
    for process in P.psutil.process_iter(['cmdline']):
        try:
            assert not any(Path(arg).name in names for arg in process.info['cmdline'] or []), \
                f'Pilot worker is still live: {process.pid}'
        except P.psutil.NoSuchProcess:
            pass
    return dict(status='no_matching_live_workers', scripts=sorted(names),
                scope='Current host process snapshot; historical completion is checked against both guard receipts.')


def check_terminal(summary, plan):
    assert summary['stage'] == 'pilot' and summary['planned_fits'] == plan['planned_fits']
    rows = summary['rows']
    assert [r['id'] for r in rows] == [a['id'] for a in plan['attempts']]
    assert len({r['id'] for r in rows}) == len(rows) == plan['planned_fits']
    counts = dict(Counter(r['status'] for r in rows))
    assert counts == summary['statuses'] and set(counts) <= {'completed', 'failed'}
    assert len(summary['panels']) == 6*plan['blocks']
    assert summary['scientific_acceptance'] is False
    assert all(r['failure']['retry'] is False for r in rows if r['status'] == 'failed')


def costs(rows):
    totals = {}
    for field in ('attempt_seconds', 'attempt_cpu_seconds'):
        values, missing = [], []
        for row in rows:
            payload = row if row['status'] == 'completed' else row['failure']
            value = payload.get(field)
            if value is None:
                missing.append(row['id'])
            else:
                assert not isinstance(value, bool) and math.isfinite(value) and value >= 0
                values.append(value)
        totals[field] = dict(known_sum=math.fsum(values), known_count=len(values), missing_ids=missing)
    fits = [r for r in rows if r['status'] == 'completed']
    return dict(attempt_totals=totals, fitting_records=len(fits),
        fitting_seconds_sum=math.fsum(r['execution']['fit_seconds'] for r in fits),
        fitting_cpu_seconds_sum=math.fsum(r['execution']['fit_cpu_seconds'] for r in fits),
        interpretation='Includes numerical failures. Summed overlapping attempt elapsed times are not whole-study elapsed time or CPU time. Missing totals are not zero; fit timings overlap known attempt totals and must not be added again. Recovery/controller costs are separate receipts.')


def closeout(root, continuation, output):
    if output.exists():
        raise FileExistsError(f'Never overwrite evidence: {output}')
    assert continuation.parent == root/'continuations'
    guard_path, summary_path = continuation/'run-guard/guard-receipt.json', continuation/'summary.json'
    if not guard_path.is_file() or not summary_path.is_file():
        raise PilotPending('Pilot still pending: final continuation guard and summary are required')
    plan, continuation_plan = C.check(root, continuation)
    evidence = [root/'plan.json', continuation/'plan.json', summary_path, guard_path,
                continuation/'run-disk-receipt.json', continuation/'recover-guard/guard-receipt.json',
                continuation/'recovery-receipt.json', *(REPO/p for p in CODE_SOURCES)]
    hashes = {str(p.relative_to(REPO)): C.sha(p) for p in evidence}
    relocation = check_guard(C.read(guard_path), root, continuation, plan, 'run')
    assert relocation == check_guard(C.read(continuation/'recover-guard/guard-receipt.json'),
                                     root, continuation, plan, 'recover')
    disk = C.read(continuation/'run-disk-receipt.json')
    assert disk['failure'] is None and disk['observations'] > 0
    assert disk['reserve_bytes'] == continuation_plan['disk_reserve_bytes']
    assert disk['minimum_observed_free_bytes'] >= disk['reserve_bytes']
    assert C.read(continuation/'recovery-receipt.json')['status'] == 'completed'
    summary = C.read(summary_path)
    assert summary['plan_sha256'] == C.sha(root/'plan.json')
    check_terminal(summary, plan)
    # Reuse frozen scoring/aggregation, including every saved draw/output hash.
    with TemporaryDirectory(prefix='mgmfrm-pilot-closeout-') as tmp:
        fresh = Path(tmp)/'summary.json'
        P.summarize(root, fresh)
        recomputed = C.read(fresh)
        verification = compare_summaries(summary, recomputed)
        calculation = P.planning(summary)
        assert planning_decisions(calculation) == planning_decisions(P.planning(recomputed)), \
            'Main planning decisions differ after recomputation'
        verification.update(recomputed_summary_sha256=C.sha(fresh),
            original_environment=plan.get('python_environment'),
            recomputed_environment=dict(python=platform.python_version(), numpy=P.np.__version__,
                                        scipy=P.scipy.__version__, psutil=P.psutil.__version__),
            planning_decisions_exact=True)
    for path, digest in hashes.items():
        assert C.sha(REPO/path) == digest, f'Evidence changed during closeout: {path}'
    worker_check = check_no_workers()
    failures = [dict(id=r['id'], classification=r['failure'].get('classification', 'recorded_attempt_failure'),
                     phase=r['failure']['phase']) for r in summary['rows'] if r['status'] == 'failed']
    result = dict(schema='mgmfrm.foundation_prediction_closeout.v2', created_utc=C.utc(),
        pilot_closed=True, comparison_protocol_frozen=False, main_launch_allowed=False,
        scientific_acceptance=False, posterior_fits=0,
        pilot_root=str(root.relative_to(REPO)), summary_path=str(summary_path.relative_to(REPO)),
        statuses=summary['statuses'], qualified_panels=sum(p['qualified'] for p in summary['panels']),
        numerical_ineligible_ids=[r['id'] for r in summary['rows']
            if r['status'] == 'completed' and not r['primary_qualified']], failures=failures,
        costs=costs(summary['rows']), baseline_planning_calculation=calculation,
        relocation=relocation, summary_verification=verification, worker_check=worker_check,
        planning_note='Baseline pilot point estimates only; comparison refits add no independent blocks. This receipt does not select a backend, freeze main N, or authorize automatic main launch.',
        evidence_sha256=hashes, code_sha256={p: hashes[p] for p in CODE_SOURCES})
    C.save(output, result)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('continuation', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    try:
        result = closeout(args.root.resolve(), args.continuation.resolve(), args.output.resolve())
    except PilotPending as error:
        print(str(error), file=sys.stderr)
        sys.exit(2)
    print(f"Pilot closed: {result['statuses']}; main launch remains disabled")
