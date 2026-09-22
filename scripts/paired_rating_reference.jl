module PairedRatingReference

using Random, LinearAlgebra, Statistics, SHA, Serialization
import LogDensityProblems as LDP
import BayesianMGMFRM as B

# A bounded application reference, not an extension of the ordinary MGMFRM API.
const SCHEMA = "bayesianmgmfrm.paired_rating_reference.v1"
const PRIOR_KEYS = (:word_sd, :rater_sd, :step_sd, :recording_log_sd_mean,
    :recording_log_sd_sd, :person_lkj_eta, :recording_lkj_eta)

function checked_prior(prior::NamedTuple)
    Set(keys(prior)) == Set(PRIOR_KEYS) || throw(ArgumentError("all A0 prior fields must be explicit"))
    number(x, positive) = x isa Real && !(x isa Bool) && isfinite(x) &&
        (!positive || x > 0) && isfinite(Float64(x)) && (!positive || Float64(x) > 0)
    number(prior.word_sd, true) || throw(ArgumentError("word_sd must be finite and positive"))
    for name in (:rater_sd, :step_sd, :recording_log_sd_mean, :recording_log_sd_sd)
        pair = getproperty(prior, name)
        pair isa Union{Tuple,AbstractVector} && length(pair) == 2 &&
            all(x -> number(x, name !== :recording_log_sd_mean), pair) ||
            throw(ArgumentError("$name must contain two finite values (scales strictly positive)"))
    end
    return (; word_sd=Float64(prior.word_sd), rater_sd=Tuple(Float64.(prior.rater_sd)),
        step_sd=Tuple(Float64.(prior.step_sd)),
        recording_log_sd_mean=Tuple(Float64.(prior.recording_log_sd_mean)),
        recording_log_sd_sd=Tuple(Float64.(prior.recording_log_sd_sd)),
        person_lkj_eta=B._checked_integer_lkj_eta(prior.person_lkj_eta),
        recording_lkj_eta=B._checked_integer_lkj_eta(prior.recording_lkj_eta))
end

function rating_data(rows; categories, criteria)
    categories isa Integer && !(categories isa Bool) && 2 <= categories <= 20 ||
        throw(ArgumentError("this reference supports 2:20 declared categories"))
    criteria isa Union{Tuple,AbstractVector} && length(criteria) == 2 && all(x -> x isa AbstractString && !isempty(x), criteria) &&
        length(unique(criteria)) == 2 || throw(ArgumentError("two distinct criterion names are required"))
    isempty(rows) && throw(ArgumentError("ratings must not be empty"))
    fields = (:person, :word, :rater, :recording, :criterion)
    for row in rows
        all(f -> hasproperty(row, f) && getproperty(row, f) isa AbstractString &&
            !isempty(getproperty(row, f)), fields) || throw(ArgumentError("rating IDs must be nonempty strings"))
        row.criterion in criteria || throw(ArgumentError("unknown criterion"))
        hasproperty(row, :score) && row.score isa Integer && !(row.score isa Bool) &&
            0 <= row.score < categories || throw(ArgumentError("scores must be integers in 0:K-1; omit missing rows"))
    end
    sorted = sort(collect(rows); by=r -> (r.recording, r.rater, r.criterion))
    length(unique((r.recording,r.rater,r.criterion) for r in sorted)) == length(sorted) ||
        throw(ArgumentError("duplicate recording/rater/criterion rating"))
    rec_pairs = unique((r.recording,r.person,r.word) for r in sorted)
    length(unique(first.(rec_pairs))) == length(rec_pairs) &&
        length(unique((r[2],r[3]) for r in rec_pairs)) == length(rec_pairs) ||
        throw(ArgumentError("each recording must identify exactly one person-word pair and vice versa"))
    levels = (; person=sort(unique(String.(getproperty.(sorted,:person)))),
        word=sort(unique(String.(getproperty.(sorted,:word)))),
        rater=sort(unique(String.(getproperty.(sorted,:rater)))),
        recording=sort(unique(String.(getproperty.(sorted,:recording)))), criterion=String.(collect(criteria)))
    length(levels.rater) >= 2 || throw(ArgumentError("at least two raters are required"))
    all(c -> any(r -> r.criterion == c, sorted), criteria) || throw(ArgumentError("both criteria must have observations"))
    indices = map(fields) do field
        lookup = Dict(id=>i for (i,id) in enumerate(getproperty(levels,field)))
        [lookup[getproperty(row,field)] for row in sorted]
    end
    return (; levels, P=length(levels.person), W=length(levels.word), R=length(levels.rater),
        O=length(levels.recording), K=Int(categories), N=length(sorted),
        person=indices[1], word=indices[2], rater=indices[3], recording=indices[4],
        criterion=indices[5], score=Int.(getproperty.(sorted,:score)))
end

struct Target{D,P}
    data::D
    prior::P
    blocks::NamedTuple
    names::Vector{String}
    logbeta::Tuple{Float64,Float64}
    function Target(rows; categories, criteria, prior::NamedTuple)
        pr = checked_prior(prior)
        d = rating_data(rows; categories, criteria)
        names = String[]
        function block(label, levels, count)
            start = length(names)+1
            append!(names, ["$label[$id,$c]" for id in levels for c in 1:count])
            return start:length(names)
        end
        person_white = block("person_white", d.levels.person, 2)
        recording_white = block("recording_white", d.levels.recording, 2)
        word = block("word", d.levels.word, 2)
        # Free rater and step coordinates have the criterion as the outer index.
        start = length(names)+1
        append!(names, ["rater_free[$id,$c]" for c in 1:2 for id in d.levels.rater[1:end-1]])
        rater_free = start:length(names)
        start = length(names)+1
        append!(names, ["step_free[$h,$c]" for c in 1:2 for h in 1:d.K-2])
        step_free = start:length(names)
        log_recording_sd = block("log_recording_sd", ["recording"], 2)
        z_correlation = block("z_correlation", ["person", "recording"], 1)
        blocks = (; person_white, recording_white, word, rater_free, step_free,
            log_recording_sd, z_correlation)
        return new{typeof(d),typeof(pr)}(d,pr,blocks,names,
            (B._log_beta_half_integer(pr.person_lkj_eta), B._log_beta_half_integer(pr.recording_lkj_eta)))
    end
end

LDP.dimension(t::Target) = length(t.names)
LDP.capabilities(::Type{<:Target}) = LDP.LogDensityOrder{1}()
function B._check_source_fixture_raw_vector(t::Target, q::AbstractVector)
    length(q) == LDP.dimension(t) && all(x -> x isa Real && isfinite(x), q) ||
        throw(ArgumentError("invalid A0 parameter vector"))
    return nothing
end
function initial(t::Target)
    q = zeros(LDP.dimension(t))
    q[t.blocks.log_recording_sd] .= t.prior.recording_log_sd_mean
    return q
end

function coordinates(t::Target, q::AbstractVector)
    B._check_source_fixture_raw_vector(t,q)
    d, b = t.data, t.blocks
    z = q[b.z_correlation]
    rho = tanh.(z)
    residual = exp.(B._log_one_minus_tanh_squared.(z)./2)
    sd = exp.(q[b.log_recording_sd])
    zp = reshape(q[b.person_white],2,d.P)
    zu = reshape(q[b.recording_white],2,d.O)
    theta = vcat(zp[1:1,:], rho[1].*zp[1:1,:] .+ residual[1].*zp[2:2,:])
    u = vcat(sd[1].*zu[1:1,:], sd[2].*(rho[2].*zu[1:1,:] .+ residual[2].*zu[2:2,:]))
    rf = reshape(q[b.rater_free],d.R-1,2)
    sf = reshape(q[b.step_free],d.K-2,2)
    return (; theta, u, word=reshape(q[b.word],2,d.W),
        rater=vcat(rf,-sum(rf;dims=1)),
        steps=vcat(zeros(eltype(q),1,2),sf,-sum(sf;dims=1)), rho, residual, sd)
end

function logprior(t::Target,q,x=coordinates(t,q))
    p,b,d = t.prior,t.blocks,t.data
    lp = sum(v -> B._normal_logpdf(v,1.0), q[b.person_white]) +
         sum(v -> B._normal_logpdf(v,1.0), q[b.recording_white]) +
         sum(v -> B._normal_logpdf(v,p.word_sd), q[b.word])
    for c in 1:2
        # Normalized density on the first n-1 entries of a zero-sum vector.
        for (values,sd,n) in ((x.rater[:,c],p.rater_sd[c],d.R),
                (x.steps[2:end,c],p.step_sd[c],d.K-1))
            lp += log(n)/2 - (n-1)*(log(2pi)/2+log(sd)) - sum(abs2,values)/(2sd^2)
        end
        lp += B._normal_logpdf(q[b.log_recording_sd[c]]-p.recording_log_sd_mean[c],p.recording_log_sd_sd[c])
        eta = c == 1 ? p.person_lkj_eta : p.recording_lkj_eta
        lp += -t.logbeta[c] + eta*B._log_one_minus_tanh_squared(q[b.z_correlation[c]])
    end
    return lp
end

function logits(t,x,n)
    d=t.data; c=d.criterion[n]
    location=x.theta[c,d.person[n]]-x.word[c,d.word[n]]-x.rater[d.rater[n],c]+x.u[c,d.recording[n]]
    return [zero(location); cumsum(location .- x.steps[2:end,c])]
end
function logprobabilities(t::Target,q)
    x=coordinates(t,q)
    return map(1:t.data.N) do n
        eta=logits(t,x,n); shifted=eta .- maximum(eta)
        shifted .- log(sum(exp,shifted))
    end
end
pointwise(t::Target,q) = [values[t.data.score[n]+1] for (n,values) in enumerate(logprobabilities(t,q))]
LDP.logdensity(t::Target,q::AbstractVector) = logprior(t,q) + sum(pointwise(t,q))

# The scalar PCM score and tail probabilities provide an O(N*K + parameters)
# gradient, avoiding ForwardDiff passes over the full 736-parameter example.
function LDP.logdensity_and_gradient(t::Target,q::AbstractVector)
    x=coordinates(t,q); d,b,p=t.data,t.blocks,t.prior
    lp=logprior(t,q,x)
    gt=zeros(2,d.P); gu=zeros(2,d.O); gb=zeros(2,d.W)
    gr=zeros(d.R,2); gs=zeros(d.K,2)
    for n in 1:d.N
        eta=logits(t,x,n); shifted=eta .- maximum(eta)
        logp=shifted .- log(sum(exp,shifted)); prob=exp.(logp)
        lp += logp[d.score[n]+1]
        delta=d.score[n]-sum((h-1)*prob[h] for h in 1:d.K)
        c=d.criterion[n]
        gt[c,d.person[n]]+=delta; gu[c,d.recording[n]]+=delta
        gb[c,d.word[n]]-=delta; gr[d.rater[n],c]-=delta
        tail=0.0
        for h in d.K:-1:2
            tail+=prob[h]
            gs[h,c]+=tail-(d.score[n]>=h-1)
        end
    end
    g=zeros(length(q))
    zp=reshape(q[b.person_white],2,d.P); zu=reshape(q[b.recording_white],2,d.O)
    g[b.person_white]=vec(vcat(gt[1:1,:]+x.rho[1]*gt[2:2,:],x.residual[1]*gt[2:2,:]))-q[b.person_white]
    g[b.recording_white]=vec(vcat(x.sd[1]*gu[1:1,:]+x.sd[2]*x.rho[2]*gu[2:2,:],
        x.sd[2]*x.residual[2]*gu[2:2,:]))-q[b.recording_white]
    g[b.word]=vec(gb)-q[b.word]/p.word_sd^2
    for c in 1:2
        gr[:,c] .-= x.rater[:,c]./p.rater_sd[c]^2
        gs[2:end,c] .-= x.steps[2:end,c]./p.step_sd[c]^2
        g[b.log_recording_sd[c]]=sum(gu[c,:].*x.u[c,:])-
            (q[b.log_recording_sd[c]]-p.recording_log_sd_mean[c])/p.recording_log_sd_sd[c]^2
    end
    g[b.rater_free]=vec(gr[1:end-1,:].-gr[end:end,:])
    g[b.step_free]=vec(gs[2:end-1,:].-gs[end:end,:])
    g[b.z_correlation[1]]=sum(gt[2,:].*(x.residual[1]^2 .*zp[1,:]-x.rho[1]*x.residual[1].*zp[2,:]))-2p.person_lkj_eta*x.rho[1]
    g[b.z_correlation[2]]=sum(gu[2,:].*x.sd[2].*(x.residual[2]^2 .*zu[1,:]-x.rho[2]*x.residual[2].*zu[2,:]))-2p.recording_lkj_eta*x.rho[2]
    return lp,g
end

function canonical_rows(d)
    [(; person=d.levels.person[d.person[n]],word=d.levels.word[d.word[n]],
        rater=d.levels.rater[d.rater[n]],recording=d.levels.recording[d.recording[n]],
        criterion=d.levels.criterion[d.criterion[n]],score=d.score[n]) for n in 1:d.N]
end
snapshot(t::Target) = Target(canonical_rows(t.data); categories=t.data.K,criteria=t.data.levels.criterion,prior=t.prior)
identity(t::Target) = B._cache_hash((;schema=SCHEMA,data=t.data,prior=t.prior))

function fit_julia(t::Target; ndraws::Int,warmup::Int,chains::Int,seed,kwargs...)
    t=snapshot(t)
    run=B._run_generalized_candidate_advancedhmc(t,initial(t);
        ndraws,warmup,chains,seed,ad_backend=:analytic,record_warmup=true,kwargs...)
    return checked_result(t,run)
end
function checked_result(t::Target,run)
    B._check_generalized_sample_run(t,run)
    record=(;schema=SCHEMA,data=t.data,prior=t.prior,target_identity=identity(t),run)
    return merge(record,(;content_hash=B._cache_hash(record)))
end
function restore(record)
    keys(record)==(:schema,:data,:prior,:target_identity,:run,:content_hash) && record.schema==SCHEMA ||
        throw(ArgumentError("invalid A0 sample record"))
    body=Base.structdiff(record,(;content_hash=nothing))
    B._cache_hash(body)==record.content_hash || throw(ArgumentError("A0 sample checksum mismatch"))
    t=Target(canonical_rows(record.data);categories=record.data.K,criteria=record.data.levels.criterion,prior=record.prior)
    isequal(t.data,record.data) && identity(t)==record.target_identity || throw(ArgumentError("A0 target mismatch"))
    B._check_generalized_sample_run(t,record.run)
    return t
end
function save_result(path,record)
    restore(record)
    return B._save_serialized_record(path,record;overwrite=false)
end
function load_result(path)
    record=open(deserialize,path) # trusted same-environment files only
    restore(record)
    return record
end

function report(record)
    t=restore(record); run=record.run; d=t.data
    names=[ ["theta[$id,$c]" for id in d.levels.person for c in 1:2];
        ["recording[$id,$c]" for id in d.levels.recording for c in 1:2];
        ["word[$id,$c]" for id in d.levels.word for c in 1:2];
        ["rater[$id,$c]" for c in 1:2 for id in d.levels.rater];
        ["step[$h,$c]" for c in 1:2 for h in 1:d.K-1];
        ["recording_sd[1]","recording_sd[2]","rho_person","rho_recording"] ]
    draws=reduce(vcat,[begin
        x=coordinates(t,q)
        permutedims([vec(x.theta);vec(x.u);vec(x.word);vec(x.rater);vec(x.steps[2:end,:]);x.sd;x.rho])
    end for q in eachrow(run.draws)])
    fixed=d.K==2 ? Set(["step[1,1]","step[1,2]"]) : Set{String}()
    diagnose(values,labels;fixed=Set{String}(),space=:model)=B._candidate_mcmc_diagnostic_rows(values,labels,run.controls.chains;
        parameter_space=space,structurally_fixed_parameters=fixed,
        split_chains=run.split_chains_requested,rhat_threshold=run.checked.rhat_threshold,ess_threshold=run.checked.ess_threshold)
    return (; model="A0 paired-rating reference",status="engineering validation only; inspect all warnings",
        data=(;d.P,d.W,d.R,d.O,d.K,d.N,criteria=d.levels.criterion),prior=t.prior,
        target_identity=record.target_identity,controls=run.controls,
        posterior=B._posterior_summary_rows(draws,names;lower=0.025,upper=0.975,
            intervals=(0.66,0.9,0.95),reference=0.0,rope=nothing,rope_probability_threshold=0.95),
        mcse=B._posterior_mcse_rows(draws,names,run.controls.chains;parameter_space=:model,structurally_fixed_parameters=fixed),
        raw_diagnostics=diagnose(run.draws,t.names;space=:raw_noncentered),model_diagnostics=diagnose(draws,names;fixed),
        sampler=run.sampler_rows,warmup=B._warmup_diagnostic_rows(run.warmup_stats,run.controls,run.backend))
end

function stan_data(t::Target)
    d,p=t.data,t.prior
    return (;d.P,d.W,d.R,d.O,d.K,d.N,person=d.person,word=d.word,rater=d.rater,
        recording=d.recording,criterion=d.criterion,y=d.score.+1,p.word_sd,
        rater_sd=collect(p.rater_sd),step_sd=collect(p.step_sd),
        recording_log_sd_mean=collect(p.recording_log_sd_mean),
        recording_log_sd_sd=collect(p.recording_log_sd_sd),p.person_lkj_eta,p.recording_lkj_eta)
end

const STAN_SOURCE=joinpath(@__DIR__,"stan","paired_rating_reference.stan")
function compile_stan(directory)
    check=B.cmdstan_backend_check(;require_ready=true,include_paths=true)
    all(isempty(get(ENV,name,"")) for name in ("MAKEFILES","MAKEFLAGS","GNUMAKEFLAGS")) ||
        throw(ArgumentError("inherited make options are not supported"))
    make=B._cmdstan_configured_program("MAKE",("make","gmake"))
    make===nothing && throw(ArgumentError("make is unavailable"))
    ispath(directory) && throw(ArgumentError("select a new empty compile directory"))
    mkdir(directory)
    stem=abspath(joinpath(directory,"paired_rating_reference"))
    cp(STAN_SOURCE,stem*".stan")
    # Keep compiler-specific precompiled headers out of the shared CmdStan tree.
    B._cmdstan_run(Cmd(`$make -f makefile PRECOMPILED_HEADERS=false $stem`;dir=check.cmdstan_root),:model_compile)
    return (;path=stem,sha256=B._cmdstan_executable_sha256(stem,:model_compile),
        source_sha256=bytes2hex(sha256(read(STAN_SOURCE))),version=check.cmdstan_version)
end

function fit_cmdstan(t::Target,compiled;ndraws::Int,warmup::Int,chains::Int,seed,
        step_size::Real=0.03,target_accept::Real=0.8,max_depth::Int=10,init_jitter::Real=0.0)
    t=snapshot(t)
    step_size=B._check_fit_controls(ndraws,warmup,chains,step_size)
    target_accept,_,init_jitter=B._check_nuts_controls(target_accept,max_depth,1000.0,init_jitter)
    compiled.source_sha256==bytes2hex(sha256(read(STAN_SOURCE))) || throw(ArgumentError("Stan source changed"))
    rng,rng_control=B._fit_rng(MersenneTwister(0),seed)
    q=initial(t)
    parse_chain=(path,chain,count)->begin
        parsed=B._cmdstan_raw_chain_result(path,LDP.dimension(t),t.data.N,chain,count,
            v->(;pointwise=pointwise(t,v),logposterior=LDP.logdensity(t,v));warmup)
        all(isapprox(s.stan_lp,lp;atol=1e-8,rtol=1e-8) for (s,lp) in zip(parsed.stats,parsed.logps)) ||
            throw(ArgumentError("Stan/Julia normalized A0 posterior mismatch"))
        parsed
    end
    sampled=B._cmdstan_sample_chains(compiled.path,stan_data(t),q,rng,v->LDP.logdensity(t,v),parse_chain;
        expected_sha256=compiled.sha256,ndraws,warmup,chains,step_size=Float64(step_size),
        target_accept=Float64(target_accept),max_depth,metric="diag_e",init_jitter=Float64(init_jitter),
        progress=false,record_warmup=true)
    controls=(;ndraws,warmup,chains,step_size=Float64(step_size),target_accept=Float64(target_accept),
        max_depth,max_energy_error=1000.0,metric=:diagonal,ad_backend=:stan_reverse_mode,
        gradient_backend=:stan_autodiff,rng=merge(rng_control,(;chain_seeds=Tuple(sampled.chain_seeds))),
        init_jitter=Float64(init_jitter),thinning=1,cmdstan_version=compiled.version,
        cmdstan_executable_sha256=compiled.sha256,execution=:cmdstan_cli)
    run=(;checked=B._check_diagnostic_thresholds(1.01,400),nparams=LDP.dimension(t),initial=q,
        initial_logdensity=LDP.logdensity(t,q),total_draws=ndraws*chains,
        draws=sampled.draws,logdensities=sampled.logdensities,chain_ids=sampled.chain_ids,
        iterations=sampled.iterations,chain_acceptance=sampled.chain_acceptance,sampler_stats=sampled.sampler_stats,
        controls,sampler_rows=B._generalized_candidate_sampler_rows(sampled.logdensities,sampled.iterations,
            sampled.chain_acceptance,sampled.sampler_stats,controls,:cmdstan),backend=:cmdstan,sampler=:nuts,
        split_chains_requested=true,actual_split=chains>=2 && ndraws>=4,warmup_stats=sampled.warmup_stats)
    return checked_result(t,run)
end

include("paired_rating_predictive.jl")
include("paired_rating_precision.jl")

end # module
