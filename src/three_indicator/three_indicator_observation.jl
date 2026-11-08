"""Private finite target; no sampler, generator or public fit registration."""
module ThreeIndicatorObservation
using LinearAlgebra
import BayesianMGMFRM as B
const logbeta = B.SpecialFunctions.logbeta
import LogDensityProblems as L
include("mgmfrm_lkj_cholesky_candidate.jl")
const C = MGMFRMLKJCholeskyCandidate
const TERMS = ["current_JPN_natural","current_JPN_accented","current_CHN_natural",
    "current_CHN_accented","block_2","block_3","block_4","within_time",
    "previous_JPN_natural","previous_JPN_accented","previous_CHN_natural",
    "previous_CHN_accented","previous_START","word_lag_log","talker_lag_log"]
const REFERENCE_PRIOR = (;sd_scale=(1.,1.,1.,.5,.5,.5),step_sd_scale=.5,
    slope_log_sd=.3,intercept_sd=2.,cohort_sd=1.,beta_sd=1.,lkj_eta=2.)
const STEPS_PRIOR = merge(REFERENCE_PRIOR,(;name=:steps,
    step_mean=Tuple(-2+4(k-1)/7 for k in 1:8),ordinal_intercept_sd=2.,ordinal_beta_sd=1.))
const COMBINED_PRIOR = merge(STEPS_PRIOR,(;name=:combined,ordinal_intercept_sd=1.,ordinal_beta_sd=.5))
function resolve_prior(prior)
    for (name,p) in ((:reference,REFERENCE_PRIOR),(:steps,STEPS_PRIOR),(:combined,COMBINED_PRIOR))
        (prior===name || (typeof(prior)===typeof(p) && prior==p)) && return p
    end
    throw(ArgumentError("declare :reference, :steps or :combined; custom priors are not supported"))
end
function prior_record(prior)
    p=resolve_prior(prior);reference=p==REFERENCE_PRIOR
    (;name=reference ? :reference : p.name,
      step_mean=reference ? ntuple(_->0.,8) : p.step_mean,
      step_coordinate_sd=1.,step_ordered=false,
      intercept_sd=reference ? (2.,2.,2.) : (p.ordinal_intercept_sd,p.ordinal_intercept_sd,2.),
      beta_sd=reference ? (1.,1.,1.) : (p.ordinal_beta_sd,p.ordinal_beta_sd,1.),
      cohort_sd=p.cohort_sd,sd_scale=p.sd_scale,step_sd_scale=p.step_sd_scale,
      slope_log_sd=p.slope_log_sd,lkj_eta=p.lkj_eta)
end
const STANDARD = (:speaker_q,:word_q,:rater_q,:token_q,:time_q,:l1_q1,:l1_q2,
    :word_slope_q,:rater_slope_q,:step_q,:rater_step_q1,:rater_step_q2)
require(ok,msg) = ok || throw(ArgumentError(msg))
isint(x) = x isa Integer && !(x isa Bool)
function mat(x)
    x isa AbstractMatrix && return Matrix(x)
    require(x isa AbstractVector && !isempty(x) && all(r->r isa AbstractVector,x),"matrix rows required")
    require(all(r->length(r)==length(first(x)),x),"ragged matrix rows")
    reduce(vcat,permutedims.(collect.(x)))
end

function helmert(n)
    h=zeros(n,n-1)
    for j in 1:n-1
        h[1:j,j].=1/sqrt(j*(j+1));h[j+1,j]=-j/sqrt(j*(j+1))
    end
    h
end
function group_basis(groups,n)
    h=zeros(length(groups),length(groups)-n);col=1
    for g in 1:n
        ix=findall(==(g),groups);m=length(ix)
        h[ix,col:col+m-2]=helmert(m);col+=m-1
    end
    h
end

struct Target{D,B,P}
    data::D
    bases::B
    prior::P
    blocks::Dict{Symbol,UnitRange{Int}}
    size::Int
end

function Target(input;prior)
    prior=resolve_prior(prior)
    for key in (:N,:R,:S,:W,:G,:J,:P)
        require(isint(input[key]) && input[key]>0,"positive integer count required: $key")
    end
    N,R,S,W,G,J,P=(Int(input[k]) for k in (:N,:R,:S,:W,:G,:J,:P))
    require(R>=2 && S>=10 && W>=2 && J==S*W && P==15,"outside first target dimensions")
    require(all(isint,input.K) && collect(input.K)==[9,9,2],"declared categories must be 9/9/2")
    require(isint(input.use_state) && input.use_state==0,"this target has no latent state")
    require(collect(input.predictor_names)==TERMS,"predictor names/order differ")
    require(collect(input.metadata.outcomes)==["accentedness","comprehension_difficulty","transcription_error"],"outcome names/order differ")
    require(input.metadata.direction=="higher_is_adverse" && input.metadata.binary_coding=="1=correct;2=incorrect","explicit canonical scoring required")
    for k in (:scoring_version,:predictor_units,:source)
        require(input.metadata[k] isa AbstractString && !isempty(input.metadata[k]),"missing provenance: $k")
    end
    idx=Dict{Symbol,Vector{Int}}()
    for (key,len,hi) in ((:rater,N,R),(:speaker,N,S),(:word,N,W),(:token,N,J),
            (:rater_group,R,G),(:speaker_cell,S,5),(:l1,N,3),(:trial,N,N),(:previous_trial,N,N))
        x=input[key];lo=key==:previous_trial ? 0 : 1
        require(length(x)==len && all(a->isint(a)&&lo<=a<=hi,x),"invalid $key")
        idx[key]=Int.(x)
    end
    X=mat(input.X);H=mat(input.l1_contrast);y=mat(input.y);lookup=mat(input.token_lookup)
    require(size(X)==(N,P) && all(x->x isa Real&&isfinite(x),X),"invalid fixed predictors")
    require(size(H)==(3,2) && all(isfinite,H),"invalid L1 contrasts")
    require(maximum(abs,H'H-I)<=1e-12 && maximum(abs,sum(H;dims=1))<=1e-12,"L1 basis must be orthonormal and zero sum")
    require(size(y)==(N,3) && all(isint,y),"complete integer response triples required")
    require(all(1<=y[n,d]<=input.K[d] for n in 1:N,d in 1:3),"response outside declared support")
    require(size(lookup)==(S,W) && all(isint,lookup) && sort(vec(lookup))==collect(1:J),"recording table must be one-to-one and complete")
    require(length(input.within_time)==N && all(x->x isa Real&&isfinite(x),input.within_time),"invalid time predictor")
    require(collect(input.within_time)==X[:,8],"time column and individual time predictor disagree")
    for (key,m) in ((:speaker_cell,5),(:rater_group,G))
        require(all(count(==(g),idx[key])>=2 for g in 1:m),"at least two levels per declared group required")
    end
    for (key,m) in ((:rater,R),(:speaker,S),(:word,W),(:token,J))
        require(sort(unique(idx[key]))==collect(1:m),"unobserved declared $key level")
    end
    for (key,m) in ((:rater,R),(:speaker,S),(:word,W),(:token,J),(:cohort,G),(:event,N))
        labels=collect(input.labels[key])
        require(length(labels)==m && all(x->x isa AbstractString&&!isempty(x),labels) && length(unique(labels))==m,"invalid $key labels")
    end
    for n in 1:N
        r,s,w=idx[:rater][n],idx[:speaker][n],idx[:word][n]
        require(idx[:token][n]==lookup[s,w],"conflicting recording ownership")
        c=idx[:speaker_cell][s]
        require(idx[:l1][n]==(c==1 ? 1 : c<=3 ? 2 : 3),"L1/cell disagreement")
        new=n==1 || r!=idx[:rater][n-1]
        require(new ? (r==(n==1 ? 1 : idx[:rater][n-1]+1) && idx[:trial][n]==1 && idx[:previous_trial][n]==0) :
            (idx[:trial][n]==idx[:trial][n-1]+1 && idx[:previous_trial][n]==n-1),"broken trial order")
    end
    fixed=hcat(ones(N),X,[Float64(idx[:rater_group][idx[:rater][n]]==g) for n in 1:N,g in 2:G])
    require(rank(fixed)==size(fixed,2),"fixed-effect columns are rank deficient")
    data=(;N,R,S,W,G,J,P,K=[9,9,2],(k=>v for (k,v) in idx)...,
        X=Float64.(X),l1_contrast=Float64.(H),y=Int.(y),token_lookup=Int.(lookup),
        within_time=Float64.(input.within_time),labels=deepcopy(input.labels),
        predictor_names=copy(TERMS),metadata=deepcopy(input.metadata))
    bases=(;speaker=group_basis(data.speaker_cell,5),word=helmert(W),rater=group_basis(data.rater_group,G),
        speaker_all=helmert(S),rater_all=helmert(R),step=helmert(8))
    sizes=[:speaker_q=>3*(S-5),:word_q=>3*(W-1),:rater_q=>3*(R-G),
        :token_q=>3*(S-1)*(W-1),:time_q=>3*(R-G),:l1_q1=>3*(R-G),:l1_q2=>3*(R-G),
        :log_sd=>18,:correlation=>18,:word_slope_q=>3*(W-1),:rater_slope_q=>3*(R-1),
        :step_q=>14,:rater_step_q1=>7*(R-1),:rater_step_q2=>7*(R-1),:log_step_sd=>2,
        :intercept=>3,:cohort=>3*(G-1),:beta=>3*P]
    blocks=Dict{Symbol,UnitRange{Int}}();start=1
    for (key,m) in sizes;blocks[key]=start:start+m-1;start+=m;end
    Target(data,bases,prior,blocks,start-1)
end
L.dimension(t::Target)=t.size
L.capabilities(::Type{<:Target})=L.LogDensityOrder{0}()
block(t,q,k)=view(q,t.blocks[k])
function initial(t::Target)
    q=zeros(t.size)
    q[t.blocks[:log_sd]] .= log.(repeat(collect(t.prior.sd_scale);inner=3))
    q[t.blocks[:log_step_sd]].=log(t.prior.step_sd_scale)
    if t.prior!=REFERENCE_PRIOR
        q[t.blocks[:step_q]].=repeat(t.bases.step'*collect(t.prior.step_mean),2)
    end
    q
end

function reconstruct(t::Target,q::AbstractVector{<:Real})
    require(length(q)==t.size && all(isfinite,q),"invalid finite parameter coordinates")
    d,h=t.data,t.bases;T=eltype(q)
    sd=reshape(exp.(block(t,q,:log_sd)),3,6);step_sd=exp.(block(t,q,:log_step_sd))
    all(x->isfinite(x)&&x>0,sd) && all(x->isfinite(x)&&x>0,step_sd) || throw(C.UnrepresentableProposal("SD overflow/underflow"))
    states=[C.correlation_state(view(block(t,q,:correlation),3b-2:3b),3;eta=t.prior.lkj_eta) for b in 1:6]
    factors=[Diagonal(sd[:,b])*states[b].L for b in 1:6]
    effect(key,basis,b)=basis*reshape(block(t,q,key),size(basis,2),3)*factors[b]'
    speaker=effect(:speaker_q,h.speaker,1);word=effect(:word_q,h.word,2)
    rater=effect(:rater_q,h.rater,3);time=effect(:time_q,h.rater,5)
    l1=[effect(k,h.rater,6) for k in (:l1_q1,:l1_q2)]
    token_coordinates=reshape(block(t,q,:token_q),(d.S-1)*(d.W-1),3)*factors[4]'
    token=zeros(T,d.J,3)
    for a in 1:3
        table=h.speaker_all*reshape(token_coordinates[:,a],d.S-1,d.W-1)*h.word'
        for s in 1:d.S,w in 1:d.W;token[d.token_lookup[s,w],a]=table[s,w];end
    end
    word_log_slope=t.prior.slope_log_sd*h.word*reshape(block(t,q,:word_slope_q),d.W-1,3)
    rater_log_slope=t.prior.slope_log_sd*h.rater_all*reshape(block(t,q,:rater_slope_q),d.R-1,3)
    word_slope=exp.(word_log_slope);rater_slope=exp.(rater_log_slope)
    all(x->isfinite(x)&&x>0,word_slope) && all(x->isfinite(x)&&x>0,rater_slope) || throw(C.UnrepresentableProposal("slope overflow/underflow"))
    step=h.step*reshape(block(t,q,:step_q),7,2)
    rater_step=[step_sd[a]*h.rater_all*reshape(block(t,q,k),d.R-1,7)*h.step' for (a,k) in enumerate((:rater_step_q1,:rater_step_q2))]
    cohort=vcat(zeros(T,1,3),reshape(block(t,q,:cohort),d.G-1,3))
    (;speaker,word,rater,token,time,l1,word_log_slope,rater_log_slope,word_slope,rater_slope,
        step,rater_step,cohort,intercept=block(t,q,:intercept),beta=reshape(block(t,q,:beta),d.P,3),sd,step_sd,states)
end
normal(x,sd=1.)=-length(x)*log(sd*sqrt(2pi))-sum(abs2,x)/(2sd^2)
function prior_parts(t,q,z=reconstruct(t,q))
    p=t.prior
    if p==REFERENCE_PRIOR
        standard=sum(normal(block(t,q,k)) for k in STANDARD)
        fixed=normal(z.intercept,p.intercept_sd)+normal(block(t,q,:cohort),p.cohort_sd)+normal(block(t,q,:beta),p.beta_sd)
    else
        # Shift the prior in reduced coordinates, not the reconstruction.
        mu=t.bases.step'*collect(p.step_mean)
        standard=sum(k==:step_q ? sum(normal(view(reshape(block(t,q,k),7,2),:,a)-mu) for a in 1:2) :
            normal(block(t,q,k)) for k in STANDARD)
        fixed=sum(normal(view(z.intercept,a:a),a<=2 ? p.ordinal_intercept_sd : p.intercept_sd)+
            normal(view(z.beta,:,a),a<=2 ? p.ordinal_beta_sd : p.beta_sd) for a in 1:3)+
            normal(block(t,q,:cohort),p.cohort_sd)
    end
    scales=sum(normal(view(z.sd,:,b),p.sd_scale[b])+3log(2) for b in 1:6)+normal(z.step_sd,p.step_sd_scale)+2log(2)
    logc=-sum(logbeta(.5,p.lkj_eta+(3-j-1)/2) for i in 2:3 for j in 1:i-1)
    correlations=sum(c.log_lkj_kernel+logc for c in z.states)
    scale_jacobian=sum(block(t,q,:log_sd))+sum(block(t,q,:log_step_sd))
    correlation_jacobian=sum(c.log_jacobian for c in z.states)
    (;standard,fixed,scales,correlations,scale_jacobian,correlation_jacobian)
end
function event_logits!(row,t,z,n,a)
    d=t.data;r,s,w,j=d.rater[n],d.speaker[n],d.word[n],d.token[n]
    eta=z.intercept[a]+dot(view(d.X,n,:),view(z.beta,:,a))+z.cohort[d.rater_group[r],a]+
        z.speaker[s,a]+z.word[w,a]+z.rater[r,a]+z.token[j,a]+z.time[r,a]*d.within_time[n]+
        sum(d.l1_contrast[d.l1[n],c]*z.l1[c][r,a] for c in 1:2)
    A=z.word_slope[w,a]*z.rater_slope[r,a];row[1]=zero(eta)
    for k in 1:d.K[a]-1
        tau=a<=2 ? z.step[k,a]+z.rater_step[a][r,k] : zero(eta)
        row[k+1]=row[k]+A*(eta-tau)
    end
    all(isfinite,row) || throw(C.UnrepresentableProposal("nonfinite adjacent logits"))
    row
end
function lognormalizer(row)
    m=maximum(row);m+log(sum(exp(x-m) for x in row))
end
function category_logprobs(t,q,z=reconstruct(t,q))
    d=t.data;lp=zeros(eltype(q),d.N,20)
    for n in 1:d.N,a in 1:3
        start=(0,9,18)[a]
        row=view(lp,n,start+1:start+d.K[a])
        event_logits!(row,t,z,n,a);row.-=lognormalizer(row)
    end
    lp
end
function loglikelihood(t,q,z)
    # Inference needs one observed category per event, not the full probability table.
    buffer=zeros(eltype(q),9);value=zero(eltype(q));d=t.data
    for n in 1:d.N,a in 1:3
        row=view(buffer,1:d.K[a]);event_logits!(row,t,z,n,a)
        value+=row[d.y[n,a]]-lognormalizer(row)
    end
    value
end
function components(t,q)
    z=reconstruct(t,q);p=prior_parts(t,q,z);likelihood=loglikelihood(t,q,z)
    (;likelihood,p...)
end
function L.logdensity(t::Target,q::AbstractVector)
    require(length(q)==t.size,"invalid parameter dimension")
    all(isfinite,q) || return oftype(first(q),-Inf)
    value = try
        sum(values(components(t,q)))
    catch err
        err isa C.UnrepresentableProposal || rethrow()
        return oftype(first(q),-Inf)
    end
    # Keep the AD return type, with zero tangent on the rejected branch.
    isfinite(value) ? value : oftype(first(q),-Inf)
end

"""Native Stan data; basis convention is reconstructed independently in Stan."""
function stan_data(t::Target)
    require(t.prior==REFERENCE_PRIOR,"this private Stan adapter implements only the reference prior")
    d=t.data
    (;(k=>getproperty(d,k) for k in (:N,:R,:S,:W,:G,:J,:P,:K,:rater,:speaker,:word,:token,
        :rater_group,:speaker_cell,:l1,:trial,:previous_trial,:X,:y,:token_lookup,:l1_contrast,:within_time))...,
        sd_scale=collect(t.prior.sd_scale),step_sd_scale=t.prior.step_sd_scale,slope_log_sd=t.prior.slope_log_sd,
        intercept_sd=t.prior.intercept_sd,cohort_sd=t.prior.cohort_sd,beta_sd=t.prior.beta_sd,lkj_eta=t.prior.lkj_eta)
end
end
