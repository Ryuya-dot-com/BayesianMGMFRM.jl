function _equation_sources(family::Symbol, thresholds::Symbol)
    if family === :mfrm
        source = thresholds === :rating_scale ?
            "Uto and Ueno (2020), Eq. 6, with Andrich (1978) rating-scale lineage" :
            "Masters (1982) partial-credit model with Uto and Ueno (2020), Eq. 3, GPCM/PCM decomposition"
        return [source]
    elseif family === :gmfrm
        return ["Uto and Ueno (2020), Behaviormetrika 47, Eq. 9 and identification restrictions"]
    elseif family === :mgmfrm
        return ["Uto (2021), Behaviormetrika 48, Eq. 6 and identification restrictions"]
    end
    return String[]
end

function _equation_source_urls(family::Symbol, thresholds::Symbol)
    if family === :mfrm
        return thresholds === :partial_credit ?
            ["https://doi.org/10.1007/BF02296272", "https://doi.org/10.1007/s41237-020-00115-7"] :
            ["https://doi.org/10.1007/BF02293814", "https://doi.org/10.1007/s41237-020-00115-7"]
    elseif family === :gmfrm
        return ["https://doi.org/10.1007/s41237-020-00115-7"]
    elseif family === :mgmfrm
        return ["https://doi.org/10.1007/s41237-021-00144-w"]
    end
    return String[]
end

function _equation_kernel(spec::FacetSpec)
    _is_mfrm_fixed_q(spec) && return "eta[1] = 0; eta[k] = sum_{m=2}^{k} (sum_d Q[i,d] * theta[p,d] - beta_i[i] - beta_r[r] - d[i,m]); d[i,1] = 0"
    if spec.family === :mfrm
        return spec.thresholds === :rating_scale ?
            "eta[k] = (k - 1) * (theta[p] - beta_r[r] - beta_i[i]) - sum_{m=1}^{k-1} d[m]" :
            "eta[k] = (k - 1) * (theta[p] - beta_r[r] - beta_i[i]) - sum_{m=1}^{k-1} d[i,m]"
    elseif spec.family === :gmfrm
        return "eta[k] = sum_{m=1}^{k} alpha_r[r] * alpha_i[i] * (theta[p] - beta_i[i] - beta_r[r] - d[r,m])"
    elseif spec.family === :mgmfrm
        return "eta[k] = sum_{m=1}^{k} 1.7 * alpha_r[r] * (sum_l alpha_i_l[i,l] * theta[p,l] - beta_i[i] - beta_r[r] - d[i,m])"
    end
    return ""
end

function _equation_required_blocks(spec::FacetSpec)
    _is_mfrm_fixed_q(spec) && return (:person_location_by_dimension, :rater_severity,
        :item_difficulty, :item_step, :fixed_q_coefficients, :fixed_rater_consistency)
    if spec.family === :mfrm
        return (:person_location, :rater_severity, :item_difficulty, :threshold_steps)
    elseif spec.family === :gmfrm
        return (
            :person_location,
            :rater_severity,
            :item_difficulty,
            :item_discrimination,
            :rater_consistency,
            :rater_step,
        )
    elseif spec.family === :mgmfrm
        return (
            :person_location_by_dimension,
            :rater_severity,
            :item_difficulty,
            :item_dimension_discrimination,
            :rater_consistency,
            :item_step,
        )
    end
    return Symbol[]
end

function _equation_identification(spec::FacetSpec)
    _is_mfrm_fixed_q(spec) && return (:prior_anchored_person_and_item_locations,
        :sum_rater_severity_equals_zero, :item_first_step_fixed_zero,
        :item_step_sum_to_zero, :fixed_q_coefficients, :unit_rater_consistency,
        :identity_latent_correlation)
    if spec.family === :mfrm
        return (
            :location_constraint_on_rater_and_item_blocks,
            :threshold_sum_to_zero,
            :ability_location_scale_set_by_parameterization_or_prior,
        )
    elseif spec.family === :gmfrm
        return (
            :prod_item_discrimination_equals_one,
            :sum_item_difficulty_equals_zero,
            :rater_first_step_fixed_zero,
            :rater_step_sum_to_zero,
            :ability_distribution_sets_location_and_scale,
        )
    elseif spec.family === :mgmfrm
        return (
            :prod_rater_consistency_equals_one,
            :sum_rater_severity_equals_zero,
            :item_first_step_fixed_zero,
            :item_step_sum_to_zero,
            :standard_normal_ability_prior_by_dimension,
            :dimension_order_or_loading_gauge_required,
        )
    end
    return Symbol[]
end

function _equation_implementation_gaps(spec::FacetSpec)
    _is_mfrm_fixed_q(spec) && return [:automatic_request_caching]
    gaps = Symbol[]
    spec.family === :mfrm && return gaps
    if spec.family === :gmfrm
        append!(gaps, (
            :identified_transform_for_item_discrimination_product_constraint,
            :identified_transform_for_rater_step_constraints,
            :literature_gmfrm_likelihood_kernel,
            :source_matched_fixture_tests,
        ))
    elseif spec.family === :mgmfrm
        append!(gaps, (
            :identified_transform_for_rater_consistency_product_constraint,
            :identified_transform_for_item_step_constraints,
            :multidimensional_ability_prior_and_gauge,
            :literature_mgmfrm_likelihood_kernel,
            :source_matched_fixture_tests,
        ))
    end
    return gaps
end

"""
    model_equation(spec_or_design)

Return a source-traced mathematical contract for the specification. The result
records the intended likelihood family, a compact adjacent-category logit
kernel, primary-source references, required parameter blocks, identification
restrictions, and implementation gaps.

For GMFRM/MGMFRM specifications, `fit_ready` continues to describe the stable
compiler route and remains `false`. `experimental_fit_available` separately
records whether the documented limited configuration can be executed through
[`BayesianMGMFRM.Experimental.fit`](@ref). The implementation-gap rows retain
the broader literature-alignment work that is outside that limited route;
`implementation_gap_scope` identifies that stable-compiler and broader-model
boundary explicitly.
"""
function model_equation(spec::FacetSpec)
    _is_mfrm_fixed_q(spec) && _require_current_facet_spec(spec, "model_equation")
    implementation_gaps = _equation_implementation_gaps(spec)
    experimental_fit_available = _is_mfrm_fixed_q(spec) || _experimental_generalized_fit_supported(spec)
    return (;
        schema = "bayesianmgmfrm.model_equation.v1",
        family = spec.family,
        scope = _spec_scope(spec),
        thresholds = spec.thresholds,
        dimensions = spec.dimensions,
        dimension_labels = copy(spec.dimension_labels),
        discrimination = spec.discrimination,
        estimation_status = spec.estimation_status,
        probability_form = :adjacent_category_softmax,
        category_indexing = :one_based_with_observed_integer_scores,
        kernel = _equation_kernel(spec),
        primary_sources = _equation_sources(spec.family, spec.thresholds),
        source_urls = _equation_source_urls(spec.family, spec.thresholds),
        required_blocks = _equation_required_blocks(spec),
        identification = _equation_identification(spec),
        implementation_gaps,
        implementation_gap_scope = _is_mfrm_fixed_q(spec) ? :experimental_workflow : spec.family === :mfrm ?
            :none : :stable_compiler_and_broader_scope,
        fit_ready = spec.estimation_status === :fit_supported &&
            isempty(implementation_gaps),
        experimental_fit_available,
        experimental_fit_entrypoint =
            experimental_fit_available ?
            "BayesianMGMFRM.Experimental.fit(spec)" : nothing,
    )
end

model_equation(design::FacetDesign) = model_equation(design.spec)

function _constraint_rows(;
        family::Symbol,
        thresholds::Symbol,
        dimensions::Int,
        dimension_labels = _default_dimension_labels(dimensions),
        discrimination::Symbol,
        q_matrix,
        validation_bias_terms,
        anchors,
        estimation_status::Symbol)
    _is_mfrm_fixed_q(family, dimensions) && return _mfrm_fixed_q_constraints()
    implemented = estimation_status === :fit_supported ? :implemented : :specified_only
    rows = NamedTuple[]
    if family === :mfrm
        anchored_blocks = Set(
            _stable_anchor_block(anchor.block)
            for anchor in anchors
            if anchor.anchor_type === :hard_anchor
        )
        append!(rows, NamedTuple[
            (;
                block = :person,
                constraint = dimensions == 1 ? :free : :latent_location_by_dimension,
                transform = :identity,
                status = implemented,
                note = "person latent location parameters",
            ),
            (;
                block = :rater,
                constraint = :rater in anchored_blocks ? :free_with_hard_anchors : :reference_first,
                transform = :rater in anchored_blocks ? :fixed_coordinate_selection : :identity,
                status = implemented,
                note = :rater in anchored_blocks ?
                    "declared rater levels fixed exactly; all other rater severities remain free" :
                    "first rater severity fixed to zero",
            ),
            (;
                block = :item,
                constraint = :item in anchored_blocks ? :free_with_hard_anchors : :reference_first,
                transform = :item in anchored_blocks ? :fixed_coordinate_selection : :identity,
                status = implemented,
                note = :item in anchored_blocks ?
                    "declared item levels fixed exactly; all other item difficulties remain free" :
                    "first item difficulty fixed to zero",
            ),
            (;
                block = :thresholds,
                constraint = :sum_to_zero,
                transform = thresholds === :rating_scale ? :shared_steps : :item_steps,
                status = implemented,
                note = "last threshold step derived by a sum-to-zero constraint",
            ),
        ])
    elseif family === :gmfrm
        append!(rows, NamedTuple[
            (;
                block = :person,
                constraint = :ability_distribution_location_scale,
                transform = :identity,
                status = :specified_only,
                note = "person latent locations; ability distribution supplies location and scale in the source model",
            ),
            (;
                block = :rater,
                constraint = :free_given_item_location_constraint,
                transform = :identity,
                status = :specified_only,
                note = "rater severity beta_r in Uto and Ueno (2020), Eq. 9",
            ),
            (;
                block = :item,
                constraint = :sum_to_zero,
                transform = :identity,
                status = :specified_only,
                note = "item/task difficulty beta_i with sum_i beta_i = 0",
            ),
            (;
                block = :item_discrimination,
                constraint = :geometric_mean_one,
                transform = :log_link,
                status = :specified_only,
                note = "positive item/task discrimination alpha_i with product_i alpha_i = 1",
            ),
            (;
                block = :rater_consistency,
                constraint = :positive,
                transform = :log_link,
                status = :specified_only,
                note = "positive rater consistency alpha_r",
            ),
            (;
                block = :rater_steps,
                constraint = :first_step_zero_sum_to_zero,
                transform = :rater_category_steps,
                status = :specified_only,
                note = "rater-specific category-use steps d_rm with d_r1 = 0 and sum_{m=2}^K d_rm = 0",
            ),
        ])
    elseif family === :mgmfrm
        append!(rows, NamedTuple[
            (;
                block = :person,
                constraint = :standard_normal_by_dimension,
                transform = :identity,
                status = :specified_only,
                dimension_labels = Tuple(dimension_labels),
                note = "multidimensional person locations theta_jl with source-model standard normal ability prior",
            ),
            (;
                block = :rater,
                constraint = :sum_to_zero,
                transform = :identity,
                status = :specified_only,
                note = "rater severity beta_r with sum_r beta_r = 0",
            ),
            (;
                block = :item,
                constraint = :free_given_ability_and_rater_constraints,
                transform = :identity,
                status = :specified_only,
                note = "item/evaluation difficulty beta_i in Uto (2021), Eq. 6",
            ),
            (;
                block = :item_dimension_discrimination,
                constraint = :confirmatory_q_mask,
                transform = :log_link,
                status = :specified_only,
                dimension_labels = Tuple(dimension_labels),
                note = "positive item-by-dimension discrimination alpha_il under the fixed Q-mask",
            ),
            (;
                block = :rater_consistency,
                constraint = :geometric_mean_one,
                transform = :log_link,
                status = :specified_only,
                note = "positive rater consistency alpha_r with product_r alpha_r = 1",
            ),
            (;
                block = :item_steps,
                constraint = :first_step_zero_sum_to_zero,
                transform = :item_category_steps,
                status = :specified_only,
                note = "item-specific category-use steps d_im with d_i1 = 0 and sum_{m=2}^K d_im = 0",
            ),
        ])
    end
    if family === :mgmfrm
        q_matrix === nothing || push!(rows, (;
            block = :q_matrix,
            constraint = :fixed_mask,
            transform = :none,
            status = :specified_only,
            dimension_labels = Tuple(dimension_labels),
            note = "fixed $(size(q_matrix, 1)) by $(size(q_matrix, 2)) item-dimension mask",
        ))
    end
    for term in validation_bias_terms
        push!(rows, (;
            block = Symbol("dff_", term[1], "_", term[2]),
            constraint = :validation_only,
            transform = :none,
            status = :validation_only,
            note = "DFF/bias term validated for sparse cells but not included in the fitted likelihood",
        ))
    end
    for anchor in anchors
        anchor_type = haskey(anchor, :anchor_type) ? anchor.anchor_type : _normalize_anchor_type(anchor)
        anchor_scale = haskey(anchor, :anchor_scale) ? anchor.anchor_scale : _anchor_scale(anchor)
        anchor_target = _anchor_target(anchor)
        anchor_status = estimation_status === :fit_supported &&
            family === :mfrm && anchor_type === :hard_anchor ?
            :implemented : :specified_only
        push!(rows, (;
            block = _stable_anchor_block(anchor.block) in (:rater, :item) ?
                _stable_anchor_block(anchor.block) : anchor.block,
            constraint = anchor_type,
            transform = anchor_type === :soft_anchor ? :soft_anchor_prior : :fixed_value,
            status = anchor_status,
            anchor_target,
            anchor_value = anchor.value,
            anchor_scale,
            note = anchor_type === :soft_anchor ?
                "soft anchor declared in specification; fitting support is planned" :
                anchor_status === :implemented ?
                    "hard anchor applied as an exact fixed coordinate" :
                    "hard anchor declared in specification; fitting support is unavailable for this declaration",
        ))
    end
    return rows
end

function _prior_rows(family::Symbol, dimensions::Int, discrimination::Symbol)
    _is_mfrm_fixed_q(family, dimensions) && return _mfrm_fixed_q_prior_rows()
    rows = NamedTuple[
        (block = :person, prior = :normal, parameters = (location = 0.0, scale = :person_sd), status = :implemented),
        (block = :rater, prior = :normal, parameters = (location = 0.0, scale = :rater_sd), status = :implemented),
        (block = :item, prior = :normal, parameters = (location = 0.0, scale = :item_sd), status = :implemented),
        (block = :thresholds, prior = :normal, parameters = (location = 0.0, scale = :step_sd), status = :implemented),
    ]
    if family === :gmfrm
        push!(rows,
            (block = :item_discrimination, prior = :lognormal_or_hierarchical, parameters = (center = 1.0,), status = :specified_only),
            (block = :rater_consistency, prior = :lognormal_or_hierarchical, parameters = (center = 1.0,), status = :specified_only),
            (block = :rater_steps, prior = :normal, parameters = (location = 0.0, scale = :step_sd), status = :specified_only))
    elseif family === :mgmfrm
        push!(rows,
            (block = :item_dimension_discrimination, prior = :lognormal_or_hierarchical, parameters = (center = 1.0,), status = :specified_only),
            (block = :rater_consistency, prior = :lognormal_or_hierarchical, parameters = (center = 1.0,), status = :specified_only),
            (block = :item_steps, prior = :normal, parameters = (location = 0.0, scale = :step_sd), status = :specified_only))
    end
    return rows
end

"""
    mfrm_spec(data::FacetData; thresholds = :partial_credit,
              family = :mfrm, dimensions = 1, discrimination = :none,
              q_matrix = nothing, dimension_labels = nothing,
              bias = Tuple{Symbol,Symbol}[], anchors = NamedTuple[], min_cell_count = 2,
              validation_report = nothing)

Describe which model to fit after resolving blocking data-validation errors.
Return a `FacetSpec`; this function does not estimate parameters or run MCMC.
The default is a one-dimensional MFRM with item-specific partial-credit steps.
`thresholds = :rating_scale` instead shares the step offsets across items.

# Examples

Using `data` from the complete example in [`FacetData`](@ref):

```julia
spec = mfrm_spec(data; thresholds = :partial_credit)
model_equation(spec)
constraint_table(spec)
```

The equation and constraints describe the model you requested. Inspect its
priors before fitting. Use [`fit`](@ref) for stable one-dimensional MFRM and
[`BayesianMGMFRM.Experimental.fit`](@ref) for admitted models.
Constructing a specification does not mean that every configuration is fit-supported.

Display `spec` to check the model meaning before fitting. `family` selects the
response model even though this constructor retains the name `mfrm_spec`.
The MGMFRM selector `discrimination = :none` still estimates positive active
item-dimension loadings and rater consistency; GMFRM's `:rater` selector also
estimates item discrimination. These are compatibility selectors, not a list of
all estimated slopes. `bias` requests cell/design checks only: it does not add
fitted interactions. For jointly fitted rater-item effects, see the separate
`BayesianMGMFRM.Experimental.RaterItemInteractions` model and its restrictions.

# Extended help

The default `family = :mfrm`, `dimensions = 1`, and
`discrimination = :none` path is the minimal MFRM/RSM/PCM slice supported by
`getdesign` and `fit`, including valid exact individual rater/item hard
anchors. Multidimensional MFRM with explicit Q and named dimensions supports
partial-credit specification and `getdesign(spec; preview = true)` inspection.
Estimate its fixed-coefficient unit-logit model through
`BayesianMGMFRM.Experimental.fit`, using Julia or CmdStan and `MFRMPrior`.
For a one-dimensional comparison using the MGMFRM equation, explicitly set
`family=:mgmfrm, dimensions=1, q_matrix=trues(n_items, 1)` with partial-credit
thresholds. This retains item-owned steps and the 1.7 scale constant; it is not
the rater-step scalar GMFRM. Use the same explicit normalized prior form and
scales in matched-dimensional comparisons, and inspect the full model contract.
GMFRM/MGMFRM configurations can be represented for
manifest and constraint review with `estimation_status = :specified_only`.
The guarded generalized numerical path is narrower than this representation
surface: it requires `thresholds = :partial_credit`, no anchors or fitted DFF
terms, and the family-specific discrimination/Q contract documented by
[`fit`](@ref). Other specified-only configurations remain inspection-only and
are rejected before numerical evaluation.
"""
function _facet_data_to_mrcml(data::FacetData;
        thresholds::Symbol,
        anchors::Vector{NamedTuple},
        prior::Symbol,
        intercept)
    facets = data.columns.rater === nothing ? (item = :item,) : (item = :item, rater = :rater)
    facet_levels = data.columns.rater === nothing ?
        (item = data.item_levels,) : (item = data.item_levels, rater = data.rater_levels)
    table = (person = data.person_levels[data.person], item = data.item_levels[data.item], score = data.score)
    if data.columns.rater !== nothing
        table = merge(table, (rater = data.rater_levels[data.rater],))
    end
    assessment = nothing
    if haskey(data.optional, :response_id)
        table = merge(table, (response_id = data.optional_levels[:response_id][data.optional[:response_id]],))
        assessment = :response_id
    else
        cells = data.columns.rater === nothing ?
            Tuple{Int,Int}[(data.person[i], data.item[i]) for i in 1:data.n] :
            Tuple{Int,Int,Int}[(data.person[i], data.item[i], data.rater[i]) for i in 1:data.n]
        if length(unique(cells)) < data.n
            table = merge(table, (row_id = collect(1:data.n),))
            assessment = :row_id
        end
    end
    fixed_cal = if isempty(anchors)
        nothing
    else
        combined = Dict{Symbol,Dict{Any,Any}}()
        for anchor in anchors
            role = _stable_anchor_block(anchor.block)
            role in (:rater, :item) && anchor.anchor_type === :hard_anchor && ismissing(anchor.anchor_scale) ||
                throw(ArgumentError("only hard rater and item location anchors can be converted to fixed_calibration"))
            level = _anchor_target(anchor)
            dict = get!(combined, role, Dict{Any,Any}())
            haskey(dict, level) && dict[level] != anchor.value &&
                throw(ArgumentError("conflicting anchor values for $role level $(repr(level))"))
            dict[level] = anchor.value
        end
        (; facets = (; combined...))
    end
    steps_owner = (thresholds === :rating_scale || length(data.category_levels) <= 2) ? :global : :item
    levels = (person = data.person_levels, facets = facet_levels)
    ma = hasproperty(data.columns, :missing_audit) ? deepcopy(data.columns.missing_audit) : nothing
    return mfrm_spec(table;
        person = :person,
        score = :score,
        facets,
        steps = steps_owner,
        category_levels = data.category_levels,
        levels,
        fixed_calibration = fixed_cal,
        prior,
        intercept,
        assessment,
        missing_audit = ma)
end

function mfrm_spec(data::FacetData;
        thresholds::Symbol = :partial_credit,
        family::Symbol = :mfrm,
        dimensions::Union{Nothing, Int} = nothing,
        discrimination::Symbol = :none,
        q_matrix = nothing,
        dimension_labels = nothing,
        bias = Tuple{Symbol,Symbol}[],
        anchors = NamedTuple[],
        min_cell_count::Int = 2,
        validation_report::Union{Nothing,ValidationReport} = nothing,
        prior = nothing,
        identification::Union{Nothing,Symbol} = nothing,
        intercept = nothing,
        kwargs...)
    identification in (nothing, :isometric, :reference) ||
        throw(ArgumentError("identification must be :isometric or :reference; got $(repr(identification))"))
    if prior === nothing && (identification === nothing || identification === :reference) && isempty(kwargs)
        intercept === nothing ||
            throw(ArgumentError("intercept on FacetData requires `prior = :default` / `identification = :isometric`"))
    else
        identification === :reference &&
            throw(ArgumentError("`identification = :reference` returns a legacy FacetSpec and requires `prior = nothing`"))
        if family in (:gmfrm, :mgmfrm) || !isempty(kwargs)
            return _facet_data_to_generalized_target(data;
                thresholds, family, dimensions, discrimination, q_matrix, dimension_labels,
                bias, anchors, validation_report, prior, identification, intercept, kwargs...)
        end
        eff_prior = prior === nothing ? :default : prior
        eff_prior in (:default, :none) ||
            throw(ArgumentError("unsupported `prior = $(repr(eff_prior))` on FacetData; expected `:default`, `:none`, or `nothing`"))
        thresholds in (:rating_scale, :partial_credit) ||
            throw(ArgumentError("thresholds must be :rating_scale or :partial_credit"))
        eff_dims_1d = something(dimensions, 1)
        family === :mfrm && eff_dims_1d == 1 && discrimination === :none &&
            q_matrix === nothing && dimension_labels === nothing && isempty(bias) ||
            throw(ArgumentError("`prior = $(repr(eff_prior))` / `identification = :isometric` on FacetData applies to scalar 1D unit-slope MFRM without Q or DFF"))
        checked_anchors = _normalize_anchors(anchors)
        if data.columns.rater === nothing && any(a -> _stable_anchor_block(a.block) === :rater, checked_anchors)
            throw(ArgumentError("rater anchors require an observed rater facet"))
        end
        return _facet_data_to_mrcml(data; thresholds, anchors = checked_anchors, prior = eff_prior, intercept)
    end
    thresholds in (:rating_scale, :partial_credit) ||
        throw(ArgumentError("thresholds must be :rating_scale or :partial_credit"))
    checked_family = _check_family(family)
    checked_dimensions = _check_dimensions(checked_family, something(dimensions, 1))
    checked_dimension_labels =
        _normalize_dimension_labels(checked_dimensions, dimension_labels)
    checked_discrimination = _check_discrimination(checked_family, discrimination)
    if data.columns.rater === nothing
        checked_family === :mfrm && checked_dimensions == 1 ||
            throw(ArgumentError("rater = nothing supports scalar unit-slope Rasch/PCM/RSM only"))
    end
    report = validation_report === nothing ?
        validate_design(data; bias, min_cell_count) :
        validation_report
    report.n == data.n ||
        throw(ArgumentError("validation_report has n = $(report.n); expected $(data.n)"))
    report.data_signature == _data_signature(data) ||
        throw(ArgumentError("validation_report was produced for different FacetData"))
    if validation_report !== nothing && !_is_default_validation_request(bias, min_cell_count)
        report.options_signature == _validation_options_signature(bias, min_cell_count) ||
            throw(ArgumentError("validation_report was produced with different validation options"))
    end
    if !report.passed
        throw(_facet_spec_validation_error(data, report))
    end
    checked_q_matrix = _normalize_q_matrix(
        data,
        checked_family,
        checked_dimensions,
        q_matrix,
        checked_dimension_labels,
    )
    checked_bias_terms = _normalize_bias_terms(bias, report)
    checked_anchors = _normalize_anchors(anchors)
    if data.columns.rater === nothing
        any(term -> :rater in term, checked_bias_terms) &&
            throw(ArgumentError("rater bias terms require an observed rater facet"))
        any(anchor -> _stable_anchor_block(anchor.block) === :rater, checked_anchors) &&
            throw(ArgumentError("rater anchors require an observed rater facet"))
    end
    _check_mfrm_fixed_q_options(checked_family, checked_dimensions, thresholds,
        checked_discrimination, checked_bias_terms, checked_anchors)
    estimation_status = _estimation_status(
        checked_family,
        checked_dimensions,
        checked_discrimination,
        checked_q_matrix,
        checked_anchors,
        data,
    )
    constraints = _constraint_rows(;
        family = checked_family,
        thresholds,
        dimensions = checked_dimensions,
        dimension_labels = checked_dimension_labels,
        discrimination = checked_discrimination,
        q_matrix = checked_q_matrix,
        validation_bias_terms = checked_bias_terms,
        anchors = checked_anchors,
        estimation_status,
    )
    prior_blocks = _prior_rows(checked_family, checked_dimensions, checked_discrimination)
    return FacetSpec(
        data,
        thresholds,
        report,
        checked_family,
        checked_dimensions,
        checked_dimension_labels,
        checked_discrimination,
        checked_q_matrix,
        checked_bias_terms,
        checked_anchors,
        constraints,
        prior_blocks,
        estimation_status,
    )
end

function Base.show(io::IO, spec::FacetSpec)
    print(io, "FacetSpec(family = :", spec.family,
        ", thresholds = :", spec.thresholds,
        ", dimensions = ", spec.dimensions,
        ", estimation_status = :", spec.estimation_status,
        ", ", spec.data, ")")
end

function Base.show(io::IO, ::MIME"text/plain", spec::FacetSpec)
    get(io, :compact, false) && return show(io, spec)
    contract = model_family_contract(spec)
    println(io, "FacetSpec: ", uppercase(string(spec.family)), " (", spec.dimensions,
        spec.dimensions == 1 ? " dimension)" : " dimensions)")
    print(io, "  Dimensions: ")
    show(io, spec.dimension_labels)
    println(io, "\n  Ratings: ", spec.data.n, "; people: ", length(spec.data.person_levels),
        "; items: ", length(spec.data.item_levels), "; raters: ",
        spec.data.columns.rater === nothing ? "none (fixed zero reference)" : length(spec.data.rater_levels))
    print(io, "  Categories: ")
    show(io, spec.data.category_levels)
    println(io, "\n  Threshold option: :", spec.thresholds)
    println(io, "  Response: adjacent-category logit; scale multiplier ",
        contract.category.implementation_scale_constant)
    step_owner = contract.steps.owner
    println(io, "  Steps: ", step_owner === :global ? "shared across items and raters" :
        step_owner === :rater ? "rater-specific, shared across items" :
        "item-specific, shared across raters")
    if spec.family === :mgmfrm
        println(io, "  Slopes: positive item-dimension loadings and rater consistency estimated")
        println(io, "  Legacy discrimination=:", spec.discrimination,
            " does not mean fixed slopes.")
    elseif spec.family === :gmfrm
        println(io, "  Slopes: positive item discrimination and rater consistency estimated")
        println(io, "  Legacy discrimination=:", spec.discrimination,
            " is a compatibility selector.")
    else
        println(io, "  Slopes: item coefficients and rater consistency fixed at one")
    end
    if spec.q_matrix !== nothing
        println(io, "  Q: ", size(spec.q_matrix, 1), " items × ", size(spec.q_matrix, 2),
            " dimensions; ", count(spec.q_matrix), " active cells; other coefficients fixed at zero")
    end
    if !isempty(spec.validation_bias_terms)
        println(io, "  Validation-only terms (not fitted interactions): ",
            join((string(a, " × ", b) for (a, b) in spec.validation_bias_terms), ", "))
    end
    println(io, "  Anchor declarations: ", length(spec.anchors),
        "; inspect constraint_table(spec) for their meaning.")
    if spec.family === :mfrm && spec.dimensions == 1 && isempty(spec.anchors)
        print(io, "  Default zero references: item = ")
        show(io, first(spec.data.item_levels))
        if spec.data.columns.rater !== nothing
            print(io, "; rater = ")
            show(io, first(spec.data.rater_levels))
        end
        println(io, " (stored label order, not input row order)")
        if length(spec.data.item_levels) > 1 || length(spec.data.rater_levels) > 1
            println(io, "  MFRMPrior uses free coordinates; changing a reference without transporting the joint prior can change the model.")
        end
    end
    support = contract.support
    if support.fit_available
        println(io, "  Fit entry: ", support.entrypoint,
            support.experimental_fit_available ? " (experimental)" : "")
    else
        println(io, "  Fit entry: unavailable for this specification; inspection only")
    end
    validation_warnings = count(issue -> issue.severity === :warning, spec.validation.issues)
    println(io, "  Design warnings: ", validation_warnings,
        "; Q warnings: ", length(support.warning_checks))
    if validation_warnings > 0 || !isempty(support.warning_checks)
        println(io, "  Read spec.validation.issues and, when Q is present, q_matrix_validation(spec).")
    end
    print(io, "  Select priors and sampler settings explicitly before fitting.")
end
