# Included in MGMFRMCoreEvaluation. Candidate-specific arithmetic, no fit runner.
const LOSS_METRICS = (:negative_log_predictive_probability,
    :squared_category_probability_error, :squared_expected_score_error, :log_score_regret)

function predictive_weights(data)
    candidate_cells(data)
    # Each of the 100 person/dimension groups receives weight 1/100.
    return [1 / (100 * (P.Q[data.item[n],1] ? 10 : 15)) for n in 1:data.n]
end

"""First-order derivatives of weighted losses at the mean predictive probabilities.
Weights are GLOBAL row weights; never renormalize a heldout fold. The derivative
with respect to log probability is multiplied by p_s / mean(p) - 1 below.
"""
function loss_delta_setup(logmean,truth,categories,weights,ndraws)
    size(logmean) == size(truth) == (length(categories),4) &&
        length(weights) == length(categories) > 0 &&
        all(k -> k isa Integer && !(k isa Bool) && 1 <= k <= 4,categories) &&
        all(w -> V._finite_number(w) && w > 0,weights) && ndraws > 0 ||
        throw(ArgumentError("Invalid predictive loss rows/categories/weights"))
    scored = B.mgmfrm_predictive_recovery_score(logmean,truth;category_levels=1:4,log_probabilities=true)
    gradients = zeros(length(weights),4,4)
    estimates = zeros(4)
    for n in eachindex(weights)
        w = weights[n]
        p,q = exp.(logmean[n,:]),exp.(truth[n,:])
        expected_error = sum((1:4) .* (p-q))
        gradients[n,categories[n],1] = -w
        gradients[n,:,2] = 2w .* (p-q) .* p
        gradients[n,:,3] = 2w * expected_error .* (1:4) .* p
        gradients[n,:,4] = -w .* q
        r = scored.rows[n]
        estimates .+= w .* [-logmean[n,categories[n]],
            4r.root_mean_squared_category_probability_error^2,
            r.expected_score_error^2,r.log_score_regret]
    end
    return (;logmean,gradients,estimates,influence=zeros(ndraws,4),scale=zeros(4))
end

function loss_delta_add!(state,logs,selected)
    size(logs) == (length(selected),size(state.logmean)...) ||
        throw(ArgumentError("Predictive draw/row shape mismatch"))
    B._mgmfrm_mean_predicted_probabilities(logs,1e-8;log_probabilities=true)
    for (local_s,s) in enumerate(selected)
        magnitude = zeros(4)
        for n in axes(logs,2), k in 1:4
            # A zero mean implies zero support in every retained draw.
            state.logmean[n,k] == -Inf && continue
            difference = expm1(logs[local_s,n,k]-state.logmean[n,k])
            iszero(difference) && continue
            for m in 1:4
                g = state.gradients[n,k,m]
                iszero(g) && continue
                term = sign(g)*sign(difference)*exp(log(abs(g))+log(abs(difference)))
                state.influence[s,m] += term
                magnitude[m] += abs(term)
            end
        end
        state.scale .= max.(state.scale,magnitude)
    end
    return state
end

function loss_delta_finish(state;chain_ids,iterations)
    layout = V.chain_order(chain_ids,iterations,size(state.influence,1))
    rows = map(1:4) do m
        values = state.influence[layout.order,m]
        status = !isfinite(state.estimates[m]) ? :nonfinite_loss :
            !all(isfinite,values) || !isfinite(state.scale[m]) ? :nonfinite_linearization :
            allequal(values) || maximum(abs,values) <= 64eps(Float64)*state.scale[m] ? :first_order_degenerate :
            :first_order_candidate
        mcse = missing
        diagnostic = nothing
        if status === :first_order_candidate
            r = only(B.posterior_mcse(reshape(values,:,1);chains=layout.chains,
                parameter_names=[String(LOSS_METRICS[m])],probabilities=()))
            mcse = r.mean_mcse
            diagnostic = only(B._candidate_mcmc_diagnostic_rows(reshape(values,:,1),
                [String(LOSS_METRICS[m])],layout.chains;parameter_space=:predictive_loss_linearization,split_chains=true,
                rhat_threshold=1.01,ess_threshold=400.))
            if ismissing(mcse) || !isfinite(mcse) || mcse <= 0
                status = :mcse_unavailable
                mcse = missing
            end
        end
        (;metric=LOSS_METRICS[m],estimate=state.estimates[m],status,mcse,diagnostic)
    end
    return (;rows,influence=state.influence,n_prediction_draws=size(state.influence,1),
        n_chains=layout.chains,weighting=:global_equal_person_equal_dimension,
        method=:first_order_delta_with_joint_row_influence,
        convergence_review_required=true,curvature_review_required=true,
        precision_threshold_applied=false,scientific_acceptance=false)
end

"""Small-array reference path; fit preparation streams the same arithmetic.
Numerical cancellation is unresolved, never evidence of zero Monte Carlo error.
"""
function predictive_loss_mcse(logdraws,truth;categories,weights,chain_ids,iterations)
    logs,ndraws = B._mgmfrm_mean_predicted_probabilities(logdraws,1e-8;log_probabilities=true)
    ndims(logdraws) == 3 || throw(ArgumentError("Individual retained predictive draws required"))
    state = loss_delta_setup(logs,truth,categories,weights,ndraws)
    loss_delta_add!(state,logdraws,1:ndraws)
    return loss_delta_finish(state;chain_ids,iterations)
end

function combine_fold_mcse(attempts,complete,dependence)
    available = complete && all(r -> hasproperty(r,:monte_carlo_error) && r.monte_carlo_error !== nothing,attempts)
    if available
        all(r -> hasproperty(r.reference,:seed),attempts) || throw(ArgumentError("Fold fit seeds required"))
        length(unique(r.reference.seed for r in attempts)) == length(attempts) ||
            throw(ArgumentError("Fold fits reuse an RNG seed"))
        for r in attempts
            e = r.monte_carlo_error
            e.n_prediction_draws == r.n_prediction_draws && e.n_chains == 4 &&
                e.weighting === :global_equal_person_equal_dimension &&
                getproperty.(e.rows,:metric) == collect(LOSS_METRICS) ||
                throw(ArgumentError("Fold MCSE scope mismatch"))
        end
    end
    rows = map(LOSS_METRICS) do metric
        parts = available ? [only(filter(x -> x.metric === metric,r.monte_carlo_error.rows)) for r in attempts] : []
        usable = available && all(p -> p.status === :first_order_candidate &&
            !ismissing(p.mcse) && isfinite(p.mcse) && p.mcse > 0,parts)
        status = !complete ? :incomplete_folds : !available ? :mcse_unavailable :
            dependence.status === :unresolved ? :dependence_unresolved :
            !usable ? :linearization_unresolved : :first_order_candidate
        (;metric,status,mcse=status === :first_order_candidate ? sqrt(sum(p.mcse^2 for p in parts)) : missing)
    end
    return (;rows,fold_independence=dependence,independence_verified=false,
        curvature_review_required=true,convergence_review_required=true,
        precision_threshold_applied=false,scientific_acceptance=false)
end

# One dataset is one replication. These are not within-fit MCMC standard errors.
replication_mcse(values,dependence) = dependence.status === :declared_independent && length(values) >= 2 ?
    std(values)/sqrt(length(values)) : missing

function recovery_dataset_rows(plan,attempts;parameter=nothing,dimension=nothing,interval=.9)
    plan.mode in (:fixed,:recovery) && interval in (.9,.95) &&
        ((parameter isa AbstractString && dimension === nothing) ||
        (parameter === nothing && dimension isa Integer && !(dimension isa Bool) && dimension in 1:2)) ||
        throw(ArgumentError("Select one named parameter OR one person dimension, and 90/95% intervals"))
    names = parameter === nothing ? ["person[$p,dim=$dimension]" for p in P.PERSONS] : [String(parameter)]
    return map(attempt_ledger(plan,attempts)) do l
        values = nothing
        status = l.status
        if status === :prepared
            rows = [only(filter(x -> x.parameter == name,l.result.rows)) for name in names]
            if any(r -> !r.local_precision_passed || r.mcse.mcse_status !== :available,rows)
                status = :mcse_unavailable
            else
                interval == .95 && (rows = [merge(r,r.interval95) for r in rows])
                values = (;bias=mean(r.error for r in rows),mse=mean(r.error^2 for r in rows),
                    coverage=mean(r.covered for r in rows),width=mean(r.width for r in rows))
                all(isfinite,values) || (status=:nonfinite_summary; values=nothing)
            end
        end
        (;l.id,status,n_parameters=length(names),values,result=l.result)
    end
end

function summarize_person_dimension(plan,attempts;dimension,interval=.9,dataset_independence)
    V._check_dependence(dataset_independence)
    ledger = recovery_dataset_rows(plan,attempts;dimension,interval)
    rows = [Base.structdiff(l,(;result=nothing)) for l in ledger]
    selected = [l.values for l in ledger if l.status === :prepared]
    n,N = length(selected),length(ledger)
    stats = map((:bias,:mse,:coverage,:width)) do metric
        values = [getproperty(r,metric) for r in selected]
        (;metric,estimate=n == 0 ? missing : mean(values),replication_mcse=replication_mcse(values,dataset_independence))
    end
    mse = n == 0 ? missing : mean(r.mse for r in selected)
    coverage = sum((r.coverage for r in selected);init=0.)
    return (;dimension,interval,planned=N,usable=n,unresolved=N-n,rows,statistics=stats,
        rmse=ismissing(mse) ? missing : sqrt(mse),
        rmse_replication_mcse=ismissing(mse) || mse == 0 ? missing :
            replication_mcse([r.mse for r in selected],dataset_independence)/(2sqrt(mse)),
        all_attempt_coverage_bounds=(coverage/N,(coverage+N-n)/N),
        dataset_independence,replication_unit=:dataset,persons_per_dataset=50,
        within_fit_mcse_combined=false,selection_caveat=:conditional_on_complete_qualified_datasets,
        scientific_acceptance=false)
end

function checked_pair_plans(plan0,plan1)
    check_seal(plan0);check_seal(plan1)
    plan0.mode === plan1.mode === :recovery && plan0.condition == "R0" && plan1.condition == "R1" &&
        Set(plan0.ids) == Set(plan1.ids) && all(k -> getproperty(plan0,k) == getproperty(plan1,k),
            (:backend,:generator_sha256,:prior,:controls,:criteria)) ||
        throw(ArgumentError("R0/R1 must share the planned roster and evaluation settings"))
    return nothing
end

function checked_pair_inputs(inputs,seen_seeds)
    if !isempty(inputs)
        g = first(inputs).generation
        all(x -> x.generation.person_seed == g.person_seed && x.generation.score_seed == g.score_seed &&
            x.truth.raw_names == first(inputs).truth.raw_names &&
            x.truth.raw[1:109] == first(inputs).truth.raw[1:109] &&
            x.truth.raw[115:128] == first(inputs).truth.raw[115:128],inputs) ||
            throw(ArgumentError("Paired generating seeds/persons/fixed facets differ"))
        for x in inputs
            expected = x.generation.condition == "R0" ? [.7,1.3,.7,1.,1.3] : [.35,.5,.7,1.,1.3]
            isapprox(Float64.(x.truth.raw[110:114]),log.(expected);atol=1e-12,rtol=1e-12) ||
                throw(ArgumentError("Paired loadings do not match R0/R1"))
        end
        any(s -> s in seen_seeds,(g.person_seed,g.score_seed)) &&
            throw(ArgumentError("Generating RNG seed reused across planned pairs"))
        union!(seen_seeds,(g.person_seed,g.score_seed))
    end
    return nothing
end

"""R1 minus R0, paired by planned ID before any eligibility filtering. The DGP
shares persons and response uniforms, not observed responses or fitted posteriors.
"""
function paired_recovery(plan0,attempts0,plan1,attempts1;
        parameter=nothing,dimension=nothing,interval=.9,dataset_independence)
    V._check_dependence(dataset_independence)
    checked_pair_plans(plan0,plan1)
    a = recovery_dataset_rows(plan0,attempts0;parameter,dimension,interval)
    other = Dict(r.id=>r for r in recovery_dataset_rows(plan1,attempts1;parameter,dimension,interval))
    rows = NamedTuple[]
    seen_seeds = Set{Int}()
    fit_seeds,fit_hashes = Set{Int}(),Set{String}()
    for r0 in a
        r1 = other[r0.id]
        inputs = [r.result.input for r in (r0,r1) if r.result !== nothing && r.result.input !== nothing]
        checked_pair_inputs(inputs,seen_seeds)
        fits = [r.result.reference for r in (r0,r1) if r.result !== nothing && r.result.kind === :recovery]
        for fit in fits
            fit.seed in fit_seeds || fit.sha256 in fit_hashes ?
                throw(ArgumentError("Paired study must use distinct fits and fit RNG seeds")) : nothing
            push!(fit_seeds,fit.seed);push!(fit_hashes,fit.sha256)
        end
        complete = r0.status === r1.status === :prepared
        differences = complete ? map(-,r1.values,r0.values) : nothing
        push!(rows,(;id=r0.id,status=complete ? :paired : :unresolved,
            R0_status=r0.status,R1_status=r1.status,R0=r0.values,R1=r1.values,differences))
    end
    selected = filter(r -> r.status === :paired,rows)
    n,N = length(selected),length(rows)
    stats = map((:bias,:mse,:coverage,:width)) do metric
        values = [getproperty(r.differences,metric) for r in selected]
        (;metric,estimate=n == 0 ? missing : mean(values),replication_mcse=replication_mcse(values,dataset_independence))
    end
    rmse0,rmse1 = n == 0 ? (missing,missing) :
        (sqrt(mean(r.R0.mse for r in selected)),sqrt(mean(r.R1.mse for r in selected)))
    rmse_mcse = n == 0 || rmse0 == 0 || rmse1 == 0 ? missing :
        replication_mcse([r.R1.mse/(2rmse1)-r.R0.mse/(2rmse0) for r in selected],dataset_independence)
    coverage = sum((r.differences.coverage for r in selected);init=0.)
    return (;parameter,dimension,interval,direction=:R1_minus_R0,planned=N,usable=n,unresolved=N-n,
        rows,statistics=stats,rmse_difference=rmse1-rmse0,rmse_difference_replication_mcse=rmse_mcse,
        all_attempt_coverage_difference_bounds=((coverage-(N-n))/N,(coverage+(N-n))/N),
        dataset_independence,replication_unit=:dataset_pair,within_fit_mcse_combined=false,
        selection_caveat=:conditional_on_jointly_qualified_pairs,scientific_acceptance=false)
end
