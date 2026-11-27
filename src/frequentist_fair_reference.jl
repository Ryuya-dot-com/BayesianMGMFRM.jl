# No simulated posterior is created for a maximum-likelihood fit.
function _legacy_fair_reference_basis(f)
    A=AdditiveFacets; F=FrequentistMFRM;r=f.record;p=r.problem;l=r.layout;P=length(p.person_levels)
    jmle=p.method===:jmle;offset=jmle ? P : 0
    jmle && r.summary.extreme_adjustment>0 && throw(ArgumentError("common-plan joint Wald scoring requires unadjusted JMLE (extreme_adjustment=0)"))
    laststruct=last(last(l.step_full_ranges)); si=offset+1:laststruct
    # Legacy display names can alias typed IDs (e.g. 1 and "1"); index the saved coefficients unambiguously.
    coefficient(i)="calibration[$(i-offset)]"
    facets=[(;name=fb.name,levels=deepcopy(fb.levels),parameters=coefficient.(l.facet_full_ranges[k]),sign=fb.sign) for (k,fb) in enumerate(p.facets)]
    steps=[(;level=deepcopy(p.step_group_levels[g]),categories=collect(p.supports[g]),parameters=coefficient.(l.step_full_ranges[g])) for g in eachindex(p.supports)]
    people=map(1:P) do i
        ix=findall(==(i),p.person_idx);cats=[steps[p.step_group[n]].categories for n in ix];same=allequal(cats)
        (;level=deepcopy(p.person_levels[i]),parameter="person[$(repr(p.person_levels[i]))]",n_observations=length(ix),
            observed_average=same ? mean(p.raw_score[ix]) : missing,observed_categories=same ? first(cats) : nothing)
    end
    parameters=vcat(getproperty.(people,:parameter),coefficient.(si))
    values=vcat([jmle ? row.limit_estimate : row.eap for row in r.person_scores],r.full_parameters[si])
    rows(M)=[collect(row) for row in eachrow(M)]
    delta=nothing;posterior=nothing
    if jmle
        sch=F.jmle_exact_hessian_and_schur_cov(r.u_free,p,l)
        if hasproperty(sch,:cov_full) || isempty(sch.D_theta)
            delta=(;full_covariance=rows(sch.ok ? sch.cov_full : fill(NaN,length(values),length(values))))
        else
            d=length(l.person_free_range);cols=d+1:l.n_free;D=zeros(P);H=zeros(P,length(cols))
            for col in l.person_free_range
                i=only(findall(!iszero,l.J_mat[1:P,col]))
                D[i]=sch.D_theta[col];H[i,:]=sch.H_theta_psi[col,:]
            end
            invD=[isfinite(p.person_anchors[i]) ? 0. : D[i]>0 ? inv(D[i]) : NaN for i in 1:P]
            delta=(;inverse_information=invD,projection=rows(invD.*H),
                structural_covariance=rows(sch.ok ? sch.cov_psi : fill(NaN,length(cols),length(cols))),model_map=rows(Matrix(l.J_mat[si,cols])))
        end
    else
        quad=F.build_quadrature(r.summary.quadrature,r.summary.quad_points;sd=1.,theta_lim=r.summary.theta_lim)
        nodes=r.summary.population_mean.+r.summary.population_sd.*quad.std_nodes
        posterior=map(1:P) do i
            logw=log.(quad.weights)
            for n in findall(==(i),p.person_idx)
                shift=sum(fb.sign*r.full_parameters[l.facet_full_ranges[k][fb.index[n]]] for (k,fb) in enumerate(p.facets))
                tau=r.full_parameters[l.step_full_ranges[p.step_group[n]]]
                for q in eachindex(nodes)
                    z=vcat(0.,cumsum(nodes[q]+shift.-tau));zm=maximum(z)
                    logw[q]+=p.weights[n]*(z[p.score_k[n]+1]-zm-log(sum(exp.(z.-zm))))
                end
            end
            weights=exp.(logw.-maximum(logw));weights./=sum(weights)
            (;nodes=copy(nodes),weights)
        end
    end
    (;schema=A.FAIR_REFERENCE_BASIS_SCHEMA,kernel=:additive,facets,steps,people,
        owner=p.step_owner,intercept=nothing,shared=NamedTuple[],
        frequentist=(;method=p.method,parameters,values,delta,posterior,
            quadrature=jmle ? nothing : (;rule=r.summary.quadrature,nodes=r.summary.quad_points,theta_lim=r.summary.theta_lim)))
end

function AdditiveFacets.fair_reference_basis(f::FrequentistMFRM.Fit)
    r=FrequentistMFRM.checked(f); p=r.problem
    p.method===:jmle && r.summary.extreme_adjustment>0 && throw(ArgumentError("common-plan joint Wald scoring requires unadjusted JMLE (extreme_adjustment=0)"))
    hasproperty(r,:mrcml_operator) || return _legacy_fair_reference_basis(f)
    op=r.mrcml_operator
    all(b->b.kind in AdditiveFacets.FAIR_REFERENCE_BLOCKS,op.block_meta) ||
        throw(ArgumentError("common-plan scoring requires structured facets, steps and supported interactions"))
    facets=[(;name=b.name,levels=deepcopy(b.levels),parameters=op.model_names[b.model_range]) for b in op.block_meta if b.kind===:facet_main]
    sb=filter(b->b.kind===:steps,op.block_meta)
    steps=[(;level=deepcopy(p.step_group_levels[g]),categories=copy(r.mrcml_category_labels[g]),parameters=op.model_names[sb[g].model_range]) for g in eachindex(sb)]
    people=map(eachindex(p.person_levels)) do i
        ix=findall(==(i),p.person_idx); supports=[steps[p.step_group[n]].categories for n in ix]
        same=allequal(supports)
        (;level=deepcopy(p.person_levels[i]),parameter="person[$(repr(p.person_levels[i]))]",
            n_observations=length(ix),observed_average=same ? mean(p.raw_score[ix]) : missing,
            observed_categories=same ? first(supports) : nothing)
    end
    ib=filter(b->b.kind===:population_mean,op.block_meta)
    interactions=AdditiveFacets._fair_reference_interactions(op)
    context_roles=unique([role for term in interactions for role in term.roles if !(role in getproperty.(facets,:name))])
    contexts=map(context_roles) do role
        pop=get(r.summary,:population,nothing)
        pop!==nothing && get(pop.design,:group_column,nothing)===role ||
            throw(ArgumentError("reference interaction role $role has no saved person context"))
        pd=pop.design
        ix=[findfirst(x->isequal(x,p.level),pd.people) for p in people]
        all(!isnothing,ix) || throw(ArgumentError("population context does not match fitted persons"))
        (;name=role,values=deepcopy(pd.groups[pd.group_index[ix]]))
    end
    b=(;schema=isempty(interactions) ? AdditiveFacets.FAIR_REFERENCE_BASIS_SCHEMA : AdditiveFacets.FAIR_REFERENCE_INTERACTION_BASIS_SCHEMA,
        kernel=:additive,facets,steps,people,interactions,contexts,
        owner=p.step_owner,intercept=isempty(ib) ? nothing : only(op.model_names[only(ib).model_range]),shared=NamedTuple[])
    xi=op.xi0_model+op.J_model*r.eta_free
    parameters=vcat(getproperty.(people,:parameter),op.model_names)
    values=vcat(getproperty.(r.person_scores,:estimate),xi)
    P=length(people); d=size(op.A_free,2); vp=op.c_pat+op.A_free*r.eta_free
    # Store matrices by rows for a language-neutral saved blueprint.
    rows(M)=[collect(row) for row in eachrow(M)]
    delta=nothing; posterior=nothing
    if p.method===:jmle
        D=zeros(P); H=zeros(P,d)
        for n in r.layout.active_rows
            i=p.person_idx[n]; isfinite(values[i]) || continue
            ix=op.pattern_ranges[op.pattern_of_row[n]]
            z=op.B_pat[ix].*values[i].+vp[ix]; pr=exp.(z.-maximum(z)); pr./=sum(pr)
            bc=op.B_pat[ix].-dot(pr,op.B_pat[ix]); af=Matrix(op.A_free[ix,:])
            D[i]+=p.weights[n]*dot(pr,bc.^2)
            H[i,:].+=p.weights[n].*(af'*(pr.*bc))
        end
        invD=[x>0 ? inv(x) : NaN for x in D]
        delta=(;inverse_information=invD,projection=rows(invD.*H),
            structural_covariance=rows(r.covariance.free_covariance),model_map=rows(Matrix(op.J_model)))
    else
        quad=FrequentistMFRM.build_quadrature(r.summary.quadrature,r.summary.quad_points;sd=1.,theta_lim=r.summary.theta_lim)
        posterior=map(1:P) do i
            mu,sd=FrequentistMFRM._mrcml_person_law(r.summary,i)
            nodes=mu.+sd.*quad.std_nodes; logw=log.(quad.weights)
            for n in findall(==(i),p.person_idx)
                ix=op.pattern_ranges[op.pattern_of_row[n]]
                for q in eachindex(nodes)
                    z=op.B_pat[ix].*nodes[q].+vp[ix]; zm=maximum(z)
                    logw[q]+=p.weights[n]*(z[p.score_k[n]+1]-zm-log(sum(exp.(z.-zm))))
                end
            end
            weights=exp.(logw.-maximum(logw));weights./=sum(weights)
            (;nodes,weights)
        end
    end
    merge(b,(;frequentist=(;method=p.method,parameters,values,delta,posterior,
        quadrature=p.method===:jmle ? nothing : (;rule=r.summary.quadrature,nodes=r.summary.quad_points,theta_lim=r.summary.theta_lim))))
end

function _fair_point_gradient(b,plan,x,names,p;theta=x[p])
    col=Dict(n=>i for (i,n) in enumerate(names)); g=zeros(length(x)); value=0.
    if !isfinite(theta)
        return (;value=theta==Inf ? maximum(plan.categories) : theta==-Inf ? minimum(plan.categories) : NaN,gradient=fill(NaN,length(x)))
    end
    for j in eachindex(plan.weights)
        loc=theta+(b.intercept===nothing ? 0. : x[col[b.intercept]])
        fs=[col[f.parameters[plan.indices[k][j]]] for (k,f) in enumerate(b.facets)]
        signs=[get(f,:sign,-1) for f in b.facets]
        adjustment=get(plan,:adjustments,nothing)===nothing ? nothing : plan.adjustments[p][j]
        if adjustment!==nothing
            append!(fs,[col[n] for n in adjustment.location]);append!(signs,fill(-1,length(adjustment.location)))
        end
        loc+=dot(signs,x[fs]); ts=[col[n] for n in b.steps[plan.groups[j]].parameters]
        extra=adjustment===nothing ? [Int[] for _ in ts] : [[col[n] for n in ns] for ns in adjustment.steps]
        tau=[x[ts[h]]+sum(x[extra[h]]) for h in eachindex(ts)]
        z=vcat(0.,cumsum(loc.-tau)); pr=exp.(z.-maximum(z));pr./=sum(pr)
        e=dot(pr,plan.categories); centered=plan.categories.-e
        dl=dot(pr.*centered,0:length(z)-1)*plan.weights[j]
        value+=plan.weights[j]*e;g[p]+=dl
        b.intercept===nothing || (g[col[b.intercept]]+=dl)
        g[fs].+=signs.*dl
        for (h,c) in enumerate(ts)
            dt=-plan.weights[j]*sum(pr[h+1:end].*centered[h+1:end])
            g[c]+=dt;g[extra[h]].+=dt
        end
    end
    (;value,gradient=g)
end

function _fair_weighted_summary(v,w;level,threshold=nothing,strict=false)
    ix=sortperm(v);cdf=cumsum(w[ix]);cdf[end]=1.
    q(a)=v[ix[searchsortedfirst(cdf,a)]]
    m=dot(v,w)
    event=if threshold===nothing
        nothing
    else
        threshold isa Real && !(threshold isa Bool) && isfinite(threshold) || throw(ArgumentError("threshold/margin must be finite"))
        (;threshold,operator=strict ? :greater : :greater_equal,
            probability=sum(w[strict ? v.>threshold : v.>=threshold]),mcse=missing,status=:deterministic_quadrature)
    end
    (;mean=m,median=q(.5),sd=sqrt(max(0.,dot(w,(v.-m).^2))),lower=q((1-level)/2),upper=q((1+level)/2),event)
end

function _frequentist_fair_reference(f;reference_plan=nothing,level=.95,threshold=nothing,comparisons=nothing,interaction_effects=nothing)
    reference_plan === nothing && throw(ArgumentError(
        "diagnostics(fit; kind = :fair_average) on FrequentistMFRM.Fit requires either `reference_plan = ...` (for common-plan person expected scores) or `by = :rater` / `:person` / `<facet>` (for FACETS-style marginal Fair-M / Fair-Z; `fair_m` and `fair_z` are also included in `facet_summary(fit)`)."))
    A=AdditiveFacets;A.interval_bounds(level)
    b=A.fair_reference_basis(f);plan=A._fair_reference_condition(b,A._fair_reference_plan(b,reference_plan),interaction_effects);d=b.frequentist
    jmle=d.method===:jmle
    jmle && threshold!==nothing && throw(ArgumentError("JMLE confidence intervals do not define posterior threshold probabilities"))
    P=length(b.people);vals=[_fair_point_gradient(b,plan,d.values,d.parameters,p) for p in 1:P]
    matrix(rows)=isempty(rows) ? zeros(0,0) : reduce(vcat,permutedims.(rows))
    fullcov=jmle && hasproperty(d.delta,:full_covariance)
    V=jmle ? matrix(fullcov ? d.delta.full_covariance : d.delta.structural_covariance) : nothing
    gamma=jmle ? [fullcov ? vals[p].gradient : matrix(d.delta.model_map)'*vals[p].gradient[P+1:end]-d.delta.projection[p]*vals[p].gradient[p] for p in 1:P] : nothing
    variance=jmle ? [(fullcov ? 0. : vals[p].gradient[p]^2*d.delta.inverse_information[p])+dot(gamma[p],V*gamma[p]) for p in 1:P] : nothing
    normal_z=quantile(Distributions.Normal(),(1+level)/2)
    wald(m,v)= (;mean=m,median=m,sd=isfinite(v)&&v>=0 ? sqrt(v) : missing,
        lower=isfinite(v)&&v>=0 ? m-normal_z*sqrt(v) : missing,
        upper=isfinite(v)&&v>=0 ? m+normal_z*sqrt(v) : missing,event=nothing)
    scores=jmle ? nothing : [[_fair_point_gradient(b,plan,d.values,d.parameters,p;theta).value for theta in d.posterior[p].nodes] for p in 1:P]
    rows=map(1:P) do p
        pb=b.people[p];obs=pb.observed_categories==plan.categories ? pb.observed_average : missing
        s=jmle ? wald(vals[p].value,variance[p]) : _fair_weighted_summary(scores[p],d.posterior[p].weights;level,threshold)
        (;person=pb.level,person_id=A.label_encoding(pb.level),person_label=string(pb.level),
            n_observations=pb.n_observations,observed_average=obs,adjustment_mean=s.mean-obs,
            plugin_mean=vals[p].value,s...)
    end
    contrasts=comparisons===nothing ? NamedTuple[] : map(collect(comparisons)) do c
        Set(propertynames(c))==Set((:left,:right,:margin)) || throw(ArgumentError("each comparison needs left, right and margin"))
        ids=[findfirst(pb->isequal(pb.level,x),b.people) for x in (c.left,c.right)]
        all(!isnothing,ids) && ids[1]!=ids[2] || throw(ArgumentError("comparisons require distinct known person IDs"))
        c.margin isa Real && !(c.margin isa Bool) && isfinite(c.margin) || throw(ArgumentError("margin must be finite"))
        l,r=ids
        s=if jmle
            wald(vals[l].value-vals[r].value,variance[l]+variance[r]-2dot(gamma[l],V*gamma[r]))
        else
            v=vec(scores[l].-scores[r]');w=vec(d.posterior[l].weights*d.posterior[r].weights')
            _fair_weighted_summary(v,w;level,threshold=c.margin,strict=true)
        end
        (;left=c.left,right=c.right,left_id=A.label_encoding(c.left),right_id=A.label_encoding(c.right),margin=c.margin,s...)
    end
    warnings=[f.record.warnings;A._fair_reference_interaction_warnings(b,interaction_effects);
        jmle ? "Wald intervals use the joint person/calibration observed-information covariance. They can exceed the score scale; extreme-person intervals are unavailable. Fixed anchors are treated as known." :
        "Conditional empirical-Bayes intervals/probabilities hold fitted calibration and population parameters fixed. They omit calibration-estimation uncertainty and are not full Bayesian intervals.";
        "Intervals describe common-plan expected scores, not future realized ratings. Whole-fit warnings remain applicable."]
    A.check_fair_reference_report((;schema=A.FAIR_REFERENCE_SCHEMA,kind=:fair_average,target=:common_plan_expected_average,
        method=d.method,conditioning=:known_facet_levels,by=:person,interval=level,reference_plan=plan.rows,
        interaction_effects,held_contexts=A._fair_reference_context_report(b),
        reference_ids=[(; (fb.name=>A.label_encoding(fb.levels[plan.indices[k][j]]) for (k,fb) in enumerate(b.facets))...) for j in eachindex(plan.rows)],
        category_levels=plan.categories,rows,contrasts,qualification=qualify(f),warnings,
        source_sample_content_hash=f.record.content_hash,n_draws=0,
        quadrature=jmle ? nothing : (;rule=f.record.summary.quadrature,nodes=f.record.summary.quad_points,theta_lim=f.record.summary.theta_lim),
        interval_target=jmle ? :wald_expected_score : :conditional_posterior_expected_score))
end

function _frequentist_marginal_fair_average(
        f::FrequentistMFRM.Fit;
        by::Symbol,
        level::Real = 0.95,
        baseline::Symbol = :sample_mean,
        step_group = nothing)
    AdditiveFacets.interval_bounds(level)
    baseline in (:sample_mean, :zero_origin) || throw(ArgumentError(
        "baseline must be :sample_mean (FACETS Fair-M) or :zero_origin (FACETS Fair-Z); got $(repr(baseline))"))
    r = FrequentistMFRM.checked(f)
    p = r.problem
    z_crit = Distributions.quantile(Distributions.Normal(), 0.5 * (1.0 + Float64(level)))
    by_sym = by === :entity ? :person : by
    is_person = by_sym === :person

    has_op = hasproperty(r, :mrcml_operator)
    cat_groups = has_op ? [Float64.(c) for c in r.mrcml_category_labels] : [Float64.(collect(sup)) for sup in p.supports]
    same_sup = has_op ? allequal(r.mrcml_category_labels) : allequal(p.supports)

    tau_groups = Vector{Float64}[]
    facet_signs = Dict{Symbol,Int}()
    facet_est_vecs = Dict{Symbol,Vector{Float64}}()
    step_int_map = Dict{Symbol,Tuple{Int,Vector{Float64}}}()
    mu_int = 0.0

    if has_op
        op = r.mrcml_operator
        xi = op.xi0_model + op.J_model * r.eta_free
        step_bms = [bm for bm in op.block_meta if bm.kind === :steps]
        !isempty(step_bms) && length(step_bms) == length(cat_groups) || throw(ArgumentError(
            "Fair Average Score requires structured step blocks matching category supports; custom unstructured design matrices without step block metadata are not supported"))
        for g in eachindex(step_bms)
            push!(tau_groups, Float64[xi[idx] for idx in step_bms[g].model_range])
        end
        for bm in op.block_meta
            if bm.kind in (:facet_main, :facet_lltm_strict, :facet_lltm_plus_residual)
                facet_signs[bm.name] = -1
                facet_est_vecs[bm.name] = Float64[xi[idx] for idx in bm.model_range]
            elseif bm.kind === :population_mean
                mu_int = xi[first(bm.model_range)]
            elseif bm.kind === :facet_step_interaction
                step_int_map[bm.f1] = (bm.n_steps, Float64[xi[idx] for idx in bm.model_range])
            end
        end
    else
        l = r.layout
        full = r.full_parameters
        for g in eachindex(p.supports)
            push!(tau_groups, Float64[full[idx] for idx in l.step_full_ranges[g]])
        end
        for (fi, fb) in enumerate(p.facets)
            facet_signs[fb.name] = fb.sign
            facet_est_vecs[fb.name] = Float64[full[idx] for idx in l.facet_full_ranges[fi]]
        end
    end

    if !is_person && !haskey(facet_est_vecs, by_sym)
        throw(ArgumentError("unknown `by = $(repr(by))` facet for Fair Average Score; available: :person, $(Tuple(keys(facet_est_vecs)))"))
    end

    chosen_g = nothing
    if step_group !== nothing
        gi = findfirst(gl -> isequal(gl, step_group) || string(gl) == string(step_group), p.step_group_levels)
        gi === nothing && throw(ArgumentError(
            "unknown `step_group = $(repr(step_group))`; available step groups: $(p.step_group_levels)"))
        chosen_g = gi
    elseif !same_sup && by_sym !== p.step_owner
        throw(ArgumentError(
            "Fair Average Score for `by = $(repr(by_sym))` under mixed category supports requires an explicit `step_group = ...` (available: $(p.step_group_levels)) because raw scores across unequal category ranges are not commensurable; or inspect `by = $(repr(p.step_owner))`."))
    end

    th_vec = Float64[
        (row.estimate === missing ? (hasproperty(row, :limit_estimate) ? Float64(row.limit_estimate) : NaN) : Float64(row.estimate))
        for row in r.person_scores
    ]
    fin_th = Float64[th for th in th_vec if isfinite(th)]
    th_bar = (isempty(fin_th) ? 0.0 : Statistics.mean(fin_th)) + mu_int
    f_signed_means = Dict{Symbol,Float64}(fn => facet_signs[fn] * Statistics.mean(vals) for (fn, vals) in facet_est_vecs)
    total_f_shift = sum(values(f_signed_means); init = 0.0)
    tau_mean = same_sup ? Float64[Statistics.mean(tau_groups[g][h] for g in eachindex(tau_groups)) for h in 1:length(tau_groups[1])] : Float64[]

    src_rows = is_person ? r.person_scores : [row for row in r.facet_measures if row.facet === by_sym]
    L = length(src_rows)
    rows = map(1:L) do j
        sr = src_rows[j]
        g_ref = chosen_g !== nothing ? chosen_g : ((!is_person && by_sym === p.step_owner) ? j : 1)
        c_vals = cat_groups[g_ref]
        base_tau = (chosen_g !== nothing || (!is_person && by_sym === p.step_owner)) ? tau_groups[g_ref] : tau_mean
        tau_j = if !is_person && haskey(step_int_map, by_sym)
            H_i, s_vals = step_int_map[by_sym]
            H_i == length(base_tau) || throw(ArgumentError("facet-step interaction dimension mismatch"))
            Float64[base_tau[h] + s_vals[(j - 1) * H_i + h] for h in 1:H_i]
        else
            base_tau
        end

        est_raw = is_person ? th_vec[j] : Float64(sr.estimate)
        sgn = is_person ? 1 : facet_signs[by_sym]
        eta_m = if is_person
            isfinite(est_raw) ? ((est_raw + mu_int) + total_f_shift) : est_raw
        else
            th_bar + sgn * est_raw + (total_f_shift - f_signed_means[by_sym])
        end
        eta_z = if is_person
            isfinite(est_raw) ? (est_raw + mu_int) : est_raw
        else
            mu_int + sgn * est_raw
        end
        fm_val, fm_slp = FrequentistMFRM._freq_adjacent_expected_score_and_slope(eta_m, tau_j, c_vals)
        fz_val, fz_slp = FrequentistMFRM._freq_adjacent_expected_score_and_slope(eta_z, tau_j, c_vals)
        fa_val = baseline === :sample_mean ? fm_val : fz_val
        fa_slp = baseline === :sample_mean ? fm_slp : fz_slp

        se_l = sr.se
        se_ok = !sr.fixed && !(se_l === missing) && isfinite(Float64(se_l)) && Float64(se_l) > 0.0 && isfinite(est_raw)
        l_lo = se_ok ? est_raw - z_crit * Float64(se_l) : missing
        l_hi = se_ok ? est_raw + z_crit * Float64(se_l) : missing
        fa_se = (se_ok && isfinite(fa_slp)) ? abs(fa_slp) * Float64(se_l) : missing
        fa_lo = !(fa_se === missing) ? fa_val - z_crit * fa_se : missing
        fa_hi = !(fa_se === missing) ? fa_val + z_crit * fa_se : missing
        n_obs_j = is_person ? (hasproperty(sr, :n_ratings) ? sr.n_ratings : count(==(j), p.person_idx)) : sr.n_ratings
        obs_avg_j = if chosen_g !== nothing || same_sup || (!is_person && by_sym === p.step_owner)
            hasproperty(sr, :observed_average) ? sr.observed_average :
                (hasproperty(sr, :raw_mean) ? sr.raw_mean : missing)
        else
            missing
        end
        pname = hasproperty(sr, :parameter) ? String(sr.parameter) : "$(by_sym)[$(repr(sr.level))]"

        (;
            parameter = pname,
            level = sr.level,
            n_observations = n_obs_j,
            observed_average = obs_avg_j,
            fixed = sr.fixed,
            logit_estimate = sr.estimate,
            logit_se = se_ok ? Float64(se_l) : missing,
            logit_lower = l_lo,
            logit_upper = l_hi,
            fair_average = isfinite(fa_val) ? fa_val : missing,
            fair_average_se = fa_se,
            fair_average_lower = fa_lo,
            fair_average_upper = fa_hi,
            fair_m = isfinite(fm_val) ? fm_val : missing,
            fair_z = isfinite(fz_val) ? fz_val : missing,
            min_category = Int(first(c_vals)),
            max_category = Int(last(c_vals)),
        )
    end

    return (;
        schema = "bayesianmgmfrm.frequentist_fair_average.v1",
        inference_paradigm = :frequentist,
        is_bayesian_posterior = false,
        method = r.summary.method,
        kind = :fair_average,
        by = by_sym,
        baseline,
        step_group = chosen_g === nothing ? (by_sym === p.step_owner ? :own_step_group : :mean_step_profile) : p.step_group_levels[chosen_g],
        level = Float64(level),
        n_levels = L,
        orientation_note = is_person ?
            "Higher person ability logits map to higher Fair Average scores." :
            "Higher facet severity/difficulty logits map to LOWER Fair Average scores at fixed reference ability and other-facet means.",
        uncertainty_note = "Conditional Wald SEs hold the reference baseline and step profile fixed; for joint person-and-calibration covariance on a concrete assessment plan, pass `reference_plan = ...`.",
        rows,
        qualification = qualify(f),
        source_sample_content_hash = r.content_hash,
    )
end

function _resolve_freq_pair_role(r, role_in::Symbol)
    p = r.problem
    rn = role_in === :entity ? :person : role_in
    rn === :person && return (:person, p.person_idx, p.person_levels)
    fi = findfirst(fb -> fb.name === rn, p.facets)
    if fi !== nothing
        fb = p.facets[fi]
        return (fb.name, fb.index, fb.levels)
    end
    if hasproperty(r.summary, :population)
        pd = r.summary.population.design
        gcol = get(pd, :group_column, :group)
        if rn === gcol || rn === :group
            p_map = Dict{Any,Int}(pd.people[i] => pd.group_index[i] for i in eachindex(pd.people))
            obs_g = Int[p_map[p.person_levels[p.person_idx[n]]] for n in eachindex(p.person_idx)]
            return (gcol, obs_g, pd.groups)
        end
    end
    avail = Any[:person, (fb.name for fb in p.facets)...]
    hasproperty(r.summary, :population) && push!(avail, get(r.summary.population.design, :group_column, :group))
    throw(ArgumentError("unknown role $(repr(role_in)) in `pair`; available: $(Tuple(unique(avail)))"))
end

function _frequentist_pair_bias(
        f::FrequentistMFRM.Fit;
        pair = nothing,
        level::Real = 0.95,
        min_obs::Integer = 1)
    AdditiveFacets.interval_bounds(level)
    min_obs isa Integer && !(min_obs isa Bool) && min_obs >= 1 ||
        throw(ArgumentError("min_obs must be a positive integer"))
    r = FrequentistMFRM.checked(f)
    p = r.problem
    z_crit = Distributions.quantile(Distributions.Normal(), 0.5 * (1.0 + Float64(level)))
    fnames = [fb.name for fb in p.facets]
    raw_pair = if pair === nothing
        (:rater in fnames && :item in fnames) ? (:rater, :item) :
            length(fnames) >= 2 ? (fnames[1], fnames[2]) : (:person, fnames[1])
    else
        pair isa Tuple && length(pair) == 2 && all(x -> x isa Symbol, pair) ||
            throw(ArgumentError("pair must be a 2-Tuple of Symbols such as `(:rater, :item)`; got $(repr(pair))"))
        pair
    end
    r1, idx1, levs1 = _resolve_freq_pair_role(r, raw_pair[1])
    r2, idx2, levs2 = _resolve_freq_pair_role(r, raw_pair[2])
    r1 != r2 || throw(ArgumentError("pair roles must be distinct; got ($r1, $r2)"))

    n_obs = length(p.person_idx)
    th_vec = Float64[
        (row.estimate === missing ? (hasproperty(row, :limit_estimate) ? Float64(row.limit_estimate) : NaN) : Float64(row.estimate))
        for row in r.person_scores
    ]
    exp_row = zeros(Float64, n_obs)
    var_row = zeros(Float64, n_obs)

    has_op = hasproperty(r, :mrcml_operator)
    joint_bm = nothing
    joint_flipped = false
    xi_mod = Float64[]
    se_mod = Float64[]

    if has_op
        op = r.mrcml_operator
        xi_mod = op.xi0_model + op.J_model * r.eta_free
        V_m = r.covariance === nothing ? nothing : r.covariance.matrix
        se_mod = V_m === nothing ? fill(NaN, length(xi_mod)) :
            Float64[sqrt(max(V_m[i, i], 0.0)) for i in 1:length(xi_mod)]
        vp = op.c_pat + op.A_free * r.eta_free
        for bm in op.block_meta
            if bm.kind in (:facet_facet_interaction, :focal_dff_interaction)
                if bm.f1 === r1 && bm.f2 === r2
                    joint_bm = bm; joint_flipped = false; break
                elseif bm.f1 === r2 && bm.f2 === r1
                    joint_bm = bm; joint_flipped = true; break
                end
            end
        end
        for n in 1:n_obs
            th = th_vec[p.person_idx[n]]
            g = p.step_group[n]
            cats = r.mrcml_category_labels[g]
            ix = op.pattern_ranges[op.pattern_of_row[n]]
            if !isfinite(th)
                b_idx = th < 0 ? argmin(view(op.B_pat, ix)) : argmax(view(op.B_pat, ix))
                exp_row[n] = Float64(cats[b_idx])
                var_row[n] = 0.0
            else
                z = op.B_pat[ix] .* th .+ vp[ix]
                pr = exp.(z .- maximum(z)); pr ./= sum(pr)
                er = LinearAlgebra.dot(pr, cats)
                exp_row[n] = er
                var_row[n] = LinearAlgebra.dot(pr, (cats .- er) .^ 2)
            end
        end
    else
        l = r.layout
        full = r.full_parameters
        for n in 1:n_obs
            th = th_vec[p.person_idx[n]]
            g = p.step_group[n]
            cats = Float64.(collect(p.supports[g]))
            if !isfinite(th)
                exp_row[n] = th < 0 ? first(cats) : last(cats)
                var_row[n] = 0.0
            else
                eta = th + sum(fb.sign * full[l.facet_full_ranges[fi][fb.index[n]]] for (fi, fb) in enumerate(p.facets); init = 0.0)
                tau = view(full, l.step_full_ranges[g])
                z = vcat(0.0, cumsum(eta .- tau))
                pr = exp.(z .- maximum(z)); pr ./= sum(pr)
                er = LinearAlgebra.dot(pr, cats)
                exp_row[n] = er
                var_row[n] = LinearAlgebra.dot(pr, (cats .- er) .^ 2)
            end
        end
    end

    analysis_mode = joint_bm === nothing ? :secondary_residual_screen :
        (joint_bm.kind === :focal_dff_interaction ? :focal_dff_model : :joint_interaction_model)

    cell_obs = Dict{Tuple{Int,Int}, Vector{Int}}()
    for n in 1:n_obs
        push!(get!(cell_obs, (idx1[n], idx2[n]), Int[]), n)
    end
    cell_keys = sort!([k for (k, ns) in cell_obs if length(ns) >= min_obs])

    rows = map(cell_keys) do (i1, i2)
        ns = cell_obs[(i1, i2)]
        w_sum = sum(p.weights[n] for n in ns)
        same_s = has_op ? allequal(r.mrcml_category_labels[p.step_group[n]] for n in ns) :
            allequal(p.supports[p.step_group[n]] for n in ns)
        o_sum = sum(p.weights[n] * Float64(p.raw_score[n]) for n in ns)
        e_sum = sum(p.weights[n] * exp_row[n] for n in ns)
        v_sum = sum(p.weights[n] * var_row[n] for n in ns)
        diff_sum = o_sum - e_sum

        obs_m = same_s && w_sum > 0 ? o_sum / w_sum : missing
        exp_m = same_s && w_sum > 0 ? e_sum / w_sum : missing
        res_m = same_s && w_sum > 0 ? diff_sum / w_sum : missing

        has_v = isfinite(v_sum) && v_sum > 1e-14
        b_est = has_v ? (-diff_sum / v_sum) : missing
        b_se = has_v ? (1.0 / sqrt(v_sum)) : missing
        b_lo = has_v ? (b_est - z_crit * b_se) : missing
        b_hi = has_v ? (b_est + z_crit * b_se) : missing
        z_res = has_v ? (diff_sum / sqrt(v_sum)) : missing
        p_val = has_v ? (2.0 * Distributions.ccdf(Distributions.Normal(), abs(z_res))) : missing

        j_fields = if joint_bm !== nothing
            b_i1, b_i2 = joint_flipped ? (i2, i1) : (i1, i2)
            mcol = if joint_bm.kind === :facet_facet_interaction
                joint_bm.model_range[(b_i1 - 1) * length(joint_bm.levels2) + b_i2]
            else
                fk = findfirst(x -> isequal(x, joint_bm.levels1[b_i1]), joint_bm.focal_levels)
                gk = findfirst(x -> isequal(x, joint_bm.levels2[b_i2]), joint_bm.compare_groups)
                (fk !== nothing && gk !== nothing) ?
                    joint_bm.model_range[(fk - 1) * length(joint_bm.compare_groups) + gk] : 0
            end
            if mcol > 0
                jv = xi_mod[mcol]
                js = se_mod[mcol]
                js_ok = isfinite(js) && js > 0.0
                (;
                    joint_interaction_logit = jv,
                    joint_interaction_se = js_ok ? js : missing,
                    joint_interaction_lower = js_ok ? jv - z_crit * js : missing,
                    joint_interaction_upper = js_ok ? jv + z_crit * js : missing,
                )
            else
                (;
                    joint_interaction_logit = 0.0,
                    joint_interaction_se = missing,
                    joint_interaction_lower = missing,
                    joint_interaction_upper = missing,
                )
            end
        else
            (;
                joint_interaction_logit = missing,
                joint_interaction_se = missing,
                joint_interaction_lower = missing,
                joint_interaction_upper = missing,
            )
        end

        merge(
            (;
                role_1 = r1,
                level_1 = levs1[i1],
                role_2 = r2,
                level_2 = levs2[i2],
                n_observations = length(ns),
                weighted_n = w_sum,
                observed_score_sum = same_s ? o_sum : missing,
                observed_score_mean = obs_m,
                expected_score_mean = exp_m,
                score_residual = res_m,
                approx_severity_bias_logit = b_est,
                approx_severity_bias_se = b_se,
                approx_severity_bias_lower = b_lo,
                approx_severity_bias_upper = b_hi,
                z_residual = z_res,
                p_value = p_val,
            ),
            j_fields,
        )
    end

    return (;
        schema = "bayesianmgmfrm.frequentist_pair_bias.v1",
        inference_paradigm = :frequentist,
        is_bayesian_posterior = false,
        method = r.summary.method,
        kind = :pair_bias,
        analysis_mode,
        pair = (r1, r2),
        level = Float64(level),
        min_obs = Int(min_obs),
        n_cells = length(rows),
        rows,
        qualification = qualify(f),
        source_sample_content_hash = r.content_hash,
    )
end
