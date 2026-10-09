module MGMFRMFoundationPrediction

# Normalized-C bindings; reuse numerical helpers without relabeling C as the old raw candidate.
using BayesianMGMFRM, Random, Serialization, Statistics
include("mgmfrm_foundation_sensitivity.jl")
const B=BayesianMGMFRM
const S=MGMFRMFoundationSensitivity
const F=S.F
const E=S.C.E

function check_split(data, folds)
    E.candidate_cells(data)
    B.kfold_plan_diagnostics(data,folds;facets=:all).passed ||
        throw(ArgumentError("Missing training facet support"))
    length(folds.fold_rows)==5 && sort([r.fold for r in folds.fold_rows])==collect(1:5) ||
        throw(ArgumentError("Exactly five declared folds required"))
    heldout=Int[]
    for f in folds.fold_rows
        train,test=f.training_observations,f.heldout_observations
        length(train)==1000 && length(test)==250 && issorted(train) && issorted(test) &&
            length(unique(train))==1000 && length(unique(test))==250 &&
            isempty(intersect(train,test)) && sort([train;test])==collect(1:1250) ||
            throw(ArgumentError("Invalid training/heldout partition"))
        append!(heldout,test)
        for person in 1:50, dimension in 1:2
            any(n->data.person[n]==person && F.Q[data.item[n],dimension],train) ||
                throw(ArgumentError("Missing training person/dimension support"))
        end
    end
    sort(heldout)==collect(1:1250) || throw(ArgumentError("Heldout roster is incomplete or repeated"))
    return folds
end

"""Bind one full panel and a fixed split; no posterior draws are generated."""
function prepare(input, input_sha256; split_seed)
    split_seed isa Integer && !(split_seed isa Bool) && split_seed>=0 ||
        throw(ArgumentError("Explicit nonnegative split seed required"))
    E.checked_bytes(input,input_sha256)
    p=F.prepare(input)
    p.x.schema in ("mgmfrm.foundation_fixed_facet_input.v1",
        "mgmfrm.foundation_fixed_facet_assessment_input.v1") ||
        throw(ArgumentError("Fixed-facet R0/R1 input required"))
    p.x.raw_names==p.target.base.blueprint.parameter_names ||
        throw(ArgumentError("Truth coordinate names/order mismatch"))
    data=p.spec.data
    folds=check_split(data,B.kfold_plan(data;k=5,group_by=nothing,shuffle=true,rng=MersenneTwister(split_seed)))
    # Reconstruct logits directly; do not log rounded/underflowed probabilities.
    direct=permutedims(B._mgmfrm_source_constrained_params_from_unconstrained(
        p.target.base.design,Float64.(p.x.raw_truth)))
    truth_logs=E.mean_log_probabilities(p.target.base.design,direct)
    independent=reduce(vcat,permutedims.(Vector{Float64}.(p.x.probabilities)))
    size(independent)==(1250,4) && maximum(abs.(exp.(truth_logs).-independent))<1e-12 ||
        throw(ArgumentError("Independent generator probabilities disagree"))
    E.checked_bytes(input,input_sha256)
    binding=E.seal((;schema=:normalized_C_prediction_panel_v1,input_sha256,split_seed,
        full_design_identity=B.design_identity(p.target.base.design).value,
        cell_ids=E.candidate_cells(data),folds,truth_logs,
        prediction_scope=:known_levels_with_1000_training_ratings))
    return (;p,binding)
end

function fold_context(panel, fold, sd)
    E.check_seal(panel.binding)
    fold isa Integer && !(fold isa Bool) && fold in 1:5 || throw(ArgumentError("Invalid fold"))
    sd isa Real && !(sd isa Bool) && sd in (.25,.5,1.) || throw(ArgumentError("Undeclared prior width"))
    (;p,binding)=panel
    B.design_identity(B._normalized_mgmfrm_target(p.spec,p.prior).base.design).value==binding.full_design_identity ||
        throw(ArgumentError("Panel data/model changed after binding"))
    f=only(filter(r->r.fold==fold,binding.folds.fold_rows))
    spec=B._refit_training_spec(p.spec,B._loo_refit_training_data(p.spec.data,f.training_observations))
    B.validate_design(spec.data).passed || throw(ArgumentError("Training design rejected before fitting"))
    prior=B.Experimental.NormalizedMGMFRMPrior(;prior_model=:exchangeable,
        merge(F.SCALES,(;log_discrimination_sd=Float64(sd)))...)
    target=B._normalized_mgmfrm_target(spec,prior)
    target.base.blueprint.parameter_names==p.target.base.blueprint.parameter_names ||
        throw(ArgumentError("Training coordinates differ from full-panel coordinates"))
    score_design=B._loo_refit_score_design(p.spec.data,target.base.design,f.heldout_observations)
    score_data=score_design.spec.data
    ids=[(score_data.person_levels[score_data.person[n]],score_data.item_levels[score_data.item[n]],
        score_data.rater_levels[score_data.rater[n]]) for n in 1:score_data.n]
    ids==binding.cell_ids[f.heldout_observations] &&
        score_data.category==p.spec.data.category[f.heldout_observations] ||
        throw(ArgumentError("Heldout ID/category alignment mismatch"))
    truth_logs=binding.truth_logs[f.heldout_observations,:]
    weights=E.predictive_weights(p.spec.data)[f.heldout_observations]
    record=E.seal((;panel_identity=binding.content_hash,fold,sd=Float64(sd),truth_logs,weights,
        training_observations=f.training_observations,heldout_observations=f.heldout_observations,
        target_identity=B._mgmfrm_normalized_prior_identity(target),prior=B._mgmfrm_normalized_prior_record(target),
        # This scoring view preserves training coordinates/validation; it is not a new fitted design.
        score_fingerprint=B._canonical_design_fingerprint(score_design),heldout_ids=ids))
    return (;spec,prior,target,score_design,binding=record)
end

"""Check target metadata only. Passing this does not validate or qualify posterior draws."""
function check_target(context, record)
    E.check_seal(context.binding)
    record.target_identity==context.binding.target_identity && record.prior==context.binding.prior ||
        throw(ArgumentError("Fit belongs to a different training target/prior"))
    return B._MGMFRMNormalizedPriorLogDensity(record.spec,record.prior;
        expected_identity=context.binding.target_identity)
end

function check_fit(context, record; seed)
    seed isa Integer && !(seed isa Bool) && seed>=0 || throw(ArgumentError("Explicit fit seed required"))
    check_target(context,record)
    checked=B._restore_mgmfrm_normalized_prior_samples(record;expected_identity=context.binding.target_identity)
    run=record.run;c=run.controls
    run.backend===:advancedhmc && run.sampler===:nuts &&
        all(k->getproperty(c,k)==getproperty(F.CONTROLS,k),
            (:chains,:warmup,:ndraws,:target_accept,:max_depth,:metric,:init_jitter)) &&
        c.step_size==.03 && c.max_energy_error==1000. && c.ad_backend===:ForwardDiff &&
        c.sampling_coordinates===:orthogonal_person_mean_item_offset &&
        c.rng.replayable===true && c.rng.seed==seed ||
        throw(ArgumentError("Fit controls/seed differ from foundation procedure"))
    warmup=checked.warmup_diagnostics
    length(warmup)==4 && all(r->r.coverage===:recorded &&
        r.observed_iterations==r.expected_iterations==1000,warmup) ||
        throw(ArgumentError("Incomplete warmup record"))
    return checked
end

"""Score already-checked direct draws; this alone asserts neither fit provenance nor qualification."""
function score_draws(context, direct; chain_ids, iterations)
    E.check_seal(context.binding)
    size(direct,1)==4000 && chain_ids==repeat(1:4;inner=1000) &&
        iterations==repeat(1:1000;outer=4) || throw(ArgumentError("Four ordered 1000-draw chains required"))
    B._canonical_design_fingerprint(context.score_design)==context.binding.score_fingerprint ||
        throw(ArgumentError("Heldout scoring design changed after binding"))
    logs=E.mean_log_probabilities(context.score_design,direct)
    state=E.loss_delta_setup(logs,context.binding.truth_logs,context.score_design.spec.data.category,
        context.binding.weights,size(direct,1))
    E.foreach_log_batch(context.score_design,direct) do selected,draws
        E.loss_delta_add!(state,draws,selected)
    end
    error=E.loss_delta_finish(state;chain_ids,iterations)
    blocks=E.predictive_blocks(context.score_design,direct;chain_ids,iterations)
    resolution=E.predictive_resolution(blocks,context.binding.truth_logs;
        categories=context.score_design.spec.data.category,weights=context.binding.weights)
    compact=Base.structdiff(error,(;influence=nothing))
    return (;log_probabilities=logs,monte_carlo_error=merge(compact,
        (;resolution,curvature=last(resolution.prefixes).curvature)))
end

end
