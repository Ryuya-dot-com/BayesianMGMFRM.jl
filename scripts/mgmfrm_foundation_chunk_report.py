"""Read-only whole-fit AD comparison, retaining diagnostic failures and planned attempts."""
import argparse
from pathlib import Path

import mgmfrm_foundation_assessment as A
from mgmfrm_foundation_assessment_report import finite, transition_times


def payload_equal(a, b, excluded=()):
    return {k: v for k, v in a.items() if k not in excluded} == {
        k: v for k, v in b.items() if k not in excluded}


def analyze(root, output):
    plan = A.read(root/'plan.json')
    plan_hash = A.sha(root/'plan.json')
    samples = A.read(root/'sample-comparison.json')
    assert samples['plan_sha256'] == plan_hash
    preflight = A.read(root/'preflight.json')
    assert preflight['plan_sha256'] == plan_hash and preflight['passed'] is True
    assert preflight['threads'] == preflight['blas_threads'] == 1
    assert A.sha(A.REPO/plan['study_plan']) == plan['study_plan_sha256']
    study = A.read(A.REPO/plan['study_plan'])
    for path, digest in plan['source_sha256'].items():
        assert A.sha(A.REPO/path) == digest, path
    log = (root/'guard/command.log').read_text()
    rows = []
    sources = {str(root/'sample-comparison.json'): A.sha(root/'sample-comparison.json')}
    for a in plan['attempts']:
        out = root/'attempts'/a['id']
        records = {}
        for name in ('started.json', 'execution.json', 'completion.json', 'core/review.json', 'extra.json', 'loading-review.json'):
            p = out/name
            records[name] = A.read(p)
            sources[str(p)] = A.sha(p)
        started, execution, completion, core, extra, loading = records.values()
        old = next(x for x in study['attempts'] if x['id'] == a['study_id'])
        assert started['plan_sha256'] == plan['study_plan_sha256']
        assert A.sha(A.REPO/old['input']) == old['input_sha256']
        assert completion['completed'] is True and execution['counts'] == [2000]*4
        sample_hash = A.sha(out/'samples.jls')
        assert execution['samples_sha256'] == sample_hash
        for r in (core, extra, loading):
            assert r['samples_sha256'] == sample_hash and r['target_identity'] == old['target_identity']
            assert r['input_sha256'] == old['input_sha256']
        assert extra['core_review_sha256'] == A.sha(out/'core/review.json')
        assert A.sha(out/'core/values.bin') == core['values']['sha256']
        timing_path = root/f"{a['id']}-timing.json"
        timing = A.read(timing_path)
        assert timing['plan_sha256'] == plan_hash and timing['attempt'] == a
        setting = A.read(root/f"{a['id']}-setting.json")
        assert setting['plan_sha256'] == plan_hash and setting['attempt'] == a
        assert timing['evaluation_credit'] == setting['evaluation_credit'] == plan['evaluation_credit'] == 0
        sources[str(timing_path)] = A.sha(timing_path)
        segment = log.split(f" comparison {a['id']} start\n", 1)[1].split(f" comparison {a['id']} complete\n", 1)[0]
        phases = transition_times(segment, a['study_id'])
        ds = core['focal'] + core['location'] + core['residuals']
        ds += [r['diagnostic'] for r in extra['rows'] + loading['rows']]
        assert all(finite(r[k]) for r in ds for k in ('bulk_ess', 'tail_ess', 'rank_normalized_rhat'))
        qualified = extra['primary_quantities_qualified'] and all(r['qualified90'] for r in loading['rows'])
        minimum = min(ds, key=lambda r: r['bulk_ess'])
        rows.append(dict(**a, qualified=qualified, fit_seconds=execution['elapsed_seconds'], **phases,
            attempt_seconds=timing['seconds'], attempt_compile_seconds=timing['compile_seconds'],
            attempt_gc_seconds=timing['gc_seconds'], maximum_rhat=max(r['rank_normalized_rhat'] for r in ds),
            minimum_bulk_ess=minimum['bulk_ess'], minimum_bulk_parameter=minimum['parameter'],
            bulk_ess_per_fit_second=minimum['bulk_ess']/execution['elapsed_seconds'] if qualified else None,
            divergences=core['diagnostic']['n_divergences'], depth_hits=core['diagnostic']['n_max_treedepth'],
            prediction_unqualified=sum(not r['qualified'] for r in extra['prediction']),
            max_extra_mean_mcse_over_sd=max(r['precision']['mean_mcse']/r['posterior_sd'] for r in extra['rows']),
            max_loading_mean_mcse_over_sd=max(r['precision']['mean_mcse']/r['posterior_sd'] for r in loading['rows'])))
    comparisons = []
    for pair in samples['pairs']:
        a, b = [next(r for r in rows if r['study_id'] == pair['study_id'] and r['chunk'] == c) for c in (12, 16)]
        left, right = [root/'attempts'/r['id'] for r in (a, b)]
        starts_equal = A.read(left/'execution.json')['starts'] == A.read(right/'execution.json')['starts']
        checks = {name: payload_equal(A.read(left/name), A.read(right/name), ('samples_sha256', 'core_review_sha256'))
                  for name in ('core/review.json', 'extra.json', 'loading-review.json')}
        exact = pair['all_run_fields_equal'] and pair['priors_equal'] and starts_equal and all(checks.values())
        reduction = 1-b['fit_seconds']/a['fit_seconds']
        comparisons.append(dict(study_id=pair['study_id'], all_numerical_outputs_equal=exact,
            baseline_reproduces_original_run=pair['baseline_reproduces_original_run'],
            initial_coordinates_equal=starts_equal, review_payloads_equal=checks,
            fit_time_reduction=reduction, fit_speed_ratio=a['fit_seconds']/b['fit_seconds'],
            attempt_time_reduction=1-b['attempt_seconds']/a['attempt_seconds'],
            saved_run_fields_equal=pair['fields'], qualification_preserved=a['qualified'] == b['qualified'],
            qualifies_for_local_adoption=exact and reduction >= plan['adoption']['minimum_fit_time_reduction_each_pair']))
    guard = A.read(root/'guard/guard-receipt.json')
    assert guard['status'] == 'completed' and guard['exit_code'] == 0
    A.save(output, dict(plan_sha256=plan_hash, source_sha256=sources,
        script_sha256=A.sha(Path(__file__)), planned=len(plan['attempts']), completed=len(rows), rows=rows,
        comparisons=comparisons, local_setting_supported=all(c['qualifies_for_local_adoption'] for c in comparisons),
        guard=guard, independent_evaluation_credit=0, scientific_acceptance=False,
        interpretation='Two deliberately selected saved targets, one serial AB/BA comparison; shared host and first-full-fit compilation remain. '
        'Preserved failures are not numerical passes. Exact saved numerical outputs and 5% full-fit improvement on each target are the fixed local decision rule. '
        'No general-domain, calibrated speedup or resolution-of-failure claim.'))


def self_check():
    assert payload_equal({'x': [1., 2.], 'samples_sha256': 'a'}, {'x': [1., 2.], 'samples_sha256': 'b'}, ('samples_sha256',))
    assert not payload_equal({'x': [1., 2.]}, {'x': [1., 3.]})
    assert not payload_equal({'x': 1}, {'x': 1, 'y': 2})
    print('Comparison payload checks passed; no fitting.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-check', action='store_true')
    parser.add_argument('--root', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.self_check:
        self_check()
    else:
        if args.root is None or args.output is None:
            parser.error('--root and --output required')
        analyze(args.root.resolve(), args.output.resolve())
