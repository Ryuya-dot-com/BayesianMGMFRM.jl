"""Finite, sampler-free input checks. One immutable roster; no retry or resume.

Read-only inspection can recover evidence after interruption. A missing guard
receipt never proves that an already started worker has stopped. This runner is
not the formal recovery/SBC/CV fit runner and has no fitting command.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import time

import mgmfrm_core_pilot as P

WORKER = P.REPO / 'scripts/run_mgmfrm_core_preflight.jl'


def publish(path, value):
    """Publish complete JSON without replacing any existing evidence."""
    path = Path(path)
    payload = json.dumps(value, allow_nan=False, indent=2) + '\n'
    fd, temporary = tempfile.mkstemp(prefix='.pending-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.link(temporary, path)  # Atomic visibility and exclusive destination.
    finally:
        os.unlink(temporary)


def prepare(directory, plan, jobs, *, seconds=300, batch_seconds=600):
    if not jobs or len({j['job_id'] for j in jobs}) != len(jobs):
        raise ValueError('Nonempty unique planned job IDs required')
    if len({(j['dataset_id'], j['fold']) for j in jobs}) != len(jobs):
        raise ValueError('Repeated dataset/fold slot')
    for j in jobs:
        if not re.fullmatch(r'[A-Za-z0-9_-]+', j['job_id']) or j['dataset_id'] not in plan['ids']:
            raise ValueError('Invalid job or dataset ID')
        if (j['fold'] is None) != (j['split_seed'] is None):
            raise ValueError('Fold and split seed must be supplied together')
    if not (0 < seconds <= 300 and 0 < batch_seconds <= 600):
        raise ValueError('Preparation limits: at most 300 seconds/job, 600 seconds/batch')
    directory = Path(directory).resolve()
    sources = [p for p in (P.REPO/'src').rglob('*') if p.is_file()]
    sources += [WORKER, Path(__file__), P.REPO/'scripts/mgmfrm_core_pilot.py',
                P.REPO/'scripts/paired_rating_resource_guard.py',
                P.REPO/'scripts/run_mgmfrm_core_pilot.jl',
                P.REPO/'scripts/mfrm_validation_preparation.jl']
    sources += [P.REPO/'scripts'/name for name in ('mgmfrm_core_evaluation.jl',
                'mgmfrm_core_summaries.jl', 'mgmfrm_core_cv_review.jl')]
    sources += [p for p in (P.REPO/'Project.toml', P.REPO/'Manifest.toml') if p.exists()]
    c = dict(mode='input_preflight_only', directory=str(directory), plan=plan, jobs=jobs,
             julia_executable=shutil.which('julia'), seconds=seconds, batch_seconds=batch_seconds,
             source_sha256={str(p.relative_to(P.REPO)): P.digest(p) for p in sources},
             new_sampler_runs=0, automatic_retry=False, execution_allowed=False,
             scientific_acceptance=False)
    if c['julia_executable'] is None:
        raise ValueError('Existing Julia executable required')
    directory.mkdir(parents=True, exist_ok=False)
    publish(directory/'contract.json', c)
    return c


def command(c, job):
    return [c['julia_executable'], '--startup-file=no', '--compiled-modules=existing',
            '--pkgimages=existing', f'--project={P.REPO}', str(WORKER),
            str(Path(c['directory'])/'contract.json'), job['job_id']]


def inspect(directory):
    """No process launch, termination, writes or automatic recovery."""
    root = Path(directory).resolve()
    c = P.read(root/'contract.json')
    contract_hash = P.digest(root/'contract.json')
    rows = []
    for j in c['jobs']:
        name = j['job_id']
        start, terminal = root/f'{name}-started.json', root/f'{name}-terminal.json'
        receipt, result = root/name/'guard-receipt.json', root/name/'result.json'
        row = dict(job_id=name, dataset_id=j['dataset_id'], fold=j['fold'],
                   status='not_started', worker_termination_confirmed=False)
        try:
            if (root/'batch-started.json').exists() and P.read(root/'batch-started.json')['contract_sha256'] != contract_hash:
                raise ValueError('Batch/roster identity mismatch')
            if not start.exists():
                if (root/name).exists() or terminal.exists():
                    raise ValueError('Artifacts without a start record')
            else:
                started = P.read(start)
                if started['contract_sha256'] != contract_hash or started['job'] != j:
                    raise ValueError('Start/roster identity mismatch')
                row['status'] = 'started_unresolved'
                if receipt.exists():
                    guard = P.read(receipt)
                    if guard['command'][-len(started['command']):] != started['command']:
                        raise ValueError('Guard command mismatch')
                    row.update(status=guard['status'], guard_sha256=P.digest(receipt),
                               guard_status=guard['status'])
                    row['worker_termination_confirmed'] = (
                        not guard['launched'] or (guard.get('exit_code') is not None and
                        guard['status'] not in ('cleanup_failed', 'cleanup_incomplete') and
                        guard.get('cleanup', {}).get('observed_live_survivors', []) == []))
                    if guard['status'] == 'completed':
                        if guard['exit_code'] != 0 or not row['worker_termination_confirmed']:
                            raise ValueError('Completion without successful cleanup/exit')
                        r = P.read(result)
                        if (r['contract_sha256'], r['job_id'], r['dataset_id'], r['fold']) != (
                                contract_hash, name, j['dataset_id'], j['fold']):
                            raise ValueError('Worker result identity mismatch')
                        if r['status'] not in ('preflight_passed', 'pre_fit_rejected') or \
                                r['new_sampler_runs'] != 0 or r['scientific_acceptance'] is not False:
                            raise ValueError('Invalid preparation outcome')
                        for artifact in ('preflight.json', 'prepared.jls'):
                            if P.digest(root/name/artifact) != r['artifact_sha256'][artifact]:
                                raise ValueError('Prepared evidence changed')
                        row.update(status=r['status'], result_sha256=P.digest(result))
                if terminal.exists():
                    if P.read(terminal) != row:
                        raise ValueError('Terminal record/evidence mismatch')
        except (OSError, ValueError, KeyError, TypeError) as error:
            row.update(status='evidence_unresolved', detail=f'{type(error).__name__}: {error}')
        rows.append(row)
    return dict(planned=len(rows), rows=rows, new_sampler_runs=0, cv_refits=0,
                scientific_acceptance=False, formal_fit_runner=False)


def run(directory):
    root = Path(directory).resolve()
    c = P.read(root/'contract.json')
    if c['mode'] != 'input_preflight_only' or c['execution_allowed'] is not False:
        raise ValueError('Only sampler-free preparation is allowed')
    if Path(c['directory']) != root:
        raise ValueError('Relocated contract')
    for name, expected in c['source_sha256'].items():
        if P.digest(P.REPO/name) != expected:
            raise ValueError(f'Changed preparation source: {name}')
    h = P.digest(root/'contract.json')
    publish(root/'batch-started.json', dict(contract_sha256=h))
    deadline = time.monotonic() + c['batch_seconds']
    for job in c['jobs']:
        if time.monotonic() >= deadline:
            break
        name = job['job_id']
        args = command(c, job)
        publish(root/f'{name}-started.json', dict(contract_sha256=h, job=job, command=args))
        P.launch(c, name, args, deadline=deadline, seconds=c['seconds'])
        row = next(r for r in inspect(root)['rows'] if r['job_id'] == name)
        publish(root/f'{name}-terminal.json', row)
        if row['status'] not in ('preflight_passed', 'pre_fit_rejected'):
            break
    result = inspect(root)
    publish(root/'batch-result.json', result)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['run', 'inspect'])
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    print(json.dumps(run(args.directory) if args.action == 'run' else inspect(args.directory), indent=2))
