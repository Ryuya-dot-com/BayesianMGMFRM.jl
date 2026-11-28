using Test, BayesianMGMFRM
include(joinpath(@__DIR__, "..", "scripts", "public_language_gate.jl"))

@testset "Reader-facing documentation preserves limits without study work orders" begin
    policy = PublicLanguageGate
    for text in ("Stage-A review is pending", "Stage A draft", "LD1b1 pilot",
            "MS3 remains open", "MP1", "does not change frozen cohorts",
            "execution-protocol authorization", "independent threshold review",
            "P2-3 pilot", "CR5 remains open", "U4 review",
            "pending recovery and coverage gates")
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
    help(name) = replace(sprint(show, MIME"text/plain"(), BayesianMGMFRM._binding_doc(BayesianMGMFRM, name)), r"\s+" => " ")
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
    sbc_help = sprint(show, MIME"text/plain"(), Docs.doc(Docs.Binding(
        BayesianMGMFRM.Experimental.RecoveryPlanning, :prepare_sbc)))
    @test occursin("simulation-based calibration", sbc_help)
    @test isempty(policy.runtime_language_violations(["SBC help" => sbc_help]))
end

@testset "R documentation shares the public-language boundary" begin
    root = normpath(joinpath(@__DIR__, ".."))
    paths = PublicLanguageGate.public_surface_paths(root)
    @test joinpath(root, "interfaces", "R", "BayesianMGMFRM", "README.md") in paths
    @test joinpath(root, "interfaces", "R", "BayesianMGMFRM", "man", "fit_mgmfrm.Rd") in paths
    mktempdir() do temp
        mkpath(joinpath(temp, "examples"))
        write(joinpath(temp, "examples", "example.jl"), "# Example\n")
        mkpath(joinpath(temp, "docs", "src"))
        for page in PublicLanguageGate.PUBLIC_DOCUMENTATION_PAGES
            write(joinpath(temp, "docs", "src", page), "# Guide\n")
        end
        for file in ("README.md", "NEWS.md")
            write(joinpath(temp, file), "# Package\n")
        end
        r_root = joinpath(temp, "interfaces", "R", "BayesianMGMFRM")
        mkpath(joinpath(r_root, "man"))
        write(joinpath(r_root, "README.md"), "# R interface\n")
        help = joinpath(r_root, "man", "example.Rd")
        write(help, "\\description{See docs/internal/study.md for P2-3 approval.}\n")
        hits = PublicLanguageGate.public_language_violations(temp)
        @test any(h -> h.rule === :study_process_wording && endswith(h.path, "example.Rd"), hits)
        @test any(h -> h.rule === :developer_artifact_path, hits)
        write(help, "\\description{Inspect posterior probabilities and Monte Carlo error.}\n")
        @test isempty(PublicLanguageGate.public_language_violations(temp))
    end
    @test !isempty(PublicLanguageGate.runtime_language_violations(
        ["help" => "See results/workflows/study/report.json"]))
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
