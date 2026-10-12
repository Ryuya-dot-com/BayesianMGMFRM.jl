"""Bind the finite post-pilot comparison design; never compile, fit or launch.

This is a design receipt, not an executable protocol. Pilot closeout, the native
target preflight and a separately frozen runner remain required before sampling.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
from statistics import NormalDist

REPO = Path(__file__).resolve().parents[1]
BALANCED = ('B001-R0-025-F1', 'B002-R0-050-F2', 'B003-R0-100-F3',
            'B001-R1-025-F4', 'B003-R1-050-F5', 'B003-R1-100-F1')
STRESS = ('B002-R0-100-F2', 'B002-R1-050-F5')
COUNTS = {'focal': 150, 'location': 17, 'residuals': 9, 'extra': 116}
METRICS = ('negative_log_predictive_probability', 'squared_category_probability_error',
           'squared_expected_score_error', 'log_score_regret')
DOCUMENT = 'docs/internal/mgmfrm-foundation-scale-acceptance.md'


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def quantity_roster(review):
    roster = []
    for block, count in COUNTS.items():
        names = [r['parameter'] for r in review[block]]
        require(len(names) == len(set(names)) == count, f'Changed {block} roster')
        roster.extend(dict(block=block, parameter=n) for n in names)
    return roster


def weight_sum(binding):
    weights = binding['weights']
    require(len(weights) == 250 and all(w in (1/1000, 1/1500) for w in weights),
            'Expected global person/dimension weights, without fold renormalization')
    return math.fsum(weights)


def schedule():
    rows = []
    for repetition in range(2):
        indices = range(8) if repetition == 0 else reversed(range(8))
        for index in indices:
            backends = ('advancedhmc', 'cmdstan') if (index+repetition) % 2 == 0 else ('cmdstan', 'advancedhmc')
            for backend in backends:
                seed = 202610090 + 100*(8*repetition+index) + (10 if backend == 'cmdstan' else 0)
                rows.append(dict(order=len(rows)+1, case=(BALANCED+STRESS)[index],
                    repetition=repetition+1, backend=backend, seed=seed,
                    cmdstan_chain_seeds=[seed+i for i in range(1, 5)] if backend == 'cmdstan' else None))
    return rows


def prepare(root, output):
    require(not output.exists(), f'Never overwrite evidence: {output}')
    plan_path = root/'plan.json'
    plan = read(plan_path)
    require(plan['stage'] == 'pilot' and plan['planned_fits'] == 240 and plan['blocks'] == 8,
            'Expected the frozen 240-fit pilot')
    require(plan['controls']['chains'] == 4 and plan['controls']['ndraws'] == 1000
            and plan['controls']['warmup'] == 1000 and plan['limits']['wall_seconds'] is None,
            'Pilot controls changed')
    require(plan['metrics'] == list(METRICS), 'Score roster changed')
    evidence = {str(plan_path.relative_to(REPO)): sha(plan_path)}

    def bind(relative, expected=None):
        digest = sha(REPO/relative)
        require(expected is None or digest == expected, f'Changed evidence: {relative}')
        evidence[relative] = digest
        return read(REPO/relative)

    original = bind(plan['roster'], plan['roster_sha256'])
    attempts = {a['id']: a for a in plan['attempts']}
    require(len(attempts) == len(plan['attempts']) == 240, 'Duplicate/missing pilot IDs')
    cases, roster = [], None
    for ident in BALANCED+STRESS:
        attempt = attempts[ident]
        bind(attempt['input'], attempt['input_sha256'])
        binding = bind(attempt['binding'], attempt['binding_sha256'])
        require(binding['target_identity'] == attempt['target_identity'] and
                binding['content_hash'] == attempt['binding_identity'], 'Target/binding changed')
        total_weight = weight_sum(binding)
        review_path = str((root/'attempts'/ident/'review.json').relative_to(REPO))
        review = bind(review_path)
        require(review['binding_identity'] == attempt['binding_identity'], 'Review target changed')
        current = quantity_roster(review)
        require([r['parameter'] for r in review['focal']] == original, 'Original 150 quantities changed')
        require(roster is None or roster == current, 'Case quantity rosters differ')
        roster = current
        if ident in STRESS:
            require(review['qualified'] is False, 'Declared historical stress case changed')
        cases.append(dict(attempt, role='balanced' if ident in BALANCED else 'historical_stress',
                          historical_geometry_qualified=review['qualified'],
                          heldout_global_weight_sum=total_weight))
    statistics = ['mean', 'sd', 'q0.05', 'q0.95']
    comparisons = 16*(len(roster)*len(statistics)+len(METRICS))
    for relative in (DOCUMENT, 'scripts/mgmfrm_foundation_efficiency_design.py',
                     'test/mgmfrm_foundation_efficiency_design.py'):
        evidence[relative] = sha(REPO/relative)
    result = dict(schema='mgmfrm.foundation_efficiency_design.v1',
        execution_allowed=False, executable_protocol_frozen=False, posterior_fits=0,
        prerequisites=['validated_pilot_closeout', 'location_stan_density_gradient_preflight',
                       'frozen_runner_sources_environment_and_executable', 'verified_scoring_and_cost_accounting'],
        cases=cases, schedule=schedule(), planned_fits=32, repetitions=2,
        retries=0, replacements=0, extensions=0, independent_validation_blocks_added=0,
        controls=plan['controls'], sampling_coordinates='orthogonal_person_mean_item_offset',
        initial_step_size=0.03, max_energy_error=1000.0, julia_forwarddiff_chunk=12,
        resources=dict(simultaneous_fits=1, simultaneous_chains=1, threads=1,
                       rss_bytes=8*1024**3, disk_reserve_bytes=5*1024**3, wall_seconds=None),
        quantities=roster, statistics=statistics, metrics=list(METRICS),
        agreement=dict(planned_comparisons=comparisons, normal_union_alpha=0.05,
            normal_multiplier=NormalDist().inv_cdf(1-0.05/(2*comparisons)),
            posterior_mcse_sd_ratio_max=0.05, posterior_difference_bound_sd_ratio_max=0.3,
            prediction_weighting='unchanged_global_person_dimension_weights_no_fold_renormalization',
            prediction_fold_difference_bound_max=0.005/5,
            prediction_fold_mcse_max=0.005/(5*3),
            prediction_fold_jensen_gap_max=0.005/5,
            prediction_fold_absolute_half_or_prefix_difference_max=0.01/5,
            predictive_primary_policy=plan['primary_numerical_policy'],
            interpretation='Approximate MCSE resolution, not joint-distribution equality or scientific equivalence'),
        efficiency=dict(ratio_direction='cmdstan/advancedhmc',
            metric='sampling_through_verified_save_diagnostics_and_scoring_elapsed_seconds',
            balanced_geomean_ratio_max_each_repetition=0.8,
            every_pair_elapsed_ratio_max=1.0, balanced_cpu_geomean_ratio_max_each_repetition=1.0,
            require_all_pairs_numerically_eligible=True, include_failed_attempt_costs=True,
            inference='Descriptive decision on eight declared targets; no population speed confidence claim'),
        policy_document=DOCUMENT, evidence_sha256=evidence)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('x') as stream:
        json.dump(result, stream, indent=2, allow_nan=False)
        stream.write('\n')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = prepare(args.root.resolve(), args.output.resolve())
    print(f"Design bound: {len(result['cases'])} cases, {result['planned_fits']} planned fits; execution disabled")
