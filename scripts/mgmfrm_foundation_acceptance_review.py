"""Deterministic design worksheet for the 2D fixed-Q foundation; no fits.

Usage: python3 scripts/mgmfrm_foundation_acceptance_review.py NEW_OUTPUT.json
Reuses prior-response case C and existing error/missingness count bounds.
Margins and error-rate assumptions are sensitivity settings, not an adopted
protocol. Outputs count thresholds, NOT a verdict on existing samples.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import platform

import scipy
from scipy.stats import norm, studentized_range
from mgmfrm_prior_response_review import cases
from mgmfrm_core_sbc_review import classification_error_power_bound


def acceptance_design(n, *, quantities, margin, unresolved_rate, error_rate, alpha=.05):
    """Conditional IUT: all median/coverage probabilities inside open margins.

K is resolved true, U unresolved, out of ALL n planned datasets. Accept each
event only if K >= min_true AND K+U <= max_true_or_unknown. Each component
uses alpha, so global false acceptance <= alpha without independence across
quantities. Joint power uses a union bound, not independent-test multiplication.
Error bound P(resolved AND wrong) must hold under the composite null as well
as the nominal alternative; independent dataset outcomes are required.
"""
    if (type(quantities) is not int or quantities < 1
            or type(margin) not in (int, float) or not 0 < margin < .1
            or type(alpha) not in (int, float) or not 0 < alpha < .5):
        raise ValueError('Positive quantity count, margin in (0,.1), alpha in (0,.5) required')
    rows = []
    failure_sum = 0.
    for nominal in (.5, .9):
        sides = []
        for direction, boundary in (('high', nominal-margin), ('low', nominal+margin)):
            # Existing helper allocates alpha/family_size to each tail. Calling
            # with two tails and 2*alpha gives exactly alpha per IUT component;
            # its two-sided union is not used as a component test here.
            sides.append(classification_error_power_bound(n, nominal,
                unresolved_rate=unresolved_rate, error_rate=error_rate,
                direction=direction, nominal=boundary, family_size=2, alpha=2*alpha))
        failure_sum += sum(1-s['detection_probability_lower_bound'] for s in sides)
        rows.append(dict(nominal=nominal, lower_boundary=nominal-margin,
            upper_boundary=nominal+margin, min_true=sides[0]['critical_count'],
            max_true_or_unknown=sides[1]['critical_count'], components=sides))
    return dict(n=n, quantities=quantities, event_count=2*quantities,
        margin=margin, unresolved_rate_bound=unresolved_rate, error_rate_bound=error_rate,
        component_alpha=alpha, global_false_acceptance_bound=alpha,
        nominal_joint_acceptance_probability_lower_bound=max(0., 1-quantities*failure_sum),
        count_region_nonempty_at_zero_unknowns=all(r['min_true'] <= r['max_true_or_unknown'] for r in rows),
        nominal_worst_mechanism_separated=margin > unresolved_rate+2*error_rate,
        events=rows, assumptions_verified=False, scientific_acceptance=False)


def scale_review():
    """Exact Gaussian marginal/contrast widths; whole-block ranges use quadrature."""
    candidate = next(c for c in cases() if c['id'] == 'C')
    s, z = candidate['scales'], norm.ppf(.975)
    rows = []
    for key, block_size, constrained, ratio in (
            ('person_sd', 50, False, False), ('item_sd', 5, False, False),
            ('log_discrimination_sd', 2, False, True),
            ('rater_sd', 5, True, False), ('log_consistency_sd', 5, True, True),
            ('step_sd', 3, True, False)):
        tau = float(s[key])
        marginal = tau*math.sqrt((block_size-1)/block_size) if constrained else tau
        halfwidth = math.sqrt(2)*tau*z
        range95 = tau*studentized_range.ppf(.95, block_size, math.inf)
        rows.append(dict(scale=key, kernel_sd=tau, marginal_sd=marginal,
            marginal_95=[-z*marginal, z*marginal], pairwise_95=[-halfwidth, halfwidth],
            ratio_95=[math.exp(-halfwidth), math.exp(halfwidth)] if ratio else None,
            block_size=block_size, all_pairs_absolute_bound_95=float(range95),
            all_pairs_probability_at_pairwise_bound=float(studentized_range.cdf(
                halfwidth/tau, block_size, math.inf))))
    return dict(candidate=candidate, widths=rows,
        block_scope='Persons: one dimension; loading: I1/I2 in D1; steps: one item. '
                    'No simultaneous claim across different blocks.',
        scientific_scale_choice=False)


def review():
    grid = [acceptance_design(n, quantities=150, margin=margin,
            unresolved_rate=u, error_rate=e)
        for margin in (.025, .05, .075)
        for u, e in ((0., 0.), (.01, .001), (.05, .001))
        for n in (274, 1000, 2000, 4000, 8000)]
    sources = [Path(__file__), Path(__file__).with_name('mgmfrm_prior_response_review.py'),
               Path(__file__).with_name('mgmfrm_core_sbc_review.py')]
    return dict(schema='mgmfrm.foundation_acceptance_worksheet.v1',
        design=dict(persons=50, items=5, raters=5, categories=4, dimensions=2,
            item_dimensions=[1, 1, 2, 2, 2], complete_cross=True, likelihood_scale=1.7,
            latent_correlation='identity', estimated_loadings=True),
        scales=scale_review(), conditional_acceptance_grid=grid,
        quantity_scope='Existing 150 scalar functions; a new prior needs a new cohort. '
                       'Count-based planning only; no per-quantity result is assessed.',
        versions=dict(python=platform.python_version(), scipy=scipy.__version__),
        source_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
        posterior_fits=0, prior_simulations=0, original_cohort_changed=False,
        scientific_acceptance=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = review()
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2, allow_nan=False)
        stream.write('\n')
