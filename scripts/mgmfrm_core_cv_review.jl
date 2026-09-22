# Included in MGMFRMCoreEvaluation. Finite chain checks and complete-roster CV
# summaries; neither executes refits nor promotes a numerical acceptance policy.

"""Sixteen chronological 250-draw means from the fixed 4 x 1000 kept draws.
This is one prediction pass, not new sampling or independent block replication.
"""
function predictive_blocks(design,direct;chain_ids,iterations)
    order=V.chain_order(chain_ids,iterations,size(direct,1))
    order.chains==4 && size(direct,1)==4000 ||
        throw(ArgumentError("Finite review requires the original four 1000-draw chains"))
    blocks=Array{Float64}(undef,4,4,design.spec.data.n,4)
    for c in 1:4,b in 1:4
        rows=order.order[(c-1)*1000+(b-1)*250+1:(c-1)*1000+b*250]
        blocks[c,b,:,:]=mean_log_probabilities(design,direct[rows,:])
    end
    return blocks
end

"""Predeclared nested prefixes and disjoint early/late halves. Differences are
observed sensitivity only: correlated blocks cannot bound unvisited-tail bias.
The reported full-draw score always retains all 4000 draws.
"""
function predictive_resolution(blocks,truth;categories,weights)
    ndims(blocks)==4 && size(blocks,1)==size(blocks,2)==size(blocks,4)==4 ||
        throw(ArgumentError("Expected four chains, four equal chronological quarters and four categories"))
    n=size(blocks,3)
    # Check every block, including normalization; pooling alone could mask errors.
    for c in 1:4,b in 1:4
        loss_delta_setup(blocks[c,b,:,:],truth,categories,weights,1)
    end
    pool(x)=first(B._mgmfrm_mean_predicted_probabilities(x,1e-8;log_probabilities=true))
    prefixes=map((1,2,4)) do count
        chains=cat([reshape(pool(blocks[c,1:count,:,:]),1,n,4) for c in 1:4]...;dims=1)
        (;draws_per_chain=250count,n_draws=1000count,
            curvature=predictive_curvature(chains,truth;categories,weights))
    end
    half_loss(bs)=loss_delta_setup(pool(reshape(blocks[:,bs,:,:],8,n,4)),
        truth,categories,weights,1).estimates
    early,late=half_loss(1:2),half_loss(3:4)
    rows=map(1:4) do m
        values=[p.curvature.rows[m].pooled_loss for p in prefixes]
        finite=all(isfinite,[values;early[m];late[m]])
        (;metric=LOSS_METRICS[m],prefix_losses=values,full_loss=values[end],
            prefix_minus_full=values.-values[end],early_half_loss=early[m],late_half_loss=late[m],
            late_minus_early=late[m]-early[m],
            status=finite ? :observed_sensitivity_only : :nonfinite_sensitivity)
    end
    return (;rows,prefixes,block_draws=250,blocks_per_chain=4,n_prediction_draws=4000,
        chronology=:within_chain_iteration,nested_prefixes_independent=false,
        halves_independent=false,bias_bound_available=false,automatic_extension=false,
        numerical_precision_accepted=false,scientific_acceptance=false)
end

"""Exact Taylor remainders at equal-length chain means. A convexity gap is an
observed discrepancy, NOT an upper bound on bias or error at the unknown mean.
"""
function predictive_curvature(chain_logmeans,truth;categories,weights)
    ndims(chain_logmeans)==3 && size(chain_logmeans,1)>=2 ||
        throw(ArgumentError("At least two equally weighted chain-mean probability matrices required"))
    pooled,nchains=B._mgmfrm_mean_predicted_probabilities(chain_logmeans,1e-8;log_probabilities=true)
    state=loss_delta_setup(pooled,truth,categories,weights,nchains)
    loss_delta_add!(state,chain_logmeans,1:nchains)
    losses=reduce(vcat,[permutedims(loss_delta_setup(chain_logmeans[c,:,:],truth,
        categories,weights,1).estimates) for c in 1:nchains])
    rows=map(1:4) do m
        remainder=losses[:,m].-state.estimates[m].-state.influence[:,m]
        finite=all(isfinite,remainder) && isfinite(state.estimates[m])
        (;metric=LOSS_METRICS[m],pooled_loss=state.estimates[m],chain_losses=losses[:,m],
            linear_changes=state.influence[:,m],remainders=remainder,
            observed_jensen_gap=finite ? mean(losses[:,m])-state.estimates[m] : missing,
            maximum_absolute_remainder=finite ? maximum(abs,remainder) : missing,
            status=finite ? :observed_curvature_only : :nonfinite_curvature)
    end
    return (;rows,n_chains=nchains,equal_chain_lengths_required=true,
        bias_bound_available=false,curvature_adequacy_assessed=false,scientific_acceptance=false)
end

"""Review proposal: report primary NLL to .01 nat; allocate half a reporting
unit to three first-order MCSEs. It is not a scientific effect margin or a bias
bound. Keep unexplained curvature and convergence separate from this budget.
"""
cv_precision_proposal()=(;metric=LOSS_METRICS[1],reporting_resolution_nats=.01,
    three_mcse_budget_nats=.005,mcse_max=.005/3,mcse_ratio_max=.1,
    geometric_probability_factor=exp(.005),status=:review_proposal,adopted=false)

function cv_budget_report(metric,mcse,replication_error)
    policy=cv_precision_proposal()
    usable=!ismissing(mcse) && isfinite(mcse) && mcse>0
    relative=usable && !ismissing(replication_error) && isfinite(replication_error) && replication_error>0 ?
        mcse/replication_error : missing
    return (;policy,absolute_mcse_screen=metric!==policy.metric || !usable ? :unresolved :
            mcse<=policy.mcse_max ? :within_proposed_budget : :exceeds_proposed_budget,
        mcse_ratio=relative,relative_mcse_screen=ismissing(relative) ? :unresolved :
            relative<=policy.mcse_ratio_max ? :within_proposed_budget : :exceeds_proposed_budget,
        curvature_adequacy_assessed=false,numerical_precision_accepted=false)
end

function prepare_cv_dataset(plan,input,split,fold_attempts;fold_independence)
    result=assemble_cv(plan,input,split,fold_attempts;fold_independence)
    return seal((;id=input.id,plan_identity=plan.content_hash,kind=:cv,input,split,fold_attempts,
        fold_independence,result,scientific_acceptance=false))
end

function cv_dataset_ledger(plan,attempts;metric)
    metric in LOSS_METRICS && plan.mode in (:fixed,:recovery) || throw(ArgumentError("Wrong CV metric or plan"))
    check_seal(plan)
    lookup=V._attempt_results([(;id,target_identity=plan.content_hash) for id in plan.ids],
        [(;r.id,target_identity=r.plan_identity,result=r) for r in attempts])
    generation_hashes,cache_hashes,fit_seeds=Set{String}(),Set{String}(),Set{Int}()
    return map(plan.ids) do id
        r=get(lookup,id,nothing)
        status=:missing_attempt
        estimate=mcse=gap=missing
        quantity_diagnostics_passed=false
        if r!==nothing
            check_seal(r)
            if r.input!==nothing
                checked_panel(plan,r.input).id==id || throw(ArgumentError("CV attempt/input mismatch"))
                r.input.hashes.generation in generation_hashes && throw(ArgumentError("Repeated CV generation under another ID"))
                push!(generation_hashes,r.input.hashes.generation)
            end
            if r.kind===:failure
                r==failure(plan,id,r.status;detail=r.detail,input=r.input) || throw(ArgumentError("Malformed CV failure"))
                status=r.status
            else
                r.kind===:cv || throw(ArgumentError("Recovery/SBC records cannot substitute for CV"))
                actual=assemble_cv(plan,r.input,r.split,r.fold_attempts;fold_independence=r.fold_independence)
                isequal(actual,r.result) || throw(ArgumentError("CV score changed after assembly"))
                status=actual.status
                for fold in r.fold_attempts
                    hasproperty(fold,:reference) || continue
                    ref=fold.reference
                    ref.sha256 in cache_hashes || ref.seed in fit_seeds ?
                        throw(ArgumentError("CV fit or RNG seed reused across planned folds/datasets")) : nothing
                    push!(cache_hashes,ref.sha256);push!(fit_seeds,ref.seed)
                end
                if status===:assembled
                    estimate=getproperty(actual.score.summary,metric)
                    if !isfinite(estimate)
                        status=:nonfinite_loss
                    else
                        status=:descriptive_complete
                        error=only(filter(x -> x.metric===metric,actual.monte_carlo_error.rows))
                        # Actual loss diagnostics and observed curvature are retained
                        # separately; missing legacy fields cannot imply adequacy.
                        parts=[get(fold,:monte_carlo_error,nothing) for fold in r.fold_attempts]
                        details=all(!isnothing,parts) ? [only(filter(x -> x.metric===metric,p.rows)) for p in parts] : []
                        quantity_diagnostics_passed=length(details)==5 && all(x ->
                            hasproperty(x,:diagnostic) && x.diagnostic!==nothing && x.diagnostic.flag===:ok,details)
                        error.status===:first_order_candidate && quantity_diagnostics_passed && (mcse=error.mcse)
                        if all(p -> p!==nothing && hasproperty(p,:curvature),parts)
                            gaps=[only(filter(x -> x.metric===metric,p.curvature.rows)).observed_jensen_gap for p in parts]
                            all(x -> !ismissing(x) && isfinite(x),gaps) && (gap=sum(gaps))
                        end
                    end
                end
            end
        end
        (;id,status,estimate,first_order_mcse=mcse,observed_jensen_gap=gap,
            quantity_diagnostics_passed,numerical_precision_accepted=false,result=r)
    end
end

function cv_summary_stats(values,mcse_values,N;metric,dataset_independence,mcmc_independence,paired)
    V._check_dependence(dataset_independence);V._check_dependence(mcmc_independence)
    n=length(values)
    estimate=n==0 ? missing : mean(values)
    rep=replication_mcse(values,dataset_independence)
    within=n>0 && mcmc_independence.status===:declared_independent &&
        all(x -> !ismissing(x) && isfinite(x) && x>0,mcse_values) ? sqrt(sum(abs2,mcse_values))/n : missing
    bound=metric===:squared_category_probability_error ? 2. : metric===:squared_expected_score_error ? 9. : Inf
    total=sum(values;init=0.)
    lower=n==N ? total/N : paired && !isfinite(bound) ? missing : (total-(paired ? (N-n)*bound : 0.))/N
    upper=n==N ? total/N : isfinite(bound) ? (total+(N-n)*bound)/N : missing
    return (;planned=N,descriptive_complete=n,unresolved=N-n,descriptive_mean=estimate,
        descriptive_replication_mcse=rep,combined_first_order_mcse=within,
        all_attempt_mean_bounds=(lower,upper),all_attempt_mean_available=n==N,
        numerical_budget=cv_budget_report(metric,within,rep),dataset_independence,mcmc_independence,
        numerical_precision_accepted=false,scientific_acceptance=false,
        selection_caveat=:conditional_on_complete_finite_CV_scores_not_precision_qualified,
        replication_mcse_includes_residual_mcmc_error=true)
end

function summarize_cv(plan,attempts;metric,dataset_independence,
        mcmc_independence=(;status=:unresolved,evidence="Across-fit MCMC independence not reviewed"))
    ledger=cv_dataset_ledger(plan,attempts;metric)
    chosen=filter(r -> r.status===:descriptive_complete,ledger)
    stats=cv_summary_stats([r.estimate for r in chosen],[r.first_order_mcse for r in chosen],length(ledger);
        metric,dataset_independence,mcmc_independence,paired=false)
    return (;metric,condition=plan.condition,stats...,replication_unit=:dataset,
        rows=[Base.structdiff(r,(;result=nothing)) for r in ledger])
end

function paired_cv(plan0,attempts0,plan1,attempts1;metric,dataset_independence,
        mcmc_independence=(;status=:unresolved,evidence="Across-condition/fold MCMC independence not reviewed"))
    checked_pair_plans(plan0,plan1)
    left=cv_dataset_ledger(plan0,attempts0;metric)
    right=Dict(r.id=>r for r in cv_dataset_ledger(plan1,attempts1;metric))
    seeds,fit_seeds,hashes=Set{Int}(),Set{Int}(),Set{String}()
    rows=map(left) do a
        b=right[a.id]
        results=[r.result for r in (a,b) if r.result!==nothing]
        checked_pair_inputs([r.input for r in results if r.input!==nothing],seeds)
        cv=filter(r -> r.kind===:cv,results)
        if length(cv)==2
            cv[1].split.seed==cv[2].split.seed && cv[1].split.folds.fold_rows==cv[2].split.folds.fold_rows ||
                throw(ArgumentError("Paired CV must use the same predeclared split and heldout IDs"))
        end
        for r in cv,fold in r.fold_attempts
            hasproperty(fold,:reference) || continue
            ref=fold.reference
            ref.seed in fit_seeds || ref.sha256 in hashes ?
                throw(ArgumentError("Fit or RNG stream reused across paired CV conditions")) : nothing
            push!(fit_seeds,ref.seed);push!(hashes,ref.sha256)
        end
        usable=a.status===b.status===:descriptive_complete
        error=usable && !ismissing(a.first_order_mcse) && !ismissing(b.first_order_mcse) &&
            mcmc_independence.status===:declared_independent ? hypot(a.first_order_mcse,b.first_order_mcse) : missing
        (;id=a.id,status=usable ? :descriptive_pair : :unresolved,R0_status=a.status,R1_status=b.status,
            difference=usable ? b.estimate-a.estimate : missing,first_order_mcse=error,
            R0_observed_jensen_gap=a.observed_jensen_gap,R1_observed_jensen_gap=b.observed_jensen_gap)
    end
    chosen=filter(r -> r.status===:descriptive_pair,rows)
    stats=cv_summary_stats([r.difference for r in chosen],[r.first_order_mcse for r in chosen],length(rows);
        metric,dataset_independence,mcmc_independence,paired=true)
    return (;metric,direction=:R1_minus_R0,stats...,rows,replication_unit=:dataset_pair)
end
