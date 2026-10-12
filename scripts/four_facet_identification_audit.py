"""Exact small-design checks for the proposed four-facet model, not a fitter.

All levels are declared before subsetting rows (as they must be for a training
fold audit). Integer adjacent-logit designs are ranked with rational arithmetic.
This checks conditional fixed-coefficient location identification only; it does
not establish covariance identification, posterior precision or model adequacy.
Run: python3 scripts/four_facet_identification_audit.py
"""
from fractions import Fraction
from itertools import product
import json


def rank(matrix):
    a = [[Fraction(x) for x in row] for row in matrix]
    pivot = 0
    for col in range(len(a[0])):
        found = next((i for i in range(pivot, len(a)) if a[i][col]), None)
        if found is None:
            continue
        a[pivot], a[found] = a[found], a[pivot]
        divisor = a[pivot][col]
        a[pivot] = [x / divisor for x in a[pivot]]
        for i in range(pivot + 1, len(a)):
            if a[i][col]:
                factor = a[i][col]
                a[i] = [x - factor*y for x, y in zip(a[i], a[pivot])]
        pivot += 1
        if pivot == len(a):
            break
    return pivot


def contrast(level, size):
    """Last level is minus the sum of the other coefficients."""
    return [int(level == j) - int(level == size-1) for j in range(size-1)]


def cells(P, T, R, C):
    return list(product(range(P), range(T), range(R), range(C)))


def design(rows, P, T, R, dimensions, *, gauge='global_criterion', H=1,
           centered_steps=True):
    """eta = theta[p,d(c)] - task[t] - rater[r] - criterion[c] - step[c,h].

    H is the number of adjacent steps (categories minus one). Three explicit
    gauges illustrate why a single criterion zero-sum fails for multiple traits.
    This is deliberately a fixture builder, not a FacetData validation API.
    """
    C, D = len(dimensions), max(dimensions)+1
    assert gauge in ('global_criterion', 'within_dimension', 'centered_person')
    out = []
    for p, t, r, c in rows:
        for h in range(H):
            person = (contrast(p, P) if gauge == 'centered_person'
                      else [int(p == j) for j in range(P)])
            row = [x*int(dimensions[c] == d) for d in range(D) for x in person]
            row += [-x for x in contrast(t, T) + contrast(r, R)]
            if gauge == 'global_criterion':
                criterion = contrast(c, C)
            elif gauge == 'centered_person':
                criterion = [int(c == j) for j in range(C)]
            else:
                criterion = []
                for d in range(D):
                    group = [j for j in range(C) if dimensions[j] == d]
                    criterion += [int(c == j)-int(c == group[-1]) for j in group[:-1]]
            row += [-x for x in criterion]
            step = contrast(h, H) if centered_steps else [int(h == j) for j in range(H)]
            row += [-int(c == j)*x for j in range(C) for x in step]
            out.append(row)
    return out


def audit():
    scalar = cells(3, 3, 2, 2)
    multidimensional = cells(3, 3, 2, 4)
    q = [0, 0, 1, 1]
    composite = [[int(p == j) for j in range(3)] +
                 [-x for x in contrast(t*2+c, 6) + contrast(r, 2)]
                 for p, t, r, c in scalar]
    composite_plus_task = [row + [-x for x in contrast(cell[1], 3)]
                           for row, cell in zip(composite, scalar)]
    centered = design(multidimensional, 3, 3, 2, q, gauge='centered_person', H=2)
    within = design(multidimensional, 3, 3, 2, q, gauge='within_dimension', H=2)
    cases = [
        ('crossed_scalar', design(scalar, 3, 3, 2, [0, 0]), 7),
        ('crossed_scalar_centered_steps', design(scalar, 3, 3, 2, [0, 0], H=2), 9),
        ('unconstrained_steps_alias_criterion',
         design(scalar, 3, 3, 2, [0, 0], H=2, centered_steps=False), 9),
        ('person_nested_in_task', design([x for x in cells(4, 2, 2, 2) if x[0]//2 == x[1]],
                                       4, 2, 2, [0, 0]), 6),
        ('rater_nested_in_task', design([x for x in cells(3, 2, 2, 2) if x[1] == x[2]],
                                      3, 2, 2, [0, 0]), 5),
        ('task_criterion_paired', design([x for x in cells(3, 2, 2, 2) if x[1] == x[3]],
                                       3, 2, 2, [0, 0]), 5),
        ('training_fold_missing_task', design([x for x in scalar if x[1] != 2],
                                             3, 3, 2, [0, 0]), 6),
        ('multidimensional_global_criterion_constraint',
         design(multidimensional, 3, 3, 2, q, H=2), 15),
        ('multidimensional_centered_person', centered, 15),
        ('multidimensional_within_dimension_criterion', within, 15),
        ('two_gauges_same_likelihood_space', [a+b for a, b in zip(centered, within)], 15),
        ('unrestricted_composite_difficulty', composite, 9),
        ('composite_plus_redundant_task', composite_plus_task, 9),
    ]
    result = []
    for name, matrix, expected in cases:
        actual = rank(matrix)
        if actual != expected:
            raise AssertionError(f'{name}: rank {actual}, expected {expected}')
        result.append(dict(case=name, rows=len(matrix), columns=len(matrix[0]),
                           rank=actual, nullity=len(matrix[0])-actual))
    return dict(schema='mgmfrm.four_facet_identification_audit.v1',
                arithmetic='exact_rational', cases=result, posterior_fits=0,
                production_model_implemented=False, scientific_acceptance=False)


if __name__ == '__main__':
    print(json.dumps(audit(), indent=2))
