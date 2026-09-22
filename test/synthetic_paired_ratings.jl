module SyntheticPairedRatingsChecks

using Test, Random, Statistics, JSON3, SHA
include(joinpath(@__DIR__, "..", "scripts", "synthetic_paired_ratings.jl"))
const S = SyntheticPairedRatings

# A direct, high-precision normalized equation, independent of the PCM helper.
function oracle(theta, b, severity, recording, steps)
    eta = BigFloat(theta) - BigFloat(b) - BigFloat(severity) + BigFloat(recording)
    weights = [exp(h*eta - sum(BigFloat.(steps[2:h+1]); init=BigFloat(0))) for h in 0:8]
    return Float64.(weights ./ sum(weights))
end

@testset "synthetic paired-criterion application data" begin
    panel = S.generate()
    t, m = panel.truth, panel.manifest
    @test m.synthetic_data_only
    @test (m.persons, m.words, m.raters, m.categories) == (12, 37, 19, 9)
    @test m.possible_recordings == 444
    @test isequal(panel, S.generate())
    @test panel.ratings != S.generate(seed=92152).ratings
    Random.seed!(310)
    expected = rand(5)
    Random.seed!(310)
    S.generate()
    @test rand(5) == expected
    @test all(abs.(sum(t.severity; dims=1)) .< 1e-12)
    @test all(abs.(sum(t.steps[:,2:end]; dims=2)) .< 1e-12)
    @test all(iszero, t.steps[:,1])
    @test t.active_loading == t.consistency == 1.0
    @test (t.rho_person, t.rho_recording) == (0.6, 0.25)
    @test abs(t.realized_person_correlation-t.rho_person) > 1e-8
    @test any(abs.(mean(t.theta; dims=1)) .> 1e-6)
    @test m.complete_rating_count == m.assigned_recordings*19*2
    @test m.observed_rating_count+m.missing_rating_count == m.complete_rating_count
    @test 0 < m.missing_rating_count < m.complete_rating_count

    assigned = filter(r -> r.assigned, panel.recordings)
    @test length(unique(r.recording for r in panel.recordings)) == 444
    @test length(unique((r.person, r.word) for r in panel.recordings)) == 444
    @test all(count(r -> r.word == w, assigned) == 12 for w in t.word_ids[1:3])
    @test all(count(r -> r.word == w, assigned) >= 2 for w in t.word_ids[4:35])
    @test count(r -> r.word == "W036", assigned) == 1
    @test count(r -> r.word == "W037", assigned) == 2
    @test all(count(r -> r.person == p, assigned) >= 3 for p in t.person_ids)
    absent_ids = Set(r.recording for r in panel.recordings if !r.assigned)
    @test all(r.recording ∉ absent_ids for r in panel.ratings)
    @test all(count(r -> r.recording == rec.recording, t.complete_ratings) == 38 for rec in assigned)
    @test length(unique((r.recording, r.rater, r.criterion) for r in panel.ratings)) == length(panel.ratings)
    @test all(0 <= r.score <= 8 for r in panel.ratings)
    @test Set(r.score for r in panel.ratings) == Set(0:8)
    @test all(length(r.probabilities) == 9 && all(isfinite, r.probabilities) &&
        all(>=(0), r.probabilities) && isapprox(sum(r.probabilities), 1; atol=1e-14)
        for r in t.complete_ratings)

    observed_ids = Set(r.row_id for r in panel.ratings)
    @test observed_ids == Set(r.row_id for r in t.complete_ratings if r.observed)
    # Replay missingness using only its own stream, without reading any score.
    mask_rng = MersenneTwister(m.seeds.missing_rating)
    mask = [r.criterion == "weak_accent" || rand(mask_rng) >= 0.005 for r in t.complete_ratings]
    @test mask == getproperty.(t.complete_ratings, :observed)
    @test all(r.row_id+1 in observed_ids for r in t.complete_ratings if !r.observed)
    @test all(r.observed for r in t.complete_ratings if r.criterion == "weak_accent")

    p_index = Dict(id => i for (i,id) in enumerate(t.person_ids))
    w_index = Dict(id => i for (i,id) in enumerate(t.word_ids))
    r_index = Dict(id => i for (i,id) in enumerate(t.rater_ids))
    rec_index = Dict(id => i for (i,id) in enumerate(t.recording_ids))
    # Includes both criteria, sparse words, multiple persons and missing rows.
    selected = unique(vcat(collect(1:137:length(t.complete_ratings)),
        findall(r -> !r.observed || r.word in ("W036", "W037"), t.complete_ratings)))
    for i in selected
        row = t.complete_ratings[i]
        p, w, r, o = p_index[row.person], w_index[row.word], r_index[row.rater], rec_index[row.recording]
        c = findfirst(==(row.criterion), t.criteria)
        probabilities = oracle(t.theta[p,c], t.b[w,c], t.severity[r,c], t.recording_effect[o,c], t.steps[c,:])
        @test row.probabilities ≈ probabilities atol=2e-14 rtol=2e-14
        # Recover the single recording effect from every selected rater's odds.
        recovered_u = log(row.probabilities[2]/row.probabilities[1]) -
            t.theta[p,c] + t.b[w,c] + t.severity[r,c] + t.steps[c,2]
        @test recovered_u ≈ t.recording_effect[o,c] atol=2e-13
    end
    @test oracle(0, 0, 0, 0, zeros(9)) ≈ fill(1/9, 9)
    @test sum((0:8) .* oracle(1, 0, 0, 0, zeros(9))) > 4
    # Check the sampler independently via cumulative probabilities and its RNG.
    rng = MersenneTwister(m.seeds.response)
    sampled = [something(findfirst(>(rand(rng)), cumsum(row.probabilities)), 9)-1
        for row in t.complete_ratings]
    @test sampled == getproperty.(t.complete_ratings, :score)

    mktempdir() do parent
        directory = joinpath(parent, "example")
        saved = S.write_example(directory)
        @test isequal(saved, panel)
        manifest = JSON3.read(read(joinpath(directory, "manifest.json"), String))
        @test Set(readdir(directory)) == Set(["ratings.json", "recordings.json", "truth.json", "manifest.json"])
        @test manifest.julia_version == string(VERSION)
        for f in manifest.files
            bytes = read(joinpath(directory, f.name))
            @test length(bytes) == f.bytes
            @test bytes2hex(sha256(bytes)) == f.sha256
        end
        rows = JSON3.read(read(joinpath(directory, "ratings.json"), String))
        truth = JSON3.read(read(joinpath(directory, "truth.json"), String))
        @test getproperty.(rows, :score) == getproperty.(panel.ratings, :score)
        @test length(truth.theta) == m.persons
        @test all(collect(truth.theta[p]) == vec(t.theta[p,:]) for p in 1:m.persons)
        @test all(collect(truth.steps[c]) == vec(t.steps[c,:]) for c in 1:2)
        @test all(!hasproperty(row, :probabilities) && !hasproperty(row, :observed) for row in rows)
        before = read(joinpath(directory, "manifest.json"))
        @test_throws ArgumentError S.write_example(directory)
        @test read(joinpath(directory, "manifest.json")) == before
        @test_throws ArgumentError S.write_example(joinpath(parent, "bad"); persons=1)
        @test !ispath(joinpath(parent, "bad"))
    end
    for n in (true, 3, 49, 12.0)
        @test_throws ArgumentError S.generate(persons=n)
    end
    for bad_seed in (true, -1, typemax(Int), 1.0)
        @test_throws ArgumentError S.generate(seed=bad_seed)
    end
    # A new population has its own people; ratings are not copied from 12 people.
    larger = S.generate(persons=48)
    @test length(unique(r.person for r in larger.ratings)) == 48
    @test size(larger.truth.theta) == (48, 2)
    @test length(unique(eachrow(larger.truth.theta))) == 48
end

end # module
