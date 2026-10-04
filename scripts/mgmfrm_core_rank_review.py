"""Experimental order-statistic boundaries; existing SBC defaults are unchanged."""
import math
from functools import cache
from scipy.stats import binom,norm
from mgmfrm_core_sbc_review import _finite


@cache
def _iid_indices(n,p,multiplier):
    tail=float(norm.sf(multiplier))
    lower=int(binom.ppf(tail,n,p))
    if binom.cdf(lower,n,p)<=tail:lower+=1
    upper=int(binom.isf(tail,n,p))+1
    if binom.sf(upper-2,n,p)<=tail:upper-=1
    return lower,upper


def rank_band_indices(n, probability, *, ess, multiplier=2.):
    """One-based order indices; 0 and n+1 are unbounded sentinels.

The iid band contains the fixed continuous population quantile with at least
1-2*Phi(-multiplier) probability for independent draws from the target. Widen
using floor(min(n, quantile ESS)), with outward integer rounding. Always include
the original iid band, even if ESS is data-dependent. ESS substitution does NOT
give a finite-MCMC coverage guarantee. Missing/insufficient ESS yields the
entire real line. No truth, value-space width, or relative-MCSE cutoff is used.
"""
    if (type(n) is not int or n<=0 or not _finite(probability) or not 0<probability<1
            or not _finite(multiplier) or multiplier<=0 or not 0<float(norm.sf(multiplier))<.5):
        raise ValueError('Positive draw count, interior probability and representable positive multiplier required')
    if isinstance(ess,bool):raise ValueError('ESS must not be Boolean')
    base_lo,base_hi=_iid_indices(n,probability,multiplier)
    available=_finite(ess) and ess>=1
    m=math.floor(min(n,ess)) if available else 0
    if available:
        lo,hi=_iid_indices(m,probability,multiplier)
        # Integer arithmetic rounds outward without floating-point rank drift.
        lo=min(base_lo,n*lo//m)
        hi=min(n+1,max(base_hi,(n*hi+m-1)//m))
    else:lo,hi=0,n+1
    return dict(probability=probability,lower_index=lo,upper_index=hi,total_draws=n,
                effective_count=m,ess=ess if _finite(ess) else None,multiplier=multiplier,
                iid_lower_index=base_lo,iid_upper_index=base_hi,
                ess_available=available,finite_mcmc_coverage_verified=False)


def rank_bands(draws, *, quantile_ess, multiplier=2.):
    """Materialize the three bands from all draws and named quantile ESS values."""
    x=list(draws)
    if not x or not all(_finite(v) for v in x) or set(quantile_ess)!={.05,.5,.95}:
        raise ValueError('Finite nonempty draws and exactly three named quantile ESS values required')
    x.sort();n=len(x)
    result=[]
    for p in (.05,.5,.95):
        band=rank_band_indices(n,p,ess=quantile_ess[p],multiplier=multiplier)
        lo,hi=band['lower_index'],band['upper_index']
        result.append(dict(band,lower=None if lo==0 else x[lo-1],
                           upper=None if hi==n+1 else x[hi-1]))
    return result


def classify_rank_bands(row):
    """Conservative median/coverage logic; null endpoints mean unbounded ends.

Coverage is false if either endpoint proves exclusion, true only if both prove
inclusion. Ties at a boundary stay unresolved. This is a candidate sensitivity
classifier, not a declaration that correlated samples are independently drawn.
"""
    truth=row['truth'];bands=row['rank_bands']
    if not _finite(truth) or len(bands)!=3 or {b['probability'] for b in bands}!={.05,.5,.95}:
        raise ValueError('Finite truth and exactly three named rank bands required')
    checked={}
    for band in bands:
        lo,hi=band['lower'],band['upper']
        if ((lo is not None and not _finite(lo)) or (hi is not None and not _finite(hi))
                or (lo is not None and hi is not None and lo>hi)):
            raise ValueError('Finite ordered endpoints or explicit unbounded ends required')
        checked[band['probability']]=(-math.inf if lo is None else lo,math.inf if hi is None else hi)
    lower,median,upper=(checked[p] for p in (.05,.5,.95))
    if lower[0]>median[1] or median[0]>upper[1] or lower[0]>upper[1]:
        raise ValueError('Bands exclude every ordered quantile triple')
    below=True if truth<median[0] else False if truth>median[1] else None
    covered=(False if truth<lower[0] or truth>upper[1] else
             True if truth>lower[1] and truth<upper[0] else None)
    return dict(below_median=below,covered_90=covered)
