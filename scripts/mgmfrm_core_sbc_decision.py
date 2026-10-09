"""Read-only decision preparation for the fixed core SBC cohort, never acceptance.

Recompute the existing primary screens from saved records, retain every planned
slot, and expose the assumptions needed to interpret the result. Input hashes
identify a snapshot; they do not replace the collector's cache/provenance checks.
"""
import argparse
import json
import math
from collections import Counter
from pathlib import Path

from scipy.stats import beta
import mgmfrm_core_sbc_plan as P
from mgmfrm_core_sbc_review import _finite, classification_error_power_bound

FIELDS = {'below_median': .5, 'covered_90': .9}
PENDING = {'not_started', 'started_without_completion'}
TERMINAL = {'completed', 'failed'}


def probability_envelope(successes, unresolved, n, *, tail_alpha, error_rate):
    """Conditional bounds for an ideal binary event, with arbitrary missingness.

Let A = resolved AND classified true, B = classified true OR unresolved, and
E = resolved AND wrong. Then P(A)-e <= p <= P(B)+e when P(E)<=e. Invert the
two binomial tails separately, then widen by e. Independent, identically
distributed dataset/classifier outcomes are assumed; no bound on u is needed.
For interim fixed-roster missingness, the envelope contains every completed
roster's interval. This is not a sequential test or an ESS/MCMC guarantee.
"""
    if (any(type(x) is not int for x in (successes, unresolved, n)) or n <= 0
            or min(successes, unresolved) < 0 or successes + unresolved > n
            or not _finite(tail_alpha) or not 0 < tail_alpha < .5
            or not _finite(error_rate) or not 0 <= error_rate < .1):
        raise ValueError('Valid counts, tail alpha and classification-error bound required')
    upper_count = successes + unresolved
    lower = 0. if successes == 0 else float(beta.ppf(tail_alpha, successes, n-successes+1))
    upper = 1. if upper_count == n else float(beta.isf(tail_alpha, upper_count+1, n-upper_count))
    return [max(0., lower-error_rate), min(1., upper+error_rate)]


def design_limits(plan):
    """Design illustrations, not acceptance margins or an audit execution plan."""
    n = plan['planned_datasets']
    alpha = plan['family_alpha']
    e = plan['power_assumptions']['error_rate']
    u = plan['power_assumptions']['unresolved_rate']
    family = plan['family_size']
    critical = {}
    illustrations = []
    for field, nominal in FIELDS.items():
        critical[field] = {direction: classification_error_power_bound(
            n, nominal, unresolved_rate=u, error_rate=e, direction=direction,
            nominal=nominal, family_size=family, alpha=alpha)['critical_count']
            for direction in ('low', 'high')}
        successes = round(n*nominal)
        illustrations.append(dict(field=field, nominal=nominal, successes=successes,
            unresolved=0, n=n, conditional_probability_envelope=probability_envelope(
                successes, 0, n, tail_alpha=alpha/family, error_rate=e)))
    # Zero OBSERVED errors requires an oracle for every planned audit case.
    # These are per-regime, per-event calculations, not n*150 independent trials.
    audits = [dict(simultaneous_events=m,
        zero_error_one_sided_upper_at_n=-math.expm1(math.log(alpha/m)/n),
        minimum_n_if_zero_errors=math.ceil(math.log(alpha/m)/math.log1p(-e)))
        for m in (1, len(FIELDS)*len(plan['names']))]
    return dict(critical_counts=critical, reference_power=P.reference_power(n, error_rate=e, unresolved_rate=u),
        hypothetical_nominal_counts=illustrations, oracle_error_audit_illustrations=audits,
        illustrations_are_acceptance_margins=False, new_audit_authorized=False)


def assess(plan, snapshot):
    # Reuse the declared collector: this module does not change classifications.
    checked = P.collect(plan, snapshot['records'])
    if any(P.identity(snapshot[k]) != P.identity(v) for k, v in checked.items()):
        raise ValueError('Saved primary summary differs from its records or setting')
    ids = [j['id'] for j in plan['jobs']]
    ledger = snapshot['ledger']
    if [r['id'] for r in ledger] != ids:
        raise ValueError('Complete ordered ledger required, including failed and absent IDs')
    records = {r['id']: r for r in snapshot['records']}
    for row in ledger:
        status = row['status']
        record = records.get(row['id'])
        if status not in PENDING | TERMINAL | {'evidence_unresolved'}:
            raise ValueError('Unknown ledger status')
        if status in PENDING:
            if record is not None or row.get('qualified', False) is not False:
                raise ValueError('An unfinished slot cannot supply an evaluated record')
        elif (record is None or type(row.get('qualified')) is not bool
                or row['qualified'] != record['qualified']
                or (status != 'completed' and record['qualified'])):
            raise ValueError('Ledger qualification or terminal record is inconsistent')

    counts = dict(Counter(r['status'] for r in ledger))
    limits = design_limits(plan)
    nominal = checked['nominal_reference']
    adjusted = checked['error_rate_sensitivity']
    reasons = Counter()
    for row in ledger:
        if row['status'] != 'completed':
            reasons[row['status']] += 1
        elif not row['qualified']:
            reasons['diagnostics_unqualified'] += 1
    all_unknown = sum(reasons.values())
    rows = []
    flags = []
    for row, adjusted_row in zip(nominal['rows'], adjusted['rows']):
        events = {}
        for field, expected in FIELDS.items():
            count = row['tests'][field+'_low']
            event_reasons = dict(reasons, classification_unresolved=count['unresolved']-all_unknown)
            if event_reasons['classification_unresolved'] < 0:
                raise ValueError('Unresolved accounting contradicts the ledger')
            tests = {direction: adjusted_row['tests'][field+'_'+direction]
                     for direction in ('low', 'high')}
            for direction, test in tests.items():
                if test['detected_departure']:
                    flags.append(dict(parameter=row['parameter'], field=field, direction=direction,
                                      conditional_p_value=test['one_sided_p_value']))
            events[field] = dict(nominal=expected, planned=count['planned'],
                true=count['covered'], false=count['not_covered'], unresolved=count['unresolved'],
                unresolved_reasons=event_reasons, full_denominator_bounds=count['full_denominator_bounds'],
                conditional_probability_envelope=probability_envelope(
                    count['covered'], count['unresolved'], count['planned'],
                    tail_alpha=plan['family_alpha']/plan['family_size'],
                    error_rate=plan['power_assumptions']['error_rate']),
                conditional_screens=tests)
        rows.append(dict(parameter=row['parameter'], events=events))
    pending = sum(counts.get(s, 0) for s in PENDING)
    evidence_unresolved = counts.get('evidence_unresolved', 0)
    final = pending == 0 and evidence_unresolved == 0
    total_resolved = sum(e['true']+e['false'] for r in rows for e in r['events'].values())
    if not final:
        state = 'incomplete'
    elif total_resolved == 0:
        state = 'no_resolved_outcomes'
    else:
        state = 'conditional_departure_detected' if flags else 'conditional_no_departure_detected'
    holds = []
    if pending: holds.append('planned_slots_unfinished')
    if evidence_unresolved: holds.append('source_evidence_unresolved')
    holds += ['mgmfrm_classification_error_bound_unverified',
              'mgmfrm_unresolved_rate_power_assumption_unverified',
              'positive_acceptance_margins_not_defined_by_this_plan']
    return dict(schema='core.sbc.decision_preparation.v1', plan_identity=checked['plan_identity'],
        candidate_id=plan['candidate_id'], planned=len(ids), status_counts=counts,
        diagnostics_qualified=sum(r.get('qualified') is True for r in ledger),
        unstarted_ids=[r['id'] for r in ledger if r['status']=='not_started'],
        failed_ids=[r['id'] for r in ledger if r['status']=='failed'],
        screen_state=state, fixed_roster_accounted=final,
        interim_results_are_descriptive=not final, conditional_flags=flags,
        hold_reasons=holds, rows=rows, design_limits=limits,
        scientific_decision='hold', scientific_acceptance=False,
        calibration_verified=False, bounds_verified_for_mgmfrm=False,
        acceptance_margins=None, independent_scientific_review=False,
        assessment_scope='Primary k=2 snapshot arithmetic; no cache replay, k=4 reclassification, or source provenance certification',
        error_bound_required_for='Type-I error and probability envelopes; also power under each alternative',
        unresolved_bound_required_for='Reference power, not conservative Type-I error or probability envelopes',
        dataset_assumption='Independent joint-prior datasets with the declared common inference/classifier procedure; no pooling across quantities',
        stopping_policy='Fixed roster only; interim flags do not authorize stopping, retuning or replacing attempts',
        new_sampler_runs=0)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('plan', type=Path)
    parser.add_argument('snapshot', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = assess(json.loads(args.plan.read_text()), json.loads(args.snapshot.read_text()))
    result['inputs_sha256'] = {str(p): P.digest(p) for p in (args.plan, args.snapshot)}
    sources = [Path(__file__).resolve().parent/f'mgmfrm_core_{name}.py'
               for name in ('sbc_decision', 'sbc_plan', 'sbc_review', 'rank_review', 'coverage_review')]
    result['review_source_sha256'] = {str(p): P.digest(p) for p in sources}
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2, allow_nan=False)
        stream.write('\n')
