using BayesianMGMFRM
using Test

@testset "Distribution archive <= 5 MiB boundary & multi-version CI compatibility (FF5)" begin
    pkg_root = normpath(joinpath(@__DIR__, ".."))

    # 1. Julia 1.13+ REPL-independent Binding docstring lookup
    @test BayesianMGMFRM._binding_doc(BayesianMGMFRM, :fit) !== nothing
    @test BayesianMGMFRM._binding_doc(BayesianMGMFRM, :qualify) !== nothing
    @test BayesianMGMFRM._binding_doc(BayesianMGMFRM.Experimental, :joint_rating_spec) !== nothing
    @test BayesianMGMFRM._binding_doc(BayesianMGMFRM.StanAdapter, :fit_stan) !== nothing

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
            cp(pkg_root, repo)
            rm(joinpath(repo, ".git"); recursive = true, force = true)
            rm(joinpath(repo, "docs", "build"); recursive = true, force = true)
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
                "src/stan_adapter.jl",
                "src/frequentist_mfrm.jl",
                "src/mrcml_design.jl",
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
            # Heavy gallery assets, Manifests, and opt-in study JSONs excluded
            for excluded in (
                "Manifest.toml",
                "Manifest-v1.10.toml",
                "docs/src/assets/visual-guide/mgmfrm-rater-comparison.svg",
                "examples/reports/explanatory-diagnostics/sensitivity.json",
                "test/fixtures/local_dependence_pilot_batch_execution_harness.json",
            )
                @test !(excluded in entries)
            end
        end
    end
end
