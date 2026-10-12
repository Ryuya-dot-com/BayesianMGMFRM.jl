#!/usr/bin/env python3
"""Generate BridgeStan fixtures for source-aligned GMFRM/MGMFRM raw targets.

This script is intentionally outside the default Julia test path. It requires
the Python `bridgestan` package and a working C++ toolchain. The generated JSON
fixtures are intended to become external-oracle checks before generalized
fitting is promoted beyond fixture-only internal targets.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import pathlib
import tempfile
from datetime import datetime, timezone
from typing import Any

import numpy as np


PRIOR = {
    "person_sd": 1.1,
    "rater_sd": 1.2,
    "item_sd": 1.3,
    "log_discrimination_sd": 1.4,
    "log_consistency_sd": 1.5,
    "step_sd": 1.6,
}

OBSERVATIONS = {
    "PersonID": [1, 1, 1, 2, 2, 2],
    "RaterID": [1, 2, 1, 1, 2, 1],
    "ItemID": [1, 1, 2, 1, 2, 2],
    "X": [1, 2, 3, 2, 1, 3],
}

FIXTURES: dict[str, dict[str, Any]] = {
    "gmfrm": {
        "schema": "bayesianmgmfrm.source_gmfrm_bridge_logdensity.v1",
        "stan_file": "test/stan/source_gmfrm_fixture.stan",
        "output": "test/fixtures/source_gmfrm_bridge_logdensity.json",
        "stan_data": {
            "J": 2,
            "I": 2,
            "R": 2,
            "K": 3,
            "N": 6,
            **OBSERVATIONS,
            **PRIOR,
        },
        "x": [
            0.3,
            -0.2,
            0.1,
            -0.05,
            -0.2,
            math.log(2.0),
            math.log(1.2),
            math.log(0.8),
            0.25,
            -0.1,
        ],
        "julia_raw_parameter_order": [
            "person[E1]",
            "person[E2]",
            "rater[R1]",
            "rater[R2]",
            "raw_item[I1]",
            "raw_log_item_discrimination[I1]",
            "raw_log_rater_consistency[rater=R1]",
            "raw_log_rater_consistency[rater=R2]",
            "rater_step[rater=R1,m=2]",
            "rater_step[rater=R2,m=2]",
        ],
        "stan_direct_parameter_order": [
            "person.1",
            "person.2",
            "rater.1",
            "rater.2",
            "item.1",
            "item.2",
            "item_discrimination.1",
            "item_discrimination.2",
            "rater_consistency.1",
            "rater_consistency.2",
            "rater_steps.1",
            "rater_steps.2",
        ],
        "julia_direct_parameter_order": [
            "person[E1]",
            "person[E2]",
            "rater[R1]",
            "rater[R2]",
            "item[I1]",
            "item[I2]",
            "item_discrimination[item=I1]",
            "item_discrimination[item=I2]",
            "rater_consistency[rater=R1]",
            "rater_consistency[rater=R2]",
            "rater_step[rater=R1,m=2]",
            "rater_step[rater=R2,m=2]",
        ],
    },
    "mgmfrm": {
        "schema": "bayesianmgmfrm.source_mgmfrm_bridge_logdensity.v1",
        "stan_file": "test/stan/source_mgmfrm_fixture.stan",
        "output": "test/fixtures/source_mgmfrm_bridge_logdensity.json",
        "stan_data": {
            "J": 2,
            "I": 2,
            "R": 2,
            "K": 3,
            "D": 2,
            "N": 6,
            "NLoadings": 2,
            "LoadingItem": [1, 2],
            "LoadingDim": [1, 2],
            **OBSERVATIONS,
            **PRIOR,
        },
        "x": [
            0.2,
            -0.1,
            -0.3,
            0.4,
            0.15,
            -0.2,
            0.1,
            math.log(1.5),
            math.log(0.7),
            math.log(1.25),
            0.3,
            -0.2,
        ],
        "julia_raw_parameter_order": [
            "person[E1,dim=1]",
            "person[E1,dim=2]",
            "person[E2,dim=1]",
            "person[E2,dim=2]",
            "raw_rater[R1]",
            "item[I1]",
            "item[I2]",
            "raw_log_item_dimension_discrimination[item=I1,dim=1]",
            "raw_log_item_dimension_discrimination[item=I2,dim=2]",
            "raw_log_rater_consistency[R1]",
            "item_step[item=I1,m=2]",
            "item_step[item=I2,m=2]",
        ],
        "stan_direct_parameter_order": [
            "person.1",
            "person.2",
            "person.3",
            "person.4",
            "rater.1",
            "rater.2",
            "item.1",
            "item.2",
            "item_dimension_discrimination.1",
            "item_dimension_discrimination.2",
            "rater_consistency.1",
            "rater_consistency.2",
            "item_steps.1",
            "item_steps.2",
        ],
        "julia_direct_parameter_order": [
            "person[E1,dim=1]",
            "person[E1,dim=2]",
            "person[E2,dim=1]",
            "person[E2,dim=2]",
            "rater[R1]",
            "rater[R2]",
            "item[I1]",
            "item[I2]",
            "item_dimension_discrimination[item=I1,dim=1]",
            "item_dimension_discrimination[item=I2,dim=2]",
            "rater_consistency[rater=R1]",
            "rater_consistency[rater=R2]",
            "item_step[item=I1,m=2]",
            "item_step[item=I2,m=2]",
        ],
    },
}


def sha256_file(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def normal_logpdf(x: float, sd: float) -> float:
    z = x / sd
    return -math.log(sd) - 0.5 * (math.log(2.0 * math.pi) + z * z)


def raw_prior_sds(family: str, stan_data: dict[str, Any]) -> list[float]:
    if family == "gmfrm":
        return (
            [stan_data["person_sd"]] * stan_data["J"]
            + [stan_data["rater_sd"]] * stan_data["R"]
            + [stan_data["item_sd"]] * (stan_data["I"] - 1)
            + [stan_data["log_discrimination_sd"]] * (stan_data["I"] - 1)
            + [stan_data["log_consistency_sd"]] * stan_data["R"]
            + [stan_data["step_sd"]] * (stan_data["R"] * (stan_data["K"] - 2))
        )
    if family == "mgmfrm":
        return (
            [stan_data["person_sd"]] * (stan_data["J"] * stan_data["D"])
            + [stan_data["rater_sd"]] * (stan_data["R"] - 1)
            + [stan_data["item_sd"]] * stan_data["I"]
            + [stan_data["log_discrimination_sd"]] * stan_data["NLoadings"]
            + [stan_data["log_consistency_sd"]] * (stan_data["R"] - 1)
            + [stan_data["step_sd"]] * (stan_data["I"] * (stan_data["K"] - 2))
        )
    raise ValueError(f"unsupported family {family}")


def raw_prior_log_density(family: str, x: np.ndarray, stan_data: dict[str, Any]) -> float:
    sds = raw_prior_sds(family, stan_data)
    if len(sds) != len(x):
        raise ValueError(f"prior scale count {len(sds)} does not match raw parameter count {len(x)}")
    return sum(normal_logpdf(float(value), float(sd)) for value, sd in zip(x, sds))


def generated_log_likelihood(
    names: list[str],
    values: list[float],
    n_observations: int,
) -> list[float]:
    lookup = dict(zip(names, values))
    out = []
    for index in range(1, n_observations + 1):
        name = f"log_lik.{index}"
        if name not in lookup:
            raise ValueError(f"generated quantity {name} is missing from BridgeStan output")
        out.append(float(lookup[name]))
    return out


def q_matrix_from_loading_rows(stan_data: dict[str, Any]) -> list[list[bool]]:
    q_matrix = [
        [False for _ in range(int(stan_data["D"]))]
        for _ in range(int(stan_data["I"]))
    ]
    for item, dim in zip(stan_data["LoadingItem"], stan_data["LoadingDim"]):
        q_matrix[int(item) - 1][int(dim) - 1] = True
    return q_matrix


def fit_ready_oracle_fixture(
    family: str,
    spec: dict[str, Any],
    x: np.ndarray,
    stan_log_density: float,
    stan_gradient: np.ndarray,
    stan_log_likelihood: float,
    stan_constrained_lookup: dict[str, float],
    stan_generated_names: list[str],
    stan_generated_values: list[float],
) -> tuple[str, dict[str, Any]] | None:
    if family not in ("gmfrm", "mgmfrm"):
        return None
    pointwise = generated_log_likelihood(
        stan_generated_names,
        stan_generated_values,
        int(spec["stan_data"]["N"]),
    )
    common = {
        "status": "internal_fit_ready_candidate",
        "public_fit": False,
        "fit_ready": False,
        "raw_parameter_order": spec["julia_raw_parameter_order"],
        "raw_parameter_values": spec["x"],
        "raw_log_density": stan_log_density,
        "raw_gradient": stan_gradient.tolist(),
        "direct_parameter_order": spec["julia_direct_parameter_order"],
        "direct_parameter_values": [
            stan_constrained_lookup[name]
            for name in spec["stan_direct_parameter_order"]
        ],
        "pointwise_log_likelihood": pointwise,
        "log_likelihood": stan_log_likelihood,
        "stan_generated_quantity_order": [
            f"log_lik.{index}" for index in range(1, int(spec["stan_data"]["N"]) + 1)
        ],
        "tolerance": 1.0e-8,
    }
    if family == "gmfrm":
        return "fit_ready_candidate", {
            "schema": "bayesianmgmfrm.fit_ready_scalar_gmfrm_bridge_oracle.v1",
            "source_oracle": "source_gmfrm_fixture.stan",
            **common,
        }
    return "confirmatory_candidate", {
        "schema": "bayesianmgmfrm.fit_ready_confirmatory_mgmfrm_bridge_oracle.v1",
        "source_oracle": "source_mgmfrm_fixture.stan",
        "dimensions": int(spec["stan_data"]["D"]),
        "q_matrix": q_matrix_from_loading_rows(spec["stan_data"]),
        "latent_correlation": "identity_fixed",
        "ability_location": "zero_by_dimension",
        "ability_scale": "unit_variance_by_dimension",
        "source_scale": 1.7,
        "interpreted_loading_sign": "positive",
        **common,
    }


def generate_fixture(root: pathlib.Path, family: str) -> pathlib.Path:
    import bridgestan
    from bridgestan.model import StanRNG

    spec = FIXTURES[family]
    stan_path = (root / spec["stan_file"]).resolve()
    output_path = (root / spec["output"]).resolve()
    x = np.array(spec["x"], dtype=np.float64)

    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as data_file:
        json.dump(spec["stan_data"], data_file, indent=2)
        data_file.write("\n")
        data_path = pathlib.Path(data_file.name)

    try:
        model = bridgestan.StanModel.from_stan_file(str(stan_path), model_data=str(data_path))
        stan_log_density, stan_gradient = model.log_density_gradient(
            x,
            propto=False,
            jacobian=False,
        )
        stan_constrained_values = model.param_constrain(
            x,
            include_tp=True,
            include_gq=False,
        )
        stan_constrained_names = model.param_names(
            include_tp=True,
            include_gq=False,
        )
        stan_generated_values = model.param_constrain(
            x,
            include_tp=True,
            include_gq=True,
            rng=StanRNG(model.stanlib, 20260619),
        )
        stan_generated_names = model.param_names(
            include_tp=True,
            include_gq=True,
        )
    finally:
        data_path.unlink(missing_ok=True)

    stan_constrained_lookup = dict(zip(stan_constrained_names, stan_constrained_values.tolist()))
    stan_generated_names_list = list(stan_generated_names)
    stan_generated_values_list = stan_generated_values.tolist()
    stan_log_likelihood = stan_log_density - raw_prior_log_density(
        family,
        x,
        spec["stan_data"],
    )
    pointwise_log_likelihood = generated_log_likelihood(
        stan_generated_names_list,
        stan_generated_values_list,
        int(spec["stan_data"]["N"]),
    )
    fixture = {
        "schema": spec["schema"],
        "source": "BridgeStan log_density_gradient, constrained parameters, and generated pointwise log likelihood for source-aligned raw-coordinate fixture",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "bridgestan_version": getattr(bridgestan, "__version__", None),
        "stan_model": str(stan_path.relative_to(root)),
        "stan_model_sha256": sha256_file(stan_path),
        "stan_data": spec["stan_data"],
        "stan_parameter_order": model.param_unc_names(),
        "julia_raw_parameter_order": spec["julia_raw_parameter_order"],
        "x": spec["x"],
        "stan_constrained_parameter_order": stan_constrained_names,
        "stan_constrained_parameter_values": stan_constrained_values.tolist(),
        "stan_log_density": stan_log_density,
        "stan_log_likelihood": stan_log_likelihood,
        "stan_pointwise_log_likelihood": pointwise_log_likelihood,
        "stan_gradient": stan_gradient.tolist(),
        "propto": False,
        "jacobian": False,
        "tolerance": 1.0e-8,
    }
    if "stan_direct_parameter_order" in spec:
        fixture["stan_direct_parameter_order"] = spec["stan_direct_parameter_order"]
        fixture["julia_direct_parameter_order"] = spec["julia_direct_parameter_order"]
        fixture["julia_direct_parameter_values"] = [
            stan_constrained_lookup[name]
            for name in spec["stan_direct_parameter_order"]
        ]
        candidate_oracle = fit_ready_oracle_fixture(
            family,
            spec,
            x,
            stan_log_density,
            stan_gradient,
            stan_log_likelihood,
            stan_constrained_lookup,
            stan_generated_names_list,
            stan_generated_values_list,
        )
        if candidate_oracle is not None:
            candidate_key, candidate_fixture = candidate_oracle
            fixture[candidate_key] = candidate_fixture
    output_path.write_text(json.dumps(fixture, indent=2) + "\n")
    return output_path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--family",
        choices=("gmfrm", "mgmfrm", "all"),
        default="all",
        help="Fixture family to generate.",
    )
    args = parser.parse_args()

    root = pathlib.Path(__file__).resolve().parents[1]
    families = ("gmfrm", "mgmfrm") if args.family == "all" else (args.family,)
    for family in families:
        output_path = generate_fixture(root, family)
        print(f"Wrote {output_path.relative_to(root)}")


if __name__ == "__main__":
    main()
