"""Fixed-point probabilities and study-defined reporting panels; no posterior inference."""
module ConcurrentReports
using LinearAlgebra, JSON3, SHA
import BayesianMGMFRM as B
import ..Concurrent as C
import ..ThreeIndicatorWorkflow as W
const SCHEMA="bayesianmgmfrm.concurrent_probabilities.v1"
const MODEL_SCHEMA="bayesianmgmfrm.concurrent_three_indicator_model.v2"
const MODEL_SCHEMAS=(MODEL_SCHEMA,"bayesianmgmfrm.concurrent_three_indicator_model.v1")
const DEFINITIONS=(
    ("JPN natural - ENG natural","condition","JPN_natural","ENG_natural"),
    ("JPN accented - ENG natural","condition","JPN_accented","ENG_natural"),
    ("CHN natural - ENG natural","condition","CHN_natural","ENG_natural"),
    ("CHN accented - ENG natural","condition","CHN_accented","ENG_natural"),
    ("JPN accented - natural","condition","JPN_accented","JPN_natural"),
    ("CHN accented - natural","condition","CHN_accented","CHN_natural"),
    ("Block 4 - block 1","block","4","1"),
    ("Trials 51-100 - trials 1-50","half","second","first"))
const WARNINGS=["Reported category probabilities are outcome marginals conditional on the full state; they are not joint response probabilities.","Fixed parameter point: no posterior intervals, MCSE or empirical model conclusion.",
    "Conditional probabilities use effective finite-grid effects; original population components are not reconstructed.",
    "Expected ordinal ratings are descriptive score summaries; they do not make the ordinal scale interval-valued."]
const require=C.require
normalized(x)=JSON3.read(JSON3.write(x),Dict{String,Any})
identity(x)=B._cache_hash(normalized(x))
function seal(body)
    d=normalized(body);d["content_hash"]=B._cache_hash(d)
    r=JSON3.read(JSON3.write(d));check(r);r
end
function header(t,q,operation,warnings)
    model=C.contract(t)
    (;schema=SCHEMA,kind="fixed_parameter_point",posterior=false,scientific_acceptance=false,
        operation,probability_scope=:outcome_marginals,model,model_identity=identity(model),point=(;dimension=length(q),identity=B._cache_hash(q)),
        context=W.context(),outcomes=C.modeldata(t).metadata.outcomes,direction="higher_is_adverse",
        binary_coding="1=correct;2=incorrect",uncertainty=(;interval=nothing,mcse=nothing),
        design=(;events=C.modeldata(t).N,listeners=C.modeldata(t).R,words=C.modeldata(t).W,recordings=C.modeldata(t).J,
            preliminary_listeners=count(<(3),C.modeldata(t).rater_group)),warnings=vcat(WARNINGS,warnings,C.observation_warnings(t)))
end
function point(t,q)
    C.check_target(t)
    require(q isa AbstractVector && length(q)==C.L.dimension(t) &&
        all(x->x isa Real && !(x isa Bool) && isfinite(x),q),"finite coordinates of the declared size required")
    v=Float64.(q);require(all(isfinite,v),"coordinates must be representable as Float64")
    v,C.reconstruct(t,v)
end
function indices(rows,N)
    rows===nothing && return collect(1:N)
    require(rows isa AbstractVector && !isempty(rows) &&
        all(i->i isa Integer && !(i isa Bool) && 1<=i<=N,rows) && allunique(rows),
        "rows must be distinct existing target-row indices")
    Int.(rows)
end
function probabilities!(p,buffer,t,z,n)
    for a in 1:3
        row=view(buffer,1:C.modeldata(t).K[a]);C.logits!(row,t,z,n,a);ln=C.M.lognormalizer(row)
        for k in eachindex(p[a]);p[a][k]=exp(row[k]-ln);end
    end
    p
end
blank()=[zeros(9),zeros(9),zeros(2)]
measure(p)=(;probabilities=p,correct_probability=p[3][1],expected_ordinal=[dot(1:9,p[a]) for a in 1:2])
function observed(t,q;rows=nothing)
    v,z=point(t,q);d=C.modeldata(t);ix=indices(rows,d.N)
    result=observed_values(t,z,ix)
    seal(merge(header(t,v,"observed_events",["Existing events and their observed histories; no new-level or held-out prediction."]),
        (;selection=(;target_rows=ix,source_rows=d.source_rows[ix]),rows=result)))
end
function observed_values(t,z,ix)
    d=C.modeldata(t);buffer=zeros(9);p=blank()
    map(ix) do n
        probabilities!(p,buffer,t,z,n)
        (;event=d.labels.event[n],source_row=d.source_rows[n],target_row=n,
            rater=d.labels.rater[d.rater[n]],token=d.labels.token[d.token[n]],measure(deepcopy(p))...)
    end
end
function contrast_design(t)
    d=C.modeldata(t);pre=findall(n->d.rater_group[d.rater[n]]<3,1:d.N)
    raters=findall(<(3),d.rater_group)
    # The source's eight contrasts use the complete, balanced preliminary protocol.
    for r in raters
        ns=filter(n->d.rater[n]==r,pre)
        require(length(ns)==100 && all(count(n->d.speaker_cell[d.speaker[n]]==c,ns)==20 for c in 1:5),
            "the eight preliminary contrasts require 100 trials and 20 observations per condition for each listener")
    end
    groups=map(DEFINITIONS) do (_,level,left,right)
        g=level=="condition" ? [C.CELLS[d.speaker_cell[d.speaker[n]]] for n in pre] :
            level=="block" ? [string(div(d.trial[n]-1,25)+1) for n in pre] :
            [d.trial[n]<=50 ? "first" : "second" for n in pre]
        l=findall(==(left),g);r=findall(==(right),g)
        require(!isempty(l) && !isempty(r),"contrast has an empty side")
        (;left=l,right=r,raters_left=length(unique(d.rater[pre[l]])),raters_right=length(unique(d.rater[pre[r]])))
    end
    (;pre,groups)
end
function contrast_values(t,z,design)
    d=C.modeldata(t);pre=design.pre
    values=[zeros(length(pre),K) for K in d.K];buffer=zeros(9);p=blank()
    for (i,n) in enumerate(pre)
        probabilities!(p,buffer,t,z,n)
        for a in 1:3;values[a][i,:]=p[a];end
    end
    map(collect(DEFINITIONS),collect(design.groups)) do (name,level,left,right),group
        l=group.left;r=group.right
        leftp=[vec(sum(view(values[a],l,:);dims=1))/length(l) for a in 1:3]
        rightp=[vec(sum(view(values[a],r,:);dims=1))/length(r) for a in 1:3]
        (;name,level,left_group=left,right_group=right,n_left=length(l),n_right=length(r),
            raters_left=group.raters_left,raters_right=group.raters_right,
            left_weight=1/length(l),right_weight=-1/length(r),
            left=measure(leftp),right=measure(rightp),difference=measure(leftp.-rightp))
    end
end
function contrasts(t,q)
    v,z=point(t,q);results=contrast_values(t,z,contrast_design(t))
    seal(merge(header(t,v,"preliminary_contrasts",["Observed-assignment/history averages, not standardized or causal language/time effects.",
        "Additional-study rows have zero averaging weight; they may inform parameters in a future joint fit."]),
        (;selection=(;cohorts=collect(C.SOURCES[1:2]),additional_row_weight=0,
            weighting="1/n_left on matching preliminary rows; -1/n_right on matching preliminary rows"),comparisons=collect(results))))
end
function reference_design(t)
    d=C.modeldata(t);rs=findall(<(3),d.rater_group);ss=findall(==(1),d.speaker_cell)
    pairs=Set((d.rater[n],d.word[n]) for n in 1:d.N)
    require(all((r,w) in pairs for r in rs,w in 1:d.W),"reference panel requires observed preliminary listener-word pairs")
    observed=Set((d.rater[n],d.token[n]) for n in 1:d.N)
    (;rs,ss,observed)
end
function reference_values(t,z,design)
    d=C.modeldata(t);rs=design.rs;ss=design.ss;observed=design.observed
    # A one-row virtual design reuses the unchanged likelihood kernel, without mutating the target.
    context=(;data=(;rater=[1],speaker=[1],word=[1],token=[1],rater_group=d.rater_group,
        X=zeros(1,d.P),within_time=[0.],l1=[1],l1_contrast=d.l1_contrast,K=d.K))
    buffer=zeros(9);p=blank();records=NamedTuple[];speakers=NamedTuple[]
    for s in ss
        speaker_p=blank();only_additional=0
        for w in 1:d.W
            j=d.token_lookup[s,w];pooled=blank();context.data.speaker[1]=s;context.data.word[1]=w;context.data.token[1]=j
            for r in rs
                context.data.rater[1]=r;probabilities!(p,buffer,context,z,1)
                for a in 1:3;pooled[a].+=p[a]/length(rs);end
            end
            seen=count(r->(r,j) in observed,rs);extra=seen==0;only_additional+=extra
            for a in 1:3;speaker_p[a].+=pooled[a]/d.W;end
            push!(records,(;token=d.labels.token[j],speaker_style=d.labels.speaker[s],word=d.labels.word[w],
                observed_preliminary_listeners=seen,cross_study_extrapolation=extra,measure(pooled)...))
        end
        push!(speakers,(;speaker_style=d.labels.speaker[s],n_words=d.W,
            cross_study_recordings=only_additional,measure(speaker_p)...))
    end
    (;recordings=records,speakers)
end
function reference(t,q)
    v,z=point(t,q);design=reference_design(t);d=C.modeldata(t);rs=design.rs
    result=reference_values(t,z,design)
    seal(merge(header(t,v,"eng_reference",["Standardized context is a declared benchmark and need not have occurred jointly.",
        "Unobserved listener-recording combinations are model-based predictions for existing levels, not observed means or new-listener validation.",
        "Recordings without preliminary listeners are cross-study extrapolations; shared recording properties are assumed, not proven invariant."]),
        (;reference=(;listeners=d.labels.rater[rs],listener_weight=1/length(rs),words=d.labels.word,word_weight=1/d.W,
            block=1,within_block_position=13,within_time=0.,previous_condition="ENG_natural",word_lag_log=0.,speaker_lag_log=0.),
            result...)))
end
function probabilities(t,q;panel=:observed,rows=nothing)
    panel===:observed && return observed(t,q;rows)
    require(panel===:eng_reference && rows===nothing,"choose :observed with existing rows, or :eng_reference without row overrides")
    reference(t,q)
end
finite(x)=x isa Real && !(x isa Bool) && isfinite(x)
positive_integer(x)=x isa Integer && !(x isa Bool) && x>0
hashstring(x)=x isa AbstractString && occursin(r"\A[0-9a-f]{64}\z",x)
function check_measure(x;signed=false)
    require(length(x.probabilities)==3 && length(x.expected_ordinal)==2,"invalid outcome support")
    for (a,K) in enumerate((9,9,2))
        p=x.probabilities[a]
        require(length(p)==K && all(v->finite(v) && (signed ? -1<=v<=1 : 0<=v<=1),p),"invalid category probabilities")
        require(abs(sum(p)-(signed ? 0 : 1))<=1e-10,"category sum differs")
        a<=2 && require(finite(x.expected_ordinal[a]) && abs(x.expected_ordinal[a]-dot(1:9,p))<=1e-10,"expected rating differs")
    end
    require(finite(x.correct_probability) && x.correct_probability==x.probabilities[3][1],"correctness must be binary category 1")
end
function check(r)
    C.check_observation_contract(r.model)
    d=normalized(r);h=pop!(d,"content_hash",nothing)
    require(hashstring(h) && B._cache_hash(d)==h,"computed report content changed")
    require(r.schema==SCHEMA && r.kind=="fixed_parameter_point" && r.posterior===false && r.scientific_acceptance===false,"not a fixed-point report")
    require(r.uncertainty.interval===nothing && r.uncertainty.mcse===nothing,"fixed points have no posterior uncertainty")
    require(collect(r.outcomes)==["accentedness","comprehension_difficulty","transcription_error"] &&
        r.direction=="higher_is_adverse" && r.binary_coding=="1=correct;2=incorrect","outcome meaning changed")
    require(hashstring(r.model.source_sha256) && hashstring(r.model.input_identity) &&
        r.model_identity==identity(r.model) && collect(r.model.categories)==[9,9,2] && r.model.likelihood_scale==1,
        "model identity/support/scale differs")
    require(hashstring(r.point.identity) && positive_integer(r.point.dimension),"invalid parameter-point binding")
    require(all(positive_integer,getproperty.(Ref(r.design),(:events,:listeners,:words,:recordings,:preliminary_listeners))),"invalid design counts")
    require(!isempty(r.warnings) && all(x->x isa AbstractString && !isempty(x),r.warnings),"warnings required")
    require(hashstring(r.context.package) && hashstring(r.context.project) && hashstring(r.context.manifest),"producer/environment binding required")
    if r.operation=="observed_events"
        require(!isempty(r.rows) && length(r.rows)==length(r.selection.target_rows)==length(r.selection.source_rows),"invalid event selection")
        require(allunique(r.selection.target_rows) && allunique(r.selection.source_rows),"duplicate events")
        for (i,row) in enumerate(r.rows)
            require(row.target_row==r.selection.target_rows[i] && row.source_row==r.selection.source_rows[i] &&
                positive_integer(row.target_row) && row.target_row<=r.design.events && positive_integer(row.source_row) && row.source_row<=r.design.events,"event row mapping differs")
            require(all(x->x isa AbstractString && !isempty(x),(row.event,row.rater,row.token)),"event labels required")
            check_measure(row)
        end
    elseif r.operation=="preliminary_contrasts"
        require(length(r.comparisons)==8 && r.selection.additional_row_weight==0 && collect(r.selection.cohorts)==collect(C.SOURCES[1:2]),"preliminary population differs")
        for (row,def) in zip(r.comparisons,DEFINITIONS)
            require((row.name,row.level,row.left_group,row.right_group)==def,"contrast definition differs")
            n=r.design.preliminary_listeners*(row.level=="condition" ? 20 : row.level=="block" ? 25 : 50)
            require(row.n_left==row.n_right==n && row.raters_left==row.raters_right==r.design.preliminary_listeners &&
                row.left_weight==1/n && row.right_weight==-1/n,"contrast denominator/weights differ")
            check_measure(row.left);check_measure(row.right);check_measure(row.difference;signed=true)
            require(all(maximum(abs.(row.difference.probabilities[a].-(row.left.probabilities[a].-row.right.probabilities[a])))<=1e-12 for a in 1:3),"contrast must use paired point differences")
        end
    elseif r.operation=="eng_reference"
        f=r.reference
        require(length(f.listeners)==r.design.preliminary_listeners && allunique(f.listeners) &&
            length(f.words)==r.design.words && allunique(f.words) && f.listener_weight==1/length(f.listeners) && f.word_weight==1/length(f.words),"reference weights differ")
        require((f.block,f.within_block_position,f.within_time,f.previous_condition,f.word_lag_log,f.speaker_lag_log)==(1,13,0.,"ENG_natural",0.,0.),"reference context differs")
        require(!isempty(r.speakers) && length(r.recordings)==length(r.speakers)*r.design.words && allunique([x.token for x in r.recordings]),"reference support differs")
        for x in r.recordings
            require(x.word in f.words && x.observed_preliminary_listeners isa Integer && !(x.observed_preliminary_listeners isa Bool) &&
                0<=x.observed_preliminary_listeners<=length(f.listeners) && x.cross_study_extrapolation===(x.observed_preliminary_listeners==0),"extrapolation flag differs")
            check_measure(x)
        end
        require(allunique([x.speaker_style for x in r.speakers]),"duplicate speaker profiles")
        for x in r.speakers
            rr=filter(y->y.speaker_style==x.speaker_style,r.recordings)
            require(x.n_words==length(rr)==r.design.words && Set(y.word for y in rr)==Set(f.words) &&
                x.cross_study_recordings==count(y->y.cross_study_extrapolation,rr),"speaker panel differs")
            check_measure(x)
            require(all(maximum(abs.(x.probabilities[a].-sum(y.probabilities[a] for y in rr)/length(rr)))<=1e-12 for a in 1:3),"speaker word weights differ")
        end
    else
        throw(ArgumentError("unsupported probability operation"))
    end
    r
end
function save(path,r)
    check(r);require(!ispath(path),"preserve existing output");mkpath(dirname(abspath(path)))
    mktemp(dirname(abspath(path))) do temporary,io
        write(io,JSON3.write(r));close(io);hardlink(temporary,path)
    end
    (;path=abspath(path),sha256=bytes2hex(sha256(read(path))),kind=:fixed_parameter_point,posterior=false)
end
end
