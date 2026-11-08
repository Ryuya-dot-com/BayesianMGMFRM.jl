"""Concurrent mixed-support target with exact Gaussian coordinate reduction."""
module Concurrent
using LinearAlgebra, SHA, JSON3
import BayesianMGMFRM as B
import LogDensityProblems as L
import ..ThreeIndicatorWorkflow: M
const C=M.C
const require=M.require
include("concurrent_prior.jl")
const EXTRA=["block_2","block_3","block_4","block_5","block_6","within_time","previous_START","word_lag_log","talker_lag_log"]
const TERMS=vcat("preliminary_" .* M.TERMS,"additional_" .* EXTRA)
const SOURCES=("original_202","gapfill_22","english_20")
const CELLS=("ENG_natural","JPN_natural","JPN_accented","CHN_natural","CHN_accented")
const FIELDS=(:source,:experiment,:trial_index,:block_index,:within_block_index,:speaker_id,
    :speaker_l1,:style,:word_number,:target_word,:rater_id,:token_id,:speaker_style_id,
    :accentedness,:comprehensibility,:intelligibility_exact)
const STANDARD=(:speaker_q,:word_q,:rater_q,:token_q,:time_q,:l1_q1,:l1_q2,
    :word_slope_q,:rater_slope_q,:step_q,:rater_step_q1,:rater_step_q2,:mean_q,:pair_q)
const HYPER=(:log_sd,:correlation,:log_step_sd,:pair_log_sd,:pair_correlation)

integer(x)=x isa Integer && !(x isa Bool) ? Int(x) : x isa AbstractString ? parse(Int,x) : throw(ArgumentError("integer required"))
label(x)=x isa AbstractString && !isempty(strip(x)) ? String(x) : throw(ArgumentError("nonempty label required"))

"""A labelled two-study row table. Pass rows such as `eachrow(df)` or `CSV.File(path)`.

The source SHA-256 identifies the original file; no CSV parser or score conversion
is inferred. Scores are canonicalized from `intelligibility_exact` only. All three
cohorts, complete recording support and the 15+9 design are checked. This does
not establish empirical linking, identification or prior suitability.
"""
struct Input{D,R}
    data::D
    rows::R
    source_sha256::String
end
function Input(table;source_sha256)
    require(source_sha256 isa AbstractString && occursin(r"\A[0-9a-f]{64}\z",source_sha256),"source SHA-256 required")
    rows=[(; (k=>(k==:word_number && !(getproperty(r,k) isa AbstractString) ? string(integer(getproperty(r,k))) : getproperty(r,k)) for k in FIELDS)...) for r in table]
    require(!isempty(rows),"empty input")
    for r in rows
        foreach(k->label(r[k]),(:source,:experiment,:speaker_id,:speaker_l1,:style,:word_number,:target_word,:rater_id,:token_id,:speaker_style_id))
        require(r.source in SOURCES && r.experiment==(r.source==SOURCES[3] ? "english_20" : "main_222"),"study/cohort mismatch")
    end
    order=sortperm(eachindex(rows);by=i->(findfirst(==(rows[i].source),SOURCES),rows[i].rater_id,integer(rows[i].trial_index)))
    sorted=rows[order]
    raters=unique(r.rater_id for r in sorted); speakers=sort(unique(r.speaker_style_id for r in sorted))
    words=sort(unique(r.word_number for r in sorted));tokens=sort(unique(r.token_id for r in sorted))
    R,S,W,J,N=length.((raters,speakers,words,tokens,sorted))
    require(R>=6 && S>=10 && W>=2 && J==S*W,"complete speaker-style by word support and three cohorts required")
    maps=[Dict(x=>i for (i,x) in enumerate(v)) for v in (raters,speakers,words,tokens)]
    idx=zeros(Int,N,7);X=zeros(N,24);y=zeros(Int,N,3);within=zeros(N)
    groups=zeros(Int,R);cells=zeros(Int,S);lookup=zeros(Int,S,W)
    physical=fill("",S);wordlabels=fill("",W);lastword=Dict{Tuple{Int,Int},Int}();lastspeaker=Dict{Tuple{Int,String},Int}()
    previous=zeros(Int,R);lasttrial=zeros(Int,R)
    for (n,row) in enumerate(sorted)
        r,s,w,j=(maps[k][row[key]] for (k,key) in enumerate((:rater_id,:speaker_style_id,:word_number,:token_id)))
        g=findfirst(==(row.source),SOURCES);cell=findfirst(==(row.speaker_l1*"_"*row.style),CELLS)
        require(cell!==nothing,"unsupported language/style cell")
        trial,block,pos=integer(row.trial_index),integer(row.block_index),integer(row.within_block_index)
        require(trial==lasttrial[r]+1 && 1<=trial<=(g==3 ? 150 : 100),"broken trial order or study schedule")
        require(block==div(trial-1,25)+1 && pos==mod(trial-1,25)+1,"block/position disagreement")
        require(g!=3 || cell==1,"additional listeners must have ENG-only observations")
        require(groups[r] in (0,g) && cells[s] in (0,cell) && lookup[s,w] in (0,j),"conflicting entity ownership")
        require(physical[s] in ("",row.speaker_id) && wordlabels[w] in ("",row.target_word),"conflicting physical speaker/word label")
        groups[r]=g;cells[s]=cell;lookup[s,w]=j;physical[s]=row.speaker_id;wordlabels[w]=row.target_word
        l1=cell==1 ? 1 : cell<=3 ? 2 : 3
        idx[n,:]=[r,s,w,j,l1,trial,n==1 || r!=idx[n-1,1] ? 0 : n-1]
        a,c,i=integer(row.accentedness),integer(row.comprehensibility),integer(row.intelligibility_exact)
        require(1<=a<=9 && 1<=c<=9 && i in (0,1),"response outside 9/9/2 support")
        y[n,:]=[a,c,2-i];within[n]=(pos-13)/10
        wl=haskey(lastword,(r,w)) ? log((trial-lastword[r,w])/50) : 0.
        sl=haskey(lastspeaker,(r,row.speaker_id)) ? log((trial-lastspeaker[r,row.speaker_id])/25) : 0.
        prev=pos==1 ? 0 : previous[r]
        if g<3
            X[n,1:15]=vcat([Int(cell==c) for c in 2:5],[Int(block==b) for b in 2:4],within[n],
                [Int(prev==c) for c in 2:5],Int(prev==0),wl,sl)
        else
            X[n,16:24]=vcat([Int(block==b) for b in 2:6],within[n],Int(prev==0),wl,sl)
        end
        lastword[r,w]=trial;lastspeaker[r,row.speaker_id]=trial;previous[r]=cell;lasttrial[r]=trial
    end
    require(sort(vec(lookup))==collect(1:J),"recordings must map one-to-one to the complete grid")
    require(all(count(==(g),groups)>=2 for g in 1:3) && all(count(==(c),cells)>=2 for c in 1:5),"two levels per cohort/cell required")
    fixed=hcat(ones(N),X,[Float64(groups[idx[n,1]]==g) for n in 1:N,g in 2:3])
    require(rank(fixed)==27,"concurrent fixed design must have rank 27")
    data=(;N,R,S,W,J,G=3,P=24,K=[9,9,2],X,y,within_time=within,
        rater=idx[:,1],speaker=idx[:,2],word=idx[:,3],token=idx[:,4],l1=idx[:,5],trial=idx[:,6],previous_trial=idx[:,7],
        rater_group=groups,speaker_cell=cells,token_lookup=lookup,l1_contrast=M.helmert(3),source_rows=order,
        labels=(;rater=raters,speaker=speakers,word=words,token=tokens,cohort=collect(SOURCES),
            event=[r.rater_id*":"*string(integer(r.trial_index)) for r in sorted]),
        predictor_names=copy(TERMS),metadata=(;source_sha256=String(source_sha256),
            outcomes=["accentedness","comprehension_difficulty","transcription_error"],
            direction="higher_is_adverse",binary_coding="1=correct;2=incorrect",scoring_version="normalized_exact",
            predictor_units="position=(within_block_index-13)/10; word_lag=log(lag/50); speaker_lag=log(lag/25)",
            mean_coordinates="effective cohort intercepts; original components require conditional reconstruction"))
    Input(data,deepcopy(rows),String(source_sha256))
end

"""Concurrent target built with `getdesign(input; prior, interaction=:none)`.

Use the shared `prepare_fit` / `fit` lifecycle for inference and `qualify`,
`contrast` and `event_probabilities` for diagnostics and posterior reporting.
Restore a model specification with `load_report(path; expected_sha256)` or
`ConcurrentTarget(path; expected_sha256)`.
Use the original package/environment and retain `contract(target)`; saved model
specifications contain inputs and model choices, not parameter points or draws.
"""
struct Target{I,D,P,H}
    input::I
    data::D
    prior::P
    interaction::Symbol
    bases::H
    blocks::Dict{Symbol,UnitRange{Int}}
    hyper_indices::Vector{Int}
    size::Int
end
function Target(input::Input;prior,interaction::Symbol=:none)
    require(interaction in (:none,:diagonal,:full),"interaction must be :none, :diagonal or :full")
    p=resolve_prior(prior);d=input.data
    groups=[findall(==(g),d.rater_group) for g in 1:3];rm=sum(length,groups[1:2])
    l1basis=zeros(d.R,rm-2);l1basis[1:rm,:]=M.group_basis(d.rater_group[1:rm],2)
    bases=(;speaker=M.group_basis(d.speaker_cell,5),rater=M.group_basis(d.rater_group,3),l1=l1basis,
        step=M.helmert(8),groups,group_h=[M.helmert(length(g)) for g in groups])
    sizes=[:speaker_q=>3*(d.S-5),:word_q=>3*(d.W-1),:rater_q=>3*(d.R-3),
        :token_q=>3*(d.S-1)*(d.W-1),:time_q=>3*(d.R-3),:l1_q1=>3*(rm-2),:l1_q2=>3*(rm-2),
        :word_slope_q=>3*(d.W-1),:rater_slope_q=>3*(d.R-1),:step_q=>14,
        :rater_step_q1=>7*(d.R-1),:rater_step_q2=>7*(d.R-1),:mean_q=>9,:beta=>72,
        :pair_q=>(interaction==:none ? 0 : 3*(d.R-1)*(d.W-1)),:log_sd=>18,:correlation=>18,
        :log_step_sd=>2,:pair_log_sd=>(interaction==:none ? 0 : 3),:pair_correlation=>(interaction==:full ? 3 : 0)]
    blocks=Dict{Symbol,UnitRange{Int}}();i=1
    for (key,n) in sizes;blocks[key]=i:i+n-1;i+=n;end
    Target(input,d,p,interaction,bases,blocks,vcat((collect(blocks[k]) for k in HYPER)...),i-1)
end
block(t,q,k)=view(q,t.blocks[k])
L.dimension(t::Target)=t.size
L.capabilities(::Type{<:Target})=L.LogDensityOrder{1}()
function initial(t::Target)
    q=zeros(t.size);q[t.blocks[:log_sd]]=log.(repeat(collect(t.prior.sd_scale);inner=3))
    q[t.blocks[:log_step_sd]].=log(t.prior.step_sd_scale);q[t.blocks[:pair_log_sd]].=log(pair_sd_scale(t.prior))
    t.prior!=M.REFERENCE_PRIOR && (q[t.blocks[:step_q]]=repeat(t.bases.step'*collect(t.prior.step_mean),2))
    q
end

# Exact Helmert convention, with linear-time transforms and adjoints.
function hmul(z)
    n=size(z,1)+1;out=zeros(eltype(z),n,size(z,2));acc=zeros(eltype(z),size(z,2))
    for j in n-1:-1:1
        scale=inv(sqrt(j*(j+1)))
        for a in axes(z,2);v=z[j,a]*scale;acc[a]+=v;out[j,a]=acc[a];out[j+1,a]-=j*v;end
    end
    out
end
function htmul(x)
    n=size(x,1);out=zeros(eltype(x),n-1,size(x,2));acc=zeros(eltype(x),size(x,2))
    for j in 1:n-1,a in axes(x,2)
        acc[a]+=x[j,a];out[j,a]=(acc[a]-j*x[j+1,a])/sqrt(j*(j+1))
    end
    out
end
table_expand(q,a,b)=hmul(hmul(q)')'
table_adjoint(x)=htmul(htmul(x)')'
function table_coordinates(q,a,b)
    reshape(reduce(hcat,(vec(table_expand(reshape(view(q,:,k),a-1,b-1),a,b)) for k in 1:3)),a*b,3)
end

function factors(t,v)
    d=t.data;p=t.prior;T=eltype(v)
    sd=reshape(exp.(view(v,1:18)),3,6);step_sd=exp.(view(v,37:38))
    require(length(v)==length(t.hyper_indices),"invalid hyperparameter dimension")
    all(x->isfinite(x)&&x>0,sd) && all(x->isfinite(x)&&x>0,step_sd) || throw(C.UnrepresentableProposal("scale overflow/underflow"))
    states=[C.correlation_state(view(v,18+3b-2:18+3b),3;eta=p.lkj_eta) for b in 1:6]
    F=[Diagonal(sd[:,b])*states[b].L for b in 1:6];Sigma=[f*f' for f in F]
    pair_sd=t.interaction==:none ? zeros(T,3) : exp.(view(v,39:41))
    t.interaction==:none || all(x->isfinite(x)&&x>0,pair_sd) || throw(C.UnrepresentableProposal("pair scale overflow/underflow"))
    pair_state=t.interaction==:full ? C.correlation_state(view(v,42:44),3;eta=pair_lkj_eta(p)) : nothing
    pair_F=Matrix(Diagonal(pair_sd))*(pair_state===nothing ? Matrix{T}(I,3,3) : pair_state.L)
    pair_Sigma=pair_F*pair_F'
    chol(x)=Matrix(cholesky(Symmetric(x)).L)
    word=t.interaction==:none ? F[2] : chol(Sigma[2]+pair_Sigma/d.R)
    rater=[g<3 && t.interaction==:none ? F[3] : chol(Sigma[3]+(g==3 ? (2/3)*Sigma[6] : zero(Sigma[6]))+pair_Sigma/d.W) for g in 1:3]
    spec=prior_record(p);mean_cov=kron(ones(3,3),Diagonal(collect(spec.intercept_sd).^2))+kron(Diagonal([0.,1.,1.]),spec.cohort_sd^2*Matrix{Float64}(I,3,3))
    mean_cov=Matrix{T}(mean_cov)
    for g in 1:3;ii=3g-2:3g;mean_cov[ii,ii]+=pair_Sigma/(length(t.bases.groups[g])*d.W);end
    (;sd,step_sd,states,F,Sigma,pair_sd,pair_state,pair_F,pair_Sigma,word,rater,mean=chol(mean_cov))
end
function hyper_prior(t,v,f=factors(t,v))
    p=t.prior
    scales=sum(M.normal(view(f.sd,:,b),p.sd_scale[b])+3log(2) for b in 1:6)+M.normal(f.step_sd,p.step_sd_scale)+2log(2)
    constant=-sum(M.logbeta(.5,p.lkj_eta+(3-j-1)/2) for i in 2:3 for j in 1:i-1)
    correlation=sum(s.log_lkj_kernel+s.log_jacobian+constant for s in f.states)
    jacobian=sum(view(v,1:18))+sum(view(v,37:38))
    if t.interaction!=:none
        scales+=M.normal(f.pair_sd,pair_sd_scale(p))+3log(2);jacobian+=sum(view(v,39:41))
    end
    if t.interaction==:full
        pair_constant=-sum(M.logbeta(.5,pair_lkj_eta(p)+(3-j-1)/2) for i in 2:3 for j in 1:i-1)
        correlation+=f.pair_state.log_lkj_kernel+f.pair_state.log_jacobian+pair_constant
    end
    scales+correlation+jacobian
end
function reconstruct(t::Target,q)
    require(length(q)==t.size && all(isfinite,q),"finite coordinates of declared size required")
    d=t.data;h=t.bases;f=factors(t,q[t.hyper_indices]);T=eltype(q)
    uspeaker=h.speaker*reshape(block(t,q,:speaker_q),d.S-5,3)
    uword=hmul(reshape(block(t,q,:word_q),d.W-1,3))
    rq=reshape(block(t,q,:rater_q),d.R-3,3);rater=zeros(T,d.R,3);urater=Matrix{T}[];start=1
    for g in 1:3
        rows=h.groups[g];n=length(rows)-1;u=h.group_h[g]*rq[start:start+n-1,:];push!(urater,u)
        rater[rows,:]=u*f.rater[g]';start+=n
    end
    utime=h.rater*reshape(block(t,q,:time_q),d.R-3,3)
    ul1=[h.l1*reshape(block(t,q,k),size(h.l1,2),3) for k in (:l1_q1,:l1_q2)]
    utoken=table_coordinates(reshape(block(t,q,:token_q),: ,3),d.S,d.W)
    token=zeros(T,d.J,3);expanded=reshape(utoken*f.F[4]',d.S,d.W,3)
    for a in 1:3,s in 1:d.S,w in 1:d.W;token[d.token_lookup[s,w],a]=expanded[s,w,a];end
    upair=t.interaction==:none ? zeros(T,d.R*d.W,3) : table_coordinates(reshape(block(t,q,:pair_q),:,3),d.R,d.W)
    pair=reshape(upair*f.pair_F',d.R,d.W,3)
    word_log_slope=p_slope(t)*hmul(reshape(block(t,q,:word_slope_q),d.W-1,3))
    rater_log_slope=p_slope(t)*hmul(reshape(block(t,q,:rater_slope_q),d.R-1,3))
    word_slope=exp.(word_log_slope);rater_slope=exp.(rater_log_slope)
    all(x->isfinite(x)&&x>0,word_slope) && all(x->isfinite(x)&&x>0,rater_slope) || throw(C.UnrepresentableProposal("slope overflow/underflow"))
    ustep=[hmul(reshape(block(t,q,k),d.R-1,7))*h.step' for k in (:rater_step_q1,:rater_step_q2)]
    (;f,uspeaker,uword,urater,utime,ul1,utoken,upair,ustep,
        speaker=uspeaker*f.F[1]',word=uword*f.word',rater,time=utime*f.F[5]',l1=[u*f.F[6]' for u in ul1],
        token,pair,word_log_slope,rater_log_slope,word_slope,rater_slope,
        step=h.step*reshape(block(t,q,:step_q),7,2),rater_step=[f.step_sd[a]*ustep[a] for a in 1:2],
        mean=reshape(f.mean*block(t,q,:mean_q),3,3)',beta=reshape(block(t,q,:beta),24,3))
end
p_slope(t)=t.prior.slope_log_sd
function ordinary_prior(t,q)
    mu=t.prior==M.REFERENCE_PRIOR ? zeros(7) : t.bases.step'*collect(t.prior.step_mean)
    standard=sum(k==:step_q ? sum(M.normal(view(reshape(block(t,q,k),7,2),:,a)-mu,step_coordinate_sd(t.prior)) for a in 1:2) : M.normal(block(t,q,k)) for k in STANDARD)
    beta=reshape(block(t,q,:beta),24,3);spec=prior_record(t.prior)
    standard+sum(M.normal(view(beta,:,a),spec.beta_sd[a]) for a in 1:3)
end
function logits!(buffer,t,z,n,a)
    d=t.data;r,s,w,j=d.rater[n],d.speaker[n],d.word[n],d.token[n]
    eta=z.mean[d.rater_group[r],a]+dot(view(d.X,n,:),view(z.beta,:,a))+z.speaker[s,a]+z.word[w,a]+z.rater[r,a]+z.token[j,a]+z.time[r,a]*d.within_time[n]+z.pair[r,w,a]
    for c in 1:2;eta+=d.l1_contrast[d.l1[n],c]*z.l1[c][r,a];end
    A=z.word_slope[w,a]*z.rater_slope[r,a];buffer[1]=zero(eta)
    for k in 1:d.K[a]-1;buffer[k+1]=buffer[k]+A*(eta-(a<=2 ? z.step[k,a]+z.rater_step[a][r,k] : zero(eta)));end
    all(isfinite,buffer) || throw(C.UnrepresentableProposal("nonfinite logits"))
    eta,A
end
function pointwise(t,q,z=reconstruct(t,q))
    d=t.data;out=zeros(eltype(q),d.N);buffer=zeros(eltype(q),9)
    for n in 1:d.N,a in 1:3
        row=view(buffer,1:d.K[a]);logits!(row,t,z,n,a);out[n]+=row[d.y[n,a]]-M.lognormalizer(row)
    end
    out
end
function components(t,q)
    z=reconstruct(t,q)
    (;likelihood=sum(pointwise(t,q,z)),ordinary_prior=ordinary_prior(t,q),hyper_prior=hyper_prior(t,q[t.hyper_indices],z.f))
end
function L.logdensity(t::Target,q::AbstractVector)
    require(length(q)==t.size,"invalid parameter dimension")
    all(isfinite,q) || return oftype(first(q),-Inf)
    try
        value=sum(values(components(t,q)))
        isfinite(value) ? value : oftype(first(q),-Inf)
    catch e
        e isa C.UnrepresentableProposal || e isa PosDefException || rethrow()
        oftype(first(q),-Inf)
    end
end

function likelihood_scores(t,q,z; association=nothing)
    d=t.data;g=(;speaker=zeros(d.S,3),word=zeros(d.W,3),rater=zeros(d.R,3),token=zeros(d.J,3),time=zeros(d.R,3),
        l1=[zeros(d.R,3) for _ in 1:2],pair=zeros(d.R,d.W,3),mean=zeros(3,3),beta=zeros(24,3),
        word_log_slope=zeros(d.W,3),rater_log_slope=zeros(d.R,3),step=zeros(8,2),rater_step=[zeros(d.R,8) for _ in 1:2],ac_log_psi=Ref(0.))
    buffer=zeros(9);likelihood=0.
    for n in 1:d.N
        ac=association===nothing ? nothing : association(n)
        if ac!==nothing;likelihood+=ac.lp;g.ac_log_psi[]+=ac.ge;end
        for a in 1:3
        K=d.K[a];row=view(buffer,1:K);eta,A=logits!(row,t,z,n,a);ln=M.lognormalizer(row)
        if ac===nothing || a==3;likelihood+=row[d.y[n,a]]-ln;end
        r,s,w,j=d.rater[n],d.speaker[n],d.word[n],d.token[n]
        tail=0.;ge=0.;ga=0.
        for k in K-1:-1:1
            tail+=ac===nothing || a==3 ? Int(d.y[n,a]==k+1)-exp(row[k+1]-ln) : (a==1 ? ac.ga[k+1] : ac.gb[k+1])
            tau=a<=2 ? z.step[k,a]+z.rater_step[a][r,k] : 0.
            ge+=A*tail;ga+=A*tail*(eta-tau)
            if a<=2;g.step[k,a]-=A*tail;g.rater_step[a][r,k]-=A*tail;end
        end
        g.speaker[s,a]+=ge;g.word[w,a]+=ge;g.rater[r,a]+=ge;g.token[j,a]+=ge
        g.time[r,a]+=ge*d.within_time[n];g.pair[r,w,a]+=ge;g.mean[d.rater_group[r],a]+=ge
        for c in 1:2;g.l1[c][r,a]+=ge*d.l1_contrast[d.l1[n],c];end
        for p in 1:24;g.beta[p,a]+=ge*d.X[n,p];end
        g.word_log_slope[w,a]+=ga;g.rater_log_slope[r,a]+=ga
    end
    end
    likelihood,g
end
function gradient(t,q,z; scores=likelihood_scores(t,q,z))
    d=t.data;h=t.bases;f=z.f;value,g=scores;dq=zeros(t.size)
    put(key,x)=(dq[t.blocks[key]]=vec(x))
    adjF=[zeros(3,3) for _ in 1:6]
    put(:speaker_q,h.speaker'*g.speaker*f.F[1]);adjF[1]=g.speaker'*z.uspeaker
    put(:word_q,htmul(g.word*f.word));adjword=g.word'*z.uword
    rq=zeros(d.R-3,3);adjrater=Matrix{Float64}[];start=1
    for k in 1:3
        rows=h.groups[k];n=length(rows)-1;gg=g.rater[rows,:]
        rq[start:start+n-1,:]=h.group_h[k]'*gg*f.rater[k];push!(adjrater,gg'*z.urater[k]);start+=n
    end
    put(:rater_q,rq);put(:time_q,h.rater'*g.time*f.F[5]);adjF[5]=g.time'*z.utime
    for (c,key) in enumerate((:l1_q1,:l1_q2));put(key,h.l1'*g.l1[c]*f.F[6]);adjF[6]+=g.l1[c]'*z.ul1[c];end
    gt=zeros(d.S,d.W,3)
    for a in 1:3,s in 1:d.S,w in 1:d.W;gt[s,w,a]=g.token[d.token_lookup[s,w],a];end
    gtflat=reshape(gt,d.S*d.W,3);adjF[4]=gtflat'*z.utoken;du=reshape(gtflat*f.F[4],d.S,d.W,3)
    put(:token_q,reduce(hcat,(vec(table_adjoint(view(du,:,:,a))) for a in 1:3)))
    adjpair=zeros(3,3)
    if t.interaction!=:none
        gp=reshape(g.pair,d.R*d.W,3);adjpair=gp'*z.upair;du=reshape(gp*f.pair_F,d.R,d.W,3)
        put(:pair_q,reduce(hcat,(vec(table_adjoint(view(du,:,:,a))) for a in 1:3)))
    end
    put(:word_slope_q,p_slope(t)*htmul(g.word_log_slope));put(:rater_slope_q,p_slope(t)*htmul(g.rater_log_slope))
    put(:step_q,h.step'*g.step);adjstep=zeros(2)
    for (a,key) in enumerate((:rater_step_q1,:rater_step_q2))
        put(key,f.step_sd[a]*htmul(g.rater_step[a])*h.step);adjstep[a]=sum(g.rater_step[a].*z.ustep[a])
    end
    gm=vec(g.mean');put(:mean_q,f.mean'*gm);adjmean=gm*block(t,q,:mean_q)'
    put(:beta,g.beta)
    function small_objective(v)
        ff=factors(t,v)
        sum(sum(adjF[b].*ff.F[b]) for b in (1,4,5,6))+sum(adjword.*ff.word)+
        sum(sum(adjrater[g].*ff.rater[g]) for g in 1:3)+sum(adjpair.*ff.pair_F)+
        sum(adjmean.*ff.mean)+dot(adjstep,ff.step_sd)+hyper_prior(t,v,ff)
    end
    dq[t.hyper_indices]=B.ForwardDiff.gradient(small_objective,q[t.hyper_indices])
    mu=t.prior==M.REFERENCE_PRIOR ? zeros(7) : h.step'*collect(t.prior.step_mean)
    for key in STANDARD
        if key==:step_q
            # Scale only the prior derivative; the likelihood derivative is unchanged.
            if step_coordinate_sd(t.prior)==1.
                dq[t.blocks[key]].-=block(t,q,key)
                dq[t.blocks[key]].+=repeat(mu,2)
            else
                dq[t.blocks[key]].-=(block(t,q,key).-repeat(mu,2))./step_coordinate_sd(t.prior)^2
            end
        else
            dq[t.blocks[key]].-=block(t,q,key)
        end
    end
    beta=reshape(block(t,q,:beta),24,3);spec=prior_record(t.prior)
    dq[t.blocks[:beta]].-=vec(beta ./ reshape(collect(spec.beta_sd).^2,1,3))
    value+ordinary_prior(t,q)+hyper_prior(t,q[t.hyper_indices],f),dq
end
function L.logdensity_and_gradient(t::Target,q::AbstractVector{<:Real})
    require(length(q)==t.size,"invalid parameter dimension")
    qf=Float64.(q)
    all(isfinite,qf) || return (-Inf,zeros(t.size))
    try
        value,dq=gradient(t,qf,reconstruct(t,qf))
        isfinite(value) && all(isfinite,dq) ? (value,dq) : (-Inf,zeros(t.size))
    catch e
        e isa C.UnrepresentableProposal || e isa PosDefException || rethrow()
        (-Inf,zeros(t.size))
    end
end
function coordinates(t,q)
    z=reconstruct(t,q)
    (;meaning=:effective_finite_grid,cohort_mean=z.mean,speaker=z.speaker,word=z.word,rater=z.rater,
        token=z.token,time=z.time,l1=z.l1,pair=z.pair,step=z.step,rater_step=z.rater_step,
        word_slope=z.word_slope,rater_slope=z.rater_slope,
        pair_covariance=z.f.pair_Sigma,original_population_components=:not_reconstructed)
end
function contract(t::Target)
    (;status=:experimental,categories=(9,9,2),likelihood_scale=1.,interaction=t.interaction,
        prior=prior_record(t.prior),pair_prior=(;sd_scale=pair_sd_scale(t.prior),lkj_eta=t.interaction==:full ? pair_lkj_eta(t.prior) : nothing),
        coordinates=:effective_gaussian_convolution,gradient=:analytic_large_blocks_forwarddiff_small_factors,
        source_sha256=t.input.source_sha256,input_identity=bytes2hex(sha256(Vector{UInt8}(codeunits(JSON3.write(t.input.rows))))),
        fitting=true,posterior_reporting=true,scientific_acceptance=false)
end
function check_target(t)
    rebuilt=Target(Input(t.input.rows;source_sha256=t.input.source_sha256);prior=t.prior,interaction=t.interaction)
    require(t.data==rebuilt.data && t.input.data==rebuilt.input.data && t.bases==rebuilt.bases &&
        t.blocks==rebuilt.blocks && t.hyper_indices==rebuilt.hyper_indices && t.size==rebuilt.size,
        "model specification differs from its input; rebuild the target instead of mutating compiled arrays")
    t
end
function save_model(path,t)
    require(!ispath(path),"preserve existing output");check_target(t)
    body=(;schema="bayesianmgmfrm.concurrent_three_indicator_model.v2",rows=t.input.rows,
        source_sha256=t.input.source_sha256,prior=prior_spec(t.prior),interaction=t.interaction)
    mkpath(dirname(abspath(path)))
    mktemp(dirname(abspath(path))) do temporary,io
        write(io,JSON3.write(body));close(io);hardlink(temporary,path)
    end
    (;path=abspath(path),sha256=bytes2hex(sha256(read(path))),kind=:model_specification,posterior=false)
end
function Target(path::AbstractString;expected_sha256)
    bytes=read(path);require(bytes2hex(sha256(bytes))==expected_sha256,"model specification checksum mismatch")
    x=JSON3.read(bytes);require(x.schema in ("bayesianmgmfrm.concurrent_three_indicator_model.v1","bayesianmgmfrm.concurrent_three_indicator_model.v2"),"unsupported model schema")
    Target(Input(x.rows;source_sha256=x.source_sha256);prior=resolve_prior(x.prior),interaction=Symbol(x.interaction))
end
"""Export the full-interaction concurrent target to `src/stan/concurrent.stan`.

Returns JSON-ready arrays with the complete numerical prior. This finite-reference
adapter does not compile/run Stan or import native posterior draws. The source
uses the same native parameter ordering. Other interaction structures are not
implemented by this independent reference.
"""
function stan_data(t::Target)
    check_target(t)
    require(t.interaction===:full,"concurrent Stan reference supports interaction=:full only")
    d=t.data;p=prior_record(t.prior)
    fields=(:N,:R,:S,:W,:J,:P,:K,:rater,:speaker,:word,:token,:rater_group,:speaker_cell,
        :l1,:X,:y,:token_lookup,:l1_contrast,:within_time)
    data=(;(k=>getproperty(d,k) for k in fields)...,RM=count(<(3),d.rater_group),
        group_count=length.(t.bases.groups),sd_scale=collect(p.sd_scale),step_sd_scale=p.step_sd_scale,
        slope_log_sd=p.slope_log_sd,intercept_sd=collect(p.intercept_sd),cohort_sd=p.cohort_sd,
        beta_sd=collect(p.beta_sd),lkj_eta=p.lkj_eta,step_mean=t.bases.step'*collect(p.step_mean),
        step_coordinate_sd=p.step_coordinate_sd,pair_sd_scale=pair_sd_scale(t.prior),pair_lkj_eta=pair_lkj_eta(t.prior))
    Dict(string(k)=>(v isa AbstractMatrix ? [collect(r) for r in eachrow(v)] : v) for (k,v) in pairs(data))
end

include("concurrent_association.jl")

end
