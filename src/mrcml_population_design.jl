"""
    MRCML.population_design(spec, roster; person, group, reference, covariates=())

Check which scalar group mean contrasts and common covariate slopes can be
separated from the free measurement coefficients in the observed ratings.
Supply one row per modeled person, a named reference group with mean zero at
covariate zero, and optional finite numeric covariate columns. An additive
group contrast compares the groups at the same covariate values.

The returned matrix and group indices follow `people` order. `mean_terms`
reports estimability of each coefficient. The check uses observed category
logit contrasts, the fixed scoring coefficients and hard constraints encoded
in the specification. It does not assess group variance precision or use an
external calibration likelihood or priors to supply missing information.
"""
function population_design(spec::Union{Spec,Target}, roster; person::Symbol,
        group::Symbol, reference, covariates::Tuple=())
    all(k -> k isa Symbol, covariates) && allunique((person, group, covariates...)) ||
        throw(ArgumentError("use distinct person, group and numeric covariate columns"))
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
    X = zeros(length(ids), length(other) + length(covariates))
    for (col, level) in enumerate(other)
        X[:,col] .= g .== level
    end
    for (col, key) in enumerate(covariates)
        X[:,length(other)+col] .= AF._numeric_column(roster, key, length(ids))[Int.(order)]
    end
    names = vcat(["group[$(repr(levels[i]))]" for i in other], String[String(k) for k in covariates])
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
    M = hcat(op.A_free[slot,:] - op.A_free[baseline,:], incidence * sparse(X))
    all_names = vcat(op.free_names, names)
    audit = AF._mrcml_spqr_rank(M, all_names)
    mean_terms = map(eachindex(names)) do k
        j = length(op.free_names) + k
        identifiable = audit.full_rank || begin
            keep = setdiff(axes(M,2), j)
            AF._mrcml_spqr_rank(M[:,keep], all_names[keep]).rank < audit.rank
        end
        (; name=names[k], identifiable)
    end
    return (; people=copy(spec.people), groups=levels, reference, group_index=g, X,
             covariates, mean_terms, rank=audit.rank, columns=audit.columns,
             full_rank=audit.full_rank, near_dependence=audit.near_dependence)
end

# Preserve native record types and older saved fits. Only the new declaration
# populates spec_record.population and adds coordinates to a Bayesian target.
function _with_fields(s; fields...)
    typeof(s)((get(fields, k, getfield(s, k)) for k in fieldnames(typeof(s)))...)
end

function _with_population(s::Union{Spec,Target}, pop::NamedTuple)
    hasproperty(s.spec_record, :population) && throw(ArgumentError("population already specified"))
    required = (:roster, :person, :group, :reference)
    all(k -> haskey(pop, k), required) &&
        all(k -> k in (required..., :covariates, :coefficient_prior, :sd_prior), keys(pop)) ||
        throw(ArgumentError("declare roster, person, group, reference and optional covariates, coefficient_prior, sd_prior"))
    d = population_design(s, pop.roster; pop.person, pop.group, pop.reference,
                          covariates=get(pop,:covariates,()))
    d.full_rank || throw(ArgumentError("unidentified population or measurement design ($(d.rank)/$(d.columns)); aliased mean terms: " *
        join([t.name for t in d.mean_terms if !t.identifiable], ", ")))
    d = merge(d,(;person_column=pop.person, group_column=pop.group))
    if s isa Spec
        any(k->haskey(pop,k), (:coefficient_prior,:sd_prior)) &&
            throw(ArgumentError("declare Bayesian measurement priors to use population priors"))
        return _with_fields(s; spec_record=merge(s.spec_record,(;population=d)))
    end
    s.person_hyper_idx==0 && s.person_sd==1 ||
        throw(ArgumentError("group SDs replace the scalar person SD; use standard normal underlying person coordinates"))
    all(k->haskey(pop,k),(:coefficient_prior,:sd_prior)) ||
        throw(ArgumentError("supply coefficient_prior=Normal(...) and sd_prior=LogNormal(...) for a Bayesian population"))
    cp = AF._normal_parameters(pop.coefficient_prior, :coefficient_prior)
    pop.sd_prior isa D.LogNormal || throw(ArgumentError("sd_prior must be LogNormal"))
    sp = AF._population_parameters(pop.sd_prior,:sd_prior)
    b = s.dimension .+ (1:size(d.X,2))
    h = last(b) .+ (1:length(d.groups))
    d = merge(d,(;coefficient_prior=cp, sd_prior=(logmean=sp.logmean,logsd=sp.logsd), beta=b, logsd=h))
    return _with_fields(s; dimension=last(h), spec_record=merge(s.spec_record,(;population=d)))
end
