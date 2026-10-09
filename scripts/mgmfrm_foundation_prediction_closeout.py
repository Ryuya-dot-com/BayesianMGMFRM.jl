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
    assert Path(guard['output_root']).resolve() == root
    assert guard['command'][1:] == [str(Path(C.__file__).resolve()), 'supervise',
                                    str(root), str(continuation), '--phase', phase]
    limits = guard['limits']
    assert limits['wall_seconds'] is None and limits['batch_deadline'] is None
    assert limits['rss_bytes'] == plan['limits']['rss_bytes']
    assert limits['output_bytes'] == plan['limits']['output_bytes']
    assert limits['allow_descendant_groups'] is False and 0 < limits['poll_seconds'] <= 1


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
    check_guard(C.read(guard_path), root, continuation, plan, 'run')
    check_guard(C.read(continuation/'recover-guard/guard-receipt.json'), root, continuation, plan, 'recover')
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
        assert C.read(fresh) == summary, 'Final summary differs from validated saved outputs'
    for path, digest in hashes.items():
        assert C.sha(REPO/path) == digest, f'Evidence changed during closeout: {path}'
    failures = [dict(id=r['id'], classification=r['failure'].get('classification', 'recorded_attempt_failure'),
                     phase=r['failure']['phase']) for r in summary['rows'] if r['status'] == 'failed']
    result = dict(schema='mgmfrm.foundation_prediction_closeout.v1', created_utc=C.utc(),
        pilot_closed=True, comparison_protocol_frozen=False, main_launch_allowed=False,
        scientific_acceptance=False, posterior_fits=0,
        pilot_root=str(root.relative_to(REPO)), summary_path=str(summary_path.relative_to(REPO)),
        statuses=summary['statuses'], qualified_panels=sum(p['qualified'] for p in summary['panels']),
        numerical_ineligible_ids=[r['id'] for r in summary['rows']
            if r['status'] == 'completed' and not r['primary_qualified']], failures=failures,
        costs=costs(summary['rows']), baseline_planning_calculation=P.planning(summary),
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
