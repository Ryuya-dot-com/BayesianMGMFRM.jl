"""Frozen normalized-C prediction studies; local persistent workers and panel summaries."""
import argparse
from collections import Counter
import json
import math
import os
from pathlib import Path
import platform
import shutil
import statistics as st
import subprocess
import sys
import time

import numpy as np
import psutil
import scipy
from scipy.special import logsumexp

import mgmfrm_foundation_assessment as A
from mgmfrm_foundation_fixed_facet_input import assessment_pair
from paired_rating_resource_guard import run_guarded

REPO = A.REPO
METRICS = ('negative_log_predictive_probability', 'squared_category_probability_error',
           'squared_expected_score_error', 'log_score_regret')
CONDITIONS = [(c, s) for c in ('R0', 'R1') for s in (.25, .5, 1.)]
read, save, sha = A.read, A.save, A.sha
RUNNER = REPO/'scripts/run_mgmfrm_foundation_prediction.jl'


def prepare_study(root, julia, selection_path=None):
    n, stage, seed_base, selection = 8, 'pilot', 20261006090000, None
    output_budget, storage_projection = 8*1024**3, None
    if selection_path is not None:
        selection = read(selection_path)
        assert selection['ready'] is True and selection['selected_target'] == .01
        pilot = REPO/selection['pilot_root']
        assert sha(pilot/'summary.json') == selection['pilot_summary_sha256']
        assert sha(pilot/'plan.json') == selection['pilot_plan_sha256']
        expected = planning(read(pilot/'summary.json'))
        assert expected == selection['calculation'] and expected['ready'] is True
        n = expected['selected_blocks']; stage = 'main'; seed_base = 20261008090000
        maximum = max(sum(p.stat().st_size for p in d.rglob('*') if p.is_file()) for d in (pilot/'attempts').iterdir() if d.is_dir())
        output_budget = max(output_budget, math.ceil(1.25*maximum*30*n)+64*1024**2)
        assert shutil.disk_usage(root.parent).free >= 1.5*output_budget, 'Insufficient local free space for planned outputs'
        storage_projection = dict(pilot_maximum_attempt_bytes=maximum, planned_attempts=30*n,
            safety_factor=1.25, output_budget_bytes=output_budget)
    root.mkdir(); (root/'inputs').mkdir()
    for block in range(1, n+1):
        for payload in assessment_pair(root.name, block, seed_base+10*block+1, seed_base+10*block+2):
            save(root/'inputs'/f"B{block:03}-{payload['condition']}.json", payload)
    save(root/'design.json', dict(schema='mgmfrm.foundation_prediction_study.v1', study_id=root.name,
        stage=stage, blocks=n, planned_fits=30*n, execution_allowed=True, scientific_acceptance=False,
        generation_scope='prospective_fixed_facet_assessment', evaluation_scope='heldout_known_levels',
        person_seed_base=seed_base, score_seed_base=seed_base,
        independent_unit='paired_R0_R1_block', training_ratings=1000, heldout_ratings_per_fold=250,
        prior_widths=[.25, .5, 1.], folds=5, split_seed_base=seed_base+max(10000,20*n),
        fit_seed_base=seed_base+max(10000,20*n)+max(10000,2*n),
        primary_metric=METRICS[0], metrics=METRICS, retries=0, extensions=0, replacements=0,
        primary_numerical_policy=dict(panel_mcse_max=.005/3, observed_jensen_gap_max=.005,
            sum_absolute_half_difference_max=.01, sum_absolute_prefix_difference_max=.01,
            interpretation='Reporting-resolution screens, not error/bias bounds or scientific effect margins.'),
        replication_se_comparisons=[.005, .01, .02], main_planning_se_target=.01,
        main_planning_minimum_blocks=32, main_N_selected=stage == 'main', summary_mcse_ratio_max=.1,
        selection=selection, selection_sha256=sha(selection_path) if selection_path is not None else None,
        storage_projection=storage_projection,
        qualification='Original 150 diagnostics (training likelihood), location residuals, 111 extra and 5 positive-loading mean/90% precision; primary loss influence diagnostics; five complete folds and panel numerical screens.',
        pilot_reason='Eight independent paired blocks provide an initial score-specific variance estimate; no precise variance, calibration or general-domain claim. Main uses fresh blocks and a separately frozen N.',
        missing_policy='Any missing/ineligible required fold leaves panel unresolved; never renormalize partial folds.',
        limits=dict(wall_seconds=None, rss_bytes=8*1024**3, output_bytes=output_budget,
            maximum_workers=2, first_worker_max_rss_bytes=3500*1024**2, second_worker_min_available_bytes=5*1024**3),
        hardware=dict(platform=platform.platform(), cpu_count=psutil.cpu_count(),
            memory=dict(psutil.virtual_memory()._asdict()), disk_free=shutil.disk_usage(root).free),
        python_environment=dict(python=platform.python_version(),numpy=np.__version__,scipy=scipy.__version__,psutil=psutil.__version__)))
    subprocess.run([julia, '--startup-file=no', '--project=.', str(RUNNER), 'prepare', str(root)], cwd=REPO, check=True)


def check_plan(root):
    p = read(root/'plan.json')
    assert p['schema'] == 'mgmfrm.foundation_prediction_study.v1'
    assert p['planned_fits'] == 30*p['blocks'] == len(p['attempts'])
    assert p['execution_allowed'] is True and p['scientific_acceptance'] is False
    assert p['summary_mcse_ratio_max'] == .1
    assert p['design_sha256'] == sha(root/'design.json')
    for path, digest in p['source_sha256'].items():
        assert sha(REPO/path) == digest, path
    assert sha(REPO/p['roster']) == p['roster_sha256']
    assert len({a['id'] for a in p['attempts']}) == len(p['attempts'])
    assert len({a['seed'] for a in p['attempts']}) == len(p['attempts'])
    assert len({a['target_identity'] for a in p['attempts']}) == len(p['attempts'])
    assert len({a['person_seed'] for a in p['attempts']}) == len({a['score_seed'] for a in p['attempts']}) == p['blocks']
    roles = [{a[k] for a in p['attempts']} for k in ('person_seed', 'score_seed', 'split_seed', 'seed')]
    assert sum(map(len, roles)) == len(set().union(*roles)), 'RNG seed namespaces overlap'
    for block in range(1, p['blocks']+1):
        group = [a for a in p['attempts'] if a['block'] == block]
        assert {(a['condition'], a['sd'], a['fold']) for a in group} == {
            (c, s, f) for c, s in CONDITIONS for f in range(1, 6)}
        assert len({a['person_seed'] for a in group}) == len({a['score_seed'] for a in group}) == len({a['split_seed'] for a in group}) == 1
        assert all(a['person_seed'] == p['person_seed_base']+10*block+1 and
                   a['score_seed'] == p['score_seed_base']+10*block+2 and
                   a['split_seed'] == p['split_seed_base']+block for a in group)
        partitions = []
        for c, s in CONDITIONS:
            bindings = []
            for a in sorted((a for a in group if (a['condition'], a['sd']) == (c, s)), key=lambda a: a['fold']):
                assert sha(REPO/a['input']) == a['input_sha256']
                assert sha(REPO/a['binding']) == a['binding_sha256']
                b = read(REPO/a['binding'])
                assert b['content_hash'] == a['binding_identity'] and b['target_identity'] == a['target_identity']
                bindings.append(b['heldout_observations'])
            assert sorted(n for fold in bindings for n in fold) == list(range(1, 1251))
            partitions.append(bindings)
        assert all(f == partitions[0] for f in partitions)
    return p


def attempt_result(root, plan, a, sources):
    out = root/'attempts'/a['id']
    row = dict(id=a['id'], block=a['block'], condition=a['condition'], sd=a['sd'], fold=a['fold'],
               seed=a['seed'], status='unstarted', primary_qualified=False, scores=None)
    if not (out/'started.json').exists():
        return row
    def load(name):
        path = out/name
        sources[str(path.relative_to(REPO))] = sha(path)
        return read(path)
    started = load('started.json')
    assert started['plan_sha256'] == sha(root/'plan.json') and started['attempt'] == a
    row['status'] = 'incomplete'
    if (out/'failure.json').exists():
        failure = load('failure.json')
        assert failure['plan_sha256'] == started['plan_sha256'] and failure['binding_identity'] == a['binding_identity']
        row.update(status='failed', failure=failure)
    if not (out/'completion.json').exists():
        return row
    done, execution, review = [load(n) for n in ('completion.json', 'execution.json', 'review.json')]
    for name, digest in done['output_sha256'].items():
        assert sha(out/name) == digest, name
    assert not (out/'failure.json').exists()
    sample_hash = sha(out/'samples.jls')
    sources[str((out/'samples.jls').relative_to(REPO))] = sample_hash
    assert done['completed'] is True and done['plan_sha256'] == started['plan_sha256']
    assert done['binding_identity'] == review['binding_identity'] == a['binding_identity']
    assert execution['target_identity'] == a['target_identity'] and execution['counts'] == [2000]*4
    assert execution['samples_sha256'] == review['samples_sha256'] == sample_hash
    assert len(review['focal']) == 150 and len(review['extra']) == 116 and review['likelihood_scope'] == 'training_only'
    assert done['geometry_qualified'] == review['qualified']
    row.update(status='completed', geometry_qualified=review['qualified'], execution=execution,
               attempt_seconds=done['attempt_seconds'], attempt_cpu_seconds=done['attempt_cpu_seconds'])
    if not review['qualified']:
        assert done['primary_qualified'] is False and not (out/'score.json').exists()
        return row
    score = load('score.json'); binding = read(REPO/a['binding'])
    assert score['samples_sha256'] == sample_hash and score['binding_identity'] == a['binding_identity']
    metrics = score['monte_carlo_error']['rows']
    assert [m['metric'] for m in metrics] == list(METRICS)
    ready = metrics[0]['status'] == 'first_order_candidate' and metrics[0]['diagnostic']['flag'] == 'ok'
    assert ready == done['primary_qualified'] == score['primary_qualified']
    logs = np.asarray(score['log_probabilities']); truth = np.asarray(binding['truth_logs'])
    weights = np.asarray(binding['weights'])
    assert logs.shape == truth.shape == (250, 4) and np.isfinite(logs).all()
    np.testing.assert_allclose(logsumexp(logs, axis=1), 0, atol=1e-10)
    observed = read(REPO/a['input'])['observations']
    rows = [observed[n-1] for n in binding['heldout_observations']]
    assert binding['heldout_ids'] == [[r[k] for k in ('person', 'item', 'rater')] for r in rows]
    expected_weights = np.array([1/(100*(10 if r['item'] in ('I1', 'I2') else 15)) for r in rows])
    np.testing.assert_array_equal(weights, expected_weights)
    categories = np.array([r['score']-1 for r in rows])
    pp, qq = np.exp(logs), np.exp(truth)
    estimates = [np.dot(weights, -logs[np.arange(250), categories]),
        np.dot(weights, ((pp-qq)**2).sum(axis=1)), np.dot(weights, ((pp-qq)@np.arange(1, 5))**2),
        np.dot(weights, (qq*(truth-logs)).sum(axis=1))]
    np.testing.assert_allclose([m['estimate'] for m in metrics], estimates, atol=1e-11, rtol=1e-10)
    row.update(primary_qualified=ready, scores=metrics, monte_carlo_error=score['monte_carlo_error'])
    return row


def panel_result(rows, policy):
    assert len(rows) == 5 and {r['fold'] for r in rows} == set(range(1, 6))
    assert len({r['seed'] for r in rows}) == 5
    first = rows[0]
    complete = all(r['status'] == 'completed' and r['primary_qualified'] for r in rows)
    result = dict(block=first['block'], condition=first['condition'], sd=first['sd'],
        complete=complete, qualified=False, planned_folds=5, usable_folds=sum(r['primary_qualified'] for r in rows),
        fold_ids=[r['id'] for r in rows], metrics=None, numerical_screens=None,
        failure_known=any(r['status'] == 'failed' or (r['status'] == 'completed' and not r['primary_qualified']) for r in rows))
    if not complete:
        return result
    metrics = []
    for j, name in enumerate(METRICS):
        parts = [r['scores'][j] for r in rows]
        usable = all(p['status'] == 'first_order_candidate' and p['diagnostic']['flag'] == 'ok'
                     and p['mcse'] is not None and math.isfinite(p['mcse']) and p['mcse'] > 0 for p in parts)
        errors = [r['monte_carlo_error'] for r in rows]
        gaps = [e['curvature']['rows'][j]['observed_jensen_gap'] for e in errors]
        halves = [e['resolution']['rows'][j]['late_minus_early'] for e in errors]
        prefixes = [[e['resolution']['rows'][j]['prefix_minus_full'][k] for e in errors] for k in (0, 1)]
        finite = all(v is not None and math.isfinite(v) for v in gaps+halves+sum(prefixes, []))
        metrics.append(dict(metric=name, estimate=sum(p['estimate'] for p in parts),
            mcse=math.sqrt(sum(p['mcse']**2 for p in parts)) if usable else None,
            observed_jensen_gap=sum(gaps) if finite else None,
            sum_absolute_half_difference=sum(map(abs, halves)) if finite else None,
            sum_absolute_prefix_differences=[sum(map(abs, p)) for p in prefixes] if finite else None))
    primary = metrics[0]
    screens = dict(mcse=primary['mcse'] is not None and primary['mcse'] <= policy['panel_mcse_max'],
        curvature=primary['observed_jensen_gap'] is not None and abs(primary['observed_jensen_gap']) <= policy['observed_jensen_gap_max'],
        halves=primary['sum_absolute_half_difference'] is not None and primary['sum_absolute_half_difference'] <= policy['sum_absolute_half_difference_max'],
        prefixes=primary['sum_absolute_prefix_differences'] is not None and max(primary['sum_absolute_prefix_differences']) <= policy['sum_absolute_prefix_difference_max'])
    result.update(metrics=metrics, numerical_screens=screens, qualified=all(screens.values()), failure_known=not all(screens.values()))
    return result


def summary_stats(values, mcse):
    result = A.mean_se(values)
    result['sample_variance'] = st.variance(values) if len(values) > 1 else None
    result['within_mcmc_mcse'] = math.sqrt(sum(v*v for v in mcse))/len(mcse) if mcse and all(v is not None for v in mcse) else None
    rep, within = result['replication_mcse'], result['within_mcmc_mcse']
    result['within_over_replication_mcse'] = within/rep if rep and within is not None else None
    ratio = result['within_over_replication_mcse']
    result['mcse_ratio_screen'] = 'unresolved' if ratio is None else 'within_budget' if ratio <= .1 else 'exceeds_budget'
    return result


def planning(summary):
    """Pilot point-estimate planning, conditional on qualification; no precision guarantee."""
    assert summary['stage'] == 'pilot'
    assert sum(summary['statuses'].get(s, 0) for s in ('completed', 'failed')) == summary['planned_fits']
    groups = summary['conditions']+summary['contrasts']
    assert len(summary['conditions']) == 6 and len(summary['contrasts']) == 7
    rows = []
    for g in groups:
        m = g['metrics'][METRICS[0]]; eligible = m['n']; total = g['planned']
        assert 0 <= eligible <= total and total > 0
        variance = m['sample_variance']
        ready = eligible >= 3 and variance is not None and math.isfinite(variance) and variance >= 0
        required = {str(se): math.ceil(max(2, variance/se**2)/(eligible/total)) if ready else None
                    for se in (.005, .01, .02)}
        rows.append(dict(group={k: g[k] for k in ('condition', 'sd', 'baseline', 'alternative') if k in g},
            eligible=eligible, planned=total, sample_variance=variance, required_planned_blocks=required))
    ready = all(r['required_planned_blocks']['0.01'] is not None for r in rows)
    compared = {str(se): 2*math.ceil(max(32, max(r['required_planned_blocks'][str(se)] for r in rows))/2)
                if ready else None for se in (.005, .01, .02)}
    return dict(ready=ready, selected_blocks=compared['0.01'], comparisons=compared, rows=rows,
        interpretation='ceil(max(2, pilot conditional variance / SE^2) / pilot eligibility fraction), maximum over six means and seven paired contrasts, at least 32, rounded up to even. Point-estimate planning ignores variance/eligibility estimation uncertainty; actual precision must be reported. SE target is not a scientific equivalence margin.')


def select_main(root, output):
    p = check_plan(root); s = read(root/'summary.json')
    assert s['plan_sha256'] == sha(root/'plan.json') and p['stage'] == 'pilot'
    for path, digest in s['source_sha256'].items(): assert sha(REPO/path) == digest, path
    calculation = planning(s)
    save(output, dict(ready=calculation['ready'], selected_target=.01, calculation=calculation,
        pilot_root=str(root.relative_to(REPO)), pilot_plan_sha256=sha(root/'plan.json'),
        pilot_summary_sha256=sha(root/'summary.json'), scientific_acceptance=False))


def summarize(root, output):
    plan = check_plan(root); sources = {}; n = plan['blocks']
    rows = [attempt_result(root, plan, a, sources) for a in plan['attempts']]
    panels = [panel_result([r for r in rows if (r['block'], r['condition'], r['sd']) == (b, c, s)], plan['primary_numerical_policy'])
              for b in range(1, n+1) for c, s in CONDITIONS]
    conditions = []
    for c, s in CONDITIONS:
        all_rows = [p for p in panels if (p['condition'], p['sd']) == (c, s)]
        usable = [p for p in all_rows if p['qualified']]
        known = sum(p['failure_known'] for p in all_rows)
        conditions.append(dict(condition=c, sd=s, planned=n, complete=sum(p['complete'] for p in all_rows),
            qualified=len(usable), unresolved=n-len(usable), eligible_blocks=[p['block'] for p in usable],
            failure=A.binomial_envelope(known, n-len(usable)-known, n),
            metrics={m: summary_stats([p['metrics'][j]['estimate'] for p in usable], [p['metrics'][j]['mcse'] for p in usable])
                     for j, m in enumerate(METRICS)}))
    contrasts = []
    lookup = {(p['block'], p['condition'], p['sd']): p for p in panels}
    pairs = [((c, .5), (c, s)) for c in ('R0', 'R1') for s in (.25, 1.)] + [(('R0', s), ('R1', s)) for s in (.25, .5, 1.)]
    for left, right in pairs:
        ids = [b for b in range(1, n+1) if lookup[(b,)+left]['qualified'] and lookup[(b,)+right]['qualified']]
        metrics = {}
        for j, m in enumerate(METRICS):
            ab = [(lookup[(b,)+left]['metrics'][j], lookup[(b,)+right]['metrics'][j]) for b in ids]
            metrics[m] = summary_stats([v['estimate']-u['estimate'] for u, v in ab],
                [math.hypot(u['mcse'], v['mcse']) if u['mcse'] is not None and v['mcse'] is not None else None for u, v in ab])
        contrasts.append(dict(baseline=left, alternative=right, planned=n, eligible_blocks=ids, metrics=metrics))
    save(output, dict(plan_sha256=sha(root/'plan.json'), stage=plan['stage'], planned_fits=len(rows),
        statuses=dict(Counter(r['status'] for r in rows)), rows=rows, panels=panels, conditions=conditions,
        contrasts=contrasts, uniform_reference_nll=math.log(4), source_sha256=sources, scientific_acceptance=False,
        interpretation='Conditional on all five folds and declared primary numerical screens. Independent paired blocks, not folds, give replication MCSE; it already includes remaining MCMC variation. Within-MCMC error is separate and first-order; finite-block checks are not bias bounds. Missing panels keep planned denominators; no unconditional NLL mean/contrast claim.'))


def workers(root):
    p = check_plan(root); plan_hash = sha(root/'plan.json')
    save(root/'worker-controller.json', dict(pid=os.getpid(), create_time=psutil.Process().create_time(), plan_sha256=plan_hash))
    base = [p['julia_binary'], '--startup-file=no', '--project=.', str(RUNNER), 'worker', str(root)]
    with (root/'worker-1.log').open('x') as log1, (root/'worker-2.log').open('x') as log2:
        first = subprocess.Popen(base+['1'], stdout=log1, stderr=subprocess.STDOUT, cwd=REPO)
        second = None; peak = 0
        while first.poll() is None:
            assert sha(root/'plan.json') == plan_hash
            try: peak = max(peak, psutil.Process(first.pid).memory_info().rss)
            except psutil.NoSuchProcess: pass
            ready = (root/'attempts'/p['attempts'][0]['id']/'completion.json').exists()
            available = psutil.virtual_memory().available
            if second is None and ready and peak <= p['limits']['first_worker_max_rss_bytes'] and available >= p['limits']['second_worker_min_available_bytes']:
                save(root/'parallel-decision.json', dict(mode='measured_parallel', first_peak_rss=peak, available_bytes=available))
                second = subprocess.Popen(base+['2'], stdout=log2, stderr=subprocess.STDOUT, cwd=REPO)
            if second is not None and second.poll() not in (None, 0):
                raise RuntimeError('Worker 2 stopped; inspect its unchanged attempt')
            time.sleep(1)
        if first.returncode:
            raise RuntimeError('Worker 1 stopped; inspect its unchanged attempt')
        if second is None:
            save(root/'parallel-decision.json', dict(mode='serial', first_peak_rss=peak, available_bytes=psutil.virtual_memory().available))
            second = subprocess.Popen(base+['2'], stdout=log2, stderr=subprocess.STDOUT, cwd=REPO)
        if second.wait(): raise RuntimeError('Worker 2 stopped; inspect its unchanged attempt')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare-pilot', 'prepare-main', 'select-main', 'run', 'workers', 'summarize'))
    parser.add_argument('root', type=Path); parser.add_argument('--julia'); parser.add_argument('--output', type=Path)
    parser.add_argument('--selection', type=Path)
    args = parser.parse_args(); root = args.root.resolve()
    for key in ('JULIA_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'JULIA_NUM_PRECOMPILE_TASKS'): os.environ[key] = '1'
    os.environ['JULIA_PKG_PRECOMPILE_AUTO'] = '0'
    if args.action in ('prepare-pilot', 'prepare-main'):
        if not args.julia: parser.error('--julia required')
        if args.action == 'prepare-main' and args.selection is None: parser.error('--selection required')
        if args.action == 'prepare-pilot' and args.selection is not None: parser.error('Pilot has no selection')
        prepare_study(root, args.julia, args.selection)
    elif args.action == 'select-main':
        if args.output is None: parser.error('--output required')
        select_main(root, args.output)
    elif args.action == 'summarize':
        if args.output is None: parser.error('--output required')
        summarize(root, args.output)
    elif args.action == 'workers': workers(root)
    else:
        p = check_plan(root)
        save(root/'controller.json', dict(pid=os.getpid(), create_time=psutil.Process().create_time(), plan_sha256=sha(root/'plan.json')))
        receipt = run_guarded([sys.executable, str(Path(__file__).resolve()), 'workers', str(root)],
            root/'guard', cwd=str(REPO), output_root=root, poll_seconds=1, wall_seconds=None,
            rss_bytes=p['limits']['rss_bytes'], output_bytes=p['limits']['output_bytes'])
        summarize(root, root/'summary.json')
        print(json.dumps(receipt), flush=True)
        sys.exit(0 if receipt['status'] == 'completed' else 1)
