"""
    MRCML.population_design(spec, roster; person, group, reference, covariates=())

Check which scalar group mean contrasts and common covariate slopes can be
separated from the free measurement coefficients in the observed ratings.
Supply one row per modeled person, a named reference group, and optional finite
numeric covariate columns. The intercept estimates the reference-group mean;
`intercept=false` explicitly fixes that mean to zero. An additive
group contrast compares the groups at the same covariate values.

The returned matrix and group indices follow `people` order. `mean_terms`
reports estimability of each coefficient. The check uses observed category
logit contrasts, the fixed scoring coefficients and hard constraints encoded
in the specification. It does not assess group variance precision or use an
external calibration likelihood or priors to supply missing information.
"""
function population_design(spec::Union{Spec,Target}, roster; person::Symbol,
        group::Symbol, reference, covariates::Tuple=(), intercept::Union{Symbol,Bool}=:auto)
    all(k -> k isa Symbol, covariates) && allunique((person, group, covariates...)) ||
        throw(ArgumentError("use distinct person, group and numeric covariate columns"))
    use_intercept = if intercept === :auto
        spec.location_mode === :finite_connected &&
            !hasproperty(spec.spec_record, :calibration) &&
            !(hasproperty(spec.spec_record, :has_xsi_fixed) && Bool(spec.spec_record.has_xsi_fixed))
    elseif intercept isa Bool
        intercept
    else
        throw(ArgumentError("population intercept must be :auto, true, or false"))
    end
    ids = collect(B._column(roster, person))
    all(AF._valid_facet_label, ids) && allunique(ids) && Set(ids) == Set(spec.people) ||
        throw(ArgumentError("supply exactly one roster row for each modeled person ID"))
    Set(spec.person) == Set(eachindex(spec.people)) ||
        throw(ArgumentError("a declared person has no ratings"))
    order = indexin(spec.people, ids)
    groups = collect(B._column(roster, group))
    B._check_length!(length(ids), groups, group)
    g, levels = AF._labels(groups[Int.(order)], group)
    AF._valid_facet_label(reference) && reference in levels && length(levels) >= 2 ||
        throw(ArgumentError("the reference and at least one comparison group must be observed"))
    other = findall(!=(reference), levels)
    int_off = use_intercept ? 1 : 0
    X = zeros(length(ids), int_off + length(other) + length(covariates))
    if use_intercept
        X[:, 1] .= 1.0
    end
    for (col, level) in enumerate(other)
        X[:, int_off + col] .= g .== level
    end
    for (col, key) in enumerate(covariates)
        X[:, int_off + length(other) + col] .= AF._numeric_column(roster, key, length(ids))[Int.(order)]
    end
    names = vcat(
        use_intercept ? String["intercept"] : String[],
        ["group[$(repr(levels[i]))]" for i in other],
        String[String(k) for k in covariates],
    )
    allunique(names) || throw(ArgumentError("covariate names must differ from the generated group contrast names"))
    op = spec.operator
    slot = Int[]; baseline = Int[]; owner = Int[]
    for (i, pattern) in enumerate(op.pattern_of_row)
        r = op.pattern_ranges[pattern]
        for k in first(r)+1:last(r)
            push!(slot, k); push!(baseline, first(r)); push!(owner, spec.person[i])
        end
    end
    # Category-independent offsets vanish from the likelihood and from this rank check.
    incidence = sparse(1:length(slot), owner, op.B_pat[slot] - op.B_pat[baseline],
                       length(slot), length(ids))
    # iid random effects contribute covariance, not fixed mean-design columns.
    fixed = AF._mrcml_fixed_columns(op)
    M = hcat(op.A_free[slot,fixed] - op.A_free[baseline,fixed], incidence * sparse(X))
    all_names = vcat(op.free_names[fixed], names)
    audit = AF._mrcml_spqr_rank(M, all_names)
    mean_terms = map(eachindex(names)) do k
        j = length(fixed) + k
        identifiable = audit.full_rank || begin
            keep = setdiff(axes(M,2), j)
            AF._mrcml_spqr_rank(M[:,keep], all_names[keep]).rank < audit.rank
        end
        (; name=names[k], identifiable)
    end
    return (; people=copy(spec.people), groups=levels, reference, group_index=g, X,
             covariates, mean_terms, rank=audit.rank, columns=audit.columns,
             full_rank=audit.full_rank, near_dependence=audit.near_dependence,
             (use_intercept ? (; has_intercept=true) : (;))...)
end

# Preserve native record types and older saved fits. Only the new declaration
# populates spec_record.population and adds coordinates to a Bayesian target.
function _with_fields(s; fields...)
    typeof(s)((get(fields, k, getfield(s, k)) for k in fieldnames(typeof(s)))...)
end

function _person_chart(target, choice, logmedian)
    choice === :noncentered && return nothing
    people = target.people
    choice === :centered && return (;mode=:centered, centered=trues(length(people)))
    if choice isa AbstractDict
        all(AF._valid_facet_label, keys(choice)) && Set(keys(choice)) == Set(people) ||
            throw(ArgumentError("person_coordinates needs one assignment for every modeled person ID"))
        all(v -> v === :centered || v === :noncentered, values(choice)) ||
            throw(ArgumentError("each person coordinate must be :centered or :noncentered"))
        return (;mode=:by_id, centered=[choice[id] === :centered for id in people])
    end
    choice isa NamedTuple && keys(choice) == (:information_cutoff,) ||
        throw(ArgumentError("use :noncentered, :centered, a dictionary keyed by person ID, or (information_cutoff=value,)"))
    cutoff = choice.information_cutoff
    cutoff isa Real && !(cutoff isa Bool) && isfinite(cutoff) && cutoff > 0 ||
        throw(ArgumentError("information_cutoff must be finite and positive"))
    # At physical ability zero and structural prior reference values, information
    # for one categorical response is Var(B). Outcome values do not enter.
    op = target.operator
    reference = AF._mrcml_unpack(target, zeros(target.dimension))
    shifts = AF._mrcml_pattern_shifts(op, reference.eta_xi)
    variance = map(op.pattern_ranges) do slots
        logits = view(shifts, slots)
        prob = exp.(logits .- maximum(logits))
        prob ./= sum(prob)
        b = view(op.B_pat, slots)
        dot(prob, (b .- dot(prob, b)).^2)
    end
    contributions = [Float64[] for _ in people]
    for (n, pattern) in enumerate(op.pattern_of_row)
        push!(contributions[target.person[n]], variance[pattern])
    end
    reference_sd = exp(logmedian)
    # A row permutation must preserve the assignment even at the cutoff.
    information = [reference_sd^2 * sum(sort!(values)) for values in contributions]
    all(isfinite, information) && isfinite(reference_sd) && reference_sd > 0 ||
        throw(ArgumentError("unrepresentable reference information for person_coordinates"))
    return (;mode=:information, centered=information .>= cutoff, information, cutoff, reference_sd)
end

function _with_population(s::Union{Spec,Target}, pop::NamedTuple)
    hasproperty(s.spec_record, :population) && throw(ArgumentError("population already specified"))
    required = (:roster, :person, :group, :reference)
    all(k -> haskey(pop, k), required) &&
        all(k -> k in (required..., :covariates, :coefficient_prior, :sd_prior, :person_coordinates, :equal_sd, :intercept), keys(pop)) ||
        throw(ArgumentError("declare roster, person, group, reference and optional covariates, coefficient_prior, sd_prior, person_coordinates, equal_sd, intercept"))
    eq_sd_raw = get(pop, :equal_sd, false)
    eq_sd_raw isa Bool || throw(ArgumentError("equal_sd must be a Bool"))
    equal_sd = Bool(eq_sd_raw)
    d = population_design(s, pop.roster; pop.person, pop.group, pop.reference,
                          covariates=get(pop,:covariates,()), intercept=get(pop,:intercept,:auto))
    d.full_rank || throw(ArgumentError("unidentified population or measurement design ($(d.rank)/$(d.columns)); aliased mean terms: " *
        join([t.name for t in d.mean_terms if !t.identifiable], ", ")))
    d = merge(d, (; person_column=pop.person, group_column=pop.group, (equal_sd ? (; equal_sd=true) : (;))...))
    if s isa Spec
        haskey(pop, :person_coordinates) && throw(ArgumentError("person_coordinates requires a Bayesian population"))
        any(k->haskey(pop,k), (:coefficient_prior,:sd_prior)) &&
            throw(ArgumentError("declare Bayesian measurement priors to use population priors"))
        return _with_fields(s; spec_record=merge(s.spec_record,(;population=d)))
    end
    s.person_hyper_idx==0 && s.person_sd==1 ||
        throw(ArgumentError("group SDs replace the scalar person SD; use standard normal underlying person coordinates"))
    all(k->haskey(pop,k),(:coefficient_prior,:sd_prior)) ||
        throw(ArgumentError("supply coefficient_prior=Normal(...) and sd_prior=LogNormal(...) / truncated(Normal(0, s), 0, Inf) / truncated(LocationScale(0, s, TDist(df)), 0, Inf) for a Bayesian population"))
    cp = AF._normal_parameters(pop.coefficient_prior, :coefficient_prior)
    AF._is_scale_prior_dist(pop.sd_prior) ||
        throw(ArgumentError("sd_prior must be LogNormal or a zero-supporting HalfNormal / HalfStudentT truncated scale prior"))
    sp = AF._parse_scale_or_lognormal(pop.sd_prior, true, :sd_prior)
    ref_logmedian = sp.kind === :lognormal ? sp.logmean : log(sp.sd)
    chart = _person_chart(s, get(pop, :person_coordinates, :noncentered), ref_logmedian)
    isnothing(chart) || (d = merge(d, (;person_chart=chart)))
    b = s.dimension .+ (1:size(d.X,2))
    n_sd = equal_sd ? 1 : length(d.groups)
    h = last(b) .+ (1:n_sd)
    sd_rec = sp.kind === :lognormal ? (logmean=sp.logmean, logsd=sp.logsd) :
        (kind=sp.kind, sd=sp.sd, logmean=sp.logmean, logsd=sp.logsd)
    d = merge(d,(;coefficient_prior=cp, sd_prior=sd_rec, beta=b, logsd=h))
    allocation = AF._mrcml_allocation(s.person,s.people,s.facets,s.operator,s.location_mode;
        n_hyper=length(h)+count(b->b.hyper_idx>0,s.prior_blocks),person_estimated=true,
        external_columns=get(s.spec_record,:external_columns,1:0))
    return _with_fields(s; dimension=last(h), allocation,
        spec_record=merge(s.spec_record,(;population=d)))
end

"""
    MRCML.focal_dff_scan(table; person, score, facets, steps = :global, category_levels,
                         population, dff_facet = :rater, targets = nothing,
                         focal_group = nothing, quadrature = :gauss_hermite,
                         quad_points = 61, theta_lim = 4.0, se_type = :observed,
                         interval = 0.95, kwargs...)

Run a focal split-level DFF likelihood-ratio & full-covariance / Huber–White sandwich scan
under `MRCML` grouped MMLE (`ConQuest_pop_LRT` / `mfrmr_MML_pop_LRT` formulation):
1. Fits the invariant grouped population null model once (`fit_null`).
2. For each target level in `targets` (all levels of `dff_facet` by default), splits that
   target level across groups while holding remaining anchor levels invariant, fits the
   nested focal DFF model (`fit_alt`), verifies exact linear-subspace nesting, and reports
   the likelihood-ratio chi-square test (`stat`, `df`, `p_value`), full observed-Hessian `se`,
   and person-cluster Huber–White `sandwich_se`.
"""
function focal_dff_scan(
        table;
        person::Symbol = :person,
        score::Symbol = :score,
        facets::NamedTuple,
        steps = :global,
        category_levels,
        population::NamedTuple,
        dff_facet::Symbol = :rater,
        targets = nothing,
        focal_group = nothing,
        quadrature::Symbol = :gauss_hermite,
        quad_points::Int = 61,
        theta_lim::Real = 4.0,
        se_type::Symbol = :observed,
        interval::Real = 0.95,
        kwargs...)
    dff_facet in keys(facets) ||
        throw(ArgumentError("dff_facet $(repr(dff_facet)) must be one of declared facets $(keys(facets))"))
    pop_freq = Base.structdiff(population, (; coefficient_prior = nothing, sd_prior = nothing, person_coordinates = nothing))

    spec_null = B.mfrm_spec(
        table;
        person, score, facets, steps, category_levels,
        population = pop_freq,
        prior = :none,
        kwargs...,
    )
    fit_null = B.fit(spec_null; method = :mmle, quadrature, quad_points, theta_lim)

    fb = only(filter(f -> f.name === dff_facet, spec_null.facets))
    all_levs = fb.levels
    length(all_levs) >= 2 || throw(ArgumentError("focal_dff_scan requires at least 2 levels in $dff_facet"))
    scan_levs = targets === nothing ? all_levs :
        ((targets isa Union{AbstractVector, Tuple} && !(targets isa AbstractString)) ? collect(targets) : [targets])

    pop_rec = spec_null.spec_record.population
    ref_grp = pop_rec.reference
    cmp_grps = [g for g in pop_rec.groups if !isequal(g, ref_grp)]
    fg_sel = focal_group === nothing ? first(cmp_grps) : focal_group
    any(x -> isequal(x, fg_sel), cmp_grps) ||
        throw(ArgumentError("focal_group $(repr(fg_sel)) must be a non-reference group in $(cmp_grps)"))

    rows = NamedTuple[]
    alt_fits = Dict{Any,Any}()
    for fl in scan_levs
        spec_alt = B.mfrm_spec(
            table;
            person, score, facets, steps, category_levels,
            population = pop_freq,
            interactions = ((; pair = (dff_facet, pop_rec.group_column), focal = fl),),
            prior = :none,
            kwargs...,
        )
        fit_alt = B.fit(spec_alt; method = :mmle, quadrature, quad_points, theta_lim)
        cmp = B.compare_models(["null" => fit_null, "focal" => fit_alt])
        lrt = cmp.likelihood_ratio
        ctr = B.contrast(
            fit_alt;
            interaction = (dff_facet, pop_rec.group_column),
            focal = fl,
            group = fg_sel,
            reference = ref_grp,
            estimand = :vs_rest_of_panel,
            se_type,
            interval,
        )
        alt_fits[fl] = fit_alt
        push!(rows, (;
            contrast_id = "$(dff_facet)$(fl)_G$(fg_sel)_minus_G$(ref_grp)",
            target_rater = fl,
            group_a = "G$(fg_sel)",
            group_b = "G$(ref_grp)",
            focal_group = fg_sel,
            reference_group = ref_grp,
            estimate = ctr.estimate,
            se = ctr.se,
            observed_se = ctr.observed_se,
            sandwich_se = ctr.sandwich_se,
            z_statistic = ctr.z_statistic,
            wald_p_value = ctr.p_value,
            stat = lrt === nothing ? NaN : lrt.lr_statistic,
            df = lrt === nothing ? 1 : lrt.df,
            p_value = lrt === nothing ? NaN : lrt.asymptotic_chisq_pvalue,
            ci_low = ctr.lower,
            ci_high = ctr.upper,
            method = se_type === :sandwich ? "MRCML_MML_pop_split_LRT_sandwich" : "MRCML_MML_pop_split_LRT",
            identifiable = Bool(fit_alt.record.summary.stationarity_qualified),
        ))
    end

    return (;
        schema = "bayesianmgmfrm.mrcml_focal_dff_scan.v1",
        dff_facet,
        reference_group = ref_grp,
        focal_group = fg_sel,
        equal_sd = Bool(get(pop_rec, :equal_sd, false)),
        quadrature,
        quad_points,
        null_fit = fit_null,
        alt_fits,
        rows,
    )
end
