using Test
using Random
using Serialization
using SHA
using Statistics
using JSON3

# M1 preparation only: reuse the standalone generator, not the fitting kernel.
# No MCMC, evaluation seeds, research fixtures, or new exports are needed.
module MFRMAnchorStandaloneDGP
include(joinpath(@__DIR__, "..", "src", "local_dependence_known_truth_dgp.jl"))
end

using BayesianMGMFRM

function mfrm_anchor_test_panel(sparse; events = [(p, r, i) for p in 1:40 for r in 1:4 for i in 1:4
        if !sparse || r in (mod1(p, 4), mod1(p + 1, 4))])
    data = FacetData((;
        person = ["P$(lpad(string(p), 2, '0'))" for (p, r, i) in events],
        rater = ["R$r" for (p, r, i) in events],
        item = ["I$i" for (p, r, i) in events],
        score = [mod(p + r + i, 4) for (p, r, i) in events],
    ); person = :person, rater = :rater, item = :item,
        score = :score, category_levels = 0:3)
    return events, data
end

mfrm_anchor_test_targets() = [
    (; name = "R3-R2", block = :rater, positive = "R3", negative = "R2", role = :primary),
    (; name = "I3-I2", block = :item, positive = "I3", negative = "I2", role = :primary),
    (; name = "P30-P10", block = :person, positive = "P30", negative = "P10", role = :primary),
    (; name = "R2-R1", block = :rater, positive = "R2", negative = "R1", role = :secondary),
    (; name = "I2-I1", block = :item, positive = "I2", negative = "I1", role = :secondary)]

# Prior-only audit: each row is one independent parameter draw, not one rating.
function mfrm_anchor_prior_profile(design, prior; ndraws, rng)
    draws = BayesianMGMFRM._prior_parameter_draws(design, prior, ndraws, rng)
    p = predictive_probabilities(design, draws)
    @assert size(p) == (ndraws, design.spec.data.n, 4)
    @assert all(isfinite, p) && all(x -> 0 <= x <= 1, p)
    @assert all(x -> isapprox(x, 1; atol = 1e-12), sum(p; dims = 3))
    return [(;
        endpoint_mass = mean(p[s, :, 1] .+ p[s, :, 4]),
        saturated_fraction = mean(maximum(p[s, :, :]; dims = 2) .> 0.95),
        expected_score = mean(p[s, :, 2] .+ 2 .* p[s, :, 3] .+ 3 .* p[s, :, 4]),
    ) for s in 1:ndraws]
end

@testset "M1 precision planning and derived-contrast MCSE (no fits)" begin
    precision = mgmfrm_validation_replication_precision((100, 400, 900, 2500);
        nominal_coverage = 0.9, coverage_mcse_target = 0.015,
        binary_rate_mcse_target = 0.025)
    @test precision.minimum_replications.coverage == 400
    @test precision.minimum_replications.binary_rate_worst_case == 400
    @test ismissing(precision.minimum_replications.bias)
    @test !precision.execution_authorized
    for row in precision.rows
        @test row.nominal_coverage_mcse ≈ sqrt(0.09 / row.replications)
        @test row.binary_rate_worst_case_mcse ≈ 0.5 / sqrt(row.replications)
    end
    # Zero failures: exact marginal bound and a conservative family-wise bound.
    for cells in (1, 16, 266)
        n = ceil(Int, log(0.05 / cells) / log(0.99))
        @test -expm1(log(0.05 / cells) / n) <= 0.01
        @test -expm1(log(0.05 / cells) / (n - 1)) > 0.01
    end
    @test 16 * 400 + (266 - 16) * 100 == 31_400
    @test 266 * 400 == 106_400
    @test 4 * 400 + (8 + 10 + 8) * 100 == 4_200
    @test (4 + 8 + 10 + 8) * 400 == 12_000
    # Synthetic columns stand for labelled R2/R3, not fitted posterior draws.
    draws = randn(MersenneTwister(17), 4 * 40, 2)
    contrast = reshape(draws[:, 2] .- draws[:, 1], :, 1)
    row = only(posterior_mcse(contrast; chains = 4,
        parameter_names = ["R3 - R2"], probabilities = (0.05, 0.95)))
    @test row.mcse_status === :available
    @test row.parameter == "R3 - R2"
    @test row.convergence_review_required && !row.precision_threshold_applied
    @test [q.probability for q in row.quantiles] == [0.05, 0.95]
    @test all(q -> isfinite(q.mcse) && q.mcse >= 0, row.quantiles)
    @test isfinite(row.mean_mcse) && row.mean_mcse >= 0
    @test all(q -> q.estimate ≈ quantile(vec(contrast), q.probability), row.quantiles)
end

@testset "M1 prior/start and response/link-misfit candidate algebra (no fits)" begin
    _, data = mfrm_anchor_test_panel(true)
    hard(block, label, value) = (; block, level = label, value, type = :hard)
    raters = [hard(:rater, "R1", 0.0), hard(:rater, "R4", 1.5)]
    items = [hard(:item, "I1", 0.0), hard(:item, "I4", 1.2)]
    regimes = (raters[1:0], raters, items, [raters; items],
        [merge(a, (; value = a.value + 0.8)) for a in raters],
        [merge(a, (; value = a.value + 0.8)) for a in items])
    for family in (:rating_scale, :partial_credit), anchors in regimes
        design = getdesign(mfrm_spec(data; thresholds = family, anchors))
        n = length(design.parameter_names)
        x = collect(range(-1.0, 1.0; length = n))
        sds = ones(n)
        sds[design.blocks[:person]] .= 1.5
        reference_at_zero = -sum(log.(sds)) - n * log(2pi) / 2
        for c in (0.5, 1.0, 2.0)
            prior = MFRMPrior(; person_sd = 1.5c, rater_sd = c,
                item_sd = c, step_sd = c)
            @test logprior(design, x, prior) ≈ reference_at_zero -
                n * log(c) - sum(abs2, x ./ sds) / (2c^2)
            profile = mfrm_anchor_prior_profile(design, prior;
                ndraws = 4, rng = MersenneTwister(17))
            @test length(profile) == 4
            @test profile == mfrm_anchor_prior_profile(design, prior;
                ndraws = 4, rng = MersenneTwister(17))
            @test all(r -> 0 <= r.endpoint_mass <= 1 &&
                0 <= r.saturated_fraction <= 1 && 0 <= r.expected_score <= 3, profile)
        end
        initial = BayesianMGMFRM._fit_initial_params(design, nothing)
        @test initial == zeros(n)
        small = BayesianMGMFRM._advancedhmc_initial(initial, MersenneTwister(17), 0.02)
        wide = BayesianMGMFRM._advancedhmc_initial(initial, MersenneTwister(17), 0.5)
        @test wide ≈ 25 .* small
        @test initial == zeros(n) # The helper must not mutate the base start.
        @test small == BayesianMGMFRM._advancedhmc_initial(initial, MersenneTwister(17), 0.02)
        rng = MersenneTwister(17)
        @test BayesianMGMFRM._advancedhmc_initial(initial, rng, 0.0) == initial
        @test rand(rng) == rand(MersenneTwister(17))
    end
    # Independent raw steps induce a correlated, non-exchangeable full-step prior.
    step_map = [1 0; 0 1; -1 -1]
    @test step_map * transpose(step_map) == [1 0 -1; 0 1 -1; -1 -1 2]

    probability = MFRMAnchorStandaloneDGP._ld1_pcm_probabilities
    theta = collect(range(-1.2, 1.2; length = 40)) .+ 1.35
    pcm = ([-0.6, 0.0, 0.6], [-0.4, 0.1, 0.3],
        [-0.8, 0.3, 0.5], [-0.2, -0.1, 0.3])
    for family in (:rating_scale, :partial_credit), topology in (:S, :N_C4)
        events = [(p, r, i) for p in 1:40 for r in 1:4 for i in 1:4
            if topology === :S ? r in (mod1(p, 4), mod1(p + 1, 4)) :
                (p in 19:22 || r in (isodd(p) ? (1, 2) : (3, 4)))]
        affected(p, r) = r == 4 && (topology === :S || p in 19:22)
        @test length(events) == (topology === :S ? 320 : 352)
        @test count(e -> affected(e[1], e[2]), events) == (topology === :S ? 80 : 16)
        for coefficient in (-0.35, 0.0, 0.35), (p, r, i) in events
            steps = pcm[family === :rating_scale ? 1 : i]
            eta = theta[p] - 0.5(r - 1) - 0.4(i - 1)
            lambda = affected(p, r) ? coefficient : 0.0
            base = probability(eta, steps)
            weights = base .* exp.(lambda .* ((0:3) .- 1.5).^2)
            actual = weights ./ sum(weights) # Existing pilot's tilt equation.
            oracle = setprecision(BigFloat, 256) do
                w = [exp(k * BigFloat(eta) - sum(BigFloat.(steps[1:k]); init = big"0") +
                    BigFloat(lambda) * (k - big"1.5")^2) for k in 0:3]
                Float64.(w ./ sum(w))
            end
            @test actual ≈ oracle atol = 1e-13 rtol = 0
            @test all(>(0), actual) && sum(actual) ≈ 1
            @test diff(log.(actual)) - diff(log.(base)) ≈
                lambda .* [-2.0, 0.0, 2.0] atol = 1e-12 rtol = 0
            endpoint(q) = q[1] + q[4]
            @test (endpoint(actual) / (1 - endpoint(actual))) /
                (endpoint(base) / (1 - endpoint(base))) ≈ exp(2lambda)
        end
    end
    # With two categories the centered quadratic is constant, not misfit.
    binary = probability(0.4, [0.0])
    for coefficient in (-0.35, 0.35)
        weights = binary .* exp.(coefficient .* ((0:1) .- 0.5).^2)
        @test weights ./ sum(weights) ≈ binary
    end
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

@testset "M1 nonlinear predictive-score MCSE candidate (no fits)" begin
    delta = BayesianMGMFRM._mfrm_anchor_log_score_delta_mcse
    score(p, q) = mgmfrm_predictive_recovery_score(p, q).summary.mean_log_score_regret
    rng = MersenneTwister(17)
    x = 0.45 .+ 0.08 .* tanh.(randn(rng, 160))
    p = zeros(160, 2, 2)
    p[:, 1, 1] = x
    p[:, 2, 1] = 0.2 .+ 0.5 .* x
    p[:, :, 2] = 1 .- p[:, :, 1]
    q = [0.7 0.3; 0.2 0.8]
    m = dropdims(mean(p; dims = 1); dims = 1)
    result = delta(log.(p), log.(q); chains = 4)
    @test result.status === :first_order_candidate
    @test result.estimate ≈ score(p, q)
    @test result.estimate < mean(score(p[s, :, :], q) for s in 1:160)
    @test result.convergence_review_required && result.curvature_review_required
    @test !result.precision_threshold_applied && !result.validation_claim_allowed
    expected = [-sum(q .* (p[s, :, :] ./ m .- 1)) / 2 for s in 1:160]
    @test result.influence ≈ expected atol = 1e-14
    @test mean(result.influence) ≈ 0 atol = 1e-14
    direct = only(posterior_mcse(reshape(expected, :, 1); chains = 4, probabilities = ()))
    @test result.mcse ≈ direct.mean_mcse
    for s in (1, 40, 41, 160), h in (1e-4, 1e-5)
        direction = p[s, :, :] .- m # A tangent to each probability simplex.
        finite_difference = (score(m .+ h .* direction, q) -
            score(m .- h .* direction, q)) / (2h)
        @test result.influence[s] ≈ finite_difference atol = 1e-9
    end
    # Duplicating correlated forecast events does not double independent N.
    single = delta(log.(p[:, 1:1, :]), log.(q[1:1, :]); chains = 4)
    duplicate = delta(log.(p[:, [1, 1], :]), log.(q[[1, 1], :]); chains = 4)
    @test duplicate.influence ≈ single.influence
    @test duplicate.mcse ≈ single.mcse
    weighted = delta(log.(p[:, [1, 1, 1, 2], :]), log.(q[[1, 1, 1, 2], :]); chains = 4)
    other = delta(log.(p[:, 2:2, :]), log.(q[2:2, :]); chains = 4)
    @test weighted.influence ≈ (3 .* single.influence .+ other.influence) ./ 4
    permuted = delta(log.(p[:, [2, 1], [2, 1]]), log.(q[[2, 1], [2, 1]]); chains = 4)
    @test permuted.estimate ≈ result.estimate
    @test permuted.influence ≈ result.influence
    @test permuted.mcse ≈ result.mcse
    chain_order = vcat(81:120, 1:40, 121:160, 41:80)
    reordered = delta(log.(p[chain_order, :, :]), log.(q); chains = 4)
    @test reordered.influence ≈ result.influence[chain_order]
    @test reordered.mcse ≈ result.mcse

    # At q=m, the first derivative along the simplex vanishes, but finite
    # sub-batch means still give positive KL: do not report MCSE=0 or pass.
    stationary = delta(log.(p), log.(m); chains = 4)
    @test stationary.status === :first_order_degenerate
    @test ismissing(stationary.mcse)
    @test score(p[1:40, :, :], m) > 0
    # Cross-event cancellation can degenerate even away from q=m.
    z = 0.08 .* tanh.(randn(rng, 80))
    mirrored = copy(p)
    mirrored[:, 1, 1] = 0.5 .+ [z; -z]
    mirrored[:, 2, 1] = 1 .- mirrored[:, 1, 1]
    mirrored[:, :, 2] = 1 .- mirrored[:, :, 1]
    cancelled = delta(log.(mirrored), log.([0.8 0.2; 0.8 0.2]); chains = 4)
    @test cancelled.status === :first_order_degenerate
    @test cancelled.estimate > 0 && ismissing(cancelled.mcse)
    # Heldout one-hot log loss remains finite even when exp(log p) underflows.
    tiny = zeros(160, 1, 2)
    tiny[:, 1, 2] = -1000 .+ tanh.(randn(rng, 160))
    heldout = delta(tiny, [-Inf 0.0]; chains = 4)
    @test all(iszero, exp.(tiny[:, 1, 2]))
    @test heldout.status === :first_order_candidate && isfinite(heldout.mcse)
    @test heldout.estimate ≈ -BayesianMGMFRM._logmeanexp(vec(tiny[:, 1, 2]))
    unsupported = delta(repeat(reshape([0.0, -Inf], 1, 1, 2), 160, 1, 1),
        [-Inf 0.0]; chains = 4)
    @test unsupported.status === :nonfinite_log_score
    @test unsupported.estimate == Inf && ismissing(unsupported.mcse)
    for chains in (0, -1, 3, true)
        @test_throws ArgumentError delta(log.(p), log.(q); chains)
    end
    @test delta(log.(p), log.(q); chains = 1).status === :insufficient_chains
    @test delta(log.(p[1:32, :, :]), log.(q); chains = 4).status === :insufficient_draws
    for invalid in (NaN, Inf, 0.1, -Inf)
        bad = copy(log.(p)); bad[1, 1, :] .= invalid
        @test_throws ArgumentError delta(bad, log.(q); chains = 4)
    end
    @test_throws ArgumentError delta(log.(p), log.(q[1:1, :]); chains = 4)

    # A synthetic payload-binding composition, not a fitted artifact or ledger.
    # The externally retained digest is essential; a self-reported hash is not trust.
    identity = (; dataset_id = "synthetic/train", heldout_id = "synthetic/heldout", method = "B")
    digest(text) = bytes2hex(sha256(codeunits(text)))
    record = merge(identity, (; attempt = 1, status = :synthetic_only,
        source_sha256 = digest("synthetic source, not a repository revision"),
        training_sha256 = digest("synthetic train bytes"),
        heldout_sha256 = digest("synthetic heldout bytes"),
        chain_layout = (; chains = 4, draws_per_chain = 40, order = :contiguous),
        logdraws = log.(p), logtruth = log.(q),
        diagnostic_policy = (; rhat_threshold = 1.01, ess_threshold = 400),
        diagnostic_result = (; status = :not_evaluated, passed = false),
        predictive_precision = result))
    bound_hash = artifact_content_hash(record)
    io = IOBuffer(); serialize(io, record); seekstart(io)
    restored = deserialize(io) # Only bytes created here; not an untrusted importer.
    @test artifact_content_hash(restored) == bound_hash
    joined = only(BayesianMGMFRM._mfrm_anchor_primary_attempts([identity], [restored]))
    @test joined.predictive_precision.estimate == result.estimate
    for changed in (merge(record, (; source_sha256 = digest("different source"))),
            merge(record, (; training_sha256 = digest("different responses"))),
            merge(record, (; heldout_sha256 = digest("different heldout"))),
            merge(record, (; chain_layout = (; chains = 2, draws_per_chain = 80, order = :contiguous))),
            merge(record, (; logdraws = log.(p[chain_order, :, :]))),
            merge(record, (; logtruth = log.(m))),
            merge(record, (; diagnostic_policy = (; rhat_threshold = 1.1, ess_threshold = 20))),
            merge(record, (; diagnostic_result = (; status = :not_evaluated, passed = true))),
            merge(record, (; predictive_precision = merge(result, (; mcse = 0.0)))),
            merge(record, (; attempt = 2)))
        @test artifact_content_hash(changed) != bound_hash
    end
    # These names are recursively excluded by the existing archive hash policy.
    @test artifact_content_hash(merge(record, (; content_hash = "not a binding"))) == bound_hash
    @test artifact_content_hash(merge(record, (; archive_manifest = "not a binding"))) == bound_hash
end

@testset "M1 predictive-score curvature oracle (no fits)" begin
    # Exact count distribution for independent, stationary two-state chains.
    # Forecast vectors are (0.3, 0.7)/(0.7, 0.3); no sampled paths or fitter.
    function count_weights(length_per_chain, chains, flip)
        total = length_per_chain * chains
        weights = zeros(total + 1, 2)
        weights[1, 1] = weights[2, 2] = 0.5
        for t in 2:total
            # A new chain starts independently, not by a boundary transition.
            switch = (t - 1) % length_per_chain == 0 ? 0.5 : flip
            next = zeros(size(weights))
            for k in 0:(t - 1)
                next[k + 1, 1] += (1 - switch) * weights[k + 1, 1] + switch * weights[k + 1, 2]
                next[k + 2, 2] += switch * weights[k + 1, 1] + (1 - switch) * weights[k + 1, 2]
            end
            weights = next
        end
        return vec(sum(weights; dims = 2))
    end
    # Independent brute-force oracle for two chains of four draws.
    for flip in (0.1, 0.5, 0.9)
        enumerated = zeros(9)
        for mask in 0:255
            states = [(mask >> (t - 1)) & 1 for t in 1:8]
            enumerated[count_ones(mask) + 1] += 0.25 * prod(
                states[t] == states[t - 1] ? 1 - flip : flip for t in (2, 3, 4, 6, 7, 8))
        end
        @test count_weights(4, 2, flip) ≈ enumerated
    end

    results = Dict()
    for length_per_chain in (40, 160), flip in (0.1, 0.5, 0.9)
        total, amplitude = 4length_per_chain, 0.2
        weights = count_weights(length_per_chain, 4, flip)
        error = amplitude .* (2 .* (0:total) ./ total .- 1)
        variance = sum(weights .* error .^ 2)
        fourth = sum(weights .* error .^ 4)
        rho = 1 - 2flip
        @test sum(weights) ≈ 1
        @test weights ≈ reverse(weights)
        @test variance ≈ amplitude^2 / total * (1 + 2sum(
            (1 - h / length_per_chain) * rho^h for h in 1:(length_per_chain - 1)))
        if flip == 0.5
            @test weights ≈ [Float64(binomial(big(total), k) / big(2)^total) for k in 0:total]
            @test fourth ≈ amplitude^4 * (3total - 2) / total^3
        end
        for offset in (0.0, 0.001, 0.2)
            truth = 0.5 + offset
            # Stable independent equation for F(0.5 + error) - F(0.5).
            increment = -truth .* log1p.(2 .* error) .- (1 - truth) .* log1p.(-2 .* error)
            target = truth * log(2truth) + (1 - truth) * log(2 * (1 - truth))
            scored = [mgmfrm_predictive_recovery_score([0.5 + e 0.5 - e],
                [truth 1 - truth]).summary.mean_log_score_regret for e in error]
            @test scored ≈ target .+ increment atol = 1e-14
            bias = sum(weights .* increment)
            sd = sqrt(sum(weights .* (increment .- bias) .^ 2))
            linear_sd = 4abs(offset) * sqrt(variance)
            quadratic_sd = sqrt(16offset^2 * variance + 4 * (fourth - variance^2))
            @test 0 < bias && linear_sd < sd
            # Fixture comparison only, not a universal second-order MCSE gate.
            @test abs(sd - quadratic_sd) < abs(sd - linear_sd)
            results[(length_per_chain, flip, offset)] = (; bias, sd, linear_sd, quadratic_sd)
        end
    end
    near = results[(40, 0.5, 0.001)]
    @test near.sd > 10near.linear_sd
    @test results[(40, 0.1, 0.001)].sd > near.sd > results[(40, 0.9, 0.001)].sd
    # At the KL stationary point (d=0), SD/bias scale as 1/S, not 1/sqrt(S).
    short, long = results[(40, 0.5, 0.0)], results[(160, 0.5, 0.0)]
    @test short.sd / long.sd ≈ 4 rtol = 0.01
    @test short.bias / long.bias ≈ 4 rtol = 0.01
    @test short.bias > 0 && short.linear_sd == 0

    # A nonzero plug-in derivative does not diagnose proximity to the true
    # stationary point. Keep the review flags even when MCSE is available.
    rng = MersenneTwister(23)
    x = shuffle(rng, [fill(0.3, 80); fill(0.7, 80)])
    p = reshape(hcat(x, 1 .- x), 160, 1, 2)
    delta = BayesianMGMFRM._mfrm_anchor_log_score_delta_mcse
    near_result = delta(log.(p), log.([0.501 0.499]); chains = 4)
    @test near_result.status === :first_order_candidate && near_result.mcse > 0
    # On Julia 1.10 this balanced two-point series has unavailable SD-MCSE,
    # but the target mean-MCSE is finite; do not gate on the whole row status.
    near_mean = only(posterior_mcse(reshape(near_result.influence, :, 1);
        chains = 4, probabilities = ()))
    @test near_result.mcse ≈ near_mean.mean_mcse
    x[findfirst(==(0.3), x)] = 0.7
    shifted = reshape(hcat(x, 1 .- x), 160, 1, 2)
    stationary_result = delta(log.(shifted), log.([0.5 0.5]); chains = 4)
    @test stationary_result.status === :first_order_candidate && stationary_result.mcse > 0
    for result in (near_result, stationary_result)
        @test result.curvature_review_required && result.convergence_review_required
        @test !result.precision_threshold_applied && !result.validation_claim_allowed
    end

    @testset "M2 paired predictive-loss error decomposition (no fits)" begin
        # Exact finite experiment: shared data context, independently sampled
        # methods conditional on it, and unequal draw counts/autocorrelation.
        # This declares coupling for this oracle ONLY, not for study fits.
        probabilities = [count_weights(n, 2, flip)
            for (n, flip) in zip((2, 4, 2, 4), (0.1, 0.5, 0.9, 0.5))]
        states = vec(collect(Iterators.product((eachindex(w) for w in probabilities)...)))
        joint_weights = [prod(probabilities[m][state[m]] for m in 1:4) for state in states]
        @test length(states) == 2025 && sum(joint_weights) ≈ 1
        score(p, q) = mgmfrm_predictive_recovery_score([p 1-p], [q 1-q]).summary.mean_log_score_regret
        comparisons = ([-1, 1, 0, 0], [-1, 0, 1, 0], [0, -1, 0, 1],
            [0, 0, -1, 1], [1, -1, -1, 1]) # B/R/I/RI; lower loss is better.
        for kind in (:truth, :heldout)
            conditional_mean, conditional_var, ideal, observed = (zeros(3, 4) for _ in 1:4)
            joint_losses, joint_cross_entropy = Matrix{Float64}[], Matrix{Float64}[]
            for d in 1:3
                q = kind === :truth ? (0.5, 0.65, 0.8)[d] : 1.0
                losses, cross_entropy = Vector{Float64}[], Vector{Float64}[]
                for m in 1:4
                    mu = 0.38 + 0.055d + (0.0, 0.02, -0.03, 0.04)[m]
                    w = probabilities[m]
                    forecasts = mu .+ 0.12 .* (2 .* (0:(length(w)-1)) ./ (length(w)-1) .- 1)
                    @test sum(w .* forecasts) ≈ mu
                    push!(losses, score.(forecasts, q))
                    push!(cross_entropy, -q .* log.(forecasts) .- (1-q) .* log1p.(-forecasts))
                    conditional_mean[d, m] = sum(w .* losses[m])
                    conditional_var[d, m] = sum(w .* (losses[m] .- conditional_mean[d, m]).^2)
                    ideal[d, m] = score(mu, q)
                    @test conditional_mean[d, m] > ideal[d, m] # Jensen bias, not centered SD.
                end
                push!(joint_losses, hcat(([losses[m][state[m]] for state in states] for m in 1:4)...))
                push!(joint_cross_entropy, hcat(([cross_entropy[m][state[m]] for state in states] for m in 1:4)...))
                observed[d, :] = joint_losses[d][(1, cld(length(states), 2), length(states))[d], :]
            end
            for w in comparisons
                differences = [losses * w for losses in joint_losses]
                means, variances = conditional_mean * w, conditional_var * (w.^2)
                bias = means - ideal * w
                for d in 1:3
                    # Common q's entropy cancels only on the same events/truth.
                    @test differences[d] ≈ joint_cross_entropy[d] * w atol = 1e-14
                    @test sum(joint_weights .* differences[d]) ≈ means[d] atol = 1e-14
                    @test sum(joint_weights .* (differences[d] .- means[d]).^2) ≈ variances[d]
                    @test sum(joint_weights .* (differences[d] .- (ideal * w)[d]).^2) ≈ variances[d] + bias[d]^2
                    @test sum(w .* (conditional_mean[d, :] - ideal[d, :])) ≈ bias[d] atol = 1e-14
                end
                @test any(abs.(bias) .> 1e-8) # Shared data does not cancel unequal curvature bias.
                # Law of total variance around the finite-MC conditional mean,
                # not around the exact-posterior loss when bias is nonzero.
                total_variance = mean(sum(joint_weights .* (x .- mean(means)).^2) for x in differences)
                between = var(means; corrected = false)
                within = mean(variances)
                @test total_variance ≈ between + within
                @test within > 0 && total_variance + within > total_variance
                # Across-data SE already concerns the noisy finite-MC losses.
                # Retain same-data covariance, including in a four-way contrast.
                paired = observed * w
                @test std(paired) / sqrt(3) ≈ sqrt(max(0, sum(w .* (cov(observed) * w))) / 3) atol = 1e-14
                @test mean(observed * (-w)) ≈ -mean(paired) atol = 1e-14
                @test std(observed * (-w)) ≈ std(paired)
            end
            pair = observed[:, 2] - observed[:, 1]
            @test !isapprox(var(pair), var(observed[:, 2]) + var(observed[:, 1]))
        end

        # Marginal chain reordering cannot change a fit's loss/MCSE, but changes
        # invented same-index cross-fit covariance. Never use it as coupling.
        a = delta(log.(p), log.([0.65 0.35]); chains = 4)
        other_p = copy(p)
        other_p[:, 1, 1] .+= 0.05
        other_p[:, 1, 2] .-= 0.05
        b = delta(log.(other_p), log.([0.65 0.35]); chains = 4)
        chain_order = vcat(81:120, 1:40, 121:160, 41:80)
        reordered = delta(log.(other_p[chain_order, :, :]), log.([0.65 0.35]); chains = 4)
        @test all(r -> r.status === :first_order_candidate, (a, b, reordered))
        @test b.estimate ≈ reordered.estimate && b.mcse ≈ reordered.mcse
        @test reordered.influence ≈ b.influence[chain_order]
        @test !isapprox(var(a.influence - b.influence), var(a.influence - reordered.influence))
        @test hypot(a.mcse, b.mcse) ≈ hypot(a.mcse, reordered.mcse)
        # Quadrature above is a first-order candidate ONLY under conditional
        # sampler independence. It neither removes curvature nor sets a gate.
        @test all(r -> r.curvature_review_required && r.convergence_review_required &&
            !r.precision_threshold_applied && !r.validation_claim_allowed, (a, b, reordered))
        unsupported = delta(repeat(reshape([0.0, -Inf], 1, 1, 2), 160, 1, 1), [-Inf 0.0]; chains = 4)
        @test unsupported.estimate == Inf && isnan(unsupported.estimate - unsupported.estimate)
        @test ismissing(unsupported.mcse) # An Inf-Inf pair must remain unresolved, not zero.
    end
end

@testset "M2 sampler RNG ownership boundary (no fits)" begin
    select_rng = BayesianMGMFRM._fit_rng
    jitter = BayesianMGMFRM._advancedhmc_initial
    # Helper-only test seed, never an evaluation allocation or sampler run.
    response_rng = MersenneTwister(17)
    rand(response_rng, 11)
    checkpoint = copy(response_rng)
    owned, control = select_rng(response_rng, 17)
    @test owned !== response_rng
    @test control == (; algorithm = :MersenneTwister, seed = 17, replayable = true)
    replay, replay_control = select_rng(MersenneTwister(29), 17)
    @test control == replay_control && owned == replay
    base = zeros(3)
    @test jitter(base, owned, 0.02) == jitter(base, replay, 0.02)
    @test owned == replay && owned != MersenneTwister(17)
    @test response_rng == checkpoint && base == zeros(3)

    borrowed, unseeded = select_rng(response_rng, nothing)
    @test borrowed === response_rng
    @test isequal(unseeded, (; algorithm = :MersenneTwister, seed = missing, replayable = false))
    @test jitter(base, borrowed, 0.02) == jitter(base, copy(checkpoint), 0.02)
    @test response_rng != checkpoint # Reusing a live response allocator would advance it.
    other, other_control = select_rng(copy(checkpoint), nothing)
    @test isequal(unseeded, other_control) && borrowed != other
    # Matching unseeded metadata does not identify the actual RNG state.
    saved = copy(response_rng)
    for invalid in (17.0, "17", big(typemax(Int)) + 1)
        @test_throws ArgumentError select_rng(response_rng, invalid)
        @test response_rng == saved
    end
end

@testset "M2 attempt-bound fit-object scoring (no fits)" begin
    consume = BayesianMGMFRM._mfrm_anchor_score_attempt
    fit_hash = BayesianMGMFRM._mfrm_anchor_fit_hash
    raw(record) = collect(codeunits(JSON3.write(record)))
    response_ref(record) = (; record.dataset_id, record.role,
        sha256 = bytes2hex(sha256(raw(record))))
    tuples = [(p, r, i) for p in 1:2 for r in 1:2 for i in 1:2]
    levels = [-2, -1, 0]
    rows = [(; person = "P/$p", rater = "R$r", item = "I$i",
        score = levels[mod1(p + r + i, 3)]) for (p, r, i) in tuples]
    training = (; dataset_id = "synthetic/train", role = "train", category_levels = levels, rows)
    heldout = (; dataset_id = "synthetic/heldout", role = "heldout", category_levels = levels,
        rows = reverse([merge(row, (; score = levels[mod1(n, 3)])) for (n, row) in pairs(rows)]))
    train_bytes, heldout_bytes = raw(training), raw(heldout)
    train = BayesianMGMFRM._mfrm_anchor_response_data(train_bytes, response_ref(training))
    source_files = Dict(abspath(joinpath(@__DIR__, "..", path)) =>
        bytes2hex(sha256(read(joinpath(@__DIR__, "..", path)))) for path in
        ("Project.toml", "src/facet_workflow.jl", "src/model_contract.jl",
            "src/bayesian_fit.jl", "src/practitioner_diagnostics.jl", "src/mgmfrm_validation_scoring.jl"))
    # Test thresholds only; not adoption of the proposed study policy.
    policy = (; split_chains = true, rhat_threshold = 1.2, ess_threshold = 20)
    screen_policy = merge(policy, (; min_e_bfmi = 0.3))
    contrasts = [(; name = string(block, "/2-1"), block,
        positive = labels[2], negative = labels[1], probabilities = (0.05, 0.95),
        mean_mcse_max = nothing, endpoint_mcse_max = nothing)
        for (block, labels) in ((:person, ("P/1", "P/2")),
            (:rater, ("R1", "R2")), (:item, ("I1", "I2")))]
    @test_throws ArgumentError consume(nothing, train_bytes, heldout_bytes, []; reference = (;))
    @test_throws ArgumentError fit_hash(nothing)
    rng = MersenneTwister(29)
    for family in (:rating_scale, :partial_credit), anchor_block in (:none, :rater, :item, :both, :all_fixed)
        anchors = [(; block, level = string(block === :rater ? "R" : "I", level),
            value = 0.2 * level, type = :hard)
            for block in (:rater, :item) for level in (anchor_block === :all_fixed ? (1, 2) : (2,))
            if anchor_block in (block, :both, :all_fixed)]
        design = getdesign(mfrm_spec(train; thresholds = family, anchors))
        draws = 0.2 .* randn(rng, 160, length(design.parameter_names))
        # Explicitly constructed synthetic object, never returned by a fit call.
        fitted = MFRMFit(design, MFRMPrior(), draws, zeros(160), 0.5,
            repeat(1:4; inner = 40), repeat(1:40, 4), fill(0.5, 4),
            :julia, :random_walk_metropolis, 0, 0.05)
        rebuild(; prior = fitted.prior, values = fitted.draws,
                ids = fitted.chain_ids, iterations = fitted.iterations,
                logps = fitted.log_posterior, stats = fitted.sampler_stats,
                backend = fitted.backend, sampler = fitted.sampler,
                controls = fitted.sampler_controls) =
            MFRMFit(design, prior, values, logps, fitted.acceptance_rate,
                ids, iterations, fitted.chain_acceptance_rate, backend,
                sampler, fitted.warmup, fitted.step_size, stats, controls)
        truth = [merge(rows[n], (; category = level,
            log_probability = MFRMAnchorStandaloneDGP._ld1_pcm_probabilities(
                0.3p - 0.1r - 0.2i,
                family === :rating_scale ? [-0.4, 0.4] : [-0.2i, 0.2i];
                log_probabilities = true)[k]))
            for (n, (p, r, i)) in pairs(tuples) for (k, level) in pairs(levels)]
        reference = (; training.dataset_id, heldout_id = heldout.dataset_id,
            method = string(family, "/", anchor_block), attempt = 1,
            training = response_ref(training), heldout = response_ref(heldout),
            fit_sha256 = fit_hash(fitted), truth_sha256 = BayesianMGMFRM._cache_hash(truth),
            source_files, diagnostic_policy = screen_policy, contrasts, cell = nothing)
        result = consume(fitted, train_bytes, heldout_bytes, truth; reference)
        @test result.status === :scored && result.attempt == 1
        @test result.evaluation_scope == (; declared_panel = false, panel_id = nothing,
            weighting = :equal_event, n_training_events = 8, n_evaluation_events = 8)
        @test result.content_hash == artifact_content_hash(result)
        @test result.precision_status === :unresolved && !result.validation_claim_allowed
        @test result.diagnostic_acceptance_review_required && result.source_coverage_review_required
        @test result.source_coverage == (; status = :undeclared, required_source_paths = nothing)
        if family === :rating_scale && anchor_block === :none
            # Bind the actual Project/Manifest bytes without inventing a new
            # execution-provenance schema or claiming source/RNG completeness.
            environment = BayesianMGMFRM._evidence_project_hashes(; include_paths = true)
            project, manifest = environment["active_project"], environment["manifest"]
            @test project == Base.active_project()
            @test manifest == Base.project_file_manifest_path(project)
            @test manifest !== nothing
            files = merge(source_files, Dict(project => environment["active_project_sha256"],
                manifest => environment["manifest_sha256"]))
            retained = merge(reference, (; source_files = files))
            environment_bound = consume(fitted, train_bytes, heldout_bytes, truth; reference = retained)
            @test environment_bound.reference.source_files == files
            @test environment_bound.truth_score.estimate == result.truth_score.estimate
            @test environment_bound.heldout_score.estimate == result.heldout_score.estimate
            @test environment_bound.source_coverage_review_required && !environment_bound.validation_claim_allowed
            for path in (project, manifest)
                bad = merge(retained, (; source_files = merge(files, Dict(path => "0"^64))))
                @test_throws ArgumentError consume(fitted, train_bytes, heldout_bytes, truth; reference = bad)
            end
            @test files == environment_bound.reference.source_files
            # Test-only conservative snapshot, not an accepted execution roster.
            # Retain the declaration separately before removing digest entries.
            required_source_paths = sort!([project, manifest, abspath(@__FILE__),
                [joinpath(dir, name) for (dir, _, names) in walkdir(joinpath(dirname(@__DIR__), "src"))
                    for name in names if endswith(name, ".jl") || endswith(name, ".stan")]...])
            covered_files = Dict(path => bytes2hex(sha256(read(path))) for path in required_source_paths)
            declared = merge(reference, (; source_files = covered_files, required_source_paths))
            original = deepcopy(declared)
            covered = consume(fitted, train_bytes, heldout_bytes, truth; reference = declared)
            @test covered.source_coverage == (; status = :declared_roster_covered,
                required_source_paths = Tuple(required_source_paths))
            @test covered.truth_score.estimate == result.truth_score.estimate
            @test covered.heldout_score.estimate == result.heldout_score.estimate
            @test covered.source_coverage_review_required && !covered.validation_claim_allowed
            @test covered.content_hash == artifact_content_hash(covered)
            for path in required_source_paths
                omitted = filter(pair -> first(pair) != path, covered_files)
                bad = merge(declared, (; source_files = omitted))
                @test_throws ArgumentError consume(fitted, train_bytes, heldout_bytes, truth; reference = bad)
            end
            for invalid in ((), String[], project, Set([project]), (project, project), (nothing,),
                    (true,), ("Project.toml",), (joinpath(dirname(project), ".", basename(project)),),
                    (joinpath(dirname(project), "absent-source.jl"),))
                bad = merge(declared, (; required_source_paths = invalid))
                @test_throws ArgumentError consume(fitted, train_bytes, heldout_bytes, truth; reference = bad)
            end
            subset_reference = merge(declared, (; required_source_paths = (project, manifest)))
            subset_report = consume(fitted, train_bytes, heldout_bytes, truth; reference = subset_reference)
            @test subset_report.source_coverage.required_source_paths == Tuple(sort([project, manifest]))
            # Extra supplied files still need valid contents even outside the roster.
            extra = abspath(@__FILE__)
            bad = merge(subset_reference, (; source_files = merge(covered_files, Dict(extra => "0"^64))))
            @test_throws ArgumentError consume(fitted, train_bytes, heldout_bytes, truth; reference = bad)
            explicit_none = consume(fitted, train_bytes, heldout_bytes, truth;
                reference = merge(declared, (; required_source_paths = nothing)))
            @test explicit_none.source_coverage.status === :undeclared
            shared = BayesianMGMFRM._mfrm_anchor_check_shared_data
            reordered = merge(declared, (; required_source_paths = Tuple(reverse(required_source_paths))))
            @test shared([covered, merge(covered, (; reference = reordered))]) === nothing
            @test_throws ArgumentError shared([covered, subset_report])
            @test_throws ArgumentError shared([covered, explicit_none])
            # Dropping the declaration and recomputing the report's hash cannot
            # bypass the separately retained planned reference digest.
            checked = BayesianMGMFRM._mfrm_anchor_checked_primary
            plan = [(; declared.dataset_id, declared.heldout_id, declared.method,
                reference_sha256 = BayesianMGMFRM._cache_hash(declared))]
            source_attempt_hashes = report -> Dict((report.dataset_id, report.heldout_id, report.method, report.attempt) =>
                BayesianMGMFRM._cache_hash(report))
            @test isequal(only(checked(plan, [covered], source_attempt_hashes(covered))), covered)
            @test_throws ArgumentError checked(plan, [explicit_none], source_attempt_hashes(explicit_none))
            @test_throws ArgumentError checked(plan, [result], source_attempt_hashes(result))
            @test declared == original && covered.reference == original
            @test files == environment_bound.reference.source_files
            # Existing hashes bind recorded RNG controls, not their execution.
            _, rng_control = BayesianMGMFRM._fit_rng(MersenneTwister(29), 17)
            controlled = rebuild(; controls = (; rng = rng_control))
            controlled_reference = merge(reference, (; fit_sha256 = fit_hash(controlled)))
            rng_report = consume(controlled, train_bytes, heldout_bytes, truth; reference = controlled_reference)
            @test fit_metadata(controlled).sampler_controls.rng == rng_control
            @test rng_report.status === :scored && !rng_report.validation_claim_allowed
            @test rng_report.truth_score.estimate == result.truth_score.estimate
            for patch in ((; seed = 18), (; algorithm = :Xoshiro), (; replayable = false),
                    (; chain_seeds = (17, 18)))
                altered = rebuild(; controls = (; rng = merge(rng_control, patch)))
                @test fit_hash(altered) != controlled_reference.fit_sha256
                @test_throws ArgumentError consume(altered, train_bytes, heldout_bytes, truth;
                    reference = controlled_reference)
            end
        end
        @test result.truth_score.curvature_review_required && result.heldout_score.curvature_review_required
        @test artifact_content_hash(result.diagnostics) == artifact_content_hash(diagnostics(fitted; policy...))
        @test !result.diagnostics.summary.e_bfmi_complete # No invented HMC diagnostics.
        @test result.hmc_screen.status === :not_applicable_backend && !result.hmc_screen.passed
        @test length(result.contrast_scores) == 3
        for (request, scored) in zip(contrasts, result.contrast_scores)
            # Independent name/declared-anchor lookup, including all-free persons.
            function coordinate(label)
                index = findfirst(==("$(request.block)[$label]"), design.parameter_names)
                index !== nothing && return draws[:, index]
                anchor = findfirst(a -> a.block === request.block && a.level == label, anchors)
                return fill(anchor === nothing ? 0.0 : anchors[anchor].value, size(draws, 1))
            end
            paired = reshape(coordinate(request.positive) .- coordinate(request.negative), :, 1)
            @test scored.estimate ≈ mean(paired)
            @test !scored.validation_claim_allowed
            if anchor_block === :all_fixed && request.block !== :person
                @test scored.contrast_is_fixed && scored.status === :not_applicable_fixed
                @test scored.mcse === nothing && scored.diagnostics === nothing
            else
                @test !scored.contrast_is_fixed
                expected_mcse = only(posterior_mcse(paired; chains = 4,
                    parameter_names = [request.name], probabilities = request.probabilities,
                    parameter_space = :derived_contrast))
                @test isequal(scored.mcse, expected_mcse)
                @test scored.status in (:precision_unresolved, :diagnostic_warning, :mcse_unavailable)
                @test scored.contrast_estimation_status === (request.block === :person ?
                    :posterior_estimated_contrast : :partially_estimated_contrast)
            end
        end
        @test result.reference.fit_sha256 == fit_hash(fitted)
        @test result.reference.source_files == source_files
        @test result.cell === nothing
        @test all(row -> row.recovery === nothing, result.contrast_scores)
        # The declaration binds the existing independent log truth to labelled
        # coordinate truth. It does not certify that declaration scientifically.
        cell = (; cell_id = reference.method, design_id = design_identity(design).value,
            log_truth_sha256 = reference.truth_sha256, model_status = :declared_correct,
            identification_status = :declared_identified, anchor_atol = 1e-12,
            truth = (; person = [(; level = "P/$p", value = 0.3p) for p in 1:2],
                rater = [(; level = "R$r", value = 0.1r) for r in 1:2],
                item = [(; level = "I$i", value = 0.2i) for i in 1:2]),
            targets = [(; r.name, r.block, r.positive, r.negative, role = :primary) for r in contrasts])
        bound = consume(fitted, train_bytes, heldout_bytes, truth; reference = merge(reference, (; cell)))
        @test bound.cell.cell_id == cell.cell_id && bound.cell.declaration_review_required
        @test bound.truth_score.estimate == result.truth_score.estimate && bound.content_hash != result.content_hash
        @test bound.cell.anchor_compatible == (anchor_block !== :all_fixed)
        for scored in bound.contrast_scores
            @test scored.target.true_value ≈ (scored.request.block === :person ? 0.3 :
                scored.request.block === :rater ? 0.1 : 0.2)
            @test scored.target_error ≈ scored.estimate - scored.target.true_value
            if anchor_block !== :all_fixed
                @test scored.recovery_status === :candidate_available
                @test scored.recovery.posterior_mean ≈ scored.estimate
                @test scored.recovery.bias ≈ scored.target_error
                @test !scored.recovery.diagnostic_selection_applied && !scored.recovery.validation_claim_allowed
            else
                @test scored.recovery === nothing
                @test scored.recovery_status === (scored.request.block === :person ? :distortion_only : :not_applicable_fixed)
            end
        end
        @test_throws ArgumentError consume(fitted, train_bytes, heldout_bytes, truth;
            reference = merge(reference, (; cell = merge(cell, (; log_truth_sha256 = "0"^64)))))
        @test_throws ArgumentError consume(fitted, train_bytes, heldout_bytes, truth;
            reference = merge(reference, (; cell = merge(cell, (; targets = cell.targets[2:end])))))
        logtruth = BayesianMGMFRM._mfrm_anchor_log_probability_matrix(truth, heldout.rows, levels)
        probabilities = predictive_probabilities(design, draws)[:, 8:-1:1, :]
        @test result.truth_score.estimate ≈ mgmfrm_predictive_recovery_score(
            log.(probabilities), logtruth; log_probabilities = true).summary.mean_log_score_regret
        @test result.heldout_score.estimate ≈ -mean(log(mean(
            probabilities[:, n, findfirst(==(heldout.rows[n].score), levels)])) for n in 1:8)
        @test only(BayesianMGMFRM._mfrm_anchor_primary_attempts([reference], [result])) === result

        # Freshly rehashed but incompatible data must still fail semantic checks.
        wrong_train = merge(training, (; rows = [merge(rows[1], (; score = -2)); rows[2:end]]))
        @test wrong_train.rows != training.rows
        @test_throws ArgumentError consume(fitted, raw(wrong_train), heldout_bytes, truth;
            reference = merge(reference, (; training = response_ref(wrong_train))))
        wrong_heldout = merge(heldout, (; rows = [merge(heldout.rows[1], (; person = "new")); heldout.rows[2:end]]))
        @test_throws ArgumentError consume(fitted, train_bytes, raw(wrong_heldout), truth;
            reference = merge(reference, (; heldout = response_ref(wrong_heldout))))
        @test_throws ArgumentError consume(fitted, heldout_bytes, train_bytes, truth;
            reference = merge(reference, (; training = response_ref(heldout), heldout = response_ref(training))))
        @test_throws ArgumentError consume(fitted, train_bytes, heldout_bytes, reverse(truth); reference)
        aligned = consume(fitted, train_bytes, heldout_bytes, reverse(truth);
            reference = merge(reference, (; truth_sha256 = BayesianMGMFRM._cache_hash(reverse(truth)))))
        @test aligned.truth_score.estimate ≈ result.truth_score.estimate

        # Contents with identical shape/display are not the same fit attempt.
        changed_values = copy(draws); changed_values[1, 1] += 0.1
        different = rebuild(; values = changed_values)
        @test sprint(show, different) == sprint(show, fitted)
        @test fit_hash(different) != reference.fit_sha256
        @test_throws ArgumentError consume(different, train_bytes, heldout_bytes, truth; reference)
        @test_throws ArgumentError consume(rebuild(; prior = MFRMPrior(person_sd = 2)),
            train_bytes, heldout_bytes, truth; reference)
        bad_ids = copy(fitted.chain_ids); bad_ids[1] = 2
        bad_iterations = copy(fitted.iterations); bad_iterations[2] = 1
        for broken in (rebuild(; ids = bad_ids), rebuild(; iterations = bad_iterations))
            @test_throws ArgumentError consume(broken, train_bytes, heldout_bytes, truth; reference)
        end
        bad_logps = copy(fitted.log_posterior); bad_logps[1] = NaN
        diagnostic_bad = rebuild(; logps = bad_logps)
        retained = consume(diagnostic_bad, train_bytes, heldout_bytes, truth;
            reference = merge(reference, (; fit_sha256 = fit_hash(diagnostic_bad), attempt = 2)))
        @test !retained.diagnostics.summary.passed && retained.status === :scored
        @test retained.truth_score.estimate == result.truth_score.estimate
        @test retained.attempt == 2 && retained.precision_status === :unresolved
        @test only(BayesianMGMFRM._mfrm_anchor_primary_attempts([reference], [retained, result])) === result
        for broken in (rebuild(; values = zeros(0, size(draws, 2))),
                rebuild(; values = draws[:, 1:(end - 1)]))
            @test_throws ArgumentError consume(broken, train_bytes, heldout_bytes, truth; reference)
        end
        if anchor_block === :none
            extreme_values = copy(draws); extreme_values[:, design.blocks[:person]] .+= 1000
            extreme_fit = rebuild(; values = extreme_values)
            extreme = consume(extreme_fit, train_bytes, heldout_bytes, truth;
                reference = merge(reference, (; fit_sha256 = fit_hash(extreme_fit))))
            @test isfinite(extreme.truth_score.estimate) && isfinite(extreme.heldout_score.estimate)
            @test any(iszero, predictive_probabilities(design, extreme_values))
            relaxed = consume(fitted, train_bytes, heldout_bytes, truth;
                reference = merge(reference, (; diagnostic_policy = merge(screen_policy, (; ess_threshold = 10)))))
            @test relaxed.content_hash != result.content_hash
            @test relaxed.precision_status === :unresolved && !relaxed.validation_claim_allowed
            io = IOBuffer(); serialize(io, result); seekstart(io)
            @test artifact_content_hash(deserialize(io)) == result.content_hash
        end

        if family === :rating_scale && anchor_block === :none
            # Fabricated retained NUTS statistics, not a sampler run or calibration.
            energies = randn(MersenneTwister(321), 160)
            stats = NamedTuple[(; chain = fitted.chain_ids[n], iteration = fitted.iterations[n],
                is_adapt = false, numerical_error = false, tree_depth = 2,
                n_steps = 4, step_size = 0.05, hamiltonian_energy = energies[n]) for n in 1:160]
            hmc(; stats = stats, controls = (; max_depth = 10), backend = :advancedhmc,
                logps = fitted.log_posterior) = rebuild(; stats, controls, backend, logps, sampler = :nuts)
            score_hmc(candidate; policy = screen_policy, requests = contrasts) =
                consume(candidate, train_bytes, heldout_bytes, truth;
                    reference = merge(reference, (; fit_sha256 = fit_hash(candidate),
                        diagnostic_policy = policy, contrasts = requests)))
            good = score_hmc(hmc())
            @test good.hmc_screen.status === :screen_passed && good.hmc_screen.passed
            @test good.hmc_screen.trajectory_complete && good.hmc_screen.depth_available
            @test !good.hmc_screen.validation_claim_allowed && !good.validation_claim_allowed
            energy_ratio(v) = sum(abs2, diff(v)) / sum(abs2, v .- mean(v))
            @test good.hmc_screen.minimum_e_bfmi ≈ minimum(
                energy_ratio(energies[((c - 1) * 40 + 1):(c * 40)]) for c in 1:4)
            for backend in (:turing, :cmdstan)
                @test score_hmc(hmc(; backend)).hmc_screen.passed
            end
            @testset "M2 retained-primary recovery summary (no fits)" begin
                summarize = BayesianMGMFRM._mfrm_anchor_recovery_summary
                full_hash = BayesianMGMFRM._cache_hash
                requests = [merge(r, (; mean_mcse_max = 1.0, endpoint_mcse_max = 1.0)) for r in contrasts]
                function completed(n; error = 0.0, scale = 4.0, diagnostic_bad = false,
                        attempt = 1, selected_requests = requests, method = reference.method,
                        selected_cell = cell)
                    saved_train = merge(training, (; dataset_id = "aggregate/train/$n"))
                    saved_heldout = merge(heldout, (; dataset_id = "aggregate/heldout/$n"))
                    synthetic_draws = copy(draws)
                    a, b = design.blocks[:person][1:2]
                    paired = scale .* (draws[:, b] .- draws[:, a])
                    paired .+= 0.3 + error - mean(paired)
                    synthetic_draws[:, b] = synthetic_draws[:, a] .+ paired
                    candidate = rebuild(; values = synthetic_draws, stats,
                        controls = (; max_depth = 10), backend = :advancedhmc, sampler = :nuts,
                        logps = diagnostic_bad ? [NaN; zeros(159)] : zeros(160))
                    expected = merge(reference, (; dataset_id = saved_train.dataset_id,
                        heldout_id = saved_heldout.dataset_id, attempt, method,
                        training = response_ref(saved_train), heldout = response_ref(saved_heldout),
                        fit_sha256 = fit_hash(candidate), contrasts = selected_requests, cell = selected_cell))
                    return consume(candidate, raw(saved_train), raw(saved_heldout), truth; reference = expected)
                end
                reports = [completed(1; error = -0.1), completed(2; error = 0.1), completed(3; error = 10.0),
                    completed(4; diagnostic_bad = true), completed(5; scale = 100.0)]
                @test all(r -> r.hmc_screen.passed && first(r.contrast_scores).status === :screen_passed, reports[1:3])
                @test !reports[4].hmc_screen.passed
                @test first(reports[5].contrast_scores).status === :precision_exceeded
                plan = [(; dataset_id = "aggregate/train/$n", heldout_id = "aggregate/heldout/$n",
                    method = reference.method, reference_sha256 = n <= 5 ? full_hash(reports[n].reference) : nothing) for n in 1:8]
                failure(n, status) = (; plan[n].dataset_id, plan[n].heldout_id, plan[n].method,
                    attempt = 1, status, reason = "synthetic disposition; no fitting occurred")
                attempts = NamedTuple[reports; failure(6, :fit_failed); failure(7, :structurally_rejected); completed(6; attempt = 2)]
                digest_key(r) = (r.dataset_id, r.heldout_id, r.method, r.attempt)
                hashes(rows) = Dict(digest_key(r) => full_hash(r) for r in rows)
                retained_hashes = hashes(attempts)
                group = (; cell = reports[1].cell, request = requests[1], diagnostic_policy = screen_policy)
                aggregate = summarize(plan, attempts; group..., attempt_hashes = retained_hashes)
                @test aggregate.status === :conditional_summary && aggregate.aggregate_finite
                @test (aggregate.n_planned, aggregate.n_reported_primary, aggregate.n_scored_primary,
                    aggregate.n_screen_eligible, aggregate.n_additional_attempts) == (8, 7, 5, 3, 1)
                @test [r.disposition for r in aggregate.dispositions] ==
                    [:screen_eligible, :screen_eligible, :screen_eligible, :diagnostic_unresolved,
                        :precision_exceeded, :fit_failed, :structurally_rejected, :not_recorded]
                @test aggregate.recovery_summary.mean_bias ≈ 10 / 3
                @test aggregate.recovery_summary.rmse ≈ sqrt(100.02 / 3)
                @test aggregate.recovery_summary.coverage_rate ≈ 2 / 3
                @test aggregate.coverage.joint_fixed_denominator_rate == 2 / 8
                @test (aggregate.coverage.unresolved_bounds.lower, aggregate.coverage.unresolved_bounds.upper) == (2 / 8, 7 / 8)
                @test aggregate.coverage.n_unresolved == 5
                @test aggregate.bias_mcse ≈ std([-0.1, 0.1, 10.0]) / sqrt(3)
                @test aggregate.mse_mcse ≈ std([0.01, 0.01, 100.0]) / sqrt(3)
                @test isfinite(aggregate.dispositions[4].point_error) && aggregate.dispositions[4].recovery !== nothing
                @test isfinite(aggregate.dispositions[5].point_error) && aggregate.dispositions[5].recovery !== nothing
                @test !aggregate.lifecycle_counts_available && aggregate.declaration_and_provenance_review_required
                @test !aggregate.validation_claim_allowed && aggregate.content_hash == artifact_content_hash(aggregate)
                @test summarize(plan, reverse(attempts); group..., attempt_hashes = retained_hashes).content_hash == aggregate.content_hash
                no_retry = attempts[1:7]
                original = summarize(plan, no_retry; group..., attempt_hashes = hashes(no_retry))
                @test isequal(original.recovery_summary, aggregate.recovery_summary)
                @test original.n_screen_eligible == aggregate.n_screen_eligible && original.n_additional_attempts == 0
                single = summarize(plan[1:1], reports[1:1]; group..., attempt_hashes = hashes(reports[1:1]))
                @test ismissing(single.bias_mcse) && ismissing(single.mse_mcse)
                empty = summarize(plan, NamedTuple[]; group..., attempt_hashes = Dict())
                @test empty.status === :no_eligible_primary && empty.coverage.n_unresolved == 8
                @test empty.recovery_summary === nothing && ismissing(empty.bias_mcse)
                @test (empty.coverage.unresolved_bounds.lower, empty.coverage.unresolved_bounds.upper) == (0.0, 1.0)
                unbound_plan = [merge(plan[1], (; reference_sha256 = nothing)); plan[2:end]]
                unbound = summarize(unbound_plan, attempts; group..., attempt_hashes = retained_hashes)
                @test unbound.dispositions[1].disposition === :reference_unavailable && unbound.n_screen_eligible == 2

                # Even a fully rehashed report cannot switch the planned cell,
                # target, source reference, endpoint orientation, or policy.
                seal(r) = merge(r, (; content_hash = artifact_content_hash(r)))
                for patch in ((; cell = merge(reports[1].cell, (; cell_id = "other"))),
                        (; contrast_scores = Base.tail(reports[1].contrast_scores)),
                        (; contrast_scores = (reports[1].contrast_scores..., first(reports[1].contrast_scores))),
                        (; reference = merge(reports[1].reference, (; fit_sha256 = "0"^64))),
                        (; reference = merge(reports[1].reference, (; diagnostic_policy = merge(screen_policy, (; ess_threshold = 10))))))
                    altered_report = seal(merge(reports[1], patch))
                    @test_throws ArgumentError summarize(plan[1:1], [altered_report]; group..., attempt_hashes = hashes([altered_report]))
                end
                for patch in ((; target = merge(first(reports[1].contrast_scores).target, (; true_value = 7.0))),
                        (; request = merge(requests[1], (; positive = requests[1].negative, negative = requests[1].positive))),
                        (; request = merge(requests[1], (; probabilities = (0.1, 0.9)))),
                        (; request = merge(requests[1], (; mean_mcse_max = 2.0))))
                    altered_report = seal(merge(reports[1], (; contrast_scores =
                        (merge(first(reports[1].contrast_scores), patch), Base.tail(reports[1].contrast_scores)...))))
                    @test_throws ArgumentError summarize(plan[1:1], [altered_report]; group..., attempt_hashes = hashes([altered_report]))
                end
                first_contrast = first(reports[1].contrast_scores)
                for patch in ((; true_value = 7.0), (; parameter = "other"), (; cell_id = "other"),
                        (; target_role = :secondary), (; interval_probability = 0.8))
                    altered_report = seal(merge(reports[1], (; contrast_scores =
                        (merge(first_contrast, (; recovery = merge(first_contrast.recovery, patch))),
                            Base.tail(reports[1].contrast_scores)...))))
                    @test_throws ArgumentError summarize(plan[1:1], [altered_report]; group..., attempt_hashes = hashes([altered_report]))
                end
                # In-memory inconsistent-producer mutations: status labels alone
                # must not overrule missing/excess MCSE or nonfinite recovery.
                for (patch, expected_status) in (
                        ((; mcse = merge(first_contrast.mcse, (; mean_mcse = missing))), :mcse_unavailable),
                        ((; mcse = merge(first_contrast.mcse, (; mean_mcse = 2.0))), :precision_exceeded),
                        ((; recovery = nothing), :recovery_unavailable),
                        ((; recovery = merge(first_contrast.recovery, (; squared_error = Inf))), :nonfinite_recovery),
                        ((; diagnostics = merge(first_contrast.diagnostics, (; flag = :mcmc_warning))), :contrast_diagnostic_unresolved))
                    altered_report = seal(merge(reports[1], (; contrast_scores =
                        (merge(first_contrast, patch), Base.tail(reports[1].contrast_scores)...))))
                    checked = summarize(plan[1:1], [altered_report]; group..., attempt_hashes = hashes([altered_report]))
                    @test only(checked.dispositions).disposition === expected_status
                    @test checked.n_screen_eligible == 0 && checked.coverage.n_unresolved == 1
                end
                wrong_endpoints = merge(first_contrast.mcse, (; quantiles = reverse(first_contrast.mcse.quantiles)))
                wrong_endpoint_report = seal(merge(reports[1], (; contrast_scores =
                    (merge(first_contrast, (; mcse = wrong_endpoints)), Base.tail(reports[1].contrast_scores)...))))
                @test_throws ArgumentError summarize(plan[1:1], [wrong_endpoint_report]; group..., attempt_hashes = hashes([wrong_endpoint_report]))
                undeclared = completed(1; selected_requests = contrasts)
                undeclared_summary = summarize([merge(plan[1], (; reference_sha256 = full_hash(undeclared.reference)))],
                    [undeclared]; cell = undeclared.cell, request = contrasts[1], diagnostic_policy = screen_policy,
                    attempt_hashes = hashes([undeclared]))
                @test only(undeclared_summary.dispositions).disposition === :precision_unresolved
                @test undeclared_summary.n_screen_eligible == 0
                tampered = merge(reports[1], (; content_hash = "0"^64))
                @test_throws ArgumentError summarize(plan[1:1], [tampered]; group..., attempt_hashes = hashes(reports[1:1]))
                @test_throws ArgumentError summarize(plan[1:1], [tampered]; group..., attempt_hashes = hashes([tampered]))
                for (bad_plan, bad_attempts, bad_hashes) in ((plan[1:0], attempts, retained_hashes),
                        (plan, attempts, Dict()), (plan, [attempts; attempts[1]], retained_hashes),
                        ([plan; plan[1]], attempts, retained_hashes),
                        ([merge(plan[1], (; method = "other")); plan[2:end]], attempts, retained_hashes),
                        (plan, [completed(6; attempt = 2)], hashes([completed(6; attempt = 2)])),
                        (plan, attempts, merge(retained_hashes, Dict(digest_key(attempts[1]) => "0"^64))))
                    @test_throws ArgumentError summarize(bad_plan, bad_attempts; group..., attempt_hashes = bad_hashes)
                end
                for row in (merge(failure(6, :fit_failed), (; reason = "")), failure(6, :unknown))
                    @test_throws ArgumentError summarize(plan, [row]; group..., attempt_hashes = hashes([row]))
                end
                @test_throws ArgumentError summarize([plan[1], merge(plan[2], (; dataset_id = plan[1].dataset_id))],
                    NamedTuple[]; group..., attempt_hashes = Dict())
                for definition in (merge(group, (; request = merge(requests[1], (; positive = "unknown")))),
                        merge(group, (; cell = merge(group.cell, (; cell_id = "wrong")))))
                    @test_throws ArgumentError summarize(plan, attempts; definition..., attempt_hashes = retained_hashes)
                end
                # N/A and distortion-only targets are not failed coverage trials.
                fixed_target = merge(only(t for t in group.cell.targets if t.name == requests[1].name), (; contrast_is_fixed = true))
                fixed_cell = merge(group.cell, (; targets = (fixed_target,)))
                fixed = summarize(plan, NamedTuple[]; group.request, diagnostic_policy = screen_policy,
                    cell = fixed_cell, attempt_hashes = Dict())
                @test fixed.status === :not_applicable_fixed && fixed.coverage === nothing
                for status in (:distortion_only, :unresolved_cell)
                    excluded = summarize(plan, NamedTuple[]; group.request, diagnostic_policy = screen_policy,
                        cell = merge(group.cell, (; recovery_status = status)), attempt_hashes = Dict())
                    @test excluded.status === status && excluded.coverage === nothing
                end
                @test retained_hashes == hashes(attempts) # No input mutation.
                @testset "M2 same-data paired recovery (no fits)" begin
                    paired_summary = BayesianMGMFRM._mfrm_anchor_paired_recovery
                    predictive_summary = BayesianMGMFRM._mfrm_anchor_paired_predictive
                    # Method labels exercise the join/arithmetic, not real
                    # B/R/I/RI performance. All objects remain synthetic.
                    function bundle(method, rows; n = 5, definition = group)
                        primaries = Dict(r.dataset_id => r for r in rows if r.attempt == 1 && r.status === :scored)
                        planned = [(; dataset_id = "aggregate/train/$i", heldout_id = "aggregate/heldout/$i", method,
                            reference_sha256 = haskey(primaries, "aggregate/train/$i") ?
                                full_hash(primaries["aggregate/train/$i"].reference) : nothing) for i in 1:n]
                        return (; plan = planned, attempts = rows, definition..., attempt_hashes = hashes(rows))
                    end
                    b = bundle("B", [completed(1; method = "B", error = -0.1),
                        completed(2; method = "B", error = 0.1), completed(3; method = "B", error = 10.0),
                        completed(4; method = "B", diagnostic_bad = true), completed(5; method = "B", scale = 100.0)])
                    r = bundle("R", NamedTuple[completed(1; method = "R", error = 1.9),
                        completed(2; method = "R", error = 4.1), completed(3; method = "R", diagnostic_bad = true),
                        completed(4; method = "R", error = 100.0), merge(failure(5, :fit_failed), (; method = "R")),
                        completed(5; method = "R", attempt = 2)])
                    pair = ((method = "R", weight = 1), (method = "B", weight = -1))
                    paired = paired_summary([b, r]; comparison = pair)
                    @test paired.status === :conditional_summary && paired.aggregate_finite
                    @test (paired.n_planned, paired.n_common_eligible, paired.n_joint_screen_eligible) == (5, 2, 2)
                    @test paired.bias_difference ≈ 3.0
                    @test paired.bias_difference_mcse ≈ 1.0
                    squared_differences = [1.9^2 - 0.1^2, 4.1^2 - 0.1^2]
                    @test paired.mse_difference ≈ mean(squared_differences)
                    @test paired.mse_difference_mcse ≈ std(squared_differences) / sqrt(2)
                    @test !isapprox(paired.bias_difference,
                        paired.methods[1].recovery_summary.mean_bias - paired.methods[2].recovery_summary.mean_bias)
                    @test [row.bias_difference for row in paired.rows[1:2]] ≈ [2.0, 4.0]
                    @test all(row -> ismissing(row.bias_difference), paired.rows[3:end])
                    @test paired.rows[5].methods[1].disposition === :fit_failed
                    @test paired.methods[1].n_additional_attempts == 1
                    @test all(s -> s.n_unavailable == 2 && s.n_eligible_outside_common == 1, paired.methods)
                    @test Set(paired.methods[1].unavailable_counts) == Set([
                        (; disposition = :diagnostic_unresolved, n = 1), (; disposition = :fit_failed, n = 1)])
                    @test !paired.lifecycle_counts_available && paired.declaration_and_provenance_review_required
                    @test !paired.validation_claim_allowed && paired.content_hash == artifact_content_hash(paired)
                    @test paired_summary([r, b]; comparison = pair).content_hash == paired.content_hash
                    reordered = merge(r, (; plan = reverse(r.plan), attempts = reverse(r.attempts)))
                    @test isequal(paired_summary([b, reordered]; comparison = pair).rows, paired.rows)
                    no_retry = merge(r, (; attempts = r.attempts[1:5], attempt_hashes = hashes(r.attempts[1:5])))
                    @test paired_summary([b, no_retry]; comparison = pair).bias_difference == paired.bias_difference
                    i = bundle("I", [completed(1; method = "I", error = 0.9), completed(2; method = "I", error = 2.1)])
                    ri = bundle("RI", [completed(1; method = "RI", error = 4.9), completed(2; method = "RI", error = 10.1)])
                    quartet = ((method = "RI", weight = 1), (method = "R", weight = -1),
                        (method = "I", weight = -1), (method = "B", weight = 1))
                    interaction = paired_summary([b, r, i, ri]; comparison = quartet)
                    @test interaction.n_common_eligible == 2 && interaction.n_planned == 5
                    @test interaction.bias_difference ≈ 3.0 && interaction.bias_difference_mcse ≈ 1.0
                    @test [row.bias_difference for row in interaction.rows[1:2]] ≈ [2.0, 4.0]
                    for (positive, negative) in ((r, b), (ri, i), (i, b), (ri, r))
                        c = ((method = positive.plan[1].method, weight = 1), (method = negative.plan[1].method, weight = -1))
                        result_pair = paired_summary([positive, negative]; comparison = c)
                        reverse_pair = paired_summary([positive, negative]; comparison = Tuple(merge(x, (; weight = -x.weight)) for x in c))
                        @test result_pair.bias_difference ≈ -reverse_pair.bias_difference
                        @test result_pair.mse_difference ≈ -reverse_pair.mse_difference
                        @test result_pair.bias_difference_mcse ≈ reverse_pair.bias_difference_mcse
                    end
                    subset(g, indices) = merge(g, (; plan = g.plan[indices],
                        attempts = [row for row in g.attempts if row.dataset_id in [p.dataset_id for p in g.plan[indices]]],
                        attempt_hashes = hashes([row for row in g.attempts if row.dataset_id in [p.dataset_id for p in g.plan[indices]]])))
                    singleton = paired_summary([subset(b, 1:1), subset(r, 1:1)]; comparison = pair)
                    @test singleton.n_common_eligible == 1 && ismissing(singleton.bias_difference_mcse) && ismissing(singleton.mse_difference_mcse)
                    absent = merge(r, (; attempts = NamedTuple[], attempt_hashes = Dict()))
                    empty_pair = paired_summary([b, absent]; comparison = pair)
                    @test empty_pair.n_common_eligible == 0 && empty_pair.status === :no_common_eligible_primary
                    @test ismissing(empty_pair.bias_difference) && ismissing(empty_pair.bias_difference_mcse)
                    @test only(empty_pair.methods[1].unavailable_counts) == (; disposition = :not_recorded, n = 5)
                    for definition in (merge(group, (; cell = fixed_cell)),
                            merge(group, (; cell = merge(group.cell, (; recovery_status = :distortion_only)))),
                            merge(group, (; cell = merge(group.cell, (; recovery_status = :unresolved_cell)))))
                        unavailable = bundle("R", NamedTuple[]; definition)
                        @test paired_summary([b, unavailable]; comparison = pair).status === :inapplicable_comparison
                    end
                    changed_cell = merge(cell, (; cell_id = "different method cell"))
                    different = completed(1; method = "R", selected_cell = changed_cell)
                    @test paired_summary([subset(b, 1:1), bundle("R", [different]; n = 1,
                        definition = merge(group, (; cell = different.cell)))]; comparison = pair).n_common_eligible == 1
                    # Rehashing BOTH the attempt and planned reference must not
                    # permit a same-ID/different-data join, even on excluded rows.
                    for index in (1, 3), patch in (
                            (; training = merge(r.attempts[index].reference.training, (; sha256 = "0"^64))),
                            (; heldout = merge(r.attempts[index].reference.heldout, (; sha256 = "0"^64))),
                            (; truth_sha256 = "0"^64), (; source_files = Dict("/other/source" => "0"^64)),
                            (; required_source_paths = (first(keys(source_files)),)),
                            (; evaluation_panel = (; panel_id = "other", weighting = :equal_event,
                                events = [Base.structdiff(row, (; score = nothing)) for row in heldout.rows])),
                            (; cell = merge(cell, (; truth = merge(cell.truth, (; person = reverse(cell.truth.person)))))))
                        changed = copy(r.attempts)
                        changed[index] = seal(merge(changed[index], (; reference = merge(changed[index].reference, patch))))
                        @test_throws ArgumentError paired_summary([b, bundle("R", changed)]; comparison = pair)
                        @test_throws ArgumentError predictive_summary([b, bundle("R", changed)]; comparison = pair, score = :truth_score)
                    end
                    for invalid in (pair[1:1], (pair..., pair[1]), (pair[1], pair[1]),
                            (merge(pair[1], (; weight = true)), pair[2]),
                            (merge(pair[1], (; weight = Inf)), pair[2]),
                            (merge(pair[1], (; weight = 2)), pair[2]),
                            (pair[1], merge(pair[2], (; weight = 1))))
                        @test_throws ArgumentError paired_summary([b, r]; comparison = invalid)
                        @test_throws ArgumentError predictive_summary([b, r]; comparison = invalid, score = :truth_score)
                    end
                    for invalid_groups in ([b], [b, b], [b, r, i], [b, subset(r, 1:4)])
                        @test_throws ArgumentError paired_summary(invalid_groups; comparison = pair)
                        @test_throws ArgumentError predictive_summary(invalid_groups; comparison = pair, score = :truth_score)
                    end
                    wrong_heldout = merge(absent, (; plan = [merge(p, (; heldout_id = "wrong/$(p.heldout_id)")) for p in absent.plan]))
                    @test_throws ArgumentError paired_summary([b, wrong_heldout]; comparison = pair)
                    @test_throws ArgumentError predictive_summary([b, wrong_heldout]; comparison = pair, score = :truth_score)
                    for patch in ((; request = merge(group.request, (; endpoint_mcse_max = 2.0))),
                            (; diagnostic_policy = merge(screen_policy, (; ess_threshold = 10))),
                            (; cell = merge(group.cell, (; targets = (merge(first(group.cell.targets), (; true_value = 9.0)),)))))
                        @test_throws ArgumentError paired_summary([b, merge(absent, patch)]; comparison = pair)
                    end
                    @test hashes(r.attempts) == r.attempt_hashes && hashes(b.attempts) == b.attempt_hashes
                    @testset "M2 descriptive paired predictive reports (no fits)" begin
                        # Only these three inputs are consumed. Parameter target,
                        # recovery applicability, and its policy are not a gate.
                        lean(g) = (; g.plan, g.attempts, g.attempt_hashes)
                        for score in (:truth_score, :heldout_score)
                            result_pair = predictive_summary(lean.([b, r]); comparison = pair, score)
                            losses = [getproperty(r.attempts[n], score).estimate -
                                getproperty(b.attempts[n], score).estimate for n in 1:4]
                            @test result_pair.status === :descriptive_common_subset && result_pair.aggregate_finite
                            @test (result_pair.n_planned, result_pair.n_common_finite, result_pair.n_joint_point_available) == (5, 4, 4)
                            @test [row.loss_difference for row in result_pair.rows[1:4]] ≈ losses
                            @test result_pair.mean_difference ≈ mean(losses)
                            @test result_pair.across_replication_se ≈ std(losses) / 2
                            @test result_pair.rows[3].methods[1].diagnostic_passed === false
                            @test result_pair.rows[3].methods[1].disposition === :point_available
                            @test result_pair.rows[5].methods[1].disposition === :fit_failed
                            @test ismissing(result_pair.rows[5].loss_difference)
                            @test result_pair.methods[1].n_additional_attempts == 1
                            @test [m.n_point_available for m in result_pair.methods] == [4, 5]
                            @test only(result_pair.methods[1].unavailable_counts) == (; disposition = :fit_failed, n = 1)
                            @test result_pair.selection === :bound_finite_primary && !result_pair.diagnostic_selection_applied
                            @test result_pair.precision_status === :unresolved && ismissing(result_pair.combined_within_fit_mcse)
                            @test result_pair.curvature_review_required && result_pair.convergence_review_required
                            @test !result_pair.lifecycle_counts_available && result_pair.declaration_and_provenance_review_required
                            @test !result_pair.validation_claim_allowed && result_pair.content_hash == artifact_content_hash(result_pair)
                            @test predictive_summary([r, b]; comparison = pair, score).content_hash == result_pair.content_hash
                            @test isequal(predictive_summary([b, reordered]; comparison = pair, score).rows, result_pair.rows)
                            @test predictive_summary([b, no_retry]; comparison = pair, score).mean_difference == result_pair.mean_difference
                            reverse_pair = predictive_summary([b, r]; score,
                                comparison = Tuple(merge(c, (; weight = -c.weight)) for c in pair))
                            @test reverse_pair.mean_difference ≈ -result_pair.mean_difference
                            @test reverse_pair.across_replication_se ≈ result_pair.across_replication_se
                            interaction = predictive_summary([ri, i, b, r]; comparison = quartet, score)
                            expected = [getproperty(ri.attempts[n], score).estimate - getproperty(r.attempts[n], score).estimate -
                                getproperty(i.attempts[n], score).estimate + getproperty(b.attempts[n], score).estimate for n in 1:2]
                            @test interaction.n_common_finite == 2 && interaction.n_planned == 5
                            @test interaction.mean_difference ≈ mean(expected)
                            @test interaction.across_replication_se ≈ std(expected) / sqrt(2)
                            singleton = predictive_summary([subset(b, 1:1), subset(r, 1:1)]; comparison = pair, score)
                            @test singleton.n_common_finite == 1 && ismissing(singleton.across_replication_se)
                            empty_pair = predictive_summary([b, absent]; comparison = pair, score)
                            @test empty_pair.status === :no_common_finite_primary && empty_pair.n_common_finite == 0
                            @test ismissing(empty_pair.mean_difference) && ismissing(empty_pair.across_replication_se)
                            @test only(empty_pair.methods[1].unavailable_counts) == (; disposition = :not_recorded, n = 5)
                            unbound = merge(r, (; plan = [merge(r.plan[1], (; reference_sha256 = nothing)); r.plan[2:end]]))
                            unbound_pair = predictive_summary([b, unbound]; comparison = pair, score)
                            @test unbound_pair.n_common_finite == 3
                            @test unbound_pair.rows[1].methods[1].disposition === :reference_unavailable
                            @test isfinite(unbound_pair.rows[1].methods[1].point_loss)
                        end
                        # Synthetic producer mutations exercise validation and
                        # nonfinite arithmetic without another forecast/fitter.
                        function changed_score(g, index, patch)
                            # Preserve variant field types, including missing/Bool.
                            changed = NamedTuple[g.attempts...]
                            changed[index] = seal(merge(changed[index], patch))
                            return merge(g, (; attempts = changed, attempt_hashes = hashes(changed)))
                        end
                        for status in (:first_order_degenerate, :insufficient_draws, :mcse_unavailable)
                            altered = changed_score(r, 1, (; truth_score = merge(r.attempts[1].truth_score, (; status, mcse = missing))))
                            result_pair = predictive_summary([b, altered]; comparison = pair, score = :truth_score)
                            @test result_pair.n_common_finite == 4 && ismissing(result_pair.combined_within_fit_mcse)
                            @test ismissing(result_pair.rows[1].methods[1].reported_within_fit_mcse)
                        end
                        for invalid in ((; estimate = true), (; estimate = missing), (; estimate = "bad"),
                                (; status = "scored"), (; mcse = NaN), (; mcse = Inf), (; mcse = -1.0), (; mcse = false))
                            altered = changed_score(r, 1, (; truth_score = merge(r.attempts[1].truth_score, invalid)))
                            @test_throws ArgumentError predictive_summary([b, altered]; comparison = pair, score = :truth_score)
                        end
                        nonfinite = (; estimate = Inf, status = :nonfinite_log_score, mcse = missing)
                        infinite_r = changed_score(r, 1, (; truth_score = merge(r.attempts[1].truth_score, nonfinite)))
                        infinite_b = changed_score(b, 1, (; truth_score = merge(b.attempts[1].truth_score, nonfinite)))
                        for baseline in (b, infinite_b)
                            result_pair = predictive_summary([baseline, infinite_r]; comparison = pair, score = :truth_score)
                            @test result_pair.n_common_finite == 3 && ismissing(result_pair.rows[1].loss_difference)
                            @test result_pair.rows[1].methods[1].point_loss == Inf
                            @test result_pair.rows[1].methods[1].disposition === :nonfinite_loss
                            # Changing truth-score fields cannot switch heldout losses.
                            @test predictive_summary([baseline, infinite_r]; comparison = pair, score = :heldout_score).n_common_finite == 4
                        end
                        for value in (NaN, -Inf)
                            altered = changed_score(r, 1, (; truth_score = merge(r.attempts[1].truth_score, (; estimate = value))))
                            result_pair = predictive_summary([b, altered]; comparison = pair, score = :truth_score)
                            @test result_pair.n_common_finite == 3 && result_pair.rows[1].methods[1].disposition === :nonfinite_loss
                        end
                        for g in (r, infinite_r)
                            altered = changed_score(g, 1, (; reference = merge(g.attempts[1].reference,
                                (; truth_sha256 = "0"^64))))
                            for digest in (nothing, full_hash(altered.attempts[1].reference))
                                unbound = merge(altered, (; plan = [merge(altered.plan[1], (; reference_sha256 = digest)); altered.plan[2:end]]))
                                @test_throws ArgumentError predictive_summary([b, unbound]; comparison = pair, score = :truth_score)
                            end
                        end
                        huge = [changed_score(subset(g, 1:1), 1, (; truth_score =
                            merge(g.attempts[1].truth_score, (; estimate = g.plan[1].method in ("RI", "B") ? floatmax(Float64) : 0.0))))
                            for g in (ri, r, i, b)]
                        overflow = predictive_summary(huge; comparison = quartet, score = :truth_score)
                        @test overflow.status === :nonfinite_comparison && overflow.n_joint_point_available == 1
                        @test overflow.n_common_finite == 0 && only(overflow.rows).status === :nonfinite_difference
                        @test ismissing(overflow.mean_difference) && ismissing(overflow.across_replication_se)
                        extreme = changed_score(subset(r, 1:2), 1, (; truth_score =
                            merge(r.attempts[1].truth_score, (; estimate = floatmax(Float64)))))
                        overflow_se = predictive_summary([subset(b, 1:2), extreme]; comparison = pair, score = :truth_score)
                        @test overflow_se.status === :nonfinite_comparison && !overflow_se.aggregate_finite
                        @test overflow_se.n_common_finite == 2 && !isfinite(overflow_se.across_replication_se)
                        for patch in ((; score_scope = :other),
                                (; evaluation_scope = merge(r.attempts[1].evaluation_scope, (; n_evaluation_events = 1))))
                            @test_throws ArgumentError predictive_summary([b, changed_score(r, 1, patch)]; comparison = pair, score = :truth_score)
                        end
                        removed = copy(r.attempts)
                        removed[1] = seal(Base.structdiff(removed[1], (; truth_score = nothing)))
                        @test_throws ArgumentError predictive_summary([b, bundle("R", removed)]; comparison = pair, score = :truth_score)
                        tampered = changed_score(r, 1, (; truth_score = merge(r.attempts[1].truth_score, (; estimate = 7.0))))
                        @test_throws ArgumentError predictive_summary([b, merge(tampered, (; attempt_hashes = r.attempt_hashes))]; comparison = pair, score = :truth_score)
                        @test_throws ArgumentError predictive_summary([b, merge(r, (; attempt_hashes = Dict()))]; comparison = pair, score = :truth_score)
                        @test_throws ArgumentError predictive_summary([b, r]; comparison = pair, score = :other)
                        for declaration in (merge(cell, (; model_status = :misspecified)),
                                merge(cell, (; identification_status = :unresolved)))
                            report = completed(1; method = "R", selected_cell = declaration)
                            @test report.cell.recovery_status !== :candidate_available
                            @test predictive_summary([subset(b, 1:1), bundle("R", [report]; n = 1)];
                                comparison = pair, score = :truth_score).n_common_finite == 1
                        end
                        unlabelled = [bundle(method, [completed(1; method, selected_cell = nothing)]; n = 1) for method in ("B", "R")]
                        @test predictive_summary(lean.(unlabelled); comparison = pair, score = :truth_score).n_common_finite == 1
                        @test hashes(r.attempts) == r.attempt_hashes && hashes(b.attempts) == b.attempt_hashes
                    end
                end
            end
            altered(index, patch) = NamedTuple[n == index ? merge(row, patch) : row
                for (n, row) in pairs(stats)]
            sticky = NamedTuple[row.chain == 4 ? merge(row, (; hamiltonian_energy = Float64(row.iteration))) : row
                for row in stats]
            cases = [
                (:low_e_bfmi, hmc(; stats = sticky)),
                (:incomplete_trajectory, hmc(; stats = stats[2:end])),
                (:incomplete_trajectory, hmc(; stats = stats[1:120])),
                (:incomplete_trajectory, hmc(; stats = NamedTuple[])),
                (:incomplete_trajectory, hmc(; stats = stats[[2, 1, 3:160...]])),
                (:incomplete_trajectory, hmc(; stats = [stats[2]; stats[2:end]])),
                (:incomplete_trajectory, hmc(; stats = altered(1, (; chain = 5)))),
                (:incomplete_trajectory, hmc(; stats = altered(1, (; is_adapt = true)))),
                (:diagnostics_unavailable, hmc(; controls = (;))),
                (:diagnostics_unavailable, hmc(; stats = altered(1, (; tree_depth = missing)))),
                (:diagnostic_warning, hmc(; stats = altered(1, (; numerical_error = true)))),
                (:diagnostic_warning, hmc(; stats = altered(1, (; tree_depth = 10)))),
                (:diagnostic_warning, hmc(; logps = [NaN; zeros(159)])),
            ]
            for energy in (NaN, Inf, missing)
                push!(cases, (:diagnostics_unavailable, hmc(; stats = altered(160, (; hamiltonian_energy = energy)))))
            end
            push!(cases, (:diagnostics_unavailable, hmc(; stats = NamedTuple[
                row.chain == 4 ? merge(row, (; hamiltonian_energy = 1.0)) : row for row in stats])))
            for (expected_status, candidate) in cases
                checked = score_hmc(candidate)
                @test checked.hmc_screen.status === expected_status
                @test !checked.hmc_screen.passed && checked.status === :scored
                @test checked.truth_score.estimate == good.truth_score.estimate
                @test checked.heldout_score.estimate == good.heldout_score.estimate
                @test checked.content_hash != good.content_hash
                @test checked.precision_status === :unresolved && !checked.validation_claim_allowed
            end
            incomplete = score_hmc(hmc(; stats = stats[2:end]))
            @test incomplete.diagnostics.summary.e_bfmi_complete # Energy values alone are insufficient.
            @test ismissing(incomplete.hmc_screen.minimum_e_bfmi)
            @test score_hmc(hmc(; stats = sticky)).hmc_screen.minimum_e_bfmi ≈ energy_ratio(collect(1:40))
            strict = score_hmc(hmc(); policy = merge(screen_policy, (; min_e_bfmi = 100.0)))
            @test strict.hmc_screen.status === :low_e_bfmi && strict.content_hash != good.content_hash
            for candidate in (hmc(; controls = (; max_depth = "10")),
                    hmc(; controls = (; max_depth = true)),
                    hmc(; stats = altered(1, (; numerical_error = missing))),
                    hmc(; stats = altered(1, (; chain = true))),
                    hmc(; stats = altered(1, (; iteration = 0))),
                    hmc(; stats = altered(1, (; tree_depth = -1))),
                    hmc(; stats = altered(1, (; hamiltonian_energy = "1"))),
                    hmc(; stats = [Base.structdiff(stats[1], (; step_size = nothing)); stats[2:end]]))
                @test_throws ArgumentError score_hmc(candidate)
            end

            contrast_score = BayesianMGMFRM._mfrm_anchor_contrast_scores
            for (request, scored) in zip(contrasts, good.contrast_scores)
                @test scored.status === :precision_unresolved
                limits = merge(request, (; mean_mcse_max = scored.mcse.mean_mcse,
                    endpoint_mcse_max = maximum(q.mcse for q in scored.mcse.quantiles)))
                @test only(contrast_score(fitted, [limits], screen_policy)).status === :screen_passed
                for field in (:mean_mcse_max, :endpoint_mcse_max)
                    tighter = merge(limits, NamedTuple{(field,)}((getproperty(limits, field) / 2,)))
                    @test only(contrast_score(fitted, [tighter], screen_policy)).status === :precision_exceeded
                end
                reversed = only(contrast_score(fitted,
                    [merge(request, (; positive = request.negative, negative = request.positive))], screen_policy))
                @test reversed.estimate ≈ -scored.estimate
                @test reversed.mcse.mean_mcse ≈ scored.mcse.mean_mcse
                @test [q.estimate for q in reversed.mcse.quantiles] ≈
                    -reverse([q.estimate for q in scored.mcse.quantiles])
            end
            request = first(contrasts)
            for patch in ((; block = :step), (; positive = "unknown"), (; negative = request.positive),
                    (; name = ""), (; probabilities = nothing), (; probabilities = (0.95, 0.05)),
                    (; probabilities = (0.05, 0.05)), (; probabilities = (0.0, 0.95)),
                    (; probabilities = (0.05, true)), (; probabilities = (0.05, "0.95")),
                    (; probabilities = (0.05, NaN)), (; mean_mcse_max = 0),
                    (; mean_mcse_max = true), (; endpoint_mcse_max = Inf))
                @test_throws ArgumentError contrast_score(fitted, [merge(request, patch)], screen_policy)
            end
            @test_throws ArgumentError contrast_score(fitted, [request, request], screen_policy)
            @test_throws ArgumentError contrast_score(fitted, [Base.structdiff(request, (; mean_mcse_max = nothing))], screen_policy)
            @test_throws ArgumentError score_hmc(hmc(); requests = nothing)
            omitted = score_hmc(hmc(); requests = NamedTuple[])
            @test isempty(omitted.contrast_scores) && omitted.content_hash != good.content_hash
            @test !omitted.validation_claim_allowed && omitted.precision_status === :unresolved
            constant = copy(draws)
            constant[:, design.blocks[:person][2]] = constant[:, design.blocks[:person][1]]
            degenerate = only(contrast_score(rebuild(; values = constant), [request], screen_policy))
            @test !degenerate.contrast_is_fixed && degenerate.status !== :screen_passed
            @test degenerate.mcse.mcse_status === :degenerate_draws && ismissing(degenerate.mcse.mean_mcse)
            shifted = copy(draws); shifted[121:end, design.blocks[:person][2]] .+= 10
            @test only(contrast_score(rebuild(; values = shifted), [request], screen_policy)).status === :diagnostic_warning
            asymmetric = only(contrast_score(fitted,
                [merge(request, (; probabilities = (0.1, 0.8)))], screen_policy))
            @test asymmetric.contrast_interval_type === :quantile_interval
            @test [q.probability for q in asymmetric.mcse.quantiles] == [0.1, 0.8]
        end

        if family === :rating_scale && anchor_block === :none
            @testset "Explicit evaluation-panel boundaries" begin
                key = BayesianMGMFRM._mfrm_anchor_event_key
                declared_events = [Base.structdiff(row, (; score = nothing)) for row in heldout.rows[1:4]]
                panel = (; panel_id = "synthetic/subset", events = declared_events, weighting = :equal_event)
                partial = merge(heldout, (; dataset_id = "synthetic/heldout/subset", rows = heldout.rows[1:4]))
                partial_truth = [row for row in truth if key(row) in Set(key.(declared_events))]
                partial_reference = merge(reference, (; heldout_id = partial.dataset_id,
                    heldout = response_ref(partial), truth_sha256 = BayesianMGMFRM._cache_hash(partial_truth)))
                check_panel(p) = consume(fitted, train_bytes, raw(partial), partial_truth;
                    reference = merge(partial_reference, (; evaluation_panel = p)))
                @test_throws ArgumentError consume(fitted, train_bytes, raw(partial), partial_truth; reference = partial_reference)
                @test_throws ArgumentError check_panel(nothing)
                subset = check_panel(panel)
                @test subset.evaluation_scope == (; declared_panel = true, panel_id = panel.panel_id,
                    weighting = :equal_event, n_training_events = 8, n_evaluation_events = 4)
                @test subset.reference.evaluation_panel == panel
                @test !subset.validation_claim_allowed && subset.precision_status === :unresolved
                permuted = check_panel(merge(panel, (; events = reverse(panel.events))))
                @test isequal(subset.heldout_score, permuted.heldout_score)
                @test isequal(subset.truth_score, permuted.truth_score)
                @test subset.content_hash != permuted.content_hash # The retained declaration changed.
                for bad in ((;), "subset", merge(panel, (; panel_id = "")), merge(panel, (; panel_id = 7)),
                        merge(panel, (; weighting = :equal_rater)), merge(panel, (; events = NamedTuple[])),
                        merge(panel, (; events = Tuple(panel.events))), merge(panel, (; extra = true)),
                        merge(panel, (; events = [panel.events; panel.events[1]])),
                        merge(panel, (; events = panel.events[2:end])),
                        merge(panel, (; events = [merge(panel.events[1], (; score = 0)); panel.events[2:end]])),
                        merge(panel, (; events = [merge(panel.events[1], (; person = "")); panel.events[2:end]])),
                        merge(panel, (; events = [merge(panel.events[1], (; item = "unknown")); panel.events[2:end]])))
                    @test_throws ArgumentError check_panel(bad)
                end
                # A self-consistent heldout/declaration still cannot introduce a
                # new training event or category scale. Rehash all changed bytes.
                for changed in (merge(partial, (; rows = [merge(partial.rows[1], (; person = "unknown")); partial.rows[2:end]])),
                        merge(partial, (; category_levels = [-2, -1, 0, 1])))
                    changed_panel = merge(panel, (; events = [Base.structdiff(row, (; score = nothing)) for row in changed.rows]))
                    @test_throws ArgumentError consume(fitted, train_bytes, raw(changed), partial_truth;
                        reference = merge(partial_reference, (; heldout = response_ref(changed), evaluation_panel = changed_panel)))
                end
                @test_throws ArgumentError consume(fitted, train_bytes, raw(partial), truth;
                    reference = merge(partial_reference, (; truth_sha256 = BayesianMGMFRM._cache_hash(truth), evaluation_panel = panel)))
                all_panel = merge(panel, (; events = [Base.structdiff(row, (; score = nothing)) for row in heldout.rows]))
                explicit_all = consume(fitted, train_bytes, heldout_bytes, truth;
                    reference = merge(reference, (; evaluation_panel = all_panel)))
                @test isequal(explicit_all.heldout_score, result.heldout_score)
                @test isequal(explicit_all.truth_score, result.truth_score)
                @test explicit_all.evaluation_scope.declared_panel
            end
        end
        for bad in (merge(reference, (; fit_sha256 = "0"^64)),
                merge(reference, (; truth_sha256 = "0"^64)),
                merge(reference, (; source_files = Dict(first(keys(source_files)) => "0"^64))),
                merge(reference, (; source_files = Dict{String,String}())),
                merge(reference, (; source_files = Dict("src/bayesian_fit.jl" => "0"^64))),
                merge(reference, (; source_files = Dict(joinpath(@__DIR__, "not-a-source-file.jl") => "0"^64))),
                merge(reference, (; dataset_id = "other")), merge(reference, (; method = "")),
                merge(reference, (; attempt = true)), merge(reference, (; attempt = 0)),
                merge(reference, (; diagnostic_policy = (; rhat_threshold = 1.2))),
                merge(reference, (; diagnostic_policy = merge(screen_policy, (; split_chains = 1)))),
                merge(reference, (; diagnostic_policy = merge(screen_policy, (; ess_threshold = NaN)))),
                merge(reference, (; diagnostic_policy = merge(screen_policy, (; ess_threshold = true)))),
                merge(reference, (; diagnostic_policy = merge(screen_policy, (; min_e_bfmi = 0)))),
                merge(reference, (; diagnostic_policy = merge(screen_policy, (; min_e_bfmi = Inf)))),
                merge(reference, (; diagnostic_policy = merge(screen_policy, (; min_e_bfmi = true)))))
            @test_throws ArgumentError consume(fitted, train_bytes, heldout_bytes, truth; reference = bad)
        end
        @test_throws ArgumentError consume(fitted, train_bytes, heldout_bytes, truth; reference = (;))
        @test fit_hash(fitted) == reference.fit_sha256 # Consumer did not mutate input.
    end
end

@testset "M2 cell-bound contrast truth and applicability (no fits)" begin
    prepare = BayesianMGMFRM._mfrm_anchor_cell_targets
    score = BayesianMGMFRM._mfrm_anchor_contrast_scores
    _, data = mfrm_anchor_test_panel(true)
    truth = (; person = Dict("P$(lpad(string(p), 2, '0'))" => t
            for (p, t) in pairs(collect(range(-1.2, 1.2; length = 40)) .+ 1.35)),
        rater = Dict("R$r" => 0.5(r - 1) for r in 1:4),
        item = Dict("I$i" => 0.4(i - 1) for i in 1:4))
    labelled_truth = map(block -> [(; level, value) for (level, value) in sort(collect(block))], truth)
    targets = mfrm_anchor_test_targets()
    requests = [merge(Base.structdiff(t, (; role = nothing)), (; probabilities = (0.05, 0.95),
        mean_mcse_max = nothing, endpoint_mcse_max = nothing)) for t in targets]
    policy = (; split_chains = true, rhat_threshold = 1.2, ess_threshold = 20, min_e_bfmi = 0.3)
    hard(block, indices) = [(; block, level = string(block === :rater ? "R" : "I", n),
        value = getproperty(truth, block)[string(block === :rater ? "R" : "I", n)], type = :hard) for n in indices]
    raters, items = hard(:rater, (1, 4)), hard(:item, (1, 4))
    regimes = [(; name = "B", anchors = raters[1:0]),
        (; name = "R", anchors = raters), (; name = "I", anchors = items),
        (; name = "RI", anchors = [raters; items]),
        (; name = "S-RI", anchors = [raters[2]; items[2]]),
        (; name = "P-R", anchors = hard(:rater, (2, 3))),
        (; name = "P-I", anchors = hard(:item, (2, 3))),
        (; name = "P-RI", anchors = [hard(:rater, (2, 3)); hard(:item, (2, 3))]),
        (; name = "F-R", anchors = hard(:rater, 1:4)),
        (; name = "F-I", anchors = hard(:item, 1:4)),
        (; name = "F-RI", anchors = [hard(:rater, 1:4); hard(:item, 1:4)])]
    for u in (-0.8, 0.0, 0.8), v in (-0.8, 0.0, 0.8), common in (true, false)
        push!(regimes, (; name = string(common ? "C" : "D", "/", u, "/", v),
            anchors = [merge(a, (; value = a.value + (common || endswith(a.level, "4") ?
                (a.block === :rater ? u : v) : 0.0))) for a in [raters; items]]))
    end
    rng = MersenneTwister(714)
    for family in (:rating_scale, :partial_credit), regime in regimes
        design = getdesign(mfrm_spec(data; thresholds = family, anchors = regime.anchors))
        draws = 0.2 .* randn(rng, 160, length(design.parameter_names))
        fitted = MFRMFit(design, MFRMPrior(), draws, zeros(160), 0.5,
            repeat(1:4; inner = 40), repeat(1:40, 4), fill(0.5, 4), :julia, :random_walk_metropolis, 0, 0.05)
        declaration = (; cell_id = string(family, "/", regime.name), design_id = design_identity(design).value,
            log_truth_sha256 = "e"^64, model_status = :declared_correct,
            identification_status = :declared_identified, anchor_atol = 1e-12, truth = labelled_truth, targets)
        cell = prepare(design, requests, declaration, "e"^64)
        compatible = !startswith(regime.name, "D/") || regime.name == "D/0.0/0.0"
        @test cell.anchor_compatible == compatible
        @test cell.recovery_status === (compatible ? :candidate_available : :distortion_only)
        @test !cell.validation_claim_allowed && cell.declaration_review_required
        @test isequal(prepare(design, reverse(requests), merge(declaration, (; targets = reverse(targets))), "e"^64), cell)
        scored = score(fitted, requests, policy; cell)
        planned_targets = sort([t.name for t in cell.targets if !t.contrast_is_fixed && compatible])
        @test planned_targets == sort([r.request.name for r in scored if r.recovery !== nothing])
        for row in scored
            target = only(t for t in targets if t.name == row.request.name)
            expected_truth = getproperty(truth, target.block)[target.positive] -
                getproperty(truth, target.block)[target.negative]
            @test row.target.true_value ≈ expected_truth
            @test row.target.role === target.role
            @test row.target.contrast_is_fixed == row.contrast_is_fixed # Known before inspecting draws.
            @test row.target_error ≈ row.estimate - expected_truth
            @test row.recovery_status === (row.contrast_is_fixed ? :not_applicable_fixed :
                compatible ? :candidate_available : :distortion_only)
            if row.contrast_is_fixed || !compatible
                @test row.recovery === nothing
            else
                @test row.recovery.bias ≈ row.target_error
                @test row.recovery.interval_probability ≈ 0.9
                @test row.recovery.posterior_lower ≈ row.mcse.quantiles[1].estimate
                @test row.recovery.posterior_upper ≈ row.mcse.quantiles[2].estimate
            end
        end
        if regime.name in ("P-R", "P-I", "P-RI")
            for (primary, secondary) in ((1, 4), (2, 5))
                if scored[primary].contrast_is_fixed
                    @test scored[secondary].contrast_estimation_status === :partially_estimated_contrast
                    @test scored[secondary].recovery !== nothing && scored[primary].recovery === nothing
                end
            end
        end
        regime.name == "B" || continue
        for patch in ((; model_status = :misspecified), (; identification_status = :unidentified),
                (; model_status = :unresolved), (; identification_status = :unresolved))
            prepared = prepare(design, requests, merge(declaration, patch), "e"^64)
            rows = score(fitted, requests, policy; cell = prepared)
            @test all(r -> r.recovery === nothing, rows)
            @test [r.target_error for r in rows] ≈ [r.target_error for r in scored]
        end
        asymmetric_requests = [merge(r, (; probabilities = (0.1, 0.8))) for r in requests]
        asymmetric = score(fitted, asymmetric_requests, policy; cell)
        @test all(r -> r.recovery_status === :unsupported_recovery_interval && r.recovery === nothing, asymmetric)
        @test [r.estimate for r in asymmetric] ≈ [r.estimate for r in scored]
        for patch in ((; cell_id = ""), (; design_id = "0"^64), (; design_id = missing),
                (; log_truth_sha256 = "0"^64), (; model_status = :correct), (; model_status = missing),
                (; identification_status = :unknown), (; anchor_atol = -1), (; anchor_atol = true),
                (; anchor_atol = Inf), (; truth = merge(labelled_truth, (; person = labelled_truth.person[2:end]))),
                (; truth = merge(labelled_truth, (; item = [labelled_truth.item[1:3]; (; level = "I4", value = NaN)]))),
                (; truth = merge(labelled_truth, (; rater = NamedTuple[labelled_truth.rater[1:3]; (; level = "R4", value = true)]))),
                (; targets = targets[2:end]), (; targets = [targets; targets[1]]),
                (; targets = [merge(targets[1], (; role = :replacement)); targets[2:end]]))
            @test_throws ArgumentError prepare(design, requests, merge(declaration, patch), "e"^64)
        end
        @test_throws ArgumentError prepare(design, requests[2:end], declaration, "e"^64)
        @test_throws ArgumentError prepare(design, [requests[1]; requests[1]; requests[3:end]], declaration, "e"^64)
        @test_throws ArgumentError prepare(design, [merge(requests[1], (; positive = "R4")); requests[2:end]], declaration, "e"^64)
        @test prepare(design, requests, nothing, "e"^64) === nothing
        # Labels are data values, never dictionary keys filtered as artifact
        # metadata. Both the target name and coordinate value stay hash-visible.
        named_requests = [merge(requests[1], (; name = "content_hash")); requests[2:end]]
        named_declaration = merge(declaration, (; targets =
            [merge(targets[1], (; name = "content_hash")); targets[2:end]]))
        named_cell = prepare(design, named_requests, named_declaration, "e"^64)
        changed_truth = merge(labelled_truth, (; rater = [labelled_truth.rater[1:2];
            merge(labelled_truth.rater[3], (; value = 1.1)); labelled_truth.rater[4]]))
        changed_cell = prepare(design, named_requests,
            merge(named_declaration, (; truth = changed_truth)), "e"^64)
        @test artifact_content_hash(named_cell) != artifact_content_hash(changed_cell)
        reserved_truth = [(; level = "archive_manifest", value = 0.0)]
        @test artifact_content_hash(reserved_truth) !=
            artifact_content_hash([merge(only(reserved_truth), (; value = 0.1))])

        # Existing spec validation already rejects this reference-rank boundary,
        # including theoretically anchor-rescued cases. Do not bypass it here.
        events = [(p, r, i) for p in 1:40 for r in (isodd(p) ? (1, 2) : (3, 4)) for i in 1:4]
        disconnected = FacetData((; person = ["P$(lpad(string(p), 2, '0'))" for (p, r, i) in events],
            rater = ["R$r" for (p, r, i) in events], item = ["I$i" for (p, r, i) in events],
            score = [mod(p + r + i, 4) for (p, r, i) in events]);
            person = :person, rater = :rater, item = :item, score = :score, category_levels = 0:3)
        for anchors in (raters[1:0], raters, items, [raters; items])
            @test_throws ArgumentError mfrm_spec(disconnected; thresholds = family, anchors)
        end
    end
end

@testset "M2 free/free facet contrast covariance (no fits)" begin
    events = [(p, r, i) for p in 1:2 for r in 1:3 for i in 1:3]
    table = (; person = ["P$p" for (p, r, i) in events],
        rater = ["R$r" for (p, r, i) in events], item = ["I$i" for (p, r, i) in events],
        score = [mod(p + r + i, 3) for (p, r, i) in events])
    data = FacetData(table; person = :person, rater = :rater, item = :item,
        score = :score, category_levels = 0:2)
    anchors = [(; block = :rater, level = "R3", value = 0.4, type = :hard),
        (; block = :item, level = "I3", value = -0.2, type = :hard)]
    rng = MersenneTwister(711)
    policy = (; split_chains = true, rhat_threshold = 1.2, ess_threshold = 20, min_e_bfmi = 0.3)
    for family in (:rating_scale, :partial_credit)
        design = getdesign(mfrm_spec(data; thresholds = family, anchors))
        draws = 0.2 .* randn(rng, 160, length(design.parameter_names))
        fitted = MFRMFit(design, MFRMPrior(), draws, zeros(160), 0.5,
            repeat(1:4; inner = 40), repeat(1:40, 4), fill(0.5, 4),
            :julia, :random_walk_metropolis, 0, 0.05)
        for (block, prefix) in ((:rater, "R"), (:item, "I"))
            a, b = [only(findall(==("$block[$prefix$level]"), design.parameter_names)) for level in 1:2]
            draws[:, b] = draws[:, a] .+ 0.01 .* randn(rng, 160)
            request = (; name = string(block, "/2-1"), block,
                positive = prefix * "2", negative = prefix * "1", probabilities = (0.05, 0.95),
                mean_mcse_max = nothing, endpoint_mcse_max = nothing)
            scored = only(BayesianMGMFRM._mfrm_anchor_contrast_scores(fitted, [request], policy))
            paired = reshape(draws[:, b] .- draws[:, a], :, 1)
            expected = only(posterior_mcse(paired; chains = 4, parameter_names = [request.name],
                probabilities = request.probabilities, parameter_space = :derived_contrast))
            @test scored.contrast_estimation_status === :posterior_estimated_contrast
            @test scored.estimate ≈ mean(paired)
            @test isequal(scored.mcse, expected)
            @test var(paired) < (var(draws[:, a]) + var(draws[:, b])) / 100
        end
    end
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
                logs[draw, :, :] = BayesianMGMFRM._mfrm_anchor_log_probability_matrix(
                    records, [(; person = table.person[n], rater = table.rater[n],
                        item = table.item[n]) for n in 1:data.n], levels)
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

@testset "M1 labelled log truth JSON roundtrip and primary dispositions" begin
    align = BayesianMGMFRM._mfrm_anchor_log_probability_matrix
    probability = MFRMAnchorStandaloneDGP._ld1_pcm_probabilities
    score = mgmfrm_predictive_recovery_score
    events = [(; person = "受験者/2", rater = "-Inf", item = "null"),
        (; person = "受験者/1", rater = "-Inf", item = "null")]
    levels = [-2, 1]
    truth = reduce(vcat, [permutedims(probability(location, [0.0];
        log_probabilities = true)) for location in (-800.0, 801.0)])
    prediction = [0.0 -1e308; -1e308 0.0]
    records(matrix) = [merge(events[n], (; category = levels[k],
        log_probability = matrix[n, k])) for n in 1:2 for k in 1:2]
    truth_records = records(truth)
    @test align(reverse(truth_records), events, levels) == truth
    @test align(truth_records, reverse(events), reverse(levels)) == reverse(truth; dims = (1, 2))
    @test align([merge(row, (; row = 999)) for row in truth_records], events, levels) == truth

    plan = [(; dataset_id = "smoke-d$id", heldout_id = "smoke-h$id", method = "B") for id in 1:8]
    states = (:completed, :completed, :completed, :completed, :completed,
        :fit_failed, :structurally_rejected)
    attempts = [merge(plan[id], (; attempt = 1, status = states[id],
        diagnostic_valid = id <= 4,
        prediction = id in (1, 2, 3, 5) ? records(id == 2 ? [0.0 -Inf; -Inf 0.0] :
            id == 3 ? truth : prediction) : nothing)) for id in 1:7]
    push!(attempts, merge(plan[6], (; attempt = 2, status = :completed,
        diagnostic_valid = true, prediction = records(truth))))
    bundle = (; scope = :synthetic_roundtrip_only, category_levels = levels,
        events, log_truth = truth, truth_records, plan, attempts)
    mktempdir() do directory
        path = joinpath(directory, "labelled-truth.json")
        BayesianMGMFRM._write_json_record(path, bundle)
        loaded = JSON3.read(read(path, String))
        @test length(loaded.log_truth) == 2 && all(length(row) == 2 for row in loaded.log_truth)
        @test loaded.log_truth[1][2] == -800.0 && loaded.log_truth[2][1] == -801.0
        @test loaded.events[1].rater == "-Inf" && loaded.events[1].item == "null"
        @test loaded.attempts[2].prediction[2].log_probability == "-Inf"
        @test loaded.attempts[4].prediction === nothing
        restored_truth = align(loaded.truth_records, loaded.events, loaded.category_levels)
        @test restored_truth == truth
        @test score(align(loaded.attempts[1].prediction, loaded.events, loaded.category_levels),
            restored_truth; log_probabilities = true).summary.mean_log_score_regret ≈
            score(prediction, truth; log_probabilities = true).summary.mean_log_score_regret

        # Validate every attempt before joining the stored plan; successful
        # retries cannot replace failures or silently create a smaller plan.
        joined = BayesianMGMFRM._mfrm_anchor_primary_attempts(loaded.plan, loaded.attempts)
        @test length(joined) == 8 && joined[8] === nothing
        @test length(loaded.attempts) == 8 && count(!isnothing, joined) == 7
        @test count(row -> row !== nothing && row.status in ("completed", "fit_failed"), joined) == 6
        @test count(row -> row !== nothing && row.status == "completed", joined) == 5
        valid = [row for row in joined if row !== nothing && row.status == "completed" &&
            row.diagnostic_valid && row.prediction !== nothing]
        @test [row.dataset_id for row in valid] == ["smoke-d1", "smoke-d2", "smoke-d3"]
        losses = [score(align(row.prediction, loaded.events, loaded.category_levels),
            restored_truth; log_probabilities = true).summary.mean_log_score_regret for row in valid]
        @test isfinite(losses[1]) && losses[1] > 0
        @test losses[2] == Inf && losses[3] == 0.0
        @test count(isfinite, losses) == 2 # Not all eight planned cases or all three scored cases.
        summary_path = joinpath(directory, "summary.json")
        BayesianMGMFRM._write_json_record(summary_path, (; losses, missing_loss = missing))
        saved = JSON3.read(read(summary_path, String))
        @test saved.losses[1] == losses[1] && saved.losses[2] == "Inf" && saved.missing_loss === nothing
    end

    for bad_events in (events[1:1], [events[1], events[1]],
            [merge(events[1], (; person = nothing)), events[2]],
            [merge(events[1], (; rater = "")), events[2]])
        @test_throws ArgumentError align(truth_records, bad_events, levels)
    end
    for bad_levels in ([-2], [-2, -2], [-2.0, 1.0], Any[-2, true])
        @test_throws ArgumentError align(truth_records, events, bad_levels)
    end
    for bad_records in (truth_records[1:3], vcat(truth_records, truth_records[1:1]),
            vcat(truth_records[1:3], truth_records[1:1]),
            [merge(row, (; category = 7)) for row in truth_records],
            [merge(row, (; category = false)) for row in truth_records],
            [merge(row, (; person = "unknown")) for row in truth_records])
        @test_throws ArgumentError align(bad_records, events, levels)
    end
    for invalid in (nothing, missing, "null", "NaN", "Inf", "-800", true,
            NaN, Inf, 0.1, -big(10)^400)
        bad = [merge(row, (; log_probability = invalid)) for row in truth_records]
        @test_throws ArgumentError align(bad, events, levels)
    end
    # These would remain normalized if coerced to ordinary numeric values.
    for (index, invalid) in ((1, false), (2, "-800"), (2, -big(10)^400))
        bad = [n == index ? merge(row, (; log_probability = invalid)) : row
            for (n, row) in pairs(truth_records)]
        @test_throws ArgumentError align(bad, events, levels)
    end
    for invalid in (0.0, -Inf, -1.0)
        @test_throws ArgumentError align(records(fill(invalid, 2, 2)), events, levels)
    end
    @test_throws ArgumentError align(truth_records, events, levels; probability_tolerance = NaN)
    @test_throws ArgumentError align(NamedTuple[], NamedTuple[], levels)
end

@testset "M1 planned identities and non-overwriting primary attempts" begin
    join_primary = BayesianMGMFRM._mfrm_anchor_primary_attempts
    # Tuple identities, not delimiter-concatenated strings; shared datasets
    # across methods are allowed, and the plan's order owns the denominator.
    plan = [(; dataset_id = "d/1", heldout_id = "h", method = "A"),
        (; dataset_id = "d", heldout_id = "1/h", method = "A"),
        (; dataset_id = "d/1", heldout_id = "h", method = "B"),
        (; dataset_id = "未実行", heldout_id = "-Inf", method = "null")]
    attempts = [merge(plan[n], (; attempt = 1, status = :fit_failed)) for n in 1:3]
    retry = merge(plan[1], (; attempt = 2, status = :completed))
    push!(attempts, retry)
    expected = Any[attempts[1:3]..., nothing]
    @test join_primary(plan, attempts) == expected
    @test join_primary(plan, reverse(attempts)) == expected
    @test join_primary(reverse(plan), attempts) == reverse(expected)
    @test attempts[end] == retry && length(attempts) == 4
    @test join_primary(plan, NamedTuple[]) == fill(nothing, 4)
    @test isempty(join_primary(NamedTuple[], NamedTuple[]))
    dict_rows(rows) = [Dict(string(k) => v for (k, v) in pairs(row)) for row in rows]
    @test join_primary(dict_rows(plan), dict_rows(attempts))[1]["status"] == :fit_failed
    loaded = JSON3.read(JSON3.write((; plan, attempts)))
    @test join_primary(loaded.plan, reverse(loaded.attempts))[1].status == "fit_failed"

    @test_throws ArgumentError join_primary(vcat(plan, plan[1:1]), attempts)
    @test_throws ArgumentError join_primary(NamedTuple[], attempts)
    for duplicate in (attempts[1], merge(attempts[1], (; status = :completed)), retry)
        @test_throws ArgumentError join_primary(plan, vcat(attempts, [duplicate]))
    end
    @test_throws ArgumentError join_primary(plan, [retry])
    for value in (0, -1, true, false, 1.0, 1.5, "1", nothing, missing, Inf, NaN)
        @test_throws ArgumentError join_primary(plan, [merge(attempts[1], (; attempt = value))])
    end
    @test_throws ArgumentError join_primary(plan, [plan[1]]) # Missing attempt number.
    for field in (:dataset_id, :heldout_id, :method)
        for value in ("", nothing, missing, 1, true, :A)
            replacement = NamedTuple{(field,)}((value,))
            @test_throws ArgumentError join_primary([merge(plan[1], replacement)], NamedTuple[])
            @test_throws ArgumentError join_primary(plan, [merge(attempts[1], replacement)])
        end
        @test_throws ArgumentError join_primary(plan,
            [merge(attempts[1], NamedTuple{(field,)}(("unplanned",)))])
        omitted = Dict(k => v for (k, v) in pairs(attempts[1]) if k != field)
        @test_throws ArgumentError join_primary(plan, [omitted])
    end
    for invalid_row in (nothing, missing, 1, "record")
        @test_throws ArgumentError join_primary([invalid_row], NamedTuple[])
        @test_throws ArgumentError join_primary(plan, [invalid_row])
    end
end

@testset "M1 byte-bound labelled response data" begin
    decode = BayesianMGMFRM._mfrm_anchor_response_data
    rows = [(; person = "受験者/2", rater = "-Inf", item = "null", score = 0),
        (; person = "受験者/1", rater = "-Inf", item = "null", score = -2)]
    record = (; dataset_id = "smoke-response/1", role = "train",
        category_levels = [-2, -1, 0, 1], rows)
    raw(value) = collect(codeunits(JSON3.write(value)))
    reference(bytes) = (; record.dataset_id, record.role, sha256 = bytes2hex(sha256(bytes)))
    restore(value) = let bytes = raw(value)
        decode(bytes, reference(bytes))
    end
    bytes = raw(record)
    bound = reference(bytes)
    data = decode(bytes, bound)
    @test data.n == 2 && data.score == [0, -2]
    @test data.category_levels == [-2, -1, 0, 1] && data.category == [3, 1]
    @test data.person_levels[data.person] == [row.person for row in rows]
    @test data.rater_levels[data.rater] == ["-Inf", "-Inf"]
    @test data.item_levels[data.item] == ["null", "null"]
    @test restore(merge(record, (; rows = reverse(rows)))).score == [-2, 0]
    @test decode(bytes, JSON3.read(JSON3.write(bound))).score == data.score
    @test decode(bytes, Dict(pairs(bound))).score == data.score
    # Heldout data are valid separately, never accepted under the train reference.
    heldout = merge(record, (; dataset_id = "smoke-heldout/1", role = "heldout"))
    heldout_bytes = raw(heldout)
    heldout_ref = (; heldout.dataset_id, heldout.role, sha256 = bytes2hex(sha256(heldout_bytes)))
    @test decode(heldout_bytes, heldout_ref).score == data.score
    @test_throws ArgumentError decode(heldout_bytes, bound)
    @test_throws ArgumentError decode(bytes, heldout_ref)
    for changed in (merge(record, (; rows = reverse(rows))),
            merge(record, (; rows = [merge(rows[1], (; score = 1)), rows[2]])),
            merge(record, (; category_levels = [-2, -1, 0])))
        @test_throws ArgumentError decode(raw(changed), bound)
    end
    @test_throws ArgumentError decode(vcat(bytes, UInt8[0x20]), bound) # Byte identity, not semantic hash.
    @test_throws ArgumentError decode(UInt8[0xff], bound) # Reject hash before JSON parsing.
    mktempdir() do directory
        path = joinpath(directory, "responses.json")
        BayesianMGMFRM._write_json_record(path, record)
        filename = collect(codeunits(path))
        @test_throws ArgumentError decode(filename, reference(filename)) # Never open a path encoded as bytes.
    end
    for invalid in (nothing, missing, 1, :digest, "", "0"^63, "g"^64, "A"^64, bound.sha256 * "\n")
        @test_throws ArgumentError decode(bytes, merge(bound, (; sha256 = invalid)))
    end
    for field in (:dataset_id, :role), value in (nothing, missing, 1, true, "", :train, "other")
        @test_throws ArgumentError decode(bytes, merge(bound, NamedTuple{(field,)}((value,))))
    end
    @test_throws ArgumentError decode(bytes, (; bound.dataset_id, bound.role))
    for invalid in (nothing, missing, 1, "reference")
        @test_throws ArgumentError decode(bytes, invalid)
    end
    # Rehash malformed payloads so these exercise semantic validation, not just SHA rejection.
    for invalid in (merge(record, (; dataset_id = "wrong")), merge(record, (; role = "heldout")),
            merge(record, (; extra = true)), Dict(:dataset_id => record.dataset_id),
            nothing, [record], merge(record, (; rows = nothing)), merge(record, (; rows = [])),
            merge(record, (; rows = [rows[1], rows[1]])),
            merge(record, (; rows = [merge(rows[1], (; extra = true)), rows[2]])),
            merge(record, (; rows = [nothing, rows[2]])))
        @test_throws ArgumentError restore(invalid)
    end
    for levels in (nothing, 2, [], [0], [-2, -2], [1, 0, -1, -2], [-2, 0, 1],
            [-2.0, -1.0, 0.0, 1.0], Any[-2, -1, false, 1],
            [typemin(Int), typemax(Int)])
        @test_throws ArgumentError restore(merge(record, (; category_levels = levels)))
    end
    for field in (:person, :rater, :item), value in (nothing, "", 1, true)
        bad = [merge(rows[1], NamedTuple{(field,)}((value,))), rows[2]]
        @test_throws ArgumentError restore(merge(record, (; rows = bad)))
    end
    for value in (nothing, true, false, "0", 0.0, 0.5, -3, 2, typemax(UInt64))
        bad = [merge(rows[1], (; score = value)), rows[2]]
        @test_throws ArgumentError restore(merge(record, (; rows = bad)))
    end
    for token in ("1.0000000000000000001", "0e0", "9007199254740993.0")
        changed = collect(codeunits(replace(String(copy(bytes)), "\"score\":0" => "\"score\":" * token)))
        @test changed != bytes
        @test_throws ArgumentError decode(changed, reference(changed))
    end
    # Genuine integer tokens above Float64's exact range must not be rounded.
    large = Int64(9_007_199_254_740_992)
    wide = merge(record, (; category_levels = [large, large + 1],
        rows = [merge(rows[1], (; score = large + 1)), merge(rows[2], (; score = large))]))
    if typemax(Int) >= large + 1
        @test restore(wide).score == [large + 1, large]
        @test restore(wide).category_levels == [large, large + 1]
    else
        @test_throws ArgumentError restore(wide)
    end
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
    # Trusted, self-produced temporary files only. Native Serialization is an
    # environment-bound replay aid, not the portable truth/data archive.
    restored = mktempdir() do directory
        path = joinpath(directory, "response-blocks.jls")
        serialize(path, (; julia_version = VERSION, rng_engine = string(typeof(rng)), blocks))
        saved = deserialize(path)
        @test saved.julia_version == VERSION
        @test saved.rng_engine == "MersenneTwister"
        @test saved.blocks == blocks
        # The existing blocks also cross the labelled JSON -> FacetData boundary.
        # Native RNG checkpoints are not a substitute for the response tables.
        for (n, b) in pairs(saved.blocks)
            _, template = mfrm_anchor_test_panel(b.id[3])
            rows = [(; person = template.person_levels[p], rater = template.rater_levels[r],
                item = template.item_levels[i], score = b.scores[(p, r, i)]) for (p, r, i) in b.events]
            record = (; dataset_id = "smoke-response-$n", role = string(b.id[4]),
                category_levels = collect(0:3), rows)
            response_path = joinpath(directory, "response-$n.json")
            BayesianMGMFRM._write_json_record(response_path, record)
            bytes = read(response_path)
            reference = (; record.dataset_id, record.role, sha256 = bytes2hex(sha256(bytes)))
            data = BayesianMGMFRM._mfrm_anchor_response_data(bytes, reference)
            @test data.person_levels[data.person] == [row.person for row in rows]
            @test data.rater_levels[data.rater] == [row.rater for row in rows]
            @test data.item_levels[data.item] == [row.item for row in rows]
            @test data.score == [b.scores[e] for e in b.events] && data.category_levels == collect(0:3)
        end
        # A fresh stdlib-only process can replay without the live RNG or fits.
        code = """
            using Random, Serialization
            saved = deserialize(ARGS[1])
            @assert saved.julia_version == VERSION
            for b in reverse(saved.blocks)
                replay = copy(b.start)
                @assert [rand(replay) for _ in b.events] == b.uniforms
                @assert replay == b.stop
            end
            print(length(saved.blocks))
            """
        command = addenv(`$(Base.julia_cmd()) --startup-file=no -e $code $path`,
            "JULIA_LOAD_PATH" => "@stdlib")
        @test read(command, String) == "16"
        saved.blocks
    end
    # Replay any saved block without generating its predecessors. Row/subset access
    # uses immutable event identities, not new draws or the consumer's row index.
    for b in reverse(restored)
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

@testset "M1/M2 complete candidate roster and paired controls (no fits)" begin
    # Encode the finite review draft, not an evaluation runner or seed roster.
    # Scores are deterministic input scaffolding; no responses or fits are sampled.
    cell(id, kind, raters, items, u = 0.0, v = 0.0) =
        (; id, anchor_id = id, kind, raters, items, u, v, prior_scale = 1.0, init_jitter = 0.02)
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
    prior_controls = ("B", "R", "I", "RI", "C-R-u+0.8", "C-I-v+0.8")
    prior_id(id, scale) = "$id-P$scale"
    start_id(id) = "$id-J0.5"

    events, data = mfrm_anchor_test_panel(true)
    strata = [findall(e -> (e[2] == 4, e[3] == 4) == pattern, events)
        for pattern in ((true, true), (true, false), (false, true), (false, false))]
    @test length.(strata) == [20, 60, 60, 180]
    base_theta = collect(range(-1.2, 1.2; length = 40)) .+ 1.35
    rho, beta = (0.0, 0.5, 1.0, 1.5), (0.0, 0.4, 0.8, 1.2)
    pcm_steps = ([-0.6, 0.0, 0.6], [-0.4, 0.1, 0.3],
        [-0.8, 0.3, 0.5], [-0.2, -0.1, 0.3])
    probability = MFRMAnchorStandaloneDGP._ld1_pcm_probabilities
    targets = mfrm_anchor_test_targets()
    requests = [merge(Base.structdiff(t, (; role = nothing)), (; probabilities = (0.05, 0.95),
        mean_mcse_max = 1.0, endpoint_mcse_max = 1.0)) for t in targets]
    # Synthetic diagnostic/precision settings only, not scientific adoption.
    policy = (; split_chains = true, rhat_threshold = 1.2, ess_threshold = 20, min_e_bfmi = 0.3)
    raw(record) = collect(codeunits(JSON3.write(record)))
    response_ref(record) = (; record.dataset_id, record.role, sha256 = bytes2hex(sha256(raw(record))))
    full_hash = BayesianMGMFRM._cache_hash
    source_files = Dict(abspath(joinpath(@__DIR__, "..", path)) =>
        bytes2hex(sha256(read(joinpath(@__DIR__, "..", path)))) for path in
        ("Project.toml", "src/facet_workflow.jl", "src/model_contract.jl", "src/bayesian_fit.jl",
            "src/practitioner_diagnostics.jl", "src/mgmfrm_validation_scoring.jl",
            "src/local_dependence_known_truth_dgp.jl", "test/mfrm_anchor_generator_crosscheck.jl"))
    energies = randn(MersenneTwister(321), 160)
    stats = [(; chain = div(n - 1, 40) + 1, iteration = mod1(n, 40), is_adapt = false,
        numerical_error = false, tree_depth = 2, n_steps = 4, step_size = 0.05,
        hamiltonian_energy = energies[n]) for n in 1:160]
    checked_cells, checked_comparisons = String[], Tuple[]
    checked_data, checked_misfit_views = String[], Tuple[]
    checked_predictive = Tuple[]
    predictive_cells = Dict(score => Set{String}() for score in (:truth_score, :heldout_score))
    previous_link_group = nothing
    previous_information_group = nothing
    previous_misfit_group = nothing
    misfit_controls = Dict{Tuple,NamedTuple}()
    secondary_panels = Dict{Tuple,NamedTuple}()
    selected_people = [1:4; 9:12; 19:22; 29:32; 37:40]
    selected_labels = ["P$(lpad(string(p), 2, '0'))" for p in selected_people]
    @test length(selected_people) == 20 && all(count(p -> mod1(p, 4) == r, selected_people) == 5 for r in 1:4)
    topologies = (("D", nothing, 0.0), ("S", nothing, 0.0), ("N-C4", collect(19:22), 0.0),
        ("N-C8", collect(17:24), 0.0), ("N-E4", [1, 2, 39, 40], 0.0), ("N-E8", [1:4; 37:40], 0.0),
        ("S20", nothing, 0.0), ("S20-L", nothing, 0.0), ("S20-H", nothing, 0.0),
        ("S20-G1", nothing, 0.0), ("S20-G2", nothing, 0.0),
        ("S-X-0.35", nothing, -0.35), ("S-X+0.35", nothing, 0.35),
        ("N-C4-X-0.35", collect(19:22), -0.35), ("N-C4-X+0.35", collect(19:22), 0.35))
    for thresholds in (:rating_scale, :partial_credit), (topology, common, coefficient) in topologies
        sparse, nested = topology == "S", common !== nothing
        information = startswith(topology, "S20")
        misfit = !iszero(coefficient)
        people = information ? selected_people : collect(1:40)
        theta = base_theta .+ (topology == "S20-L" ? -4 : topology == "S20-H" ? 4 : 0)
        events, data = nested ? mfrm_anchor_test_panel(true; events = [(p, r, i)
            for p in 1:40 for r in 1:4 for i in 1:4 if p in common || r in (isodd(p) ? (1, 2) : (3, 4))]) :
            information ? mfrm_anchor_test_panel(true; events = [(p, r, i)
                for p in people for r in 1:4 for i in 1:4 if r in (mod1(p, 4), mod1(p + 1, 4))]) :
            mfrm_anchor_test_panel(sparse || misfit)
        prefix = string(thresholds === :rating_scale ? "RSM" : "PCM", "-", topology)
        delta_steps = topology == "S20-G1" ? [8, -8, 0] : topology == "S20-G2" ? [0, 8, -8] : zeros(3)
        steps = map(s -> s .+ delta_steps, thresholds === :rating_scale ? ntuple(_ -> pcm_steps[1], 4) : pcm_steps)
        labelled_truth = (; person = [(; level = "P$(lpad(string(p), 2, '0'))", value = theta[p]) for p in people],
            rater = [(; level = "R$r", value = rho[r]) for r in 1:4],
            item = [(; level = "I$i", value = beta[i]) for i in 1:4])
        results = Dict{String,NamedTuple}()
        reports = Dict{String,NamedTuple}()
        predictive_views = Dict{Tuple,NamedTuple}()
        signatures = []
        selected_cells = sparse ? copy(cells) : [c for c in cells if c.kind === :E]
        if sparse
            append!(selected_cells, [merge(c, (; id = prior_id(c.id, scale), prior_scale = scale))
                for c in cells if c.id in prior_controls for scale in (0.5, 2.0)])
            append!(selected_cells, [merge(c, (; id = start_id(c.id), init_jitter = 0.5)) for c in cells if c.kind === :E])
            @test length(selected_cells) == length(unique(c.id for c in selected_cells)) == 77
        end
        rows = [(; person = "P$(lpad(string(p), 2, '0'))", rater = "R$r", item = "I$i",
            score = mod(p + r + i, 4)) for (p, r, i) in events]
        # Deliberately constructed occupancy fixtures, not DGP draws conditioned
        # on a missing category. Each profile is a distinct synthetic data block.
        unused = topology == "S20-L" ? 3 : topology == "S20-H" ? 0 :
            topology == "S20-G1" ? 1 : topology == "S20-G2" ? 2 : nothing
        observed_levels = [k for k in 0:3 if k != unused]
        if information
            rows = [merge(row, (; score = observed_levels[mod1(n + 1, length(observed_levels))])) for (n, row) in pairs(rows)]
            record = (; dataset_id = "synthetic/$prefix/train", role = "train", category_levels = collect(0:3), rows)
            data = BayesianMGMFRM._mfrm_anchor_response_data(raw(record), response_ref(record))
            @test data.person_levels == selected_labels && data.n == 160
            @test data.person_levels[findfirst(==("P30"), data.person_levels)] == "P30"
            @test findfirst(==("P30"), data.person_levels) != 30
            @test all(count(==(r), data.rater) == count(==(r), data.item) == 40 for r in 1:4)
            @test all(count(==(p), data.person) == 8 for p in 1:20)
            @test all(s -> isapprox(sum(s), 0; atol = 1e-14) && all(isfinite, s), steps)
            validation, audit = validate_design(data), ordinal_response_pattern_audit(data)
            @test validation.passed && !audit.fit_prohibited
            @test data.category_levels == collect(0:3) && audit.category_scale.levels == (0, 1, 2, 3)
            @test collect(audit.overall.unused_categories) == (unused === nothing ? Int[] : [unused])
            @test validation.category_counts == audit.overall.category_counts
            for facet in (:item, :rater), row in getproperty(audit.facets, facet)
                @test sum(Base.values(row.category_counts)) == row.n_observations == 40
                @test Set(keys(row.category_counts)) == Set(0:3)
                # Overall support need not hold in each labelled stratum.
                expected_counts = Dict(k => count(r -> getproperty(r, facet) == row.level && r.score == k, rows) for k in 0:3)
                @test row.category_counts == expected_counts
                @test row.unused_categories == Tuple(k for k in 0:3 if expected_counts[k] == 0)
            end
            if unused !== nothing
                code = unused in (0, 3) ? :unobserved_declared_endpoint : :unused_interior_category
                @test any(issue -> issue.code === code && issue.severity === :warning, validation.issues)
            end
        end
        training = (; dataset_id = "synthetic/$prefix/train", role = "train", category_levels = collect(0:3), rows)
        push!(checked_data, training.dataset_id)
        evaluation_indices = [n for (n, (p, r, i)) in pairs(events) if !nested || r in (isodd(p) ? (1, 2) : (3, 4))]
        evaluation_rows = rows[evaluation_indices]
        evaluation_panel = nested || information ? (; panel_id = nested ? "nested/base-320" : "information/common-160", weighting = :equal_event,
            events = [Base.structdiff(row, (; score = nothing)) for row in evaluation_rows]) : nothing
        heldout = (; dataset_id = "synthetic/$prefix/heldout", role = "heldout", category_levels = collect(0:3),
            rows = reverse([merge(row, (; score = information ? observed_levels[mod1(n + 2, length(observed_levels))] :
                mod(row.score + 1, 4))) for (n, row) in pairs(evaluation_rows)]))
        train_bytes, heldout_bytes = raw(training), raw(heldout)
        rejected = merge(training, (; dataset_id = "synthetic/$prefix/rejected/train",
            rows = [merge(row, (; score = 0)) for row in rows]))
        if information
            rejected_data = BayesianMGMFRM._mfrm_anchor_response_data(raw(rejected), response_ref(rejected))
            rejection = validate_design(rejected_data)
            @test !rejection.passed && any(issue -> issue.code === :single_observed_category && issue.severity === :error, rejection.issues)
            @test ordinal_response_pattern_audit(rejected_data).fit_prohibited
            @test rejected_data.n == 160 && rejected_data.category_levels == collect(0:3)
            @test ordinal_response_pattern_audit(BayesianMGMFRM._mfrm_anchor_response_data(
                heldout_bytes, response_ref(heldout))).overall.unused_categories == (unused === nothing ? () : (unused,))
        end
        base_logs = reduce(vcat, [permutedims(probability(theta[p] - rho[r] - beta[i], steps[i]; log_probabilities = true))
            for (p, r, i) in events])
        truth_logs = copy(base_logs)
        affected = [r == 4 && (!nested || p in common) for (p, r, i) in events]
        misfit_oracle = nothing
        if misfit
            # Log-domain tilt, independent of the fitting kernel. The response
            # scaffolds remain deterministic, not random samples from this q.
            for n in findall(affected)
                weights = base_logs[n, :] .+ coefficient .* ((0:3) .- 1.5).^2
                shift = maximum(weights)
                truth_logs[n, :] = weights .- (shift + log(sum(exp, weights .- shift)))
            end
            misfit_oracle = setprecision(BigFloat, 256) do
                reduce(vcat, [permutedims(let eta = BigFloat(theta[p]) - BigFloat(rho[r]) - BigFloat(beta[i])
                    weights = [exp(k * eta - sum(BigFloat.(steps[i][1:k]); init = big"0") +
                        (affected[n] ? BigFloat(coefficient) : big"0") * (k - big"1.5")^2) for k in 0:3]
                    Float64.(log.(weights ./ sum(weights)))
                end) for (n, (p, r, i)) in pairs(events)])
            end
            @test truth_logs ≈ misfit_oracle atol = 1e-12 rtol = 0
            @test all(isfinite, truth_logs) && all(>(0), exp.(truth_logs))
            @test vec(sum(exp.(truth_logs); dims = 2)) ≈ ones(data.n) atol = 1e-12
            @test truth_logs[.!affected, :] == base_logs[.!affected, :]
            @test diff(truth_logs[affected, :]; dims = 2) - diff(base_logs[affected, :]; dims = 2) ≈
                repeat(permutedims(coefficient .* [-2.0, 0.0, 2.0]), count(affected), 1) atol = 1e-12
            @test (count(affected), count(!, affected)) == (nested ? (16, 336) : (80, 240))
            @test (count(affected[evaluation_indices]), count(!, affected[evaluation_indices])) ==
                (nested ? (8, 312) : (80, 240))
            for n in findall(affected)
                p, q = exp.(base_logs[n, :]), exp.(truth_logs[n, :])
                @test ((q[1] + q[4]) / (q[2] + q[3])) / ((p[1] + p[4]) / (p[2] + p[3])) ≈ exp(2coefficient)
            end
        end
        log_truth = [merge(rows[n], (; category = k - 1, log_probability = truth_logs[n, k]))
            for n in evaluation_indices for k in 1:4]
        all_names = ["$block[$(row.level)]" for block in (:person, :rater, :item)
            for row in getproperty(labelled_truth, block)]
        append!(all_names, [thresholds === :rating_scale ? "step[$s]" : "step[item=I$i,$s]"
            for i in (thresholds === :rating_scale ? (1,) : (1, 2, 3, 4)) for s in 1:2])
        rng = MersenneTwister(715)
        noise = Dict(name => 0.2 .* randn(rng, 160) for name in all_names)
        foreach(v -> v .-= mean(v), Base.values(noise))
        for (index, c) in pairs(selected_cells)
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
                    Tuple((i, ivalues[i]) for i in ifixed), c.prior_scale, c.init_jitter))
                design = getdesign(mfrm_spec(data; thresholds, anchors))
                information && @test_throws ArgumentError mfrm_spec(rejected_data; thresholds, anchors)
                values = Dict("person[P$(lpad(string(p), 2, '0'))]" => theta[p] + ru + iv
                    for p in people)
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
                expected_loglikelihood = [log(expected[n, row.score + 1]) for (n, row) in pairs(rows)]
                @test pointwise_loglikelihood(design, params) ≈ expected_loglikelihood atol = 1e-12 rtol = 0
                prior = MFRMPrior(; person_sd = 1.5 * c.prior_scale, rater_sd = c.prior_scale,
                    item_sd = c.prior_scale, step_sd = c.prior_scale)
                settings_checked = sparse && c.anchor_id in prior_controls
                starts = nothing
                if settings_checked
                    # Native helpers, but no fit or new evaluation RNG allocation.
                    initial = BayesianMGMFRM._fit_initial_params(design, nothing)
                    @test initial == zeros(length(params)) && initial != params
                    start_rng, oracle_rng = MersenneTwister(17), MersenneTwister(17)
                    starts = [BayesianMGMFRM._advancedhmc_initial(initial, start_rng, c.init_jitter) for _ in 1:4]
                    @test starts == [[c.init_jitter * randn(oracle_rng) for _ in eachindex(initial)] for _ in 1:4]
                    @test start_rng == oracle_rng && initial == zeros(length(params))
                    @test all(x -> isfinite(logposterior(design, x, prior)), starts)
                    sds = fill(c.prior_scale, length(params))
                    sds[design.blocks[:person]] .*= 1.5
                    for x in (params, collect(range(-0.3, 0.4; length = length(params))))
                        normal_logdensity = -length(x) * log(2pi) / 2 - sum(log, sds) - sum(abs2, x ./ sds) / 2
                        @test logprior(design, x, prior) ≈ normal_logdensity atol = 1e-12
                        @test logposterior(design, x, prior) ≈ loglikelihood(design, x) + normal_logdensity atol = 1e-12
                    end
                end
                results[c.id] = (; names = Tuple(design.parameter_names), probabilities = actual,
                    prior = logprior(design, params, prior), likelihood = loglikelihood(design, params),
                    posterior = logposterior(design, params, prior), starts)
                @testset "Bound recovery and applicability" begin
                    # Full-size real anchor designs, but fabricated draws and
                    # NUTS statistics. No fit call or evaluation replication.
                    offset = 0.01index
                    means = (; person = Dict("P$(lpad(string(p), 2, '0'))" => theta[p] + ru + iv + offset * 0.1p for p in people),
                        rater = Dict("R$r" => (r in rfixed ? rvalues[r] : rho[r] + ru + offset * 0.2r) for r in 1:4),
                        item = Dict("I$i" => (i in ifixed ? ivalues[i] : beta[i] + iv - offset * 0.1i) for i in 1:4))
                    synthetic_means = copy(values)
                    for block in (:person, :rater, :item), (level, value) in getproperty(means, block)
                        name = "$block[$level]"
                        haskey(synthetic_means, name) && (synthetic_means[name] = value)
                    end
                    draws = reduce(hcat, [noise[name] .+ synthetic_means[name] for name in design.parameter_names])
                    controls = (; max_depth = 10, init_jitter = c.init_jitter)
                    fitted = MFRMFit(design, prior, draws, zeros(160), 0.5,
                        repeat(1:4; inner = 40), repeat(1:40, 4), fill(0.5, 4),
                        :advancedhmc, :nuts, 0, 0.05, stats, controls)
                    declaration = (; cell_id = "$prefix-$(c.anchor_id)", design_id = design_identity(design).value,
                        log_truth_sha256 = full_hash(log_truth), model_status = misfit ? :misspecified : :declared_correct,
                        identification_status = :declared_identified, anchor_atol = 1e-12, truth = labelled_truth, targets)
                    reference = (; training.dataset_id, heldout_id = heldout.dataset_id, method = "$prefix-$(c.id)",
                        attempt = 1, training = response_ref(training), heldout = response_ref(heldout),
                        fit_sha256 = BayesianMGMFRM._mfrm_anchor_fit_hash(fitted), truth_sha256 = full_hash(log_truth),
                        source_files, diagnostic_policy = policy, contrasts = requests, cell = declaration)
                    (nested || information) && (reference = merge(reference, (; evaluation_panel)))
                    if settings_checked
                        metadata = fit_metadata(fitted)
                        @test metadata.prior == (; person_sd = 1.5 * c.prior_scale, rater_sd = c.prior_scale,
                            item_sd = c.prior_scale, step_sd = c.prior_scale)
                        @test metadata.sampler_controls.init_jitter == c.init_jitter
                        # Keep the retained fit reference fixed: changing only
                        # a prior or start setting must not score as that fit.
                        for (wrong_prior, wrong_controls) in ((MFRMPrior(; person_sd = 3.0 * c.prior_scale), controls),
                                (prior, merge(controls, (; init_jitter = 2 * c.init_jitter))))
                            changed = MFRMFit(design, wrong_prior, draws, zeros(160), 0.5,
                                repeat(1:4; inner = 40), repeat(1:40, 4), fill(0.5, 4),
                                :advancedhmc, :nuts, 0, 0.05, stats, wrong_controls)
                            @test BayesianMGMFRM._mfrm_anchor_fit_hash(changed) != reference.fit_sha256
                            @test_throws ArgumentError BayesianMGMFRM._mfrm_anchor_score_attempt(
                                changed, train_bytes, heldout_bytes, log_truth; reference)
                        end
                    end
                    report = BayesianMGMFRM._mfrm_anchor_score_attempt(fitted, train_bytes, heldout_bytes, log_truth; reference)
                    @test report.hmc_screen.passed && report.cell.anchor_compatible == (c.kind !== :D)
                    @test report.reference.cell.design_id == design_identity(design).value
                    @test report.reference.training == response_ref(training) && report.reference.heldout == response_ref(heldout)
                    @test !report.validation_claim_allowed && report.precision_status === :unresolved
                    if misfit
                        @test report.cell.anchor_compatible && report.cell.recovery_status === :distortion_only
                        @test report.reference.cell.model_status === :misspecified
                        unperturbed = [merge(rows[n], (; category = k - 1, log_probability = base_logs[n, k]))
                            for n in evaluation_indices for k in 1:4]
                        @test full_hash(unperturbed) != reference.truth_sha256
                        @test_throws ArgumentError BayesianMGMFRM._mfrm_anchor_score_attempt(
                            fitted, train_bytes, heldout_bytes, unperturbed; reference)
                    end
                    @test Tuple(row.category for row in report.category_totals) == (0, 1, 2, 3)
                    @test sum(row.observed_count for row in report.category_totals) == length(evaluation_rows)
                    @test sum(row.truth_expected_count for row in report.category_totals) ≈ length(evaluation_rows)
                    @test sum(row.predicted_expected_count for row in report.category_totals) ≈ length(evaluation_rows)
                    if nested
                        @test data.n == 320 + 8length(common)
                        @test length(evaluation_indices) == report.evaluation_scope.n_evaluation_events == 320
                        @test report.evaluation_scope.n_training_events == data.n && report.evaluation_scope.declared_panel
                        @test report.reference.evaluation_panel == evaluation_panel
                        @test_throws ArgumentError mfrm_spec(BayesianMGMFRM._mfrm_anchor_response_data(
                            heldout_bytes, response_ref(heldout)); thresholds, anchors)
                    end
                    if information
                        @test report.evaluation_scope.n_training_events == report.evaluation_scope.n_evaluation_events == 160
                        @test report.evaluation_scope.declared_panel && report.reference.evaluation_panel == evaluation_panel
                        @test length(report.reference.cell.truth.person) == 20
                        @test only(t for t in report.cell.targets if t.name == "P30-P10").true_value ≈ base_theta[30] - base_theta[10]
                        if unused !== nothing
                            rare = only(row for row in report.category_totals if row.category == unused)
                            @test rare.observed_count == 0 && rare.truth_expected_count > 0 && rare.predicted_expected_count > 0
                        end
                        if topology == "S20"
                            control = secondary_panels[(thresholds, c.id)]
                            @test control.report.reference.evaluation_panel == evaluation_panel
                            @test control.report.dataset_id != report.dataset_id && control.report.heldout_id != report.heldout_id
                            @test control.report.reference.training != report.reference.training
                        end
                    end
                    if nested || information || misfit || (sparse && c.kind === :E && c.id == c.anchor_id) || c.id != c.anchor_id
                        selections = misfit ? [evaluation_indices,
                                filter(n -> affected[n], evaluation_indices), filter(n -> !affected[n], evaluation_indices)] :
                            sparse && c.id == c.anchor_id ? [findall(e -> e[1] in selected_people, events)] : [evaluation_indices]
                        misfit_views = NamedTuple[]
                        for scored_indices in selections
                            scored_report, scored_heldout = report, heldout
                            if scored_indices != evaluation_indices
                                # A secondary view of the SAME fit/attempt, not
                                # a new cell, data block, or primary overwrite.
                                before = full_hash((report, reference, train_bytes, heldout_bytes, log_truth))
                                selected = Set(BayesianMGMFRM._mfrm_anchor_event_key.(rows[scored_indices]))
                                scored_heldout = merge(heldout, (; rows = [row for row in heldout.rows
                                    if BayesianMGMFRM._mfrm_anchor_event_key(row) in selected]))
                                selected_truth = [row for row in log_truth if BayesianMGMFRM._mfrm_anchor_event_key(row) in selected]
                                panel_id = misfit ? (affected[first(scored_indices)] ? "misfit/affected" : "misfit/unaffected") : "information/common-160"
                                panel = (; panel_id, weighting = :equal_event,
                                    events = [Base.structdiff(row, (; score = nothing)) for row in rows[scored_indices]])
                                selected_reference = merge(reference, (; heldout = response_ref(scored_heldout), evaluation_panel = panel,
                                    truth_sha256 = full_hash(selected_truth), cell = merge(declaration, (; log_truth_sha256 = full_hash(selected_truth)))))
                                scored_report = BayesianMGMFRM._mfrm_anchor_score_attempt(fitted, train_bytes, raw(scored_heldout), selected_truth;
                                    reference = selected_reference)
                                @test full_hash((report, reference, train_bytes, heldout_bytes, log_truth)) == before
                                @test BayesianMGMFRM._mfrm_anchor_fit_hash(fitted) == reference.fit_sha256 == scored_report.reference.fit_sha256
                                @test (report.dataset_id, report.heldout_id, report.method, report.attempt) ==
                                    (scored_report.dataset_id, scored_report.heldout_id, scored_report.method, scored_report.attempt)
                                @test report.evaluation_scope.n_evaluation_events == length(evaluation_indices)
                                @test scored_report.evaluation_scope.n_training_events == data.n &&
                                    scored_report.evaluation_scope.n_evaluation_events == length(scored_indices)
                                @test report.contrast_scores == scored_report.contrast_scores && report.cell == scored_report.cell
                                @test report.content_hash != scored_report.content_hash && reference.heldout != selected_reference.heldout
                                @test_throws ArgumentError BayesianMGMFRM._mfrm_anchor_primary_attempts([reference], [report, scored_report])
                                saved_view = (; report = scored_report, digest = full_hash(scored_report))
                                predictive_views[(c.id, panel_id)] = saved_view
                                if misfit
                                    @test scored_report.cell.recovery_status === :distortion_only && scored_report.evaluation_scope.declared_panel
                                    push!(misfit_views, scored_report)
                                    push!(checked_misfit_views, (reference.method, panel_id))
                                else
                                    @test !report.evaluation_scope.declared_panel && data.n == 320 && length(scored_indices) == 160
                                    secondary_panels[(thresholds, c.id)] = saved_view
                                end
                            end
                            # Independent recurrence on declared events, including
                            # absent categories, not an average over training rows.
                            n_events = length(scored_indices)
                            columns = Dict(name => n for (n, name) in pairs(design.parameter_names))
                            coord(block, label, s) = haskey(columns, "$block[$label]") ?
                                draws[s, columns["$block[$label]"]] : getproperty(means, block)[label]
                            oracle_logs = Array{Float64}(undef, 160, n_events, 4)
                            for s in 1:160, (n, event_index) in pairs(scored_indices)
                                p, r, i = events[event_index]
                                location = coord(:person, "P$(lpad(string(p), 2, '0'))", s) - coord(:rater, "R$r", s) - coord(:item, "I$i", s)
                                free_steps = [draws[s, columns[thresholds === :rating_scale ? "step[$k]" : "step[item=I$i,$k]"]] for k in 1:2]
                                oracle_logs[s, n, :] = probability(location, [free_steps; -sum(free_steps)]; log_probabilities = true)
                            end
                            logmean = [BayesianMGMFRM._logmeanexp(oracle_logs[:, n, k]) for n in 1:n_events, k in 1:4]
                            oracle_truth = misfit ? misfit_oracle[scored_indices, :] :
                                reduce(vcat, [permutedims(probability(theta[p] - rho[r] - beta[i], steps[i]; log_probabilities = true))
                                    for (p, r, i) in events[scored_indices]])
                            heldout_scores = Dict(BayesianMGMFRM._mfrm_anchor_event_key(row) => row.score for row in scored_heldout.rows)
                            @test scored_report.truth_score.estimate ≈ sum(exp.(oracle_truth) .* (oracle_truth .- logmean)) / n_events atol = 1e-12
                            @test scored_report.heldout_score.estimate ≈ -mean(logmean[n, heldout_scores[BayesianMGMFRM._mfrm_anchor_event_key(row)] + 1]
                                for (n, row) in pairs(rows[scored_indices])) atol = 1e-12
                            @test scored_report.truth_score.curvature_review_required && !scored_report.truth_score.precision_threshold_applied
                            @test scored_report.heldout_score.curvature_review_required && !scored_report.heldout_score.precision_threshold_applied
                            for (k, total) in pairs(scored_report.category_totals)
                                @test total.observed_count == count(row -> row.score == k - 1, scored_heldout.rows)
                                @test total.truth_expected_count ≈ sum(exp, oracle_truth[:, k]) atol = 1e-12
                                @test total.predicted_expected_count ≈ sum(exp, logmean[:, k]) atol = 1e-12
                            end
                        end
                        if misfit
                            @test [v.evaluation_scope.n_evaluation_events for v in misfit_views] == (nested ? [8, 312] : [80, 240])
                            for field in (:truth_score, :heldout_score)
                                @test sum(v.evaluation_scope.n_evaluation_events * getproperty(v, field).estimate for v in misfit_views) / 320 ≈
                                    getproperty(report, field).estimate atol = 1e-12
                            end
                            # Endpoints (0,3) and interiors (1,2) remain sums of
                            # declared category totals, not new scales/intervals.
                            for band in ((1, 4), (2, 3)), field in (:observed_count, :truth_expected_count, :predicted_expected_count)
                                @test sum(getproperty(v.category_totals[k], field) for v in misfit_views for k in band) ≈
                                    sum(getproperty(report.category_totals[k], field) for k in band) atol = 1e-12
                            end
                        end
                    end
                    oracle = Dict{String,NamedTuple}()
                    for (target, scored) in zip(targets, report.contrast_scores)
                        fixed_levels = target.block === :rater ? ["R$r" for r in rfixed] :
                            target.block === :item ? ["I$i" for i in ifixed] : String[]
                        nfixed = count(in(fixed_levels), (target.positive, target.negative))
                        block_truth = Dict(row.level => row.value for row in getproperty(labelled_truth, target.block))
                        error = getproperty(means, target.block)[target.positive] - getproperty(means, target.block)[target.negative] -
                            (block_truth[target.positive] - block_truth[target.negative])
                        applicability = nfixed == 2 ? :not_applicable_fixed : misfit || c.kind === :D ? :distortion_only : :candidate_available
                        oracle[target.name] = (; error, applicability)
                        @test scored.target_error ≈ error atol = 1e-12
                        @test scored.recovery_status === applicability
                        @test scored.contrast_is_fixed == (nfixed == 2)
                        @test scored.target.role === target.role
                        if nfixed == 2
                            @test scored.recovery === nothing && scored.mcse === nothing
                        else
                            @test scored.status === :screen_passed
                            @test scored.contrast_estimation_status === (nfixed == 1 ?
                                :partially_estimated_contrast : :posterior_estimated_contrast)
                            @test (scored.recovery === nothing) == (misfit || c.kind === :D)
                        end
                    end
                    reports[c.id] = (; report, oracle, digest = full_hash(report))
                    push!(checked_cells, reference.method)
                end
            end
        end
        @test length(unique(signatures)) == length(selected_cells)
        comparisons = [(ids = ("R", "B"), weights = (1, -1)),
            (ids = ("RI", "I"), weights = (1, -1)), (ids = ("I", "B"), weights = (1, -1)),
            (ids = ("RI", "R"), weights = (1, -1)), (ids = ("RI", "R", "I", "B"), weights = (1, -1, -1, 1))]
        if sparse
            for c in cells
                c.kind === :E && continue
                control = isempty(c.raters) ? "I" : isempty(c.items) ? "R" : "RI"
                push!(comparisons, (; ids = (c.id, control), weights = (1, -1)))
                c.kind === :S && push!(comparisons, (; ids = (c.id, "B"), weights = (1, -1)))
            end
            append!(comparisons, [(; ids = (error_id(u, v), error_id(u, 0.0), error_id(0.0, v), "RI"),
                weights = (1, -1, -1, 1)) for u in U for v in U])
            append!(comparisons, [(; ids = (prior_id(id, scale), id), weights = (1, -1))
                for id in prior_controls for scale in (0.5, 2.0)])
            append!(comparisons, [(; ids = (prior_id(shifted, scale), prior_id(clean, scale)), weights = (1, -1))
                for (shifted, clean) in (("C-R-u+0.8", "R"), ("C-I-v+0.8", "I")) for scale in (0.5, 2.0)])
            append!(comparisons, [(; ids = (start_id(id), id), weights = (1, -1)) for id in ("B", "R", "I", "RI")])
        end
        for comparison in comparisons, request in requests
            @testset "Paired $(comparison.ids) / $(request.name)" begin
                groups = [let saved = reports[id], r = saved.report
                    rejected_attempt = (; dataset_id = rejected.dataset_id, heldout_id = "synthetic/$prefix/rejected/heldout",
                        r.method, attempt = 1, status = :structurally_rejected, reason = "single_observed_category",
                        training = response_ref(rejected))
                    attempts = information ? NamedTuple[r, rejected_attempt] : NamedTuple[r]
                    rejected_plan = (; rejected_attempt.dataset_id, rejected_attempt.heldout_id, r.method, reference_sha256 = nothing)
                    pending = (; dataset_id = "synthetic/$prefix/pending/train", heldout_id = "synthetic/$prefix/pending/heldout",
                        r.method, reference_sha256 = nothing)
                    if misfit || endswith(id, "-J0.5")
                        # A failed planned method is still a primary case,
                        # not a successful replacement for another method.
                        push!(attempts, (; pending.dataset_id, pending.heldout_id, r.method, attempt = 1,
                            status = :fit_failed, reason = misfit ? "synthetic misfit-cell failure; no fit executed" :
                                "synthetic planned-start failure; no fit executed"))
                    end
                    (; plan = [(; r.dataset_id, r.heldout_id, r.method, reference_sha256 = full_hash(r.reference)),
                            (information ? [rejected_plan] : NamedTuple[])...,
                            pending],
                        attempts, r.cell, request, diagnostic_policy = policy,
                        attempt_hashes = Dict((a.dataset_id, a.heldout_id, a.method, 1) =>
                            (a.status === :scored ? saved.digest : full_hash(a)) for a in attempts))
                end for id in comparison.ids]
                if nested && !misfit && comparison.ids == ("R", "B") && request.name == targets[1].name
                    current = groups[2]
                    if previous_link_group !== nothing
                        @test_throws ArgumentError BayesianMGMFRM._mfrm_anchor_paired_recovery([previous_link_group, current];
                            comparison = ((; method = previous_link_group.plan[1].method, weight = 1),
                                (; method = current.plan[1].method, weight = -1)))
                        for score in (:truth_score, :heldout_score)
                            @test_throws ArgumentError BayesianMGMFRM._mfrm_anchor_paired_predictive([previous_link_group, current]; score,
                                comparison = ((; method = previous_link_group.plan[1].method, weight = 1),
                                    (; method = current.plan[1].method, weight = -1)))
                        end
                    end
                    previous_link_group = current
                end
                if (sparse || information) && comparison.ids == ("R", "B") && request.name == targets[1].name
                    current = groups[2]
                    if information
                        @test_throws ArgumentError BayesianMGMFRM._mfrm_anchor_paired_recovery([previous_information_group, current];
                            comparison = ((; method = previous_information_group.plan[1].method, weight = 1),
                                (; method = current.plan[1].method, weight = -1)))
                        for score in (:truth_score, :heldout_score)
                            @test_throws ArgumentError BayesianMGMFRM._mfrm_anchor_paired_predictive([previous_information_group, current]; score,
                                comparison = ((; method = previous_information_group.plan[1].method, weight = 1),
                                    (; method = current.plan[1].method, weight = -1)))
                        end
                    end
                    previous_information_group = current
                end
                if (sparse || topology == "N-C4" || misfit) && comparison.ids == ("R", "B") && request.name == targets[1].name
                    current = groups[2]
                    if misfit
                        control = misfit_controls[(thresholds, nested)]
                        @test control.attempts[1].reference.cell.model_status === :declared_correct
                        @test current.attempts[1].reference.cell.model_status === :misspecified
                        @test current.attempts[1].reference.training != control.attempts[1].reference.training
                        @test current.attempts[1].reference.truth_sha256 != control.attempts[1].reference.truth_sha256
                        for other in (previous_misfit_group === nothing ? [control] : [control, previous_misfit_group])
                            @test_throws ArgumentError BayesianMGMFRM._mfrm_anchor_paired_recovery([other, current];
                                comparison = ((; method = other.plan[1].method, weight = 1),
                                    (; method = current.plan[1].method, weight = -1)))
                            for score in (:truth_score, :heldout_score)
                                @test_throws ArgumentError BayesianMGMFRM._mfrm_anchor_paired_predictive([other, current]; score,
                                    comparison = ((; method = other.plan[1].method, weight = 1),
                                        (; method = current.plan[1].method, weight = -1)))
                            end
                        end
                        previous_misfit_group = current
                    else
                        misfit_controls[(thresholds, nested)] = current
                    end
                end
                weights = Tuple((; method = "$prefix-$id", weight) for (id, weight) in zip(comparison.ids, comparison.weights))
                if request.name == targets[1].name
                    # Once per comparison/score kind, NOT per parameter target.
                    # Reuse the scored reports and preserve all primary failures.
                    panels = sort!(unique([key[2] for key in keys(predictive_views)]))
                    filter!(panel -> all(id -> haskey(predictive_views, (id, panel)), comparison.ids), panels)
                    predictive = Dict{Tuple,NamedTuple}()
                    for panel in (nothing, panels...)
                        selected_reports = [panel === nothing ? reports[id] : predictive_views[(id, panel)] for id in comparison.ids]
                        pgroups = [let r = saved.report
                            @test (r.dataset_id, r.heldout_id, r.method, r.attempt) ==
                                (g.attempts[1].dataset_id, g.attempts[1].heldout_id, g.attempts[1].method, 1)
                            (; plan = [merge(g.plan[1], (; reference_sha256 = full_hash(r.reference))); g.plan[2:end]],
                                attempts = NamedTuple[r; g.attempts[2:end]],
                                attempt_hashes = merge(g.attempt_hashes,
                                    Dict((r.dataset_id, r.heldout_id, r.method, 1) => saved.digest)))
                        end for (g, saved) in zip(groups, selected_reports)]
                        before = full_hash(pgroups)
                        for score in (:truth_score, :heldout_score)
                            p = BayesianMGMFRM._mfrm_anchor_paired_predictive(pgroups; comparison = weights, score)
                            expected_loss = sum(weight * getproperty(saved.report, score).estimate
                                for (weight, saved) in zip(comparison.weights, selected_reports))
                            @test p.status === :descriptive_common_subset && p.aggregate_finite
                            @test (p.n_planned, p.n_common_finite, p.n_joint_point_available) == (information ? 3 : 2, 1, 1)
                            @test p.mean_difference ≈ expected_loss atol = 1e-12
                            @test ismissing(p.across_replication_se) && ismissing(p.combined_within_fit_mcse)
                            scored_row = only(row for row in p.rows if row.dataset_id == training.dataset_id)
                            @test scored_row.status === :point_available && isapprox(scored_row.loss_difference, expected_loss; atol = 1e-12)
                            @test [m.point_loss for m in scored_row.methods] ≈
                                [getproperty(saved.report, score).estimate for saved in selected_reports] atol = 1e-12
                            @test all(row -> ismissing(row.loss_difference), [row for row in p.rows if row.dataset_id != training.dataset_id])
                            @test p.selection === :bound_finite_primary && !p.diagnostic_selection_applied
                            @test p.precision_status === :unresolved && p.curvature_review_required && p.convergence_review_required
                            @test !p.validation_claim_allowed && !p.lifecycle_counts_available && p.declaration_and_provenance_review_required
                            @test p.content_hash == artifact_content_hash(p)
                            for (m, g) in zip(p.methods, pgroups)
                                @test m.n_scored_primary == m.n_point_available == 1 && m.n_additional_attempts == 0
                                @test m.n_reported_primary == length(g.attempts) && m.n_planned == length(g.plan)
                                expected_dispositions = information ? [:structurally_rejected, :not_recorded] :
                                    [misfit || endswith(m.method, "-J0.5") ? :fit_failed : :not_recorded]
                                @test Set(m.unavailable_counts) == Set((; disposition = d, n = 1) for d in expected_dispositions)
                            end
                            if panel === nothing
                                union!(predictive_cells[score], (s.report.method for s in selected_reports))
                            else
                                @test p.plans != predictive[(nothing, score)].plans
                                @test [m.unavailable_counts for m in p.methods] ==
                                    [m.unavailable_counts for m in predictive[(nothing, score)].methods]
                                # Same attempt IDs are not permission to mix full
                                # and subset evidence in a same-data comparison.
                                mixed = [groups[1]; pgroups[2:end]]
                                @test_throws ArgumentError BayesianMGMFRM._mfrm_anchor_paired_predictive(mixed; comparison = weights, score)
                            end
                            predictive[(panel, score)] = p
                            push!(checked_predictive, (prefix, comparison.ids, panel, score))
                        end
                        @test full_hash(pgroups) == before
                    end
                    if misfit
                        for score in (:truth_score, :heldout_score)
                            reconstructed = sum(predictive_views[(comparison.ids[1], panel)].report.evaluation_scope.n_evaluation_events *
                                predictive[(panel, score)].mean_difference for panel in panels) / length(evaluation_indices)
                            @test reconstructed ≈ predictive[(nothing, score)].mean_difference atol = 1e-12
                        end
                    end
                end
                paired = BayesianMGMFRM._mfrm_anchor_paired_recovery(groups; comparison = weights)
                expected = [reports[id].oracle[request.name] for id in comparison.ids]
                applicable = all(row -> row.applicability === :candidate_available, expected)
                @test paired.status === (applicable ? :conditional_summary : :inapplicable_comparison)
                @test paired.n_planned == (information ? 3 : 2) && paired.n_common_eligible == Int(applicable)
                @test ismissing(paired.bias_difference_mcse) && ismissing(paired.mse_difference_mcse)
                scored_row = only(row for row in paired.rows if row.dataset_id == training.dataset_id)
                @test [m.point_error for m in scored_row.methods] ≈ [r.error for r in expected] atol = 1e-12
                if applicable
                    @test paired.bias_difference ≈ sum(w * r.error for (w, r) in zip(comparison.weights, expected)) atol = 1e-12
                    @test paired.mse_difference ≈ sum(w * r.error^2 for (w, r) in zip(comparison.weights, expected)) atol = 1e-12
                else
                    @test ismissing(paired.bias_difference) && ismissing(paired.mse_difference)
                end
                for (method, expected_row) in zip(paired.methods, expected)
                    @test method.applicability === expected_row.applicability
                    @test (method.coverage === nothing) == (expected_row.applicability !== :candidate_available)
                    if information
                        @test method.n_scored_primary == 1 && method.n_reported_primary == 2 && method.n_additional_attempts == 0
                        @test only(row for row in method.unavailable_counts if row.disposition === :structurally_rejected).n == 1
                        @test only(row for row in method.unavailable_counts if row.disposition === :not_recorded).n == 1
                        @test method.coverage.n_planned == 3
                    end
                    if endswith(method.method, "-J0.5")
                        @test method.n_scored_primary == 1 && method.n_reported_primary == 2 && method.n_additional_attempts == 0
                        @test only(row for row in method.unavailable_counts if row.disposition === :fit_failed).n == 1
                        @test method.coverage.n_planned == 2 && all(row -> row.attempt == 1, method.dispositions)
                    end
                    if misfit
                        @test method.n_planned == 2 && method.n_scored_primary == 1 && method.n_reported_primary == 2
                        @test method.n_screen_eligible == 0 && method.n_additional_attempts == 0
                        @test method.coverage === nothing && method.recovery_summary === nothing
                        @test only(row for row in method.unavailable_counts if row.disposition === :distortion_only).n == 1
                        @test only(row for row in method.unavailable_counts if row.disposition === :fit_failed).n == 1
                        @test all(row -> row.attempt == 1, method.dispositions)
                    end
                end
                @test !paired.validation_claim_allowed && !paired.lifecycle_counts_available
                push!(checked_comparisons, (prefix, comparison.ids, request.name))
            end
        end
        println("candidate profile processed: $prefix; $(length(reports)) primary reports; $(length(predictive_views)) secondary views")
        flush(stdout) # Progress stays in the quiet wrapper's retained log.
        sparse || continue # The 57 sensitivity regimes were proposed only for sparse data.
        for c in selected_cells
            c.id == c.anchor_id && continue
            variant, control = results[c.id], results[c.anchor_id]
            r, baseline = reports[c.id].report, reports[c.anchor_id].report
            @test variant.names == control.names && variant.likelihood == control.likelihood
            @test variant.probabilities == control.probabilities
            @test r.cell.cell_id == baseline.cell.cell_id && r.method != baseline.method
            @test r.attempt == baseline.attempt == 1
            @test r.reference.training == baseline.reference.training && r.reference.heldout == baseline.reference.heldout
            @test r.reference.truth_sha256 == baseline.reference.truth_sha256 && r.reference.cell.truth == baseline.reference.cell.truth
            @test r.reference.fit_sha256 != baseline.reference.fit_sha256
            @test length(BayesianMGMFRM._mfrm_anchor_primary_attempts([baseline.reference, r.reference], [baseline, r])) == 2
            if c.prior_scale != 1.0
                @test !isapprox(variant.prior, control.prior; atol = 1e-12, rtol = 0)
                @test !isapprox(variant.posterior, control.posterior; atol = 1e-12, rtol = 0)
                @test variant.starts == control.starts # Equal test RNG and jitter, not an evaluation seed policy.
            else
                @test variant.prior == control.prior && variant.posterior == control.posterior
                @test all(a ≈ 25 .* b for (a, b) in zip(variant.starts, control.starts))
                @test_throws ArgumentError BayesianMGMFRM._mfrm_anchor_primary_attempts([baseline.reference],
                    [merge(r, (; method = baseline.method, attempt = 2))])
            end
        end
        for (shifted, clean) in (("C-R-u+0.8", "R"), ("C-I-v+0.8", "I")), scale in (0.5, 2.0)
            a, b = results[prior_id(shifted, scale)], results[prior_id(clean, scale)]
            @test a.names == b.names
            @test a.probabilities ≈ b.probabilities atol = 1e-12
            @test a.prior - b.prior ≈ (results[shifted].prior - results[clean].prior) / scale^2 atol = 1e-12
        end
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
    @test length(checked_cells) == length(unique(checked_cells)) == 266
    @test length(checked_data) == length(unique(checked_data)) == 30
    @test count(id -> occursin("-X", id), checked_data) == 8
    @test count(id -> occursin("-X", id), checked_cells) == 32
    @test count(id -> occursin("-N-", id) && !occursin("-X", id), checked_cells) == 32
    @test count(id -> occursin("-S20", id), checked_cells) == 40
    @test count(id -> endswith(id, "-P0.5") || endswith(id, "-P2.0"), checked_cells) == 24
    @test count(id -> endswith(id, "-J0.5"), checked_cells) == 8
    @test length(secondary_panels) == 8
    @test length(checked_misfit_views) == length(unique(checked_misfit_views)) == 64
    @test length(misfit_controls) == 4
    @test length(checked_comparisons) == length(unique(checked_comparisons)) == 1710
    @test length(checked_predictive) == length(unique(checked_predictive)) == 864
    @test count(c -> c[3] === nothing, checked_predictive) == 684
    @test count(c -> c[3] == "information/common-160", checked_predictive) == 20
    @test count(c -> c[3] in ("misfit/affected", "misfit/unaffected"), checked_predictive) == 160
    @test all(ids -> ids == Set(checked_cells), Base.values(predictive_cells))
    @test Set((c[1], c[2]) for c in checked_predictive if c[3] === nothing) ==
        Set((c[1], c[2]) for c in checked_comparisons)
    @test count(c -> occursin("-X", c[1]), checked_comparisons) == 200
    @test count(c -> occursin("-N-", c[1]) && !occursin("-X", c[1]), checked_comparisons) == 200
    @test count(c -> occursin("-S20", c[1]), checked_comparisons) == 250
    @test count(c -> any(id -> endswith(id, "-P0.5") || endswith(id, "-P2.0") || endswith(id, "-J0.5"), c[2]), checked_comparisons) == 200
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
