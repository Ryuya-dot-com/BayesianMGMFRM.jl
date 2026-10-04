module MGMFRMFoundationOracle
using BayesianMGMFRM, JSON3, LinearAlgebra, Statistics, SHA, Test
const B = BayesianMGMFRM
include("mgmfrm_core_recovery_review.jl")
include("mgmfrm_core_interval_review.jl")
const R = MGMFRMCoreRecoveryReview
const Q = Bool[1 0; 1 0; 0 1; 0 1; 0 1]
const SCALES = (; person_sd=1., rater_sd=sqrt(2.), item_sd=1.,
    log_discrimination_sd=.5, log_consistency_sd=sqrt(2.)/2, step_sd=sqrt(2.))
const CONTROLS = (; chains=4, warmup=1000, ndraws=1000, seed=26092703,
    target_accept=.9, max_depth=10, metric=:diagonal, init_jitter=.1,
    rhat_threshold=1.01, ess_threshold=400., progress=false)
digest(path) = bytes2hex(sha256(read(path)))

function prepare(input)
    x = JSON3.read(read(input, String))
    assessment = x.schema == "mgmfrm.foundation_fixed_facet_assessment_input.v1"
    fixed = assessment || x.schema == "mgmfrm.foundation_fixed_facet_input.v1"
    (fixed || x.schema == "mgmfrm.foundation_oracle_input.v1") || error("Wrong input schema")
    Dict(String(k)=>Float64(v) for (k,v) in pairs(x.scales)) ==
        Dict(String(k)=>v for (k,v) in pairs(SCALES)) || error("Wrong scales")
    if fixed
        if assessment
            x.scope == "prospective_fixed_facet_assessment" && x.evaluation_credit === 1 &&
                x.scientific_acceptance === false && x.block isa Integer &&
                !(x.block isa Bool) && x.block > 0 &&
                occursin(r"^[A-Za-z0-9][A-Za-z0-9_-]*$",x.assessment_id) ||
                error("Wrong assessment scope")
        else
            x.scope == "engineering_fixed_facet_rehearsal" && x.evaluation_credit == 0 &&
                x.scientific_acceptance === false || error("Wrong fixed-facet scope")
        end
        x.condition in ("R0", "R1") || error("Wrong fixed-facet condition")
        !haskey(x,:log_prior) && !haskey(x,:candidate_id) || error("Legacy raw metadata is not a normalized target")
        x.generator_sha256 == digest(joinpath(@__DIR__,"mgmfrm_core_reference.py")) ||
            error("Fixed-facet generator changed")
        raw = Float64.(x.raw_truth)
        length(raw)==128 && all(isfinite,raw) || error("Wrong truth coordinates")
        loading = x.condition == "R0" ? [.7,1.3,.7,1.,1.3] : [.35,.5,.7,1.,1.3]
        expected = [-.8,-.4,0.,.4,-1.,-.5,0.,.5,1.,log.(loading)...,
            -.4,-.2,0.,.2,repeat([-.8,0.],5)...]
        isapprox(raw[101:128],expected;atol=1e-14,rtol=0) || error("Fixed facets do not match the declared condition")
    end
    rows = x.observations
    data = FacetData((; person=String[r.person for r in rows], item=String[r.item for r in rows],
        rater=String[r.rater for r in rows], score=Int[r.score for r in rows]);
        person=:person, item=:item, rater=:rater, score=:score, category_levels=1:4)
    @assert data.n == 1250 && length(Set(zip(data.person,data.item,data.rater))) == 1250
    @assert data.person_levels == sort(["P$i" for i in 1:50])
    @assert data.item_levels == ["I$i" for i in 1:5] && data.rater_levels == ["R$i" for i in 1:5]
    if fixed
        String.(x.ordered_ids.person)==data.person_levels &&
            String.(x.ordered_ids.item)==data.item_levels &&
            String.(x.ordered_ids.rater)==data.rater_levels || error("Truth/observation ID order mismatch")
    end
    spec = mfrm_spec(data; family=:mgmfrm, dimensions=2, thresholds=:partial_credit, q_matrix=Q)
    prior = B.Experimental.NormalizedMGMFRMPrior(; prior_model=:exchangeable, SCALES...)
    target = B._normalized_mgmfrm_target(spec, prior)
    return (; x, spec, prior, target)
end

function check_reference(target, x)
    raw = Float64.(x.raw_truth)
    z(v) = vec(R.location_moments(target.base, permutedims(v)).conditional_output[:,7:8])
    errors = Float64[]
    @testset "Normalized C location oracle and independent response equations" begin
        @test B.LogDensityProblems.dimension(target) == 128
        direct = B._mgmfrm_source_constrained_params_from_unconstrained(target.base.design, raw)
        p = B._mgmfrm_predictive_probabilities_direct(target.base.design, permutedims(direct))[1,:,:]
        @test p ≈ reduce(vcat, permutedims.(Vector{Float64}.(x.probabilities))) atol=1e-12
        # Vary nuisance configurations as well as location; full normalized
        # target density differences must equal standard-normal log ratios.
        for v in (raw, zeros(128), .3 .* sin.(collect(1:128))), shift in
                ([.2,-.3], [-1.,.7], [2.,-1.5])
            A = Float64.(Q) .* exp.(v[110:114])
            moved = copy(v)
            moved[1:100] .+= repeat(shift, 50)
            moved[105:109] .+= A*shift
            actual = B.LogDensityProblems.logdensity(target,moved)-B.LogDensityProblems.logdensity(target,v)
            expected = -.5*(sum(abs2,z(moved))-sum(abs2,z(v)))
            push!(errors, abs(actual-expected))
            @test actual ≈ expected atol=1e-8 rtol=1e-10
        end
    end
    return (; maximum_density_difference_error=maximum(errors), truth_z=z(raw))
end

function run(input, output)
    ispath(output) && error("Output directory must be new")
    prepared = prepare(input)
    (; x, spec, prior, target) = prepared
    reference = check_reference(target,x)
    sources = filter(p->endswith(p,".jl") || endswith(p,".stan"),
        [joinpath(d,f) for (d,_,files) in walkdir(joinpath(@__DIR__,"..","src")) for f in files])
    append!(sources, [@__FILE__, joinpath(@__DIR__,"mgmfrm_core_recovery_review.jl"),
        joinpath(@__DIR__,"mgmfrm_core_location_conditional.jl"),
        joinpath(@__DIR__,"mgmfrm_core_interval_review.jl")])
    hashes = Dict(relpath(p,dirname(@__DIR__))=>digest(p) for p in sources)
    mkpath(output)
    writejson(name,value) = B._write_json_record(joinpath(output,name),value)
    writejson("protocol.json", (; input=abspath(input), input_sha256=digest(input),
        prior=B._mgmfrm_normalized_prior_record(target), controls=CONTROLS, backend=:cmdstan,
        target_identity=B._mgmfrm_normalized_prior_identity(target), source_sha256=hashes,
        reference, maximum_fits=1, retries=0, initialization=:zero_plus_truth_independent_jitter,
        multipliers=(2.,4.), quantile_ess_floor=400., diagnostic_failure=:all_unresolved,
        scientific_acceptance=false, scope=:one_dataset_two_exact_location_pivots))
    try
        fit = B.Experimental.fit(spec; prior, backend=:cmdstan, CONTROLS...,
            init=zeros(128), cmdstan_cache_dir=joinpath(output,"compile"))
        B._save_serialized_record(joinpath(output,"samples.jls"),fit.record)
        diagnostic = diagnostics(fit)
        raw = fit.record.run.draws
        moments = R.location_moments(target.base,raw)
        z = moments.conditional_output[:,7:8]
        names = ["location_z_D1","location_z_D2"]
        precision = MGMFRMCoreIntervalReview.quantile_precision(z; parameter_names=names,chains=4)
        extra = B._candidate_mcmc_diagnostic_rows(moments.values,moments.names,4;
            split_chains=true,rhat_threshold=1.01,ess_threshold=400.)
        qualified = diagnostic.summary.passed && all(r->r.flag===:ok,extra) &&
            all(r->isfinite(r.e_bfmi) && r.e_bfmi>=.3,fit.record.run.sampler_rows)
        writejson("oracle-input.json", (; z_columns=[z[:,d] for d in 1:2], precision,
            qualified, diagnostic=diagnostic.summary, location_diagnostics=extra,
            truth_z=reference.truth_z, samples_sha256=digest(joinpath(output,"samples.jls")),
            moment_mcse=B.posterior_mcse(moments.values;chains=4,parameter_names=moments.names,probabilities=())))
        writejson("diagnostics.json",diagnostic)
        @assert all(digest(joinpath(dirname(@__DIR__),p))==h for (p,h) in hashes)
        println("Completed one fit; diagnostic qualification: ",qualified)
    catch err
        writejson("failure.json", (; error=sprint(showerror,err), completed=false, retry=false))
        rethrow()
    end
end
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("usage: run_mgmfrm_foundation_oracle.jl INPUT.json NEW_OUTPUT_DIRECTORY")
    MGMFRMFoundationOracle.run(ARGS...)
end
