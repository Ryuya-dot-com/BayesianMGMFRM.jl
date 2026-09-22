using Test
include(joinpath(@__DIR__,"..","scripts","run_mgmfrm_core_rehearsal.jl"))
const R=MGMFRMCoreRehearsal
const E=R.E
const P=R.P
const B=R.B
contract,root=ARGS
c=R.checked_contract(contract)
jobs=R.prepare_all(contract,joinpath(root,"prepared-targets.json"))
records=NamedTuple[]

@testset "Exact full and heldout training targets for twelve fixed slots" begin
    @test length(jobs)==12
    for j in jobs
        @test j.preflight.passed && j.spec.data.n==(j.fold===nothing ? 1250 : 1000)
        @test j.spec.q_matrix==P.Q && j.spec.data.category_levels==collect(1:4)
        @test j.spec.data.person_levels==P.PERSONS
        t=P.target(j.spec)
        @test length(t.blueprint.parameter_names)==128 && isfinite(B.LogDensityProblems.logdensity(t,zeros(128)))
        if j.fold!==nothing
            f=only(filter(f -> f.fold==j.fold,j.split.folds.fold_rows))
            @test isempty(intersect(f.training_observations,f.heldout_observations))
            @test sort([f.training_observations;f.heldout_observations])==collect(1:1250)
            @test B.design_identity(t.design).value!=B.design_identity(P.target(P.specification(j.input.observed)).design).value
        end
    end
    for k in 3:2:11
        a,b=jobs[k:k+1]
        @test a.split.folds.fold_rows==b.split.folds.fold_rows
    end
    @test jobs[1].input.truth.raw[1:100]==jobs[2].input.truth.raw[1:100]
end

@testset "Unreviewed plan cannot reach sampler or produce a fit-start marker" begin
    called=Ref(false)
    sampler(args...;kwargs...)=(called[]=true;error("Sampler must not run"))
    @test_throws ArgumentError R.fit_job(contract,first(jobs).job_id,joinpath(root,"forbidden-fit");sampler)
    @test !called[] && !ispath(joinpath(root,"forbidden-fit"))
    bad=merge((;c...),(;jobs=c.jobs[1:11]))
    @test_throws Exception R.prepare_job(bad,"unplanned")
end

@testset "Observed operational failures enter original study slots" begin
    for j in jobs[[1,3]],stage in (:fit,:score)
        for status in (:wall_limit,:wall_limit_before_launch,:rss_limit,:output_limit,:interrupted,
                       :command_failed,:observation_unavailable,:controller_error,:unjoined_descendants)
            receipt=(;status,launched=true,exit_code=-15,cleanup=(;observed_live_survivors=Int[]))
            failure=R.guard_failure(j,receipt;stage)
            expected=status in (:wall_limit,:wall_limit_before_launch) ? :timeout :
                status===:command_failed ? (stage===:fit ? :fit_error : :scoring_error) : :interrupted
            @test failure.status===expected && failure.id==j.input.id
            @test E.check_seal(failure)==failure
        end
        @test R.guard_failure(j,nothing;stage)===nothing
        @test R.guard_failure(j,(;status=:interrupted,launched=true,exit_code=nothing);stage)===nothing
        @test R.guard_failure(j,(;status=:cleanup_incomplete,launched=true,exit_code=-9);stage)===nothing
        @test R.guard_failure(j,(;status=:completed,launched=true,exit_code=0);stage)===nothing
    end
    j=jobs[3]
    fail=R.guard_failure(j,(;status=:wall_limit,launched=true,exit_code=-15);stage=:fit)
    R.save_attempt(joinpath(root,"stopped-fold"),fail)
    restored=E.deserialize(joinpath(root,"stopped-fold","attempt.jls"))
    cv=E.assemble_cv(j.plan,j.input,j.split,[restored])
    @test cv.status===:incomplete && cv.planned_folds==5 && cv.usable_folds==0
    @test getproperty.(cv.ledger,:status)==[:timeout;fill(:missing_attempt,4)]
    @test_throws ErrorException R.save_attempt(joinpath(root,"stopped-fold"),fail)
    full=R.guard_failure(jobs[1],(;status=:command_failed,launched=true,exit_code=1);stage=:fit)
    recovery=E.summarize_recovery(jobs[1].plan,[full];parameter="b[I1]")
    @test recovery.planned==1 && recovery.usable==0 && recovery.unresolved==1
    @test recovery.all_attempt_coverage_bounds==(0.,1.)
    push!(records,(;scope=:synthetic_receipt_mapping,cv,recovery))
end

@testset "Wrong cached fit never becomes a planned recovery or CV result" begin
    old=joinpath("results/workflows/20260921-core-generator-01/pilot-01/advancedhmc","fit.jls")
    reference=(;path=old,sha256=P.digest(old),seed=9220101)
    for j in jobs[[1,3]]
        failed=R.score_job(j,reference,joinpath(root,j.job_id*"-wrong-seed"))
        @test failed.status===:scoring_error && occursin("seed",failed.detail)
        # Same declared seed cannot disguise mismatched data or saved RNG identity.
        disguised=merge(reference,(;seed=j.fit_seed))
        failed=R.score_job(j,disguised,joinpath(root,j.job_id*"-wrong-target"))
        @test failed.status===:scoring_error && occursin("bound training target",failed.detail)
    end
end
P.writejson(joinpath(root,"tests.json"),(;tests_passed=true,records,new_sampler_runs=0,cv_refits=0,
    formal_recovery_replications=0,scientific_acceptance=false))
