using BayesianMGMFRM
using BayesianMGMFRM.Legacy
using Test

module ArchiveTeachingResult
include("../examples/first_analysis_figures.jl")
end

@testset "Distribution archive <= 5 MiB boundary & multi-version CI compatibility (FF5)" begin
    pkg_root = normpath(joinpath(@__DIR__, ".."))

    # 1. Julia 1.13+ REPL-independent Binding docstring lookup & v0.2 root surface
    @test BayesianMGMFRM._binding_doc(BayesianMGMFRM, :fit) !== nothing
    @test BayesianMGMFRM._binding_doc(BayesianMGMFRM, :qualify) !== nothing
    @test BayesianMGMFRM._binding_doc(BayesianMGMFRM, :plausible_values) !== nothing
    @test BayesianMGMFRM._binding_doc(BayesianMGMFRM, :GlassBox) !== nothing
    @test BayesianMGMFRM._binding_doc(BayesianMGMFRM, :Legacy) !== nothing
    @test BayesianMGMFRM._binding_doc(BayesianMGMFRM.Experimental, :joint_rating_spec) !== nothing
    @test BayesianMGMFRM._binding_doc(BayesianMGMFRM.StanAdapter, :fit_stan) !== nothing
    @test length(BayesianMGMFRM._root_api_contract().layer1_practitioner) == 41
    @test length(names(BayesianMGMFRM)) == 42

    # 2. ELF PT_GNU_STACK PF_X stripper self-test (Ubuntu 26.04 / Julia 1.10.8 libopenlibm.so)
    py_exe = something(Sys.which("python3"), Sys.which("python"), nothing)
    if py_exe !== nothing
        elf_script = joinpath(pkg_root, "scripts", "clear_elf_execstack.py")
        @test isfile(elf_script)
        out = read(`$py_exe $elf_script --self-test`, String)
        @test occursin("clear_elf_execstack self-test passed", out)
    end

    # 3. Actual `git archive --format=tar.gz HEAD` budget <= 5,242,880 bytes & contents boundary
    git_exe = Sys.which("git")
    tar_exe = Sys.which("tar")
    if git_exe !== nothing && tar_exe !== nothing && isfile(joinpath(pkg_root, ".gitattributes"))
        mktempdir() do tmp
            repo = joinpath(tmp, "repo")
            mkpath(repo)
            if ispath(joinpath(pkg_root, ".git"))
                vis = filter(!isempty, split(read(Cmd(`$git_exe ls-files -co --exclude-standard -z`; dir = pkg_root), String), '\0'))
                for rel in vis
                    src = joinpath(pkg_root, rel)
                    (isfile(src) || islink(src)) || continue
                    dst = joinpath(repo, rel)
                    mkpath(dirname(dst))
                    islink(src) ? symlink(readlink(src), dst) : cp(src, dst)
                end
            else
                for entry in readdir(pkg_root)
                    entry in (".git", "results", "artifacts", "data", "public-package") && continue
                    cp(joinpath(pkg_root, entry), joinpath(repo, entry))
                end
                rm(joinpath(repo, "docs", "build"); recursive = true, force = true)
            end
            hooks = joinpath(tmp, "empty-hooks")
            mkpath(hooks)
            run_git(args...) = run(pipeline(
                `$git_exe -C $repo -c core.hooksPath=$hooks -c gc.auto=0 -c maintenance.auto=false $args`;
                stdout = devnull, stderr = devnull))
            run_git("init", "-q")
            run_git("config", "user.email", "verify@example.com")
            run_git("config", "user.name", "Verify")
            run_git("add", ".")
            run_git("commit", "-qm", "snapshot")

            archive_path = joinpath(tmp, "package.tar.gz")
            run(pipeline(`$git_exe -C $repo archive --format=tar.gz HEAD`; stdout = archive_path))
            archive_bytes = filesize(archive_path)
            @test 0 < archive_bytes <= 5_242_880

            entries = Set(filter(!isempty, split(read(`$tar_exe -tzf $archive_path`, String), '\n')))
            # Essential installable & testable files present
            for required in (
                "Project.toml",
                "LICENSE",
                "README.md",
                "NEWS.md",
                ".github/workflows/CI.yml",
                "src/BayesianMGMFRM.jl",
                "src/bayesian_fit.jl",
                "src/facet_workflow/anchors_and_support.jl",
                "src/facet_workflow/coverage_and_linking.jl",
                "src/facet_workflow/data.jl",
                "src/facet_workflow/design_and_predictors.jl",
                "src/facet_workflow/design_audit.jl",
                "src/facet_workflow/domain_and_surfaces.jl",
                "src/facet_workflow/gmfrm_api_contract.jl",
                "src/facet_workflow/gmfrm_coordinates.jl",
                "src/facet_workflow/likelihood.jl",
                "src/facet_workflow/mgmfrm_api_contract.jl",
                "src/facet_workflow/mgmfrm_coordinates.jl",
                "src/facet_workflow/model_manifests.jl",
                "src/facet_workflow/model_specification.jl",
                "src/facet_workflow/model_support.jl",
                "src/facet_workflow/parameter_layout.jl",
                "src/facet_workflow/q_matrix.jl",
                "src/facet_workflow/raw_parameter_contracts.jl",
                "src/facet_workflow/release_and_provenance.jl",
                "src/facet_workflow/software_comparison.jl",
                "src/facet_workflow/validation.jl",
                "test/suites/core.jl",
                "test/suites/fitting_core.jl",
                "test/support/chain_fixtures.jl",
                "test/support/common.jl",
                "test/support/gmfrm_api.jl",
                "test/support/gmfrm_archives.jl",
                "test/support/gmfrm_comparisons.jl",
                "test/support/gmfrm_dff_and_scope.jl",
                "test/support/gmfrm_exposure.jl",
                "test/support/gmfrm_recovery.jl",
                "test/support/gmfrm_sensitivity.jl",
                "test/support/mgmfrm_agreement.jl",
                "test/support/mgmfrm_api.jl",
                "test/support/mgmfrm_benchmarks.jl",
                "test/support/mgmfrm_budgets.jl",
                "test/support/mgmfrm_external_evidence.jl",
                "test/support/mgmfrm_heldout.jl",
                "test/support/mgmfrm_publication.jl",
                "test/support/mgmfrm_q_review.jl",
                "test/support/mgmfrm_recovery.jl",
                "test/support/mgmfrm_refits.jl",
                "test/support/mgmfrm_remediation.jl",
                "test/support/scalar_validation.jl",
                "src/mfrm_core/priors_and_density.jl",
                "src/mfrm_core/hmc_sampling.jl",
                "src/mfrm_core/mcmc_diagnostics.jl",
                "src/mfrm_core/fit_reports.jl",
                "src/mfrm_core/persistence_and_summaries.jl",
                "src/mfrm_core/predictive_criteria.jl",
                "src/mfrm_core/sensitivity_and_comparisons.jl",
                "src/mfrm_core/reliability_and_facets_stats.jl",
                "src/mfrm_core/simulation_and_recovery.jl",
                "src/stan_adapter.jl",
                "src/glass_box_module.jl",
                "src/legacy_module.jl",
                "src/frequentist_mfrm.jl",
                "src/mrcml_design.jl",
                "src/mrcml_specification.jl",
                "src/mrcml_specification/inputs.jl",
                "src/mrcml_specification/blocks.jl",
                "src/mrcml_specification/finalize.jl",
                "test/mrcml_specification.jl",
                "src/mrcml_frequentist.jl",
                "docs/src/migration-stan-brms.md",
                "docs/src/assets/first-analysis/posterior.png",
                "examples/minimal.jl",
                "scripts/platform_smoke.jl",
                "test/runtests.jl",
                "test/fixtures/local_dependence_known_truth_preflight.json",
                "test/fixtures/gmfrm_guarded_fit_api_dry_run.json",
            )
                @test required in entries
            end
            # The installed teaching example must verify the complete archived bundle.
            unpacked = mkpath(joinpath(tmp, "unpacked"))
            run(`$tar_exe -xzf $archive_path -C $unpacked`)
            teaching = ArchiveTeachingResult.FirstMFRMFigures.review(
                joinpath(unpacked, "docs", "src", "assets", "first-analysis"))
            @test teaching.answer.numerically_qualified

            # Heavy gallery assets, Manifests, and opt-in study JSONs excluded
            for excluded in (
                "Manifest.toml",
                "Manifest-v1.10.toml",
                "AGENTS.md",
                "ROADMAP.md",
                "docs/internal/software-comparison.md",
                "docs/src/assets/visual-guide/mgmfrm-rater-comparison.svg",
                "examples/reports/explanatory-diagnostics/sensitivity.json",
                "test/fixtures/local_dependence_pilot_batch_execution_harness.json",
            )
                @test !(excluded in entries)
            end
        end
    end
end
