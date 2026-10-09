"""One-dimensional item-difficulty checks for the dense raw-prior core candidate.

This is an analysis helper, not a new sampler. Integrating out one difficulty
conditional on saved values of the other coordinates gives a conditional CDF.
Averaging it still requires representative posterior draws of those coordinates.
QUADPACK error estimates and MCMC error are separate, neither is a proof of
calibration. NumPy/SciPy are analysis dependencies, not Julia package dependencies.
"""
import math

import numpy as np
from scipy.integrate import quad
from scipy.optimize import brentq
from scipy.special import logsumexp

import mgmfrm_core_reference as D


class ItemConditional:
    def __init__(self, offsets, slopes, categories, prior_sd=1.):
        self.offsets = np.asarray(offsets, dtype=float)
        self.slopes = np.asarray(slopes, dtype=float)
        self.categories = np.asarray(categories)
        if (self.offsets.ndim != 2 or self.offsets.shape[1] != 4
                or self.slopes.shape != self.offsets.shape
                or self.categories.shape != (len(self.offsets),)
                or not np.issubdtype(self.categories.dtype, np.integer)
                or np.any((self.categories < 0) | (self.categories > 3))
                or not np.all(np.isfinite(self.offsets)) or not np.all(np.isfinite(self.slopes))
                or not math.isfinite(prior_sd) or prior_sd <= 0):
            raise ValueError('Finite four-category logits, integer outcomes and positive prior SD required')
        self.prior_sd = float(prior_sd)
        self.rows = np.arange(len(self.offsets))

    def log_density(self, b):
        logits = self.offsets + self.slopes*b
        return -0.5*(b/self.prior_sd)**2 + float(np.sum(
            logits[self.rows, self.categories]-logsumexp(logits, axis=1)))

    def score(self, b):
        logits = self.offsets + self.slopes*b
        probabilities = np.exp(logits-logsumexp(logits, axis=1, keepdims=True))
        return -b/self.prior_sd**2 + float(np.sum(
            self.slopes[self.rows, self.categories]-np.sum(probabilities*self.slopes, axis=1)))

    def cdf(self, threshold, *, epsabs=1e-10, epsrel=1e-8):
        if not math.isfinite(threshold) or min(epsabs, epsrel) <= 0:
            raise ValueError('Finite threshold and positive tolerances required')
        # Strict concavity: l''(b) = -1/sd^2 - sum Var(category slope | b) < 0.
        lo, hi = -self.prior_sd, self.prior_sd
        while self.score(lo) < 0:
            lo *= 2
            if not math.isfinite(lo):
                raise ArithmeticError('Could not bracket conditional mode')
        while self.score(hi) > 0:
            hi *= 2
            if not math.isfinite(hi):
                raise ArithmeticError('Could not bracket conditional mode')
        mode = brentq(self.score, lo, hi, xtol=1e-12)
        peak = self.log_density(mode)

        def integral(lower, upper, pivot):
            result = quad(lambda b: math.exp(self.log_density(b)-pivot), lower, upper,
                          epsabs=epsabs, epsrel=epsrel, full_output=1)
            if len(result) != 3:
                raise ArithmeticError(f'Conditional quadrature failed: {result[3]}')
            value, error, _ = result
            if not math.isfinite(value) or value <= 0 or not math.isfinite(error):
                raise ArithmeticError('Conditional quadrature gave no finite positive mass')
            return value, error

        left, le = integral(-np.inf, mode, peak)
        right, re = integral(mode, np.inf, peak)
        normalizer = left+right
        pivot = self.log_density(threshold)
        below = threshold <= mode
        mass, error = integral(-np.inf if below else threshold,
                               threshold if below else np.inf, pivot)
        log_tail = pivot-peak+math.log(mass)-math.log(normalizer)
        if log_tail > 0:
            raise ArithmeticError('Integrated tail probability exceeded one')
        tail = math.exp(log_tail)
        probability = tail if below else -math.expm1(log_tail)
        log_cdf = log_tail if below else math.log(probability)
        estimated_error = tail*(error/mass+(le+re)/normalizer)
        return dict(cdf=probability, log_cdf=log_cdf, mode=mode,
                    log_normalizer=peak+math.log(normalizer),
                    estimated_quadrature_error=estimated_error,
                    underflow=bool(below and tail == 0))


def item_conditional(raw, observations, item):
    """Use actual person/item/rater IDs; the core prior fixes item SD to one."""
    state = D.state(list(map(float, raw)))
    i = D.ITEMS.index(item)
    rows = [r for r in observations if r['item'] == item]
    if len(rows) != 250 or len({(r['person'], r['rater']) for r in rows}) != 250:
        raise ValueError('The dense candidate requires all 50 x 5 item observations')
    p = np.array([D.PERSONS.index(r['person']) for r in rows])
    r = np.array([D.RATERS.index(row['rater']) for row in rows])
    y = np.array([row['score']-1 for row in rows])
    location = state['loading'][i]*np.array(state['theta'])[p, D.DIMENSIONS[i]]-np.array(state['severity'])[r]
    scale = 1.7*np.array(state['consistency'])[r]
    k = np.arange(4)
    step_sum = np.cumsum(state['steps'][i])
    offsets = scale[:, None]*(location[:, None]*k-step_sum)
    slopes = -scale[:, None]*np.broadcast_to(k, offsets.shape)
    return ItemConditional(offsets, slopes, y)
