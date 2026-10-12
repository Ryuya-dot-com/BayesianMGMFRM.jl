# This same entry runs standalone or from the ordinary fitting_reports shard.
module CommonPredictionTests

module Comparison
include("common_prediction_comparison.jl")
common_prediction_comparison_checks()
end

module RecordedReports
include("common_prediction_report.jl")
mktempdir(common_prediction_report_checks)
end

module FixedReports
include("fixed_mfrm_prediction_report.jl")
mktempdir(fixed_mfrm_report_checks)
end

module SavedWorkflow
include("common_prediction_workflow.jl")
mktempdir(common_prediction_workflow_checks)
end

end
