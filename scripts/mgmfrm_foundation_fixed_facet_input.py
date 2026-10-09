"""Export one engineering R0/R1 pair without legacy raw-prior target metadata."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import platform
import re

import mgmfrm_core_reference as reference


def pair(person_seed, score_seed):
    reference.check_seed(person_seed)
    reference.check_seed(score_seed)
    if person_seed == score_seed:
        raise ValueError('Person and response seeds must differ')
    rows = []
    for condition in ('R0', 'R1'):
        raw = reference.recovery_raw(condition, person_seed)
        observed, truth = reference.generate(raw, score_seed)
        rows.append(dict(schema='mgmfrm.foundation_fixed_facet_input.v1',
            scope='engineering_fixed_facet_rehearsal', condition=condition,
            evaluation_credit=0, scientific_acceptance=False,
            person_seed=person_seed, score_seed=score_seed,
            generating_distribution='fixed_facets_random_N(0,I)_persons_no_sample_standardization',
            generator_sha256=hashlib.sha256(Path(reference.__file__).read_bytes()).hexdigest(),
            producer_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            python_version=platform.python_version(), ordered_ids=truth['ordered_ids'],
            raw_truth=raw, raw_names=truth['raw_names'], observations=observed['observations'],
            probabilities=[[math.exp(x) for x in row] for row in truth['log_probabilities']],
            scales=dict(person_sd=1., item_sd=1., log_discrimination_sd=.5,
                        rater_sd=math.sqrt(2), log_consistency_sd=math.sqrt(2)/2, step_sd=math.sqrt(2))))
    assert rows[0]['raw_truth'][:109] == rows[1]['raw_truth'][:109]
    assert rows[0]['raw_truth'][111:] == rows[1]['raw_truth'][111:]
    d2 = lambda x: [r for r in x['observations'] if r['item'] in ('I3', 'I4', 'I5')]
    assert d2(rows[0]) == d2(rows[1]) and len(d2(rows[0])) == 750
    return rows


def assessment_pair(assessment_id, block, person_seed, score_seed):
    """Fresh prospective pair; never relabel or reuse an engineering panel."""
    if (not isinstance(assessment_id, str) or
            not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]*', assessment_id) or
            isinstance(block, bool) or not isinstance(block, int) or block < 1):
        raise ValueError('Assessment ID and positive block number required')
    rows = pair(person_seed, score_seed)
    for row in rows:
        row.update(schema='mgmfrm.foundation_fixed_facet_assessment_input.v1',
                   scope='prospective_fixed_facet_assessment', evaluation_credit=1,
                   assessment_id=assessment_id, block=block)
    return rows


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--person-seed', type=int, required=True)
    parser.add_argument('--score-seed', type=int, required=True)
    args = parser.parse_args()
    args.directory.mkdir()  # Never replace a generated pair.
    for payload in pair(args.person_seed, args.score_seed):
        reference.write_json(args.directory/f"{payload['condition']}.json", payload)
    print('Saved one engineering pair; evaluation credit 0, posterior fits 0.')
