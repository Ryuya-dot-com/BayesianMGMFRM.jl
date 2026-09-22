"""Independent stdlib DGP for the one dense 50/5/5/4 raw-prior MGMFRM candidate.

No Julia/package imports, fitting, rejection sampling or scientific acceptance.
Fixed mode holds all 128 coordinates fixed; prior mode draws their joint prior.
Recovery mode redraws N(0,I) persons with one of two declared fixed facets.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import platform
import random

CANDIDATE = "independent_2d_raw_primary_01"
PERSONS = tuple(sorted(f"P{i}" for i in range(1, 51)))
ITEMS = tuple(f"I{i}" for i in range(1, 6))
RATERS = tuple(f"R{i}" for i in range(1, 6))
DIMENSIONS = (0, 0, 1, 1, 1)
RAW_SDS = (1.0,) * 109 + (0.5,) * 9 + (1.0,) * 10
RAW_NAMES = (
    tuple(f"person[{p},dim={d}]" for p in PERSONS for d in (1, 2))
    + tuple(f"raw_rater[{r}]" for r in RATERS[:-1])
    + tuple(f"item[{i}]" for i in ITEMS)
    + tuple(f"raw_log_item_dimension_discrimination[item={i},dim={d+1}]"
            for i, d in zip(ITEMS, DIMENSIONS))
    + tuple(f"raw_log_rater_consistency[{r}]" for r in RATERS[:-1])
    + tuple(f"item_step[item={i},m={m}]" for i in ITEMS for m in (2, 3)))


def check_seed(seed):
    if type(seed) is not int or seed < 0:
        raise ValueError("seed must be an explicit nonnegative integer")


def check_raw(raw):
    if len(raw) != 128 or any(type(x) not in (int, float) or not math.isfinite(x) for x in raw):
        raise ValueError("128 finite real raw coordinates in the declared order are required")


def prior_raw(seed):
    check_seed(seed)
    rng = random.Random(seed)
    return [rng.gauss(0.0, sd) for sd in RAW_SDS]


def recovery_raw(condition, person_seed):
    """R0/R1 share persons for a shared seed; never standardize their sample."""
    if condition not in ('R0', 'R1'):
        raise ValueError('recovery condition must be R0 or R1')
    check_seed(person_seed)
    rng = random.Random(person_seed)
    loading = (.7, 1.3, .7, 1., 1.3) if condition == 'R0' else (.35, .5, .7, 1., 1.3)
    return ([rng.gauss(0., 1.) for _ in range(100)]
            + [-.8, -.4, 0., .4] + [-1., -.5, 0., .5, 1.]
            + [math.log(a) for a in loading] + [-.4, -.2, 0., .2]
            + [-.8, 0.] * 5)


def state(raw):
    check_raw(raw)
    severity = list(raw[100:104]) + [-math.fsum(raw[100:104])]
    log_consistency = list(raw[114:118]) + [-math.fsum(raw[114:118])]
    values = dict(theta=[list(raw[2*j:2*j+2]) for j in range(50)],
                severity=severity, difficulty=list(raw[104:109]),
                loading=[math.exp(x) for x in raw[109:114]],
                log_consistency=log_consistency,
                consistency=[math.exp(x) for x in log_consistency],
                steps=[[0.0, raw[118+2*i], raw[119+2*i],
                        -math.fsum(raw[118+2*i:120+2*i])] for i in range(5)])
    if not all(math.isfinite(x) and x > 0 for x in values['loading'] + values['consistency']):
        raise ValueError('positive transforms exceeded floating-point range')
    return values


def log_probabilities(values, person, item, rater):
    location = (values['loading'][item] * values['theta'][person][DIMENSIONS[item]]
                - values['difficulty'][item] - values['severity'][rater])
    scale = 1.7 * values['consistency'][rater]
    # Sum adjacent logits, independently of the Julia predictor and transforms.
    logits = [0.0]
    for step in values['steps'][item][1:]:
        logits.append(logits[-1] + scale * (location - step))
    if not all(math.isfinite(x) for x in logits):
        raise ValueError("nonfinite response logits; retain the failed attempt, do not clip or redraw")
    shifted = [x - max(logits) for x in logits]
    normalizer = math.log(math.fsum(math.exp(x) for x in shifted))
    return [x - normalizer for x in shifted]


def inverse_cdf(probabilities, uniform):
    if not 0 <= uniform < 1 or not all(math.isfinite(p) and p >= 0 for p in probabilities):
        raise ValueError("invalid probability or uniform variate")
    if len(probabilities) != 4 or not math.isclose(math.fsum(probabilities), 1.0, rel_tol=1e-12, abs_tol=1e-12):
        raise ValueError("four normalized probabilities required")
    cumulative = 0.0
    for score, probability in enumerate(probabilities, 1):
        cumulative += probability
        if uniform < cumulative:
            return score
    return 4  # Rounding of the final cumulative sum only; uniform is strictly <1.


def generate(raw, score_seed):
    check_seed(score_seed)
    values = state(raw)
    rng = random.Random(score_seed)
    observations, logs = [], []
    for p, person in enumerate(PERSONS):
        for i, item in enumerate(ITEMS):
            for r, rater in enumerate(RATERS):
                row = log_probabilities(values, p, i, r)
                logs.append(row)
                observations.append(dict(person=person, item=item, rater=rater,
                    score=inverse_cdf([math.exp(x) for x in row], rng.random())))
    prior = -math.fsum(math.log(sd) + 0.5*math.log(2*math.pi) + 0.5*(x/sd)**2
                       for x, sd in zip(raw, RAW_SDS))
    likelihood = math.fsum(row[observation['score']-1] for row, observation in zip(logs, observations))
    observed = dict(candidate_id=CANDIDATE, category_levels=[1, 2, 3, 4], observations=observations)
    truth = dict(candidate_id=CANDIDATE, raw=list(raw), raw_names=RAW_NAMES,
                 ordered_ids=dict(person=PERSONS, item=ITEMS, rater=RATERS),
                 state=values, log_probabilities=logs, log_prior=prior, log_likelihood=likelihood)
    return observed, truth


def write_json(path, value):
    with Path(path).open('x') as stream:
        json.dump(value, stream, allow_nan=False, indent=2)
        stream.write('\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--mode', choices=('fixed', 'prior', 'recovery'), required=True)
    parser.add_argument('--truth', type=Path)
    parser.add_argument('--truth-seed', type=int)
    parser.add_argument('--person-seed', type=int)
    parser.add_argument('--condition', choices=('R0', 'R1'))
    parser.add_argument('--score-seed', type=int, required=True)
    args = parser.parse_args()
    supplied = (args.truth is not None, args.truth_seed is not None,
                args.person_seed is not None, args.condition is not None)
    expected = dict(fixed=(True,False,False,False), prior=(False,True,False,False),
                    recovery=(False,False,True,True))[args.mode]
    if supplied != expected:
        parser.error('fixed requires --truth; prior --truth-seed; recovery --person-seed and --condition; do not mix modes')
    args.directory.mkdir(parents=True, exist_ok=False)
    receipt = dict(candidate_id=CANDIDATE, mode=args.mode, truth_seed=args.truth_seed,
        score_seed=args.score_seed, python_version=platform.python_version(),
        generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        status='started', response_datasets=0, redraws=0, new_sampler_runs=0,
        scientific_acceptance=False, role='generation only; not a fitted SBC or recovery result')
    if args.mode == 'recovery':
        receipt.update(person_seed=args.person_seed, condition=args.condition,
            person_distribution='independent N(0,I_2); no sample normalization',
            shared_uniforms='Identical score seed reuses response uniforms in the fixed cell order')
    write_json(args.directory/'started.json', receipt)
    try:
        if args.mode == 'fixed':
            payload = args.truth.read_bytes()
            supplied = json.loads(payload)
            if supplied['raw_names'] != list(RAW_NAMES):
                raise ValueError('fixed truth coordinate names/order do not match this candidate')
            raw = supplied['raw']
            receipt['fixed_truth_sha256'] = hashlib.sha256(payload).hexdigest()
        elif args.mode == 'prior':
            if args.truth_seed == args.score_seed:
                raise ValueError('truth and response seeds must differ')
            raw = prior_raw(args.truth_seed)
        else:
            if args.person_seed == args.score_seed:
                raise ValueError('person and response seeds must differ')
            raw = recovery_raw(args.condition, args.person_seed)
        # Preserve truth before response generation, including failed extreme cases.
        write_json(args.directory/'raw-truth.json', dict(raw=raw, raw_names=RAW_NAMES))
        observed, truth = generate(raw, args.score_seed)
        write_json(args.directory/'observed.json', observed)
        write_json(args.directory/'truth.json', truth)
        receipt.update(status='generated', response_datasets=1,
            observed_categories=sorted({r['score'] for r in observed['observations']}))
    except Exception as error:
        receipt.update(status='generation_failed', error=f'{type(error).__name__}: {error}')
        raise
    finally:
        write_json(args.directory/'generation.json', receipt)


if __name__ == '__main__':
    main()
