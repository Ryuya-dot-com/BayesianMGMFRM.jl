"""Small mathematical oracles for shared effects and learned scales, not a fitter.

The covariance audit concerns a Gaussian latent predictor with fixed loadings.
Full rank is only a necessary design check, not ordinal-model identification.
No production prediction API, posterior draw, or scientific acceptance is added.
"""
from fractions import Fraction as F
from itertools import product
import json
import math

from four_facet_identification_audit import rank

LOG2PI = math.log(2 * math.pi)
TRAITS = ('trait_11', 'trait_22', 'trait_12')


def kernels(a, b, R, C):
    """Rows are (person, task, occasion, rater, criterion); c is also trait ID."""
    p, t, o, r, c = a
    pp, tt, oo, rr, cc = b
    same_person = p == pp
    same_task = same_person and t == tt
    same_response = same_task and o == oo
    rater = F(r == rr) - F(1, R)
    criterion = F(c == cc) - F(1, C)
    return dict(trait_11=int(same_person and c == cc == 0),
                trait_22=int(same_person and c == cc == 1),
                trait_12=int(same_person and c != cc),
                person_task=int(same_task), response=int(same_response),
                rater_response=int(same_response and r == rr),
                rater=rater, rater_criterion=rater * criterion)


def covariance_case(name, P, T, O, R, C, components, expected_rank):
    cells = list(product(range(P), range(T), range(O), range(R), range(C)))
    full, off_diagonal = [], []
    for i, a in enumerate(cells):
        for j in range(i, len(cells)):
            values = kernels(a, cells[j], R, C)
            row = [values[k] for k in components]
            full.append(row)
            if i != j:
                off_diagonal.append(row)
    actual = rank(full)
    if actual != expected_rank:
        raise AssertionError(f'{name}: rank {actual}, expected {expected_rank}')
    return dict(case=name, observations=len(cells), components=list(components),
                rank=actual, nullity=len(components)-actual,
                off_diagonal_rank=rank(off_diagonal))


def covariance_audit():
    base = TRAITS + ('person_task', 'rater_response', 'rater', 'rater_criterion')
    repeated = base + ('response',)
    return [
        covariance_case('crossed_two_criteria', 2, 2, 1, 2, 2, base, 7),
        covariance_case('repeated_responses', 2, 2, 2, 2, 2, repeated, 8),
        covariance_case('one_task_trait_shared_effect_alias', 2, 1, 1, 2, 2, base, 6),
        covariance_case('one_response_per_task_alias', 2, 2, 1, 2, 2, repeated, 7),
        covariance_case('one_rater_response_halo_alias', 2, 2, 2, 1, 2,
                        TRAITS + ('person_task', 'response', 'rater_response'), 5),
        covariance_case('one_criterion_no_within_cell_halo_pair', 2, 2, 1, 2, 1,
                        ('trait_11', 'person_task', 'rater_response'), 3),
        covariance_case('one_task_one_rater_alias', 2, 1, 1, 1, 2,
                        TRAITS + ('person_task', 'rater_response'), 3),
    ]


def positive(value):
    if not math.isfinite(value) or value <= 0:
        raise ValueError('scale must be finite and positive')
    return value


def helmert(n):
    if not isinstance(n, int) or isinstance(n, bool) or n < 1:
        raise ValueError('n must be a positive integer')
    return [[(1 if i <= j else -(j+1) if i == j+1 else 0) /
             math.sqrt((j+1)*(j+2)) for j in range(n-1)] for i in range(n)]


def zero_sum_logpdf(free, tau):
    """Normalized density in the first R-1 coordinates, last = -sum(free)."""
    positive(tau)
    if not all(math.isfinite(x) for x in free):
        raise ValueError('coordinates must be finite')
    q = len(free)
    squared_norm = sum(x*x for x in free) + sum(free)**2
    return .5*math.log(q+1) - q*(math.log(tau) + .5*LOG2PI) - squared_norm/(2*tau*tau)


def hyper_logpdf(log_tau, scale):
    """Half-normal density on tau, transformed to d log(tau); scale is fixed."""
    positive(scale)
    tau = positive(math.exp(log_tau))
    return .5*math.log(2/math.pi) - math.log(scale) - .5*(tau/scale)**2 + log_tau


def scale_audit():
    cases = []
    for R, tau in product((2, 3, 5), (.2, 1., 3.)):
        q, a = R-1, 1.3
        z = [.2*(j+1)-.3 for j in range(q)]
        s = [tau*sum(h*v for h, v in zip(row, z)) for row in helmert(R)]
        free, y = s[:-1], math.log(tau)
        log_jacobian = q*y - .5*math.log(R)
        centered = zero_sum_logpdf(free, tau) + hyper_logpdf(y, a)
        noncentered = -.5*(q*LOG2PI + sum(v*v for v in z)) + hyper_logpdf(y, a)
        error = abs(centered + log_jacobian - noncentered)
        step = 1e-5
        target = lambda v: zero_sum_logpdf(free, math.exp(v)) + hyper_logpdf(v, a)
        derivative = (target(y+step)-target(y-step))/(2*step)
        expected = -q + sum(v*v for v in s)/(tau*tau) + 1 - (tau/a)**2
        derivative_error = abs(derivative-expected)
        if error > 1e-12 or derivative_error > 2e-8:
            raise AssertionError('centered/noncentered scale density mismatch')
        cases.append(dict(raters=R, kernel_sd=tau, logdensity_error=error,
                          logscale_derivative_error=derivative_error))
    return cases


def logmeanexp(values):
    maximum = max(values)
    return maximum + math.log(sum(math.exp(v-maximum) for v in values)/len(values))


def score_oracle(loglik):
    """Equal-weight JOINT latent draws, already appropriate to the target.

    This demonstrates scoring order only; it does not validate a fitted/CV target
    or generate/integrate unseen effects for a production fit.
    """
    if not loglik or not loglik[0] or any(len(row) != len(loglik[0]) for row in loglik):
        raise ValueError('nonempty rectangular draws by observations are required')
    if not all(math.isfinite(x) for row in loglik for x in row):
        raise ValueError('log likelihoods must be finite')
    return dict(joint=logmeanexp([sum(row) for row in loglik]),
                sum_marginal=sum(logmeanexp(column) for column in zip(*loglik)))


def normal_expectation(function, intervals=2048):
    """Deterministic Simpson oracle on [-9, 9]; omitted normal mass < 3e-19."""
    if not isinstance(intervals, int) or intervals < 2 or intervals % 2:
        raise ValueError('an even positive interval count is required')
    step = 18 / intervals
    terms = []
    for i in range(intervals+1):
        x = -9 + i*step
        weight = 1 if i in (0, intervals) else 4 if i % 2 else 2
        terms.append(weight * math.exp(-.5*x*x)/math.sqrt(2*math.pi) * function(x))
    return step/3 * math.fsum(terms)


def audit():
    mixture = score_oracle([[math.log(p)]*2 for p in (.1, .9)])
    p11 = normal_expectation(lambda z: (1/(1+math.exp(-z)))**2)
    finer = normal_expectation(lambda z: (1/(1+math.exp(-z)))**2, 4096)
    R = 3
    return dict(schema='mgmfrm.shared_effect_hierarchy_audit.v1',
                covariance_arithmetic='exact_rational', covariance_cases=covariance_audit(),
                scale_cases=scale_audit(),
                prediction_oracles=dict(two_point_shared_probability=mixture,
                    gaussian_shared_effect=dict(sd=1, p11=p11, product_of_marginals=.25,
                                                quadrature_refinement_error=abs(p11-finer))),
                population_completion_example=dict(raters=R, kernel_variance=1,
                    old_centered_variance=(R-1)/R, naively_augmented_variance=R/(R+1),
                    independent_panel_mean_variance=1/R,
                    new_relative_variance=1+1/R, two_new_relative_covariance=1/R),
                posterior_fits=0, production_model_implemented=False,
                ordinal_identification_established=False, scientific_acceptance=False)


if __name__ == '__main__':
    print(json.dumps(audit(), indent=2))
