"""Invert the existing conditional acceptance worksheet; never launch fits.

Integer binomial thresholds can make power bounds nonmonotone. Scan every
integer, then check the rounded planning count separately. All e/u bounds
remain assumptions, including when they resemble observed pilot quantities.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import platform
import statistics

import numpy as np
import scipy
from scipy.stats import binom
from mgmfrm_foundation_acceptance_review import acceptance_design


def power_bounds(ns, *, margin, unresolved_rate, error_rate, quantities=150):
    acceptance_design(1, quantities=quantities, margin=margin,
        unresolved_rate=unresolved_rate, error_rate=error_rate)
    ns = np.asarray(ns)
    if ns.ndim != 1 or ns.dtype.kind not in 'iu' or len(ns) == 0 or np.any(ns < 1):
        raise ValueError('Nonempty vector of positive integer counts required')
    failures = np.zeros(len(ns))
    for p in (.5, .9):
        null_high, null_low = p-margin+error_rate, p+margin-error_rate
        low = binom.ppf(.05, ns, null_low).astype(int)
        low -= binom.cdf(low, ns, null_low) > .05
        complement = binom.ppf(.05, ns, 1-null_high).astype(int)
        complement -= binom.cdf(complement, ns, 1-null_high) > .05
        high = ns-complement
        failures += binom.cdf(high-1, ns, max(0., p-unresolved_rate-error_rate))
        failures += binom.sf(low, ns, min(1., p+unresolved_rate+error_rate))
    return np.maximum(0., 1-quantities*failures)


def first_count(*, margin, unresolved_rate, error_rate, quantities=150,
                target_power=.8, scan_limit=200000):
    settings = dict(margin=margin, unresolved_rate=unresolved_rate,
                    error_rate=error_rate, quantities=quantities)
    probe = acceptance_design(1, **settings)
    if (type(scan_limit) is not int or scan_limit < 1 or
            type(target_power) not in (int, float) or not 0 < target_power < 1):
        raise ValueError('Positive integer scan limit and interior target power required')
    result = dict(**settings, target_power=target_power, scan_limit=scan_limit,
        separation_gap=margin-unresolved_rate-2*error_rate,
        assumptions_verified=False, scientific_acceptance=False)
    if not probe['nominal_worst_mechanism_separated']:
        return dict(result, status='no_worst_case_separation', first_count=None)
    previous_max = 0.
    for start in range(1, scan_limit+1, 2048):
        ns = np.arange(start, min(start+2048, scan_limit+1))
        bounds = power_bounds(ns, **settings)
        eligible = np.flatnonzero(bounds >= target_power)
        if len(eligible):
            index = int(eligible[0]); n = int(ns[index])
            prior_max = max(previous_max, float(bounds[:index].max()) if index else 0.)
            exact = acceptance_design(n, **settings)
            assert abs(exact['nominal_joint_acceptance_probability_lower_bound']-bounds[index]) < 1e-10
            rounded = 100*math.ceil(n/100)
            while acceptance_design(rounded, **settings)['nominal_joint_acceptance_probability_lower_bound'] < target_power:
                rounded += 100
            return dict(result, status='first_bound_crossing', first_count=n,
                maximum_bound_at_any_smaller_count=prior_max, design=exact,
                rounded_design=acceptance_design(rounded, **settings),
                larger_counts_automatically_certified=False)
        previous_max = max(previous_max, float(bounds.max()))
    return dict(result, status='not_found_within_scan', first_count=None,
        maximum_bound_in_scan=previous_max)


def review(repo):
    sources = [Path(__file__), Path(__file__).with_name('mgmfrm_foundation_acceptance_review.py'),
               Path(__file__).with_name('mgmfrm_core_sbc_review.py')]
    paths = [repo/'results/workflows'/p/'location/execution.json' for p in
             ('20260926-normalized-location-comparison-01',)]
    paths.append(repo/'results/workflows/20260926-normalized-replication-01/run/execution.json')
    timings = [json.loads(p.read_text())['elapsed_seconds'] for p in paths]
    sizes = [p.with_name('samples.jls').stat().st_size for p in paths]
    seconds, size = statistics.median(timings), statistics.median(sizes)
    rows = []
    for margin in (.025, .05, .075):
        for u, e in ((0., 0.), (.01, .001), (.03, .001), (.04, .001), (.05, .001)):
            r = first_count(margin=margin, unresolved_rate=u, error_rate=e)
            if r['first_count'] is not None:
                n = r['rounded_design']['n']
                r['cost_reference'] = dict(fits=n, serial_days=n*seconds/86400,
                    samples_only_gib=n*size/2**30,
                    note='All planned datasets counted. Linear reference from two pilots; no timing guarantee; excludes reviews/exports; failed-attempt costs may differ. Only for unchanged 4000-draw budget.')
            rows.append(r)
    # Zero observed errors: P(no errors | rate=e)=(1-e)^m. This presumes
    # independent Bernoulli trials with an observable correct event label.
    audits = [dict(events=events, error_cap=.001, alpha=.05,
        zero_error_trials_required=math.ceil(math.log(.05/events)/math.log1p(-.001)))
        for events in (1, 300)]
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    return dict(schema='mgmfrm.foundation_replication_budget.v1', rows=rows,
        cost_inputs=[dict(path=str(p.relative_to(repo)), sha256=digest(p), seconds=t, sample_bytes=b)
                     for p, t, b in zip(paths, timings, sizes)],
        median_pilot_seconds=seconds, median_sample_bytes=size,
        zero_error_audit_reference=audits,
        audit_scope='Known-label Bernoulli reference only; two normal pivots do not supply exact labels for all 300 core events. Audit uncertainty needs its own error allocation.',
        audit_and_acceptance_alpha_note='Separate 5% audit and conditional 5% acceptance bounds do not provide an unconditional 5% guarantee; a union bound would allow up to 10%.',
        source_sha256={p.name:digest(p) for p in sources},
        versions=dict(python=platform.python_version(), numpy=np.__version__, scipy=scipy.__version__),
        comparison_margins=[.025,.05,.075],
        fits_launched=0, adopted_margin=None, scientific_acceptance=False,
        original_raw_cohort_changed=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = review(Path(__file__).resolve().parents[1])
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2, allow_nan=False)
        stream.write('\n')
