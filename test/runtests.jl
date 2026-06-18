using Test
using ForwardDiff
using JSON3
using LinearAlgebra
using LogDensityProblems
using Random
using ReverseDiff
using SHA

import BayesianMGMFRM
using BayesianMGMFRM:
    FacetData,
    compare_models,
    coverage_matrix,
    coverage_summary,
    expected_scores,
    fit,
    fit_stats,
    getdesign,
    ScalarValidationData,
    ScalarValidationAnalyticLogDensity,
    ScalarValidationContrastLogDensity,
    ScalarValidationLogDensity,
    scalar_validation_contrast_num_params,
    scalar_validation_decode,
    scalar_validation_decode_contrast,
    scalar_validation_logposterior,
    scalar_validation_logposterior_and_gradient,
    scalar_validation_logposterior_contrast,
    scalar_validation_num_params,
    scalar_validation_offsets,
    logposterior,
    MFRMFit,
    MFRMPrior,
    mfrm_spec,
    pointwise_loglikelihood,
    pointwise_loglikelihood_matrix,
    posterior_predict,
    posterior_predictive_check,
    posterior_summary,
    predictive_check_summary,
    predictive_probabilities,
    predictive_residuals,
    predictive_variances,
    prior_predict,
    prior_predictive_check,
    rater_overlap,
    threshold_map_data,
    validate_design,
    waic,
    zerosum_basis_fast

struct ExplodingTable end
Base.getindex(::ExplodingTable, args...) = error("backend exploded")

struct InternalMethodErrorTable end
_method_error_trigger(::Int) = nothing
Base.getindex(::InternalMethodErrorTable, args...) = _method_error_trigger("not an Int")

function central_difference(logp, x, i; eps = 1e-5)
    xp = copy(x)
    xm = copy(x)
    xp[i] += eps
    xm[i] -= eps
    return (logp(xp) - logp(xm)) / (2eps)
end

function has_issue(report, code::Symbol)
    return any(issue -> issue.code === code, report.issues)
end

function has_issue(report, code::Symbol, facet::Symbol)
    return any(report.issues) do issue
        issue.code === code &&
            haskey(issue.context, :facet) &&
            issue.context[:facet] === facet
    end
end

function has_doc(mod, name::Symbol)
    isdefined(mod, name) || return false
    binding = Base.Docs.Binding(mod, name)
    haskey(Base.Docs.meta(mod), binding) && return true
    try
        return Base.Docs.doc(getfield(mod, name)) !== nothing
    catch error
        error isa MethodError || rethrow()
        return false
    end
end

function file_sha256(path)
    return bytes2hex(open(sha256, path))
end

function test_logsumexp(vals)
    m = maximum(vals)
    return m + log(sum(exp(v - m) for v in vals))
end

function test_sample_variance(vals)
    n = length(vals)
    m = sum(Float64, vals) / n
    return sum((Float64(v) - m)^2 for v in vals) / (n - 1)
end

function raw_pcm_pointwise(data, person, rater, item, steps_by_item)
    K = length(data.category_levels)
    out = Vector{Float64}(undef, data.n)
    for n in 1:data.n
        location = person[data.person[n]] - rater[data.rater[n]] - item[data.item[n]]
        steps = steps_by_item[data.item[n]]
        etas = [
            (category - 1) * location - sum(steps[1:(category - 1)]; init = 0.0)
            for category in 1:K
        ]
        out[n] = etas[data.category[n]] - test_logsumexp(etas)
    end
    return out
end

function scalar_validation_fixture_data(fixture)
    data = fixture[:data]
    return ScalarValidationData(
        X = Vector{Int}(data[:X]),
        examinee = Vector{Int}(data[:examinee]),
        rater = Vector{Int}(data[:rater]),
        J = Int(data[:J]),
        R = Int(data[:R]),
        K = Int(data[:K]),
        N = Int(data[:N]),
    )
end

@testset "public docstrings" begin
    for name in (:FacetData, :ValidationIssue, :ValidationReport, :FacetSpec, :FacetDesign,
            :MFRMPrior, :MFRMFit, :expected_scores, :fit, :fit_stats, :logposterior,
            :compare_models, :coverage_matrix, :coverage_summary, :validate_design, :mfrm_spec, :getdesign,
            :pointwise_loglikelihood, :pointwise_loglikelihood_matrix, :posterior_predict,
            :posterior_predictive_check, :posterior_summary,
            :predictive_check_summary, :predictive_probabilities,
            :predictive_residuals, :predictive_variances,
            :prior_predict, :prior_predictive_check,
            :rater_overlap, :threshold_map_data, :evidence_metadata, :waic)
        @test has_doc(BayesianMGMFRM, name)
    end
    @test !isdefined(BayesianMGMFRM, :audit)
    @test !isdefined(BayesianMGMFRM, :AuditIssue)
    @test !isdefined(BayesianMGMFRM, :AuditReport)
end

@testset "FacetData long-format indexing" begin
    table = (
        examinee = ["E2", "E1", "E1", "E2", "E1", "E2", "E2", "E1"],
        rater = ["R2", "R1", "R2", "R1", "R1", "R2", "R1", "R2"],
        item = ["I2", "I1", "I1", "I2", "I2", "I1", "I1", "I2"],
        score = [2, 0, 1, 1, 2, 0, 1, 2],
    )
    data = FacetData(table; person = :examinee, rater = :rater, item = :item, score = :score)

    @test length(data) == 8
    @test data.person_levels == Any["E1", "E2"]
    @test data.rater_levels == Any["R1", "R2"]
    @test data.item_levels == Any["I1", "I2"]
    @test data.category_levels == [0, 1, 2]
    @test data.person == [2, 1, 1, 2, 1, 2, 2, 1]

    reordered = (
        examinee = reverse(table.examinee),
        rater = reverse(table.rater),
        item = reverse(table.item),
        score = reverse(table.score),
    )
    data2 = FacetData(reordered; person = :examinee, rater = :rater, item = :item, score = :score)
    @test data2.person_levels == data.person_levels
    @test data2.rater_levels == data.rater_levels
    @test data2.item_levels == data.item_levels
    @test data2.category_levels == data.category_levels

    numeric_labels = (
        examinee = [1, 10, 2, 1],
        rater = ["R1", "R1", "R1", "R1"],
        item = ["I1", "I1", "I1", "I1"],
        score = [0, 1, 0, 1],
    )
    data3 = FacetData(numeric_labels; person = :examinee, rater = :rater, item = :item, score = :score)
    @test data3.person_levels == Any[1, 2, 10]

    bool_scores = (
        examinee = ["E1", "E1"],
        rater = ["R1", "R1"],
        item = ["I1", "I1"],
        score = [false, true],
    )
    @test_throws ArgumentError FacetData(bool_scores; person = :examinee, rater = :rater, item = :item, score = :score)

    @test_throws ErrorException FacetData(ExplodingTable(); person = :examinee, rater = :rater, item = :item, score = :score)
    @test_throws MethodError FacetData(InternalMethodErrorTable(); person = :examinee, rater = :rater, item = :item, score = :score)
end

@testset "pre-fit validation" begin
    empty = (
        examinee = String[],
        rater = String[],
        item = String[],
        score = Int[],
    )
    empty_data = FacetData(empty; person = :examinee, rater = :rater, item = :item, score = :score)
    empty_report = validate_design(empty_data)
    @test !empty_report.passed
    @test has_issue(empty_report, :empty_data)

    connected = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        score = [0, 1, 2, 1, 0, 2],
    )
    connected_data = FacetData(connected; person = :examinee, rater = :rater, item = :item, score = :score)
    connected_report = validate_design(connected_data)
    @test connected_report.passed
    @test !has_issue(connected_report, :disconnected_design)
    @test !has_issue(connected_report, :rank_deficient_design)
    @test has_issue(connected_report, :unobserved_item_category)

    rank_deficient_connected = (
        examinee = ["E1", "E1", "E2", "E2"],
        rater = ["R1", "R2", "R2", "R1"],
        item = ["I1", "I1", "I2", "I2"],
        score = [0, 1, 2, 1],
    )
    rank_data = FacetData(rank_deficient_connected; person = :examinee, rater = :rater, item = :item, score = :score)
    rank_report = validate_design(rank_data)
    @test !rank_report.passed
    @test !has_issue(rank_report, :disconnected_design)
    @test has_issue(rank_report, :rank_deficient_design)
    @test_throws ArgumentError mfrm_spec(rank_data)

    disconnected = (
        examinee = ["E1", "E1", "E2", "E2"],
        rater = ["R1", "R1", "R2", "R2"],
        item = ["I1", "I1", "I2", "I2"],
        score = [0, 1, 0, 1],
    )
    disconnected_data = FacetData(disconnected; person = :examinee, rater = :rater, item = :item, score = :score)
    disconnected_report = validate_design(disconnected_data)
    @test !disconnected_report.passed
    @test has_issue(disconnected_report, :disconnected_design)
    @test_throws ArgumentError mfrm_spec(disconnected_data)

    skipped_category = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        score = [0, 2, 0, 2, 0, 2],
    )
    skipped_data = FacetData(skipped_category; person = :examinee, rater = :rater, item = :item, score = :score)
    skipped_report = validate_design(skipped_data)
    @test skipped_report.passed
    @test skipped_data.category_levels == [0, 1, 2]
    @test skipped_report.category_counts[1] == 0
    @test has_issue(skipped_report, :unused_interior_category)
    @test has_issue(skipped_report, :unobserved_item_category)

    optional_singleton = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        group = ["A", "A", "A", "A", "A", "B"],
        score = [0, 1, 2, 1, 0, 2],
    )
    optional_data = FacetData(optional_singleton;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
        group = :group)
    optional_report = validate_design(optional_data)
    @test has_issue(optional_report, :singleton_facet_level, :group)

    dff_empty = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        group = ["A", "A", "A", "A", "B", "A"],
        score = [0, 1, 2, 1, 0, 2],
    )
    dff_data = FacetData(dff_empty;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
        group = :group)
    dff_report = validate_design(dff_data; bias = [(:rater, :group)])
    @test dff_report.passed
    @test has_issue(dff_report, :empty_dff_cell)
    @test has_issue(dff_report, :potential_dff_confounding)
    @test dff_report.dff_counts[(:rater, :group)][("R1", "B")] == 0

    invalid_bias_report = validate_design(connected_data; bias = [:rater])
    @test !invalid_bias_report.passed
    @test has_issue(invalid_bias_report, :invalid_bias_term)

    unknown_bias_report = validate_design(connected_data; bias = [(:rater, :group)])
    @test !unknown_bias_report.passed
    @test has_issue(unknown_bias_report, :unknown_bias_facet)

    sparse_dff_report = validate_design(dff_data; bias = [(:rater, :group)], min_cell_count = 3)
    @test sparse_dff_report.passed
    @test has_issue(sparse_dff_report, :sparse_dff_cell)
    @test_throws ArgumentError validate_design(connected_data; min_cell_count = 0)
end

@testset "minimal MFRM spec and design" begin
    table = (
        examinee = ["E1", "E1"],
        rater = ["R1", "R1"],
        item = ["I1", "I1"],
        score = [0, 1],
    )
    data = FacetData(table; person = :examinee, rater = :rater, item = :item, score = :score)
    spec = mfrm_spec(data; thresholds = :partial_credit)
    design = getdesign(spec)

    @test design.parameter_names == ["person[E1]"]
    @test design.blocks[:person] == 1:1
    @test isempty(design.blocks[:rater])
    @test isempty(design.blocks[:item])
    @test isempty(design.blocks[:thresholds])
    @test design.identification[:person] === :free
    @test design.identification[:rater] === :reference_first
    @test design.identification[:item] === :reference_first
    @test design.identification[:thresholds] === :sum_to_zero

    params = [0.4]
    pointwise = pointwise_loglikelihood(design, params)
    location = 0.4
    eta0 = 0.0
    eta1 = location
    denom = log(exp(eta0) + exp(eta1))
    @test pointwise[1] ≈ eta0 - denom
    @test pointwise[2] ≈ eta1 - denom

    summary = coverage_summary(spec)
    @test summary.n_ratings == 2
    @test summary.n_persons == 1
    @test summary.n_raters == 1
    @test summary.n_items == 1
    @test summary.validation.passed
    @test [row.category for row in summary.category_counts] == [0, 1]
    @test sum(row.count for row in summary.category_counts) == 2
    @test any(row -> row.facet === :person && row.n_levels == 1, summary.facet_summary)

    matrix = coverage_matrix(spec)
    @test matrix.row_facet === :rater
    @test matrix.column_facet === :person
    @test matrix.row_levels == Any["R1"]
    @test matrix.column_levels == Any["E1"]
    @test matrix.counts == reshape([2], 1, 1)

    binary_thresholds = threshold_map_data(design; params)
    @test length(binary_thresholds) == 1
    @test binary_thresholds[1].status === :fixed_zero
    @test binary_thresholds[1].value == 0.0

    identified = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        task = ["T1", "T1", "T2", "T1", "T2", "T2"],
        score = [0, 1, 2, 1, 0, 2],
    )
    identified_data = FacetData(identified; person = :examinee, rater = :rater, item = :item, score = :score, task = :task)
    identified_spec = mfrm_spec(identified_data; thresholds = :partial_credit)
    identified_design = getdesign(identified_spec)
    @test identified_design.parameter_names == [
        "person[E1]",
        "person[E2]",
        "rater[R2]",
        "item[I2]",
        "step[item=I1,1]",
        "step[item=I2,1]",
    ]

    identified_params = [0.4, -0.1, 0.2, -0.3, 0.5, -0.25]
    identified_pointwise = pointwise_loglikelihood(identified_design, identified_params)
    row2_location = 0.4 - 0.2 - 0.0
    row2_etas = [0.0, row2_location - 0.5, 2row2_location]
    @test identified_pointwise[2] ≈ row2_etas[2] - (maximum(row2_etas) + log(sum(exp.(row2_etas .- maximum(row2_etas)))))
    row3_location = 0.4 - 0.0 - (-0.3)
    row3_etas = [0.0, row3_location - (-0.25), 2row3_location]
    @test identified_pointwise[3] ≈ row3_etas[3] - (maximum(row3_etas) + log(sum(exp.(row3_etas .- maximum(row3_etas)))))

    raw_person = [0.4, -0.1]
    raw_rater = [0.0, 0.2]
    raw_item = [0.0, -0.3]
    raw_steps = [[0.5, -0.5], [-0.25, 0.25]]
    @test identified_pointwise ≈ raw_pcm_pointwise(identified_data, raw_person, raw_rater, raw_item, raw_steps)

    rater_person = coverage_matrix(identified_spec; rows = :rater, columns = :person)
    @test rater_person.row_levels == Any["R1", "R2"]
    @test rater_person.column_levels == Any["E1", "E2"]
    @test rater_person.counts == [2 2; 1 1]
    task_rater = coverage_matrix(identified_data; rows = :task, columns = :rater)
    @test task_rater.row_levels == Any["T1", "T2"]
    @test task_rater.column_levels == Any["R1", "R2"]
    @test task_rater.counts == [2 1; 2 1]
    @test_throws ArgumentError coverage_matrix(data; rows = :task, columns = :rater)

    overlap = rater_overlap(identified_data)
    @test length(overlap) == 1
    @test overlap[1].rater_a == "R1"
    @test overlap[1].rater_b == "R2"
    @test overlap[1].shared_units == 2
    @test overlap[1].jaccard ≈ 2 / 4

    task_overlap = rater_overlap(identified_spec; unit = :person_task)
    @test only(task_overlap).shared_units == 2
    @test_throws ArgumentError rater_overlap(data; unit = :person_task)

    pcm_thresholds = threshold_map_data(identified_design; params = identified_params)
    @test length(pcm_thresholds) == 4
    @test pcm_thresholds[1].parameter_name == "step[item=I1,1]"
    @test pcm_thresholds[1].value == 0.5
    @test pcm_thresholds[2].status === :sum_to_zero_derived
    @test pcm_thresholds[2].value == -0.5
    @test pcm_thresholds[4].value == 0.25

    shifted_person_rater = raw_pcm_pointwise(
        identified_data,
        raw_person .+ 1.3,
        raw_rater .+ 1.3,
        raw_item,
        raw_steps,
    )
    shifted_person_item = raw_pcm_pointwise(
        identified_data,
        raw_person .- 0.7,
        raw_rater,
        raw_item .- 0.7,
        raw_steps,
    )
    shifted_item_steps = raw_pcm_pointwise(
        identified_data,
        raw_person,
        raw_rater,
        [raw_item[1], raw_item[2] + 0.9],
        [raw_steps[1], raw_steps[2] .- 0.9],
    )
    @test identified_pointwise ≈ shifted_person_rater
    @test identified_pointwise ≈ shifted_person_item
    @test identified_pointwise ≈ shifted_item_steps

    rsm_spec = mfrm_spec(identified_data; thresholds = :rating_scale)
    rsm_design = getdesign(rsm_spec)
    @test rsm_design.parameter_names[end] == "step[1]"
    @test count(name -> startswith(name, "step"), rsm_design.parameter_names) == 1
    rsm_params = [0.4, -0.1, 0.2, -0.3, 0.5]
    rsm_pointwise = pointwise_loglikelihood(rsm_design, rsm_params)
    rsm_row3_location = 0.4 - 0.0 - (-0.3)
    rsm_row3_etas = [0.0, rsm_row3_location - 0.5, 2rsm_row3_location]
    @test rsm_pointwise[3] ≈ rsm_row3_etas[3] - test_logsumexp(rsm_row3_etas)

    rsm_thresholds = threshold_map_data(rsm_design; params = rsm_params)
    @test length(rsm_thresholds) == 2
    @test rsm_thresholds[1].item === missing
    @test rsm_thresholds[1].value == 0.5
    @test rsm_thresholds[2].status === :sum_to_zero_derived
    @test rsm_thresholds[2].value == -0.5

    dff_empty = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        group = ["A", "A", "A", "A", "B", "A"],
        score = [0, 1, 2, 1, 0, 2],
    )
    dff_data = FacetData(dff_empty;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
        group = :group)
    plain_dff_report = validate_design(dff_data)
    @test_throws ArgumentError mfrm_spec(
        dff_data;
        thresholds = :partial_credit,
        bias = [(:rater, :group)],
        validation_report = plain_dff_report,
    )
    dff_report = validate_design(dff_data; bias = [(:rater, :group)])
    dff_spec = mfrm_spec(dff_data; thresholds = :partial_credit, validation_report = dff_report)
    @test haskey(dff_spec.validation.dff_counts, (:rater, :group))
    @test dff_spec.validation.dff_counts[(:rater, :group)][("R1", "B")] == 0

    disconnected_same_n = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R1", "R1", "R2", "R2", "R2"],
        item = ["I1", "I1", "I1", "I2", "I2", "I2"],
        score = [0, 1, 2, 0, 1, 2],
    )
    stale_data = FacetData(disconnected_same_n; person = :examinee, rater = :rater, item = :item, score = :score)
    @test_throws ArgumentError mfrm_spec(stale_data; thresholds = :partial_credit, validation_report = validate_design(identified_data))
end

@testset "minimal Bayesian MFRM fitting" begin
    table = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2", "E3", "E3", "E3"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2", "I1", "I2", "I2"],
        score = [0, 1, 2, 1, 0, 2, 1, 2, 0],
    )
    data = FacetData(table; person = :examinee, rater = :rater, item = :item, score = :score)
    spec = mfrm_spec(data; thresholds = :partial_credit)
    design = getdesign(spec)
    prior = MFRMPrior(; person_sd = 1.2, rater_sd = 0.8, item_sd = 0.9, step_sd = 0.7)
    init = zeros(length(design.parameter_names))

    @test logposterior(design, init, prior) ≈ logposterior(spec, init, prior)
    @test isfinite(logposterior(design, init, prior))
    @test_throws ArgumentError MFRMPrior(; person_sd = 0.0)
    @test_throws ArgumentError logposterior(design, [0.0], prior)
    @test_throws ArgumentError fit(design; ndraws = 0)
    @test_throws ArgumentError fit(design; warmup = -1)
    @test_throws ArgumentError fit(design; step_size = 0.0)
    @test_throws ArgumentError fit(design; backend = :stan)

    result = fit(design;
        prior,
        backend = :julia,
        ndraws = 24,
        warmup = 12,
        step_size = 0.04,
        init,
        rng = MersenneTwister(20260618))
    @test result isa MFRMFit
    @test result.design === design
    @test result.prior === prior
    @test size(result.draws) == (24, length(design.parameter_names))
    @test length(result.log_posterior) == 24
    @test all(isfinite, result.log_posterior)
    @test 0.0 <= result.acceptance_rate <= 1.0
    @test result.backend === :julia
    @test result.sampler === :random_walk_metropolis
    @test result.warmup == 12
    @test result.step_size == 0.04

    spec_result = fit(spec;
        prior,
        backend = :julia,
        ndraws = 2,
        warmup = 0,
        step_size = 0.04,
        init,
        rng = MersenneTwister(20260619))
    @test spec_result isa MFRMFit
    @test spec_result.design.parameter_names == design.parameter_names
    @test size(spec_result.draws) == (2, length(design.parameter_names))

    summary = posterior_summary(result)
    @test length(summary) == length(design.parameter_names)
    @test [row.parameter for row in summary] == design.parameter_names
    @test all(row -> isfinite(row.mean), summary)
    @test all(row -> row.lower <= row.median <= row.upper, summary)
    @test_throws ArgumentError posterior_summary(result; lower = 0.6)
    @test_throws ArgumentError posterior_summary(result; upper = 0.4)

    llmat = pointwise_loglikelihood_matrix(result)
    @test size(llmat) == (24, data.n)
    @test llmat[1, :] ≈ pointwise_loglikelihood(design, result.draws[1, :])
    @test pointwise_loglikelihood_matrix(design, result.draws) ≈ llmat
    @test_throws ArgumentError pointwise_loglikelihood_matrix(design, result.draws[:, 1:end-1])

    waic_result = waic(result; draw_indices = [1, 2, 3])
    manual_lppd = [test_logsumexp(@view llmat[1:3, row]) - log(3) for row in 1:data.n]
    manual_p_waic = [test_sample_variance(@view llmat[1:3, row]) for row in 1:data.n]
    manual_elpd = manual_lppd .- manual_p_waic
    manual_waic = -2 .* manual_elpd
    @test waic_result.criterion === :waic
    @test waic_result.n_draws == 3
    @test waic_result.n_observations == data.n
    @test waic_result.pointwise.lppd ≈ manual_lppd
    @test waic_result.pointwise.p_waic ≈ manual_p_waic
    @test waic_result.pointwise.elpd_waic ≈ manual_elpd
    @test waic_result.pointwise.waic ≈ manual_waic
    @test waic_result.lppd ≈ sum(manual_lppd)
    @test waic_result.p_waic ≈ sum(manual_p_waic)
    @test waic_result.elpd_waic ≈ sum(manual_elpd)
    @test waic_result.waic ≈ sum(manual_waic)
    @test waic_result.waic ≈ -2 * waic_result.elpd_waic
    @test waic_result.se_waic ≈ 2 * waic_result.se_elpd_waic
    @test waic_result.high_variance_count == count(>(0.4), manual_p_waic)
    @test waic_result.warning in (:ok, :high_loglik_variance)
    @test waic(design, result.draws[1:3, :]).waic ≈ waic_result.waic
    @test waic(llmat[1:3, :]).waic ≈ waic_result.waic
    @test_throws ArgumentError waic(result; ndraws = 1)
    @test_throws ArgumentError waic(result; ndraws = 2, draw_indices = [1])
    @test_throws ArgumentError waic(design, result.draws[1:3, 1:end-1])
    @test_throws ArgumentError waic(llmat[1:1, :])
    @test_throws ArgumentError waic([0.0 Inf; 1.0 2.0])

    comparison = compare_models(result, spec_result; names = [:main, :short], draw_indices = [1, 2])
    comparison_stats = Dict(
        "main" => waic(result; draw_indices = [1, 2]),
        "short" => waic(spec_result; draw_indices = [1, 2]),
    )
    best_stat = comparison_stats[comparison[1].model]
    @test length(comparison) == 2
    @test [row.rank for row in comparison] == [1, 2]
    @test comparison[1].elpd_waic >= comparison[2].elpd_waic
    @test comparison[1].elpd_difference ≈ 0.0
    @test comparison[1].waic_difference ≈ 0.0
    @test comparison[2].elpd_difference <= 0
    @test comparison[2].waic_difference >= 0
    @test all(row -> row.criterion === :waic, comparison)
    @test all(row -> row.n_observations == data.n, comparison)
    for row in comparison
        stat = comparison_stats[row.model]
        pointwise_difference = stat.pointwise.elpd_waic .- best_stat.pointwise.elpd_waic
        @test row.elpd_waic ≈ stat.elpd_waic
        @test row.elpd_difference ≈ stat.elpd_waic - best_stat.elpd_waic
        @test row.se_elpd_difference ≈ sqrt(length(pointwise_difference) * test_sample_variance(pointwise_difference))
        @test row.waic ≈ stat.waic
        @test row.waic_difference ≈ stat.waic - best_stat.waic
        @test row.p_waic ≈ stat.p_waic
        @test row.lppd ≈ stat.lppd
        @test row.high_variance_count == stat.high_variance_count
        @test row.warning === stat.warning
    end
    pair_comparison = compare_models(:main => result, :short => spec_result; draw_indices = [1, 2])
    @test [row.model for row in pair_comparison] == [row.model for row in comparison]
    @test [row.waic for row in pair_comparison] ≈ [row.waic for row in comparison]
    @test_throws ArgumentError compare_models(result; names = [:single])
    @test_throws ArgumentError compare_models(result, spec_result; names = [:only])
    @test_throws ArgumentError compare_models(result, spec_result; names = [:dup, :dup])
    @test_throws ArgumentError compare_models(result, spec_result; criterion = :loo)
    @test_throws ArgumentError compare_models(:bad => design, :good => result)

    probabilities = zeros(Float64, length(data.category_levels))
    draw_params = @view result.draws[1, :]
    draw_loglik = pointwise_loglikelihood(design, draw_params)
    for row in 1:data.n
        BayesianMGMFRM._category_probabilities!(probabilities, design, draw_params, row)
        @test sum(probabilities) ≈ 1.0
        @test log(probabilities[data.category[row]]) ≈ draw_loglik[row]
    end

    prob_array = predictive_probabilities(result; draw_indices = [1, 2])
    @test size(prob_array) == (2, data.n, length(data.category_levels))
    @test predictive_probabilities(design, result.draws[1:2, :]) ≈ prob_array
    @test all(draw -> all(row -> sum(prob_array[draw, row, :]) ≈ 1.0, 1:data.n), 1:2)
    @test all(row -> log(prob_array[1, row, data.category[row]]) ≈ llmat[1, row], 1:data.n)
    @test_throws ArgumentError predictive_probabilities(result; ndraws = 0)
    @test_throws ArgumentError predictive_probabilities(result; ndraws = 2, draw_indices = [1])
    @test_throws ArgumentError predictive_probabilities(design, result.draws[:, 1:end-1])

    expected = expected_scores(result; draw_indices = [1, 2])
    variances = predictive_variances(result; draw_indices = [1, 2])
    residuals = predictive_residuals(result; draw_indices = [1, 2])
    @test size(expected) == (2, data.n)
    @test expected_scores(design, result.draws[1:2, :]) ≈ expected
    @test size(variances) == (2, data.n)
    @test predictive_variances(design, result.draws[1:2, :]) ≈ variances
    @test size(residuals) == (2, data.n)
    @test predictive_residuals(design, result.draws[1:2, :]) ≈ residuals
    for draw in 1:2, row in 1:data.n
        manual_mean = sum(data.category_levels[k] * prob_array[draw, row, k] for k in eachindex(data.category_levels))
        manual_second = sum(data.category_levels[k]^2 * prob_array[draw, row, k] for k in eachindex(data.category_levels))
        @test expected[draw, row] ≈ manual_mean
        @test variances[draw, row] ≈ manual_second - manual_mean^2 atol = 1e-12
        @test residuals[draw, row] ≈ data.score[row] - expected[draw, row]
    end
    @test all(>=(0.0), variances)
    @test_throws ArgumentError expected_scores(result; ndraws = 0)
    @test_throws ArgumentError predictive_variances(result; ndraws = 0)
    @test_throws ArgumentError predictive_residuals(result; ndraws = 0)

    rater_fit = fit_stats(result; by = :rater, draw_indices = [1, 2], interval = 0.8)
    @test length(rater_fit) == length(data.rater_levels)
    @test [row.level for row in rater_fit] == data.rater_levels
    @test all(row -> row.facet === :rater, rater_fit)
    @test all(row -> row.method === :posterior, rater_fit)
    @test all(row -> row.n_obs == count(==(findfirst(==(row.level), data.rater_levels)), data.rater), rater_fit)
    @test all(row -> row.lower_probability ≈ 0.1, rater_fit)
    @test all(row -> row.upper_probability ≈ 0.9, rater_fit)
    @test all(row -> row.flag in (:ok, :tiny_predictive_variance), rater_fit)
    @test all(row -> row.infit_lower <= row.infit_median <= row.infit_upper, rater_fit)
    @test all(row -> row.outfit_lower <= row.outfit_median <= row.outfit_upper, rater_fit)
    @test fit_stats(design, result.draws[1:2, :]; by = :rater, interval = 0.8) == rater_fit

    item_fit = fit_stats(result; by = :item, draw_indices = [1, 2])
    @test [row.level for row in item_fit] == data.item_levels
    category_fit = fit_stats(result; by = :category, draw_indices = [1, 2])
    @test [row.level for row in category_fit] == data.category_levels
    sparse_fit = fit_stats(result; by = :rater, draw_indices = [1, 2], min_n = data.n + 1)
    @test all(row -> row.flag === :below_min_n, sparse_fit)
    @test all(row -> isnan(row.infit_mean) && isnan(row.outfit_mean), sparse_fit)
    @test_throws ArgumentError fit_stats(result; by = :unknown)
    @test_throws ArgumentError fit_stats(result; method = :plugin)
    @test_throws ArgumentError fit_stats(result; interval = 1.0)
    @test_throws ArgumentError fit_stats(result; min_n = 0)

    prior_replicated = prior_predict(design; prior, ndraws = 5, rng = MersenneTwister(2234))
    @test size(prior_replicated) == (5, data.n)
    @test all(score -> score in data.category_levels, prior_replicated)
    prior_replicated_spec = prior_predict(spec; prior, ndraws = 2, rng = MersenneTwister(2235))
    @test size(prior_replicated_spec) == (2, data.n)
    @test_throws ArgumentError prior_predict(design; prior, ndraws = 0)

    prior_ppc = prior_predictive_check(design; prior, ndraws = 6, rng = MersenneTwister(6678))
    @test size(prior_ppc.replicated_scores) == (6, data.n)
    @test size(prior_ppc.parameter_draws) == (6, length(design.parameter_names))
    @test all(isfinite, prior_ppc.parameter_draws)
    @test prior_ppc.category_levels == data.category_levels
    @test prior_ppc.rater_levels == data.rater_levels
    @test prior_ppc.item_levels == data.item_levels
    @test length(prior_ppc.observed.category_proportions) == length(data.category_levels)
    @test size(prior_ppc.replicated.category_proportions) == (6, length(data.category_levels))
    @test all(rep -> sum(prior_ppc.replicated.category_proportions[rep, :]) ≈ 1.0,
        axes(prior_ppc.replicated.category_proportions, 1))
    prior_ppc_spec = prior_predictive_check(spec; prior, ndraws = 2, rng = MersenneTwister(6679))
    @test size(prior_ppc_spec.replicated_scores) == (2, data.n)
    @test_throws ArgumentError prior_predictive_check(design; prior, ndraws = 0)

    prior_ppc_summary = predictive_check_summary(prior_ppc; interval = 0.8)
    expected_n_summary_rows = 1 + length(data.category_levels) + length(data.rater_levels) + length(data.item_levels)
    @test length(prior_ppc_summary) == expected_n_summary_rows
    @test prior_ppc_summary[1].statistic === :mean_score
    @test prior_ppc_summary[1].level === missing
    @test prior_ppc_summary[1].observed ≈ prior_ppc.observed.mean_score
    @test prior_ppc_summary[1].replicated_mean ≈ sum(prior_ppc.replicated.mean_score) / 6
    @test prior_ppc_summary[1].lower_probability ≈ 0.1
    @test prior_ppc_summary[1].upper_probability ≈ 0.9
    @test prior_ppc_summary[1].n_replicates == 6
    @test prior_ppc_summary[1].lower_tail_probability ≈
        count(<=(prior_ppc.observed.mean_score), prior_ppc.replicated.mean_score) / 6
    @test prior_ppc_summary[1].upper_tail_probability ≈
        count(>=(prior_ppc.observed.mean_score), prior_ppc.replicated.mean_score) / 6
    @test prior_ppc_summary[1].two_sided_tail_probability ≈
        min(1.0, 2 * min(prior_ppc_summary[1].lower_tail_probability,
                prior_ppc_summary[1].upper_tail_probability))
    @test all(row -> row.flag in (:ok, :outside_interval), prior_ppc_summary)
    @test any(row -> row.statistic === :category_proportion && row.level == first(data.category_levels),
        prior_ppc_summary)
    @test_throws ArgumentError predictive_check_summary(prior_ppc; interval = 1.0)
    @test_throws ArgumentError predictive_check_summary((observed = prior_ppc.observed,))

    replicated = posterior_predict(result; ndraws = 5, rng = MersenneTwister(1234))
    @test size(replicated) == (5, data.n)
    @test all(score -> score in data.category_levels, replicated)
    replicated_by_index = posterior_predict(result; draw_indices = [1, 2], rng = MersenneTwister(1235))
    @test size(replicated_by_index) == (2, data.n)
    @test_throws ArgumentError posterior_predict(result; ndraws = 0)
    @test_throws ArgumentError posterior_predict(result; ndraws = 2, draw_indices = [1])
    @test_throws ArgumentError posterior_predict(result; draw_indices = [0])

    ppc = posterior_predictive_check(result; ndraws = 6, rng = MersenneTwister(5678))
    @test size(ppc.replicated_scores) == (6, data.n)
    @test length(ppc.observed.category_proportions) == length(data.category_levels)
    @test sum(ppc.observed.category_proportions) ≈ 1.0
    @test size(ppc.replicated.category_proportions) == (6, length(data.category_levels))
    @test all(rep -> sum(ppc.replicated.category_proportions[rep, :]) ≈ 1.0,
        axes(ppc.replicated.category_proportions, 1))
    @test size(ppc.replicated.rater_mean) == (6, length(data.rater_levels))
    @test size(ppc.replicated.item_mean) == (6, length(data.item_levels))
    @test ppc.category_levels == data.category_levels
    @test ppc.rater_levels == data.rater_levels
    @test ppc.item_levels == data.item_levels
    ppc_summary = predictive_check_summary(ppc; interval = 0.8)
    @test length(ppc_summary) == expected_n_summary_rows
    @test [row.statistic for row in ppc_summary[1:4]] ==
        [:mean_score, :category_proportion, :category_proportion, :category_proportion]
    @test ppc_summary[1].observed ≈ ppc.observed.mean_score
    @test ppc_summary[1].replicated_lower <= ppc_summary[1].replicated_median <=
        ppc_summary[1].replicated_upper
    @test all(row -> row.n_replicates == 6, ppc_summary)
    ppc_by_index = posterior_predictive_check(result; draw_indices = [1, 2], rng = MersenneTwister(5679))
    @test size(ppc_by_index.replicated_scores) == (2, data.n)
    @test ppc_by_index.draw_indices == [1, 2]
    @test_throws ArgumentError posterior_predictive_check(result; ndraws = 0)
    @test_throws ArgumentError posterior_predictive_check(result; ndraws = 2, draw_indices = [1])
end

@testset "scalar validation analytic gradient" begin
    fixture_path = joinpath(@__DIR__, "fixtures", "scalar_validation_known_value.json")
    stan_model_path = joinpath(@__DIR__, "stan", "scalar_gmfrm.stan")
    @test isfile(stan_model_path)
    @test occursin("categorical_logit", read(stan_model_path, String))
    fixture = JSON3.read(read(fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.scalar_validation_known_value.v1"

    fd = scalar_validation_fixture_data(fixture)
    x = Vector{Float64}(fixture[:x])
    expected_lp = Float64(fixture[:log_density])
    expected_gradient = Vector{Float64}(fixture[:gradient])
    fixture_tol = Float64(fixture[:tolerance])
    @test length(x) == scalar_validation_num_params(fd)

    logp = z -> scalar_validation_logposterior(z, fd)

    facet_data = FacetData((
            examinee = ["E1", "E1", "E2", "E2", "E3", "E3"],
            rater = ["R1", "R2", "R1", "R2", "R1", "R2"],
            item = ["I1", "I1", "I1", "I1", "I1", "I1"],
            score = [0, 1, 2, 0, 1, 2],
        );
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score)
    facet_fd = ScalarValidationData(facet_data)
    @test facet_fd.X == facet_data.category
    @test facet_fd.examinee == facet_data.person
    @test facet_fd.rater == facet_data.rater
    @test (facet_fd.J, facet_fd.R, facet_fd.K, facet_fd.N) ==
        (3, 2, 3, length(facet_data))

    multi_item_data = FacetData((
            examinee = ["E1", "E1", "E2", "E2"],
            rater = ["R1", "R2", "R1", "R2"],
            item = ["I1", "I2", "I1", "I2"],
            score = [0, 1, 1, 0],
        );
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score)
    @test_throws ArgumentError ScalarValidationData(multi_item_data)

    lp, g_analytic = scalar_validation_logposterior_and_gradient(x, fd)
    @test lp ≈ logp(x) atol = 1e-10 rtol = 1e-10
    @test lp ≈ expected_lp atol = fixture_tol rtol = fixture_tol
    @test maximum(abs.(g_analytic .- expected_gradient)) < fixture_tol
    o = scalar_validation_offsets(fd)

    stan_fixture_path = joinpath(@__DIR__, "fixtures", "scalar_validation_stan_logdensity.json")
    stan_fixture = JSON3.read(read(stan_fixture_path, String))
    @test String(stan_fixture[:schema]) == "bayesianmgmfrm.scalar_stan_logdensity.v1"
    @test Bool(stan_fixture[:propto]) == false
    @test Bool(stan_fixture[:jacobian]) == true
    @test String(stan_fixture[:stan_model]) == "test/stan/scalar_gmfrm.stan"
    @test String(stan_fixture[:stan_model_sha256]) == file_sha256(stan_model_path)
    @test String(stan_fixture[:known_fixture_sha256]) == file_sha256(fixture_path)
    @test Vector{Float64}(stan_fixture[:x]) == x
    @test Vector{String}(stan_fixture[:stan_parameter_order]) == [
        "theta.1.1",
        "theta.1.2",
        "theta.1.3",
        "theta.1.4",
        "theta.1.5",
        "alpha_i.1.1",
        "beta_i.1",
        "log_alpha_r.1",
        "log_alpha_r.2",
        "log_alpha_r.3",
        "beta_r.1",
        "beta_r.2",
        "beta_r.3",
        "beta_ik.1.1",
        "beta_ik.2.1",
        "beta_ik.3.1",
    ]
    stan_tol = Float64(stan_fixture[:tolerance])
    stan_lp = Float64(stan_fixture[:stan_log_density])
    stan_gradient = Vector{Float64}(stan_fixture[:stan_gradient])
    @test lp ≈ stan_lp atol = stan_tol rtol = stan_tol
    @test maximum(abs.(g_analytic .- stan_gradient)) < stan_tol
    @test LogDensityProblems.logdensity(ScalarValidationLogDensity(fd), x) ≈ lp atol = 1e-10 rtol = 1e-10

    decoded = scalar_validation_decode(x, fd)
    @test size(decoded.theta) == (1, fd.J)
    @test sum(log.(decoded.trans_alpha_r)) ≈ 0.0 atol = 1e-12
    @test sum(decoded.trans_beta_r) ≈ 0.0 atol = 1e-12
    @test decoded.category_prm[1][end] ≈ 0.0 atol = 1e-12

    Qr = zerosum_basis_fast(fd.R)
    Qs = zerosum_basis_fast(fd.K - 1)
    @test size(Qr) == (fd.R, fd.R - 1)
    @test size(Qs) == (fd.K - 1, fd.K - 2)
    @test maximum(abs.(sum(Qr; dims = 1))) < 1e-12
    @test maximum(abs.(sum(Qs; dims = 1))) < 1e-12
    @test Qr' * Qr ≈ Matrix{Float64}(I, fd.R - 1, fd.R - 1) atol = 1e-12 rtol = 1e-12
    @test Qs' * Qs ≈ Matrix{Float64}(I, fd.K - 2, fd.K - 2) atol = 1e-12 rtol = 1e-12

    @test scalar_validation_contrast_num_params(fd) == scalar_validation_num_params(fd)
    contrast_lp = scalar_validation_logposterior_contrast(x, fd, Qr, Qs)
    contrast_target = ScalarValidationContrastLogDensity(fd, Qr, Qs)
    @test isfinite(contrast_lp)
    @test LogDensityProblems.logdensity(contrast_target, x) ≈ contrast_lp atol = 1e-10 rtol = 1e-10
    contrast_decoded = scalar_validation_decode_contrast(x, fd)
    @test sum(log.(contrast_decoded.trans_alpha_r)) ≈ 0.0 atol = 1e-12
    @test sum(contrast_decoded.trans_beta_r) ≈ 0.0 atol = 1e-12
    @test contrast_decoded.category_prm[1][end] ≈ 0.0 atol = 1e-12

    x_contrast = copy(x)
    raw_log_alpha_r = log.(decoded.trans_alpha_r)
    raw_category_est = diff(decoded.category_prm[1])
    x_contrast[o.o_log_alpha_r:(o.o_log_alpha_r + fd.R - 2)] .= Qr' * raw_log_alpha_r
    x_contrast[o.o_beta_r:(o.o_beta_r + fd.R - 2)] .= Qr' * decoded.trans_beta_r
    x_contrast[o.o_beta_ik:(o.o_beta_ik + fd.K - 3)] .= Qs' * raw_category_est
    matched_contrast_decoded = scalar_validation_decode_contrast(x_contrast, fd)
    @test matched_contrast_decoded.theta ≈ decoded.theta atol = 1e-12 rtol = 1e-12
    @test matched_contrast_decoded.alpha_i ≈ decoded.alpha_i atol = 1e-12 rtol = 1e-12
    @test matched_contrast_decoded.beta_i ≈ decoded.beta_i atol = 1e-12 rtol = 1e-12
    @test matched_contrast_decoded.trans_alpha_r ≈ decoded.trans_alpha_r atol = 1e-12 rtol = 1e-12
    @test matched_contrast_decoded.trans_beta_r ≈ decoded.trans_beta_r atol = 1e-12 rtol = 1e-12
    @test matched_contrast_decoded.category_prm[1] ≈ decoded.category_prm[1] atol = 1e-12 rtol = 1e-12
    @test scalar_validation_logposterior_contrast(x_contrast, fd, Qr, Qs) ≈ lp atol = 1e-10 rtol = 1e-10

    g_reverse = ReverseDiff.gradient(logp, x)
    @test maximum(abs.(g_analytic .- g_reverse)) < 1e-8

    g_forward = ForwardDiff.gradient(logp, x)
    @test maximum(abs.(g_analytic .- g_forward)) < 1e-8

    coords = unique(round.(Int, range(1, length(x), length = min(length(x), 12))))
    for i in coords
        @test g_analytic[i] ≈ central_difference(logp, x, i) atol = 1e-4 rtol = 1e-4
    end

    x_extreme = zeros(scalar_validation_num_params(fd))
    x_extreme[o.o_theta] = 10.0
    x_extreme[o.o_log_alpha_i] = 4.0
    lp_extreme = scalar_validation_logposterior(x_extreme, fd)
    lp_grad_extreme, _ = scalar_validation_logposterior_and_gradient(x_extreme, fd)
    analytic_target = ScalarValidationAnalyticLogDensity(fd)
    @test isfinite(lp_extreme)
    @test lp_extreme ≈ lp_grad_extreme atol = 1e-8 rtol = 1e-8
    @test LogDensityProblems.logdensity(analytic_target, x_extreme) ≈
        first(LogDensityProblems.logdensity_and_gradient(analytic_target, x_extreme)) atol = 1e-8 rtol = 1e-8

    external_stan_fixture = get(ENV, "MFRM_STAN_LOGDENSITY_FIXTURE", "")
    if !isempty(external_stan_fixture)
        fixture = JSON3.read(read(external_stan_fixture, String))
        fd_stan = scalar_validation_fixture_data(fixture)
        x_stan = Vector{Float64}(fixture[:x])
        lp_stan = Float64(fixture[:stan_log_density])
        tol = haskey(fixture, :tolerance) ? Float64(fixture[:tolerance]) : 1e-6
        @test length(x_stan) == scalar_validation_num_params(fd_stan)
        lp_julia, g_julia = scalar_validation_logposterior_and_gradient(x_stan, fd_stan)
        @test lp_julia ≈ lp_stan atol = tol rtol = tol
        if haskey(fixture, :stan_gradient)
            g_stan = Vector{Float64}(fixture[:stan_gradient])
            @test maximum(abs.(g_julia .- g_stan)) < max(tol, 1e-6)
        end
    end
end
