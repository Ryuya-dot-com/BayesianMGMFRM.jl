using Test, BayesianMGMFRM
include(joinpath(@__DIR__, "..", "scripts", "public_language_gate.jl"))

@testset "Reader-facing documentation preserves limits without study work orders" begin
    policy = PublicLanguageGate
    for text in ("Stage-A review is pending", "Stage A draft", "LD1b1 pilot",
            "MS3 remains open", "MP1", "does not change frozen cohorts",
            "execution-protocol authorization", "independent threshold review")
        @test any(r -> r.rule === :study_process_wording,
            policy.runtime_language_violations(["help" => text]))
    end
    for text in ("profile = :analysis is not implemented in this version",
            "status == :stage_a_draft_execution_blocked",
            "readiness.blockers lists missing study components",
            "No parameter-recovery or calibration evidence is supplied",
            "Prior sensitivity and independent evaluation remain necessary",
            "Fit diagnostics include R-hat, ESS and Monte Carlo uncertainty")
        @test isempty(policy.runtime_language_violations(["help" => text]))
    end
    root = normpath(joinpath(@__DIR__, ".."))
    @test policy.check_public_language(root).passed
    help(name) = replace(sprint(show, MIME"text/plain"(), Docs.doc(getfield(BayesianMGMFRM,name))), r"\s+" => " ")
    fitting = help(:mgmfrm_response_stress_fit_attempts)
    @test occursin("not implemented in this version", fitting)
    @test occursin("four retained draws in one chain", fitting)
    @test occursin("does not assess convergence", fitting)
    for name in (:mgmfrm_response_stress_fit_attempts, :mgmfrm_response_stress_preflight,
            :mgmfrm_validation_protocol, :mgmfrm_validation_analysis_contract,
            :mgmfrm_predictive_recovery_score, :local_dependence_calibration_pilot_contract,
            :local_dependence_calibration_pilot_check, :local_dependence_calibration_pilot_preflight)
        @test isempty(policy.runtime_language_violations([String(name) => help(name)]))
    end
    protocol = help(:mgmfrm_validation_protocol)
    @test occursin("stage_a_draft_execution_blocked", protocol)
    @test occursin("readiness.blockers", protocol)
    @test occursin("does not simulate data or fit models", protocol)
    @test occursin("infinite log-score regret", help(:mgmfrm_predictive_recovery_score))
end

@testset "Downloadable summaries omit working-directory paths" begin
    mktempdir() do root
        assets=joinpath(root,"docs","src","assets");mkpath(assets)
        path=joinpath(assets,"summary.json")
        write(path,"{\"path\":\"results/workflows/example/samples.jls\"}")
        @test length(PublicLanguageGate.documentation_asset_path_violations(root))==1
        write(path,"{\"source_sha256\":\"abc\",\"sampling_warning\":true}")
        @test isempty(PublicLanguageGate.documentation_asset_path_violations(root))
    end
end
