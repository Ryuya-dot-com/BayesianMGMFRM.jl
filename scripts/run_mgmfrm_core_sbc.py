"""Launch declared SBC slots once, then collect every planned ID; no time cap."""
import argparse,json,math,os,resource,shutil,subprocess,sys,time
from datetime import datetime,timezone
from pathlib import Path
import numpy as np
import mgmfrm_core_sbc_plan as S
from mgmfrm_core_rank_review import rank_bands,classify_rank_bands

REPO=Path(__file__).resolve().parents[1]
WORKER=REPO/'scripts/run_mgmfrm_core_sbc.jl'
FILES=dict(generation='generation.json',raw_truth='raw-truth.json',truth='truth.json',observed='observed.json')

def write(path,value):
    with Path(path).open('x') as f:json.dump(value,f,indent=2,allow_nan=False);f.write('\n')

def read(path):return json.loads(Path(path).read_text())
def now():return datetime.now(timezone.utc).isoformat()


def context(root):
    launch=read(root/'launch.json');plan=read(root/'execution-setting.json')
    checked=S.validate(plan,repository=REPO)
    if S.digest(root/'execution-setting.json')!=launch['setting_sha256'] or checked['plan_identity']!=launch['plan_identity']:
        raise ValueError('Changed execution setting')
    for name,expected in launch['worker_sha256'].items():
        if S.digest(REPO/name)!=expected:raise ValueError(f'Worker changed: {name}')
    return plan,launch


def preflight(root):
    """Load the saved Python/Julia worker without generating data or claiming an ID."""
    plan,launch=context(root);snapshot=root/'runtime-source'
    for name,expected in (plan['source_sha256']|launch['worker_sha256']).items():
        if S.digest(snapshot/name)!=expected:raise ValueError(f'Snapshot changed: {name}')
    subprocess.run([sys.executable,'-I','-c',
        'import sys; from pathlib import Path; sys.path.insert(0,sys.argv[1]); '
        'import run_mgmfrm_core_sbc as R; R.context(Path(sys.argv[2]))',
        str(snapshot/'scripts'),str(root)],cwd=snapshot,check=True)
    julia=shutil.which('julia')
    if julia is None:raise RuntimeError('Julia executable unavailable')
    environment=dict(os.environ,JULIA_LOAD_PATH='@:@stdlib',JULIA_NUM_THREADS='1',
        OPENBLAS_NUM_THREADS='1',OMP_NUM_THREADS='1')
    subprocess.run([julia,'--startup-file=no',f'--project={snapshot}','-e',
        'include(ARGS[1]); @assert realpath(pathof(MGMFRMCoreSBCWorker.B)) == '
        'realpath(joinpath(ARGS[2],"src","BayesianMGMFRM.jl")); println("SBC_WORKER_IMPORT_OK")',
        str(snapshot/'scripts/run_mgmfrm_core_sbc.jl'),str(snapshot)],
        cwd=snapshot,env=environment,check=True)


def prepare(setting,root,ids):
    plan=read(setting);checked=S.validate(plan,repository=REPO)
    roster=[j['id'] for j in plan['jobs']]
    if not ids or len(set(ids))!=len(ids) or any(i not in roster for i in ids):
        raise ValueError('Unique predeclared IDs required')
    root.mkdir(parents=True,exist_ok=False)
    shutil.copyfile(setting,root/'execution-setting.json')
    sources={str(p.relative_to(REPO)):S.digest(p) for p in
        (Path(__file__),WORKER,REPO/'scripts/mgmfrm_core_cv_review.jl')}
    write(root/'launch.json',dict(created_utc=now(),setting_sha256=S.digest(setting),
        source_setting=str(setting.resolve()),plan_identity=checked['plan_identity'],
        selected_ids=ids,worker_sha256=sources,
        purpose='Prospectively selected slots from the fixed 274-ID roster; cost and pipeline measurement',
        no_success_substitution=True,wall_timeout_seconds=None,scientific_acceptance=False))
    snapshot=root/'runtime-source'
    for name in set(plan['source_sha256'])|set(sources):
        dest=snapshot/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(REPO/name,dest)
    preflight(root)
    return context(root)


def run_one(root,id):
    plan,launch=context(root)
    if id not in launch['selected_ids']:raise ValueError('ID was not selected before generation')
    job=next(j for j in plan['jobs'] if j['id']==id)
    directory=root/id
    if directory.exists():raise FileExistsError(directory)
    preflight(root)
    directory.mkdir(exist_ok=False) # durable claim, including pre-fit failures
    write(directory/'started.json',dict(id=id,job=job,plan_identity=launch['plan_identity'],started_utc=now()))
    started=time.monotonic();phase='generation';result={}
    try:
        generator=[sys.executable,str(REPO/'scripts/mgmfrm_core_reference.py'),
            '--directory',str(root/'inputs'/id),'--mode','prior',
            '--truth-seed',str(job['truth_seed']),'--score-seed',str(job['score_seed'])]
        with (directory/'generation.log').open('x') as log:
            generated=subprocess.run(generator,cwd=REPO,stdout=log,stderr=subprocess.STDOUT)
        generation_seconds=time.monotonic()-started
        if generated.returncode!=0:raise RuntimeError(f'Generator exited {generated.returncode}')
        hashes={k:S.digest(root/'inputs'/id/name) for k,name in FILES.items()}
        write(directory/'generation-receipt.json',dict(id=id,plan_identity=launch['plan_identity'],
            hashes=hashes,generation_seconds=generation_seconds))
        context(root)
        phase='worker';worker_start=time.monotonic()
        julia=shutil.which('julia')
        if julia is None:raise RuntimeError('Julia executable unavailable')
        environment=dict(os.environ,JULIA_NUM_THREADS='1',OPENBLAS_NUM_THREADS='1',OMP_NUM_THREADS='1')
        command=[julia,'--startup-file=no',f'--project={REPO}',str(WORKER),str(root),id]
        with (directory/'worker.log').open('x') as log:
            worker=subprocess.run(command,cwd=REPO,env=environment,stdout=log,stderr=subprocess.STDOUT)
        result.update(worker_returncode=worker.returncode,worker_process_seconds=time.monotonic()-worker_start)
        if worker.returncode!=0:raise RuntimeError(f'Julia worker exited {worker.returncode}')
        if not (directory/'worker-result.json').is_file():raise RuntimeError('Worker omitted its result')
        context(root)
        result.update(status='completed',worker_result_sha256=S.digest(directory/'worker-result.json'))
    except BaseException as error:
        result.update(status='failed',phase=phase,error=f'{type(error).__name__}: {error}')
        raise
    finally:
        peak=resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
        result.update(id=id,plan_identity=launch['plan_identity'],completed_utc=now(),
            total_seconds=time.monotonic()-started,
            child_peak_rss_bytes=peak if sys.platform=='darwin' else peak*1024,
            rss_scope='OS maximum of completed child processes in this driver; not a simultaneous process-tree sum',
            scientific_acceptance=False)
        write(directory/'completed.json',result)
    return result


def convert_result(root,plan,launch,id):
    """Verify the worker's hashes/settings before applying the existing rank helper."""
    directory=root/id;complete=read(directory/'completed.json')
    if complete['id']!=id or complete['plan_identity']!=launch['plan_identity']:
        raise ValueError('Completion identity mismatch')
    if complete['status']!='completed':
        return dict(id=id,plan_identity=launch['plan_identity'],qualified=False,rows=None),None
    path=directory/'worker-result.json'
    if S.digest(path)!=complete['worker_result_sha256']:raise ValueError('Worker result changed')
    r=read(path);receipt=read(directory/'generation-receipt.json')
    job=next(j for j in plan['jobs'] if j['id']==id)
    if (r['id']!=id or r['plan_identity']!=launch['plan_identity'] or
            r['setting_sha256']!=launch['setting_sha256'] or r['reference']['seed']!=job['fit_seed'] or
            r['input_hashes']!=receipt['hashes'] or receipt['plan_identity']!=launch['plan_identity']):
        raise ValueError('Worker result has different inputs or controls')
    for k,name in FILES.items():
        if S.digest(root/'inputs'/id/name)!=r['input_hashes'][k]:raise ValueError('Generated input changed')
    if S.digest(directory/'fit.jls')!=r['reference']['sha256']:raise ValueError('Saved fit changed')
    if S.digest(directory/'location-moments.json')!=r['location_moments_sha256']:raise ValueError('Conditional review changed')
    export=r['export_record'];precision=r['precision'];names=plan['names']
    if (r['names']!=names or export['names']!=names or export['shape']!=[16000,150] or
            export['format']!='little_endian_float64' or export['order']!='column_major' or
            precision['n_chains']!=4 or precision['draws_per_chain']!=4000 or precision['total_draws']!=16000 or
            [row['parameter'] for row in precision['rows']]!=names or len(r['truths'])!=150 or
            type(r['qualification']['qualified']) is not bool):
        raise ValueError('Complete named 16000-by-150 export and four-chain precision required')
    path=directory/'quantities.f64'
    if S.digest(path)!=export['sha256'] or path.stat().st_size!=16000*150*8:raise ValueError('Quantity bytes changed')
    draws=np.fromfile(path,dtype='<f8').reshape(16000,150,order='F')
    if not np.isfinite(draws).all():raise ValueError('Nonfinite exported draws')
    rows=[];sensitivity=[]
    for j,q in enumerate(precision['rows']):
        if len(q['quantiles'])!=3 or {v['probability'] for v in q['quantiles']}!={.05,.5,.95}:
            raise ValueError('Exactly three named quantile ESS values required')
        ess={v['probability']:v['ess'] if type(v['ess']) in (float,int) and math.isfinite(v['ess'])
             and v['ess']>=plan['quantile_ess_floor'] else None for v in q['quantiles']}
        truth=r['truths'][j]
        bands=rank_bands(draws[:,j],quantile_ess=ess,multiplier=plan['band_multiplier'])
        row=dict(parameter=names[j],truth=truth,rank_bands=bands)
        classify_rank_bands(row) # validate finite truth even when whole fit is rejected
        rows.append(row)
        extra=rank_bands(draws[:,j],quantile_ess=ess,multiplier=plan['sensitivity']['band_multiplier'])
        decision=classify_rank_bands(dict(truth=truth,rank_bands=extra)) if r['qualification']['qualified'] else dict(below_median=None,covered_90=None)
        sensitivity.append(dict(parameter=names[j],**decision))
    return dict(id=id,plan_identity=launch['plan_identity'],qualified=r['qualification']['qualified'],rows=rows),sensitivity


def collect(root):
    plan,launch=context(root);records=[];ledger=[];sensitivity={}
    for job in plan['jobs']:
        id=job['id'];directory=root/id
        if not (directory/'completed.json').exists():
            ledger.append(dict(id=id,status='started_without_completion' if directory.exists() else 'not_started'))
            continue
        record,extra=convert_result(root,plan,launch,id);records.append(record)
        status=read(directory/'completed.json')['status']
        ledger.append(dict(id=id,status=status,qualified=record['qualified']))
        if extra is not None:sensitivity[id]=extra
    report=S.collect(plan,records)
    counts=[]
    for name in plan['names']:
        values=[next(r for r in rows if r['parameter']==name) for rows in sensitivity.values()]
        counts.append(dict(parameter=name,**{field:dict(
            true=sum(v[field] is True for v in values),false=sum(v[field] is False for v in values),
            unresolved=274-sum(v[field] is not None for v in values)) for field in ('below_median','covered_90')}))
    return dict(report,ledger=ledger,records=records,
        sensitivity=dict(multiplier=4.,role='Descriptive only; no additional hypothesis tests',counts=counts))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=('prepare','preflight','run','collect'))
    parser.add_argument('directory',type=Path)
    parser.add_argument('--setting',type=Path)
    parser.add_argument('--id',action='append')
    parser.add_argument('--output',type=Path)
    args=parser.parse_args();root=args.directory.resolve()
    if args.action=='prepare':
        if args.setting is None or not args.id:parser.error('prepare requires --setting and --id')
        prepare(args.setting.resolve(),root,args.id)
    elif args.action=='preflight':
        preflight(root)
    elif args.action=='run':
        if not args.id or len(args.id)!=1:parser.error('run requires one --id')
        run_one(root,args.id[0])
    else:
        if args.output is None:parser.error('collect requires a fresh --output')
        write(args.output,collect(root))
