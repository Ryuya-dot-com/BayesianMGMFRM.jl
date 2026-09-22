"""Serial controller for the fixed 12-slot rehearsal; no retry or resume.

Public run requires a reviewed contract. inspect never launches or writes.
collect is a separate sampler-free, bounded follow-up to a retained batch.
"""
import argparse
import math
from pathlib import Path
import shutil
import time
import json

import mgmfrm_core_preflight as F

P=F.P
WORKER=P.REPO/'scripts/run_mgmfrm_core_rehearsal.jl'
ATTEMPTS={'prepared','diagnostic_warning','mcse_unavailable','pre_fit_rejected','scoring_error'}
CONTINUE=ATTEMPTS-{'scoring_error'}


def checked_plan(path, *, execution):
    path=Path(path).resolve();c=P.read(path)
    if execution and not (c['protocol_frozen'] is True and c['execution_allowed'] is True and
            c['review']==dict(scientific='accepted',execution='accepted')):
        raise ValueError('Unreviewed rehearsal: no worker may start')
    if c['schema']!='core.paired_rehearsal.v1' or c['backend']!='advancedhmc' or Path(c['directory'])!=path.parent:
        raise ValueError('Wrong rehearsal contract')
    proposal=path.parent/'proposal.json'
    if P.digest(proposal)!=c['proposal_sha256'] or any(c[k]!=v for k,v in P.read(proposal).items()):
        raise ValueError('Changed prospective plan')
    jobs=c['jobs']
    expected=[(condition,fold) for fold in [None,1,2,3,4,5] for condition in ['R0','R1']]
    if [(j['condition'],j['fold']) for j in jobs]!=expected or len({j['job_id'] for j in jobs})!=12:
        raise ValueError('Wrong fixed job roster/order')
    if any(j['job_id']!=f"{j['condition']}-pair001-"+('full' if j['fold'] is None else f"fold{j['fold']}") for j in jobs):
        raise ValueError('Wrong job path/ID')
    if len({j['fit_seed'] for j in jobs})!=12 or any(j['dataset_id']!='pair-001' for j in jobs):
        raise ValueError('Repeated seed or wrong dataset ID')
    for name,h in c['source_sha256'].items():
        if P.digest(P.REPO/name)!=h:raise ValueError(f'Changed source: {name}')
    r=c['resources']
    for name in ['fit_wall_seconds','score_wall_seconds','prepare_wall_seconds','collection_wall_seconds','batch_wall_seconds','rss_bytes','shared_output_bytes']:
        if type(r[name]) not in (int,float) or not math.isfinite(r[name]) or r[name]<=0:
            raise ValueError('Invalid resource bound')
    if r['parallel_jobs']!=1:raise ValueError('Serial execution only')
    return c


def reference(path):
    return dict(path=str(Path(path).resolve()),sha256=P.digest(path))


def command(plan,run,phase,job=None):
    base=[shutil.which('julia'),'--startup-file=no','--compiled-modules=existing','--pkgimages=existing',
          f'--project={P.REPO}',str(WORKER)]
    if phase=='prepare':return base+['prepare',str(plan),str(run/'prepare/prepared.json')]
    if phase=='collect':return base+['collect',str(plan),str(run/'ledger.json'),str(run/'collect')]
    out=run/job['job_id']/phase
    if phase=='fit':return base+['fit',str(plan),job['job_id'],str(out)]
    return base+['score',str(plan),job['job_id'],str(run/job['job_id']/'fit/fit-result.json'),str(out)]


def launch(c,plan,run,phase,deadline,job=None):
    if reference(plan)!=P.read(run/'batch-started.json')['plan']:
        raise ValueError('Contract changed during the batch')
    rel=Path(phase) if job is None else Path(job['job_id'])/phase
    out=run/rel
    out.parent.mkdir(parents=True,exist_ok=True)
    scratch=run/('scratch-'+str(rel).replace('/','-'));scratch.mkdir(exist_ok=False)
    args=['/usr/bin/env',f'TMPDIR={scratch}','JULIA_NUM_THREADS=1','OPENBLAS_NUM_THREADS=1',
          'OMP_NUM_THREADS=1','MAKEFLAGS=','GNUMAKEFLAGS=','MAKEFILES=','MFLAGS=',*command(plan,run,phase,job)]
    F.publish(out.parent/(out.name+'-started.json'),dict(plan_sha256=P.digest(plan),phase=phase,job=job,command=args))
    limits=c['resources']
    return P.guard.run_guarded(args,out,cwd=P.REPO,output_root=c['directory'],
        wall_seconds=limits[{'collect':'collection'}.get(phase,phase)+'_wall_seconds'],
        rss_bytes=limits['rss_bytes'],output_bytes=limits['shared_output_bytes'],
        batch_deadline=deadline,poll_seconds=.1,grace_seconds=.5,allow_descendant_groups=True)


def phase_evidence(c,plan_hash,run,phase,job=None):
    out=run/phase if job is None else run/job['job_id']/phase
    start=out.parent/(out.name+'-started.json')
    row=dict(phase=phase,status='not_started',termination_recorded=False,evidence=[],attempt=None,guard=None)
    try:
        if not start.exists():
            if out.exists():raise ValueError('Orphan phase outputs')
            return row
        s=P.read(start);row['evidence'].append(reference(start))
        if (s['plan_sha256'],s['phase'],s['job'])!=(plan_hash,phase,job):
            raise ValueError('Start/slot mismatch')
        row['status']='started_unresolved'
        receipt=out/'guard-receipt.json'
        if not receipt.exists():return row
        g=P.read(receipt);row['guard']=reference(receipt);row['evidence'].append(row['guard'])
        if g['command']!=s['command'] or g['output_root']!=c['directory']:
            raise ValueError('Guard command/root mismatch')
        row.update(status=g['status'],guard_status=g['status'])
        row['termination_recorded']=not g['launched'] or (g.get('exit_code') is not None and
            g['status'] not in ('cleanup_failed','cleanup_incomplete') and
            g.get('cleanup',{}).get('observed_live_survivors',[])==[])
        if g['status']!='completed':return row
        if g['exit_code']!=0 or not row['termination_recorded']:raise ValueError('Unconfirmed completion')
        if phase=='prepare':
            p=P.read(out/'prepared.json')
            if p['contract_sha256']!=plan_hash or [r['job_id'] for r in p['rows']]!=[j['job_id'] for j in c['jobs']]:
                raise ValueError('Preparation roster mismatch')
            row['evidence'].append(reference(out/'prepared.json'));return row
        if phase=='collect':
            p=P.read(out/'collection.json')
            if p['contract_sha256']!=plan_hash or p['scientific_acceptance'] is not False:
                raise ValueError('Collection identity mismatch')
            row['evidence'].append(reference(out/'collection.json'));return row
        result=P.read(out/'worker-result.json');row['evidence'].append(reference(out/'worker-result.json'))
        expected=dict(job_id=job['job_id'],dataset_id=job['dataset_id'],condition=job['condition'],
            fold=job['fold'],fit_seed=job['fit_seed'],phase=phase,contract_sha256=plan_hash,scientific_acceptance=False)
        if any(result[k]!=v for k,v in expected.items()):raise ValueError('Worker result/slot mismatch')
        status=result['status']
        names=['fit.jls','fit-result.json'] if phase=='fit' and status=='fit_saved_not_yet_scored' else ['attempt.json','attempt.jls']
        if set(result['artifact_sha256'])!=set(names):raise ValueError('Wrong result artifacts')
        for name in names:
            ref=reference(out/name)
            if ref['sha256']!=result['artifact_sha256'][name]:raise ValueError('Changed worker artifact')
            row['evidence'].append(ref)
        if phase=='fit' and status=='fit_saved_not_yet_scored':
            fit=P.read(out/'fit-result.json')
            if fit['job_id']!=job['job_id'] or fit['contract_sha256']!=plan_hash or fit['reference']!={
                    **reference(out/'fit.jls'),'seed':job['fit_seed']}:
                raise ValueError('Saved fit reference mismatch')
        elif status in ATTEMPTS and (phase=='score' or status=='pre_fit_rejected'):
            attempt=P.read(out/'attempt.json')
            if attempt['id']!=job['dataset_id'] or attempt['status']!=status:
                raise ValueError('Attempt/result mismatch')
            if job['fold'] is not None and attempt['fold']!=job['fold']:raise ValueError('Wrong attempt fold')
            row['attempt']=reference(out/'attempt.jls')
        else:raise ValueError('Unexpected phase status')
        row['status']=status
    except (OSError,ValueError,KeyError,TypeError) as error:
        row.update(status='evidence_unresolved',attempt=None,detail=f'{type(error).__name__}: {error}')
    return row


def inspect(directory):
    run=Path(directory).resolve();m=P.read(run/'batch-started.json');c=m['contract']
    plan_hash=m['plan']['sha256']
    try:intact=P.digest(m['plan']['path'])==plan_hash
    except OSError:intact=False
    prepare=phase_evidence(c,plan_hash,run,'prepare')
    rows=[]
    for j in c['jobs']:
        fit=phase_evidence(c,plan_hash,run,'fit',j);score=phase_evidence(c,plan_hash,run,'score',j)
        chosen=score if score['status']!='not_started' else fit
        row=dict(**j,status=chosen['status'],stage=chosen['phase'],stages=[fit,score],
                 attempt=chosen['attempt'],guard=chosen['guard'],termination_recorded=chosen['termination_recorded'])
        if fit['status']=='fit_saved_not_yet_scored' and score['status']=='not_started':row['status']='fit_saved_unscored'
        if not intact or (fit['status']!='not_started' and prepare['status']!='completed') or (
                score['status']!='not_started' and fit['status']!='fit_saved_not_yet_scored'):
            row.update(status='evidence_unresolved',attempt=None,guard=None,termination_recorded=False)
        rows.append(row)
    # Once a snapshot exists, retain its artifact hashes as the comparison point.
    if (run/'ledger.json').exists():
        try:
            saved=P.read(run/'ledger.json')
            if saved['batch_started']!=reference(run/'batch-started.json'):
                raise ValueError('Batch manifest changed after snapshot')
            for row,old in zip(rows,saved['rows'],strict=True):
                refs=[e for stage in old['stages'] for e in stage['evidence']]
                if row['job_id']!=old['job_id'] or any(not Path(e['path']).is_file() or P.digest(e['path'])!=e['sha256'] for e in refs):
                    row.update(status='evidence_unresolved',attempt=None,guard=None,termination_recorded=False)
        except (OSError,ValueError,KeyError,TypeError):
            for row in rows:row.update(status='evidence_unresolved',attempt=None,guard=None,termination_recorded=False)
    return dict(schema='core.rehearsal.ledger.v1',plan=m['plan'],batch_started=reference(run/'batch-started.json'),
        execution_scope=m['execution_scope'],preparation=prepare,
        collection=phase_evidence(c,plan_hash,run,'collect'),rows=rows,planned=12,scientific_acceptance=False)


def _execute(c,plan,run,*,fixture=False):
    """Internal orchestration; tests replace command with owned Python fixtures."""
    run=Path(run).resolve();plan=Path(plan).resolve()
    if fixture:
        if c['execution_allowed'] is not False:raise ValueError('Fixtures cannot authorize real sampling')
    elif not (c['execution_allowed'] is True and c['protocol_frozen'] is True and
            c['review']==dict(scientific='accepted',execution='accepted')):
        raise ValueError('Unreviewed rehearsal')
    if not run.is_relative_to(Path(c['directory'])) or run==Path(c['directory']):
        raise ValueError('Run outputs must be inside the shared budget root')
    run.mkdir(parents=True,exist_ok=False)
    F.publish(run/'batch-started.json',dict(plan=reference(plan),contract=c,
        execution_scope='owned_python_fixture' if fixture else 'reviewed_rehearsal'))
    deadline=time.monotonic()+c['resources']['batch_wall_seconds']
    try:
        launch(c,plan,run,'prepare',deadline)
        if inspect(run)['preparation']['status']=='completed':
            for job in c['jobs']:
                if time.monotonic()>=deadline:break
                launch(c,plan,run,'fit',deadline,job)
                row=next(r for r in inspect(run)['rows'] if r['job_id']==job['job_id'])
                if row['status']=='pre_fit_rejected':continue
                if row['status']!='fit_saved_unscored' or time.monotonic()>=deadline:break
                launch(c,plan,run,'score',deadline,job)
                row=next(r for r in inspect(run)['rows'] if r['job_id']==job['job_id'])
                if row['status'] not in CONTINUE:break
    finally:
        F.publish(run/'ledger.json',inspect(run))
    ledger=inspect(run)
    # Do not launch anything else after an interruption/operational failure.
    if all(r['status'] in CONTINUE for r in ledger['rows']) and time.monotonic()<deadline:
        launch(c,plan,run,'collect',deadline)
    result=dict(ledger=reference(run/'ledger.json'),collection=phase_evidence(c,P.digest(plan),run,'collect'),
                scientific_acceptance=False)
    F.publish(run/'batch-result.json',result)
    return inspect(run)


def run(plan,directory):
    return _execute(checked_plan(plan,execution=True),plan,directory)


def collect(directory,output):
    """Explicit post-stop analysis: fresh 300s/8-GiB/2-GiB guard, zero refits."""
    ledger=inspect(directory);plan=Path(ledger['plan']['path'])
    checked_plan(plan,execution=False)
    output=Path(output).resolve();output.mkdir(parents=True,exist_ok=False)
    F.publish(output/'ledger.json',ledger)
    args=[shutil.which('julia'),'--startup-file=no','--compiled-modules=existing','--pkgimages=existing',
          f'--project={P.REPO}',str(WORKER),'collect',str(plan),str(output/'ledger.json'),str(output/'worker')]
    receipt=P.launch(dict(directory=str(output)),'worker',args,seconds=300)
    F.publish(output/'collection-receipt.json',dict(mode='explicit_sampler_free_followup',
        ledger=reference(output/'ledger.json'),guard_status=receipt['status'],new_sampler_runs=0))
    return receipt


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=['run','inspect','collect']);p.add_argument('path',type=Path)
    p.add_argument('output',nargs='?',type=Path);a=p.parse_args()
    result=inspect(a.path) if a.action=='inspect' else run(a.path,a.output) if a.action=='run' else collect(a.path,a.output)
    print(json.dumps(result,indent=2))
