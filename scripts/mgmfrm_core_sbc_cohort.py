"""Serial batches and byte-exact XZ storage for the existing 274-slot SBC worker."""
import argparse,fcntl,hashlib,lzma,os,shutil,subprocess,sys,tempfile,time
from contextlib import contextmanager
from pathlib import Path
import run_mgmfrm_core_sbc as R

FILTERS=[dict(id=lzma.FILTER_LZMA2,preset=1,dict_size=256*1024*1024)]
SOURCE=Path(__file__).resolve()


def context(root):
    plan,launch=R.context(root);cohort=R.read(root/'cohort.json')
    if (cohort['schema']!='core.sbc.cohort.v1' or cohort['plan_identity']!=launch['plan_identity'] or
            cohort['launch_sha256']!=R.S.digest(root/'launch.json') or
            cohort['controller_sha256']!=R.S.digest(SOURCE)):
        raise ValueError('Changed cohort, launch or controller')
    return plan,launch


@contextmanager
def locked(root):
    # OS lock releases on exit; no stale PID handling or job-service dependency.
    with (root/'.cohort.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        yield lock


def prepare(root,source):
    plan,launch=R.context(source)
    prior=R.collect(source) # validate existing evidence before copying it
    R.prepare(source/'execution-setting.json',root,[j['id'] for j in plan['jobs']])
    imported=[]
    for row in prior['ledger']:
        id=row['id']
        if row['status']=='not_started':continue
        if row['status']=='started_without_completion':
            raise ValueError('Finish or account for the existing driver before importing')
        shutil.copytree(source/id,root/id)
        if (source/'inputs'/id).exists():shutil.copytree(source/'inputs'/id,root/'inputs'/id)
        imported.append(dict(id=id,status=row['status'],source=str(source),
            completion_sha256=R.S.digest(source/id/'completed.json')))
    assert R.collect(root)['records']==prior['records']
    R.write(root/'cohort.json',dict(schema='core.sbc.cohort.v1',created_utc=R.now(),
        plan_identity=launch['plan_identity'],launch_sha256=R.S.digest(root/'launch.json'),
        controller_sha256=R.S.digest(SOURCE),imported=imported,
        execution='Only explicitly named unstarted IDs; serial batches; no retries or timeout',
        storage='XZ/LZMA2 preset 1, 256 MiB dictionary; exact original cache bytes retained',
        scientific_acceptance=False))
    shutil.copyfile(SOURCE,root/'runtime-source'/SOURCE.relative_to(R.REPO))
    return context(root)


def restored_digest(archive,output=None):
    digest=hashlib.sha256();size=0
    with lzma.open(archive,'rb') as stream:
        while chunk:=stream.read(1024*1024):
            digest.update(chunk);size+=len(chunk)
            if output is not None:output.write(chunk)
    return digest.hexdigest(),size


def checked_archive(directory,expected):
    receipt=R.read(directory/'archive.json');path=directory/'fit.jls.xz'
    if (receipt['original_sha256']!=expected or receipt['archive_sha256']!=R.S.digest(path) or
            receipt['archive_bytes']!=path.stat().st_size):
        raise ValueError('Changed cache archive or receipt')
    return receipt


def archive_fit(root,id):
    plan,_=context(root)
    if id not in [j['id'] for j in plan['jobs']]:raise ValueError('Unknown ID')
    directory=root/id;raw=directory/'fit.jls';archive=directory/'fit.jls.xz'
    if directory.is_symlink() or raw.is_symlink() or archive.is_symlink():
        raise ValueError('Archive only owned regular cohort files')
    complete=R.read(directory/'completed.json')
    if complete['id']!=id or complete['plan_identity']!=R.S.identity(plan):raise ValueError('Wrong completed attempt')
    expected=R.read(directory/'fit-result.json')['reference']['sha256']
    if (directory/'archive.json').exists():
        receipt=checked_archive(directory,expected)
        if restored_digest(archive)!=(expected,receipt['original_bytes']):raise ValueError('Archive restore differs')
    else:
        if R.S.digest(raw)!=expected:raise ValueError('Original cache changed')
        started=time.monotonic()
        if not archive.exists():
            with tempfile.TemporaryDirectory(dir=directory) as scratch:
                temporary=Path(scratch)/'fit.jls.xz'
                with raw.open('rb') as inp,lzma.open(temporary,'wb',filters=FILTERS) as out:
                    shutil.copyfileobj(inp,out,1024*1024)
                os.link(temporary,archive) # never replace another archive
        # Also permits recovery of an already written archive, without recompression.
        if restored_digest(archive)!=(expected,raw.stat().st_size):raise ValueError('Archive restore differs')
        receipt=dict(original_sha256=expected,original_bytes=raw.stat().st_size,
            archive_sha256=R.S.digest(archive),archive_bytes=archive.stat().st_size,
            verified_utc=R.now(),archive_and_verification_seconds=time.monotonic()-started,
            exact_original_bytes_verified=True)
        R.write(directory/'archive.json',receipt)
    if raw.exists():
        if R.S.digest(raw)!=expected:raise ValueError('Original cache changed before archival')
        raw.unlink() # recoverable exact copy; earlier source workflow is untouched
    return receipt


@contextmanager
def materialized(root,id):
    directory=root/id
    if not (directory/'archive.json').exists():
        yield root
        return
    expected=R.read(directory/'fit-result.json')['reference']['sha256']
    receipt=checked_archive(directory,expected)
    with tempfile.TemporaryDirectory(prefix='.restore-',dir=root) as scratch:
        temporary=Path(scratch);job=temporary/id;job.mkdir()
        (temporary/'inputs').symlink_to(root/'inputs',target_is_directory=True)
        for path in directory.iterdir():
            if path.is_file() and path.name not in ('fit.jls','fit.jls.xz'):
                (job/path.name).symlink_to(path.resolve())
        with (job/'fit.jls').open('xb') as output:
            restored=restored_digest(directory/'fit.jls.xz',output)
        if restored!=(expected,receipt['original_bytes']):raise ValueError('Restored cache differs')
        yield temporary


def collect(root):
    plan,launch=context(root);records=[];ledger=[];sensitivity={}
    for job in plan['jobs']:
        id=job['id'];directory=root/id;complete=directory/'completed.json'
        if not complete.exists():
            ledger.append(dict(id=id,status='started_without_completion' if directory.exists() else 'not_started'))
            continue
        try:
            execution_status=R.read(complete)['status']
            if execution_status=='completed':
                with materialized(root,id) as restored:
                    record,extra=R.convert_result(restored,plan,launch,id)
            else:record,extra=R.convert_result(root,plan,launch,id)
            records.append(record)
            ledger.append(dict(id=id,status=execution_status,qualified=record['qualified']))
            if extra is not None:sensitivity[id]=extra
        except (OSError,EOFError,ValueError,KeyError,TypeError,lzma.LZMAError) as error:
            # Corrupt evidence is an explicit unresolved slot, never a dropped ID.
            records.append(dict(id=id,plan_identity=launch['plan_identity'],qualified=False,rows=None))
            ledger.append(dict(id=id,status='evidence_unresolved',qualified=False,error=str(error)))
    report=R.S.collect(plan,records);counts=[]
    for j,name in enumerate(plan['names']):
        values=[rows[j] for rows in sensitivity.values()]
        counts.append(dict(parameter=name,**{field:dict(
            true=sum(v[field] is True for v in values),false=sum(v[field] is False for v in values),
            unresolved=len(plan['jobs'])-sum(v[field] is not None for v in values))
            for field in ('below_median','covered_90')}))
    return dict(report,ledger=ledger,records=records,
        sensitivity=dict(multiplier=4.,role='Descriptive only; no additional hypothesis tests',counts=counts))


def run_batch(root,name,ids):
    with locked(root) as lock:
        plan,launch=context(root)
        roster=[j['id'] for j in plan['jobs']]
        if (not ids or len(set(ids))!=len(ids) or any(id not in roster for id in ids) or
                ids!=sorted(ids) or any((root/id).exists() for id in ids)):
            raise ValueError('Explicit ordered, unique, unstarted planned IDs required')
        if Path(name).name!=name or name in ('.','..',''):raise ValueError('Invalid batch name')
        directory=root/'batches'/name;directory.mkdir(parents=True,exist_ok=False)
        R.write(directory/'started.json',dict(ids=ids,created_utc=R.now(),
            plan_identity=launch['plan_identity'],cohort_sha256=R.S.digest(root/'cohort.json')))
        attempted=[];failure=None
        try:
            for id in ids:
                context(root)
                with (directory/f'{id}.log').open('x') as log:
                    result=subprocess.run([sys.executable,str(Path(R.__file__).resolve()),'run',str(root),'--id',id],
                        cwd=R.REPO,stdout=log,stderr=subprocess.STDOUT,pass_fds=(lock.fileno(),))
                attempted.append(dict(id=id,returncode=result.returncode))
                if result.returncode!=0:raise RuntimeError(f'{id} driver exited {result.returncode}; preserve the attempt')
                archive_fit(root,id)
        except BaseException as error:
            failure=f'{type(error).__name__}: {error}'
            raise
        finally:
            R.write(directory/'completed.json',dict(attempted=attempted,error=failure,completed_utc=R.now(),
                unstarted=[id for id in ids if not (root/id).exists()],scientific_acceptance=False))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=('prepare','archive','collect','run'))
    p.add_argument('directory',type=Path);p.add_argument('--source',type=Path)
    p.add_argument('--id',action='append');p.add_argument('--batch');p.add_argument('--output',type=Path)
    args=p.parse_args();root=args.directory.resolve()
    if args.action=='prepare':
        if args.source is None:p.error('prepare requires --source')
        prepare(root,args.source.resolve())
    elif args.action=='run':
        if args.batch is None or not args.id:p.error('run requires --batch and --id')
        run_batch(root,args.batch,args.id)
    else:
        with locked(root):
            if args.action=='archive':
                if not args.id:p.error('archive requires --id')
                for id in args.id:archive_fit(root,id)
            else:
                if args.output is None:p.error('collect requires a fresh --output')
                R.write(args.output,collect(root))
