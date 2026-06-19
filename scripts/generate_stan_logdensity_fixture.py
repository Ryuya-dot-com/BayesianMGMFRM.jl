#!/usr/bin/env python3
"""Generate the scalar Stan/BridgeStan log-density fixture.

This script is intentionally not part of the default Julia test path. It
requires the Python `bridgestan` package and a working C++ toolchain. The
generated JSON is committed under `test/fixtures/` and read by `Pkg.test()`.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
from datetime import datetime, timezone

import numpy as np


def stan_data_from_known_fixture(fixture: dict) -> dict:
    data = fixture["data"]
    return {
        "J": data["J"],
        "I": 1,
        "R": data["R"],
        "K": data["K"],
        "D": 1,
        "N": data["N"],
        "ExamineeID": data["examinee"],
        "ItemID": [1] * data["N"],
        "RaterID": data["rater"],
        "X": data["X"],
    }


def sha256_file(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--known-fixture",
        default="test/fixtures/scalar_validation_known_value.json",
        help="Julia analytic known-answer fixture to use as the fixed point.",
    )
    parser.add_argument(
        "--stan-file",
        default="test/stan/scalar_gmfrm.stan",
        help="Scalar Stan reference model.",
    )
    parser.add_argument(
        "--output",
        default="test/fixtures/scalar_validation_stan_logdensity.json",
        help="Output JSON fixture path.",
    )
    args = parser.parse_args()

    root = pathlib.Path(__file__).resolve().parents[1]
    known_path = (root / args.known_fixture).resolve()
    stan_path = (root / args.stan_file).resolve()
    output_path = (root / args.output).resolve()

    import bridgestan

    known = json.loads(known_path.read_text())
    stan_data = stan_data_from_known_fixture(known)
    x = np.array(known["x"], dtype=np.float64)

    data_path = output_path.with_suffix(".stan_data.tmp.json")
    data_path.write_text(json.dumps(stan_data, indent=2) + "\n")
    try:
        model = bridgestan.StanModel.from_stan_file(str(stan_path), model_data=str(data_path))
        stan_log_density, stan_gradient = model.log_density_gradient(
            x,
            propto=False,
            jacobian=True,
        )
    finally:
        data_path.unlink(missing_ok=True)

    fixture = {
        "schema": "bayesianmgmfrm.scalar_stan_logdensity.v1",
        "source": "BridgeStan log_density_gradient with propto=false and jacobian=true",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "bridgestan_version": getattr(bridgestan, "__version__", None),
        "stan_model": str(stan_path.relative_to(root)),
        "stan_model_sha256": sha256_file(stan_path),
        "known_fixture": str(known_path.relative_to(root)),
        "known_fixture_sha256": sha256_file(known_path),
        "stan_data": stan_data,
        "stan_parameter_order": model.param_unc_names(),
        "x": known["x"],
        "stan_log_density": stan_log_density,
        "stan_gradient": stan_gradient.tolist(),
        "julia_log_density": known["log_density"],
        "julia_gradient": known["gradient"],
        "propto": False,
        "jacobian": True,
        "tolerance": 1.0e-9,
    }
    if "size" in known:
        fixture["size"] = known["size"]
    output_path.write_text(json.dumps(fixture, indent=2) + "\n")
    print(f"Wrote {output_path.relative_to(root)}")


if __name__ == "__main__":
    main()
