# Validate declarations and preserve their original error order.
# Calibration receipts are fresh working arrays for this construction only.

function _prepare_structured_mrcml(table, options)
    (;
        person, score, facets, steps, prior_sd, default_prior, category_levels, levels,
        interactions, context_facets, random_effects, lltm, fixed_calibration, calibration,
        intercept, performance, assessment, missing_audit,
    ) = options

    default_prior && prior_sd !== nothing &&
        throw(ArgumentError("cannot combine `prior = :default` with explicit `prior_sd`"))
    is_bayesian = prior_sd !== nothing || default_prior
    reserved = (:person, :steps, :step, :global, :score, :performance, :assessment)
    all(k -> !(k in reserved), keys(facets)) ||
        throw(ArgumentError("facet names cannot use reserved roles $reserved"))
    all(x -> x isa Symbol, values(facets)) ||
        throw(ArgumentError("facet mapping values must be column symbols"))

    facet_names = keys(facets)
    random_effects isa NamedTuple && all(k -> k in facet_names, keys(random_effects)) ||
        throw(ArgumentError("random_effects must be a NamedTuple of declared facet roles and SD priors"))
    isempty(random_effects) || is_bayesian || throw(ArgumentError("iid random effects require Bayesian priors and NUTS"))
    # Validate `steps`: `:global`, single facet `Symbol`, or tuple of >=2 facet `Symbol`s
    if steps === :global || steps isa Symbol
        steps === :global || steps in facet_names ||
            throw(ArgumentError("steps must be :global, a declared facet name, or a tuple of declared facet names"))
    elseif steps isa Tuple && length(steps) >= 2 && all(s -> s isa Symbol && s in facet_names, steps)
        length(unique(steps)) == length(steps) ||
            throw(ArgumentError("tuple `steps = $steps` cannot repeat the same facet"))
    else
        throw(ArgumentError("steps must be :global, a declared facet Symbol, or a Tuple of >= 2 declared facet Symbols; got $(repr(steps))"))
    end

    # Parse LLTM feature specifications
    lltm_nt = lltm === nothing ? (;) : _named(lltm, :lltm)
    all(k -> k in facet_names, keys(lltm_nt)) ||
        throw(ArgumentError("lltm keys $(collect(keys(lltm_nt))) must name declared facets in $facet_names"))
    lltm_cols = Symbol[]
    for (fk, lspec) in pairs(lltm_nt)
        lspec isa NamedTuple && hasproperty(lspec, :features) ||
            throw(ArgumentError("lltm.$fk must be a NamedTuple with `features = (:col1, ...)`"))
        fcols = collect(Symbol, lspec.features)
        !isempty(fcols) && allunique(fcols) ||
            throw(ArgumentError("lltm.$fk.features must be nonempty and distinct"))
        append!(lltm_cols, fcols)
    end

    selected = unique(Symbol[person, score, values(facets)..., lltm_cols...])
    performance !== nothing && !(performance in selected) && push!(selected, performance)
    assessment !== nothing && !(assessment in selected) && push!(selected, assessment)

    # Distinct role columns check for person, score, and facets
    core_roles = Symbol[person, score, values(facets)...]
    length(unique(core_roles)) == length(core_roles) ||
        throw(ArgumentError("person, score, and each facet must use distinct columns"))

    raw = Dict{Symbol,Vector}(c => deepcopy(B._column(table, c)) for c in selected)
    n = length(raw[score])
    n > 0 || throw(ArgumentError("ratings cannot be empty"))
    for c in core_roles
        B._check_length!(n, raw[c], c)
        c == score || _labels(raw[c], c)
    end
    for c in lltm_cols
        B._check_length!(n, raw[c], c)
    end

    if levels !== nothing
        _keys(levels, (:person, :facets), :levels)
        _keys(levels.facets, facet_names, :facet_levels)
    end

    p_idx, p_levels = _labels(raw[person], :person, levels === nothing ? nothing : levels.person)
    P = length(p_levels)

    # Parse person prior SD if Bayesian
    p_sd_val = 1.0
    p_logmean = 0.0
    p_logsd = 1.0
    p_scale_kind = :fixed
    p_is_hyper = false
    if default_prior
        # CR6 evidence-backed default: zero-supporting HalfNormal(1.0) on residual_sd[person]
        # cuts zero-spread midpoint bias by 37% (+0.143 -> +0.090), raises 95% coverage from
        # 92.44% -> 94.36%, achieves lowest RMSE across all 6 x 8,192 benchmark cells, and
        # preserves 0-divergence NUTS sampling at +3-logit ceiling.
        pspec = _parse_scale_or_lognormal(D.truncated(D.Normal(0.0, 1.0), 0.0, Inf), true, :person_sd)
        p_sd_val = pspec.sd
        p_logmean = pspec.logmean
        p_logsd = pspec.logsd
        p_scale_kind = pspec.kind
        p_is_hyper = true
    elseif is_bayesian
        prior_sd isa NamedTuple || throw(ArgumentError("prior_sd must be a NamedTuple"))
        hasproperty(prior_sd, :person) && hasproperty(prior_sd, :facets) && hasproperty(prior_sd, :step) ||
            throw(ArgumentError("prior_sd must specify `person`, `facets`, and `step` (plus optional `interactions`)"))
        allowed_psd_keys = (:person, :facets, :step, :interactions)
        all(k -> k in allowed_psd_keys, keys(prior_sd)) ||
            throw(ArgumentError("unexpected keys in prior_sd: $(setdiff(keys(prior_sd), allowed_psd_keys))"))
        pspec = _parse_scale_or_lognormal(prior_sd.person, true, :person_sd)
        p_sd_val = pspec.sd
        p_logmean = pspec.logmean
        p_logsd = pspec.logsd
        p_scale_kind = pspec.kind
        p_is_hyper = pspec.kind !== :fixed
    end

    # Build facet index metadata
    f_info = NamedTuple[]
    for (fname, fcol) in pairs(facets)
        idx, lev = _labels(raw[fcol], fname, levels === nothing ? nothing : levels.facets[fname])
        push!(f_info, (; name = fname, column = fcol, levels = lev, index = idx))
    end
    f_lookup = Dict(b.name => b for b in f_info)

    # Optional zero-main-effect context factors (e.g. person-level `population.group` participating in `(rater, group)` DFF)
    c_info = NamedTuple[]
    if context_facets !== nothing
        for (cname, cspec) in pairs(_named(context_facets, :context_facets))
            cname in reserved && throw(ArgumentError("context facet $(repr(cname)) cannot use reserved roles $reserved"))
            cname in facet_names && throw(ArgumentError("context facet $(repr(cname)) cannot duplicate a declared main-effect facet"))
            cvals = cspec.values
            B._check_length!(n, cvals, cname)
            cidx, clev = _labels(cvals, cname)
            push!(c_info, (; name = cname, levels = clev, index = cidx,
                reference = get(cspec, :reference, nothing), is_context = true))
        end
    end
    role_lookup = merge(f_lookup, Dict(c.name => c for c in c_info))
    context_names = Tuple(c.name for c in c_info)

    # Step ownership group mapping
    owner_sym, group, group_levels = if steps === :global
        (:global, ones(Int, n), Any[:global])
    elseif steps isa Symbol
        ob = f_lookup[steps]
        (steps, copy(ob.index), deepcopy(ob.levels))
    else
        # Tuple of facets e.g. (:rater, :item) -> Cartesian product of declared levels
        sub_bs = [f_lookup[s] for s in steps]
        dims = Tuple(length(b.levels) for b in sub_bs)
        lin = LinearIndices(dims)
        cart = CartesianIndices(dims)
        g_levs = Any[Tuple(sub_bs[d].levels[ci[d]] for d in 1:length(sub_bs)) for ci in vec(cart)]
        g_idx = [lin[ntuple(d -> sub_bs[d].index[i], length(sub_bs))...] for i in 1:n]
        comb_sym = Symbol(join(String.(collect(steps)), "__"))
        (comb_sym, g_idx, g_levs)
    end

    if category_levels isa AbstractDict && !(steps isa Symbol && steps !== :global)
        throw(ArgumentError("Dict category_levels by owner requires a single declared facet `steps = :facet`"))
    end
    cat, categories, supports = _category_support(raw[score], score, category_levels,
        steps isa Tuple ? owner_sym : steps, group, group_levels)

    transfer = nothing
    if !isnothing(calibration)
        isnothing(fixed_calibration) || throw(ArgumentError("choose fixed_calibration or calibration"))
        transfer, fixed_calibration = _joint_calibration(calibration,steps)
    end
    calibration = isnothing(fixed_calibration) ? (;) : fixed_calibration
    calibration isa NamedTuple && all(k -> k in (:facets,:steps,:groups,:cells), keys(calibration)) ||
        throw(ArgumentError("fixed_calibration accepts named facets, steps, groups and interaction cells"))
    fixed_facets = get(calibration, :facets, (;))
    fixed_facets isa NamedTuple && all(k -> k in facet_names, keys(fixed_facets)) ||
        throw(ArgumentError("calibrated facets must match declared facet roles"))
    all(k -> !haskey(lltm_nt,k), keys(fixed_facets)) ||
        throw(ArgumentError("a fixed facet location cannot also have an LLTM feature model"))
    groups = get(calibration, :groups, ())
    groups isa Union{Tuple,AbstractVector} && (!haskey(calibration,:groups) || !isempty(groups)) &&
        all(g -> g isa NamedTuple && haskey(g,:block) && g.block in facet_names &&
            !haskey(lltm_nt,g.block), groups) ||
        throw(ArgumentError("groups must name declared facet main effects without an LLTM restriction"))
    group_receipt = NamedTuple[]
    group_dimensions = NamedTuple[]
    fixed_steps = if haskey(calibration, :steps)
        declaration = calibration.steps
        valid_owner(x) = (x isa Tuple ? all(_valid_facet_label,x) : _valid_facet_label(x)) && x in group_levels
        declaration isa NamedTuple && Set(keys(declaration)) == Set((:owner,:values)) &&
            isequal(declaration.owner,steps) && declaration.values isa AbstractDict &&
            !isempty(declaration.values) && all(valid_owner, keys(declaration.values)) ||
            throw(ArgumentError("fixed steps require the declared owner and a dictionary by owner level"))
        declaration.values
    else
        Dict()
    end
    if !isnothing(fixed_calibration)
        (!isempty(fixed_facets) || !isempty(fixed_steps) || !isempty(groups) || haskey(calibration,:cells)) || throw(ArgumentError("empty fixed calibration"))
        all(v -> v isa AbstractDict && !isempty(v), values(fixed_facets)) &&
            all(v -> v isa AbstractDict && !isempty(v), values(fixed_steps)) ||
            throw(ArgumentError("each calibrated block requires a nonempty dictionary of values"))
    end
    if !isnothing(intercept)
        is_bayesian && intercept isa D.Normal ||
            throw(ArgumentError("a population intercept requires an explicit Normal prior and Bayesian prior specification"))
        :population_mean in facet_names && throw(ArgumentError("population_mean is reserved for the population intercept"))
    end

    int_specs = _normalize_interaction_specs(interactions, prior_sd, facet_names, context_names)
    cells = haskey(calibration,:cells) ? _calibrated_cells(calibration.cells,int_specs) : nothing
    cell_anchors = NamedTuple[]
    cell_dimensions = NamedTuple[]
    if any(x -> x.kind === :facet_step && steps === x.f1, int_specs)
        throw(ArgumentError("cannot add `($(repr(steps)), :step)` interaction when `steps = $(repr(steps))` already owns unconstrained per-level steps"))
    end

    return (;
        person, score, facets, steps, prior_sd, default_prior, category_levels, interactions,
        random_effects, lltm, fixed_calibration, intercept, performance, assessment, missing_audit,
        is_bayesian, lltm_nt, raw, n, p_idx, p_levels, P, p_sd_val, p_logmean, p_logsd,
        p_scale_kind, p_is_hyper, f_info, f_lookup, c_info, role_lookup, owner_sym, group,
        group_levels, cat, categories, supports, transfer, fixed_facets, groups, group_receipt,
        group_dimensions, fixed_steps, int_specs, cells, cell_anchors, cell_dimensions,
    )
end
