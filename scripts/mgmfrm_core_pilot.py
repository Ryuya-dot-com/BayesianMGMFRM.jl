"""A frozen core MGMFRM pilot, or one CmdStan follow-up reusing its Julia fit."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import statistics
import sys
import time

import paired_rating_resource_guard as guard

REPO = Path(__file__).resolve().parents[1]
WORKER = REPO/'scripts/run_mgmfrm_core_pilot.jl'
BACKENDS = ('advancedhmc', 'cmdstan')
REUSED_FILES = ('contract.json', 'preflight/checked.json', 'advancedhmc/result.json',
                'advancedhmc/fit.jls', 'cmdstan/failure.json', 'batch-result.json', 'comparison.json')
DRIVER_CHANGES = ('scripts/mgmfrm_core_pilot.py', 'scripts/run_mgmfrm_core_pilot.jl')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def write(path, value):
    with Path(path).open('x') as stream:
        json.dump(value, stream, allow_nan=False, indent=2)
        stream.write('\n')


def launch(c, name, arguments, *, deadline=None, seconds=1800):
    root=Path(c['directory'])
    scratch=root/f'scratch-{name}'
    scratch.mkdir(exist_ok=False)
    environment=['/usr/bin/env',f'TMPDIR={scratch}','JULIA_NUM_THREADS=1',
                 'OPENBLAS_NUM_THREADS=1','OMP_NUM_THREADS=1',
                 'MAKEFLAGS=','GNUMAKEFLAGS=','MAKEFILES=','MFLAGS=']
    return guard.run_guarded(environment+arguments,root/name,cwd=REPO,output_root=root,
        wall_seconds=seconds,rss_bytes=8*1024**3,output_bytes=2*1024**3,
        poll_seconds=.1,grace_seconds=.5,batch_deadline=deadline,allow_descendant_groups=True)


def julia_command(c, *arguments):
    return [c['julia_executable'],'--startup-file=no','--compiled-modules=existing',
            '--pkgimages=existing',f'--project={REPO}',str(WORKER),*map(str,arguments)]


def checked_reuse(c, preparation=None):
    """Accept only the retained pre-MCMC Make failure, with the same scientific recipe."""
    reuse=c['reuse_pilot']; origin=Path(reuse['directory'])
    for name in REUSED_FILES:
        if digest(origin/name)!=reuse['artifact_sha256'][name]:
            raise ValueError(f'Reused evidence changed: {name}')
    old=read(origin/'contract.json'); old_p=read(origin/'preflight/checked.json')
    fit=read(origin/'advancedhmc/result.json')
    if 'unsupported_make_environment' not in read(origin/'cmdstan/failure.json')['error']:
        raise ValueError('This follow-up only repairs the recorded pre-MCMC Make failure')
    assert read(origin/'batch-result.json')['not_started']==[]
    assert not (origin/'cmdstan/result.json').exists() and not (origin/'cmdstan/fit.jls').exists()
    assert fit['computationally_qualified'] and fit['backend']=='advancedhmc'
    assert fit['cache_sha256']==digest(origin/'advancedhmc/fit.jls')
    assert fit['contract_sha256']==old_p['contract_sha256']==digest(origin/'contract.json')
    assert c['observed_sha256']==old['observed_sha256']==digest(old['observed_path'])
    for key in ('candidate_id','seeds','rng_policy','initialization','controls','criteria','precision','comparison'):
        assert c[key]==old[key], f'Changed reused scientific recipe: {key}'
    assert set(c['source_sha256'])==set(old['source_sha256'])
    for name, expected in old['source_sha256'].items():
        assert digest(origin/'frozen-source'/name)==expected, name
        if name not in DRIVER_CHANGES:
            assert c['source_sha256'][name]==expected, f'Changed model or environment: {name}'
    if preparation is not None:
        for key in ('julia_version','environment','controls','criteria','initial','cmdstan_chain_seeds',
                    'cmdstan_chain_initials','raw_names','focal','target_identity','prior','stan_data','initial_logdensity'):
            assert preparation[key]==old_p[key], f'Changed prepared target: {key}'
    return old,fit


def prepare(directory, observed, *, reuse_pilot=None):
    directory.mkdir(parents=True,exist_ok=False)
    julia=shutil.which('julia')
    if julia is None:
        raise RuntimeError('Julia is not installed; no automatic environment installation')
    paths=[p for p in (REPO/'src').rglob('*') if p.is_file()]
    paths += [Path(__file__),WORKER,REPO/'scripts/mgmfrm_core_reference.py',
              REPO/'scripts/paired_rating_resource_guard.py',REPO/'scripts/mfrm_validation_preparation.jl']
    paths += [p for p in (REPO/'Project.toml', REPO/'Manifest.toml') if p.is_file()]
    copied=directory/'observed.json'
    shutil.copyfile(observed,copied)
    c=dict(candidate_id='independent_2d_raw_primary_01',purpose='computation_and_cost_only',
        directory=str(directory),julia_executable=julia,python_executable=sys.executable,
        observed_path=str(copied),observed_sha256=digest(copied),
        source_observation_path=str(observed),
        source_sha256={str(p.relative_to(REPO)):digest(p) for p in paths},
        preflight_path=str(directory/'preflight/checked.json'),maximum_fits=2,
        seeds=dict(advancedhmc=9220101,cmdstan=9220102),
        rng_policy=dict(advancedhmc='One MersenneTwister host stream consumed sequentially across initialization and all chains; no invented per-chain seeds.',
                        cmdstan='Host MersenneTwister draws four distinct UInt32 chain seeds before jitter; exact seeds and initials saved in preflight.'),
        initialization=dict(base_raw=[0.0]*128,jitter_sd=.1,truth_used=False),
        build_environment='Inherited Make settings cleared in the child; use the existing serial make default, without injecting -j flags.',
        controls=dict(chains=4,warmup=1000,ndraws=1000,step_size=.03,target_accept=.9,max_depth=12,
                      metric='diagonal',ad_backend='ForwardDiff',init_jitter=.1,split_chains=True,
                      rhat_threshold=1.01,ess_threshold=400.0,progress=False),
        criteria=dict(chains=4,rhat=1.01,ess=400.0,ebfmi=.3,allow_treedepth_hits=False),
        precision=dict(mean_mcse_over_sd=.05,interval_endpoint_mcse_over_width=.05,
                       probability_mean_mcse=.01,primary_interval=.90,secondary_interval=.95),
        comparison=dict(alpha=.05,multiplicity='Bonferroni across all 313 numerical comparisons in this pair',
                        mean_tolerance='0.1 * pooled posterior SD',
                        endpoint_tolerance='0.1 * mean backend interval width for the matching 90% or 95% interval',
                        probability_mean_tolerance=.01,
                        rule='agreement if abs(delta)+z*combined_mcse <= tolerance; discrepancy if abs(delta)-z*combined_mcse > tolerance; otherwise inconclusive',
                        primary_statistics=303,secondary_statistics=10,scientific_margin=False),
        resources=dict(fit_wall_seconds=1800,batch_wall_seconds=3600,
                       observed_descendant_rss_bytes=8*1024**3,shared_output_bytes=2*1024**3,
                       compilation_and_scratch_included=True,hard_os_containment=False),
        planned_backends=list(BACKENDS),automatic_retries=False,automatic_extensions=False,
        evaluation_replications=0,scientific_acceptance=False)
    if reuse_pilot is not None:
        c.update(maximum_fits=1,planned_backends=['cmdstan'],
            reuse_pilot=dict(directory=str(reuse_pilot),
                artifact_sha256={name:digest(reuse_pilot/name) for name in REUSED_FILES},
                allowed_driver_changes=list(DRIVER_CHANGES),
                reason='Separate one-fit follow-up after pre-MCMC Make failure; retain all original attempts.'))
        c['resources']['batch_wall_seconds']=1860
        checked_reuse(c)
    write(directory/'contract.json',c)
    receipt=launch(c,'preflight',julia_command(c,'preflight',directory/'contract.json',c['preflight_path']),seconds=180)
    if receipt['status']=='completed':
        p=read(c['preflight_path'])
        assert p['controls']==c['controls'] and p['criteria']==c['criteria']
        if reuse_pilot is not None:
            checked_reuse(c,p)
        status='prepared_not_launched'
    else:
        status='preparation_failed'
    write(directory/'preparation.json',dict(status=status,guard_status=receipt['status'],new_sampler_runs=0))
    return status


def inputs(directory):
    c=read(directory/'contract.json')
    p=read(c['preflight_path'])
    if digest(directory/'contract.json')!=p['contract_sha256']:
        raise ValueError('Contract changed after preflight')
    if digest(c['observed_path'])!=c['observed_sha256']:
        raise ValueError('Observed data changed')
    for name, expected in c['source_sha256'].items():
        if digest(REPO/name)!=expected:
            raise ValueError(f'Source changed: {name}')
    if 'reuse_pilot' in c:
        checked_reuse(c,p)
    return c,p


def compare_rows(roster, results):
    planned=[(r,stat) for r in roster for stat in
             (('mean',) if r['kind']=='probability' else ('mean',.025,.05,.95,.975))]
    assert len(planned)==313
    z=statistics.NormalDist().inv_cdf(1-.05/(2*len(planned)))
    tables=[{r['parameter']:r for r in x['rows']} if x else {} for x in results]
    eligible=all(x and x['computationally_qualified'] for x in results)
    rows=[]
    for focal, stat in planned:
        pair=[t.get(focal['parameter']) for t in tables]
        row=dict(parameter=focal['parameter'],role=focal['role'],statistic=stat,
                 status='inconclusive',reason='missing_or_unqualified_fit',difference=None,
                 combined_mcse=None,tolerance=None,halfwidth=None)
        if all(pair):
            try:
                qs=[{q['probability']:q for q in r['mcse']['quantiles']} for r in pair]
                estimates=[r['estimate'] if stat=='mean' else q[stat]['estimate'] for r,q in zip(pair,qs)]
                mcse=[r['mcse']['mean_mcse'] if stat=='mean' else q[stat]['mcse'] for r,q in zip(pair,qs)]
                if stat=='mean':
                    tolerance=.01 if focal['kind']=='probability' else .1*math.sqrt(sum(r['posterior_sd']**2 for r in pair)/2)
                else:
                    lo,hi=(.025,.975) if stat in (.025,.975) else (.05,.95)
                    tolerance=.1*sum(q[hi]['estimate']-q[lo]['estimate'] for q in qs)/2
                available=all(type(x) in (int,float) and math.isfinite(x) for x in estimates+mcse+[tolerance])
                available=available and min(mcse)>=0 and tolerance>0 and all(r['mcse']['mcse_status']=='available' for r in pair)
                if eligible and not available:
                    row['reason']='unavailable_precision'
                if available:
                    delta=estimates[0]-estimates[1]; combined=math.hypot(*mcse); half=z*combined
                    row.update(difference=delta,combined_mcse=combined,tolerance=tolerance,halfwidth=half)
                    if eligible:
                        row.update(reason='numerical_precision',status='agreement' if abs(delta)+half<=tolerance
                                   else 'discrepancy' if abs(delta)-half>tolerance else 'inconclusive')
            except (KeyError,TypeError,ValueError,OverflowError):
                row['reason']='unavailable_precision'
        rows.append(row)
    primary=[r for r in rows if r['role']=='primary']
    assert len(primary)==303
    counts={status:sum(r['status']==status for r in primary) for status in ('agreement','discrepancy','inconclusive')}
    return dict(rows=rows,primary_counts=counts,z=z,planned_statistics=313,
                scientific_acceptance=False,interpretation='numerical resolution only; asymptotic MCSE comparison, not exact finite-sample coverage')


def compare(directory):
    c,p=inputs(directory)
    results=[]
    for backend in BACKENDS:
        reused=backend=='advancedhmc' and 'reuse_pilot' in c
        root=Path(c['reuse_pilot']['directory']) if reused else directory
        path=root/backend/'result.json'
        result=read(path) if path.exists() else None
        if result:
            assert result['backend']==backend and result['contract_sha256']==digest(root/'contract.json')
            assert result['cache_sha256']==digest(root/backend/'fit.jls')
            assert [r['parameter'] for r in result['rows']]==[r['parameter'] for r in p['focal']]
        results.append(result)
    write(directory/'comparison.json',compare_rows(p['focal'],results))


def run(directory):
    c,p=inputs(directory)
    planned=c['planned_backends']
    assert (planned==list(BACKENDS) and c['maximum_fits']==2) or (planned==['cmdstan'] and c['maximum_fits']==1 and 'reuse_pilot' in c)
    write(directory/'batch-started.json',dict(contract_sha256=digest(directory/'contract.json'),planned_fits=len(planned)))
    deadline=time.monotonic()+c['resources']['batch_wall_seconds']
    receipts=[]
    monitor_failed=False
    for backend in planned:
        result=launch(c,backend,julia_command(c,'fit',directory/'contract.json',backend,directory/backend),deadline=deadline)
        receipts.append(dict(backend=backend,receipt=result))
        if result['status'] in ('observation_unavailable','controller_error','cleanup_failed','cleanup_incomplete','interrupted'):
            monitor_failed=True
            break
    comparison=launch(c,'comparison',[c['python_executable'],str(Path(__file__).resolve()),'compare',
        '--directory',str(directory)],deadline=deadline,seconds=60) if len(receipts)==len(planned) and not monitor_failed else None
    write(directory/'batch-result.json',dict(attempts=receipts,comparison_guard=comparison,
        not_started=[b for b in planned if b not in [r['backend'] for r in receipts]],
        scientific_acceptance=False,evaluation_replications=0))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=('prepare','run','compare'))
    parser.add_argument('--directory',type=Path,required=True)
    parser.add_argument('--observed',type=Path)
    parser.add_argument('--reuse-pilot',type=Path,help='Prepare one CmdStan follow-up using a retained qualified Julia pilot')
    args=parser.parse_args(); directory=args.directory.resolve()
    if args.mode=='prepare':
        reuse=args.reuse_pilot.resolve() if args.reuse_pilot else None
        observed=args.observed.resolve() if args.observed else reuse/'observed.json' if reuse else None
        if observed is None: parser.error('prepare requires --observed or --reuse-pilot')
        status=prepare(directory,observed,reuse_pilot=reuse);print(status)
        raise SystemExit(0 if status=='prepared_not_launched' else 1)
    elif args.mode=='run': run(directory)
    else: compare(directory)
