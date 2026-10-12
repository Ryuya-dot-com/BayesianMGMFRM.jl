"""One declared MGMFRM prior-predictive comparison; no posterior fitting.

Usage: python3 scripts/mgmfrm_prior_response_review.py NEW_OUTPUT_DIRECTORY
The fixed plan is written before generating normals. A separate Julia checker
compares these independent equations with the production target and predictor.
"""
import hashlib
import json
import os
from pathlib import Path
import platform
import sys

import numpy as np
import scipy
from scipy.special import logsumexp
from scipy.stats import norm

REPO = Path(__file__).resolve().parents[1]
PERSONS = sorted(f"P{i}" for i in range(1, 51))
ITEM_DIM = np.array([0, 0, 1, 1, 1])
METRICS = ["category_1", "category_2", "category_3", "category_4",
           "endpoint_mass", "dominant_095", "normalized_entropy", "expected_score"]
COLORS = ["#0072B2", "#E69F00", "#009E73", "#CC79A7"]


def write_json(path, value):
    with path.open("x") as stream:
        json.dump(value, stream, indent=2, allow_nan=False)
        stream.write("\n")


def cases():
    root2, z = np.sqrt(2), norm.ppf(.975)
    settings = [
        ("A", "raw_reference", "raw", 1., .5, 1.),
        ("B", "exchangeable_same_numeric", "exchangeable", 1., .5, 1.),
        ("C", "exchangeable_average_variance", "exchangeable", root2, root2 * .5, root2),
        ("D", "exchangeable_narrow_raters", "exchangeable", .5 / (root2*z), np.log(2)/(root2*z), root2),
        ("E", "exchangeable_narrow_raters_steps", "exchangeable", .5/(root2*z), np.log(2)/(root2*z), 1/(root2*z)),
        ("F", "exchangeable_wider_raters_narrow_steps", "exchangeable", 1/(root2*z), np.log(4)/(root2*z), 1/(root2*z)),
    ]
    return [dict(id=key, name=name, model=model, scales=dict(person_sd=1.,
        rater_sd=s, item_sd=1., log_discrimination_sd=.5,
        log_consistency_sd=g, step_sd=t)) for key, name, model, s, g, t in settings]


def zero_sum(z, sd, model):
    if model == "raw":
        free = sd * z[..., :-1]
        return np.concatenate((free, -free.sum(axis=-1, keepdims=True)), axis=-1)
    return sd * (z - z.mean(axis=-1, keepdims=True))


def raw_draws(z, case):
    s, model = case["scales"], case["model"]
    severity = zero_sum(z[:, 110:115], s["rater_sd"], model)
    ell = zero_sum(z[:, 115:120], s["log_consistency_sd"], model)
    steps = zero_sum(z[:, 120:135].reshape(-1, 5, 3), s["step_sd"], model)
    return np.column_stack((z[:, :100]*s["person_sd"], severity[:, :4],
        z[:, 100:105]*s["item_sd"], z[:, 105:110]*s["log_discrimination_sd"],
        ell[:, :4], steps[:, :, :2].reshape(-1, 10)))


def unpack(raw):
    theta = raw[:, :100].reshape(-1, 50, 2)
    severity = np.column_stack((raw[:, 100:104], -raw[:, 100:104].sum(axis=1)))
    ell = np.column_stack((raw[:, 114:118], -raw[:, 114:118].sum(axis=1)))
    free = raw[:, 118:128].reshape(-1, 5, 2)
    steps = np.concatenate((free, -free.sum(axis=-1, keepdims=True)), axis=-1)
    return theta, severity, raw[:, 104:109], raw[:, 109:114], ell, steps


def probabilities(raw):
    theta, severity, b, loga, ell, steps = unpack(raw)
    eta = (theta[:, :, ITEM_DIM] * np.exp(loga)[:, None, :]
           - b[:, None, :])[:, :, :, None] - severity[:, None, None, :]
    adjacent = 1.7 * np.exp(ell)[:, None, None, :, None] * (
        eta[..., None] - steps[:, None, :, None, :])
    logits = np.concatenate((np.zeros((*eta.shape, 1)), adjacent.cumsum(axis=-1)), axis=-1)
    logs = logits - logsumexp(logits, axis=-1, keepdims=True)
    return np.exp(logs).reshape(-1, 1250, 4), logs.reshape(-1, 1250, 4)


def prior_logdensity(raw, case):
    s = case["scales"]
    sd = np.repeat([s["person_sd"], s["rater_sd"], s["item_sd"],
        s["log_discrimination_sd"], s["log_consistency_sd"], s["step_sd"]],
        [100, 4, 5, 5, 4, 10])
    value = (-.5*(raw/sd)**2 - np.log(sd) - .5*np.log(2*np.pi)).sum(axis=1)
    if case["model"] == "exchangeable":
        for block, tau, n in [(raw[:, 100:104], s["rater_sd"], 5),
                             (raw[:, 114:118], s["log_consistency_sd"], 5)]:
            value += .5*np.log(n) - .5*(block.sum(axis=1)/tau)**2
        free = raw[:, 118:128].reshape(-1, 5, 2)
        value += (np.log(3)/2 - .5*(free.sum(axis=-1)/s["step_sd"])**2).sum(axis=1)
    return value


def summarize(x):
    return dict(n=len(x), mean=float(x.mean()), q05=float(np.quantile(x, .05)),
        q95=float(np.quantile(x, .95)), iid_panel_mean_mcse=float(x.std(ddof=1)/np.sqrt(len(x))))


def groups():
    cells = [(p, i, r) for p in range(50) for i in range(5) for r in range(5)]
    items, raters = np.array(cells)[:, 1:].T
    weights = np.where(items < 2, 1/(50*2*2*5), 1/(50*2*3*5))
    masks = [np.ones(1250, dtype=bool)] + [raters == r for r in range(5)] + [ITEM_DIM[items] == d for d in range(2)]
    names = ["overall"] + [f"R{r}" for r in range(1, 6)] + ["D1", "D2"]
    return [(name, mask, weights[mask]/weights[mask].sum()) for name, mask in zip(names, masks)]


def mechanism_probs(location, gamma, steps):
    adjacent = 1.7*np.asarray(gamma)[..., None]*(np.asarray(location)[..., None]-np.asarray(steps))
    logits = np.concatenate((np.zeros((*adjacent.shape[:-1], 1)), adjacent.cumsum(axis=-1)), axis=-1)
    return np.exp(logits-logsumexp(logits, axis=-1, keepdims=True))


def mechanisms(output, plt):
    severity = np.linspace(-2, 2, 201)
    gamma = np.geomspace(.05, 10, 201)
    ordered_steps = np.array([-1., 0., 1.])
    ps = mechanism_probs(-severity, 1., ordered_steps)
    pg = mechanism_probs(.6, gamma, ordered_steps)
    arrangements = [ordered_steps, np.zeros(3), -ordered_steps]
    pt = np.array([mechanism_probs(0., 1., step) for step in arrangements])
    assert np.allclose(pt @ np.arange(1, 5), 2.5)
    assert np.allclose(pt[[0, 2], 0] + pt[[0, 2], 3], 1/(1+np.exp([1.7, -1.7])))
    fig, axes = plt.subplots(1, 3, figsize=(13.5, 4.2), layout="constrained")
    for k, color in enumerate(COLORS):
        axes[0].plot(severity, ps[:, k], color=color, label=f"Category {k+1}")
        axes[1].semilogx(gamma, pg[:, k], color=color)
        axes[2].bar(np.arange(3), pt[:, k], bottom=pt[:, :k].sum(axis=1), color=color)
    axes[0].set(xlabel="Rater severity s (a*theta - b = 0)", title="Severity changes score location")
    axes[1].set(xlabel="Rater consistency gamma (location = 0.6)", title="High gamma favors category 3 here")
    axes[2].set(xticks=range(3), xticklabels=["(-1, 0, 1)", "(0, 0, 0)", "(1, 0, -1)"],
                xlabel="Step vector; all expected scores = 2.5", title="Equal means, different categories")
    for ax in axes:
        ax.set(ylim=(0, 1), ylabel="Response probability")
        ax.spines[["top", "right"]].set_visible(False)
    axes[0].legend(frameon=False, fontsize=9)
    for suffix in ("png", "svg"):
        fig.savefig(output/f"mechanisms.{suffix}", dpi=180)
    plt.close(fig)
    # Embed these examples into the valid complete design for production checks.
    probes = []
    for mode, values in (("severity", [-1., 0., 1.]), ("gamma", [.25, 1., 4.]), ("steps", arrangements)):
        for index, value in enumerate(values):
            raw = np.zeros((1, 128))
            raw[:, 118:] = np.tile(ordered_steps[:2], 5)
            if mode == "severity":
                raw[0, 100:102] = [value, -value]
                expected = mechanism_probs(-value, 1., ordered_steps)
            elif mode == "gamma":
                raw[:, :100] = .6
                raw[0, 114:116] = [np.log(value), -np.log(value)]
                expected = mechanism_probs(.6, value, ordered_steps)
            else:
                raw[:, 118:] = np.tile(value[:2], 5)
                expected = mechanism_probs(0., 1., value)
            assert np.allclose(probabilities(raw)[0][0, 0], expected)
            probes.append(dict(name=f"{mode}_{index}", raw=raw[0].tolist(), first_cell_probabilities=expected.tolist()))
    write_json(output/"mechanisms.json", dict(severity_odds_multiplier_delta_half=float(np.exp(-.85)),
        step_probabilities=pt.tolist(), step_endpoint_mass=(pt[:, 0]+pt[:, 3]).tolist(), probes=probes))


def plot_comparison(output, summaries, plt):
    fig, axes = plt.subplots(1, 3, figsize=(12, 4.6), layout="constrained")
    titles = ["Endpoint probability", "Cells with max probability >= 0.95", "Entropy / log(4)"]
    for ax, metric, title in zip(axes, ["endpoint_mass", "dominant_095", "normalized_entropy"], titles):
        values = [s["groups"]["overall"][metric] for s in summaries]
        ax.errorbar([v["mean"] for v in values], np.arange(6),
            xerr=[2*v["iid_panel_mean_mcse"] for v in values], fmt="o", color="#0072B2", capsize=3)
        ax.set(yticks=range(6), yticklabels=[s["id"] for s in summaries], xlabel=title)
        ax.invert_yaxis()
        ax.grid(axis="x", alpha=.2)
        ax.spines[["top", "right"]].set_visible(False)
    fig.suptitle("Joint prior predictions: mean +/- 2 Monte Carlo SE (4,096 independent panels)")
    fig.text(.015, -.08, "A raw | B same numeric SD | C mean variance matched | D narrower raters | E D + narrower steps | F E + wider raters", fontsize=9)
    for suffix in ("png", "svg"):
        fig.savefig(output/f"joint-comparison.{suffix}", dpi=180, bbox_inches="tight")
    plt.close(fig)
    matrix = np.array([[s["groups"][f"R{r}"]["dominant_095"]["mean"] for r in range(1, 6)] for s in summaries])
    fig, ax = plt.subplots(figsize=(7, 4.4), layout="constrained")
    im = ax.imshow(matrix, cmap="Blues", vmin=0, vmax=1)
    for row in range(6):
        for col in range(5):
            ax.text(col, row, f"{100*matrix[row, col]:.1f}%", ha="center", va="center", color="#152d40")
    ax.set(xticks=range(5), xticklabels=[f"R{r}" for r in range(1, 6)], yticks=range(6),
        yticklabels=[s["id"] for s in summaries], title="Prior mean fraction of concentrated cells, by rater")
    fig.colorbar(im, ax=ax, label="Cell maximum category probability >= 0.95")
    for suffix in ("png", "svg"):
        fig.savefig(output/f"rater-comparison.{suffix}", dpi=180)
    plt.close(fig)


def main(output):
    output.mkdir(parents=True, exist_ok=False)
    plan = dict(question="How do declared contrast widths change MGMFRM prior response probabilities?",
        status="exploratory illustration; no adopted scientific widths or acceptance threshold",
        ndraws=4096, seed=2026092409, generator="numpy.random.PCG64", batch_size=128,
        precision="independent unit is a complete prior parameter panel; bounded mean MCSE <= 0.5/sqrt(4096)",
        persons=PERSONS, items=[f"I{i}" for i in range(1, 6)], raters=[f"R{r}" for r in range(1, 6)],
        categories=[1, 2, 3, 4], item_dimension_0based=ITEM_DIM.tolist(), source_scale=1.7,
        cell_order="person, then item, then rater (rater fastest)",
        weighting="equal persons/dimensions, then equal items within dimension and equal raters",
        common_normals="135 columns: theta person-major (100), b (5), loga (5), severity (5), loggamma (5), steps item-major (15)",
        raw_order="128: theta(100), severity_free(4), b(5), loga(5), loggamma_free(4), step_free item-major(10)",
        cases=cases(), paired_differences=["B-A", "C-A", "D-C", "E-D", "F-E"],
        probe_indices_0based=[0, 1, 63, 511, 2047, 4095], metrics=METRICS,
        category_absence="conditional product over the 1250 actual cells; no weighting or response sampling",
        observed_data_used=False, posterior_fitting=False,
        versions=dict(python=platform.python_version(), numpy=np.__version__, scipy=scipy.__version__),
        source_sha256={str(p.relative_to(REPO)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [
            Path(__file__).resolve(), REPO/"scripts/check_mgmfrm_prior_response_review.jl",
            REPO/"src/bayesian_fit.jl", REPO/"src/facet_workflow.jl", REPO/"src/mgmfrm_normalized_prior.jl"]})
    write_json(output/"plan.json", plan)
    z = np.random.Generator(np.random.PCG64(plan["seed"])).standard_normal((plan["ndraws"], 135))
    np.save(output/"common-normal-innovations.npy", z)
    all_groups = groups()
    summaries, panels, probes = [], {}, []
    max_normalization_error = 0.
    for case in plan["cases"]:
        raw = raw_draws(z, case)
        np.savez_compressed(output/f'{case["id"]}-raw.npz', raw=raw)
        values = np.empty((len(raw), len(all_groups), len(METRICS)))
        absence = np.empty((len(raw), 4))
        for start in range(0, len(raw), plan["batch_size"]):
            stop = min(start+plan["batch_size"], len(raw))
            p, logp = probabilities(raw[start:stop])
            assert np.isfinite(logp).all() and np.isfinite(p).all()
            max_normalization_error = max(max_normalization_error, float(np.max(np.abs(p.sum(axis=-1)-1))))
            cell_metrics = np.concatenate((p, (p[:, :, 0]+p[:, :, 3])[..., None],
                (p.max(axis=-1) >= .95)[..., None],
                (-np.sum(p*logp, axis=-1)/np.log(4))[..., None],
                (p@np.arange(1, 5))[..., None]), axis=-1)
            for gi, (_, mask, weights) in enumerate(all_groups):
                values[start:stop, gi] = np.einsum("nrm,r->nm", cell_metrics[:, mask], weights)
            # log(1-p) via the other three log probabilities avoids rounding p=1.
            for k in range(4):
                absence[start:stop, k] = np.exp(logsumexp(np.delete(logp, k, axis=-1), axis=-1).sum(axis=-1))
        assert max_normalization_error < 1e-11
        np.savez_compressed(output/f'{case["id"]}-panel-metrics.npz', metrics=values, category_absence=absence)
        summary = dict(id=case["id"], groups={name: {metric: summarize(values[:, gi, mi])
            for mi, metric in enumerate(METRICS)} for gi, (name, _, _) in enumerate(all_groups)},
            category_absence={str(k+1): summarize(absence[:, k]) for k in range(4)},
            rater5_minus_mean_others={metric: summarize(values[:, 5, mi]-values[:, 1:5, mi].mean(axis=1))
                for mi, metric in enumerate(METRICS)})
        summaries.append(summary)
        panels[case["id"]] = values
        chosen = raw[plan["probe_indices_0based"]]
        pp, _ = probabilities(chosen)
        probes.append(dict(id=case["id"], raw=chosen.tolist(), probabilities=pp.tolist(),
            logprior=prior_logdensity(chosen, case).tolist()))
        print(json.dumps(dict(id=case["id"], overall=summary["groups"]["overall"])), flush=True)
    paired = {contrast: {metric: summarize((panels[contrast[0]]-panels[contrast[2]])[:, 0, mi])
        for mi, metric in enumerate(METRICS)} for contrast in plan["paired_differences"]}
    write_json(output/"summary.json", dict(cases=summaries, paired=paired,
        max_probability_sum_error=max_normalization_error))
    write_json(output/"production-probes.json", probes)
    os.environ.setdefault("MPLCONFIGDIR", str(output/"matplotlib-cache"))
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    mechanisms(output, plt)
    plot_comparison(output, summaries, plt)
    print(f"Finished prior predictions in {output}; run the Julia production checker next.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(Path(sys.argv[1]).resolve())
