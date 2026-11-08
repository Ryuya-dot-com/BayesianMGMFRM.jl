using BayesianMGMFRM

# Artificial data for learning the input contract, not a recommended study size.
ratings = (
    student = ["P1", "P1", "P1", "P1", "P2", "P2", "P2", "P2"],
    item = ["I1", "I1", "I2", "I2", "I1", "I1", "I2", "I2"],
    rater = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
    score = [0, 1, 2, 0, 1, 2, 0, 2],
)
data = FacetData(ratings; person = :student, item = :item,
    rater = :rater, score = :score, category_levels = 0:2)
println("Ratings: ", data.n, "; people: ", length(data.person_levels),
    "; items: ", length(data.item_levels), "; raters: ", length(data.rater_levels))
println("Intended categories: ", data.category_levels)

report = validate_design(data)
println(report)
for issue in report.issues
    println(issue.severity, ": ", issue.message)
end
report.passed || error("Resolve the reported design errors before specifying a model.")

spec = mfrm_spec(data; thresholds = :partial_credit, validation_report = report)
show(stdout, MIME"text/plain"(), spec)
println()
println("Category log weights (k indexes categories starting at 1):")
println(model_equation(spec).kernel)
println("No model was fitted and no files were written. Review priors before fitting.")
println("For the next step, follow the manual's First MFRM analysis: examples/first_analysis.jl.")
