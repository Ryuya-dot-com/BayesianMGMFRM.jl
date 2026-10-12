"""Fixed-cohort coverage accounting; unresolved panels stay in the denominator.

One Boolean per independently generated panel and fixed parameter, or None.
These binomial calculations do not apply to correlated persons within a panel.
"""
import math
from numbers import Real
from scipy.stats import beta, binom


def _settings(nominal, alpha, family_size):
    if (not isinstance(family_size, int) or isinstance(family_size, bool) or family_size < 1
            or any(not isinstance(x, Real) or isinstance(x, bool) or not math.isfinite(x)
                   or not 0 < x < 1 for x in (nominal, alpha))):
        raise ValueError('Interior probabilities and a positive integer family size required')


def coverage(values, *, nominal=.9, alpha=.05, family_size=1):
    """Exact binomial reference and union over every unresolved completion.

    The conservative undercoverage flag uses the largest possible covered count.
    Non-rejection is not acceptance. Filtering to successful fits is not allowed.
    """
    _settings(nominal, alpha, family_size)
    values = list(values)
    if not values or any(x is not None and type(x) is not bool for x in values):
        raise ValueError('A nonempty planned roster of Boolean or None values is required')
    n = len(values); s = values.count(True); missing = values.count(None)
    upper_s = s + missing; threshold = alpha / family_size
    def envelope(a):
        return [0. if s == 0 else float(beta.ppf(a / 2, s, n - s + 1)),
                1. if upper_s == n else float(beta.ppf(1 - a / 2, upper_s + 1, n - upper_s))]
    p_values = [float(binom.cdf(s, n, nominal)), float(binom.cdf(upper_s, n, nominal))]
    estimate = s / n if missing == 0 else None
    return dict(planned=n, covered=s, not_covered=n-s-missing, unresolved=missing,
                estimate=estimate, full_denominator_bounds=[s/n, upper_s/n],
                plug_in_mcse=math.sqrt(estimate*(1-estimate)/n) if estimate is not None else None,
                zero_empirical_variance=missing == 0 and s in (0, n),
                pointwise_exact_interval_envelope=envelope(alpha),
                family_exact_interval_envelope=envelope(threshold),
                one_sided_p_value_bounds=p_values, per_parameter_alpha=threshold,
                detected_undercoverage=p_values[1] <= threshold,
                scientific_acceptance=False)


def design(*, nominal=.9, alternative=.7, power=.8, alpha=.05, family_size=5):
    """Smallest fixed n meeting the declared per-parameter exact-test power.

    Requires all outcomes resolved; correlated parameters do not increase n.
    Bonferroni controls the union of false flags without parameter independence.
    """
    _settings(nominal, alpha, family_size)
    if any(not isinstance(x, Real) or isinstance(x, bool) or not math.isfinite(x)
           for x in (alternative, power)) or not 0 < alternative < nominal or not 0 < power < 1:
        raise ValueError('A smaller positive alternative and interior power required')
    n = 0; history = []
    while True:
        n += 1
        critical = int(binom.ppf(alpha/family_size, n, nominal))
        if binom.cdf(critical, n, nominal) > alpha/family_size:
            critical -= 1
        attained = float(binom.cdf(critical, n, alternative))
        history.append(dict(n=n, critical_covered=critical,
                            null_rejection_probability=float(binom.cdf(critical, n, nominal)), power=attained))
        if attained >= power:
            return dict(n=n, nominal=nominal, alternative=alternative, requested_power=power,
                        family_alpha=alpha, family_size=family_size, per_parameter_alpha=alpha/family_size,
                        **{k:v for k,v in history[-1].items() if k != 'n'},
                        nominal_mcse=math.sqrt(nominal*(1-nominal)/n), worst_case_mcse=.5/math.sqrt(n),
                        all_smaller_n=history[:-1], scientific_acceptance=False)
