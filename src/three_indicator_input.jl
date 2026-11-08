using LinearAlgebra: rank, I

const INPUT_TERMS = ["current_JPN_natural","current_JPN_accented","current_CHN_natural",
    "current_CHN_accented","block_2","block_3","block_4","within_time",
    "previous_JPN_natural","previous_JPN_accented","previous_CHN_natural",
    "previous_CHN_accented","previous_START","word_lag_log","talker_lag_log"]

function _input_fields(x,names)
    missing=filter(n->!hasproperty(x,n),names)
    _require(isempty(missing),"missing input fields: $(join(missing, ", "))")
end
function _input_matrix(x,name)
    x isa AbstractMatrix && return Matrix(x)
    _require(x isa AbstractVector && !isempty(x) &&
        all(r->r isa AbstractVector && !isempty(r),x),"matrix rows required: $name")
    _require(all(r->length(r)==length(first(x)),x),"ragged matrix rows: $name")
    reduce(vcat,permutedims.(collect.(x)))
end

"""
    inspect_input(input)
    inspect_input(path; expected_sha256)

Check a labelled no-state three-outcome input and return counts, category
frequencies, fixed-design rank, labels, units and warnings without fitting.
`input` is a NamedTuple or JSON3 object with the documented fields; the file
method reads that JSON and requires a separately retained SHA-256 receipt.

Keep complete 9/9/2 response triples, all declared levels, a complete one-to-one
speaker-style × word recording table, the five declared condition cells and
ordered trials. Current/previous condition indicators must agree with IDs;
previous-condition START resets at each listener or block boundary, while
`previous_trial` continues within a listener across blocks. Numeric position
and lag transformations must be documented; their construction is not inferred.

This checks the input contract, not prior suitability, latent identification,
linking adequacy, model fit or scientific validity. It neither repairs input
nor creates responses, priors, posterior draws or a fitting plan.
"""
function inspect_input(input)
    _input_fields(input,(:N,:R,:S,:W,:G,:J,:P,:K,:use_state,:predictor_names,:metadata,
        :rater,:speaker,:word,:token,:rater_group,:speaker_cell,:l1,:trial,:previous_trial,
        :X,:l1_contrast,:y,:token_lookup,:within_time,:labels))
    _require(all(k->_integer(input[k]) && input[k]>0,(:N,:R,:S,:W,:G,:J,:P)),
        "counts must be positive integers")
    N,R,S,W,G,J,P=(Int(input[k]) for k in (:N,:R,:S,:W,:G,:J,:P))
    _require(R>=2 && S>=10 && W>=2 && J==S*W && P==15,"outside the declared input dimensions")
    _require(input.K isa AbstractVector && all(_integer,input.K) && collect(input.K)==[9,9,2],
        "categories must be 9/9/2")
    _require(_integer(input.use_state) && input.use_state==0,"only the no-state input is admitted")
    _require(collect(input.predictor_names)==INPUT_TERMS,"predictor names/order differ")
    m=input.metadata
    _input_fields(m,(:outcomes,:direction,:binary_coding,:scoring_version,:predictor_units,:source))
    _require(collect(m.outcomes)==["accentedness","comprehension_difficulty","transcription_error"] &&
        m.direction=="higher_is_adverse" && m.binary_coding=="1=correct;2=incorrect",
        "outcomes or canonical scoring differ")
    _require(all(k->m[k] isa AbstractString && !isempty(strip(m[k])),
        (:scoring_version,:predictor_units,:source)),"scoring, predictor units and source are required")
    for (key,len,hi) in ((:rater,N,R),(:speaker,N,S),(:word,N,W),(:token,N,J),
            (:rater_group,R,G),(:speaker_cell,S,5),(:l1,N,3),(:trial,N,N),(:previous_trial,N,N))
        x=input[key];lo=key==:previous_trial ? 0 : 1
        _require(x isa AbstractVector && length(x)==len &&
            all(a->_integer(a)&&lo<=a<=hi,x),"invalid $key")
    end
    X=_input_matrix(input.X,"X");H=_input_matrix(input.l1_contrast,"l1_contrast")
    y=_input_matrix(input.y,"y");lookup=_input_matrix(input.token_lookup,"token_lookup")
    _require(size(X)==(N,P) && all(_finite,X),"invalid fixed predictors")
    _require(size(H)==(3,2) && all(_finite,H),"invalid L1 contrasts")
    H=Float64.(H)
    _require(maximum(abs,H'H-I)<=1e-12 && maximum(abs,sum(H;dims=1))<=1e-12,
        "L1 basis must be orthonormal and zero sum")
    _require(size(y)==(N,3) && all(_integer,y),"complete integer response triples required")
    _require(all(1<=y[n,d]<=input.K[d] for n in 1:N,d in 1:3),"response outside category support")
    _require(size(lookup)==(S,W) && all(_integer,lookup) && sort(vec(lookup))==collect(1:J),
        "recording table must be one-to-one and complete")
    _require(input.within_time isa AbstractVector && length(input.within_time)==N &&
        all(_finite,input.within_time) && collect(input.within_time)==X[:,8],
        "invalid position or disagreement with X column 8")
    for (key,m) in ((:speaker_cell,5),(:rater_group,G))
        _require(all(g->count(==(g),input[key])>=2,1:m),"at least two levels per declared $key group required")
    end
    for (key,m) in ((:rater,R),(:speaker,S),(:word,W),(:token,J))
        _require(sort(unique(input[key]))==collect(1:m),"unobserved declared $key level")
    end
    for (key,m) in ((:rater,R),(:speaker,S),(:word,W),(:token,J),(:cohort,G),(:event,N))
        _input_fields(input.labels,(key,));v=input.labels[key]
        _require(v isa AbstractVector && length(v)==m &&
            all(a->a isa AbstractString && !isempty(strip(a)),v) && length(unique(v))==m,
            "invalid $key labels")
    end
    _require(all(v->v in (0,1),X[:,5:7]) && all(sum(X[n,5:7])<=1 for n in 1:N),
        "block indicators must encode one of blocks 1–4")
    blocks=[1+sum(j*Int(X[n,4+j]) for j in 1:3) for n in 1:N]
    starts=Int[]
    for n in 1:N
        r,s,w=input.rater[n],input.speaker[n],input.word[n]
        _require(input.token[n]==lookup[s,w],"conflicting recording ownership at event $n")
        cell=input.speaker_cell[s]
        _require(input.l1[n]==(cell==1 ? 1 : cell<=3 ? 2 : 3),"L1/cell disagreement at event $n")
        new=n==1 || r!=input.rater[n-1]
        _require(new ? (r==(n==1 ? 1 : input.rater[n-1]+1) && input.trial[n]==1 && input.previous_trial[n]==0) :
            (input.trial[n]==input.trial[n-1]+1 && input.previous_trial[n]==n-1),
            "broken listener/trial order at event $n")
        _require(new || blocks[n]>=blocks[n-1],"blocks run backwards at event $n")
        _require(all(X[n,c-1]==Int(cell==c) for c in 2:5),"current-condition indicators disagree at event $n")
        start=new || blocks[n]!=blocks[n-1]
        previous=start ? 0 : input.speaker_cell[input.speaker[n-1]]
        _require(all(X[n,7+c]==Int(previous==c) for c in 2:5) && X[n,13]==Int(start),
            "previous-condition indicators disagree at event $n; START resets at each block")
        start && push!(starts,n)
    end
    fixed=hcat(ones(N),Float64.(X),[Float64(input.rater_group[input.rater[n]]==g) for n in 1:N,g in 2:G])
    fixed_rank=rank(fixed)
    _require(fixed_rank==size(fixed,2),"fixed-effect columns are rank deficient")
    counts=[[count(==(k),y[:,d]) for k in 1:input.K[d]] for d in 1:3]
    warnings=["Input checks do not establish latent identification, adequate linking, prior suitability or scientific validity.",
        "Position/lag transformations are retained as supplied; verify them against the source preprocessing and documented units.",
        "Three-outcome fitting is not available through this interface."]
    any(any(==(0),v) for v in counts) && push!(warnings,"Some declared outcome categories are unobserved; their support is retained.")
    (;input_checked=true,counts=(;events=N,listeners=R,speaker_styles=S,words=W,recordings=J,cohorts=G),
        categories=[9,9,2],category_counts=counts,fixed_design=(;rank=fixed_rank,columns=size(fixed,2)),
        ratings_per_listener=[count(==(r),input.rater) for r in 1:R],
        ratings_per_recording=[count(==(j),input.token) for j in 1:J],
        block_start_events=starts,labels=deepcopy(input.labels),metadata=deepcopy(input.metadata),
        predictor_names=copy(INPUT_TERMS),l1_contrast=H,warnings,
        scientific_acceptance=false,fitting=false)
end

function inspect_input(path::AbstractString;expected_sha256)
    text=_read(path,expected_sha256)
    merge(inspect_input(JSON3.read(text)),(;source_sha256=String(expected_sha256)))
end
