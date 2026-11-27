# Uses the common fit/report lifecycle; saved reports need no resampling to draw.
function _additive_warning_caption(rep)
    (hasproperty(rep,:response_patterns) && hasproperty(rep.response_patterns,:issues)) || return join(rep.warnings," ")
    messages=Set{String}();parts=String[]
    for (code,label) in (("unused_interior_category","unused-interior-category"),
            ("unobserved_declared_endpoint","unobserved-endpoint"),
            ("constant_score_pattern","constant-score"))
        rows=filter(r->String(r.code)==code && r.message in rep.warnings,rep.response_patterns.issues)
        isempty(rows) && continue
        union!(messages,String(r.message) for r in rows)
        push!(parts,"$(length(rows)) $label")
    end
    isempty(parts) && return join(rep.warnings," ")
    # Only recognized pattern messages are summarized; all other warnings survive.
    remaining=[w for w in rep.warnings if !(w in messages)]
    summary="Observed rating-pattern issues: "*join(parts,"; ")*". "*
        "Counts refer to issue records within steps-owner groups, not distinct people or ratings. "*
        "Individual IDs, scores and counts remain in report.response_patterns.issues. "*
        "All observations/categories are retained; these are descriptive warnings, not exclusion or quality verdicts."
    join([remaining;summary]," ")
end

function _additive_model_title_prefix(rep)
    if hasproperty(rep, :api) && rep.api !== nothing
        fam = hasproperty(rep.api, :family) ? string(rep.api.family) : ""
        fam == "mixed_outcome_joint_explanatory" && return "Mixed-outcome joint model"
        fam == "gmfrm" && return "GMFRM"
        fam in ("mgmfrm", "scale_identified_mgmfrm") && return "Scale-identified MGMFRM"
        hasproperty(rep.api, :status) && string(rep.api.status) == "supported" &&
            return "1D MFRM"
    end
    return "Scalar rating model"
end

function plot_additive_report(rep;kind,size=nothing,annotation_io=stdout,style=nothing)
    rep.schema==B.AdditiveFacets.FAIR_REFERENCE_SCHEMA && return plot_fair_reference(rep;size,annotation_io)
    rep.schema in (B.AdditiveFacets.MIXED_PPC_SCHEMA,B.AdditiveFacets.MIXED_PREDICTION_SCHEMA) && return plot_mixed_report(rep;kind,size,annotation_io)
    rep.schema in (B.AdditiveFacets.BOUNDED_PPC_SCHEMA,B.AdditiveFacets.BOUNDED_PREDICTION_SCHEMA) && return plot_bounded_report(rep;kind,size,annotation_io)
    rep.schema in (B.AdditiveFacets.COUNT_PPC_SCHEMA,B.AdditiveFacets.COUNT_PREDICTION_SCHEMA) && return plot_count_report(rep;kind,size,annotation_io)
    rep.schema==B.AdditiveFacets.PRIOR_SCHEMA && return plot_additive_prior(rep;size,annotation_io)
    kind===:diagnostics && return plot_additive_trace(rep;size,annotation_io)
    kind===:prediction && return plot_additive_prediction(rep;size,annotation_io)
    offset=_annotation_offset(annotation_io)
    qualified=rep.qualification.qualified
    if kind===:posterior
        rows=rep.summary.rows
        fig=Figure(;size=something(size,(1050,180+32length(rows)+100offset)),fontsize=14)
        ax=Axis(fig[1+offset,1];yticks=(1:length(rows),[r.parameter for r in rows]),
            yreversed=true,ygridvisible=false,xlabel="Parameter value (units specified below)")
        vlines!(ax,[style===nothing ? 0. : style.reference];color=:gray60,linestyle=:dash)
        for (i,r) in enumerate(rows)
            color=style===nothing ? :steelblue4 : style.colors[i]
            marker=style===nothing ? (r.structurally_fixed ? :diamond : :circle) : style.markers[i]
            rangebars!(ax,[i],[r.lower],[r.upper];direction=:x,color,linewidth=2,whiskerwidth=8)
            scatter!(ax,[r.median],[i];marker,color,markersize=9)
        end
        ylims!(ax,length(rows)+.6,.4)
        if style!==nothing
            elements=[MarkerElement(;marker=:circle,color=style.palette.contains,markersize=10),
                MarkerElement(;marker=:rect,color=style.palette.excludes,markersize=10)]
            labels=["CrI contains $(style.reference)","CrI excludes $(style.reference)"]
            if :fixed in style.states
                push!(elements,MarkerElement(;marker=:diamond,color=:gray30,markersize=10));push!(labels,"Fixed value (not a CrI)")
            end
            Legend(fig[2+offset,1],elements,labels;orientation=:horizontal,framevisible=false)
        end
        note="Medians and $(round(100rep.summary.interval;digits=1))% equal-tailed credible intervals; fixed values use diamonds. " *
            (style===nothing ? "" : "Colors/shapes indicate whether the closed interval contains the reference $(style.reference), including equality at an endpoint. This is not a posterior null probability, practical-importance or fit-quality decision. ") *
            (hasproperty(rep.api,:family) && string(rep.api.family)=="mixed_outcome_joint_explanatory" ? "Outcome-specific link parameters, factor loadings, owner residual SDs, CPC correlations, and family observation parameters (ZOIB precision/endpoint logits, ordinal steps, or beta-binomial precision). " : hasproperty(rep.api,:family) && string(rep.api.family)=="scalar_explanatory_count" ? "Location effects/SDs: success-probability logits; coefficients: logits per predictor unit; precision: beta-binomial concentration (when present). " : hasproperty(rep.api,:family) && string(rep.api.family)=="scalar_explanatory_zoib" ? "Location effects/SDs: interior-mean logits; coefficients: logits per predictor unit; precision: beta concentration; endpoint parameters: logits; random slopes: interior logits per predictor unit; intercept/slope correlations: dimensionless (when present). " : "Effects/SDs: unit adjacent logits; coefficients: logits per supplied predictor unit (different columns need not be commensurable); white coordinates: standard-normal units. ") *
            (hasproperty(rep.api,:family) && string(rep.api.family)=="mixed_outcome_joint_explanatory" ? "Positive person effects raise proficiency; positive facet effects raise severity; outcomes with direction=:higher_is_less flip the location sign on that link. " : hasproperty(rep.api,:family) && string(rep.api.family)=="scalar_explanatory_count" ? "Positive person/response coefficients increase success log odds; positive facet coefficients decrease them. A listener effect need not represent rating severity. " : "Positive person/response coefficients raise ratings; positive facet coefficients raise severity and lower ratings. ") *
            "Whole-fit numerical qualification: $qualified. " *
            _additive_warning_caption(rep)
        fig_title = "$(_additive_model_title_prefix(rep)) · posterior intervals"
        return _figure_text!(fig,fig_title,note;annotation_io,bottom_row=2+offset+(style!==nothing))
    end
    kind===:predictive || throw(ArgumentError("additive reports support :posterior and :predictive"))
    fig=Figure(;size=something(size,(1100,440+120offset)),fontsize=14)
    for (j,rows) in enumerate((rep.rows,rep.groups))
        owned=hasproperty(rep,:grouping_by_support) && rep.grouping_by_support
        labels=j==1 ? [hasproperty(r,:level) ? "$(r.level): $(r.category)" : string(r.category) for r in rows] : [r.label for r in rows]
        ax=Axis(fig[1+offset,j];xticks=(1:length(rows),labels),
            xticklabelrotation=owned ? pi/4 : 0,
            xlabel=j==1 ? (owned ? "Step owner and rating category" : "Rating category") : (owned ? "Groups within category support" : "$(rep.groupby===nothing ? "All observations" : rep.groupby)"),
            ylabel=j==1 ? "Number of ratings" : "Mean rating")
        rangebars!(ax,1:length(rows),[r.lower for r in rows],[r.upper for r in rows];color=:steelblue4,linewidth=2,whiskerwidth=8)
        scatter!(ax,1:length(rows),[r.median for r in rows];color=:steelblue4,markersize=9,label="Replicated median / interval")
        scatter!(ax,1:length(rows),[r.observed for r in rows];color=:black,marker=:diamond,markersize=9,label="Observed")
        j==1 && ylims!(ax,0,nothing)
        j==1 && Legend(fig[2+offset,1:2],ax;orientation=:horizontal,framevisible=false)
    end
    note="POSTERIOR predictive check: observed black diamonds versus replicated medians and $(round(100rep.interval;digits=1))% pointwise predictive intervals. " *
        "$(rep.ndraws) replicate datasets share one posterior parameter draw per dataset; known owners and observed design retained. " *
        (hasproperty(rep,:grouping_by_support) && rep.grouping_by_support ? "Category counts and raw-score means are separated by step owner; raw means across different supports are not commensurable. " : "") *
        "Whole-fit numerical qualification: $qualified. " * _additive_warning_caption(rep)
    _figure_text!(fig,"$(_additive_model_title_prefix(rep)) · posterior predictive check",note;annotation_io,bottom_row=3+offset,columns=2)
end

function plot_fair_reference(rep;size=nothing,annotation_io=stdout)
    rows=rep.rows; offset=_annotation_offset(annotation_io); n=length(rows)
    target=string(rep.interval_target)
    label=target=="wald_expected_score" ? "Estimate / Wald CI" : target=="conditional_posterior_expected_score" ? "Conditional mean / CrI" : "Posterior mean / CrI"
    endpoint(x)=x===nothing || ismissing(x) ? NaN : Float64(x)
    title="Common-plan Fair Average"*(string(rep.conditioning)=="marginal_new" ? ": New events" : string(rep.conditioning)=="zero" ? ": Zero shared effects" : "")
    mode=get(rep,:interaction_effects,nothing)
    mode===nothing || (title*=string(mode)=="fitted" ? "\nFitted interactions" : "\nZero interaction reference")
    fig=Figure(;size=something(size,(900,180+32n+100offset)),fontsize=14)
    ax=Axis(fig[1+offset,1];yticks=(1:n,[r.person_label for r in rows]),
        yreversed=true,ygridvisible=false,xlabel="Score",ylabel="Person")
    annotation_io===nothing || (ax.title=title)
    rangebars!(ax,1:n,[endpoint(r.lower) for r in rows],[endpoint(r.upper) for r in rows];direction=:x,
        color=:steelblue4,linewidth=2,whiskerwidth=8)
    scatter!(ax,[r.mean for r in rows],1:n;color=:steelblue4,label="$label ($(round(100rep.interval;digits=1))%)")
    ix=findall(r->r.observed_average!==nothing && !ismissing(r.observed_average),rows)
    scatter!(ax,[rows[j].observed_average for j in ix],ix;color=:black,marker=:diamond,label="Observed average")
    ylims!(ax,n+.6,.4)
    Legend(fig[2+offset,1],ax;orientation=:horizontal,framevisible=false)
    note="$(round(100rep.interval;digits=1))% intervals for expected scores under the same $(length(rep.reference_plan))-cell reference plan. " *
        (target=="posterior_expected_score" ? "All retained joint draws propagate calibration and person uncertainty. " : "") *
        "Conditioning: $(rep.conditioning). These are not future-rating prediction intervals. " *
        "Whole-fit numerical qualification: $(rep.qualification.qualified). " * join(rep.warnings," ")
    _figure_text!(fig,title,note;annotation_io,bottom_row=3+offset)
end

function plot_additive_prior(rep;size,annotation_io)
    offset=_annotation_offset(annotation_io);rows=rep.rows
    labels=[hasproperty(r,:level) ? "$(r.level): $(r.category)" : string(r.category) for r in rows]
    fig=Figure(;size=something(size,(950,450+120offset)),fontsize=15)
    ax=Axis(fig[1+offset,1];xticks=(1:length(rows),labels),
        xticklabelrotation=rep.grouping_by_support ? pi/4 : 0,
        xlabel=rep.grouping_by_support ? "Step owner and rating category" : "Rating category",
        ylabel="Prior replicated count")
    rangebars!(ax,1:length(rows),[r.lower for r in rows],[r.upper for r in rows];color=:purple3,linewidth=2,whiskerwidth=8)
    scatter!(ax,1:length(rows),[r.median for r in rows];color=:purple3,markersize=10)
    ylims!(ax,0,nothing)
    note="PRIOR predictive check: medians and $(round(100rep.interval;digits=1))% pointwise intervals for replicated category counts, " *
        "$(rep.ndraws) replicas. Parameters are drawn from the declared prior, not a fitted posterior; observed scores are not used to condition predictions. " *
        "Source: $(rep.source). No convergence qualification applies to a prior simulation. " * join(rep.warnings," ")
    _figure_text!(fig,"$(_additive_model_title_prefix(rep)) · prior predictive check",note;annotation_io,bottom_row=2+offset)
end

function plot_additive_trace(rep;size,annotation_io)
    t=rep.traces;offset=_annotation_offset(annotation_io);cols=min(2,length(t.parameters));nr=cld(length(t.parameters),cols)
    fig=Figure(;size=something(size,(1150,240nr+90+120offset)),fontsize=14)
    colors=_response_category_colors(t.chains);firstaxis=nothing
    for (j,name) in enumerate(t.parameters)
        ax=Axis(fig[cld(j,cols)+offset,mod1(j,cols)];title=name,
            xlabel="Retained iteration",ylabel=string(t.scale)=="raw" ? "Raw coordinate (see parameter name)" : "Model coordinate")
        firstaxis===nothing && (firstaxis=ax)
        for c in 1:t.chains
            s=only(filter(s->s.parameter==name && s.chain==c,t.series))
            lines!(ax,s.iterations,s.values;color=(colors[c],.7),linewidth=.7,label="Chain $c")
        end
    end
    Legend(fig[nr+1+offset,1:cols],firstaxis;orientation=:horizontal,framevisible=false)
    note="Retained MCMC traces, $(t.chains) chains × $(t.draws_per_chain) draws; warmup is not displayed. " *
        "The original chain/iteration ordering is retained without thinning. Visually overlapping traces do not prove convergence. " *
        "Read R-hat, bulk/tail ESS, divergences, tree depth, E-BFMI and focal MCSE alongside these panels. " *
        "Whole-fit numerical qualification: $(rep.qualification.qualified). " * _additive_warning_caption(rep)
    trace_title = "$(_additive_model_title_prefix(rep)) · retained-chain traces"
    _figure_text!(fig,trace_title,note;annotation_io,bottom_row=nr+2+offset,columns=cols)
end

function plot_additive_prediction(rep;size,annotation_io)
    offset=_annotation_offset(annotation_io);K=length(rep.category_levels);cols=min(2,K);nr=cld(K,cols)
    fig=Figure(;size=something(size,(1050,300nr+120offset)),fontsize=14)
    for (j,k) in enumerate(rep.category_levels)
        rows=filter(r->r.category==k,rep.cells);x=1:length(rows)
        ax=Axis(fig[cld(j,cols)+offset,mod1(j,cols)];title="Category $k",xticks=(x,string.(rep.rows)),
            xlabel="Selected rating row",ylabel="Category probability")
        rangebars!(ax,x,[r.lower for r in rows],[r.upper for r in rows];color=:steelblue4,linewidth=2,whiskerwidth=8)
        for (i,r) in enumerate(rows)
            scatter!(ax,[i],[r.mean];color=r.structural_zero ? :gray50 : :steelblue4,
                marker=r.structural_zero ? :diamond : :circle,markersize=9)
        end
        ylims!(ax,-.03,1.03)
    end
    is_new=hasproperty(rep,:mode) && String(rep.mode)=="new_owners"
    note="Posterior category probabilities for explicitly selected rating rows: means and $(round(100rep.interval;digits=1))% pointwise credible intervals. " *
        "Diamonds mark structural zeros outside the row's declared support. These are intervals for probabilities, not future-rating predictive intervals. " *
        (is_new ? "NEW-OWNER prediction (mode=:new_owners, new_owners=$(collect(rep.new_owners)), seed=$(rep.seed)): fresh latent owner effects were drawn from fitted population priors at each posterior draw; zero-effect substitution was NOT used. " : "Conditioning: $(rep.conditioning); these are not new-owner or causal predictor effects. ") *
        "Row attributes and probability MCSE are retained in the report. " *
        "Whole-fit numerical qualification: $(rep.qualification.qualified). " * _additive_warning_caption(rep)
    pred_title=is_new ? "$(_additive_model_title_prefix(rep)) · new-owner population-integrated probabilities" : "$(_additive_model_title_prefix(rep)) · conditional category probabilities"
    _figure_text!(fig,pred_title,note;annotation_io,bottom_row=nr+1+offset,columns=cols)
end
