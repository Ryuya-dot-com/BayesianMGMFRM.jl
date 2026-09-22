using Test, Random, Statistics, JSON3
include(joinpath(@__DIR__, "..", "scripts", "mgmfrm_core_evaluation.jl"))
const E = MGMFRMCoreEvaluation
const P = E.P
const B = E.B
const V = E.V
root = first(ARGS)
output = length(ARGS) == 2 ? ARGS[2] : joinpath(root,"evaluation-tests.json")
records = NamedTuple[]
matrix(rows) = reduce(vcat, permutedims.(Vector{Float64}.(rows)))
observed = P.readjson(joinpath(root, "R0", "observed.json"))
truth = P.readjson(joinpath(root, "R0", "truth.json"))
target = P.target(P.specification(observed; require_all_categories=false))
ids = E.candidate_design(target.design)
raw = Float64.(truth.raw)
logs = matrix(truth.log_probabilities)

@testset "Recovery generator agrees with the actual Julia target" begin
    for condition in ("R0", "R1")
        obs = P.readjson(joinpath(root, condition, "observed.json"))
        tr = P.readjson(joinpath(root, condition, "truth.json"))
        t = P.target(P.specification(obs; require_all_categories=false))
        q = Float64.(tr.raw)
        @test t.blueprint.parameter_names == String.(tr.raw_names)
        direct = B._mgmfrm_source_constrained_params_from_unconstrained(t.design, q)
        actual = dropdims(B._mgmfrm_predictive_probabilities_direct(t.design, permutedims(direct)); dims=1)
        expected = exp.(matrix(tr.log_probabilities))
        @test actual ≈ expected atol=1e-12 rtol=1e-12
        @test B._source_fixture_logprior(t, q) ≈ tr.log_prior atol=1e-9
        @test B._source_fixture_loglikelihood(t, q) ≈ tr.log_likelihood atol=1e-8
        push!(records, (; condition, probability_error=maximum(abs.(actual-expected)),
            likelihood_error=abs(B._source_fixture_loglikelihood(t, q)-tr.log_likelihood)))
    end
    unused = JSON3.read(JSON3.write(observed), Dict{String,Any})
    foreach(r -> r["score"] = r["score"] == 3 ? 2 : r["score"], unused["observations"])
    obs = JSON3.read(JSON3.write(unused))
    @test_throws ErrorException P.specification(obs)
    t = P.target(P.specification(obs; require_all_categories=false))
    @test t.design.spec.data.category_levels == [1,2,3,4]
    @test Set(t.design.spec.data.score) == Set([1,2,4])
    @test isfinite(B.LogDensityProblems.logdensity(t, raw))
    foreach(r -> r["score"] = 1, unused["observations"])
    # The existing fitting boundary still rejects a single observed category.
    # Preserve this as an unresolved study slot, never redraw or bypass it.
    single = JSON3.read(JSON3.write(unused))
    @test P.observation_data(single).category_levels == [1,2,3,4]
    @test_throws ArgumentError P.specification(single; require_all_categories=false)
end

@testset "Prediction scoring preserves IDs and equal dimension weighting" begin
    exact = E.predictive_score(observed, logs, logs; prediction_ids=ids, truth_ids=ids)
    @test exact.summary.squared_category_probability_error == 0.
    @test exact.summary.squared_expected_score_error == 0.
    @test !exact.heldout_provenance_verified && !exact.scientific_acceptance
    @test length(exact.person_dimension_rows) == 100
    @test getproperty.(exact.person_dimension_rows, :n_observations) == repeat([10,15],50)
    permutation = randperm(MersenneTwister(9232301),1250)
    other = reverse(1:1250)
    reordered = E.predictive_score(observed, logs[permutation,:], logs[other,:];
        prediction_ids=ids[permutation], truth_ids=ids[other])
    @test reordered == exact
    wrong = copy(logs)
    p3 = findall(id -> id[1] == "P3", ids)
    p4 = findall(id -> id[1] == "P4", ids)
    wrong[p3,:] = logs[p4,:]; wrong[p4,:] = logs[p3,:]
    @test vec(mean(exp.(wrong); dims=1)) ≈ vec(mean(exp.(logs); dims=1))
    swapped = E.predictive_score(observed, wrong, logs; prediction_ids=ids, truth_ids=ids)
    @test swapped.summary.squared_category_probability_error > 0.001
    @test swapped.summary.squared_expected_score_error > 0.
    uniform = fill(-log(4),1250,4)
    shifted = copy(uniform)
    d1 = findall(id -> id[2] in ("I1","I2"), ids)
    shifted[d1,:] .= permutedims(log.([.4,.2,.2,.2]))
    score = E.predictive_score(observed, shifted, uniform; prediction_ids=ids, truth_ids=ids)
    @test score.summary.squared_category_probability_error ≈ .5 * .03
    @test score.summary.squared_expected_score_error ≈ .5 * .3^2
    @test mean(r.squared_category_probability_error for r in score.rows) ≈ .4 * .03
    for bad in (ids[1:end-1], [ids[2]; ids[2:end]], [("P51","I1","R1");ids[2:end]])
        @test_throws ArgumentError E.predictive_score(observed, logs, logs; prediction_ids=bad, truth_ids=ids)
        @test_throws ArgumentError E.predictive_score(observed, logs, logs; prediction_ids=ids, truth_ids=bad)
    end
    @test_throws ArgumentError E.predictive_score(observed, logs[1:1249,:], logs; prediction_ids=ids, truth_ids=ids)
    @test_throws ArgumentError E.predictive_score(observed, fill(NaN,1250,4), logs; prediction_ids=ids, truth_ids=ids)
    @test_throws ArgumentError E.predictive_score(observed, zeros(1250,4), logs; prediction_ids=ids, truth_ids=ids)
    push!(records, (; case="person_swap", squared_category_probability_error=swapped.summary.squared_category_probability_error,
        squared_expected_score_error=swapped.summary.squared_expected_score_error))
end

@testset "Use log mean probability, preserve zero support and declared categories" begin
    changed = JSON3.read(JSON3.write(observed), Dict{String,Any})
    foreach(r -> r["score"] = 1, changed["observations"])
    obs = JSON3.read(JSON3.write(changed))
    draws = zeros(2,1250,4)
    draws[1,:,:] .= permutedims(log.([.1,.3,.3,.3]))
    draws[2,:,:] .= permutedims(log.([.9,1/30,1/30,1/30]))
    expected = repeat(permutedims(log.([.5,1/6,1/6,1/6])),1250)
    score = E.predictive_score(obs, draws, expected; prediction_ids=ids, truth_ids=ids)
    @test score.summary.negative_log_predictive_probability ≈ log(2)
    @test score.summary.negative_log_predictive_probability < -(log(.1)+log(.9))/2
    @test score.summary.squared_category_probability_error < 1e-30
    @test score.n_prediction_draws == 2
    zero = fill(-Inf,1250,4); zero[:,4] .= 0.
    score = E.predictive_score(obs, zero, expected; prediction_ids=ids, truth_ids=ids)
    @test score.summary.negative_log_predictive_probability == Inf
    @test score.summary.log_score_regret == Inf
end

@testset "SBC quantities bind coordinate IDs and observed likelihood" begin
    q = E.sbc_quantities(target, permutedims(raw); parameter_names=truth.raw_names)
    @test size(q.values) == (1,138)
    @test length(unique(q.names)) == 138
    @test q.values[1,1:128] == raw
    @test q.values[1,129] ≈ truth.state.severity[5]
    @test q.values[1,130] ≈ truth.state.log_consistency[5]
    @test q.values[1,131:135] ≈ [s[4] for s in truth.state.steps]
    for (col,person) in ((136,"P1"),(137,"P2"))
        p = findfirst(==(person),String.(truth.ordered_ids.person))
        @test q.values[1,col] ≈ prod(truth.state.theta[p])
    end
    @test q.values[1,138] ≈ truth.log_likelihood atol=1e-8
    changed = JSON3.read(JSON3.write(observed), Dict{String,Any})
    foreach(r -> r["score"] = 1, changed["observations"])
    changed["observations"][1]["score"] = 2
    t = P.target(P.specification(JSON3.read(JSON3.write(changed)); require_all_categories=false))
    other = E.sbc_quantities(t, permutedims(raw); parameter_names=truth.raw_names)
    @test other.values[1,1:137] == q.values[1,1:137]
    @test abs(other.values[1,138] - q.values[1,138]) > 1
    @test_throws ArgumentError E.sbc_quantities(target, permutedims(raw); parameter_names=reverse(truth.raw_names))
    @test_throws ArgumentError E.sbc_quantities(target, fill(NaN,1,128); parameter_names=truth.raw_names)
end

@testset "Fixed chain selection, ties and failure denominators" begin
    draws = repeat(permutedims(raw),8)
    draws[:,1] += collect(1:8)./100
    chains = repeat(1:4; inner=2); iterations = repeat(1:2,4)
    selected = E.sbc_rank_draws(target, draws; parameter_names=truth.raw_names,
        chain_ids=chains, iterations, retained_iteration=2)
    @test selected.selected_rows == [2,4,6,8]
    @test selected.chain_ids == [1,2,3,4]
    @test !selected.independence_verified && !selected.diagnostic_qualification_applied
    @test !selected.joint_prior_binding_verified && !selected.scientific_acceptance
    order = [8,1,3,5,2,6,4,7]
    shuffled = E.sbc_rank_draws(target, draws[order,:]; parameter_names=truth.raw_names,
        chain_ids=chains[order], iterations=iterations[order], retained_iteration=2)
    @test shuffled.values == selected.values
    @test order[shuffled.selected_rows] == selected.selected_rows
    for (c,it,k) in ((ones(Int,8),collect(1:8),8),(chains,iterations,1),
            (chains,ones(Int,8),2),(chains,iterations,true))
        @test_throws ArgumentError E.sbc_rank_draws(target, draws; parameter_names=truth.raw_names,
            chain_ids=c, iterations=it, retained_iteration=k)
    end
    draws[1,1]=NaN # Unselected rows must not escape validation.
    @test_throws ArgumentError E.sbc_rank_draws(target, draws; parameter_names=truth.raw_names,
        chain_ids=chains, iterations, retained_iteration=2)
    tied = V.randomized_rank(0.,[0.,0.,0.,0.],MersenneTwister(9232302))
    @test (tied.lower,tied.upper,tied.ties,tied.n_draws) == (0,4,4,4)
    @test 0 <= tied.rank <= 4
    screen = V.rank_cdf([fill(0,60);fill(missing,40)];n_draws=4,n_quantities=138)
    @test (screen.planned,screen.usable,screen.unresolved) == (100,60,40)
    @test screen.rows[1].lower == .6 && screen.rows[1].upper == 1.
    @test screen.conditional_screen == :departure
    @test !screen.calibration_verified
    unresolved = V.rank_cdf(fill(missing,100);n_draws=4,n_quantities=138)
    @test unresolved.conditional_screen == :unresolved
    @test unresolved.rows[1].lower == 0. && unresolved.rows[1].upper == 1.
    balanced = V.rank_cdf(repeat(0:4,20);n_draws=4,n_quantities=138)
    @test balanced.conditional_screen == :no_resolved_departure
    @test !balanced.calibration_verified && !balanced.scientific_acceptance
    push!(records, (; case="missing_rank_slots", epsilon=screen.epsilon,
        planned=screen.planned, usable=screen.usable, unresolved=screen.unresolved))
end

P.writejson(output, (;records,tests_passed=true,
    julia_version=string(VERSION), new_sampler_runs=0, scientific_acceptance=false))
