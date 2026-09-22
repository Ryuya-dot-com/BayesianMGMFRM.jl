"""One reviewable 12-fit R0/R1 execution rehearsal. Preparation never fits."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

import mgmfrm_core_preflight as F

P=F.P
FILES=dict(generation='generation.json',raw_truth='raw-truth.json',truth='truth.json',observed='observed.json')
SEEDS=dict(person=9270101,response=9270102,split=9270103)


def seed_inventory(paths):
    """Known local JSON seed fields only, not a global RNG-independence proof."""
    found={}
    unreadable=[]
    def visit(x,path,in_seed=False):
        if isinstance(x,dict):
            for k,v in x.items():visit(v,path,in_seed or 'seed' in k.lower())
        elif isinstance(x,list):
            for v in x:visit(v,path,in_seed)
        elif in_seed and type(x) is int:
            found.setdefault(x,set()).add(str(path))
    for path in paths:
        try:visit(json.loads(path.read_text()),path)
        except (ValueError,OSError):unreadable.append(str(path))
    return found,unreadable


def proposal(directory):
    root=Path(directory).resolve()
    jobs=[]
    for fold in [None,1,2,3,4,5]:
        for condition in ['R0','R1']:
            jobs.append(dict(job_id=f'{condition}-pair001-'+('full' if fold is None else f'fold{fold}'),
                condition=condition,dataset_id='pair-001',fold=fold,
                split_seed=None if fold is None else SEEDS['split'],fit_seed=9271001+len(jobs),
                training_rows=1250 if fold is None else 1000,heldout_rows=0 if fold is None else 250))
    return dict(schema='core.paired_rehearsal.v1',purpose='execution_feasibility_only',directory=str(root),
        protocol_frozen=False,execution_allowed=False,review=dict(scientific='open',execution='open'),
        candidate_id='independent_2d_raw_primary_01',backend='advancedhmc',ids=['pair-001'],
        seeds=SEEDS,jobs=jobs,maximum_fits=12,complete_data_fits=2,cv_refits=10,
        prior='implementation_reference',initial_raw=[0.]*128,
        controls=dict(chains=4,warmup=1000,ndraws=1000,step_size=.03,target_accept=.9,max_depth=12,
            metric='diagonal',ad_backend='ForwardDiff',init_jitter=.1,split_chains=True,
            rhat_threshold=1.01,ess_threshold=400.,progress=False),
        resources=dict(fit_wall_seconds=1800,score_wall_seconds=300,prepare_wall_seconds=300,
            collection_wall_seconds=300,batch_wall_seconds=8*3600,rss_bytes=8*2**30,
            shared_output_bytes=4*2**30,parallel_jobs=1,hard_os_containment=False),
        estimands=dict(recovery='59 primary facet quantities and 100 named abilities; 90% primary, 95% secondary intervals',
            predictive='Five-fold existing-level NLL plus category squared error, expected-score squared error and KL',
            aggregation='Equal person and dimension weights; all five folds; one matched dataset pair',
            finite_draw_review='Fixed 250/500/1000 prefixes, early/late halves, influence diagnostics and observed curvature'),
        claims=dict(feasibility_and_cost=True,replicated_coverage=False,replication_mcse=False,
            calibrated_posterior=False,prior_robustness=False,model_superiority=False,
            numerical_precision_accepted=False,scientific_acceptance=False),
        stops=dict(redraw=False,retry=False,extend_draws=False,replace_ids=False,
            pre_fit_rejection='Record original slot and continue fixed roster',
            diagnostic_or_precision_warning='Retain result and continue; no success substitution',
            operational_failure='Stop batch, retain current failure and every unstarted slot',
            unknown_worker_state='Unresolved; never relaunch or infer termination'),
        uncertainty=dict(dataset_pairs=1,independent_replications_per_condition=1,
            coverage_all_success_95_two_sided_exact_lower=.025,
            zero_failure_95_one_sided_upper=.95,
            caveat='Illustrative one-Bernoulli-event bounds only; facets, people and folds do not increase dataset repetitions'),
        generation_recipe=dict(mode='recovery',conditions=['R0','R1'],person_seed=SEEDS['person'],
            score_seed=SEEDS['response'],shared_response_uniforms=True,redraws=0),
        new_sampler_runs=0,scientific_acceptance=False)


def prepare(directory):
    c=proposal(directory)
    root=Path(c['directory'])
    history=[p for p in (P.REPO/'results/workflows').glob('20260921-core-*/**/*.json')
             if not p.is_relative_to(root)]
    known,unreadable=seed_inventory(history)
    proposed=list(SEEDS.values())+[j['fit_seed'] for j in c['jobs']]
    if len(set(proposed))!=len(proposed) or set(proposed)&set(known):
        raise ValueError('Repeated or previously used proposed seed')
    root.mkdir(parents=True,exist_ok=False)
    # Publish all IDs/seeds before seeing either generated outcome.
    F.publish(root/'proposal.json',c)
    F.publish(root/'seed-review.json',dict(proposed=proposed,collisions=[],checked_files=len(history),
        unreadable_json=unreadable,scope='Known local core-workflow JSON seed fields',independence_proven=False))
    inputs={}
    for condition in ['R0','R1']:
        panel=root/'inputs'/condition
        args=[sys.executable,str(P.REPO/'scripts/mgmfrm_core_reference.py'),'--directory',str(panel),
            '--mode','recovery','--condition',condition,'--person-seed',str(SEEDS['person']),
            '--score-seed',str(SEEDS['response'])]
        subprocess.run(args,check=True,timeout=30)
        inputs[condition]=dict(directory=str(panel),hashes={k:P.digest(panel/v) for k,v in FILES.items()})
    sources=[p for p in (P.REPO/'src').rglob('*') if p.is_file()]
    sources += [P.REPO/'scripts'/n for n in ['mgmfrm_core_run_plan.py','run_mgmfrm_core_rehearsal.jl',
        'mgmfrm_core_reference.py','mgmfrm_core_evaluation.jl','mgmfrm_core_summaries.jl',
        'mgmfrm_core_cv_review.jl','run_mgmfrm_core_pilot.jl','mfrm_validation_preparation.jl',
        'mgmfrm_core_pilot.py','mgmfrm_core_preflight.py','mgmfrm_core_controller.py','paired_rating_resource_guard.py']]
    sources += [p for p in (P.REPO/'Project.toml',P.REPO/'Manifest.toml') if p.exists()]
    c.update(inputs=inputs,proposal_sha256=P.digest(root/'proposal.json'),
        generator_sha256=P.digest(P.REPO/'scripts/mgmfrm_core_reference.py'),
        source_sha256={str(p.relative_to(P.REPO)):P.digest(p) for p in sources})
    F.publish(root/'bound-plan.json',c)
    return c


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory',type=Path)
    c=prepare(parser.parse_args().directory)
    print(json.dumps(dict(plan=str(Path(c['directory'])/'bound-plan.json'),maximum_fits=c['maximum_fits'],
        execution_allowed=c['execution_allowed'],new_sampler_runs=0),indent=2))
