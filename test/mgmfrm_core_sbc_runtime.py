"""Load a self-contained SBC snapshot, then reproduce an omitted dependency; no fits."""
import argparse,json,subprocess,sys,tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import run_mgmfrm_core_sbc as R


def check(directory):
    directory.mkdir(parents=True,exist_ok=False)
    sources=[p for p in (R.REPO/'src').rglob('*') if p.is_file()]
    sources += [R.REPO/p for p in (
        'Project.toml','Manifest.toml','scripts/mgmfrm_core_sbc_plan.py',
        'scripts/mgmfrm_core_sbc_review.py','scripts/mgmfrm_core_coverage_review.py',
        'scripts/mgmfrm_core_rank_review.py','scripts/mgmfrm_core_interval_review.jl',
        'scripts/mgmfrm_core_evaluation.jl','scripts/mgmfrm_core_summaries.jl',
        'scripts/run_mgmfrm_core_pilot.jl','scripts/mfrm_validation_preparation.jl',
        'scripts/mgmfrm_core_reference.py','scripts/mgmfrm_core_location_conditional.jl')]
    plan=R.S.proposal([f'test_quantity_{i}' for i in range(150)],
        {str(p.relative_to(R.REPO)):R.S.digest(p) for p in sources})
    setting=directory/'synthetic-setting.json';R.write(setting,plan)
    root=directory/'run';R.prepare(setting,root,['joint-001'])
    launch=R.read(root/'launch.json');cv='scripts/mgmfrm_core_cv_review.jl'
    assert cv in launch['worker_sha256']
    assert R.S.digest(root/'runtime-source'/cv)==launch['worker_sha256'][cv]
    R.write(directory/'prepared-launch.json',launch)
    # Reproduce the historical omission, including its absent manifest entry.
    # Hash validation alone still passes; loading the actual worker must fail.
    del launch['worker_sha256'][cv]
    (root/'launch.json').write_text(json.dumps(launch))
    (root/'runtime-source'/cv).unlink()
    R.context(root)
    try:R.preflight(root)
    except subprocess.CalledProcessError:pass
    else:raise AssertionError('Incomplete worker snapshot was accepted')
    assert not (root/'inputs').exists() and not (root/'joint-001').exists()
    result=dict(complete_snapshot_import_passed=True,unbound_missing_dependency_rejected=True,
        generated_datasets=0,new_sampler_runs=0,scientific_acceptance=False)
    R.write(directory/'verification.json',result)
    print(json.dumps(result))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory',type=Path)
    args=parser.parse_args()
    if args.directory is not None:check(args.directory.resolve())
    else:
        with tempfile.TemporaryDirectory() as tmp:check(Path(tmp)/'runtime')
