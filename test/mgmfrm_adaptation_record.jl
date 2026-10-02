module MGMFRMAdaptationRecordChecks
using Test, Random, Logging, LinearAlgebra, JSON3, BayesianMGMFRM
include("../scripts/mgmfrm_adaptation_review.jl")
const R = MGMFRMAdaptationReview
const A = R.A
const B = BayesianMGMFRM

function specification()
    cells = [(p,i,r) for p in 1:3 for i in 1:4 for r in 1:3]
    data = FacetData((; person=first.(cells), item=getindex.(cells,2), rater=last.(cells),
        score=[mod(sum(c),3) for c in cells]); person=:person, item=:item,
        rater=:rater, score=:score, category_levels=0:2)
    mfrm_spec(data; family=:mgmfrm, dimensions=2, q_matrix=Bool[1 0;1 0;0 1;0 1],
        thresholds=:partial_credit)
end

read_record(directory) = JSON3.read(read(joinpath(directory,"adaptation.json"),String))

@testset "Adaptation timing and copied metric snapshots" begin
    for metric in (B.AdvancedHMC.DiagEuclideanMetric(2), B.AdvancedHMC.DenseEuclideanMetric(2))
        record = Dict{Symbol,Any}(:chains=>Dict{Symbol,Any}[])
        initial = [0.1,0.2]
        A.observe!(record,(; phase=:sampling_start,chain=1,initial_raw=initial,
            initial_sampling=initial,metric,controls=(;warmup=2,ndraws=2)))
        initial .= 99
        @test record[:chains][1][:initial_sampling] == [.1,.2]
        for i in 1:4
            i == 2 && (metric.M⁻¹ .*= 2)
            stat = (; iterations=i,is_adapt=i<=2,step_size=i/10,
                acceptance_rate=.9,log_density=-1.,n_steps=3,tree_depth=2,
                numerical_error=false,mass_matrix=metric)
            # The used step size freezes only AFTER the last warmup transition.
            i > 2 && (stat=merge(stat,(;step_size=.3)))
            A.observe!(record,(;phase=:transition,chain=1,stat))
        end
        A.observe!(record,(;phase=:sampling_end,chain=1))
        chain = only(record[:chains])
        @test getproperty.(chain[:rows],:metric_used) == [1,1,2,2]
        @test getproperty.(chain[:rows],:metric_after) == [1,2,2,2]
        @test getproperty.(chain[:metrics],:after_iteration) == [0,2]
        @test chain[:retained_kernel] == (;metric_id=2,step_size=.3,adapted=true)
        metric.M⁻¹ .*= 5
        @test chain[:metrics][2].inverse_mass_matrix == 2chain[:metrics][1].inverse_mass_matrix
        @test chain[:completed]
        @test_throws ErrorException A.observe!(record,(;phase=:transition,chain=1,
            stat=(;iterations=6,is_adapt=false)))
        mktempdir() do dir
            A.write_record(dir,record)
            restored = read_record(dir)
            @test length(restored.chains[1].metrics) == 2
            values = restored.chains[1].metrics[2].inverse_mass_matrix
            @test (metric isa B.AdvancedHMC.DiagEuclideanMetric ? collect(values) :
                reduce(vcat,permutedims.(collect.(values)))) == chain[:metrics][2].inverse_mass_matrix
        end
    end
    @test A.metric_values(B.AdvancedHMC.UnitEuclideanMetric(2)) == ones(2)
    @test A.portable_integers(typemax(UInt64)) == string(typemax(UInt64))
    @test A.portable_integers(typemin(Int64)) == string(typemin(Int64))
    @test A.portable_integers(Dict("seed"=>[typemax(Int64)]))["seed"] == [string(typemax(Int64))]
end

function run_fit_checks(parent)
    @testset "Opt-in adaptation records preserve actual MGMFRM fits and RNG" begin
        spec = specification()
        prior = B.Experimental.GeneralizedPrior(person_sd=1.3,item_sd=.7)
        base = B._mgmfrm_guarded_local_fit_logdensity(spec; prior=B._source_fixture_prior(prior))
        target = B._MGMFRMLocationLogDensity(base)
        initial = [.03sin(i) for i in 1:length(B.initial_params(base))]
        for coordinates in (:raw,:orthogonal_person_mean_item_offset),
                metric in (:diagonal,:dense,:unit), warmup in (0,120,200)
            options = (; prior,init=initial,sampling_coordinates=coordinates,metric,warmup,
                chains=2,ndraws=8,max_depth=3,init_jitter=.1,step_size=.03)
            plain_rng, recorded_rng = MersenneTwister(924301),MersenneTwister(924301)
            dir = joinpath(parent,"$(coordinates)-$(metric)-$(warmup)")
            plain, recorded = with_logger(NullLogger()) do
                (B.Experimental.fit(spec;options...,rng=plain_rng),
                 A.fit_recorded(dir,spec;options...,rng=recorded_rng))
            end
            @test isequal(plain.draws,recorded.draws)
            @test isequal(plain.log_posterior,recorded.log_posterior)
            @test isequal(plain.sampler_stats,recorded.sampler_stats)
            @test isequal(plain.sampler_controls,recorded.sampler_controls)
            @test isequal(plain.diagnostic_surface,recorded.diagnostic_surface)
            @test rand(plain_rng,10) == rand(recorded_rng,10)
            restored_fit = load_fit_cache(joinpath(dir,"fit.jls"))
            @test isequal(restored_fit.draws,recorded.draws)
            record = read_record(dir)
            @test record.status == "complete"
            @test record.fit_cache.sha256 == A.digest(joinpath(dir,"fit.jls"))
            @test record.data_signature == string(spec.validation.data_signature)
            @test record.prior.person_sd == 1.3
            @test record.environment.advancedhmc == string(Base.pkgversion(B.AdvancedHMC))
            @test record.environment.source_files_on_disk[Symbol("src/bayesian_fit.jl")] ==
                A.digest(joinpath(@__DIR__,"../src/bayesian_fit.jl"))
            @test record.coordinates.raw_names == base.blueprint.parameter_names
            @test record.controls.warmup == warmup
            @test length(record.chains) == 2
            expected_first = B._advancedhmc_initial(copy(initial),MersenneTwister(924301),.1)
            @test record.chains[1].initial_raw == expected_first
            for c in record.chains
                @test c.completed
                @test length(c.rows) == warmup+8
                @test getproperty.(c.rows,:iteration) == 1:(warmup+8)
                @test getproperty.(c.rows,:is_adapt) == [trues(warmup);falses(8)]
                @test count(r -> r.phase == "warmup", c.rows) == warmup
                @test c.retained_kernel.adapted == (warmup>0)
                expected = coordinates === :raw ? collect(c.initial_raw) :
                    B._mgmfrm_location_from_raw(target,collect(c.initial_raw))
                @test c.initial_sampling ≈ expected atol=1e-14
                @test c.metrics[1].after_iteration == 0
                # Default buffers (75 + 50) leave no mass-update window at 120.
                if metric === :unit || warmup < 150
                    @test length(c.metrics) == 1
                else
                    @test length(c.metrics) > 1 # Exercise real mass-matrix adaptation.
                end
                for r in c.rows
                    @test c.metrics[r.metric_used].after_iteration < r.iteration
                    @test c.metrics[r.metric_after].after_iteration <= r.iteration
                end
                retained = filter(r -> r.chain == c.chain,recorded.sampler_stats)
                @test getproperty.(c.rows[warmup+1:end],:step_size) == getproperty.(retained,:step_size)
                @test c.retained_kernel.step_size == first(retained).step_size
                @test all(r -> r.metric_used == r.metric_after == c.retained_kernel.metric_id,
                    c.rows[warmup+1:end])
            end
            if coordinates === :raw
                @test record.coordinates.sampling_names == record.coordinates.raw_names
                @test record.coordinates.transform === nothing
            else
                @test record.coordinates.sampling_names[base.blueprint.blocks[:person][1:2]] ==
                    ["scaled_person_mean[D1]","scaled_person_mean[D2]"]
                @test all(startswith("item_offset"),
                    record.coordinates.sampling_names[base.blueprint.blocks[:item]])
                @test record.coordinates.transform.person_reflector == target.reflector
            end
            before = A.digest(joinpath(dir,"adaptation.json"))
            reviewed = R.review(dir)
            @test reviewed.integrity == "checked"
            @test reviewed.backend == "advancedhmc"
            @test reviewed.coordinates["sampling"] == string(coordinates)
            @test reviewed.input.adaptation_sha256 == before
            @test reviewed.input.fit_cache["sha256"] == A.digest(joinpath(dir,"fit.jls"))
            for (summary, chain) in zip(reviewed.chains,record.chains)
                @test summary.warmup.iterations == warmup
                @test summary.late_warmup.iterations == ceil(Int,.2warmup)
                @test summary.retained.iterations == 8
                @test summary.metric.updates == length(chain.metrics)-1
                @test summary.metric.update_iterations == [m.after_iteration for m in chain.metrics[2:end]]
                @test summary.retained_kernel["step_size"] == chain.retained_kernel.step_size
                @test summary.retained.step_size.minimum == summary.retained.step_size.maximum ==
                    chain.retained_kernel.step_size
            end
            B._write_json_record(joinpath(dir,"review.json"),reviewed)
            @test record.fit_cache.sha256 == A.digest(joinpath(dir,"fit.jls"))
            @test_throws Base.IOError A.fit_recorded(dir,spec;options...)
            @test A.digest(joinpath(dir,"adaptation.json")) == before
        end
        failed = joinpath(parent,"failed")
        @test_throws ArgumentError A.fit_recorded(failed,spec;ndraws=0,seed=924301)
        failure = read_record(failed)
        @test failure.status == "failed"
        @test isempty(failure.chains)
        @test !isfile(joinpath(failed,"fit.jls"))
        @test !isempty(failure.error)
        @test_throws ArgumentError R.review(failed)
        @test_throws ArgumentError A.fit_recorded(joinpath(parent,"unsupported"),spec;backend=:turing)
        @test !ispath(joinpath(parent,"unsupported"))
        @test_throws ArgumentError A.fit_recorded(joinpath(parent,"override"),spec;
            _initial_transform=identity)
        @test !ispath(joinpath(parent,"override"))
    end
    B._write_json_record(joinpath(parent,"test-runtime.json"),(;julia=string(VERSION),
        advancedhmc=string(Base.pkgversion(B.AdvancedHMC)),forwarddiff=string(Base.pkgversion(B.ForwardDiff)),
        paired_conditions=18,engineering_fits=36,scientific_acceptance=false,
        test_sha256=A.digest(@__FILE__),reviewer_sha256=A.digest(joinpath(@__DIR__,"../scripts/mgmfrm_adaptation_review.jl"))))
end

if abspath(PROGRAM_FILE)==(@__FILE__) && !isempty(ARGS)
    directory=abspath(only(ARGS));mkdir(directory)
    run_fit_checks(directory)
else
    mktempdir(run_fit_checks)
end
end
