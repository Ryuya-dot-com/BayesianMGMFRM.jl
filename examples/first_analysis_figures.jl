module FirstMFRMFigures

using BayesianMGMFRM, SHA
using BayesianMGMFRM.Legacy
using BayesianMGMFRM: JSON3

const BUNDLE = joinpath(pkgdir(BayesianMGMFRM), "docs", "src", "assets", "first-analysis")

"""Read the supplied fitted teaching result and verify its saved figures; no fitting or random draws."""
function review(directory=BUNDLE)
    provenance = JSON3.read(read(joinpath(directory, "provenance.json"), String))
    for name in ("answer.json", "answer.txt", "fit_report.json")
        bytes2hex(sha256(read(joinpath(directory, name)))) == provenance.sha256[name] ||
            throw(ArgumentError("Saved teaching-result checksum mismatch: $name"))
    end
    # The existing bundle reader checks the report, tables and all declared figures.
    report = load_fit_report_bundle(directory; require_complete=true)
    answer = JSON3.read(read(joinpath(directory, "answer.json"), String))
    row = only(filter(r -> r["parameter"] == answer.parameter, report["posterior"]["rows"]))
    # Match the recorded interval definition, not a separately rounded tail probability.
    interval = only(filter(r -> r["probability"] == answer.interval_probability, row["intervals"]))
    row["mean"] == answer.mean &&
        all(interval[String(k)] == getproperty(answer, k) for k in (:lower, :upper)) ||
        throw(ArgumentError("The answer and report describe different estimates."))
    return (; report, answer, provenance, directory=abspath(directory),
        figures=(; (kind => joinpath(abspath(directory), "figures", "$kind.svg")
            for kind in (:posterior, :diagnostics, :predictive))...))
end

"""
    FirstMFRMFigures.main(; output_parent="results/first-analysis-figures")

Verify the supplied result, copy its portable report and existing figures to a
new directory, and reopen them. This reads computed values and vector images;
it neither redraws figures nor reconstructs a native fit. CairoMakie is not needed.
"""
function main(; output_parent="results/first-analysis-figures")
    original = review()
    parent = mktempdir(mkpath(output_parent); prefix="review-", cleanup=false)
    destination = joinpath(parent, "report")
    cp(BUNDLE, destination)
    restored = review(destination)
    isequal(original.report, restored.report) && isequal(original.answer, restored.answer) ||
        error("Saved and reopened teaching results differ.")
    print(read(joinpath(destination, "answer.txt"), String))
    println("Verified report, captions and SVG/PDF figures: ", isabspath(output_parent) ? abspath(destination) : normpath(destination))
    return restored
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    isempty(ARGS) || throw(ArgumentError("Usage: first_analysis_figures.jl"))
    FirstMFRMFigures.main()
end
