# Included inside PairedRatingReference; no public package API or new dependency.
function checked_count(value, name; minimum=1)
    value isa Integer && !(value isa Bool) && minimum <= value <= typemax(Int) ||
        throw(ArgumentError("$name must be an integer >= $minimum"))
    return Int(value)
end
local_rng(seed) = MersenneTwister(checked_count(seed,"seed";minimum=0))

function prior_draws(t::Target; ndraws, seed)
    count=checked_count(ndraws,"ndraws"); rng=local_rng(seed)
    p,b,d=t.prior,t.blocks,t.data
    draws=zeros(count,LDP.dimension(t))
    for q in eachrow(draws)
        q[b.person_white]=randn(rng,2d.P)
        q[b.recording_white]=randn(rng,2d.O)
        q[b.word]=p.word_sd.*randn(rng,2d.W)
        # Draw the full exchangeable vector and project, THEN retain free entries.
        # Independent free entries would imply a different prior for the last rater.
        r=randn(rng,d.R,2).*permutedims(collect(p.rater_sd))
        s=randn(rng,d.K-1,2).*permutedims(collect(p.step_sd))
        r .-= mean(r;dims=1); s .-= mean(s;dims=1)
        q[b.rater_free]=vec(r[1:end-1,:]); q[b.step_free]=vec(s[1:end-1,:])
        q[b.log_recording_sd]=collect(p.recording_log_sd_mean)+collect(p.recording_log_sd_sd).*randn(rng,2)
        for (j,eta) in enumerate((p.person_lkj_eta,p.recording_lkj_eta))
            rho=2rand(rng,B.Turing.Beta(eta,eta))-1
            -1 < rho < 1 || throw(ArgumentError("unrepresentable prior correlation; no redraw performed"))
            q[b.z_correlation[j]]=atanh(rho)
        end
    end
    all(isfinite,draws) || throw(ArgumentError("nonfinite prior draw; no redraw performed"))
    return draws
end

prediction_rows(t::Target) = [Base.structdiff(row,(;score=nothing)) for row in canonical_rows(t.data)]

function prediction_design(t::Target, rows; recording_effect)
    recording_effect in (:existing,:new) || throw(ArgumentError("recording_effect must be :existing or :new"))
    isempty(rows) && throw(ArgumentError("prediction rows must not be empty"))
    fields=(:person,:word,:rater,:recording,:criterion)
    for row in rows
        Set(propertynames(row))==Set(fields) && all(f->getproperty(row,f) isa AbstractString &&
            !isempty(getproperty(row,f)),fields) ||
            throw(ArgumentError("prediction rows require exactly the five ID fields, without scores"))
    end
    rows=[NamedTuple{fields}(Tuple(String(getproperty(row,f)) for f in fields)) for row in rows]
    length(unique((r.recording,r.rater,r.criterion) for r in rows))==length(rows) ||
        throw(ArgumentError("duplicate prediction rating"))
    pairs=unique((r.recording,r.person,r.word) for r in rows)
    length(unique(first.(pairs)))==length(pairs) && length(unique((p[2],p[3]) for p in pairs))==length(pairs) ||
        throw(ArgumentError("prediction recordings and person-word pairs must be one-to-one"))
    trained=Dict(r.recording=>(r.person,r.word) for r in canonical_rows(t.data))
    trained_pairs=Set(values(trained))
    for (id,p,w) in pairs
        if recording_effect===:existing
            get(trained,id,nothing)==(p,w) || throw(ArgumentError("existing recording must retain its trained person-word pair"))
        else
            !haskey(trained,id) && !((p,w) in trained_pairs) ||
                throw(ArgumentError("new recording must be absent from training, including its person-word pair"))
        end
    end
    indices=map((:person,:word,:rater,:criterion)) do field
        lookup=Dict(id=>i for (i,id) in enumerate(getproperty(t.data.levels,field)))
        all(r->haskey(lookup,getproperty(r,field)),rows) || throw(ArgumentError("new $field levels are unsupported"))
        [lookup[getproperty(r,field)] for r in rows]
    end
    ids=sort(unique(r.recording for r in rows))
    lookup=Dict(id=>i for (i,id) in enumerate(ids))
    group=[lookup[r.recording] for r in rows]
    trained_index=recording_effect===:existing ? [findfirst(==(id),t.data.levels.recording) for id in ids] : Int[]
    criteria=sort(unique(indices[4]))
    # Each criterion: equal recordings, equal supplied raters within a recording.
    cells=Dict((o,c)=>findall(n->group[n]==o && indices[4][n]==c,eachindex(rows))
        for o in eachindex(ids) for c in criteria)
    counts=[count(o->!isempty(cells[(o,c)]),eachindex(ids)) for c in criteria]
    weights=zeros(length(rows))
    for (j,c) in enumerate(criteria), o in eachindex(ids)
        ns=cells[(o,c)]
        isempty(ns) || (weights[ns].=1/(counts[j]*length(ns)))
    end
    return (;rows,person=indices[1],word=indices[2],rater=indices[3],criterion=indices[4],
        recording_ids=ids,group,trained_index,criteria,recording_counts=counts,weights,recording_effect,
        order=sortperm(rows;by=r->(r.recording,r.rater,r.criterion)))
end

function simulate_prediction(t::Target,q,design,rng::AbstractRNG)
    x=coordinates(t,q)
    all(v->all(isfinite,v),(x.theta,x.word,x.rater,x.steps,x.sd)) && all(>(0),x.sd) ||
        throw(ArgumentError("unrepresentable predictive coordinates; no redraw performed"))
    u=if design.recording_effect===:existing
        x.u[:,design.trained_index]
    else
        z=randn(rng,2,length(design.recording_ids))
        vcat(x.sd[1].*z[1:1,:],x.sd[2].*(x.rho[2].*z[1:1,:]+x.residual[2].*z[2:2,:]))
    end
    all(isfinite,u) || throw(ArgumentError("nonfinite predictive recording effect"))
    probabilities=zeros(length(design.rows),t.data.K); scores=zeros(Int,length(design.rows))
    for n in design.order
        c=design.criterion[n]
        location=x.theta[c,design.person[n]]-x.word[c,design.word[n]]-x.rater[design.rater[n],c]+u[c,design.group[n]]
        prob=B._ld1_pcm_probabilities(location,x.steps[2:end,c])
        probabilities[n,:]=prob
        scores[n]=B._ld1_inverse_cdf(rand(rng),prob,0:t.data.K-1)
    end
    return (;probabilities,scores,recording_effects=u)
end

function category_frequencies(design,values,K)
    out=zeros(length(design.criteria),K)
    for (j,c) in enumerate(design.criteria), n in eachindex(design.rows)
        design.criterion[n]==c || continue
        if values isa AbstractVector
            out[j,values[n]+1]+=design.weights[n]
        else
            out[j,:].+=design.weights[n].*values[n,:]
        end
    end
    return vec(permutedims(out)) # criterion outer, category inner
end

function prediction_summary(t::Target,draws::AbstractMatrix,rows;
        recording_effect,seed,integrations)
    S=size(draws,1); L=checked_count(integrations,"integrations")
    S>0 && size(draws,2)==LDP.dimension(t) && all(isfinite,draws) || throw(ArgumentError("invalid predictive draws"))
    recording_effect===:new ? L>=2 || throw(ArgumentError("new recording integration requires at least two samples per draw")) :
        L==1 || throw(ArgumentError("existing effects use integrations=1"))
    design=prediction_design(t,rows;recording_effect); rng=local_rng(seed)
    N,K=length(rows),t.data.K; C=length(design.criteria)
    probability_sum=zeros(N,K); integration_variance=zeros(N,K)
    expected=zeros(S,C*K); replicated=zeros(S*L,C*K); aggregate_variance=zeros(C*K)
    for (s,q) in enumerate(eachrow(draws))
        avg=zeros(N,K); m2=zeros(N,K); aggregate_m2=zeros(C*K)
        for l in 1:L
            rep=simulate_prediction(t,q,design,rng)
            delta=rep.probabilities-avg; avg .+= delta./l
            m2 .+= delta.*(rep.probabilities-avg)
            freq=category_frequencies(design,rep.probabilities,K)
            diff=freq-expected[s,:]; expected[s,:].+=diff./l
            aggregate_m2 .+= diff.*(freq-expected[s,:])
            replicated[(s-1)*L+l,:]=category_frequencies(design,rep.scores,K)
        end
        probability_sum .+= avg
        if L>1
            integration_variance .+= max.(m2,0)./(L*(L-1))
            aggregate_variance .+= max.(aggregate_m2,0)./(L*(L-1))
        end
    end
    probabilities=probability_sum./S
    return (;schema="bayesianmgmfrm.paired_rating_prediction.v1",target_identity=identity(t),
        conditioning=recording_effect===:existing ? :conditional_on_recording_draws : :new_recording_effect_integrated,
        rows=design.rows,categories=collect(0:K-1),criteria=t.data.levels.criterion[design.criteria],
        controls=(;seed,parameter_draws=S,integrations=L,replications=S*L),
        probabilities,cumulative_probabilities=cumsum(probabilities;dims=2),
        integration_mcse=sqrt.(integration_variance)./S,
        category_integration_mcse=sqrt.(aggregate_variance)./S,
        integration_mcse_scope="conditional on supplied parameter draws; excludes posterior MCMC error and parameter uncertainty",
        category_columns=[(;criterion=t.data.levels.criterion[c],category=k) for c in design.criteria for k in 0:K-1],
        category_expected_by_draw=expected,category_replicated=replicated,
        weighting=(;rule=:equal_recordings_then_equal_supplied_raters_within_criterion,
            recording_counts=design.recording_counts,row_weights=design.weights),
        joint_replication="one bivariate effect per recording shared by all criteria and raters; scores conditionally independent",
        marginal_warning="products of row marginal probabilities are not joint predictive probabilities")
end

function prior_predictive_check(t::Target;ndraws,parameter_seed,prediction_seed)
    # Validate both seeds before generating any draws.
    local_rng(prediction_seed)
    raw=prior_draws(t;ndraws,seed=parameter_seed)
    rows=prediction_rows(t)
    result=prediction_summary(t,raw,rows;recording_effect=:existing,seed=prediction_seed,integrations=1)
    design=prediction_design(t,rows;recording_effect=:existing)
    return merge(result,(;conditioning=:joint_prior_on_observed_design,prior=t.prior,parameter_seed,
        raw_parameter_draws=raw,parameter_names=copy(t.names),
        observed_category_frequencies=category_frequencies(design,t.data.score,t.data.K),
        status="prior implications only; scores were not used to generate parameters; no acceptance threshold"))
end

function posterior_predict(record,rows;recording_effect,seed,integrations)
    t=restore(record)
    result=prediction_summary(t,record.run.draws,rows;recording_effect,seed,integrations)
    diagnostics=report(record)
    return merge(result,(;source_sample_content_hash=record.content_hash,backend=record.run.backend,
        parameter_chain_ids=record.run.chain_ids,parameter_iterations=record.run.iterations,
        sampling_quality=(;status=diagnostics.status,controls=diagnostics.controls,
            raw_diagnostics=diagnostics.raw_diagnostics,model_diagnostics=diagnostics.model_diagnostics,
            sampler=diagnostics.sampler,warmup=diagnostics.warmup)))
end
