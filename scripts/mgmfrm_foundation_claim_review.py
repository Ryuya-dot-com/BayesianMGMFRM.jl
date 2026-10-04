"""Describe ability recovery on the two saved candidate-C panels; no acceptance test."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from mgmfrm_normalized_core_analysis import PERSONS


def ability_errors(draws, truth, person_sd):
    draws, truth = np.asarray(draws, dtype=float), np.asarray(truth, dtype=float)
    if (draws.ndim != 3 or draws.shape[0] < 2 or draws.shape[1] < 2
            or truth.shape != draws.shape[1:] or not np.isfinite(draws).all()
            or not np.isfinite(truth).all() or not np.isfinite(person_sd) or person_sd <= 0):
        raise ValueError("finite draw/person/dimension arrays and a positive prior SD required")
    n = draws.shape[1]
    means = draws.mean(axis=1)
    centered = draws - means[:, None, :]
    truth_mean = truth.mean(axis=0)
    truth_centered = truth - truth_mean
    estimate = draws.mean(axis=0)
    absolute_mse = np.mean((estimate - truth)**2, axis=0)
    centered_mse = np.mean((centered.mean(axis=0) - truth_centered)**2, axis=0)
    location_error = estimate.mean(axis=0) - truth_mean
    return [dict(dimension=d+1,
        absolute_rmse=float(np.sqrt(absolute_mse[d])),
        centered_rmse=float(np.sqrt(centered_mse[d])),
        panel_mean_error=float(location_error[d]),
        mse_decomposition_error=float(absolute_mse[d]-centered_mse[d]-location_error[d]**2),
        prior_zero_absolute_rmse=float(np.sqrt(np.mean(truth[:, d]**2))),
        prior_zero_centered_rmse=float(np.sqrt(np.mean(truth_centered[:, d]**2))),
        posterior_panel_mean_sd=float(means[:, d].std(ddof=1)),
        prior_panel_mean_sd=float(person_sd/np.sqrt(n)),
        mean_posterior_centered_sd=float(centered[:, :, d].std(axis=0, ddof=1).mean()),
        prior_centered_marginal_sd=float(person_sd*np.sqrt(1-1/n)))
        for d in range(truth.shape[1])]


def review(root):
    panels = [
        ("first", "20260926-foundation-oracle-01/input.json",
         "20260926-normalized-core-review-01/location"),
        ("independent", "20260926-normalized-replication-01/input.json",
         "20260926-normalized-replication-01/run/review")]
    rows, hashes = [], {}
    def read_bytes(path):
        data = path.read_bytes()
        hashes[str(path.relative_to(root))] = hashlib.sha256(data).hexdigest()
        return data
    for label, input_name, directory_name in panels:
        input_path = root/input_name
        directory = root/directory_name
        source = json.loads(read_bytes(input_path))
        record = json.loads(read_bytes(directory/"review.json"))
        binary = read_bytes(directory/"values.bin")
        expected_names = [f"person[{p},dim={d}]" for p in PERSONS for d in (1, 2)]
        if (hashes[input_name] != record["input_sha256"]
                or hashlib.sha256(binary).hexdigest() != record["values"]["sha256"]
                or record["values"]["shape"] != [4000, 150]
                or record["values"]["format"] != "little_endian_float64"
                or record["values"]["order"] != "column_major"
                or record["names"][:100] != expected_names):
            raise ValueError("input, sample export, shape or person order mismatch")
        values = np.frombuffer(binary, dtype="<f8").reshape(4000, 150, order="F")
        truth = np.array(source["raw_truth"][:100]).reshape(50, 2)
        if not np.allclose(truth.ravel(), record["truths"][:100], atol=1e-12, rtol=0):
            raise ValueError("truth export mismatch")
        rows.append(dict(panel=label, input_sha256=record["input_sha256"],
            target_identity=record["target_identity"], original_gate=record["qualified"],
            dimensions=ability_errors(values[:, :100].reshape(4000, 50, 2),
                                      truth, source["scales"]["person_sd"])))
    if len({r["input_sha256"] for r in rows}) != 2:
        raise ValueError("the two panel inputs must be distinct")
    for path, digest in hashes.items():
        if hashlib.sha256((root/path).read_bytes()).hexdigest() != digest:
            raise ValueError("source changed during review")
    return dict(rows=rows, source_sha256=hashes, independent_datasets=2,
        new_fits=0, scientific_acceptance=False, exploratory_posthoc=True,
        centered_quantity_mcse_verified=False,
        interpretation="Posterior-mean error on two joint-prior panels, not fixed-facet recovery, "
                       "calibration acceptance, a confidence interval or predictive validation. "
                       "Centering removes location, not dependence on the ability unit. "
                       "Prior zero is a data-ignoring point baseline, not another fitted model.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = review(Path(__file__).resolve().parents[1]/"results/workflows")
    result["script_sha256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    with args.output.open("x") as stream:
        json.dump(result, stream, indent=2, allow_nan=False)
        stream.write("\n")
    print(json.dumps(result["rows"], indent=2))
