#!/usr/bin/env julia

module MFRMAnchorRecoveryPilot

using Dates
using Random
using Statistics

using BayesianMGMFRM

include(joinpath(@__DIR__, "local_json.jl"))

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT = joinpath(ROOT, "artifacts", "mfrm_anchor_recovery_pilot.json")
const PROTOCOL = (;
    replications = 2,
    topologies = (:full, :sparse, :nested_link_early,
        :nested_link_distributed),
    dgp_conditions = (:well_specified, :rater_extremity_misfit),
    persons = 20,
    raters = 4,
    items = 4,
    categories = 4,
    thresholds = :partial_credit,
    sampler = (;
        backend = :advancedhmc,
        chains = 4,
        warmup = 200,
        draws = 200,
        step_size = 0.03,
        target_accept = 0.9,
        max_depth = 8,
        metric = :diagonal,
        ad_backend = :ForwardDiff,
        init_jitter = 0.02,
        initialization = :known_truth_or_anchor_projection_plus_jitter,
    ),
    diagnostic_thresholds = (;
        max_rank_normalized_rhat = 1.05,
        min_bulk_ess = 200.0,
        min_tail_ess = 200.0,
    ),
    pairing = :same_training_and_heldout_responses_within_topology_replication_condition,
    topology_pairing =
        :same_base_nested_events_and_event_keyed_uniforms_composite_link_placement_stress,
    prediction_target = :same_design_true_category_probabilities,
    heldout_prediction = :independent_responses_on_same_facet_design,
    heldout_new_facet_levels = false,
    heldout_new_facet_level_status =
        :unsupported_without_hierarchical_facet_distribution,
    independent_dgp_implementation = false,
    nested_common_linking_target_fraction = 0.10,
    rater_misfit = (;
        rater = "R4",
        mechanism = :quadratic_category_log_weight,
        coefficient = 0.35,
        represented_by_fitted_severity = false,
    ),
)

function stress_data(topology::Symbol)
    topology in PROTOCOL.topologies || throw(ArgumentError(
        "unknown topology: $topology",
    ))
    events = if topology === :full
        [(person, rater, item)
            for person in 1:PROTOCOL.persons
            for rater in 1:PROTOCOL.raters
            for item in 1:PROTOCOL.items]
    elseif topology === :sparse
        [(person, rater, item)
            for person in 1:PROTOCOL.persons
            for rater in ((mod(person - 1, PROTOCOL.raters) + 1),
                (mod(person, PROTOCOL.raters) + 1))
            for item in 1:PROTOCOL.items]
    else
        targets = [(person, item)
            for person in 1:PROTOCOL.persons
            for item in 1:PROTOCOL.items]
        n_linking = round(Int,
            PROTOCOL.nested_common_linking_target_fraction * length(targets))
        linking_indices = topology === :nested_link_early ?
            collect(1:n_linking) :
            unique(round.(Int, range(1, length(targets); length = n_linking)))
        length(linking_indices) == n_linking || error(
            "linking placement did not preserve the requested count",
        )
        linking_set = Set(linking_indices)
        events = Tuple{Int,Int,Int}[]
        persons_per_rater = cld(PROTOCOL.persons, PROTOCOL.raters)
        for (target_index, (person, item)) in pairs(targets)
            primary = min(cld(person, persons_per_rater), PROTOCOL.raters)
            raters = target_index in linking_set ?
                (1:PROTOCOL.raters) : (primary:primary)
            append!(events, [(person, rater, item) for rater in raters])
        end
        events
    end
    return FacetData((;
        person = ["P$(lpad(row[1], 2, '0'))" for row in events],
        rater = ["R$(row[2])" for row in events],
        item = ["I$(row[3])" for row in events],
        score = [mod(row[1] + 2row[2] + 3row[3], PROTOCOL.categories)
            for row in events],
    );
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        category_levels = 0:(PROTOCOL.categories - 1))
end

function topology_summary(topology::Symbol, data, truth)
    raters_by_target = Dict{Tuple{Int,Int},Set{Int}}()
    for row in 1:data.n
        target = (data.person[row], data.item[row])
        push!(get!(raters_by_target, target, Set{Int}()), data.rater[row])
    end
    common_targets = [target for (target, raters) in raters_by_target
        if length(raters) == PROTOCOL.raters]
    common_abilities = [truth.person[target[1]] for target in common_targets]
    linking = anchor_linking_summary(data;
        unit = :person_item,
        min_shared_units = 1)
    return (;
        topology,
        n_observations = data.n,
        n_targets = length(raters_by_target),
        n_all_rater_common_targets = length(common_targets),
        all_rater_common_target_fraction =
            length(common_targets) / length(raters_by_target),
        common_target_ability_range = isempty(common_abilities) ? missing :
            maximum(common_abilities) - minimum(common_abilities),
        common_target_item_counts = [count(target -> target[2] == item,
            common_targets) for item in 1:PROTOCOL.items],
        rater_rating_counts = [count(==(rater), data.rater)
            for rater in 1:PROTOCOL.raters],
        nested_link_contrast_role = topology in
            (:nested_link_early, :nested_link_distributed) ?
            :composite_ability_range_item_mix_and_rater_load_stress :
            :not_applicable,
        rater_linking_status = linking.rater_linking_status,
        minimum_shared_person_item_units = linking.minimum_shared_units,
    )
end

function truth_values()
    return (;
        person = collect(range(-1.2, 1.2; length = PROTOCOL.persons)),
        rater = [-0.75, -0.25, 0.25, 0.75],
        item = [-0.60, -0.20, 0.20, 0.60],
        thresholds = repeat([-0.25, 0.15], PROTOCOL.items),
    )
end

function encoded_truth(data, anchors, truth)
    design = getdesign(mfrm_spec(data;
        thresholds = PROTOCOL.thresholds,
        anchors))
    fixed = BayesianMGMFRM._stable_hard_anchor_map(design)
    rater_shifts = [value - truth.rater[index]
        for (index, value) in sort(collect(fixed[:rater]))]
    item_shifts = [value - truth.item[index]
        for (index, value) in sort(collect(fixed[:item]))]
    rater_shift = isempty(rater_shifts) ? -truth.rater[1] : first(rater_shifts)
    item_shift = isempty(item_shifts) ? -truth.item[1] : first(item_shifts)
    free_raters = isempty(fixed[:rater]) ? (2:length(truth.rater)) :
        [index for index in eachindex(truth.rater)
            if !haskey(fixed[:rater], index)]
    free_items = isempty(fixed[:item]) ? (2:length(truth.item)) :
        [index for index in eachindex(truth.item)
            if !haskey(fixed[:item], index)]
    params = zeros(length(design.parameter_names))
    params[design.blocks[:person]] .= truth.person .+ rater_shift .+ item_shift
    params[design.blocks[:rater]] .= truth.rater[free_raters] .+ rater_shift
    params[design.blocks[:item]] .= truth.item[free_items] .+ item_shift
    params[design.blocks[:thresholds]] .= truth.thresholds
    representable = all(shift -> shift ≈ rater_shift, rater_shifts) &&
        all(shift -> shift ≈ item_shift, item_shifts)
    return (; design, params, representable)
end

function condition_probabilities(base, data, condition::Symbol)
    condition === :well_specified && return copy(base)
    condition === :rater_extremity_misfit || throw(ArgumentError(
        "unknown DGP condition: $condition",
    ))
    out = copy(base)
    center = (size(out, 2) + 1) / 2
    coefficient = PROTOCOL.rater_misfit.coefficient
    target_rater = only(findall(==(PROTOCOL.rater_misfit.rater),
        data.rater_levels))
    for row in axes(out, 1)
        data.rater[row] == target_rater || continue
        weights = [out[row, category] *
            exp(coefficient * (category - center)^2)
            for category in axes(out, 2)]
        out[row, :] .= weights ./ sum(weights)
    end
    return out
end

function response_uniforms(data, seed::Integer)
    return [rand(MersenneTwister(seed +
        100_000_000 * data.person[row] +
        100_000 * data.rater[row] +
        100 * data.item[row])) for row in 1:data.n]
end

function sample_scores(probabilities, category_levels, uniforms)
    length(uniforms) == size(probabilities, 1) || throw(DimensionMismatch(
        "response uniforms must match probability rows",
    ))
    scores = Int[]
    for row in axes(probabilities, 1)
        category = clamp(searchsortedfirst(
            cumsum(probabilities[row, :]),
            uniforms[row],
        ), 1, size(probabilities, 2))
        push!(scores, category_levels[category])
    end
    return scores
end

function data_with_scores(data, scores)
    return FacetData((;
        person = [data.person_levels[index] for index in data.person],
        rater = [data.rater_levels[index] for index in data.rater],
        item = [data.item_levels[index] for index in data.item],
        score = scores,
    );
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        category_levels = data.category_levels)
end

function response_log_loss(probabilities, scores, category_levels)
    category_index = Dict(level => index
        for (index, level) in pairs(category_levels))
    return -mean(log(probabilities[row, category_index[scores[row]]])
        for row in eachindex(scores))
end

hard_anchor(block, level, value) = (; block, level, value, type = :hard)

function anchor_regimes(truth)
    single_truth = [
        hard_anchor(:rater, "R1", truth.rater[1]),
        hard_anchor(:item, "I1", truth.item[1]),
    ]
    single_shifted = [
        hard_anchor(:rater, "R1", truth.rater[1] + 0.4),
        hard_anchor(:item, "I1", truth.item[1] - 0.3),
    ]
    clean = [
        hard_anchor(:rater, "R1", truth.rater[1]),
        hard_anchor(:rater, "R4", truth.rater[4]),
        hard_anchor(:item, "I1", truth.item[1]),
        hard_anchor(:item, "I4", truth.item[4]),
    ]
    contaminated = [
        clean[1],
        hard_anchor(:rater, "R4", truth.rater[4] + 0.4),
        clean[3],
        hard_anchor(:item, "I4", truth.item[4] - 0.3),
    ]
    clean_interior = [
        hard_anchor(:rater, "R2", truth.rater[2]),
        hard_anchor(:rater, "R3", truth.rater[3]),
        hard_anchor(:item, "I2", truth.item[2]),
        hard_anchor(:item, "I3", truth.item[3]),
    ]
    return (
        (; name = :single_truth, anchors = single_truth),
        (; name = :single_shifted, anchors = single_shifted),
        (; name = :clean_multi, anchors = clean),
        (; name = :clean_interior, anchors = clean_interior),
        (; name = :contaminated_multi, anchors = contaminated),
    )
end

function facet_contrast(fitted, block::Symbol, first_index::Int, last_index::Int)
    return [
        BayesianMGMFRM._stable_facet_value(
            fitted.design, view(fitted.draws, draw, :), block, last_index) -
        BayesianMGMFRM._stable_facet_value(
            fitted.design, view(fitted.draws, draw, :), block, first_index)
        for draw in axes(fitted.draws, 1)
    ]
end

function fit_row(topology::Symbol, replication::Int, condition::Symbol,
        regime, truth, simulated, true_probabilities, heldout_scores,
        topology_index::Int, condition_index::Int, regime_index::Int)
    candidate = encoded_truth(simulated, regime.anchors, truth)
    sampler_seed = 20261005 + 10_000topology_index +
        1_000replication + 100condition_index + regime_index
    sampler = PROTOCOL.sampler
    elapsed_seconds = @elapsed fitted = fit(candidate.design;
        backend = sampler.backend,
        ndraws = sampler.draws,
        warmup = sampler.warmup,
        chains = sampler.chains,
        step_size = sampler.step_size,
        target_accept = sampler.target_accept,
        max_depth = sampler.max_depth,
        metric = sampler.metric,
        ad_backend = sampler.ad_backend,
        init = candidate.params,
        init_jitter = sampler.init_jitter,
        seed = sampler_seed,
        progress = false)
    thresholds = PROTOCOL.diagnostic_thresholds
    diagnostic = diagnostics(fitted;
        split_chains = true,
        rhat_threshold = thresholds.max_rank_normalized_rhat,
        ess_threshold = min(thresholds.min_bulk_ess, thresholds.min_tail_ess)).summary
    posterior_probabilities = dropdims(mean(
        predictive_probabilities(fitted);
        dims = 1,
    ); dims = 1)
    log_score_regret = mean([
        sum(true_probabilities[row, :] .* log.(
            true_probabilities[row, :] ./ posterior_probabilities[row, :]))
        for row in axes(true_probabilities, 1)
    ])
    rater_contrast = facet_contrast(fitted, :rater, 1, PROTOCOL.raters)
    item_contrast = facet_contrast(fitted, :item, 1, PROTOCOL.items)
    recovery = condition === :well_specified && candidate.representable ?
        parameter_recovery_summary(fitted, candidate.params;
            interval = 0.9, by = :block) : NamedTuple[]
    return (;
        topology,
        replication,
        condition,
        regime = regime.name,
        n_observations = simulated.n,
        simulation_seed = 10_000_000_000 + 10replication + condition_index,
        heldout_seed = 20_000_000_000 + 10replication + condition_index,
        sampler_seed,
        elapsed_seconds,
        anchor_contract_representable = candidate.representable,
        dgp_in_fitted_model_family = condition === :well_specified,
        diagnostics_passed = diagnostic.passed,
        max_rank_normalized_rhat = diagnostic.max_rank_normalized_rhat,
        min_bulk_ess = diagnostic.min_bulk_ess,
        min_tail_ess = diagnostic.min_tail_ess,
        n_divergences = diagnostic.n_divergences,
        n_max_treedepth = diagnostic.n_max_treedepth,
        e_bfmi = diagnostic.e_bfmi,
        log_score_regret,
        heldout_log_loss = response_log_loss(
            posterior_probabilities,
            heldout_scores,
            simulated.category_levels,
        ),
        oracle_heldout_log_loss = response_log_loss(
            true_probabilities,
            heldout_scores,
            simulated.category_levels,
        ),
        rater_contrast_mean = mean(rater_contrast),
        rater_contrast_sd = std(rater_contrast),
        rater_contrast_truth = truth.rater[end] - truth.rater[1],
        item_contrast_mean = mean(item_contrast),
        item_contrast_sd = std(item_contrast),
        item_contrast_truth = truth.item[end] - truth.item[1],
        recovery = [(;
            block = recovery_row.group,
            mean_absolute_error = recovery_row.mean_absolute_error,
            coverage_rate = recovery_row.coverage_rate,
        ) for recovery_row in recovery],
    )
end

function run_pilot()
    truth = truth_values()
    regimes = anchor_regimes(truth)
    rows = NamedTuple[]
    topology_rows = NamedTuple[]
    for (topology_index, topology) in pairs(PROTOCOL.topologies)
        template = stress_data(topology)
        push!(topology_rows, topology_summary(topology, template, truth))
        oracle = encoded_truth(template, NamedTuple[], truth)
        base_probabilities = dropdims(predictive_probabilities(
            oracle.design,
            reshape(oracle.params, 1, :),
        ); dims = 1)
        for replication in 1:PROTOCOL.replications
            for (condition_index, condition) in pairs(PROTOCOL.dgp_conditions)
                true_probabilities = condition_probabilities(
                    base_probabilities,
                    template,
                    condition,
                )
                simulation_seed =
                    10_000_000_000 + 10replication + condition_index
                heldout_seed =
                    20_000_000_000 + 10replication + condition_index
                simulated_scores = sample_scores(
                    true_probabilities,
                    template.category_levels,
                    response_uniforms(template, simulation_seed),
                )
                heldout_scores = sample_scores(
                    true_probabilities,
                    template.category_levels,
                    response_uniforms(template, heldout_seed),
                )
                simulated = data_with_scores(template, simulated_scores)
                for (regime_index, regime) in pairs(regimes)
                    row = fit_row(topology, replication, condition,
                        regime, truth, simulated, true_probabilities,
                        heldout_scores, topology_index, condition_index,
                        regime_index)
                    push!(rows, row)
                    println((;
                        row.topology,
                        row.replication,
                        row.condition,
                        row.regime,
                        row.diagnostics_passed,
                        row.log_score_regret,
                        row.heldout_log_loss,
                        row.elapsed_seconds,
                    ))
                end
            end
        end
    end
    paired_rows = [(;
        topology,
        replication,
        condition,
        clean_log_score_regret = only(row.log_score_regret for row in rows
            if row.topology === topology && row.replication == replication &&
                row.condition === condition &&
                row.regime === :clean_multi),
        contaminated_log_score_regret = only(row.log_score_regret for row in rows
            if row.topology === topology && row.replication == replication &&
                row.condition === condition &&
                row.regime === :contaminated_multi),
        clean_heldout_log_loss = only(row.heldout_log_loss for row in rows
            if row.topology === topology && row.replication == replication &&
                row.condition === condition && row.regime === :clean_multi),
        contaminated_heldout_log_loss = only(row.heldout_log_loss for row in rows
            if row.topology === topology && row.replication == replication &&
                row.condition === condition && row.regime === :contaminated_multi),
    ) for topology in PROTOCOL.topologies
        for replication in 1:PROTOCOL.replications
        for condition in PROTOCOL.dgp_conditions]
    paired_rows = [merge(row, (;
        contamination_minus_clean_log_score_regret =
            row.contaminated_log_score_regret - row.clean_log_score_regret,
        contamination_minus_clean_heldout_log_loss =
            row.contaminated_heldout_log_loss - row.clean_heldout_log_loss,
    )) for row in paired_rows]
    gauge_rows = [(;
        topology,
        replication,
        condition,
        shifted_minus_truth_log_score_regret =
            only(row.log_score_regret for row in rows
                if row.topology === topology && row.replication == replication &&
                    row.condition === condition && row.regime === :single_shifted) -
            only(row.log_score_regret for row in rows
                if row.topology === topology && row.replication == replication &&
                    row.condition === condition && row.regime === :single_truth),
        shifted_minus_truth_heldout_log_loss =
            only(row.heldout_log_loss for row in rows
                if row.topology === topology && row.replication == replication &&
                    row.condition === condition && row.regime === :single_shifted) -
            only(row.heldout_log_loss for row in rows
                if row.topology === topology && row.replication == replication &&
                    row.condition === condition && row.regime === :single_truth),
    ) for topology in PROTOCOL.topologies
        for replication in 1:PROTOCOL.replications
        for condition in PROTOCOL.dgp_conditions]
    placement_rows = [(;
        topology,
        replication,
        condition,
        interior_minus_endpoint_log_score_regret =
            only(row.log_score_regret for row in rows
                if row.topology === topology && row.replication == replication &&
                    row.condition === condition && row.regime === :clean_interior) -
            only(row.log_score_regret for row in rows
                if row.topology === topology && row.replication == replication &&
                    row.condition === condition && row.regime === :clean_multi),
        interior_minus_endpoint_heldout_log_loss =
            only(row.heldout_log_loss for row in rows
                if row.topology === topology && row.replication == replication &&
                    row.condition === condition && row.regime === :clean_interior) -
            only(row.heldout_log_loss for row in rows
                if row.topology === topology && row.replication == replication &&
                    row.condition === condition && row.regime === :clean_multi),
    ) for topology in PROTOCOL.topologies
        for replication in 1:PROTOCOL.replications
        for condition in PROTOCOL.dgp_conditions]
    linking_placement_rows = [(;
        replication,
        condition,
        regime,
        distributed_minus_early_log_score_regret =
            only(row.log_score_regret for row in rows
                if row.topology === :nested_link_distributed &&
                    row.replication == replication && row.condition === condition &&
                    row.regime === regime) -
            only(row.log_score_regret for row in rows
                if row.topology === :nested_link_early &&
                    row.replication == replication && row.condition === condition &&
                    row.regime === regime),
        distributed_minus_early_heldout_log_loss =
            only(row.heldout_log_loss for row in rows
                if row.topology === :nested_link_distributed &&
                    row.replication == replication && row.condition === condition &&
                    row.regime === regime) -
            only(row.heldout_log_loss for row in rows
                if row.topology === :nested_link_early &&
                    row.replication == replication && row.condition === condition &&
                    row.regime === regime),
    ) for replication in 1:PROTOCOL.replications
        for condition in PROTOCOL.dgp_conditions
        for regime in Tuple(row.name for row in regimes)]
    condition_rows = [(;
        topology,
        replication,
        regime,
        misfit_minus_well_specified_log_score_regret =
            only(row.log_score_regret for row in rows
                if row.topology === topology && row.replication == replication &&
                    row.condition === :rater_extremity_misfit &&
                    row.regime === regime) -
            only(row.log_score_regret for row in rows
                if row.topology === topology && row.replication == replication &&
                    row.condition === :well_specified && row.regime === regime),
    ) for topology in PROTOCOL.topologies
        for replication in 1:PROTOCOL.replications
        for regime in Tuple(row.name for row in regimes)]
    return (;
        schema = "bayesianmgmfrm.mfrm_anchor_recovery_pilot.v2",
        status = :completed_descriptive_pilot,
        generated_at = string(Dates.now()),
        julia_version = string(VERSION),
        package_version = string(Base.pkgversion(BayesianMGMFRM)),
        protocol = PROTOCOL,
        anchor_regimes = regimes,
        topology_rows,
        rows,
        paired_rows,
        gauge_rows,
        placement_rows,
        linking_placement_rows,
        condition_rows,
        summary = (;
            n_fits = length(rows),
            n_diagnostics_passed = count(row -> row.diagnostics_passed, rows),
            total_divergences = sum(row.n_divergences for row in rows),
            total_max_treedepth = sum(row.n_max_treedepth for row in rows),
            n_pairs_contamination_worse_log_score = count(
                row -> row.contamination_minus_clean_log_score_regret > 0,
                paired_rows,
            ),
            mean_contamination_minus_clean_log_score_regret = mean(
                row.contamination_minus_clean_log_score_regret for row in paired_rows),
            n_pairs_contamination_worse_heldout_log_loss = count(
                row -> row.contamination_minus_clean_heldout_log_loss > 0,
                paired_rows,
            ),
            mean_contamination_minus_clean_heldout_log_loss = mean(
                row.contamination_minus_clean_heldout_log_loss for row in paired_rows),
            max_absolute_single_gauge_log_score_regret_difference = maximum(abs(
                row.shifted_minus_truth_log_score_regret) for row in gauge_rows),
            max_absolute_single_gauge_heldout_log_loss_difference = maximum(abs(
                row.shifted_minus_truth_heldout_log_loss) for row in gauge_rows),
            n_pairs_interior_worse_log_score_regret = count(
                row -> row.interior_minus_endpoint_log_score_regret > 0,
                placement_rows,
            ),
            mean_interior_minus_endpoint_log_score_regret = mean(
                row.interior_minus_endpoint_log_score_regret
                for row in placement_rows),
            n_pairs_distributed_worse_log_score_regret = count(
                row -> row.distributed_minus_early_log_score_regret > 0,
                linking_placement_rows,
            ),
            mean_distributed_minus_early_log_score_regret = mean(
                row.distributed_minus_early_log_score_regret
                for row in linking_placement_rows),
            n_pairs_distributed_worse_heldout_log_loss = count(
                row -> row.distributed_minus_early_heldout_log_loss > 0,
                linking_placement_rows,
            ),
            mean_distributed_minus_early_heldout_log_loss = mean(
                row.distributed_minus_early_heldout_log_loss
                for row in linking_placement_rows),
            nested_link_placement_effect_isolated = false,
            n_condition_pairs_misfit_worse_log_score_regret = count(
                row -> row.misfit_minus_well_specified_log_score_regret > 0,
                condition_rows,
            ),
            claim_scope = :two_replication_operability_pilot_not_recovery_evidence,
            diagnostic_thresholds_are_pilot_only = true,
            favorable_known_truth_initialization = true,
            heldout_prediction_evaluated = true,
            heldout_new_facet_levels = false,
            heldout_new_facet_level_status =
                :unsupported_without_hierarchical_facet_distribution,
            independent_dgp_cross_check_completed = false,
            failure_policy = :retain_all_completed_rows_and_block_public_claim,
            public_claim_release_allowed = false,
            next_gate = :predeclare_larger_fresh_seed_grid_with_linking_dose_and_external_dgp,
        ),
    )
end

function main(args = ARGS)
    length(args) <= 1 || throw(ArgumentError(
        "usage: julia --project=. scripts/run_mfrm_anchor_recovery_pilot.jl [output.json]",
    ))
    output = isempty(args) ? DEFAULT_OUTPUT : abspath(args[1])
    result = run_pilot()
    write_artifact(output, result)
    println("wrote ", relpath(output, ROOT))
    println(result.summary)
    return result
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    MFRMAnchorRecoveryPilot.main()
end
