module SyntheticPairedRatings

using Random, Statistics, SHA
import BayesianMGMFRM as B

"""
    generate(; seed=92151, persons=12)

Generate one wholly synthetic, paired-criterion pronunciation example. All 37
words, 19 raters, scores and assignment positions are artificial. The illustrative
constants below are generating values, not estimated quantities or fitting priors.
This implements the proposed A0 response equation; it does not fit that model.
"""
function generate(; seed=92151, persons=12)
    seed isa Integer && !(seed isa Bool) && 0 <= seed <= typemax(Int)-6 ||
        throw(ArgumentError("seed must be an integer between 0 and typemax(Int)-6"))
    persons isa Integer && !(persons isa Bool) && 4 <= persons <= 48 ||
        throw(ArgumentError("persons must be an integer between 4 and 48 for this example"))
    persons, seed = Int(persons), Int(seed)
    words, raters, categories = 37, 19, 9
    criteria = ["ease_of_understanding", "weak_accent"]
    person_ids = ["P" * lpad(p, 3, '0') for p in 1:persons]
    word_ids = ["W" * lpad(w, 3, '0') for w in 1:words]
    rater_ids = ["R" * lpad(r, 3, '0') for r in 1:raters]
    seeds = (; assignment=seed, person=seed+1, word=seed+2, rater=seed+3,
        recording=seed+4, response=seed+5, missing_rating=seed+6)

    # Assignment is independent of abilities, recording effects and responses.
    assignment_rng = MersenneTwister(seeds.assignment)
    assigned = rand(assignment_rng, persons, words) .< 0.7
    assigned[:, 1:3] .= true # connected person-word graph
    for w in 4:words-2
        if count(assigned[:, w]) < 2
            assigned[:, w] .= false
            assigned[randperm(assignment_rng, persons)[1:2], w] .= true
        end
    end
    for (w, n) in ((words-1, 1), (words, 2))
        assigned[:, w] .= false
        assigned[randperm(assignment_rng, persons)[1:n], w] .= true
    end

    rho_person, rho_recording = 0.6, 0.25
    recording_sd = [0.45, 0.6]
    rater_kernel_sd = [0.4, 0.55]
    # Retain random population draws without empirical recentering/rescaling.
    theta = randn(MersenneTwister(seeds.person), persons, 2)
    theta[:, 2] = rho_person .* theta[:, 1] .+ sqrt(1-rho_person^2) .* theta[:, 2]
    b = 0.65 .* randn(MersenneTwister(seeds.word), words, 2)
    severity = randn(MersenneTwister(seeds.rater), raters, 2) .* permutedims(rater_kernel_sd)
    severity .-= mean(severity; dims=1)
    u = randn(MersenneTwister(seeds.recording), persons*words, 2)
    u[:, 2] = rho_recording .* u[:, 1] .+ sqrt(1-rho_recording^2) .* u[:, 2]
    u .*= permutedims(recording_sd)
    steps = [0.0 collect(range(-1.4, 1.4; length=categories-1))';
             0.0 collect(range(-1.0, 1.0; length=categories-1))']
    steps[:, 2:end] .-= mean(steps[:, 2:end]; dims=2)

    recordings = [(; recording="S" * lpad((p-1)*words+w, 4, '0'),
        person=person_ids[p], word=word_ids[w], assigned=assigned[p,w])
        for p in 1:persons for w in 1:words]
    response_rng = MersenneTwister(seeds.response)
    missing_rng = MersenneTwister(seeds.missing_rating)
    ratings, complete_ratings = NamedTuple[], NamedTuple[]
    for (omega, recording) in enumerate(recordings)
        recording.assigned || continue
        p, w = div(omega-1, words)+1, mod(omega-1, words)+1
        for r in 1:raters, c in 1:2
            location = theta[p,c] - b[w,c] - severity[r,c] + u[omega,c]
            probabilities = B._ld1_pcm_probabilities(location, vec(steps[c,2:end]))
            score = B._ld1_inverse_cdf(rand(response_rng), probabilities, 0:categories-1)
            observed = c == 2 || rand(missing_rng) >= 0.005
            row = (; row_id=length(complete_ratings)+1, recording=recording.recording,
                person=recording.person, word=recording.word, rater=rater_ids[r],
                criterion=criteria[c], item=word_ids[w] * ":C$c", score)
            push!(complete_ratings, (; row..., observed, probabilities))
            observed && push!(ratings, row)
        end
    end
    truth = (; person_ids, word_ids, rater_ids, criteria,
        recording_ids=getproperty.(recordings, :recording), theta, b, severity,
        recording_effect=u, steps, active_loading=1.0, consistency=1.0,
        rho_person, rho_recording, recording_sd, rater_kernel_sd,
        word_sd=0.65, realized_person_correlation=cor(theta[:,1], theta[:,2]),
        complete_ratings)
    manifest = (;
        synthetic_data_only=true,
        purpose="One application-shaped known-truth example; no fitting, recovery study or SBC",
        empirical_input="None: no empirical IDs, scores, features or assignment positions are read",
        model="A0: fixed coefficients, paired criteria, shared recording effects",
        adjacent_logit="theta[p,c] - b[w,c] - severity[r,c] + u[recording,c] - steps[c,h]",
        score_direction="0:8; higher means easier to understand / weaker accent, respectively",
        seeds, persons, words, raters, categories, criteria,
        possible_recordings=length(recordings), assigned_recordings=count(assigned),
        absent_recordings=count(!, assigned), complete_rating_count=length(complete_ratings),
        observed_rating_count=length(ratings),
        missing_rating_count=length(complete_ratings)-length(ratings),
        assignment="Words 1:3 complete; 4:35 Bernoulli(0.7), replaced by a random pair if fewer than two persons; words 36 and 37 have one and two random persons; all assigned recordings have 19 raters",
        missingness="Independent probability 0.005 for criterion 1; criterion 2 complete; absent productions are absent rows, not score zero",
        dependence="Person effects shared across words; recording effects shared across all raters and both criteria; conditionally independent rating draws",
        truth_axes="Matrices: IDs in listed order by criteria; steps: criteria by baseline 0 then transitions 1:8; complete_ratings contains assigned cells only",
        limitations="Illustrative constants are not empirical estimates or fitting priors. Population rho differs from realized sample correlation. No phonetic features, secondary outcomes or ability-dependent missingness. Current ordinary MGMFRM does not implement this entire model.")
    return (; ratings, recordings, truth, manifest)
end

"Write a new directory containing observed views, separate truth, and provenance."
function write_example(directory::AbstractString; kwargs...)
    ispath(directory) && throw(ArgumentError("output directory already exists"))
    panel = generate(; kwargs...)
    mkdir(directory)
    files = ("ratings.json", "recordings.json", "truth.json")
    for (name, payload) in zip(files, (panel.ratings, panel.recordings, panel.truth))
        B._write_json_record(joinpath(directory, name), payload)
    end
    manifest = (; panel.manifest..., julia_version=string(VERSION),
        generator_sha256=bytes2hex(sha256(read(@__FILE__))),
        response_helper_sha256=bytes2hex(sha256(read(joinpath(dirname(pathof(B)),
            "local_dependence_known_truth_dgp.jl")))),
        files=[(; name, bytes=filesize(joinpath(directory, name)),
            sha256=bytes2hex(sha256(read(joinpath(directory, name))))) for name in files])
    B._write_json_record(joinpath(directory, "manifest.json"), manifest)
    return panel
end

end # module
