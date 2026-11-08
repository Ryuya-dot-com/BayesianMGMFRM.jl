if ARGS == ["--help"]
    println("Usage: julia --project=. examples/joint_ratings_saved.jl SAMPLES.jls REQUEST.json NEW_OUTPUT.json")
    println("Request: operation ('predict' or 'score'), response_effect ('existing' or 'new'), rows.")
    println("Rows: seven rating IDs and fitted numeric predictors; score additionally requires integer raw score.")
    println("No fitting or random generation. Use trusted samples and their original Julia/dependency environment.")
    println("Warnings and failed precision/integration checks remain in the report. This is not heldout validation.")
    exit()
end
length(ARGS) == 3 || error("Use --help for usage")
using BayesianMGMFRM
using BayesianMGMFRM: JSON3
const J = BayesianMGMFRM.Experimental.JointRatings
samples, request_path, destination = ARGS
(ispath(destination) || islink(destination)) && error("Choose a new output file")
request = JSON3.read(read(request_path, String))
Set(keys(request)) == Set((:operation, :response_effect, :rows)) ||
    error("Declare operation, response_effect and rows")
request.operation in ("predict", "score") || error("operation must be predict or score")
rows = [(; (Symbol(k) => v for (k,v) in pairs(row))...) for row in request.rows]
result = J.load_result(samples)
operation = request.operation == "predict" ? J.predict : J.score
report = operation(result, rows; response_effect=Symbol(request.response_effect))
J.save_report(destination, report)
println("Saved $(request.operation) report; $(report.result.summary.computationally_qualified) quantities computationally qualified.")
println("Source warnings remain. Scientific acceptance and heldout validation are not established.")
