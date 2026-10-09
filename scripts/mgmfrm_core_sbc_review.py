"""Median and central-interval SBC screens over the full planned dataset roster.

Consumes the existing Julia interval_review output. Exact-binomial references
assume independent joint-prior datasets and exact continuous posteriors. The
finite-MCMC two-MCSE exclusions are sensitivity diagnostics, not error bounds.
This is complementary to ranks, not a test of the entire posterior distribution.
"""
import math
from scipy.stats import binom
from mgmfrm_core_coverage_review import coverage


def _finite(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x)


def classify(row, *, multiplier=2., maximum_relative_mcse=.05):
    """Return truth-below-median and 90% coverage, or None when unresolved."""
    if not _finite(multiplier) or multiplier < 0 or not _finite(maximum_relative_mcse) or maximum_relative_mcse <= 0:
        raise ValueError('Finite nonnegative multiplier and positive precision threshold required')
    truth = row['truth']
    qs = row['precision']['quantiles']
    selected = [[q for q in qs if q['probability'] == p] for p in (.05, .5, .95)]
    if not _finite(truth) or any(len(x) != 1 for x in selected):
        raise ValueError('One finite truth and exactly one of each required quantile expected')
    lo, median, hi = [x[0] for x in selected]
    if any(not _finite(q['estimate']) for q in (lo, median, hi)) or not lo['estimate'] <= median['estimate'] <= hi['estimate']:
        raise ValueError('Finite ordered quantiles required')
    width = hi['estimate'] - lo['estimate']
    def resolved(q):
        se = q['mcse']
        return (width > 0 and _finite(se) and se >= 0
                and se / width <= maximum_relative_mcse
                and abs(truth - q['estimate']) > multiplier * se)
    return dict(below_median=truth < median['estimate'] if resolved(median) else None,
                covered_90=lo['estimate'] < truth < hi['estimate'] if resolved(lo) and resolved(hi) else None)


def summarize(records, *, ids, names, alpha=.05, classification_method='value_mcse'):
    """Four predeclared one-sided screens per quantity; no successful-fit filtering.

    ids is the separately declared planned roster. An absent record becomes an
    unresolved slot. Each supplied record has id, qualified, rows; a rejected fit
    has qualified=False and rows=None. Complete fits need all declared quantities.
    rank_band explicitly selects the experimental order-statistic candidate;
    its rows carry truth and rank_bands. Existing calls retain value_mcse.
"""
    if classification_method == 'value_mcse':
        classify_row = classify
        policy = 'Within two endpoint/median MCSE, unavailable MCSE, or MCSE/90%-width > .05 remains unresolved'
    elif classification_method == 'rank_band':
        from mgmfrm_core_rank_review import classify_rank_bands
        classify_row = classify_rank_bands
        policy = 'Explicit rank bands: resolve only logically forced median/coverage outcomes; unavailable bands remain unbounded; no finite-MCMC guarantee'
    else:
        raise ValueError('classification_method must be value_mcse or rank_band')
    names = list(names); records = list(records); ids = list(ids)
    if (not names or any(not isinstance(n, str) or not n.strip() for n in names)
            or len(set(names)) != len(names)):
        raise ValueError('A nonempty unique quantity list and dataset roster are required')
    if not ids or any(not isinstance(i, str) or not i.strip() for i in ids) or len(set(ids)) != len(ids):
        raise ValueError('Unique nonempty planned dataset IDs required')
    supplied = [r['id'] for r in records]
    if any(i not in ids for i in supplied) or len(set(supplied)) != len(supplied):
        raise ValueError('Unplanned or duplicate supplied dataset IDs')
    by_id = {r['id']: r for r in records}
    records = [by_id.get(i,dict(id=i,qualified=False,rows=None)) for i in ids]
    columns = {n: [] for n in names}
    for record in records:
        if type(record['qualified']) is not bool:
            raise ValueError('Explicit Boolean diagnostic qualification required')
        rows = record['rows']
        if rows is None:
            if record['qualified']:
                raise ValueError('A qualified fit needs its complete review')
            mapped = None
        else:
            mapped = {r['parameter']: r for r in rows}
            if len(mapped) != len(rows) or set(mapped) != set(names):
                raise ValueError('Duplicate, missing or extra review quantities')
        for name in names:
            columns[name].append(classify_row(mapped[name]) if record['qualified'] else
                                 dict(below_median=None, covered_90=None))
    result = []
    for name, values in columns.items():
        tests = {}
        for field, nominal in (('below_median', .5), ('covered_90', .9)):
            events = [v[field] for v in values]
            for direction in ('low', 'high'):
                outcomes = events if direction == 'low' else [None if x is None else not x for x in events]
                reference = nominal if direction == 'low' else 1 - nominal
                report = coverage(outcomes, nominal=reference, alpha=alpha, family_size=4*len(names))
                detected = report.pop('detected_undercoverage')
                tests[f'{field}_{direction}'] = dict(report, detected_departure=detected,
                    counted_event=field if direction == 'low' else f'not_{field}')
        result.append(dict(parameter=name, outcomes=values, tests=tests))
    return dict(planned=len(ids), ids=ids, absent_ids=[i for i in ids if i not in by_id],
                quantity_count=len(names), family_size=4*len(names),
                family_alpha=alpha, rows=result, calibration_verified=False,
                scientific_acceptance=False, new_sampler_runs=0,
                boundary_policy=policy, classification_method=classification_method,
                finite_mcmc_error_control_verified=False)


def rejection_power(n, probability, *, nominal, family_size, alpha=.05):
    """Exact finite sums for the union of both one-sided count tails.

family_size counts ALL one-sided tests, not just this probability's two tails.
Assumes every dataset is resolved; not a model of diagnostic selection.
"""
    if (type(n) is not int or n <= 0 or type(family_size) is not int or family_size < 2
            or not _finite(probability) or not 0 <= probability <= 1
            or not _finite(nominal) or not 0 < nominal < 1
            or not _finite(alpha) or not 0 < alpha < 1):
        raise ValueError('Valid sample size, probabilities and family size required')
    tail_alpha = alpha/family_size
    lo = int(binom.ppf(tail_alpha, n, nominal))
    if binom.cdf(lo, n, nominal) > tail_alpha:
        lo -= 1
    failures = int(binom.ppf(tail_alpha, n, 1-nominal))
    if binom.cdf(failures, n, 1-nominal) > tail_alpha:
        failures -= 1
    hi = n-failures
    return dict(n=n, probability=probability, nominal=nominal, lower_critical=lo,
                upper_critical=hi, power=float(binom.cdf(lo,n,probability)+binom.sf(hi-1,n,probability)),
                null_rejection_probability=float(binom.cdf(lo,n,nominal)+binom.sf(hi-1,n,nominal)))


def unresolved_power_bound(n, probability, *, max_unresolved, nominal, family_size, alpha=.05):
    """Detection lower bound even when unresolved cases depend on true outcomes.

If the complete success count is S and at most m cases are hidden, the largest
completed count is at most S+m and the smallest at least S-m. Thus S<=lo-m or
S>=hi+m forces a robust flag regardless of which cases are unresolved. The
reference is Binomial(n,p), not Binomial(n-m,p). This requires correct resolved
classifications and the stated cap on the NUMBER of unknown outcomes across
repetitions of the entire study, not conditioning on an observed low count. It is
not a stopping rule, permission to omit attempts, or a finite-MCMC guarantee.
"""
    r = rejection_power(n, probability, nominal=nominal, family_size=family_size, alpha=alpha)
    if type(max_unresolved) is not int or not 0 <= max_unresolved <= n:
        raise ValueError('max_unresolved must be an integer between zero and n')
    lo = r['lower_critical']-max_unresolved
    hi = r['upper_critical']+max_unresolved
    return dict(n=n, max_unresolved=max_unresolved, complete_count_lower=lo,
                complete_count_upper=hi, probability=probability, nominal=nominal,
                detection_probability_lower_bound=float(binom.cdf(lo,n,probability)+binom.sf(hi-1,n,probability)),
                unresolved_selection_may_depend_on_outcome=True,
                resolved_classification_error_included=False)


def unresolved_rate_power_bound(n, probability, *, unresolved_rate, direction,
                                nominal, family_size, alpha=.05):
    """One-direction power lower bound under independent dataset outcomes.

Each dataset has event probability p and unresolved probability at most u.
Unresolved status may depend on that dataset's event. Known-success probability
is at least max(p-u,0); success-or-unknown probability is at most min(p+u,1).
The robust high test counts only known successes; the low test counts every
unknown as a success. Binomial tails at these adverse probabilities give sharp
one-direction bounds. Independence of the joint outcomes ACROSS datasets is
essential, but dependence across quantities is allowed. No cap on the realized
number of unknowns is assumed. u must be justified separately, not estimated
by conditioning on a favorable realized count. Resolved classifications must
be correct; finite-MCMC classification error is not included.
"""
    r = rejection_power(n, probability, nominal=nominal, family_size=family_size, alpha=alpha)
    if not _finite(unresolved_rate) or not 0 <= unresolved_rate <= 1 or direction not in ('low', 'high'):
        raise ValueError('Unresolved probability in [0,1] and low/high direction required')
    if direction == 'high':
        adverse = max(probability-unresolved_rate, 0.)
        critical = r['upper_critical']
        bound = binom.sf(critical-1, n, adverse)
    else:
        adverse = min(probability+unresolved_rate, 1.)
        critical = r['lower_critical']
        bound = binom.cdf(critical, n, adverse)
    return dict(n=n, probability=probability, nominal=nominal,
                unresolved_rate_bound=unresolved_rate, direction=direction,
                critical_count=critical, adverse_event_probability=adverse,
                detection_probability_lower_bound=float(bound),
                independent_datasets_required=True,
                cap_on_realized_unknown_count_assumed=False,
                resolved_classification_error_included=False)


def classification_error_power_bound(n, probability, *, unresolved_rate, error_rate,
                                     direction, nominal, family_size, alpha=.05):
    """Conditional one-direction design with unresolved AND misclassified outcomes.

The error bound is P(resolved and wrong), per planned dataset, not conditional
on resolution. It must hold under the null and the specified alternative.
Across-dataset independence is required; within a dataset, missingness and
errors may depend on the ideal event. Shift the null AGAINST rejection by e,
then the alternative AGAINST detection by e+u. A small measured error rate in
normal controls does not establish this assumption for an MGMFRM posterior.
"""
    if (not _finite(nominal) or not 0<nominal<1 or not _finite(error_rate)
            or not 0<=error_rate<min(nominal,1-nominal)
            or not _finite(probability) or not 0<=probability<=1
            or direction not in ('low','high')):
        raise ValueError('Interior nominal, valid event/error probabilities and one direction required')
    signed=error_rate if direction=='high' else -error_rate
    result=unresolved_rate_power_bound(n,min(1.,max(0.,probability-signed)),
        unresolved_rate=unresolved_rate,direction=direction,nominal=nominal+signed,
        family_size=family_size,alpha=alpha)
    return dict(result,probability=probability,nominal=nominal,
        null_reference_probability=nominal+signed,error_rate_bound=error_rate,
        resolved_classification_error_included=True,error_bound_verified=False,
        scientific_acceptance=False)


def classification_error_sensitivity(summary, *, error_rate):
    """Additional conditional p-values; keep original counts/intervals untouched.

Every existing screen is expressed as a lower-tail event. Under a correct
posterior, the probability of that event OR unresolved status is at least
nominal-e. Binomial CDF at nominal-e therefore gives a conservative p-value
only if the unconditional error bound holds and datasets are independent.
No claim about the realized number of mistakes or calibration acceptance.
"""
    if not _finite(error_rate) or not 0<=error_rate<.1:
        raise ValueError('An error probability bound in [0,.1) is required')
    rows=[]
    for row in summary['rows']:
        tests={}
        for key,t in row['tests'].items():
            field,direction=key.rsplit('_',1)
            nominal={'below_median':.5,'covered_90':.9}[field]
            reference=(nominal if direction=='low' else 1-nominal)-error_rate
            p=float(binom.cdf(t['covered']+t['unresolved'],t['planned'],reference))
            tests[key]=dict(null_counted_event_probability=reference,
                one_sided_p_value=p,detected_departure=p<=summary['family_alpha']/summary['family_size'])
        rows.append(dict(parameter=row['parameter'],tests=tests))
    return dict(planned=summary['planned'],family_size=summary['family_size'],
        family_alpha=summary['family_alpha'],error_rate_bound=error_rate,rows=rows,
        error_bound_verified=False,independent_datasets_required=True,
        scientific_acceptance=False)
