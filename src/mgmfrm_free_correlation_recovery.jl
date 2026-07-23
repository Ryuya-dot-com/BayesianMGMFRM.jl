# mgmfrm_free_correlation_recovery.jl -- quarantined response-recovery layer.

const _FREE_CORRELATION_FIXTURE_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_known_truth_fixture.v1"
const _FREE_CORRELATION_PILOT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_recovery_pilot.v1"
const _FREE_CORRELATION_HARD_MAX_OBSERVATIONS = 100_000
const _FREE_CORRELATION_HARD_MAX_PROBABILITY_CELLS = 500_000
const _FREE_CORRELATION_SOURCE_SCALE = 1.7

function _free_correlation_checked_integer(
        value,
        name::Symbol;
        minimum::Int = 1)
    value isa Integer && !(value isa Bool) || throw(ArgumentError(
        "$name must be an integer",
    ))
    converted = try
        Int(value)
    catch
        throw(ArgumentError("$name must fit in Int"))
    end
    converted >= minimum || throw(ArgumentError(
        "$name must be at least $minimum",
    ))
    return converted
end

function _free_correlation_checked_seed(value, name::Symbol)
    seed = _free_correlation_checked_integer(value, name; minimum = 0)
    return seed
end

function _free_correlation_checked_rho(value)
    value isa Real && !(value isa Bool) || throw(ArgumentError(
        "rho_truth must be a real value in (-1, 1)",
    ))
    rho = try
        Float64(value)
    catch
        throw(ArgumentError("rho_truth must be convertible to Float64"))
    end
    isfinite(rho) && -1 < rho < 1 || throw(ArgumentError(
        "rho_truth must be finite and in (-1, 1)",
    ))
    return rho
end

function _free_correlation_checked_product(
        limit::Int,
        name::AbstractString,
        values::Int...)
    limit >= 1 || throw(ArgumentError("$name limit must be positive"))
    total = 1
    for value in values
        value >= 1 || throw(ArgumentError(
            "$name received a non-positive factor",
        ))
        total <= limit ÷ value || throw(ArgumentError(
            "$name exceeds its configured limit $limit",
        ))
        total *= value
    end
    return total
end

function _free_correlation_fixture_q_matrix(items_per_dimension::Int)
    q_matrix = falses(2 * items_per_dimension, 2)
    q_matrix[1:items_per_dimension, 1] .= true
    q_matrix[(items_per_dimension + 1):(2 * items_per_dimension), 2] .= true
    return q_matrix
end

function _free_correlation_fixture_columns(
        n_persons::Int,
        items_per_dimension::Int,
        n_raters::Int,
        n_categories::Int,
        n_observations::Int)
    n_items = 2 * items_per_dimension
    person = Vector{Int}(undef, n_observations)
    rater = Vector{Int}(undef, n_observations)
    item = Vector{Int}(undef, n_observations)
    score = Vector{Int}(undef, n_observations)
    row = 0
    for person_index in 1:n_persons, item_index in 1:n_items
        row += 1
        person[row] = person_index
        item[row] = item_index
        rater[row] = 1 + mod(person_index + item_index - 2, n_raters)
        score[row] = mod(row - 1, n_categories)
    end
    row == n_observations || throw(ArgumentError(
        "internal free-correlation fixture row-count mismatch",
    ))
    return (; person, rater, item, score)
end

function _free_correlation_fixture_spec(columns, q_matrix)
    data = FacetData(
        columns;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
    return mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        dimension_labels = ["dimension_1", "dimension_2"],
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix,
    )
end

function _free_correlation_correlated_abilities(
        n_persons::Int,
        rho::Float64,
        seed::Int,
        person_sd::Float64)
    rng = MersenneTwister(seed)
    first_dimension = person_sd .* randn(rng, n_persons)
    innovations = person_sd .* randn(rng, n_persons)
    complement = sqrt((1 - rho) * (1 + rho))
    second_dimension = rho .* first_dimension .+
        complement .* innovations
    abilities = hcat(first_dimension, second_dimension)
    all(isfinite, abilities) || throw(ArgumentError(
        "known-truth ability generation produced non-finite values",
    ))
    realized = cor(first_dimension, second_dimension)
    isfinite(realized) || throw(ArgumentError(
        "known-truth ability generation produced an undefined realized correlation",
    ))
    return abilities, Float64(realized)
end

function _free_correlation_fixture_base_truth(
        target::_MGMFRMFreeLatentCorrelation2DLogDensity,
        abilities::AbstractMatrix{<:Real})
    blueprint = target.base.blueprint
    spec = target.base.design.spec
    data = spec.data
    n_persons = length(data.person_levels)
    n_raters = length(data.rater_levels)
    n_items = length(data.item_levels)
    n_categories = length(data.category_levels)
    size(abilities) == (n_persons, 2) || throw(ArgumentError(
        "ability truth must have size ($n_persons, 2)",
    ))
    raw = zeros(Float64, blueprint.n_parameters)

    person_block = blueprint.blocks[:person]
    for person in 1:n_persons, dimension in 1:2
        raw[person_block[(person - 1) * 2 + dimension]] =
            Float64(abilities[person, dimension])
    end

    rater_values = collect(range(-0.25, 0.25; length = n_raters))
    rater_values .-= sum(rater_values; init = 0.0) / n_raters
    raw[blueprint.blocks[:rater_free]] .= rater_values[1:(end - 1)]

    item_values = collect(range(-0.5, 0.5; length = div(n_items, 2)))
    raw[blueprint.blocks[:item]] .= vcat(item_values, item_values)
    raw[blueprint.blocks[:log_item_dimension_discrimination]] .= 0.0
    raw[blueprint.blocks[:log_rater_consistency_free]] .= 0.0

    free_steps = max(n_categories - 2, 0)
    if free_steps > 0
        conceptual_steps = collect(range(-0.4, 0.4; length = n_categories - 1))
        free_step_values = conceptual_steps[1:free_steps]
        for item in 1:n_items
            offset = (item - 1) * free_steps
            raw[blueprint.blocks[:item_steps][
                (offset + 1):(offset + free_steps)]] .= free_step_values
        end
    end
    all(isfinite, raw) || throw(ArgumentError(
        "known-truth raw parameter construction produced non-finite values",
    ))
    return raw
end

function _free_correlation_assignment_checks(
        data::FacetData,
        q_matrix::AbstractMatrix{Bool})
    n_persons = length(data.person_levels)
    n_raters = length(data.rater_levels)
    n_items = length(data.item_levels)
    pair_counts = zeros(Int, n_persons, n_items)
    rater_counts = zeros(Int, n_raters)
    person_dimension_observed = falses(n_persons, 2)
    person_rater_observed = falses(n_persons, n_raters)
    rater_dimension_observed = falses(n_raters, 2)
    rater_item_observed = falses(n_raters, n_items)
    item_rater_observed = falses(n_items, n_raters)
    for row in 1:data.n
        person = data.person[row]
        item = data.item[row]
        rater = data.rater[row]
        pair_counts[person, item] += 1
        rater_counts[rater] += 1
        person_rater_observed[person, rater] = true
        rater_item_observed[rater, item] = true
        item_rater_observed[item, rater] = true
        for dimension in 1:2
            if q_matrix[item, dimension]
                person_dimension_observed[person, dimension] = true
                rater_dimension_observed[rater, dimension] = true
            end
        end
    end
    distinct_raters_per_person = [
        count(@view person_rater_observed[person, :])
        for person in 1:n_persons
    ]
    distinct_raters_per_item = [
        count(@view item_rater_observed[item, :])
        for item in 1:n_items
    ]
    return (;
        every_person_item_once = all(==(1), pair_counts),
        every_person_observed_in_both_dimensions =
            all(person_dimension_observed),
        every_rater_observed = all(>(0), rater_counts),
        latin_square_rater_balance =
            maximum(rater_counts) - minimum(rater_counts) <= 1,
        every_person_has_at_least_two_raters =
            all(>=(2), distinct_raters_per_person),
        every_rater_observed_in_both_dimensions =
            all(rater_dimension_observed),
        every_rater_observed_on_all_items = all(rater_item_observed),
        every_item_has_at_least_two_raters =
            all(>=(2), distinct_raters_per_item),
        pair_counts,
        rater_counts,
        distinct_raters_per_person,
        distinct_raters_per_item,
        person_dimension_observed,
        person_rater_observed,
        rater_dimension_observed,
        rater_item_observed,
        item_rater_observed,
    )
end

function _free_correlation_probability_checks(probabilities::AbstractMatrix)
    finite = all(isfinite, probabilities)
    nonnegative = all(>=(0), probabilities)
    bounded = all(<=(1), probabilities)
    sum_errors = [
        abs(sum(@view(probabilities[row, :]); init = 0.0) - 1.0)
        for row in axes(probabilities, 1)
    ]
    maximum_sum_error = maximum(sum_errors)
    return (;
        finite,
        nonnegative,
        bounded,
        maximum_sum_error,
        passed = finite && nonnegative && bounded && maximum_sum_error <= 1e-12,
    )
end

function _free_correlation_closed_form_probabilities(
        design::FacetDesign,
        direct_params::AbstractVector)
    data = design.spec.data
    design.spec.family === :mgmfrm || throw(ArgumentError(
        "closed-form recovery oracle requires an MGMFRM design",
    ))
    design.spec.dimensions == 2 || throw(ArgumentError(
        "closed-form recovery oracle requires exactly two dimensions",
    ))
    q_matrix = design.spec.q_matrix
    q_matrix isa AbstractMatrix{Bool} || throw(ArgumentError(
        "closed-form recovery oracle requires a Boolean Q-matrix",
    ))
    n_persons = length(data.person_levels)
    n_raters = length(data.rater_levels)
    n_items = length(data.item_levels)
    n_categories = length(data.category_levels)
    size(q_matrix) == (n_items, 2) || throw(ArgumentError(
        "closed-form recovery oracle Q-matrix has the wrong shape",
    ))
    all(item -> count(@view(q_matrix[item, :])) == 1, 1:n_items) ||
        throw(ArgumentError(
            "closed-form recovery oracle requires a pure simple-structure Q-matrix",
        ))
    length(direct_params) == length(design.parameter_names) ||
        throw(ArgumentError(
            "closed-form recovery oracle received the wrong direct parameter length",
        ))
    values = Float64.(direct_params)
    all(isfinite, values) || throw(ArgumentError(
        "closed-form recovery oracle requires finite direct parameters",
    ))

    required_blocks = (
        :person,
        :rater,
        :item,
        :item_dimension_discrimination,
        :rater_consistency,
        :item_steps,
    )
    all(block -> haskey(design.blocks, block), required_blocks) ||
        throw(ArgumentError(
            "closed-form recovery oracle design is missing a required block",
        ))
    person_block = design.blocks[:person]
    rater_block = design.blocks[:rater]
    item_block = design.blocks[:item]
    discrimination_block = design.blocks[:item_dimension_discrimination]
    consistency_block = design.blocks[:rater_consistency]
    step_block = design.blocks[:item_steps]
    free_steps = max(n_categories - 2, 0)
    length(person_block) == 2 * n_persons &&
        length(rater_block) == n_raters &&
        length(item_block) == n_items &&
        length(discrimination_block) == count(q_matrix) &&
        length(consistency_block) == n_raters &&
        length(step_block) == n_items * free_steps ||
        throw(ArgumentError(
            "closed-form recovery oracle block dimensions are inconsistent",
        ))

    discrimination_indices = zeros(Int, n_items, 2)
    active_index = 0
    for item in 1:n_items, dimension in 1:2
        q_matrix[item, dimension] || continue
        active_index += 1
        discrimination_indices[item, dimension] =
            discrimination_block[active_index]
    end
    active_index == length(discrimination_block) || throw(ArgumentError(
        "closed-form recovery oracle discrimination indexing failed",
    ))

    probabilities = Matrix{Float64}(undef, data.n, n_categories)
    eta = Vector{Float64}(undef, n_categories)
    for row in 1:data.n
        person = data.person[row]
        rater = data.rater[row]
        item = data.item[row]
        ability_score = 0.0
        person_offset = (person - 1) * 2
        for dimension in 1:2
            q_matrix[item, dimension] || continue
            ability_score +=
                values[discrimination_indices[item, dimension]] *
                values[person_block[person_offset + dimension]]
        end
        location = ability_score - values[item_block[item]] -
            values[rater_block[rater]]
        scale = _FREE_CORRELATION_SOURCE_SCALE *
            values[consistency_block[rater]]
        eta[1] = 0.0
        cumulative = 0.0
        for category_index in 2:n_categories
            step = if free_steps == 0
                0.0
            elseif category_index <= n_categories - 1
                local_step = (item - 1) * free_steps + category_index - 1
                values[step_block[local_step]]
            else
                first_step = (item - 1) * free_steps + 1
                last_step = item * free_steps
                -sum(@view values[step_block[first_step:last_step]];
                    init = 0.0)
            end
            cumulative += scale * (location - step)
            eta[category_index] = cumulative
        end
        all(isfinite, eta) || throw(ArgumentError(
            "closed-form recovery oracle produced a non-finite linear predictor",
        ))
        maximum_eta = maximum(eta)
        denominator = 0.0
        for category_index in 1:n_categories
            probability = exp(eta[category_index] - maximum_eta)
            probabilities[row, category_index] = probability
            denominator += probability
        end
        isfinite(denominator) && denominator > 0 || throw(ArgumentError(
            "closed-form recovery oracle produced an invalid softmax denominator",
        ))
        for category_index in 1:n_categories
            probabilities[row, category_index] /= denominator
        end
    end
    _free_correlation_probability_checks(probabilities).passed ||
        throw(ArgumentError(
            "closed-form recovery oracle produced invalid probabilities",
        ))
    return probabilities
end

function _mgmfrm_free_latent_correlation_2d_known_truth_fixture(;
        n_persons = 24,
        items_per_dimension = 3,
        n_raters = 2,
        n_categories = 3,
        rho_truth = 0.6,
        ability_seed = 20260723,
        response_seed = 20260724,
        lkj_eta = 2,
        max_observations = 100_000,
        max_probability_cells = 500_000)
    people = _free_correlation_checked_integer(
        n_persons,
        :n_persons;
        minimum = 4,
    )
    items_per_dim = _free_correlation_checked_integer(
        items_per_dimension,
        :items_per_dimension;
        minimum = 2,
    )
    raters = _free_correlation_checked_integer(
        n_raters,
        :n_raters;
        minimum = 2,
    )
    categories = _free_correlation_checked_integer(
        n_categories,
        :n_categories;
        minimum = 2,
    )
    people >= raters || throw(ArgumentError(
        "n_persons must be at least n_raters for the Latin-square assignment",
    ))
    checked_rho = _free_correlation_checked_rho(rho_truth)
    ability_seed_value = _free_correlation_checked_seed(
        ability_seed,
        :ability_seed,
    )
    response_seed_value = _free_correlation_checked_seed(
        response_seed,
        :response_seed,
    )
    ability_seed_value != response_seed_value || throw(ArgumentError(
        "ability_seed and response_seed must be distinct",
    ))
    observation_cap = _free_correlation_checked_integer(
        max_observations,
        :max_observations,
    )
    probability_cap = _free_correlation_checked_integer(
        max_probability_cells,
        :max_probability_cells,
    )
    observation_cap <= _FREE_CORRELATION_HARD_MAX_OBSERVATIONS ||
        throw(ArgumentError(
            "max_observations must not exceed the hard quarantine cap " *
            "$_FREE_CORRELATION_HARD_MAX_OBSERVATIONS",
        ))
    probability_cap <= _FREE_CORRELATION_HARD_MAX_PROBABILITY_CELLS ||
        throw(ArgumentError(
            "max_probability_cells must not exceed the hard quarantine cap " *
            "$_FREE_CORRELATION_HARD_MAX_PROBABILITY_CELLS",
        ))
    n_items = _free_correlation_checked_product(
        observation_cap,
        "item count",
        2,
        items_per_dim,
    )
    n_observations = _free_correlation_checked_product(
        observation_cap,
        "observation workload",
        people,
        n_items,
    )
    n_probability_cells = _free_correlation_checked_product(
        probability_cap,
        "probability workload",
        n_observations,
        categories,
    )

    q_matrix = _free_correlation_fixture_q_matrix(items_per_dim)
    columns = _free_correlation_fixture_columns(
        people,
        items_per_dim,
        raters,
        categories,
        n_observations,
    )
    template_spec = _free_correlation_fixture_spec(columns, q_matrix)
    template_design = getdesign(template_spec; preview = true)
    template_candidate = _mgmfrm_free_latent_correlation_2d_logdensity(
        template_spec;
        lkj_eta,
    )
    abilities, realized_correlation =
        _free_correlation_correlated_abilities(
            people,
            checked_rho,
            ability_seed_value,
            template_candidate.prior.source_prior.person_sd,
        )
    base_raw_truth = _free_correlation_fixture_base_truth(
        template_candidate,
        abilities,
    )
    direct_truth = _mgmfrm_source_constrained_params_from_unconstrained(
        template_design,
        base_raw_truth,
    )
    constraint_rows = _mgmfrm_direct_constraint_rows(
        template_design,
        direct_truth,
    )
    all(row -> row.passed, constraint_rows) || throw(ArgumentError(
        "known-truth direct parameters failed MGMFRM constraints",
    ))
    probability_cube = _mgmfrm_predictive_probabilities_direct(
        template_design,
        reshape(direct_truth, 1, :),
    )
    probabilities = Matrix{Float64}(@view probability_cube[1, :, :])
    probability_checks = _free_correlation_probability_checks(probabilities)
    probability_checks.passed || throw(ArgumentError(
        "known-truth response probabilities failed their finite simplex contract",
    ))

    generated_data = simulate_responses(
        template_design,
        base_raw_truth;
        rng = MersenneTwister(response_seed_value),
        output = :data,
        parameter_space = :raw,
    )
    generated_spec = mfrm_spec(
        generated_data;
        family = :mgmfrm,
        dimensions = 2,
        dimension_labels = copy(template_spec.dimension_labels),
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix = copy(q_matrix),
    )
    generated_design = getdesign(generated_spec; preview = true)
    candidate = _mgmfrm_free_latent_correlation_2d_logdensity(
        generated_spec;
        lkj_eta,
    )
    generated_direct_truth =
        _mgmfrm_source_constrained_params_from_unconstrained(
            generated_design,
            base_raw_truth,
        )
    direct_truth == generated_direct_truth || throw(ArgumentError(
        "generated MGMFRM design changed the direct truth transform",
    ))
    generated_probability_cube = _mgmfrm_predictive_probabilities_direct(
        generated_design,
        reshape(generated_direct_truth, 1, :),
    )
    generated_probabilities =
        Matrix{Float64}(@view generated_probability_cube[1, :, :])
    maximum_probability_replay_error =
        maximum(abs.(generated_probabilities .- probabilities))

    raw_order_unchanged = candidate.blueprint.parameter_names ==
        template_candidate.blueprint.parameter_names
    direct_order_unchanged = generated_design.parameter_names ==
        template_design.parameter_names
    raw_order_unchanged || throw(ArgumentError(
        "generated MGMFRM design changed the candidate raw parameter order",
    ))
    direct_order_unchanged || throw(ArgumentError(
        "generated MGMFRM design changed the direct parameter order",
    ))
    maximum_probability_replay_error <= 1e-12 || throw(ArgumentError(
        "generated MGMFRM design changed known-truth response probabilities",
    ))

    intended_category_levels = collect(0:(categories - 1))
    category_scale_preserved =
        generated_data.category_levels == intended_category_levels
    category_counts = Tuple((;
        category,
        count = count(==(category), generated_data.score),
    ) for category in intended_category_levels)
    all_categories_observed = all(row -> row.count > 0, category_counts)
    category_scale_preserved || throw(ArgumentError(
        "generated responses did not preserve the intended category scale",
    ))
    all_categories_observed || throw(ArgumentError(
        "generated responses did not realize every intended category",
    ))

    assignment = _free_correlation_assignment_checks(
        generated_data,
        q_matrix,
    )
    assignment_passed = assignment.every_person_item_once &&
        assignment.every_person_observed_in_both_dimensions &&
        assignment.every_rater_observed && assignment.latin_square_rater_balance &&
        assignment.every_person_has_at_least_two_raters &&
        assignment.every_rater_observed_in_both_dimensions &&
        assignment.every_rater_observed_on_all_items &&
        assignment.every_item_has_at_least_two_raters
    assignment_passed || throw(ArgumentError(
        "generated responses failed the Latin-square assignment contract",
    ))
    q_validation = q_matrix_validation(
        generated_spec;
        cross_loading_policy = :blocked_simple_structure,
    )
    q_validation.passed || throw(ArgumentError(
        "generated responses failed the pure-Q validation contract",
    ))
    facet_graph_connected = length(generated_spec.validation.components) == 1
    facet_graph_connected || throw(ArgumentError(
        "generated responses did not produce one connected facet graph",
    ))
    candidate_raw_truth = vcat(base_raw_truth, atanh(checked_rho))
    truth_logdensity = LogDensityProblems.logdensity(
        candidate,
        candidate_raw_truth,
    )
    truth_pointwise_loglikelihood =
        _mgmfrm_free_latent_correlation_2d_pointwise_loglikelihood(
            candidate,
            candidate_raw_truth,
        )
    probability_implied_pointwise = [
        log(generated_probabilities[row, generated_data.category[row]])
        for row in 1:generated_data.n
    ]
    maximum_truth_pointwise_error = maximum(abs.(
        truth_pointwise_loglikelihood .- probability_implied_pointwise,
    ))
    shared_kernel_replay_probabilities = zeros(
        Float64,
        generated_data.n,
        categories,
    )
    for row in _mgmfrm_source_fixture_values(
            generated_design,
            generated_direct_truth)
        shared_kernel_replay_probabilities[row.row, row.category_index] =
            exp(Float64(row.log_probability))
    end
    source_oracle_probabilities =
        _free_correlation_closed_form_probabilities(
            generated_design,
            generated_direct_truth,
        )
    maximum_shared_kernel_replay_error = maximum(abs.(
        shared_kernel_replay_probabilities .- generated_probabilities,
    ))
    maximum_closed_form_oracle_error = maximum(abs.(
        source_oracle_probabilities .- generated_probabilities,
    ))
    maximum_source_oracle_error = maximum_closed_form_oracle_error
    maximum_truth_pointwise_error <= 1e-12 || throw(ArgumentError(
        "known-truth pointwise likelihood disagrees with response probabilities",
    ))
    maximum_shared_kernel_replay_error <= 1e-12 || throw(ArgumentError(
        "known-truth response probabilities disagree with the shared-kernel replay",
    ))
    maximum_closed_form_oracle_error <= 1e-12 || throw(ArgumentError(
        "known-truth response probabilities disagree with the independent closed-form oracle",
    ))
    finite_truth = all(isfinite, base_raw_truth) &&
        all(isfinite, candidate_raw_truth) &&
        all(isfinite, generated_direct_truth) &&
        all(isfinite, truth_pointwise_loglikelihood) &&
        all(isfinite, shared_kernel_replay_probabilities) &&
        all(isfinite, source_oracle_probabilities) && isfinite(truth_logdensity)
    finite_truth || throw(ArgumentError(
        "known-truth fixture produced a non-finite parameter payload",
    ))

    checks = (;
        workload_within_caps = n_observations <= observation_cap &&
            n_probability_cells <= probability_cap,
        q_matrix_valid = q_validation.passed,
        q_matrix_pure_simple_structure = all(
            count(@view(q_matrix[item, :])) == 1
            for item in axes(q_matrix, 1)
        ),
        assignment_passed,
        every_person_item_once = assignment.every_person_item_once,
        every_person_observed_in_both_dimensions =
            assignment.every_person_observed_in_both_dimensions,
        every_rater_observed = assignment.every_rater_observed,
        latin_square_rater_balance = assignment.latin_square_rater_balance,
        every_person_has_at_least_two_raters =
            assignment.every_person_has_at_least_two_raters,
        every_rater_observed_in_both_dimensions =
            assignment.every_rater_observed_in_both_dimensions,
        every_rater_observed_on_all_items =
            assignment.every_rater_observed_on_all_items,
        every_item_has_at_least_two_raters =
            assignment.every_item_has_at_least_two_raters,
        facet_graph_connected,
        category_scale_preserved,
        all_categories_observed,
        probabilities_valid = probability_checks.passed,
        maximum_probability_replay_error,
        maximum_truth_pointwise_error,
        maximum_shared_kernel_replay_error,
        maximum_closed_form_oracle_error,
        maximum_source_oracle_error,
        constraints_valid = all(row -> row.passed, constraint_rows),
        raw_parameter_order_unchanged = raw_order_unchanged,
        direct_parameter_order_unchanged = direct_order_unchanged,
        finite_truth,
        seeds_separated = ability_seed_value != response_seed_value,
    )
    passed = all((
        checks.workload_within_caps,
        checks.q_matrix_valid,
        checks.q_matrix_pure_simple_structure,
        checks.assignment_passed,
        checks.facet_graph_connected,
        checks.category_scale_preserved,
        checks.all_categories_observed,
        checks.probabilities_valid,
        checks.constraints_valid,
        checks.raw_parameter_order_unchanged,
        checks.direct_parameter_order_unchanged,
        checks.finite_truth,
        checks.seeds_separated,
    ))
    passed || throw(ArgumentError(
        "known-truth fixture failed its closed validation contract",
    ))
    return (;
        schema = _FREE_CORRELATION_FIXTURE_SCHEMA,
        family = :mgmfrm,
        scope = :mgmfrm_2d_free_latent_correlation_candidate,
        status = :known_truth_generated,
        claim_scope = :response_level_dgp_not_recovery,
        public_fit = false,
        fit_ready = false,
        cache_enabled = false,
        promotion_effect = :none,
        result_type = :named_tuple_only,
        seeds = (;
            ability = ability_seed_value,
            response = response_seed_value,
            separated = ability_seed_value != response_seed_value,
            rng = :MersenneTwister,
            cross_julia_bitwise_portability_claimed = false,
        ),
        design_contract = (;
            dimensions = 2,
            n_persons = people,
            items_per_dimension = items_per_dim,
            n_items,
            n_raters = raters,
            n_categories = categories,
            n_observations,
            n_probability_cells,
            assignment = :all_person_by_item_latin_square_rater,
            q_matrix = copy(q_matrix),
            thresholds = :partial_credit,
            discrimination = :none,
            source_scale = _FREE_CORRELATION_SOURCE_SCALE,
            max_observations = observation_cap,
            max_probability_cells = probability_cap,
        ),
        data = generated_data,
        spec = generated_spec,
        candidate,
        truth = (;
            population_rho = checked_rho,
            zrho = atanh(checked_rho),
            realized_latent_correlation = realized_correlation,
            person_sd = candidate.prior.source_prior.person_sd,
            person_abilities = abilities,
            base_raw_parameter_names =
                copy(candidate.base.blueprint.parameter_names),
            base_raw_parameter_values = copy(base_raw_truth),
            candidate_raw_parameter_names =
                copy(candidate.blueprint.parameter_names),
            candidate_raw_parameter_values = copy(candidate_raw_truth),
            direct_parameter_names = copy(generated_design.parameter_names),
            direct_parameter_values = copy(generated_direct_truth),
            truth_logdensity,
        ),
        response_probabilities = generated_probabilities,
        shared_kernel_replay_probabilities,
        source_oracle_probabilities,
        probability_oracle_contract = (;
            source_oracle = :independent_closed_form_direct_scale,
            shared_kernel_replay = :source_fixture_values,
            source_scale = _FREE_CORRELATION_SOURCE_SCALE,
            forbidden_shared_helpers = (
                :_mgmfrm_predictive_probabilities_direct,
                :_mgmfrm_source_linear_predictors!,
                :_mgmfrm_source_fixture_values,
                :_source_step_value,
                :_source_step_values,
                :_logsumexp,
            ),
        ),
        truth_pointwise_loglikelihood,
        category_counts,
        score_counts = category_counts,
        constraint_rows,
        q_matrix_validation = q_validation,
        assignment = assignment,
        probability_checks,
        likelihood_identity = (;
            maximum_truth_pointwise_error,
            maximum_shared_kernel_replay_error,
            maximum_closed_form_oracle_error,
            maximum_source_oracle_error,
            passed = maximum_truth_pointwise_error <= 1e-12 &&
                maximum_shared_kernel_replay_error <= 1e-12 &&
                maximum_closed_form_oracle_error <= 1e-12,
        ),
        checks = merge(checks, (; passed)),
        summary = (;
            passed,
            n_parameters = candidate.blueprint.n_parameters,
            n_observations,
            population_rho = checked_rho,
            realized_latent_correlation = realized_correlation,
            all_categories_observed,
        ),
        recovery_verified = false,
        next_gate = :single_dataset_multichain_recovery_pilot,
    )
end

function _validate_free_correlation_known_truth_fixture(fixture)
    fixture isa NamedTuple || throw(ArgumentError(
        "fixture must be returned by the free-correlation known-truth generator",
    ))
    required_fields = (
        :schema, :status, :claim_scope, :public_fit, :fit_ready,
        :cache_enabled, :promotion_effect, :seeds, :design_contract,
        :data, :spec, :candidate, :truth, :response_probabilities,
        :shared_kernel_replay_probabilities, :source_oracle_probabilities,
        :probability_oracle_contract, :truth_pointwise_loglikelihood,
        :category_counts, :constraint_rows, :likelihood_identity, :checks,
    )
    all(field -> hasproperty(fixture, field), required_fields) ||
        throw(ArgumentError(
            "known-truth fixture is missing required fields",
        ))
    fixture.schema == _FREE_CORRELATION_FIXTURE_SCHEMA || throw(ArgumentError(
        "unexpected free-correlation known-truth fixture schema",
    ))
    fixture.status === :known_truth_generated || throw(ArgumentError(
        "known-truth fixture is not in generated status",
    ))
    fixture.claim_scope === :response_level_dgp_not_recovery ||
        throw(ArgumentError("known-truth fixture claim scope was modified"))
    fixture.public_fit === false && fixture.fit_ready === false &&
        fixture.cache_enabled === false && fixture.promotion_effect === :none ||
        throw(ArgumentError("known-truth fixture quarantine flags were modified"))
    fixture.candidate isa _MGMFRMFreeLatentCorrelation2DLogDensity ||
        throw(ArgumentError("known-truth fixture candidate has an invalid type"))
    fixture.checks.passed || throw(ArgumentError(
        "known-truth fixture did not pass its generation checks",
    ))
    fixture.seeds.separated || throw(ArgumentError(
        "known-truth fixture seed streams are not separated",
    ))
    fixture.spec.data === fixture.data || throw(ArgumentError(
        "known-truth fixture spec and data are not identical",
    ))
    fixture.candidate.blueprint.parameter_names ==
        fixture.truth.candidate_raw_parameter_names || throw(ArgumentError(
        "known-truth fixture raw parameter order was modified",
    ))
    fixture.candidate.base.design.parameter_names ==
        fixture.truth.direct_parameter_names || throw(ArgumentError(
        "known-truth fixture direct parameter order was modified",
    ))
    length(fixture.truth.candidate_raw_parameter_values) ==
        fixture.candidate.blueprint.n_parameters || throw(ArgumentError(
        "known-truth fixture raw truth length was modified",
    ))
    length(fixture.truth.direct_parameter_values) ==
        length(fixture.candidate.base.design.parameter_names) ||
        throw(ArgumentError(
            "known-truth fixture direct truth length was modified",
        ))
    all(isfinite, fixture.truth.candidate_raw_parameter_values) &&
        all(isfinite, fixture.truth.direct_parameter_values) ||
        throw(ArgumentError("known-truth fixture contains non-finite truth"))
    fixture.data.n == fixture.design_contract.n_observations ||
        throw(ArgumentError("known-truth fixture observation count was modified"))
    fixture.data.category_levels ==
        collect(0:(fixture.design_contract.n_categories - 1)) ||
        throw(ArgumentError("known-truth fixture category scale was modified"))
    fixture.design_contract.source_scale == _FREE_CORRELATION_SOURCE_SCALE ||
        throw(ArgumentError(
            "known-truth fixture source scale was modified",
        ))
    fixture.probability_oracle_contract == (;
        source_oracle = :independent_closed_form_direct_scale,
        shared_kernel_replay = :source_fixture_values,
        source_scale = _FREE_CORRELATION_SOURCE_SCALE,
        forbidden_shared_helpers = (
            :_mgmfrm_predictive_probabilities_direct,
            :_mgmfrm_source_linear_predictors!,
            :_mgmfrm_source_fixture_values,
            :_source_step_value,
            :_source_step_values,
            :_logsumexp,
        ),
    ) || throw(ArgumentError(
        "known-truth fixture probability oracle contract was modified",
    ))
    all(row -> row.passed, fixture.constraint_rows) || throw(ArgumentError(
        "known-truth fixture contains a failed direct constraint",
    ))

    candidate = fixture.candidate
    design = candidate.base.design
    design.spec.validation.data_signature ==
        fixture.spec.validation.data_signature || throw(ArgumentError(
        "known-truth fixture candidate and spec data signatures differ",
    ))
    design.spec.q_matrix == fixture.design_contract.q_matrix ||
        throw(ArgumentError("known-truth fixture Q-matrix was modified"))
    rho = _free_correlation_checked_rho(fixture.truth.population_rho)
    zrho = Float64(fixture.truth.zrho)
    isfinite(zrho) && zrho == atanh(rho) &&
        isapprox(tanh(zrho), rho; rtol = 8eps(Float64), atol = 8eps(Float64)) ||
        throw(ArgumentError(
        "known-truth fixture rho and zrho are inconsistent",
    ))
    candidate_raw = Float64.(fixture.truth.candidate_raw_parameter_values)
    base_raw = Float64.(fixture.truth.base_raw_parameter_values)
    candidate_raw[candidate.blueprint.base_parameter_range] == base_raw ||
        throw(ArgumentError(
            "known-truth fixture candidate and base raw truth differ",
        ))
    candidate_raw[candidate.blueprint.zrho_index] == zrho ||
        throw(ArgumentError(
            "known-truth fixture candidate zrho truth was modified",
        ))

    regenerated_abilities, regenerated_realized_correlation =
        _free_correlation_correlated_abilities(
            fixture.design_contract.n_persons,
            rho,
            fixture.seeds.ability,
            candidate.prior.source_prior.person_sd,
        )
    regenerated_abilities == fixture.truth.person_abilities ||
        throw(ArgumentError(
            "known-truth fixture ability values do not replay from ability_seed",
        ))
    regenerated_realized_correlation ==
        fixture.truth.realized_latent_correlation || throw(ArgumentError(
        "known-truth fixture realized latent correlation was modified",
    ))
    person_block = candidate.base.blueprint.blocks[:person]
    reshape(base_raw[person_block], 2, :)' == regenerated_abilities ||
        throw(ArgumentError(
            "known-truth fixture person raw block does not match abilities",
        ))

    recomputed_direct =
        _mgmfrm_source_constrained_params_from_unconstrained(
            design,
            base_raw,
        )
    recomputed_direct == fixture.truth.direct_parameter_values ||
        throw(ArgumentError(
            "known-truth fixture direct truth does not match its raw transform",
        ))
    recomputed_constraints = _mgmfrm_direct_constraint_rows(
        design,
        recomputed_direct,
    )
    all(row -> row.passed, recomputed_constraints) || throw(ArgumentError(
        "known-truth fixture recomputed direct constraints failed",
    ))
    recomputed_constraints == fixture.constraint_rows || throw(ArgumentError(
        "known-truth fixture direct constraint rows were modified",
    ))

    probability_cube = _mgmfrm_predictive_probabilities_direct(
        design,
        reshape(recomputed_direct, 1, :),
    )
    recomputed_probabilities = Matrix{Float64}(@view probability_cube[1, :, :])
    size(recomputed_probabilities) == size(fixture.response_probabilities) &&
        maximum(abs.(recomputed_probabilities .-
            fixture.response_probabilities)) <= 1e-12 ||
        throw(ArgumentError(
            "known-truth fixture response probabilities were modified",
        ))
    recomputed_probability_checks =
        _free_correlation_probability_checks(recomputed_probabilities)
    recomputed_probability_checks.passed || throw(ArgumentError(
        "known-truth fixture recomputed probabilities are invalid",
    ))

    recomputed_pointwise =
        _mgmfrm_free_latent_correlation_2d_pointwise_loglikelihood(
            candidate,
            candidate_raw,
        )
    recomputed_pointwise == fixture.truth_pointwise_loglikelihood ||
        throw(ArgumentError(
            "known-truth fixture pointwise log likelihood was modified",
        ))
    implied_pointwise = [
        log(recomputed_probabilities[row, fixture.data.category[row]])
        for row in 1:fixture.data.n
    ]
    maximum_truth_pointwise_error =
        maximum(abs.(recomputed_pointwise .- implied_pointwise))
    maximum_truth_pointwise_error <= 1e-12 ||
        throw(ArgumentError(
            "known-truth fixture pointwise likelihood identity failed",
        ))
    recomputed_shared_kernel_replay = zeros(
        Float64,
        fixture.data.n,
        fixture.design_contract.n_categories,
    )
    for row in _mgmfrm_source_fixture_values(design, recomputed_direct)
        recomputed_shared_kernel_replay[row.row, row.category_index] =
            exp(Float64(row.log_probability))
    end
    size(recomputed_shared_kernel_replay) ==
        size(fixture.shared_kernel_replay_probabilities) &&
        maximum(abs.(recomputed_shared_kernel_replay .-
            fixture.shared_kernel_replay_probabilities)) <= 1e-12 ||
        throw(ArgumentError(
            "known-truth fixture shared-kernel probability replay was modified",
        ))
    maximum_shared_kernel_replay_error = maximum(abs.(
        recomputed_shared_kernel_replay .- recomputed_probabilities,
    ))
    maximum_shared_kernel_replay_error <= 1e-12 || throw(ArgumentError(
        "known-truth fixture shared-kernel probability identity failed",
    ))
    recomputed_closed_form = _free_correlation_closed_form_probabilities(
        design,
        recomputed_direct,
    )
    size(recomputed_closed_form) == size(fixture.source_oracle_probabilities) &&
        maximum(abs.(recomputed_closed_form .-
            fixture.source_oracle_probabilities)) <= 1e-12 ||
        throw(ArgumentError(
            "known-truth fixture independent probability oracle was modified",
        ))
    maximum_closed_form_oracle_error = maximum(abs.(
        recomputed_closed_form .- recomputed_probabilities,
    ))
    maximum_closed_form_oracle_error <= 1e-12 || throw(ArgumentError(
        "known-truth fixture independent probability identity failed",
    ))
    expected_likelihood_identity = (;
        maximum_truth_pointwise_error,
        maximum_shared_kernel_replay_error,
        maximum_closed_form_oracle_error,
        maximum_source_oracle_error = maximum_closed_form_oracle_error,
        passed = true,
    )
    fixture.likelihood_identity == expected_likelihood_identity ||
        throw(ArgumentError(
            "known-truth fixture likelihood identity metadata was modified",
        ))

    replayed_data = simulate_responses(
        design,
        base_raw;
        rng = MersenneTwister(fixture.seeds.response),
        output = :data,
        parameter_space = :raw,
    )
    replayed_data.score == fixture.data.score || throw(ArgumentError(
        "known-truth fixture responses do not replay from response_seed",
    ))
    expected_categories = collect(0:(fixture.design_contract.n_categories - 1))
    replayed_data.category_levels == expected_categories ||
        throw(ArgumentError(
            "known-truth fixture replay changed the intended category scale",
        ))
    recomputed_counts = Tuple((;
        category,
        count = count(==(category), fixture.data.score),
    ) for category in expected_categories)
    recomputed_counts == fixture.category_counts &&
        all(row -> row.count > 0, recomputed_counts) || throw(ArgumentError(
        "known-truth fixture category counts were modified or incomplete",
    ))
    assignment = _free_correlation_assignment_checks(
        fixture.data,
        design.spec.q_matrix,
    )
    assignment.every_person_item_once &&
        assignment.every_person_observed_in_both_dimensions &&
        assignment.every_rater_observed &&
        assignment.latin_square_rater_balance &&
        assignment.every_person_has_at_least_two_raters &&
        assignment.every_rater_observed_in_both_dimensions &&
        assignment.every_rater_observed_on_all_items &&
        assignment.every_item_has_at_least_two_raters ||
        throw(ArgumentError(
            "known-truth fixture assignment no longer satisfies its contract",
        ))
    length(fixture.spec.validation.components) == 1 || throw(ArgumentError(
        "known-truth fixture facet graph is no longer connected",
    ))
    q_matrix_validation(
        fixture.spec;
        cross_loading_policy = :blocked_simple_structure,
    ).passed || throw(ArgumentError(
        "known-truth fixture Q-matrix no longer passes validation",
    ))
    recomputed_logdensity = LogDensityProblems.logdensity(
        candidate,
        candidate_raw,
    )
    isfinite(recomputed_logdensity) &&
        recomputed_logdensity == fixture.truth.truth_logdensity ||
        throw(ArgumentError(
            "known-truth fixture truth log density was modified",
        ))
    return fixture
end

function _free_correlation_pilot_mode_controls(
        mode::Symbol,
        ndraws,
        warmup,
        chains)
    mode in (:diagnostic_smoke, :scientific) || throw(ArgumentError(
        "mode must be :diagnostic_smoke or :scientific",
    ))
    default_draws = mode === :scientific ? 500 : 8
    default_warmup = mode === :scientific ? 500 : 8
    default_chains = mode === :scientific ? 4 : 2
    checked_draws = _free_correlation_checked_integer(
        ndraws === nothing ? default_draws : ndraws,
        :ndraws,
    )
    checked_warmup = _free_correlation_checked_integer(
        warmup === nothing ? default_warmup : warmup,
        :warmup;
        minimum = 0,
    )
    checked_chains = _free_correlation_checked_integer(
        chains === nothing ? default_chains : chains,
        :chains,
    )
    if mode === :scientific
        checked_chains >= 4 || throw(ArgumentError(
            "scientific mode requires at least four chains",
        ))
        checked_warmup >= 500 || throw(ArgumentError(
            "scientific mode requires at least 500 warmup iterations per chain",
        ))
        checked_draws >= 500 || throw(ArgumentError(
            "scientific mode requires ndraws >= 500 retained draws per chain",
        ))
    end
    return (;
        mode,
        ndraws = checked_draws,
        warmup = checked_warmup,
        chains = checked_chains,
    )
end

function _free_correlation_scientific_chain_initials(
        candidate::_MGMFRMFreeLatentCorrelation2DLogDensity,
        raw_initial::AbstractVector,
        chains::Int)
    rho_starts = chains == 4 ? [-0.8, -0.3, 0.3, 0.8] :
        collect(range(-0.8, 0.8; length = chains))
    zrho_starts = atanh.(rho_starts)
    initial_matrix = repeat(
        reshape(Float64.(collect(raw_initial)), 1, :),
        chains,
        1,
    )
    initial_matrix[:, candidate.blueprint.zrho_index] .= zrho_starts
    return initial_matrix, (;
        rho = rho_starts,
        zrho = zrho_starts,
    )
end

function _free_correlation_recovery_metadata(parameter_space::Symbol)
    return _recovery_metadata(;
        model_family = :mgmfrm,
        parameter_space,
        density_space = parameter_space === :constrained_direct ?
            :constrained_direct :
            (parameter_space === :derived_correlation ?
                :derived_correlation : :raw_unconstrained),
        scope = :mgmfrm_2d_free_latent_correlation_candidate,
        fit_ready = false,
        public_fit = false,
        experimental_public = false,
        guarded_local_fit = true,
    )
end

function _free_correlation_chain_layout(bundle, chains::Int, ndraws::Int)
    expected_chain_ids = repeat(collect(1:chains); inner = ndraws)
    expected_iterations = repeat(collect(1:ndraws), chains)
    passed = size(bundle.draws, 1) == chains * ndraws &&
        bundle.chain_ids == expected_chain_ids &&
        bundle.iterations == expected_iterations &&
        size(bundle.chain_initials, 1) == chains &&
        size(bundle.chain_initials, 2) == size(bundle.draws, 2)
    return (;
        ordering = :chain_major,
        n_chains = chains,
        draws_per_chain = ndraws,
        total_draws = chains * ndraws,
        expected_chain_ids,
        expected_iterations,
        chain_ids_match = bundle.chain_ids == expected_chain_ids,
        iterations_match = bundle.iterations == expected_iterations,
        chain_initial_shape = size(bundle.chain_initials),
        passed,
    )
end

function _mgmfrm_free_latent_correlation_2d_recovery_pilot(
        fixture;
        mode::Symbol = :diagnostic_smoke,
        ndraws = nothing,
        warmup = nothing,
        chains = nothing,
        seed = 20260725,
        raw_initial = nothing,
        chain_initials = nothing,
        step_size::Real = 0.03,
        target_accept::Real = 0.8,
        max_depth::Int = 10,
        max_energy_error::Real = 1000.0,
        metric::Symbol = :diagonal,
        ad_backend::Symbol = :ForwardDiff,
        init_jitter::Real = 0.0,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400.0,
        min_e_bfmi::Real = 0.3,
        interval::Real = 0.9,
        progress::Bool = false)
    checked_fixture = _validate_free_correlation_known_truth_fixture(fixture)
    controls = _free_correlation_pilot_mode_controls(
        mode,
        ndraws,
        warmup,
        chains,
    )
    sampler_seed = _free_correlation_checked_seed(seed, :seed)
    sampler_seed != checked_fixture.seeds.ability &&
        sampler_seed != checked_fixture.seeds.response || throw(ArgumentError(
        "pilot seed must differ from ability and response seeds",
    ))
    diagnostic_thresholds = _check_diagnostic_thresholds(
        rhat_threshold,
        ess_threshold,
    )
    checked_e_bfmi = Float64(min_e_bfmi)
    isfinite(checked_e_bfmi) && checked_e_bfmi >= 0 || throw(ArgumentError(
        "min_e_bfmi must be finite and non-negative",
    ))
    checked_interval = Float64(interval)
    checked_interval == 0.9 || throw(ArgumentError(
        "the first recovery pilot requires interval = 0.9",
    ))

    candidate = checked_fixture.candidate
    initial = raw_initial === nothing ? initial_params(candidate) :
        Float64.(collect(raw_initial))
    _check_source_fixture_raw_vector(candidate, initial)
    supplied_chain_initials = chain_initials
    resolved_chain_initials, initial_starts = if mode === :scientific &&
            supplied_chain_initials === nothing
        _free_correlation_scientific_chain_initials(
            candidate,
            initial,
            controls.chains,
        )
    elseif supplied_chain_initials === nothing
        zrho_starts = fill(
            Float64(initial[candidate.blueprint.zrho_index]),
            controls.chains,
        )
        nothing, (;
            rho = tanh.(zrho_starts),
            zrho = zrho_starts,
        )
    else
        supplied_chain_initials isa AbstractMatrix || throw(ArgumentError(
            "chain_initials must be a chains-by-parameters matrix",
        ))
        matrix = try
            Matrix{Float64}(supplied_chain_initials)
        catch
            throw(ArgumentError(
                "chain_initials must contain values convertible to Float64",
            ))
        end
        size(matrix) == (controls.chains, candidate.blueprint.n_parameters) ||
            throw(ArgumentError(
                "chain_initials has size $(size(matrix)); expected " *
                "($(controls.chains), $(candidate.blueprint.n_parameters))",
            ))
        zrho_starts = copy(@view matrix[:, candidate.blueprint.zrho_index])
        rho_starts = tanh.(zrho_starts)
        if mode === :scientific
            minimum(rho_starts) < 0 < maximum(rho_starts) || throw(ArgumentError(
                "scientific chain_initials must disperse zrho starts across zero",
            ))
            length(unique(rho_starts)) == controls.chains || throw(ArgumentError(
                "scientific chain_initials must use distinct zrho starts",
            ))
        end
        matrix, (;
            rho = rho_starts,
            zrho = zrho_starts,
        )
    end
    resolved_chain_initials === nothing || iszero(init_jitter) ||
        throw(ArgumentError(
            "init_jitter must be zero when pilot chain_initials are explicit",
        ))

    sample_bundle = _mgmfrm_free_latent_correlation_2d_sample_bundle(
        candidate,
        initial;
        ndraws = controls.ndraws,
        warmup = controls.warmup,
        chains = controls.chains,
        step_size,
        seed = sampler_seed,
        target_accept,
        max_depth,
        max_energy_error,
        metric,
        ad_backend,
        init_jitter,
        chain_initials = resolved_chain_initials,
        progress,
    )
    chain_layout = _free_correlation_chain_layout(
        sample_bundle,
        controls.chains,
        controls.ndraws,
    )
    chain_layout.passed || throw(ArgumentError(
        "sample bundle did not preserve chain-major draw metadata",
    ))
    if resolved_chain_initials !== nothing
        sample_bundle.chain_initials == resolved_chain_initials ||
            throw(ArgumentError(
                "sample bundle did not preserve the requested chain initials",
            ))
    end

    raw_parameter_rows = _candidate_mcmc_diagnostic_rows(
        sample_bundle.draws,
        copy(candidate.blueprint.parameter_names),
        controls.chains;
        parameter_space = :raw_unconstrained,
        split_chains,
        rhat_threshold = diagnostic_thresholds.rhat_threshold,
        ess_threshold = diagnostic_thresholds.ess_threshold,
    )
    raw_block_rows = _candidate_parameter_block_diagnostics(
        candidate.blueprint.blocks,
        copy(candidate.blueprint.parameter_names),
        raw_parameter_rows;
        parameter_space = :raw_unconstrained,
        chains = controls.chains,
        draws_per_chain = controls.ndraws,
        total_draws = controls.chains * controls.ndraws,
        split_chains,
        rhat_threshold = diagnostic_thresholds.rhat_threshold,
        ess_threshold = diagnostic_thresholds.ess_threshold,
    )
    direct_names = copy(candidate.base.blueprint.constrained_parameter_names)
    structurally_fixed_direct_parameters =
        _structurally_fixed_constrained_parameter_names(
            candidate.base.blueprint,
        )
    direct_parameter_rows = _candidate_mcmc_diagnostic_rows(
        sample_bundle.direct_draws,
        direct_names,
        controls.chains;
        parameter_space = :constrained_direct,
        structurally_fixed_parameters =
            structurally_fixed_direct_parameters,
        split_chains,
        rhat_threshold = diagnostic_thresholds.rhat_threshold,
        ess_threshold = diagnostic_thresholds.ess_threshold,
    )
    direct_block_rows = _candidate_parameter_block_diagnostics(
        candidate.base.blueprint.constrained_blocks,
        direct_names,
        direct_parameter_rows;
        parameter_space = :constrained_direct,
        chains = controls.chains,
        draws_per_chain = controls.ndraws,
        total_draws = controls.chains * controls.ndraws,
        split_chains,
        rhat_threshold = diagnostic_thresholds.rhat_threshold,
        ess_threshold = diagnostic_thresholds.ess_threshold,
    )
    rho_name = only(candidate.blueprint.derived_parameter_names)
    rho_parameter_rows = _candidate_mcmc_diagnostic_rows(
        reshape(sample_bundle.rho_draws, :, 1),
        [rho_name],
        controls.chains;
        parameter_space = :derived_correlation,
        split_chains,
        rhat_threshold = diagnostic_thresholds.rhat_threshold,
        ess_threshold = diagnostic_thresholds.ess_threshold,
    )
    rho_diagnostic = only(rho_parameter_rows)
    rho_blocks = Dict{Symbol,UnitRange{Int}}(:latent_correlation => 1:1)
    rho_block_rows = _candidate_parameter_block_diagnostics(
        rho_blocks,
        [rho_name],
        rho_parameter_rows;
        parameter_space = :derived_correlation,
        chains = controls.chains,
        draws_per_chain = controls.ndraws,
        total_draws = controls.chains * controls.ndraws,
        split_chains,
        rhat_threshold = diagnostic_thresholds.rhat_threshold,
        ess_threshold = diagnostic_thresholds.ess_threshold,
    )
    e_bfmi = _ebfmi_coverage(sample_bundle.sampler_rows)

    raw_recovery_rows = _parameter_recovery_rows(
        copy(candidate.blueprint.parameter_names),
        candidate.blueprint.blocks,
        sample_bundle.draws,
        checked_fixture.truth.candidate_raw_parameter_values;
        interval = checked_interval,
        metadata = _free_correlation_recovery_metadata(:raw_unconstrained),
    )
    direct_recovery_base = parameter_recovery(
        candidate.base.design,
        sample_bundle.direct_draws,
        checked_fixture.truth.direct_parameter_values;
        interval = checked_interval,
        parameter_space = :direct,
    )
    direct_metadata = _free_correlation_recovery_metadata(:constrained_direct)
    direct_recovery_rows = [
        merge(row, direct_metadata) for row in direct_recovery_base
    ]
    direct_recovery_by_block = parameter_recovery_summary(
        direct_recovery_rows;
        by = :block,
    )
    rho_recovery = only(_parameter_recovery_rows(
        [rho_name],
        rho_blocks,
        reshape(sample_bundle.rho_draws, :, 1),
        [checked_fixture.truth.population_rho];
        interval = checked_interval,
        metadata = _free_correlation_recovery_metadata(:derived_correlation),
    ))
    positive_probability = count(>(0), sample_bundle.rho_draws) /
        length(sample_bundle.rho_draws)
    negative_probability = count(<(0), sample_bundle.rho_draws) /
        length(sample_bundle.rho_draws)
    truth_sign_probability = checked_fixture.truth.population_rho > 0 ?
        positive_probability : checked_fixture.truth.population_rho < 0 ?
        negative_probability : missing
    direction_matches_truth = iszero(checked_fixture.truth.population_rho) ?
        missing : sign(rho_recovery.posterior_median) ==
            sign(checked_fixture.truth.population_rho)

    all_diagnostic_rows = vcat(
        raw_parameter_rows,
        direct_parameter_rows,
        rho_parameter_rows,
    )
    diagnostic_metrics = _mcmc_metric_summary(
        all_diagnostic_rows,
        diagnostic_thresholds.rhat_threshold,
        diagnostic_thresholds.ess_threshold,
    )
    n_divergences = sum(
        ismissing(row.n_divergences) ? 0 : Int(row.n_divergences)
        for row in sample_bundle.sampler_rows;
        init = 0,
    )
    n_max_treedepth = sum(
        ismissing(row.n_max_treedepth) ? 0 : Int(row.n_max_treedepth)
        for row in sample_bundle.sampler_rows;
        init = 0,
    )
    diagnostics_passed = all(
        row -> !row.quality_gate_applicable || row.flag === :ok,
        all_diagnostic_rows,
    ) &&
        e_bfmi.e_bfmi_complete && !ismissing(e_bfmi.e_bfmi) &&
        e_bfmi.e_bfmi >= checked_e_bfmi && n_divergences == 0 &&
        n_max_treedepth == 0
    scientific_gate_applicable = mode === :scientific
    scientific_gate_passed = scientific_gate_applicable &&
        sample_bundle.summary.passed && chain_layout.passed &&
        diagnostics_passed && rho_recovery.covered &&
        (ismissing(direction_matches_truth) || direction_matches_truth)
    single_dataset_gate = (;
        applicable = scientific_gate_applicable,
        status = !scientific_gate_applicable ?
            :not_evaluable_diagnostic_smoke :
            (scientific_gate_passed ? :passed : :failed),
        passed = scientific_gate_passed,
        execution_passed = sample_bundle.summary.passed,
        chain_layout_passed = chain_layout.passed,
        diagnostics_passed,
        rho_truth_in_90_percent_interval = rho_recovery.covered,
        direction_matches_truth,
        thresholds = (;
            rhat = diagnostic_thresholds.rhat_threshold,
            bulk_tail_ess = diagnostic_thresholds.ess_threshold,
            min_e_bfmi = checked_e_bfmi,
            n_divergences = 0,
            n_max_treedepth = 0,
            interval = checked_interval,
        ),
        claim_scope = :single_dataset_gate_not_replicated_recovery,
    )
    return (;
        schema = _FREE_CORRELATION_PILOT_SCHEMA,
        family = :mgmfrm,
        scope = :mgmfrm_2d_free_latent_correlation_candidate,
        status = mode === :scientific ?
            :internal_single_dataset_scientific_pilot :
            :internal_diagnostic_smoke,
        mode,
        claim_scope = :single_dataset_response_recovery_pilot_not_replicated_recovery,
        public_fit = false,
        fit_ready = false,
        cache_enabled = false,
        promotion_effect = :none,
        result_type = :named_tuple_only,
        convergence_evaluated = mode === :scientific,
        recovery_verified = false,
        fixture = checked_fixture,
        sampler_seed,
        controls = merge(controls, (;
            step_size = Float64(step_size),
            target_accept = Float64(target_accept),
            max_depth,
            max_energy_error = Float64(max_energy_error),
            metric,
            ad_backend,
            init_jitter = Float64(init_jitter),
            split_chains,
            rho_initial_starts = copy(initial_starts.rho),
            zrho_initial_starts = copy(initial_starts.zrho),
        )),
        sample_bundle,
        chain_layout,
        diagnostics = (;
            contract = _mcmc_diagnostic_contract_record(),
            raw_parameter_rows,
            raw_block_rows,
            direct_parameter_rows,
            direct_block_rows,
            structurally_fixed_direct_parameters,
            rho_row = rho_diagnostic,
            rho_block_rows,
            e_bfmi,
            metrics = diagnostic_metrics,
            n_divergences,
            n_max_treedepth,
            known_truth_likelihood_identity =
                checked_fixture.likelihood_identity,
        ),
        recovery = (;
            interval = checked_interval,
            raw_rows = raw_recovery_rows,
            rho_row = rho_recovery,
            direct_rows = direct_recovery_rows,
            direct_by_block = direct_recovery_by_block,
            sign_probabilities = (;
                positive = positive_probability,
                negative = negative_probability,
                truth_sign = truth_sign_probability,
                direction_matches_truth,
            ),
        ),
        single_dataset_gate,
        summary = (;
            execution_passed = sample_bundle.summary.passed,
            chain_layout_passed = chain_layout.passed,
            diagnostics_passed,
            rho_truth = checked_fixture.truth.population_rho,
            realized_latent_correlation =
                checked_fixture.truth.realized_latent_correlation,
            rho_posterior_median = rho_recovery.posterior_median,
            rho_truth_in_interval = rho_recovery.covered,
            truth_sign_probability,
            single_dataset_gate_passed = scientific_gate_passed,
            diagnostic_wiring_complete = chain_layout.passed &&
                length(raw_parameter_rows) == size(sample_bundle.draws, 2) &&
                length(direct_parameter_rows) ==
                    size(sample_bundle.direct_draws, 2) &&
                length(rho_parameter_rows) == 1,
            recovery_claimed = false,
            recovery_verified = false,
        ),
        next_gate = :replicated_known_truth_correlation_recovery,
    )
end
