"""Continue the disk-interrupted prediction pilot without changing its frozen code.

Original receipts remain immutable. Restore saved draws once, retain the other
interruption as a failure, and launch only the prospectively listed unstarted IDs.
"""
import argparse
from datetime import datetime, timezone
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

import psutil
import mgmfrm_foundation_prediction_study as P

REPO = P.REPO
RUNNER = REPO/'scripts/run_mgmfrm_foundation_prediction_continue.jl'
RECOVER = 'B005-R0-025-F3'
INTERRUPTED = 'B004-R1-050-F4'
REPLAY = 'B001-R0-025-F1'
PILOT_HASH = 'f64b476f7232bee2dd82f7a9c1d378ef173a75a7308d68f9412c556279d28428'
RESERVE = 5*1024**3
ADDED_SOURCES = [Path(__file__).resolve(), RUNNER,
                 REPO/'test/mgmfrm_foundation_prediction_continue.py']
read, save, sha = P.read, P.save, P.sha


def utc():
    return datetime.now(timezone.utc).isoformat()


def inventory(root, plan):
    rows = [P.attempt_result(root, plan, a, {}) for a in plan['attempts']]
    for row in rows:
        if row['status'] == 'unstarted':
            assert not (root/'attempts'/row['id']).exists(), 'Unrecorded attempt directory'
    return rows


def saved_inputs(root, plan, ident):
    a = next(a for a in plan['attempts'] if a['id'] == ident)
    out = root/'attempts'/ident
    started, execution = read(out/'started.json'), read(out/'execution.json')
    assert started['attempt'] == a and started['plan_sha256'] == sha(root/'plan.json')
    assert execution['counts'] == [2000]*4
    assert execution['target_identity'] == a['target_identity']
    assert execution['samples_sha256'] == sha(out/'samples.jls')
    return a


def prepare(root, destination):
    p = P.check_plan(root)
    assert sha(root/'plan.json') == PILOT_HASH and p['stage'] == 'pilot'
    assert destination.parent == root/'continuations' and not destination.exists()
    old_guard = read(root/'guard/guard-receipt.json')
    assert old_guard['status'] == 'unjoined_descendants'
    assert old_guard['cleanup']['observed_live_survivors'] == []
    for process in psutil.process_iter(['cmdline']):
        try:
            command = process.info['cmdline'] or []
            assert not (str(root) in command and any(Path(c).name in
                ('run_mgmfrm_foundation_prediction.jl', 'mgmfrm_foundation_prediction_study.py')
                for c in command)), 'Original pilot process is still running'
        except psutil.NoSuchProcess:
            pass
    rows = inventory(root, p)
    assert [r['id'] for r in rows if r['status'] == 'incomplete'] == [INTERRUPTED, RECOVER]
    assert sum(r['status'] == 'completed' for r in rows) == 115
    assert sum(r['status'] == 'unstarted' for r in rows) == 123
    assert {f.name for f in (root/'attempts'/RECOVER).iterdir()} == {'started.json', 'execution.json', 'samples.jls'}
    assert {f.name for f in (root/'attempts'/INTERRUPTED).iterdir()} == {'started.json'}
    saved_inputs(root, p, RECOVER); saved_inputs(root, p, REPLAY)
    log = (root/'worker-1.log').read_text()
    assert f'{RECOVER}/review.json' in log and 'No space left on device' in log
    assert 'signal 15: Terminated' in (root/'worker-2.log').read_text()
    files = [f for f in root.rglob('*') if f.is_file()]
    assert not any(f.is_symlink() for f in root.rglob('*'))
    maximum = max(sum(f.stat().st_size for f in d.iterdir() if f.is_file())
                  for d in (root/'attempts').iterdir())
    projected = math.ceil(1.25*maximum*124)+64*1024**2
    free = shutil.disk_usage(root).free
    assert free >= RESERVE+projected, 'Insufficient free space for remaining output plus reserve'
    destination.mkdir(parents=True)
    save(destination/'plan.json', dict(schema='mgmfrm.foundation_prediction_continuation.v1',
        created_utc=utc(), pilot_root=str(root.relative_to(REPO)), pilot_plan_sha256=PILOT_HASH,
        recovery_id=RECOVER, interrupted_id=INTERRUPTED, replay_id=REPLAY,
        unstarted_ids=[r['id'] for r in rows if r['status'] == 'unstarted'],
        baseline_statuses=dict(P.Counter(r['status'] for r in rows)),
        history_sha256={str(f.relative_to(REPO)): sha(f) for f in files},
        source_sha256={str(f.relative_to(REPO)): sha(f) for f in ADDED_SOURCES},
        disk_reserve_bytes=RESERVE, projected_remaining_bytes=projected, free_bytes=free,
        disk_policy='Admission requires reserve plus projected output; poll every second and stop below reserve. Polling cannot reserve host space or prevent sudden external exhaustion.',
        retries=0, replacement_fits=0, posterior_draws_for_recovery=0,
        timing_policy='Recovered original attempt wall/CPU totals are unknown; preserve fit timing, report restoration separately, never count the offline gap as computation.',
        scientific_acceptance=False))


def check(root, continuation, history=True):
    p = P.check_plan(root); c = read(continuation/'plan.json')
    assert c['schema'] == 'mgmfrm.foundation_prediction_continuation.v1'
    assert c['pilot_root'] == str(root.relative_to(REPO))
    assert c['pilot_plan_sha256'] == sha(root/'plan.json') == PILOT_HASH
    assert c['recovery_id'] == RECOVER and c['interrupted_id'] == INTERRUPTED and c['replay_id'] == REPLAY
    assert c['disk_reserve_bytes'] == RESERVE
    for path, digest in c['source_sha256'].items():
        assert sha(REPO/path) == digest, path
    if history:
        for path, digest in c['history_sha256'].items():
            assert sha(REPO/path) == digest, path
    return p, c


def disk_check(root, reserve):
    free = shutil.disk_usage(root).free
    if free < reserve:
        raise RuntimeError(f'Disk reserve reached: {free} available bytes < {reserve}')
    return free


def publish_recovery(root, continuation, p, c):
    staged = continuation/'restored'
    done = read(staged/'completion.json')
    assert done['recovery']['posterior_fits'] == 0
    assert done['recovery']['continuation_plan_sha256'] == sha(continuation/'plan.json')
    assert read(continuation/'replay-verification.json')['status'] == 'passed'
    saved_inputs(root, p, RECOVER)
    names = ['review.json'] + (['score.json'] if done['geometry_qualified'] else []) + ['completion.json']
    out = root/'attempts'/RECOVER
    assert all(not (out/n).exists() for n in names) and not (out/'failure.json').exists()
    for n in names[:-1]:
        assert sha(staged/n) == done['output_sha256'][n]
    assert sha(out/'execution.json') == done['output_sha256']['execution.json']
    for n in names:
        # Exclusive publication: completion is last; original files are never replaced.
        with (out/n).open('xb') as f:
            f.write((staged/n).read_bytes())
    a = next(a for a in p['attempts'] if a['id'] == RECOVER)
    assert P.attempt_result(root, p, a, {})['status'] == 'completed'
    lost = next(a for a in p['attempts'] if a['id'] == INTERRUPTED)
    assert {f.name for f in (root/'attempts'/INTERRUPTED).iterdir()} == {'started.json'}
    save(root/'attempts'/INTERRUPTED/'failure.json', dict(
        phase='sampling', classification='external_storage_interruption', recorded_utc=utc(),
        error='Sibling failed to persist review after ENOSPC; resource guard terminated this unsaved fit.',
        plan_sha256=c['pilot_plan_sha256'], binding_identity=lost['binding_identity'], retry=False,
        counts=None, observed_transition_lower_bounds=[2000, 2000, 2000, 0],
        counts_note='Log checkpoints only; exact counts and partial draws were not persisted.',
        attempt_seconds=None, attempt_cpu_seconds=None,
        continuation_plan_sha256=sha(continuation/'plan.json'),
        evidence_sha256={str((root/n).relative_to(REPO)): sha(root/n) for n in
                         ('guard/guard-receipt.json', 'worker-1.log', 'worker-2.log')},
        scientific_acceptance=False))
    check(root, continuation)
    P.summarize(root, continuation/'after-recovery-summary.json')
    save(continuation/'recovery-receipt.json', dict(status='completed', created_utc=utc(),
        recovered_id=RECOVER, external_interruption_id=INTERRUPTED, posterior_fits=0,
        summary_sha256=sha(continuation/'after-recovery-summary.json'), history_unchanged=True))


def supervise(root, continuation, action):
    p, c = check(root, continuation)
    continuation_hash = sha(continuation/'plan.json')
    save(continuation/f'{action}-controller.json', dict(pid=os.getpid(),
        create_time=psutil.Process().create_time(), continuation_plan_sha256=continuation_hash))
    free = disk_check(root, c['disk_reserve_bytes'])
    assert free >= c['disk_reserve_bytes']+c['projected_remaining_bytes']
    base = [p['julia_binary'], '--startup-file=no', '--project=.', str(RUNNER),
            str(root), str(continuation)]
    processes, logs = [], []
    peak = 0; minimum_free = free; observations = 0; failure = None
    def launch(mode, number=None):
        log = (continuation/f'{mode}{number or ""}.log').open('x'); logs.append(log)
        process = subprocess.Popen(base+[mode]+([] if number is None else [str(number)]),
            stdout=log, stderr=subprocess.STDOUT, cwd=REPO)
        processes.append(process)
        return process
    try:
        if action == 'recover':
            first = launch('restore')
        else:
            assert read(continuation/'recovery-receipt.json')['status'] == 'completed'
            assert all(not (root/'attempts'/ident).exists() for ident in c['unstarted_ids'])
            first = launch('worker', 1)
        second = None
        first_id = next(a['id'] for a in p['attempts']
                        if a['id'] in c['unstarted_ids'] and a['block'] % 2 == 1)
        while True:
            assert sha(continuation/'plan.json') == continuation_hash
            minimum_free = min(minimum_free, disk_check(root, c['disk_reserve_bytes']))
            observations += 1
            for process in processes:
                code = process.poll()
                if code not in (None, 0):
                    raise RuntimeError(f'Child {process.pid} exited {code}; no retry')
            if action == 'run' and second is None:
                try: peak = max(peak, psutil.Process(first.pid).memory_info().rss)
                except psutil.NoSuchProcess: pass
                ready = (root/'attempts'/first_id/'completion.json').exists()
                available = psutil.virtual_memory().available
                parallel = (ready and peak <= p['limits']['first_worker_max_rss_bytes'] and
                            available >= p['limits']['second_worker_min_available_bytes'])
                if first.poll() == 0 or parallel:
                    save(continuation/'parallel-decision.json', dict(
                        mode='serial' if first.poll() == 0 else 'measured_parallel',
                        first_peak_rss_bytes=peak, available_bytes=available,
                        first_new_attempt=first_id, continuation_plan_sha256=continuation_hash))
                    second = launch('worker', 2)
            if all(process.poll() == 0 for process in processes) and (action == 'recover' or second is not None):
                break
            time.sleep(1)
        check(root, continuation)
        if action == 'recover': publish_recovery(root, continuation, p, c)
    except Exception as error:
        failure = f'{type(error).__name__}: {error}'
        raise
    finally:
        # The existing outer resource guard owns and terminates live descendants.
        for log in logs: log.close()
        save(continuation/f'{action}-disk-receipt.json', dict(created_utc=utc(),
            minimum_observed_free_bytes=minimum_free, reserve_bytes=c['disk_reserve_bytes'],
            observations=observations, poll_seconds=1, failure=failure,
            limitation='Polling is not a disk reservation; abrupt external consumption can outrun it.'))


def guarded(root, continuation, action):
    p, c = check(root, continuation)
    disk_check(root, c['disk_reserve_bytes'])
    receipt = P.run_guarded([sys.executable, str(Path(__file__).resolve()), 'supervise',
        str(root), str(continuation), '--phase', action], continuation/f'{action}-guard',
        cwd=str(REPO), output_root=root, poll_seconds=1, wall_seconds=None,
        rss_bytes=p['limits']['rss_bytes'], output_bytes=p['limits']['output_bytes'])
    check(root, continuation)
    if action == 'run': P.summarize(root, continuation/'summary.json')
    print(receipt, flush=True)
    return 0 if receipt['status'] == 'completed' else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'recover', 'run', 'supervise'))
    parser.add_argument('root', type=Path); parser.add_argument('continuation', type=Path)
    parser.add_argument('--phase', choices=('recover', 'run'))
    args = parser.parse_args(); root = args.root.resolve(); continuation = args.continuation.resolve()
    for key in ('JULIA_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'JULIA_NUM_PRECOMPILE_TASKS'):
        os.environ[key] = '1'
    os.environ['JULIA_PKG_PRECOMPILE_AUTO'] = '0'
    if args.action == 'prepare': prepare(root, continuation)
    elif args.action == 'supervise':
        if args.phase is None: parser.error('--phase required')
        supervise(root, continuation, args.phase)
    else: sys.exit(guarded(root, continuation, args.action))
