using Test
using Random
using Statistics

# M1 preparation only: reuse the standalone generator, not the fitting kernel.
# No MCMC, evaluation seeds, research fixtures, or new exports are needed.
module MFRMAnchorStandaloneDGP
include(joinpath(@__DIR__, "..", "src", "local_dependence_known_truth_dgp.jl"))
end

using BayesianMGMFRM

function mfrm_anchor_test_panel(sparse)
    events = [(p, r, i) for p in 1:40 for r in 1:4 for i in 1:4
        if !sparse || r in (mod1(p, 4), mod1(p + 1, 4))]
    data = FacetData((;
        person = ["P$(lpad(string(p), 2, '0'))" for (p, r, i) in events],
        rater = ["R$r" for (p, r, i) in events],
        item = ["I$i" for (p, r, i) in events],
        score = [mod(p + r + i, 4) for (p, r, i) in events],
    ); person = :person, rater = :rater, item = :item,
        score = :score, category_levels = 0:3)
    return events, data
end

@testset "M1 scoring applicability, failures, and paired denominators" begin
    # Hand-constructed scoring smoke, not posterior draws from a fitted model.
    recovery_rows = BayesianMGMFRM._parameter_recovery_rows
    binary_summary = BayesianMGMFRM._free_correlation_study_binary_summary
    score(error) = only(recovery_rows(["R3 - R2"], Dict(:rater_contrast => 1:1),
        reshape(0.5 .+ error .+ [-2.0, -1.0, 0.0, 1.0, 2.0], :, 1), [0.5];
        interval = 0.8, metadata = (; scope = :synthetic_scoring_check)))
    _, data = mfrm_anchor_test_panel(true)
    for fixed in ((1, 4), (2, 3), (1, 2, 3, 4))
        anchors = [(; block = :rater, level = "R$r", value = 0.5(r - 1), type = :hard)
            for r in fixed]
        design = getdesign(mfrm_spec(data; anchors))
        draws = zeros(4, length(design.parameter_names))
        for r in 1:4
            r in fixed && continue
            index = only(findall(==("rater[R$r]"), design.parameter_names))
            draws[:, index] .= 0.5(r - 1) .+ (0:3)
        end
        for (left, right) in ((3, 2), (2, 1))
            values = [BayesianMGMFRM._stable_facet_value(design, row, :rater, left) -
                BayesianMGMFRM._stable_facet_value(design, row, :rater, right)
                for row in eachrow(draws)]
            # Structural applicability, never inferred from an empirical SD.
            applicable = left ∉ fixed || right ∉ fixed
            @test applicable == (length(fixed) == 2 && (left == 2 || fixed == (1, 4)))
            scored = applicable ? only(recovery_rows(["R$left - R$right"],
                Dict(:rater_contrast => 1:1), reshape(values, :, 1), [0.5];
                interval = 0.8, metadata = (; scope = :synthetic_scoring_check))) : missing
            if applicable
                @test scored.interval_probability == 0.8
                @test scored.posterior_mean ≈ mean(values)
            else
                @test ismissing(scored) # N/A, not an unresolved coverage trial.
            end
            if fixed == (1, 4) && left == 3
                @test values == fill(0.5, 4)
                @test applicable && scored.covered # Zero sample SD is not a fixed anchor.
            end
        end
    end

    planned = 1:8
    states = (:completed, :completed, :completed, :completed, :completed,
        :fit_failed, :structurally_rejected, :not_started)
    attempts = [(; id, attempt = 1, status = states[id], diagnostic_valid = id <= 4,
        recovery = id <= 3 ? score((-1.0, 1.0, 2.0)[id]) : id == 5 ? score(0.0) : missing)
        for id in planned]
    push!(attempts, (; id = 6, attempt = 2, status = :completed,
        diagnostic_valid = true, recovery = score(0.0)))
    primary = [r for r in attempts if r.attempt == 1]
    @test sort([r.id for r in primary]) == collect(planned)
    @test length(unique((r.id, r.attempt) for r in attempts)) == length(attempts) == 9
    @test count(r -> r.status in (:completed, :fit_failed), primary) == 6
    @test count(r -> r.status === :completed, primary) == 5
    @test count(r -> r.status === :completed && r.diagnostic_valid, primary) == 4
    valid = [r for r in primary if r.status === :completed && r.diagnostic_valid &&
        !ismissing(r.recovery)]
    @test [r.id for r in valid] == [1, 2, 3] # Excludes retry success and invalid diagnostics.
    summary = only(parameter_recovery_summary([r.recovery for r in valid]; by = :all))
    @test summary.n_parameters == 3 # Row count, not all eight planned datasets.
    @test summary.mean_bias ≈ 2 / 3
    @test summary.rmse ≈ sqrt(2)
    @test summary.coverage_rate ≈ 2 / 3
    @test summary.mean_interval_width ≈ 3.2
    errors = [r.recovery.bias for r in valid]
    @test std(errors) / sqrt(length(errors)) ≈ sqrt(7) / 3
    @test std(abs2.(errors)) / sqrt(length(errors)) ≈ 1.0
    coverage = binary_summary(summary.n_covered, length(valid), length(planned), 1.959963984540054)
    @test coverage.conditional_rate_among_valid ≈ 2 / 3
    @test coverage.joint_fixed_denominator_rate == 2 / 8
    @test coverage.n_unresolved == 5
    @test (coverage.unresolved_bounds.lower, coverage.unresolved_bounds.upper) == (2 / 8, 7 / 8)
    unresolved = binary_summary(0, 0, 8, 1.959963984540054)
    @test ismissing(unresolved.conditional_rate_among_valid)
    @test (unresolved.unresolved_bounds.lower, unresolved.unresolved_bounds.upper) == (0.0, 1.0)
    @test_throws ArgumentError binary_summary(2, 1, 8, 1.959963984540054)
    @test_throws ArgumentError binary_summary(0, 0, 0, 1.959963984540054)

    # Four methods on the same dataset/heldout IDs; one missing result and one
    # infinite log loss must not silently become ordinary finite outcomes.
    methods = (:B, :R, :I, :RI)
    losses = [10.0 8.0 9.0 6.0; 20.0 17.0 19.0 14.0;
        30.0 27.0 28.0 missing; 40.0 Inf 39.0 34.0]
    rows = [(; dataset = ("RSM-S", id), heldout = ("RSM-S", id, :heldout),
        method, loss = losses[id, column]) for id in 1:4 for (column, method) in pairs(methods)]
    keyed = Dict((r.dataset, r.heldout, r.method) => r.loss for r in rows)
    @test length(keyed) == length(rows) == 16
    @test isequal(keyed, Dict((r.dataset, r.heldout, r.method) => r.loss for r in reverse(rows)))
    @test ismissing(get(keyed, (("RSM-S", 1), ("RSM-S", 2, :heldout), :B), missing))
    finite(x) = !ismissing(x) && isfinite(x)
    complete = [id for id in 1:4 if all(finite, [keyed[(("RSM-S", id),
        ("RSM-S", id, :heldout), method)] for method in methods])]
    @test complete == [1, 2]
    @test count(ismissing, losses) == 1
    @test count(x -> !ismissing(x) && isinf(x), losses) == 1
    differences = [losses[id, 4] - losses[id, 2] - losses[id, 3] + losses[id, 1]
        for id in complete]
    @test differences == [-1.0, -2.0]
    @test mean(differences) == -1.5
    @test std(differences) / sqrt(length(differences)) ≈ 0.5
    marginal = [mean(filter(finite, losses[:, column])) for column in 1:4]
    @test !isapprox(marginal[4] - marginal[2] - marginal[3] + marginal[1], mean(differences))
    for incomplete in (Float64[], [1.0])
        mcse = length(incomplete) < 2 ? missing : std(incomplete) / sqrt(length(incomplete))
        @test ismissing(mcse)
    end
    # No all-attempt executor or acceptance gate is implemented by this smoke.
end

@testset "M1 predictive score boundaries and event weights" begin
    # Reuse the array scorer, not the historical pilot's inline KL formula.
    # Gneiting & Raftery (2007), Sec. 3.1, Example 3: negative log score
    # and truth-to-prediction KL. No fitted posterior or evaluation responses.
    score = mgmfrm_predictive_recovery_score
    levels = [-2, -1, 0, 1]
    onehot(y, labels) = Float64.([value == label for value in y, label in labels])
    truth = [0.25 0.25 0.5 0.0; 0.1 0.2 0.3 0.4]
    draws = zeros(2, 2, 4)
    draws[1, :, :] = [0.8 0.1 0.1 0.0; 0.1 0.2 0.3 0.4]
    draws[2, :, :] = [0.2 0.3 0.5 0.0; 0.3 0.1 0.2 0.4]
    averaged = dropdims(mean(draws; dims = 1); dims = 1)
    recovery = score(draws, truth; category_levels = levels)
    expected_kl = [sum(truth[n, k] * (log(truth[n, k]) - log(averaged[n, k]))
        for k in 1:4 if truth[n, k] > 0) for n in 1:2]
    @test recovery.summary.n_prediction_draws == 2
    @test [r.log_score_regret for r in recovery.rows] ≈ expected_kl
    @test recovery.summary.mean_log_score_regret ≈ mean(expected_kl)
    @test score(truth, truth).summary.mean_log_score_regret == 0.0
    observed = onehot([-2, 1], levels)
    heldout = score(draws, observed; category_levels = levels)
    # Only the one-hot KL field is a heldout loss; probability/expected-score
    # errors against observed outcomes are not known-truth recovery metrics.
    @test [r.log_score_regret for r in heldout.rows] ≈ -log.([0.5, 0.4])
    @test heldout.summary.mean_log_score_regret ≈ -mean(log.([0.5, 0.4]))
    @test heldout.rows[1].log_score_regret < -mean(log.(draws[:, 1, 1]))
    permutation = [4, 2, 1, 3]
    relabelled = score(draws[:, :, permutation], truth[:, permutation];
        category_levels = levels[permutation])
    @test relabelled.summary.mean_log_score_regret ≈ recovery.summary.mean_log_score_regret
    @test relabelled.summary.mean_absolute_expected_score_error ≈
        recovery.summary.mean_absolute_expected_score_error
    @test score(draws[:, :, permutation], onehot([-2, 1], levels[permutation])).summary.mean_log_score_regret ≈
        heldout.summary.mean_log_score_regret
    @test_throws ArgumentError score(draws, onehot([-3, 1], levels))
    @test score(draws, onehot([1, 1], levels)).status === :nonfinite_log_score_regret

    events, _ = mfrm_anchor_test_panel(true)
    strata = [findall(e -> (e[2] == 4, e[3] == 4) == pattern, events)
        for pattern in ((true, true), (true, false), (false, true), (false, false))]
    @test length.(strata) == [20, 60, 60, 180]
    predicted = zeros(length(events), 4)
    for (s, rows) in pairs(strata)
        predicted[rows, 1] .= exp(-s)
        predicted[rows, 2:4] .= (1 - exp(-s)) / 3
    end
    losses = score(predicted, onehot(fill(-2, length(events)), levels))
    stratum_means = [mean(losses.rows[n].log_score_regret for n in rows) for rows in strata]
    @test stratum_means ≈ 1:4
    @test losses.summary.n_observations == 320
    @test losses.summary.mean_log_score_regret ≈ sum(length.(strata) .* stratum_means) / 320
    @test losses.summary.mean_log_score_regret ≈ 3.25
    @test !isapprox(losses.summary.mean_log_score_regret, mean(stratum_means))

    # A Float64 zero can be representational, not structural. Score actual
    # heldout categories from finite model log probabilities when available.
    table = (; person = ["P1", "P2"], rater = ["R1", "R1"],
        item = ["I1", "I1"], score = [1, -2])
    design_for(t) = getdesign(mfrm_spec(FacetData(t; person = :person,
        rater = :rater, item = :item, score = :score, category_levels = levels)))
    training = design_for(table)
    heldout_design = design_for(merge(table, (; score = [-2, 1])))
    @test training.parameter_names == heldout_design.parameter_names
    @test heldout_design.spec.data.category_levels == levels
    params = zeros(2, length(training.parameter_names))
    for (label, sign) in (("P1", 1), ("P2", -1))
        person = only(findall(==("person[$label]"), training.parameter_names))
        params[:, person] = sign .* [1_000.0, 1_001.0]
    end
    probabilities = predictive_probabilities(heldout_design, params)
    @test all(iszero, probabilities[:, 1, 1])
    @test score(probabilities, onehot([-2, 1], heldout_design.spec.data.category_levels)).summary.mean_log_score_regret == Inf
    logs = [first(pointwise_loglikelihood(heldout_design, row)) for row in eachrow(params)]
    @test logs == [-3_000.0, -3_003.0]
    log_loss = -BayesianMGMFRM._logmeanexp(logs)
    @test isfinite(log_loss)
    @test log_loss ≈ 3_000 + log(2) - log1p(exp(-3))
    @test log_loss < -mean(logs)
    @test all(all(iszero, pointwise_loglikelihood(training, row)) for row in eachrow(params))
    @test_throws ArgumentError BayesianMGMFRM._logmeanexp([-Inf, -1.0])
    # The shared finite-only helper is unchanged. The scorer's explicit log
    # input handles structural zeros separately; see the checks below.
end

@testset "M1 all-category log scoring through existing predictor values" begin
    events = [(p, r, i) for p in 1:2 for r in 1:2 for i in 1:2]
    levels = [-2, -1, 0, 1]
    table = (; person = ["P$p" for (p, r, i) in events],
        rater = ["R$r" for (p, r, i) in events], item = ["I$i" for (p, r, i) in events],
        score = [levels[mod1(p + r + i, 4)] for (p, r, i) in events])
    data = FacetData(table; person = :person, rater = :rater, item = :item,
        score = :score, category_levels = levels)
    theta, rho, beta = [0.4, -0.8], [0.0, 0.5], [0.0, 0.4]
    # Independent high-precision equation oracle, not a new DGP or fitter.
    function big_probability(location, steps)
        weights = [exp(k * BigFloat(location) - sum(BigFloat.(steps[1:k]);
            init = BigFloat(0))) for k in 0:3]
        return weights / sum(weights)
    end
    for thresholds in (:rating_scale, :partial_credit),
            fixed_raters in (false, true), fixed_items in (false, true)
        steps = ([-0.6, 0.0, 0.6], thresholds === :rating_scale ?
            [-0.6, 0.0, 0.6] : [-0.4, 0.1, 0.3])
        anchors = vcat([(; block = :rater, level = "R$r", value = rho[r], type = :hard)
                for r in 1:2 if fixed_raters],
            [(; block = :item, level = "I$i", value = beta[i], type = :hard)
                for i in 1:2 if fixed_items])
        design = getdesign(mfrm_spec(data; thresholds, anchors))
        values = Dict("person[P$p]" => theta[p] for p in 1:2)
        merge!(values, Dict("rater[R$r]" => rho[r] for r in 1:2),
            Dict("item[I$i]" => beta[i] for i in 1:2))
        for i in (thresholds === :rating_scale ? (1,) : (1, 2)), s in 1:2
            name = thresholds === :rating_scale ? "step[$s]" : "step[item=I$i,$s]"
            values[name] = steps[i][s]
        end
        truth_logs = reduce(vcat, [permutedims(MFRMAnchorStandaloneDGP._ld1_pcm_probabilities(
            theta[p] - rho[r] - beta[i], steps[i]; log_probabilities = true))
            for (p, r, i) in events])
        truth = exp.(truth_logs)
        for shift in (0.2, -1_000.0, 1_000.0)
            shifts = (shift, shift + 0.3)
            params = repeat(reshape([values[name] for name in design.parameter_names], 1, :), 2, 1)
            for p in 1:2
                index = only(findall(==("person[P$p]"), design.parameter_names))
                params[:, index] = theta[p] .+ collect(shifts)
            end
            logs = zeros(2, data.n, 4)
            for draw in 1:2
                records = reverse(linear_predictor_values(design, params[draw, :]))
                keyed = Dict((r.row, r.category) => r.log_probability for r in records)
                @test length(keyed) == length(records) == data.n * 4
                @test all((r.person, r.rater, r.item) ==
                    (table.person[r.row], table.rater[r.row], table.item[r.row]) for r in records)
                logs[draw, :, :] = [keyed[(n, category)] for n in 1:data.n, category in levels]
            end
            scored = mgmfrm_predictive_recovery_score(logs, truth_logs;
                log_probabilities = true, category_levels = levels)
            oracle = setprecision(256) do
                [Float64(sum(BigFloat(truth[n, k]) * log(BigFloat(truth[n, k]) /
                    mean(big_probability(theta[p] + s - rho[r] - beta[i], steps[i])[k]
                        for s in shifts)) for k in 1:4))
                    for (n, (p, r, i)) in pairs(events)]
            end
            @test scored.status === :scored
            @test [r.log_score_regret for r in scored.rows] ≈ oracle rtol = 1e-11 atol = 1e-12
            @test scored.summary.mean_log_score_regret ≈ mean(oracle) rtol = 1e-11 atol = 1e-12
            probabilities = predictive_probabilities(design, params)
            @test exp.(logs) ≈ probabilities atol = 1e-12
            ordinary = mgmfrm_predictive_recovery_score(probabilities, truth)
            if abs(shift) < 1
                @test ordinary.summary.mean_log_score_regret ≈ scored.summary.mean_log_score_regret
            else
                @test ordinary.summary.mean_log_score_regret == Inf
            end
        end
    end
end

@testset "M1 independent log truth and underflow boundaries" begin
    probability = MFRMAnchorStandaloneDGP._ld1_pcm_probabilities
    # Blanchard, Higham & Higham (2021), Sec. 4, Algorithm 4.1:
    # https://doi.org/10.1093/imanum/draa038 (shift plus log1p).
    for location in (-1_000.0, -50.0, -0.7, 0.0, 0.8, 50.0, 1_000.0),
            steps in (Float64[], [0.0], [-0.3, 0.7], [-0.6, 0.1, 0.5],
                zeros(4), [-1.0, 0.0, 2.0, 1.0])
        logs = probability(location, steps; log_probabilities = true)
        # Separate category equation, not the production recurrence/normalizer.
        oracle = setprecision(512) do
            weights = [exp(k * BigFloat(location) - sum(BigFloat.(steps[1:k]);
                init = BigFloat(0))) for k in 0:length(steps)]
            Float64.(log.(weights ./ sum(weights)))
        end
        @test all(isfinite, logs)
        @test all(<=(0), logs)
        @test all(isapprox.(logs, oracle; rtol = 2e-13, atol = 0))
        @test exp.(logs) ≈ probability(location, steps) atol = 1e-14
        @test sum(exp.(logs)) ≈ 1 atol = 1e-14
        @test diff(logs) ≈ location .- steps atol = 1e-12 rtol = 1e-12
    end
    # Tiny dominant-category log probabilities must not round to zero just
    # because the ordinary probability has rounded to one.
    for location in (-50.0, 50.0)
        mode = location < 0 ? 1 : 2
        @test probability(location, [0.0])[mode] == 1.0
        @test probability(location, [0.0]; log_probabilities = true)[mode] ≈
            -log1p(exp(-50.0)) rtol = 1e-14 atol = 0
    end
    @test probability(0.0, zeros(3); log_probabilities = true) == fill(-log(4.0), 4)
    for (location, steps) in ((NaN, [0.0]), (Inf, [0.0]), (-Inf, [0.0]),
            (NaN, Float64[]), (Inf, Float64[]), (-Inf, Float64[]),
            (0.0, [NaN]), (0.0, [Inf]), (0.0, [-Inf]),
            (1e308, zeros(3)), (-1e308, zeros(3)),
            (0.0, [1e308, -1e308, -1e308]))
        # Arithmetic overflow is not a structural zero and must not be clipped.
        @test_throws ArgumentError probability(location, steps; log_probabilities = true)
    end

    score = mgmfrm_predictive_recovery_score
    truth = permutedims(probability(-800.0, [0.0]; log_probabilities = true))
    prediction = permutedims(probability(-1e308, [0.0]; log_probabilities = true))
    @test all(isfinite, truth) && all(isfinite, prediction)
    @test exp.(truth) == exp.(prediction) == [1.0 0.0]
    actual = score(prediction, truth; log_probabilities = true)
    expected = setprecision(512) do
        tail = exp(BigFloat(-800))
        p = [inv(1 + tail), tail / (1 + tail)]
        logp = [-log1p(tail), BigFloat(-800) - log1p(tail)]
        Float64(sum(p .* (logp .- BigFloat.([0.0, -1e308]))))
    end
    @test actual.status === :scored
    @test actual.summary.mean_log_score_regret > 0
    @test actual.summary.mean_log_score_regret ≈ expected rtol = 1e-12 atol = 0
    @test score(exp.(prediction), exp.(truth)).summary.mean_log_score_regret == 0.0
    @test score([0.0 -Inf], truth; log_probabilities = true).summary.mean_log_score_regret == Inf

    source = joinpath(@__DIR__, "..", "src", "local_dependence_known_truth_dgp.jl")
    code = "include(ARGS[1]); @assert !isdefined(Main, :BayesianMGMFRM); " *
        "print(_ld1_pcm_probabilities(-1000.0, [0.0]; log_probabilities = true))"
    command = addenv(`$(Base.julia_cmd()) --startup-file=no -e $code $source`,
        "JULIA_LOAD_PATH" => "@stdlib")
    @test read(command, String) == "[0.0, -1000.0]"
end

@testset "M1 serial response blocks and replay" begin
    # Smoke only, not a pilot/evaluation seed or a production generator.
    # One advancing RNG; checkpoint at whole-block boundaries, never reseed
    # each event or derive overlapping starts by advancing just one draw.
    rng = MersenneTwister(17)
    blocks = NamedTuple[]
    theta = collect(range(-1.2, 1.2; length = 40)) .+ 1.35
    rho, beta = (0.0, 0.5, 1.0, 1.5), (0.0, 0.4, 0.8, 1.2)
    pcm_steps = ([-0.6, 0.0, 0.6], [-0.4, 0.1, 0.3],
        [-0.8, 0.3, 0.5], [-0.2, -0.1, 0.3])
    probability = MFRMAnchorStandaloneDGP._ld1_pcm_probabilities
    draw = MFRMAnchorStandaloneDGP._ld1_inverse_cdf
    for replication in 1:2, family in 1:2, sparse in (false, true),
            role in (:train, :heldout)
        events, _ = mfrm_anchor_test_panel(sparse)
        steps = family == 1 ? ntuple(_ -> pcm_steps[1], 4) : pcm_steps
        probabilities = Dict(e => probability(theta[e[1]] - rho[e[2]] - beta[e[3]],
            steps[e[3]]) for e in events)
        start = copy(rng)
        uniforms = [rand(rng) for _ in events] # Scalar calls are part of replay.
        stop = copy(rng)
        uniform_by_event = Dict(zip(events, uniforms))
        scores = Dict(e => draw(uniform_by_event[e], probabilities[e], 0:3) for e in events)
        push!(blocks, (; id = (replication, family, sparse, role), events,
            start, stop, uniforms, uniform_by_event, probabilities, scores))
    end
    @test length(unique(b.id for b in blocks)) == 16
    @test sum(length(b.events) for b in blocks) == 7_680
    replay = MersenneTwister(17)
    @test reduce(vcat, [b.uniforms for b in blocks]) == [rand(replay) for _ in 1:7_680]
    @test rng == replay
    for (previous, following) in zip(blocks[1:end-1], blocks[2:end])
        @test previous.stop == following.start
    end
    # Replay any block without generating its predecessors. Row/subset access
    # uses immutable event identities, not new draws or the consumer's row index.
    for b in reverse(blocks)
        replay = copy(b.start)
        @test [rand(replay) for _ in b.events] == b.uniforms
        @test replay == b.stop
        @test issorted(b.events) && length(unique(b.events)) == length(b.events)
        @test all(score -> score in 0:3, values(b.scores))
        @test [draw(u, b.probabilities[e], 0:3) for (e, u) in zip(b.events, b.uniforms)] ==
            [b.scores[e] for e in b.events]
        for selected in (reverse(b.events), b.events[2:2:end])
            actual = Dict(e => draw(b.uniform_by_event[e], b.probabilities[e], 0:3)
                for e in selected)
            @test actual == Dict(e => b.scores[e] for e in selected)
        end
    end
    # Equality of scores across roles is possible; disjoint draw positions,
    # not forced score inequality, are the implementation property under test.
end

@testset "reference-valued anchor declarations share sampling targets" begin
    hard(block, level, value) = (; block, level, value, type = :hard)
    r1, r4 = hard(:rater, "R1", 0.0), hard(:rater, "R4", 1.5)
    i1, i4 = hard(:item, "I1", 0.0), hard(:item, "I4", 1.2)
    baseline = NamedTuple[]
    rater_pair, item_pair = [r1, r4], [i1, i4]
    equivalent_declarations = (
        (baseline, [r1]), (baseline, [i1]), (baseline, [r1, i1]),
        (rater_pair, [r1, r4, i1]), (item_pair, [i1, i4, r1]),
    )
    for thresholds in (:rating_scale, :partial_credit), sparse in (false, true)
        _, data = mfrm_anchor_test_panel(sparse)
        @test data.n == (sparse ? 320 : 640)
        @test all(count(==(rater), data.rater) == (sparse ? 80 : 160)
            for rater in 1:4)
        for (canonical, declared) in equivalent_declarations
            reference = getdesign(mfrm_spec(data; thresholds, anchors = canonical))
            alias = getdesign(mfrm_spec(data; thresholds, anchors = declared))
            @test alias.parameter_names == reference.parameter_names
            n = length(reference.parameter_names)
            for params in (zeros(n), collect(range(-0.5, 0.5; length = n)),
                    collect(range(1.5, -1.5; length = n)))
                @test loglikelihood(alias, params) == loglikelihood(reference, params)
                for scale in (0.5, 1.0, 2.0)
                    prior = MFRMPrior(; person_sd = 1.5scale,
                        rater_sd = scale, item_sd = scale, step_sd = scale)
                    @test logprior(alias, params, prior) == logprior(reference, params, prior)
                end
            end
        end
        # R3-R2 and I3-I2 stay estimated in all four primary regimes. Endpoint
        # or fully fixed contrasts must not be scored as posterior coverage.
        for anchors in (baseline, rater_pair, item_pair, [r1, r4, i1, i4])
            design = getdesign(mfrm_spec(data; thresholds, anchors))
            @test all(name -> name in design.parameter_names,
                ("rater[R2]", "rater[R3]", "item[I2]", "item[I3]",
                    "person[P10]", "person[P30]"))
        end
        for (block, prefix, endpoints, interior) in (
                (:rater, "R", rater_pair,
                    [hard(:rater, "R2", 0.5), hard(:rater, "R3", 1.0)]),
                (:item, "I", item_pair,
                    [hard(:item, "I2", 0.4), hard(:item, "I3", 0.8)]))
            for anchors in (endpoints, interior)
                design = getdesign(mfrm_spec(data; thresholds, anchors))
                # The alternate 2-1 contrast is partially estimated under
                # either placement; it is not the fixed interior 3-2 contrast.
                @test count(level -> "$block[$prefix$level]" in design.parameter_names,
                    (1, 2)) == 1
                if anchors === interior
                    @test all(level -> "$block[$prefix$level]" ∉ design.parameter_names,
                        (2, 3))
                end
            end
        end
    end
    # This does not equate reports/cache metadata, shifted anchor values,
    # different reference levels, or priors in different coordinates.
end

@testset "M1 sensitivity candidate constraints and paired controls" begin
    # Encode the finite review draft, not an evaluation runner or seed roster.
    # Scores are deterministic input scaffolding; no responses or fits are sampled.
    cell(id, kind, raters, items, u = 0.0, v = 0.0) =
        (; id, kind, raters, items, u, v)
    shift_label(x) = iszero(x) ? "0" : x > 0 ? "+$x" : string(x)
    error_id(u, v) = "D-RI-u$(shift_label(u))-v$(shift_label(v))"
    hard(block, level, value) = (; block, level, value, type = :hard)
    U = (-0.8, -0.2, 0.2, 0.8)
    cells = NamedTuple[cell("B", :E, (), ())]
    for facet in ("R", "I", "RI")
        rs, its = facet == "I" ? () : (1, 4), facet == "R" ? () : (1, 4)
        push!(cells, cell(facet, :E, rs, its))
        for (kind, locations) in ((:S, (4,)), (:P, (2, 3)), (:F, (1, 2, 3, 4)))
            push!(cells, cell("$kind-$facet", kind,
                isempty(rs) ? () : locations, isempty(its) ? () : locations))
        end
        for kind in (:C, :D)
            shifts = facet == "R" ? [(u, 0.0) for u in U] :
                facet == "I" ? [(0.0, v) for v in U] :
                kind === :C ? [(u, v) for u in U for v in U if abs(u) == abs(v)] :
                [(u, v) for u in (0.0, U...) for v in (0.0, U...)
                    if !iszero(u) || !iszero(v)]
            for (u, v) in shifts
                suffix = facet == "R" ? "-u$(shift_label(u))" :
                    facet == "I" ? "-v$(shift_label(v))" :
                    "-u$(shift_label(u))-v$(shift_label(v))"
                push!(cells, cell("$kind-$facet$suffix", kind, rs, its, u, v))
            end
        end
    end
    @test length(cells) == length(unique(c.id for c in cells)) == 61
    @test Tuple(count(c -> c.kind === kind, cells) for kind in (:E, :S, :P, :F, :C, :D)) ==
        (4, 3, 3, 3, 16, 32) # Four clean comparators + 57 sensitivities.

    events, data = mfrm_anchor_test_panel(true)
    strata = [findall(e -> (e[2] == 4, e[3] == 4) == pattern, events)
        for pattern in ((true, true), (true, false), (false, true), (false, false))]
    @test length.(strata) == [20, 60, 60, 180]
    theta = collect(range(-1.2, 1.2; length = 40)) .+ 1.35
    rho, beta = (0.0, 0.5, 1.0, 1.5), (0.0, 0.4, 0.8, 1.2)
    pcm_steps = ([-0.6, 0.0, 0.6], [-0.4, 0.1, 0.3],
        [-0.8, 0.3, 0.5], [-0.2, -0.1, 0.3])
    probability = MFRMAnchorStandaloneDGP._ld1_pcm_probabilities
    for thresholds in (:rating_scale, :partial_credit)
        prefix = thresholds === :rating_scale ? "RSM-S" : "PCM-S"
        steps = thresholds === :rating_scale ? ntuple(_ -> pcm_steps[1], 4) : pcm_steps
        results = Dict{String,NamedTuple}()
        signatures = []
        for c in cells
            @testset "$prefix-$(c.id)" begin
                # A common shift translates all free facet/person coordinates.
                # A differential error changes only the fixed fourth endpoint.
                ru, iv = c.kind === :C ? (c.u, c.v) : (0.0, 0.0)
                dr, di = c.kind === :D ? (c.u, c.v) : (0.0, 0.0)
                rvalues = [rho[r] + ru + (r == 4 ? dr : 0.0) for r in 1:4]
                ivalues = [beta[i] + iv + (i == 4 ? di : 0.0) for i in 1:4]
                anchors = vcat([hard(:rater, "R$r", rvalues[r]) for r in c.raters],
                    [hard(:item, "I$i", ivalues[i]) for i in c.items])
                rfixed = isempty(c.raters) ? (1,) : c.raters
                ifixed = isempty(c.items) ? (1,) : c.items
                push!(signatures, (Tuple((r, rvalues[r]) for r in rfixed),
                    Tuple((i, ivalues[i]) for i in ifixed)))
                design = getdesign(mfrm_spec(data; thresholds, anchors))
                values = Dict("person[P$(lpad(string(p), 2, '0'))]" => theta[p] + ru + iv
                    for p in 1:40)
                merge!(values, Dict("rater[R$r]" => rho[r] + ru for r in 1:4 if r ∉ rfixed))
                merge!(values, Dict("item[I$i]" => beta[i] + iv for i in 1:4 if i ∉ ifixed))
                for i in (thresholds === :rating_scale ? (1,) : (1, 2, 3, 4)), s in 1:2
                    name = thresholds === :rating_scale ? "step[$s]" : "step[item=I$i,$s]"
                    values[name] = steps[i][s]
                end
                @test Set(design.parameter_names) == Set(keys(values))
                # These are estimation masks, not implemented interval scores.
                @test length(design.blocks[:rater]) == 4 - length(rfixed)
                @test length(design.blocks[:item]) == 4 - length(ifixed)
                params = [values[name] for name in design.parameter_names]
                expected = reduce(vcat, [permutedims(probability(
                    theta[p] - rho[r] - beta[i] - (r == 4 ? dr : 0.0) -
                    (i == 4 ? di : 0.0), steps[i])) for (p, r, i) in events])
                actual = dropdims(predictive_probabilities(design, reshape(params, 1, :)); dims = 1)
                @test actual ≈ expected atol = 1e-12 rtol = 0
                expected_loglikelihood = [log(expected[row, mod(p + r + i, 4) + 1])
                    for (row, (p, r, i)) in pairs(events)]
                @test pointwise_loglikelihood(design, params) ≈ expected_loglikelihood atol = 1e-12 rtol = 0
                results[c.id] = (; names = Tuple(design.parameter_names), probabilities = actual,
                    prior = logprior(design, params))
            end
        end
        @test length(unique(signatures)) == 61
        for c in cells
            c.kind === :C || continue
            facet = isempty(c.raters) ? "I" : isempty(c.items) ? "R" : "RI"
            @test results[c.id].probabilities ≈ results[facet].probabilities atol = 1e-12 rtol = 0
            # At these truth vectors the unchanged zero-centered prior differs;
            # likelihood equality alone does not establish posterior equality.
            @test !isapprox(results[c.id].prior, results[facet].prior; atol = 1e-12, rtol = 0)
        end
        for u in U, v in U
            joint, ronly, ionly, clean = results[error_id(u, v)],
                results[error_id(u, 0.0)], results[error_id(0.0, v)], results["RI"]
            @test joint.names == ronly.names == ionly.names == clean.names
            @test joint.prior == ronly.prior == ionly.prior == clean.prior
            intersection, rrows, irows, untouched = strata
            @test joint.probabilities[rrows, :] ≈ ronly.probabilities[rrows, :] atol = 1e-12 rtol = 0
            @test joint.probabilities[irows, :] ≈ ionly.probabilities[irows, :] atol = 1e-12 rtol = 0
            @test joint.probabilities[untouched, :] ≈ clean.probabilities[untouched, :] atol = 1e-12 rtol = 0
            # Numerical non-equality checks, not practical distortion thresholds.
            @test maximum(abs.(joint.probabilities[rrows, :] .- clean.probabilities[rrows, :])) > 1e-4
            @test maximum(abs.(joint.probabilities[irows, :] .- clean.probabilities[irows, :])) > 1e-4
            if iszero(u + v)
                @test joint.probabilities[intersection, :] ≈ clean.probabilities[intersection, :] atol = 1e-12 rtol = 0
            else
                @test maximum(abs.(joint.probabilities[intersection, :] .- clean.probabilities[intersection, :])) > 1e-4
            end
        end
        for u in U
            @test results[error_id(u, 0.0)].names != results["D-R-u$(shift_label(u))"].names
            @test results[error_id(0.0, u)].names != results["D-I-v$(shift_label(u))"].names
        end
    end
end

@testset "MFRM anchor generator equation and category checks" begin
    probability = MFRMAnchorStandaloneDGP._ld1_pcm_probabilities
    draw = MFRMAnchorStandaloneDGP._ld1_inverse_cdf
    # Adjacent-category odds: exp(theta - severity - difficulty - step).
    # Wind & Jones (2018), p. 686, Eq. 1, DOI: 10.1177/0013164417703733.
    # PCM changes step ownership, not this recurrence; see Linacre (2000),
    # https://www.rasch.org/rmt/rmt143k.htm (RSM shared / PCM item-specific).
    @test probability(log(2), zeros(3)) ≈ [1, 2, 4, 8] ./ 15 atol = 1e-14
    @test probability(0.0, [-log(2), 0.0, log(2)]) ≈ [1, 2, 2, 1] ./ 6 atol = 1e-14
    @test probability(0.0, [-log(3), log(3)]) ≈ [1, 3, 1] ./ 5 atol = 1e-14
    @test probability(0.0, [0.0]) == [0.5, 0.5]
    for location in (-1_000.0, 1_000.0)
        probabilities = probability(location, [-0.6, 0.1, 0.5])
        @test all(isfinite, probabilities)
        @test sum(probabilities) ≈ 1 atol = 1e-14
        @test probabilities[location < 0 ? 1 : end] == 1.0
    end
    # Half-open CDF bins, including zero-probability endpoints and labels
    # that differ from the zero-based category position in the equation.
    for first_category in (-2, 0, 1)
        levels = collect(first_category:(first_category + 3))
        @test draw(0.0, [0.0, 0.25, 0.75, 0.0], levels) == levels[2]
        @test draw(0.25, [0.0, 0.25, 0.75, 0.0], levels) == levels[3]
        @test draw(prevfloat(1.0), [0.0, 0.25, 0.75, 0.0], levels) == levels[3]
    end
    @test_throws ArgumentError draw(-eps(), [0.5, 0.5], [0, 1])
    @test_throws ArgumentError draw(1.0, [0.5, 0.5], [0, 1])

    source = joinpath(@__DIR__, "..", "src", "local_dependence_known_truth_dgp.jl")
    code = "include(ARGS[1]); @assert !isdefined(Main, :BayesianMGMFRM); " *
        "print(_ld1_pcm_probabilities(0.0, [0.0]))"
    command = addenv(`$(Base.julia_cmd()) --startup-file=no -e $code $source`,
        "JULIA_LOAD_PATH" => "@stdlib")
    @test read(command, String) == "[0.5, 0.5]"
end

@testset "MFRM anchor generator versus identified RSM and PCM" begin
    probability = MFRMAnchorStandaloneDGP._ld1_pcm_probabilities
    persons = ["P3", "P1", "P4", "P2"]
    raters = ["R3", "R1", "R2"]
    items = ["I3", "I1", "I2"]
    theta = Dict(zip(persons, [-0.9, -0.3, 0.3, 0.9]))
    severity = Dict(zip(raters, [-0.6, 0.1, 0.5]))
    difficulty = Dict(zip(items, [-0.4, 0.2, 0.7]))
    selected(mask, labels) = [label for (index, label) in pairs(labels)
        if !iszero(mask & (1 << (index - 1)))]

    # 2 families x 3 category counts x 2 designs x 8 x 8 anchor masks = 768.
    # Truth is assembled by semantic labels, never extracted from fit helpers.
    for thresholds in (:rating_scale, :partial_credit),
            (categories, first_category) in ((2, -2), (3, 1), (5, 0)),
            sparse in (false, true)
        levels = collect(first_category:(first_category + categories - 1))
        events = [(p, r, i) for p in 1:4 for r in 1:3 for i in 1:3
            if !sparse || r in (mod1(p, 3), mod1(p + 1, 3))]
        sparse && reverse!(events)
        table = (;
            person = [persons[p] for (p, r, i) in events],
            rater = [raters[r] for (p, r, i) in events],
            item = [items[i] for (p, r, i) in events],
            score = [levels[mod1(p + 2r + i, categories)] for (p, r, i) in events],
        )
        data = FacetData(table; person = :person, rater = :rater,
            item = :item, score = :score, category_levels = levels)
        steps = Dict{String,Vector{Float64}}()
        for (i, label) in pairs(items)
            owner = thresholds === :rating_scale ? 1 : i
            free = [0.15 * s - 0.11 * owner for s in 1:(categories - 2)]
            steps[label] = vcat(free, -sum(free))
        end
        expected = reduce(vcat, [permutedims(probability(
            theta[p] - severity[r] - difficulty[i], steps[i]))
            for (p, r, i) in zip(table.person, table.rater, table.item)])
        expected_loglikelihood = [log(expected[row, score - first_category + 1])
            for (row, score) in pairs(table.score)]

        for rater_mask in 0:7, item_mask in 0:7
            fixed_raters = selected(rater_mask, raters)
            fixed_items = selected(item_mask, items)
            # Common shifts remain compatible even with multiple anchors.
            # The untouched zero-centered priors are NOT claimed invariant.
            rater_shift = isempty(fixed_raters) ? -severity[first(data.rater_levels)] : 0.4
            item_shift = isempty(fixed_items) ? -difficulty[first(data.item_levels)] : -0.3
            anchors = vcat(
                [(; block = :rater, level, value = severity[level] + rater_shift,
                    type = :hard) for level in fixed_raters],
                [(; block = :item, level, value = difficulty[level] + item_shift,
                    type = :hard) for level in fixed_items])
            design = getdesign(mfrm_spec(data; thresholds, anchors))
            isempty(fixed_raters) && push!(fixed_raters, first(data.rater_levels))
            isempty(fixed_items) && push!(fixed_items, first(data.item_levels))
            values = Dict("person[$level]" => theta[level] + rater_shift + item_shift
                for level in persons)
            merge!(values, Dict("rater[$level]" => severity[level] + rater_shift
                for level in raters if level ∉ fixed_raters))
            merge!(values, Dict("item[$level]" => difficulty[level] + item_shift
                for level in items if level ∉ fixed_items))
            for label in (thresholds === :rating_scale ? items[1:1] : items),
                    step in 1:(categories - 2)
                name = thresholds === :rating_scale ? "step[$step]" : "step[item=$label,$step]"
                values[name] = steps[label][step]
            end
            @test Set(design.parameter_names) == Set(keys(values))
            params = [values[name] for name in design.parameter_names]
            actual = dropdims(predictive_probabilities(design, reshape(params, 1, :)); dims = 1)
            @test actual ≈ expected atol = 1e-12 rtol = 0
            @test pointwise_loglikelihood(design, params) ≈ expected_loglikelihood atol = 1e-12 rtol = 0
            if rater_mask == item_mask == 0b101
                # Differential error excludes the original truth. Cross signs
                # to check that opposite facet errors cannot cancel globally.
                for magnitude in (0.2, 0.8), rater_sign in (-1, 1), item_sign in (-1, 1)
                    dr, di = magnitude * rater_sign, magnitude * item_sign
                    perturbed = [merge(anchor, (; value = anchor.value +
                        (anchor.block === :rater && anchor.level == raters[3] ? dr :
                         anchor.block === :item && anchor.level == items[3] ? di : 0.0)))
                        for anchor in anchors]
                    constrained = getdesign(mfrm_spec(data; thresholds, anchors = perturbed))
                    constrained_params = [values[name] for name in constrained.parameter_names]
                    constrained_expected = reduce(vcat, [permutedims(probability(
                        theta[p] - severity[r] - difficulty[i] -
                        (r == raters[3] ? dr : 0.0) - (i == items[3] ? di : 0.0), steps[i]))
                        for (p, r, i) in zip(table.person, table.rater, table.item)])
                    constrained_actual = dropdims(predictive_probabilities(
                        constrained, reshape(constrained_params, 1, :)); dims = 1)
                    @test constrained_actual ≈ constrained_expected atol = 1e-12 rtol = 0
                    # Detect accidental equality, not a practical effect size.
                    @test maximum(abs.(constrained_expected .- expected)) > 1e-4
                end
            end
        end
    end
end
