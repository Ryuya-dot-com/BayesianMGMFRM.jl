"""Calculate a review-only fixed-facet design; no fitting or evaluation data export."""
import argparse
import hashlib
import json
import math
from pathlib import Path
from statistics import NormalDist, median

from mgmfrm_core_reference import generate, recovery_raw, state


def engineering_check():
    """Two disposable paired blocks check the existing DGP, not recovery."""
    receipts = []
    for person_seed in (20260927014001, 20260927014003):
        raw0, raw1 = [recovery_raw(c, person_seed) for c in ('R0', 'R1')]
        assert raw0[:109] == raw1[:109] and raw0[111:] == raw1[111:]
        panels = [generate(raw, person_seed + 1) for raw in (raw0, raw1)]
        for raw, (observed, truth) in zip((raw0, raw1), panels):
            v = state(raw)
            assert abs(math.fsum(v['severity'])) < 1e-12
            assert abs(math.fsum(v['log_consistency'])) < 1e-12
            assert all(abs(math.fsum(x)) < 1e-12 for x in v['steps'])
            assert len(observed['observations']) == 1250
            assert len({(r['person'], r['item'], r['rater']) for r in observed['observations']}) == 1250
            assert all(r['score'] in (1, 2, 3, 4) for r in observed['observations'])
            assert all(abs(math.fsum(map(math.exp, row))-1) < 1e-12 for row in truth['log_probabilities'])
        # D2 has unchanged truth and the same response uniforms, so its scores agree.
        d2 = lambda p: [r for r in p[0]['observations'] if r['item'] in ('I3', 'I4', 'I5')]
        assert d2(panels[0]) == d2(panels[1])
        receipts.append(dict(person_seed=person_seed, score_seed=person_seed+1,
                             paired_D2_rows_equal=len(d2(panels[0]))))
    return dict(blocks=receipts, engineering_panels=4, evaluation_panels=0,
                posterior_fits=0, fit_ready_inputs_exported=False)


def design(repo):
    sources = [Path(__file__), Path(__file__).with_name('mgmfrm_core_reference.py')]
    cost_root = repo/'results/workflows/20260927-foundation-sensitivity-01'
    costs = []
    for name in ('first-025', 'first-100', 'independent-025', 'independent-100'):
        path = cost_root/name/'guard-receipt.json'
        receipt = json.loads(path.read_text())
        if receipt['status'] != 'completed':
            raise ValueError('Completed cost references required')
        sources.append(path)
        costs.append(receipt['seconds'])
    seconds = median(costs)
    z = NormalDist().inv_cdf(.975)
    scales = [dict(log_loading_sd=s,
        loading_central_95=[math.exp(-z*s), math.exp(z*s)],
        same_dimension_loading_ratio_central_95=[math.exp(-z*math.sqrt(2)*s), math.exp(z*math.sqrt(2)*s)],
        prior_probability_loading_at_most_R1_I1=NormalDist().cdf(math.log(.35)/s),
        prior_probability_loading_at_most_R1_I2=NormalDist().cdf(math.log(.5)/s))
        for s in (.25, .5, 1.)]
    facets = {}
    for condition in ('R0', 'R1'):
        # Only fixed coordinates are exported; discarded persons are not a panel.
        facets[condition] = {k: v for k, v in state(recovery_raw(condition, 0)).items() if k != 'theta'}
    precision = [dict(paired_blocks=n, panels=2*n, fits=6*n,
        serial_hours_reference=6*n*seconds/3600,
        nominal_pointwise_coverage_mcse_pp=100*math.sqrt(.9*.1/n),
        worst_case_single_coverage_mcse_pp=50/math.sqrt(n),
        worst_case_paired_coverage_difference_mcse_pp=100/math.sqrt(n))
        for n in (8, 32, 128)]
    counts = [dict(target_pointwise_mcse_pp=100*h,
        panels_per_condition_if_p_equals_09=math.ceil(.09/h**2),
        panels_per_condition_worst_case=math.ceil(.25/h**2)) for h in (.01, .02, .03)]
    return dict(schema='mgmfrm.foundation_fixed_facet_design.v1',
        scope='review_only_fixed_facets_random_persons_and_responses',
        fitting_prior='normalized_exchangeable_C_with_loading_sd_sensitivity',
        person_distribution='iid N(0,I_2); no realized-sample centering or rescaling',
        fixed_facets=facets, loading_prior_interpretation=scales,
        baseline_log_loading_sd=.5, scientifically_adopted_prior=False,
        pairing='One independent block shares persons and score uniforms across R0/R1; each panel is shared across three priors. Fit streams are distinct.',
        fixed_N_options=precision, pointwise_precision_references=counts,
        selected_evaluation_N=None, adopted_calibration_margin=None,
        calibration_margins_pp=[2.5, 5., 7.5],
        cost_reference=dict(median_guard_seconds=seconds, observations=costs,
            limitation='Four different joint-prior panels/prior fits; includes their postprocessing, not a cost guarantee for R0/R1 or scientific review.'),
        next_rehearsal_proposal=dict(paired_blocks=1, panels=2, maximum_fits=6,
            serial_hours_reference=6*seconds/3600, batch_wall_hours=5,
            per_attempt_wall_minutes=45, rss_gib=4, output_mib_per_attempt=256,
            retries=0, extensions=0, evaluation_credit=0,
            requires_new_input_binding_and_frozen_execution_manifest=True),
        engineering_check=engineering_check(),
        source_sha256={str(p.resolve().relative_to(repo)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
        posterior_fits_launched=0, execution_allowed=False,
        independent_scientific_review='pending', scientific_acceptance=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = design(Path(__file__).resolve().parents[1])
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2, allow_nan=False)
        stream.write('\n')
    print(json.dumps(dict(engineering_check=result['engineering_check'],
        fixed_N_options=result['fixed_N_options'], posterior_fits_launched=0), indent=2))
