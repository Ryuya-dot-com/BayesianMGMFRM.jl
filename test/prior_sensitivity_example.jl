module PriorSensitivityExampleChecks
using Test, BayesianMGMFRM, SHA
const B = BayesianMGMFRM
include("common_prediction_fixtures.jl")
include("../examples/prior_sensitivity.jl")
const E = PriorSensitivityExample

function checks(directory)
    @testset "User-owned saved prior comparison" begin
        # Deterministic artificial draws test plumbing, not statistical recovery.
        record = F.synthetic_record(F.target())
        narrow = normalized_fixture(record)
        target = B._MGMFRMNormalizedPriorLogDensity(record.spec; prior_model=:exchangeable,
            scales=merge(record.prior.scales, (;log_discrimination_sd=.8)))
        wide = normalized_fixture(record; target)
        inventory = B.recovery_quantities(narrow).rows
        persons = [r.parameter for r in inventory if r.block === :person && r.dimension == 1]
        args = (;planned_prior_ids=["Narrow", "Wide", "Failed", "Missing"],
            failures=["Failed" => "Declared fixture failure"], dataset_id="artificial-example-check",
            observation_ids=["row-$i" for i in 1:record.spec.data.n],
            estimands=["Ability contrast" => (persons[1], persons[2])],
            interval=.99, cutoffs=Dict("Ability contrast"=>0.), max_mcse=.01)
        paths = ["Narrow"=>joinpath(directory,"narrow.jls"), "Wide"=>joinpath(directory,"wide.jls")]
        save_fit_cache(last(paths[1]), narrow); save_fit_cache(last(paths[2]), wide)
        hashes = [bytes2hex(open(sha256, path)) for (_, path) in paths]
        output = joinpath(directory,"comparison")
        result = E.run_saved_example(paths, output; args...)
        expected = B.prior_sensitivity(["Narrow"=>narrow,"Wide"=>wide];args...)
        @test isequal(result, expected)
        @test isequal(B.load_prior_sensitivity(joinpath(output,"result.jls")), expected)
        @test getproperty.(result.ledger,:status) == [:warning,:warning,:failed,:missing]
        @test result.ledger[3].reason == "Declared fixture failure"
        @test result.interval_probability == .99
        @test result.max_mcse == .01
        @test result.new_fits == 0 && result.scientific_acceptance === :not_established
        @test !isempty(result.changes) && all(c -> !c.paired_draws,result.changes)
        source = B.JSON3.read(read(joinpath(output,"sources.json"),String))
        @test source.result_hash == result.content_hash
        @test source.planned_prior_ids == args.planned_prior_ids
        @test [s.sha256 for s in source.sources] == hashes
        @test [s.path for s in source.sources] == abspath.(last.(paths))
        output_hashes = Dict(p=>bytes2hex(open(sha256,joinpath(output,p))) for p in readdir(output))
        @test_throws ArgumentError E.run_saved_example(paths,output;args...)
        @test output_hashes == Dict(p=>bytes2hex(open(sha256,joinpath(output,p))) for p in readdir(output))
        destination = joinpath(directory,"not-created")
        @test_throws ArgumentError E.run_saved_example(["Narrow"=>joinpath(directory,"absent.jls")],destination;args...)
        @test !ispath(destination)
        @test_throws ArgumentError E.run_saved_example("old-private-repository-path",destination;args...)
        @test !ispath(destination)
        @test_throws ArgumentError E.run_saved_example([paths[1],paths[1]],destination;args...)
        @test !ispath(destination)
        @test_throws ArgumentError E.run_saved_example(paths,destination;args...,baseline="Unplanned")
        @test !ispath(destination)
        @test_throws ArgumentError E.run_saved_example(paths,destination;
            merge(args,(;observation_ids=fill("duplicate",record.spec.data.n)))...)
        @test !ispath(destination)
        @test_throws ArgumentError E.run_saved_example(paths,destination;
            merge(args,(;estimands=["Unknown"=>"not-a-coordinate"]))...)
        @test !ispath(destination)
        write(destination,"retain this file")
        @test_throws ArgumentError E.run_saved_example(paths,destination;args...)
        @test read(destination,String) == "retain this file"
        @test hashes == [bytes2hex(open(sha256,path)) for (_,path) in paths]
    end
end
end
