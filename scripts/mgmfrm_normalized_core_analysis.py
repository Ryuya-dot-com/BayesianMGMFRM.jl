"""Audit a normalized core review; empirical band masses are not error bounds."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy.special import logsumexp
from mgmfrm_core_rank_review import rank_bands, classify_rank_bands
from mgmfrm_location_oracle_review import review as oracle_review

PERSONS = sorted(f'P{i}' for i in range(1, 51))
DIMS = np.array([0, 0, 1, 1, 1])


def quantities(raw, observations):
    """Independent response equations and 22 derived quantities, in frozen order."""
    n = len(raw)
    theta = raw[:, :100].reshape(n, 50, 2)
    severity = np.column_stack((raw[:, 100:104], -raw[:, 100:104].sum(axis=1)))
    loggamma = np.column_stack((raw[:, 114:118], -raw[:, 114:118].sum(axis=1)))
    a, b = np.exp(raw[:, 109:114]), raw[:, 104:109]
    free = raw[:, 118:128].reshape(n, 5, 2)
    steps = np.concatenate((free, -free.sum(axis=2, keepdims=True)), axis=2)
    means = theta.mean(axis=1)
    weighted = a * means[:, DIMS]
    location = np.column_stack([means] + [col for i in range(5)
        for col in (weighted[:, i], b[:, i] - weighted[:, i])])
    pidx = np.array([PERSONS.index(r['person']) for r in observations])
    iidx = np.array([int(r['item'][1:])-1 for r in observations])
    ridx = np.array([int(r['rater'][1:])-1 for r in observations])
    scores = np.array([r['score']-1 for r in observations])
    ll = np.empty(n)
    for start in range(0, n, 128):
        rows = slice(start, start+128)
        eta = a[rows][:, iidx]*theta[rows][:, pidx, DIMS[iidx]] - b[rows][:, iidx] - severity[rows][:, ridx]
        delta = 1.7*np.exp(loggamma[rows][:, ridx])[:, :, None]*(eta[:, :, None]-steps[rows][:, iidx, :])
        logits = np.concatenate((np.zeros((*eta.shape, 1)), delta.cumsum(axis=2)), axis=2)
        logs = logits-logsumexp(logits, axis=2, keepdims=True)
        ll[rows] = logs[:, np.arange(len(scores)), scores].sum(axis=1)
    return np.column_stack((raw, severity[:, -1], loggamma[:, -1], steps[:, :, -1],
        theta[:, PERSONS.index('P1'), :].prod(axis=1),
        theta[:, PERSONS.index('P2'), :].prod(axis=1), ll, location))


def analyze(input_path, directory):
    read = lambda p: json.loads(p.read_text())
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    x, record = read(input_path), read(directory/'review.json')
    assert digest(input_path) == record['input_sha256']
    assert digest(directory/'values.bin') == record['values']['sha256']
    values = np.fromfile(directory/'values.bin', dtype='<f8').reshape(4000, 150, order='F')
    expected = quantities(values[:, :128], x['observations'])
    error = float(np.max(np.abs(expected-values)))
    truth_error = float(np.max(np.abs(quantities(np.array([x['raw_truth']]), x['observations'])[0]-record['truths'])))
    qerror = float(np.max(np.abs(np.quantile(values, [.05, .5, .95], axis=0).T -
        [[q['estimate'] for q in r['quantiles']] for r in record['precision']['rows']])))
    assert error < 1e-8 and truth_error < 1e-8 and qerror < 1e-10
    oracle_input = read(directory/'oracle-input.json')
    raw = values[:, :128]
    mu = raw[:, :100].reshape(-1, 50, 2).mean(axis=1)
    a, b = np.exp(raw[:, 109:114]), raw[:, 104:109]
    z = np.zeros_like(mu)
    for d, ix in enumerate(([0, 1], [2, 3, 4])):
        precision = 50+(a[:, ix]**2).sum(axis=1)
        center = -(a[:, ix]*(b[:, ix]-a[:, ix]*mu[:, d, None])).sum(axis=1)/precision
        z[:, d] = np.sqrt(precision)*(mu[:, d]-center)
    zerror = float(np.max(np.abs(z-np.array(oracle_input['z_columns']).T)))
    assert zerror < 1e-12
    rows = record['focal']+record['location']+record['residuals']
    qualified = record['original_gate'] and all(r['flag'] == 'ok' for r in rows)
    assert qualified == record['qualified']
    outcomes = []
    for multiplier in (2., 4.):
        detail = []
        for j, precision in enumerate(record['precision']['rows']):
            assert precision['parameter'] == record['names'][j]
            ess = {q['probability']: q['ess'] if q['ess'] is not None and q['ess'] >= 400 else None
                   for q in precision['quantiles']}
            bands = rank_bands(values[:, j], quantile_ess=ess, multiplier=multiplier)
            actual = classify_rank_bands(dict(truth=record['truths'][j], rank_bands=bands))
            limits = [(b['lower'] if b['lower'] is not None else -np.inf,
                       b['upper'] if b['upper'] is not None else np.inf) for b in bands]
            lo, med, hi = limits
            v = values[:, j]
            # Empirical mass of unresolved classification regions, including unbounded ends.
            masses = dict(below_median=float(np.mean((med[0] <= v) & (v <= med[1]))),
                covered_90=float(np.mean((v >= lo[0]) & (v <= hi[1]) & ~((v > lo[1]) & (v < hi[0])))))
            detail.append(dict(parameter=precision['parameter'], bands=bands,
                actual_truth_before_gate=actual,
                actual_truth=actual if qualified else dict.fromkeys(actual),
                empirical_unresolved_mass_before_gate=masses))
        counts = lambda key: {event: {status: sum(r[key][event] is val for r in detail)
            for status, val in [('true', True), ('false', False), ('unresolved', None)]}
            for event in ('below_median', 'covered_90')}
        outcomes.append(dict(multiplier=multiplier, rows=detail,
            counts_before_gate=counts('actual_truth_before_gate'), counts=counts('actual_truth'),
            empirical_mass_summary={event: dict(mean=float(np.mean([r['empirical_unresolved_mass_before_gate'][event] for r in detail])),
                maximum=max(r['empirical_unresolved_mass_before_gate'][event] for r in detail))
                for event in ('below_median', 'covered_90')}))
    qess = [q['ess'] for r in record['precision']['rows'] for q in r['quantiles']]
    result = dict(qualified=qualified, original_gate=record['original_gate'],
        maximum_derived_error=error, maximum_truth_error=truth_error, maximum_quantile_error=qerror,
        maximum_pivot_error=zerror, pivot_values_verified=8000,
        derived_values_verified=4000*22, truths_verified=150, quantiles_verified=450,
        maximum_focal_rhat=max(r['rank_normalized_rhat'] for r in record['focal']),
        minimum_focal_bulk_ess=min(r['bulk_ess'] for r in record['focal']),
        minimum_focal_tail_ess=min(r['tail_ess'] for r in record['focal']),
        minimum_quantile_ess=min(e for e in qess if e is not None),
        quantile_ess_below_floor=sum(e is not None and e < 400 for e in qess),
        quantile_ess_unavailable=sum(e is None for e in qess),
        failed_rows=[r for r in rows if r['flag'] != 'ok'],outcomes=outcomes,
        oracle=oracle_review(oracle_input),
        masses_are_empirical_not_bounds=True,parameter_events_are_not_independent_trials=True,
        ess_estimator_independently_implemented=False,scientific_acceptance=False)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('review_directory', type=Path)
    args = parser.parse_args()
    result = analyze(args.input, args.review_directory)
    with (args.review_directory/'analysis.json').open('x') as stream:
        json.dump(result, stream, indent=2, allow_nan=False)
        stream.write('\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ('outcomes', 'oracle', 'failed_rows')}))
    for r in result['outcomes']:
        print(r['multiplier'], r['counts'], r['empirical_mass_summary'])
