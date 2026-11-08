"""Joint-prior response replication on the declared concurrent design."""
module ConcurrentPriorPredictive
using Random, Statistics, JSON3, SHA
using Distributions: Beta
import BayesianMGMFRM as B
import ..Concurrent as C
import ..ConcurrentReports as R
import ..ConcurrentWorkflow as F
import ..ConcurrentPredictive as P
const require=C.require
const SCHEMA="bayesianmgmfrm.concurrent_prior_predictive.v3"
const SCHEMAS=(SCHEMA,"bayesianmgmfrm.concurrent_prior_predictive.v2")

# Sample the normalized effective-coordinate prior, not the posterior initializer.
function parameter_draw(rng,t)
    q=randn(rng,C.L.dimension(t));p=t.prior;s=C.prior_record(p)
    q[t.blocks[:step_q]].*=C.step_coordinate_sd(p)
    q[t.blocks[:step_q]].+=repeat(t.bases.step'*collect(s.step_mean),2)
    q[t.blocks[:beta]].*=repeat(collect(s.beta_sd);inner=24)
    q[t.blocks[:log_sd]]=log.(abs.(randn(rng,18)).*repeat(collect(p.sd_scale);inner=3))
    q[t.blocks[:log_step_sd]]=log.(abs.(randn(rng,2)).*p.step_sd_scale)
    q[t.blocks[:pair_log_sd]]=log.(abs.(randn(rng,length(t.blocks[:pair_log_sd]))).*C.pair_sd_scale(p))
    for key in (:correlation,:pair_correlation)
        eta=key==:correlation ? p.lkj_eta : C.pair_lkj_eta(p)
        for b in 0:(length(t.blocks[key])÷3-1),(k,j) in enumerate((1,1,2))
            a=eta+(3-j-1)/2
            q[first(t.blocks[key])+3b+k-1]=atanh(2rand(rng,Beta(a,a))-1)
        end
    end
    require(all(isfinite,q),"prior draw exceeds floating-point support; no clipping or redraw was applied")
    q
end

parameter_draw(rng,t::C.AssociationTarget)=vcat(parameter_draw(rng,t.base),t.log_sd*randn(rng))

function estimate(x;structural=false)
    se=structural ? 0. : allequal(x) ? nothing : std(x)/sqrt(length(x))
    (;estimate=mean(x),mcse=se,precision_status=structural ? :analytic_support :
        se===nothing ? :unavailable_constant_sample : :estimated_iid_mcse)
end
function endpoint(x,sorted,p,N)
    q=Int(sorted[ceil(Int,length(x)*p)])
    below=estimate(x.<q;structural=q==0);at=estimate(x.<=q;structural=q==N)
    available=below.mcse!==nothing && at.mcse!==nothing
    stable=available && below.estimate+2*below.mcse<p && at.estimate-2*at.mcse>=p
    (;probability=p,count=q,cdf_below=below,cdf_at=at,quantile_mcse=nothing,
        status=!available ? :cdf_mcse_unavailable : stable ? :stable_under_pointwise_cdf_mcse_screen : :unresolved_cdf_mcse_screen)
end
function summarize(counts,design,expected,interval)
    lo,hi=F.bounds(interval)
    map(eachindex(design.definitions)) do j
        x=Float64.(counts[:,j]);sorted=sort(x);def=design.definitions[j];N=def.denominator
        lower=endpoint(x,sorted,lo,N);upper=endpoint(x,sorted,hi,N);obs=design.observed[j]
        (;def...,observed=obs,mean=mean(x),mean_mcse=estimate(x).mcse,
            conditional_expected_mean=expected[j],median=Int(sorted[ceil(Int,length(x)*.5)]),
            lower=lower.count,upper=upper.count,lower_endpoint=lower,upper_endpoint=upper,
            outside_pointwise_interval=obs<lower.count || obs>upper.count)
    end
end
function replicate(t,ndraws,seeds)
    design=P.layout(t);maxN=maximum(design.denominators)
    require(maxN<=typemax(UInt32),"panel count exceeds supported integer storage")
    T=maxN<=typemax(UInt16) ? UInt16 : UInt32
    counts=zeros(T,ndraws,202);total=zeros(202);mu=zeros(202);variance=zeros(202)
    parameters=MersenneTwister(seeds[1]);responses=MersenneTwister(seeds[2])
    for s in 1:ndraws
        q=parameter_draw(parameters,t)
        P.state!(view(counts,s,:),mu,variance,t,q,design.panel,responses)
        total.+=mu
    end
    (;design,counts,expected=total./ndraws)
end
function check(t::Union{C.Target,C.AssociationTarget};ndraws,seed,interval=.95,conditioning=:declared_design)
    require(ndraws isa Integer && !(ndraws isa Bool) && 2<=ndraws<=typemax(Int),"at least two independent prior draws required")
    require(seed isa Integer && !(seed isa Bool) && 0<=seed<=typemax(Int),"nonnegative Int seed required")
    require(conditioning===:declared_design,"only joint-prior replication on the declared design is supported")
    F.bounds(interval);C.check_target(t)
    seeds=rand(MersenneTwister(Int(seed)),0:typemax(Int),2);require(allunique(seeds),"duplicate RNG stream seeds")
    generated=replicate(t,Int(ndraws),seeds)
    rows=summarize(generated.counts,generated.design,generated.expected,interval)
    unresolved=count(e->e.status!==:stable_under_pointwise_cdf_mcse_screen,[e for x in rows for e in (x.lower_endpoint,x.upper_endpoint)])
    body=(;schema=SCHEMA,replication_law=C.observation(t),check_type=:prior_predictive,parameter_source=:joint_prior,
        data_used_to_estimate_parameters=false,posterior_predictive_performed=false,
        scientific_acceptance=false,new_fits=0,conditioning,model=C.contract(t),context=F.W.context(),
        seed=string(seed),parameter_seed=string(seeds[1]),response_seed=string(seeds[2]),seed_encoding=:decimal_strings,rng=:MersenneTwister,rng_julia_version=string(VERSION),
        replications=Int(ndraws),sampling=:independent_joint_prior,draw_ids=collect(1:Int(ndraws)),
        category_support=copy(C.modeldata(t).K),direction=:higher_is_adverse,binary_coding="1=correct;2=error",
        panels=["main_222","english_20"],denominators=generated.design.denominators,
        event_ids=copy(C.modeldata(t).labels.event),source_rows=copy(C.modeldata(t).source_rows),
        interval,interval_method=:inverse_empirical_cdf,endpoint_screen_multiplier=2.,
        predictive_precision=:reported_by_quantity,discrete_endpoints_unresolved=unresolved,
        retained_response_cube=false,rows,warnings=vcat(C.observation_warnings(t),[
            "Prior predictive check: parameters and existing-roster effects come from the joint prior, not a fitted posterior.",
            "The supplied responses are comparison values only; model/prior choices may still have been data-informed.",
            "Assignment, entity roster and presentation histories are fixed; arbitrary new-level designs are not supplied.",
            "Count intervals describe replicated responses; the conditional expected mean integrates category probabilities over prior draws.",
            "Independent-draw mean/CDF MCSE is separate from predictive intervals; a constant empirical sample has unavailable precision.",
            "Discrete endpoint CDF screens are not quantile MCSE, simultaneous guarantees or calibrated prior-adequacy tests."]))
    d=R.normalized(B.Experimental.JointRatings.W.jsonsafe(body));d["content_hash"]=B._cache_hash(d)
    check_report(JSON3.read(JSON3.write(d)))
end

function check_estimate(x)
    require(P.finite(x.estimate) && 0<=x.estimate<=1,"invalid prior CDF")
    require(x.mcse===nothing || (P.finite(x.mcse) && x.mcse>=0),"invalid prior CDF MCSE")
    require(x.precision_status in ("analytic_support","estimated_iid_mcse","unavailable_constant_sample"),"invalid prior precision status")
    require((x.mcse===nothing)==(x.precision_status=="unavailable_constant_sample"),"prior MCSE status differs")
    x.precision_status=="analytic_support" && require(x.estimate in (0,1) && x.mcse==0,"analytic prior support differs")
end
function check_report(r)
    P.check_replication_law(r,SCHEMA)
    d=R.normalized(r);h=pop!(d,"content_hash",nothing)
    require(R.hashstring(h) && B._cache_hash(d)==h,"prior predictive report content changed")
    require(r.schema in SCHEMAS && r.check_type=="prior_predictive" && r.parameter_source=="joint_prior" &&
        r.data_used_to_estimate_parameters===false && r.posterior_predictive_performed===false &&
        r.scientific_acceptance===false && r.new_fits==0 && r.conditioning=="declared_design","prior predictive provenance differs")
    require(r.replications isa Integer && r.replications>=2 && r.sampling=="independent_joint_prior" &&
        collect(r.draw_ids)==collect(1:r.replications),"independent prior draw layout differs")
    require(r.rng=="MersenneTwister" && r.seed_encoding=="decimal_strings" &&
        all(P.valid_seed_string,(r.seed,r.parameter_seed,r.response_seed)) &&
        r.parameter_seed!=r.response_seed,"exact prior RNG layout differs")
    require(R.hashstring(r.context.package) && R.hashstring(r.model.input_identity) &&
        R.hashstring(r.model.source_sha256) && r.model.likelihood_scale==1,"prior source/model identity differs")
    require(collect(r.category_support)==[9,9,2] && r.direction=="higher_is_adverse" && r.binary_coding=="1=correct;2=error" &&
        collect(r.panels)==["main_222","english_20"] && length(r.denominators)==2 && all(x->x isa Integer && x>0,r.denominators),"prior support/panels differ")
    N=sum(r.denominators)
    require(length(r.event_ids)==N && allunique(r.event_ids) && sort(collect(r.source_rows))==collect(1:N),"prior event identity differs")
    require(length(r.rows)==202 && allunique(x.name for x in r.rows),"prior summary scope differs")
    require(r.interval_method=="inverse_empirical_cdf" && r.endpoint_screen_multiplier==2 &&
        r.predictive_precision=="reported_by_quantity" && r.retained_response_cube===false,"prior precision contract differs")
    lo,hi=F.bounds(r.interval);unresolved=0
    for (j,x) in enumerate(r.rows)
        g=div(j-1,101)+1;i=mod(j-1,101)+1
        if i<=20
            a=i<=9 ? 1 : i<=18 ? 2 : 3;k=i-(a==1 ? 0 : a==2 ? 9 : 18)
            require(x.kind=="marginal" && x.outcome==F.OUTCOMES[a] && x.category==k && x.a==0 && x.c==0 &&
                x.name=="panel[$g]/$(F.OUTCOMES[a])/category[$k]","prior category definition differs")
        else
            a=div(i-21,9)+1;c=mod(i-21,9)+1
            require(x.kind=="ac_joint" && x.outcome=="A/C" && x.category==0 && x.a==a && x.c==c &&
                x.name=="panel[$g]/joint[$a,$c]","prior cell definition differs")
        end
        require(x.panel==g && x.denominator==r.denominators[g] &&
            all(v->v isa Integer,(x.observed,x.lower,x.median,x.upper)) &&
            0<=x.observed<=x.denominator && 0<=x.lower<=x.median<=x.upper<=x.denominator &&
            P.finite(x.mean) && 0<=x.mean<=x.denominator && P.finite(x.conditional_expected_mean) &&
            0<=x.conditional_expected_mean<=x.denominator,"invalid prior count summary")
        require(x.mean_mcse===nothing || (P.finite(x.mean_mcse) && x.mean_mcse>=0),"invalid prior mean MCSE")
        require(x.outside_pointwise_interval===(x.observed<x.lower || x.observed>x.upper),"prior outside flag differs")
        for (e,p,q) in ((x.lower_endpoint,lo,x.lower),(x.upper_endpoint,hi,x.upper))
            require(e.probability==p && e.count==q && e.quantile_mcse===nothing,"prior endpoint differs")
            check_estimate(e.cdf_below);check_estimate(e.cdf_at)
            require(e.cdf_below.estimate<=e.cdf_at.estimate &&
                (e.cdf_below.precision_status=="analytic_support")==(q==0) &&
                (e.cdf_at.precision_status=="analytic_support")==(q==x.denominator),"prior CDF support differs")
            available=e.cdf_below.mcse!==nothing && e.cdf_at.mcse!==nothing
            stable=available && e.cdf_below.estimate+2*e.cdf_below.mcse<p && e.cdf_at.estimate-2*e.cdf_at.mcse>=p
            status=!available ? "cdf_mcse_unavailable" : stable ? "stable_under_pointwise_cdf_mcse_screen" : "unresolved_cdf_mcse_screen"
            require(e.status==status,"prior endpoint precision differs");unresolved+=!stable
        end
    end
    for g in 1:2,ix in (P.index(g,1,1):P.index(g,1,9),P.index(g,2,1):P.index(g,2,9),
                       P.index(g,3,1):P.index(g,3,2),P.joint(g,1,1):P.joint(g,9,9))
        require(sum(r.rows[j].observed for j in ix)==r.denominators[g] &&
            isapprox(sum(r.rows[j].mean for j in ix),r.denominators[g];atol=1e-10,rtol=1e-12),"prior count denominator differs")
    end
    require(r.discrete_endpoints_unresolved==unresolved,"prior unresolved precision count differs")
    r
end
function save(path,r)
    check_report(r);require(!(ispath(path)||islink(path)),"preserve existing prior predictive report")
    mkpath(dirname(abspath(path)))
    mktemp(dirname(abspath(path))) do temporary,io
        JSON3.write(io,r);close(io);hardlink(temporary,path)
    end
    (;path=abspath(path),sha256=bytes2hex(sha256(read(path))))
end
end
