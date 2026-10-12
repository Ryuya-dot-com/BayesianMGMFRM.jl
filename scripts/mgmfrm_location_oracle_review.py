"""Exact conditional classification risks for a standard-normal posterior pivot.

Use only after proving that the chosen quantity has this posterior distribution.
Integrates over a fresh posterior truth, conditional on the observed dataset and
the actual fitted chains. This is not a bound across datasets or across all
MGMFRM quantities. No assumption that the chain draws are iid is needed for
this integration; the normal oracle, not the empirical chain CDF, supplies mass.
"""
import argparse
import hashlib
import json
from pathlib import Path

from scipy.stats import norm
from mgmfrm_core_rank_review import rank_bands, classify_rank_bands


def normal_classifier_risk(bands):
    classify_rank_bands(dict(truth=0., rank_bands=bands))  # Validate even degenerate bands.
    cuts = {0., .05, .5, .95, 1.}
    for b in bands:
        cuts.update(float(norm.cdf(b[side])) for side in ('lower', 'upper') if b[side] is not None)
    cuts = sorted(cuts)
    result = {k: dict(correct=0., wrong=0., unresolved=0.) for k in ('below_median', 'covered_90')}
    for lo, hi in zip(cuts, cuts[1:]):
        u = (lo+hi)/2
        if not lo < u < hi:  # Sub-ulp tail mass cannot be resolved in Float64.
            continue
        answer = classify_rank_bands(dict(truth=float(norm.ppf(u)), rank_bands=bands))
        ideal = dict(below_median=u < .5, covered_90=.05 < u < .95)
        for key in result:
            status = 'unresolved' if answer[key] is None else 'correct' if answer[key] == ideal[key] else 'wrong'
            result[key][status] += hi-lo
    return result


def review(record):
    if type(record['qualified']) is not bool:
        raise ValueError('Explicit diagnostic qualification required')
    if len(record['z_columns']) != 2 or len(record['precision']['rows']) != 2 or len(record['truth_z']) != 2:
        raise ValueError('Exactly two location pivots required')
    rows = []
    for d, (values, precision, truth) in enumerate(zip(record['z_columns'], record['precision']['rows'], record['truth_z']), 1):
        ess = {q['probability']: q['ess'] if q['ess'] is not None and q['ess'] >= 400 else None
               for q in precision['quantiles']}
        for multiplier in (2., 4.):
            bands = rank_bands(values, quantile_ess=ess, multiplier=multiplier)
            risk = normal_classifier_risk(bands)
            effective = risk if record['qualified'] else {
                key: dict(correct=0., wrong=0., unresolved=1.) for key in risk}
            actual = classify_rank_bands(dict(truth=truth, rank_bands=bands))
            rows.append(dict(dimension=d, multiplier=multiplier, bands=bands,
                conditional_risk_before_diagnostic_gate=risk, conditional_risk=effective,
                truth=truth, oracle_truth_events=dict(below_median=truth<0.,
                    covered_90=bool(norm.ppf(.05)<truth<norm.ppf(.95))),
                actual_truth_classification=actual if record['qualified'] else dict.fromkeys(actual)))
    return dict(rows=rows, qualified=record['qualified'], new_fits=0,
        oracle='Two location pivots with exact N(0,1) posterior; conditional on this dataset and these chains',
        risk_definition='P(resolved AND wrong), not P(wrong | resolved)',
        dataset_averaged_error_bound_verified=False, all_150_quantities_verified=False,
        scientific_acceptance=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = review(json.loads(args.input.read_text()))
    result['input_sha256'] = hashlib.sha256(args.input.read_bytes()).hexdigest()
    result['source_sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in
        (Path(__file__), Path(__file__).with_name('mgmfrm_core_rank_review.py'))}
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2, allow_nan=False)
        stream.write('\n')
