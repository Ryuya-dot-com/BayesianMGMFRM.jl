module MFRMFixedQFitChecks

using Test, BayesianMGMFRM, Random, Statistics, SHA
const B = BayesianMGMFRM
include("test_groups.jl")
include("fixtures/fixed_q_result.jl")

function check_canonical_fit(dimensions, backend, directory)
    cells = [(p,i,r) for p in 1:2 for i in 1:(2dimensions) for r in 1:3]
    data = FacetData((; person = first.(cells), item = getindex.(cells,2), rater = last.(cells),
        score = [mod(sum(cell),4) for cell in cells]); person=:person,item=:item,rater=:rater,score=:score)
    q = [cld(i,2) == d for i in 1:(2dimensions), d in 1:dimensions]
    dimensions == 2 && (q[2,2] = true)
    spec = mfrm_spec(data; dimensions, q_matrix=q, dimension_labels=["Ability $d" for d in 1:dimensions])
    prior = MFRMPrior(person_sd=0.7,rater_sd=0.4,item_sd=0.6,step_sd=0.5)
    target = B._MFRMFixedQReferenceLogDensity(spec; prior)
    identity = B._mfrm_fixed_q_identity(target)
    record_warmup = dimensions == 2
    controls = (; ndraws=12,warmup=10,chains=2,seed=9271,step_size=0.03,max_depth=4,init_jitter=0.02,record_warmup)
    options = backend === :cmdstan ? (; backend,cmdstan_cache_dir=joinpath(directory,"compile")) : (;)
    fit = if dimensions == 3
        # Derived target views are rebuilt before sampling, not trusted as another model authority.
        target.base.design.spec.q_matrix .= true
        target.blueprint.parameter_names[1] = "stale"
        B._mfrm_fixed_q_fit(B._mfrm_fixed_q_sample(target; controls...))
    else
        B.Experimental.fit(spec; prior, controls..., options...)
    end
    record, run = fit.record, fit.record.run
    @test record.schema == "bayesianmgmfrm.fixed_q_mfrm_samples.v2"
    @test record.spec.family === :mfrm && record.spec.dimensions == dimensions
    @test run.backend === backend && run.sampler === :nuts
    @test record.target_identity == identity
    @test size(run.draws) == (24,dimensions == 2 ? 18 : 26)
    @test all(isfinite,run.draws) && all(isfinite,run.logdensities)
    @test fit_metadata(fit).parameter_names == getdesign(spec; preview=true).parameter_names
    checked = B._mfrm_fixed_q_samples(fit)
    check_fixed_q_result(checked)
    @test all(row.coverage === (record_warmup ? :recorded : :not_recorded) for row in diagnostics(fit).warmup_rows)
    expected = B._MFRMFixedQReferenceLogDensity(spec; prior)
    for (params,lp) in zip(eachrow(run.draws),run.logdensities)
        @test lp ≈ B.LogDensityProblems.logdensity(expected,params) atol=1e-8
    end
    if backend === :cmdstan
        @test all(isapprox(stat.stan_lp,lp;atol=1e-8) for (stat,lp) in zip(run.sampler_stats,run.logdensities))
    end
    path = joinpath(directory,"samples.jls")
    B._save_mfrm_fixed_q_samples(path,fit)
    bytes = read(path)
    loaded = B._load_mfrm_fixed_q_samples(path; expected_identity=identity)
    restored = B._mfrm_fixed_q_fit(loaded)
    @test isequal(fit_metadata(restored),fit_metadata(fit))
    @test isequal(posterior_summary(restored),posterior_summary(fit))
    @test isequal(B.direct_posterior_summary(restored),B.direct_posterior_summary(fit))
    @test isequal(diagnostics(restored),diagnostics(fit))
    @test_throws ArgumentError B._save_mfrm_fixed_q_samples(path,fit)
    @test read(path) == bytes
    @test_throws ArgumentError B._load_mfrm_fixed_q_samples(path; expected_identity="wrong")
    @test_throws ArgumentError load_fit_cache(path)
    corrupted = B._mfrm_fixed_q_fit(loaded)
    corrupted.record.run.draws[1,1] += 0.5
    @test_throws ArgumentError B._save_mfrm_fixed_q_samples(path,corrupted;overwrite=true)
    @test read(path) == bytes
    B._save_mfrm_fixed_q_samples(path,fit;overwrite=true)
    @test B._load_mfrm_fixed_q_samples(path;expected_identity=identity).record.content_hash == record.content_hash
    report = B._mfrm_fixed_q_report(loaded;require_complete=true)
    @test report.metadata.target_identity == identity
    @test report.metadata.source_sample_schema == record.schema
    @test report.metadata.source_sample_content_hash == record.content_hash
    @test report.report_status === :complete
    for options in ((; backend=:julia),(; init=[0.0]),(; init=fill(NaN,size(run.draws,2))),
            (; backend=:advancedhmc,ndraws=0),(; backend=:cmdstan,ndraws=0,cmdstan_cache_dir=joinpath(directory,"never-compile")))
        @test_throws ArgumentError B.Experimental.fit(spec;options...)
    end
    @test !ispath(joinpath(directory,"never-compile"))
    @test_throws ArgumentError B._mfrm_fixed_q_fit(B._mfrm_fixed_q_reference_spec(spec))
    original_names = copy(fit_metadata(fit).parameter_names)
    spec.dimension_labels[1] = "changed"
    @test fit_metadata(fit).parameter_names == original_names
    B._write_json_record(joinpath(directory,"result.json"), (; julia_version=string(VERSION),
        metadata=fit_metadata(fit), posterior=posterior_summary(fit),
        model_posterior=B.direct_posterior_summary(fit),diagnostics=diagnostics(fit),
        file_sha256=bytes2hex(sha256(read(path))), scientific_acceptance=false))
end

@testset "canonical fixed-Q sampling and replay (operability only)" begin
    cases = [(2,:advancedhmc),(3,:advancedhmc)]
    test_flag("BAYESIANMGMFRM_CMDSTAN_TESTS") && push!(cases,(2,:cmdstan))
    for (dimensions,backend) in cases
        output = get(ENV,"BAYESIANMGMFRM_FIXED_Q_OUTPUT",nothing)
        run = directory -> check_canonical_fit(dimensions,backend,directory)
        output === nothing ? mktempdir(run) : run(mkpath(joinpath(output,"$backend-$dimensions")))
    end
end

end
