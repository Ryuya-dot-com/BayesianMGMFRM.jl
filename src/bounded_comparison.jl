const _COUNT_CRITERIA_SCHEMA="bayesianmgmfrm.count_rating_criteria.v1"
const _COUNT_COMPARISON_SCHEMA="bayesianmgmfrm.count_rating_comparison.v1"
_rating_metadata(t::AdditiveFacets.BoundedTarget)=(;measure=:original_score_density_and_endpoint_atoms,bounds=t.observation.bounds)
_rating_metadata(t::AdditiveFacets.CountTarget)=(;measure=:success_count_given_trials,trials=copy(t.trials))
_rating_log_cell(t::AdditiveFacets.BoundedTarget,v,n)=first(AdditiveFacets.bounded_cell(t.y[n],AdditiveFacets.bounded_eta(t,v,n),AdditiveFacets.observation_values(t,v,n),t.observation.bounds[2]-t.observation.bounds[1]))
_rating_log_cell(t::AdditiveFacets.CountTarget,v,n)=first(AdditiveFacets.count_cell(t,v,n))
const _BOUNDED_CRITERIA_SCHEMA="bayesianmgmfrm.bounded_rating_criteria.v1"
const _BOUNDED_COMPARISON_SCHEMA="bayesianmgmfrm.bounded_rating_comparison.v1"
function _bounded_criteria(f;unit,integrate,refits,independent_refit_rng,mcse_blocks)
    unit===:rating && integrate===nothing || throw(ArgumentError("scalar population scoring requires unit=:rating, with all owner identities known; held-owner integration is not implemented"))
    isempty(refits) && !independent_refit_rng && isempty(mcse_blocks) || throw(ArgumentError("scalar row scoring does not accept performance-refit or block-quadrature controls"))
    A=AdditiveFacets;t=A.checked(f;full=true);run=f.record.run
    _check_psis_iterations(run.chain_ids,run.iterations)
    S=size(run.draws,1);N=length(t.y);rows=NamedTuple[];influence=zeros(S)
    quality=qualify(f);meta=_rating_metadata(t);counts=t isa A.CountTarget
    # Chunk rows, retaining joint draw order for the aggregate influence/MCSE.
    for start in 1:32:N
        ix=start:min(start+31,N);ll=zeros(S,length(ix))
        for (s,q) in enumerate(eachrow(run.draws))
            v=coordinates(t,q)
            for (j,n) in enumerate(ix);ll[s,j]=_rating_log_cell(t,v,n);end
        end
        for (j,n) in enumerate(ix)
            x=_CC_MOD._profile_score(ll[:,j],-ll[:,j],run)
            eligible=x.row.importance_status===:ok && x.row.mcse_status===:available
            push!(rows,(;row=n,log_score=x.row.log_score,eligible,diagnostics=x.row))
            influence.+=x.influence
        end
    end
    eligible=quality.qualified && all(r->r.eligible,rows)
    precision=_CC_MOD._heldout_precision(influence,run,eligible)
    available=eligible && precision.mcse_status===:available
    cols=unique([t.columns.person,t.columns.score,values(t.columns.facets)...,
        filter(!isnothing,[t.columns.performance,t.columns.assessment])...])
    counts && push!(cols,t.observation.trials)
    observations=Dict(c=>t.table[c] for c in cols)
    predictor_columns=Dict(p.column=>t.table[p.column] for p in t.terms if p.column!==nothing)
    if t isa A.BoundedTarget
        for b in A.distribution_blocks(t),p in b.terms;predictor_columns[p.column]=t.table[p.column];end
    end
    _prediction_seal((;schema=counts ? _COUNT_CRITERIA_SCHEMA : _BOUNDED_CRITERIA_SCHEMA,unit=:rating,conditioning=:known_owners_observed_covariates,
      meta...,observations,
      observation_binding=counts ? _cache_hash((;observations,meta...,unit=:rating)) :
          _cache_hash((;observations,bounds=t.observation.bounds,measure=:original_score_density_and_endpoint_atoms,unit=:rating)),
      rows,elpd=sum(r.log_score for r in rows),mcse=available ? precision.mcse : nothing,
      status=available ? :estimated : :diagnostic_only,precision,quality,
      predictor_columns,
      source_sample_hash=f.record.content_hash,target_identity=f.record.target_identity,
      sampling_standard_error=nothing,sampling_uncertainty=:unassessed_crossed_design,automatic_ranking=false,
      warnings=[A.design(t).warnings;"Rating-wise PSIS predicts another response with known owners; not a new speaker, recording or listener. MCSE ignores PSIS tail-estimation uncertainty; population sampling uncertainty is not computed."],scientific_acceptance=false))
end
function _check_bounded_scores(r)
    r.schema in (_BOUNDED_CRITERIA_SCHEMA,_BOUNDED_COMPARISON_SCHEMA,_COUNT_CRITERIA_SCHEMA,_COUNT_COMPARISON_SCHEMA) || throw(ArgumentError("invalid rating score schema"))
    r isa NamedTuple && _prediction_check_seal(r,r.schema)
    string(r.unit)=="rating" && string(r.conditioning)=="known_owners_observed_covariates" &&
      string(r.measure)==(r.schema in (_COUNT_CRITERIA_SCHEMA,_COUNT_COMPARISON_SCHEMA) ? "success_count_given_trials" : "original_score_density_and_endpoint_atoms") && r.automatic_ranking===false || throw(ArgumentError("rating comparison unit/measure changed"))
    if r.schema in (_BOUNDED_CRITERIA_SCHEMA,_COUNT_CRITERIA_SCHEMA)
        !isempty(r.rows) && all(x->isfinite(x.log_score),r.rows) && isapprox(sum(x.log_score for x in r.rows),r.elpd;atol=1e-8) || throw(ArgumentError("score total mismatch"))
    else
        length(r.models)==2 || throw(ArgumentError("two models required"));foreach(_check_bounded_scores,r.models)
        r.models[1].observation_binding==r.models[2].observation_binding==r.observation_binding || throw(ArgumentError("observation mismatch"))
        isapprox(r.difference,r.models[1].elpd-r.models[2].elpd;atol=1e-8) || throw(ArgumentError("difference mismatch"))
    end
    r
end
function _compare_bounded_scores(models;criterion,comparison_axis,independent_model_rng)
    length(models)==2 && criterion===:psis_loo && comparison_axis in (nothing,:model) || throw(ArgumentError("supply two rating-wise criteria reports with criterion=:psis_loo"))
    labels=string.(first.(models));allunique(labels) && all(!isempty,labels) || throw(ArgumentError("distinct model labels required"))
    a,b=last.(models);foreach(_check_bounded_scores,(a,b))
    a.schema==b.schema && a.schema in (_BOUNDED_CRITERIA_SCHEMA,_COUNT_CRITERIA_SCHEMA) && a.observation_binding==b.observation_binding || throw(ArgumentError("same observations, bounds, measure and conditioning are required"))
    for c in intersect(keys(a.predictor_columns),keys(b.predictor_columns))
        collect(a.predictor_columns[c])==collect(b.predictor_columns[c]) || throw(ArgumentError("shared predictor values differ"))
    end
    independent_model_rng && a.source_sample_hash==b.source_sample_hash && throw(ArgumentError("shared draws are not independent model streams"))
    available=independent_model_rng && a.mcse!==nothing && b.mcse!==nothing
    _prediction_seal((;schema=a.schema==_COUNT_CRITERIA_SCHEMA ? _COUNT_COMPARISON_SCHEMA : _BOUNDED_COMPARISON_SCHEMA,names=labels,models=[a,b],unit=a.unit,conditioning=a.conditioning,measure=a.measure,
      observation_binding=a.observation_binding,difference=a.elpd-b.elpd,mcse=available ? hypot(a.mcse,b.mcse) : nothing,
      status=available ? :estimated : :diagnostic_only,independent_model_rng,
      rows=[(;row=x.row,primary=x.log_score,baseline=y.log_score,difference=x.log_score-y.log_score,eligible=x.eligible && y.eligible) for (x,y) in zip(a.rows,b.rows)],
      sampling_standard_error=nothing,sampling_uncertainty=:unassessed_crossed_design,automatic_ranking=false,
      warnings=unique([a.warnings;b.warnings]),scientific_acceptance=false))
end
