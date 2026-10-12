"""Known-continuous-posterior audit of the existing finite-draw SBC classifier."""
import math
from mgmfrm_core_sbc_review import classify, _finite
from mgmfrm_core_rank_review import classify_rank_bands


def classification_error_mass(quantiles, *, reference_quantiles, cdf,
                              multiplier=2., maximum_relative_mcse=.05):
    """Integrate classifier outcomes under a known continuous reference CDF.

reference_quantiles maps .05, .5, .95 to exact target quantiles. Piecewise
classification is evaluated by the production helper; the oracle uses the
reference quantiles. CDF differences integrate over an independent generating
truth conditional on these fixed estimated quantiles/MCSE. This audits a
known-answer control, not a bound for an unknown MGMFRM posterior.
"""
    row=dict(truth=0.,precision=dict(quantiles=list(quantiles)))
    # Reuse all validation and every classification rule.
    classify(row,multiplier=multiplier,maximum_relative_mcse=maximum_relative_mcse)
    selected={q['probability']:q for q in row['precision']['quantiles'] if q['probability'] in (.05,.5,.95)}
    cuts=set()
    for q in selected.values():
        cuts.add(q['estimate'])
        if _finite(q['mcse']) and q['mcse']>=0:
            cuts.update((q['estimate']-multiplier*q['mcse'],q['estimate']+multiplier*q['mcse']))
    return _integrate_classifier(cuts,reference_quantiles,cdf,lambda truth:classify(
        dict(row,truth=truth),multiplier=multiplier,maximum_relative_mcse=maximum_relative_mcse))


def rank_classification_error_mass(bands, *, reference_quantiles, cdf):
    """Known-answer audit of the rank-band candidate on the same target CDF."""
    row=dict(truth=0.,rank_bands=list(bands))
    classify_rank_bands(row)
    cuts={b[side] for b in row['rank_bands'] for side in ('lower','upper') if b[side] is not None}
    return _integrate_classifier(cuts,reference_quantiles,cdf,
        lambda truth:classify_rank_bands(dict(row,truth=truth)))


def _integrate_classifier(cuts,reference_quantiles,cdf,classify_at):
    probabilities=(.05,.5,.95)
    if set(reference_quantiles)!=set(probabilities):
        raise ValueError('Exactly the three named reference quantiles required')
    reference=[reference_quantiles[p] for p in probabilities]
    if not all(_finite(q) for q in reference) or not reference[0]<reference[1]<reference[2]:
        raise ValueError('Finite strictly ordered reference quantiles required')
    cuts=set(cuts)|set(reference)
    if not all(_finite(q) for q in cuts):raise ValueError('Finite boundary locations required')
    cuts=sorted(cuts)
    cdfs=[cdf(q) for q in cuts]
    if (not all(_finite(p) and 0<=p<=1 for p in cdfs)
            or any(a>b for a,b in zip(cdfs,cdfs[1:]))):
        raise ValueError('A monotone continuous reference CDF in [0,1] is required')
    for q,p in zip(reference,probabilities):
        if abs(cdfs[cuts.index(q)]-p)>1e-10:
            raise ValueError('Reference quantiles do not match the CDF')
    result={field:dict(true_positive=0.,true_negative=0.,false_positive=0.,false_negative=0.,
                       unresolved=0.) for field in ('below_median','covered_90')}
    edges=[-math.inf,*cuts,math.inf]
    cdfs=[0.,*cdfs,1.]
    for i,(lo,hi) in enumerate(zip(edges,edges[1:])):
        mass=cdfs[i+1]-cdfs[i]
        if mass==0:continue
        # One floating-point step is not enough: subtracting the estimated
        # quantile can round the distance back onto its guard boundary.
        point=(hi-max(1.,abs(hi)) if lo==-math.inf else
               lo+max(1.,abs(lo)) if hi==math.inf else lo/2+hi/2)
        if not _finite(point) or not lo<point<hi:
            raise ValueError('Boundary spacing is too small for floating-point integration')
        observed=classify_at(point)
        oracle=dict(below_median=point<reference[1],covered_90=reference[0]<point<reference[2])
        for field,decision in observed.items():
            outcome=('unresolved' if decision is None else
                     'true_positive' if decision and oracle[field] else
                     'true_negative' if not decision and not oracle[field] else
                     'false_positive' if decision else 'false_negative')
            result[field][outcome]+=mass
    for field,values in result.items():
        values['resolved_wrong']=values['false_positive']+values['false_negative']
        values['known_true']=values['true_positive']+values['false_positive']
        values['known_false']=values['true_negative']+values['false_negative']
        values['resolved_correct']=values['true_positive']+values['true_negative']
    return result
