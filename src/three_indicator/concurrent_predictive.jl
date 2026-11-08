"""Existing-level posterior predictive counts for the concurrent 9/9/2 target."""
module ConcurrentPredictive
using Random, Statistics, JSON3, SHA
import BayesianMGMFRM as B
import ..Concurrent as C
import ..ConcurrentReports as R
import ..ConcurrentWorkflow as F
const LEGACY_SCHEMA="bayesianmgmfrm.concurrent_posterior_predictive.v1"
const SCHEMA="bayesianmgmfrm.concurrent_posterior_predictive.v3"
const EXACT_SEED_SCHEMA="bayesianmgmfrm.concurrent_posterior_predictive.v2"
const SCHEMAS=(LEGACY_SCHEMA,EXACT_SEED_SCHEMA,SCHEMA)
valid_seed_string(x)=x isa AbstractString && occursin(r"\A(?:0|[1-9][0-9]*)\z",x) &&
    tryparse(Int,x)!==nothing && parse(Int,x)>=0
const require=C.require
const FIT_WARNING="The fitted posterior did not pass whole-fit numerical diagnostics."
index(g,a,k)=(g-1)*101+(a==1 ? 0 : a==2 ? 9 : 18)+k
joint(g,a,c)=(g-1)*101+20+(a-1)*9+c

function layout(t)
    d=C.modeldata(t);panel=[d.rater_group[r]==3 ? 2 : 1 for r in d.rater]
    denominators=[count(==(g),panel) for g in 1:2]
    definitions=NamedTuple[]
    for g in 1:2
        for a in 1:3,k in 1:d.K[a]
            push!(definitions,(;panel=g,kind="marginal",outcome=F.OUTCOMES[a],category=k,a=0,c=0,
                denominator=denominators[g],name="panel[$g]/$(F.OUTCOMES[a])/category[$k]"))
        end
        for a in 1:9,c in 1:9
            push!(definitions,(;panel=g,kind="ac_joint",outcome="A/C",category=0,a,c,
                denominator=denominators[g],name="panel[$g]/joint[$a,$c]"))
        end
    end
    observed=zeros(Int,202)
    for n in eachindex(panel)
        for a in 1:3;observed[index(panel[n],a,d.y[n,a])]+=1;end
        observed[joint(panel[n],d.y[n,1],d.y[n,2])]+=1
    end
    (;panel,denominators,definitions,observed)
end

joint_workspace(t)=nothing
joint_workspace(t::C.AssociationTarget)=(;table=C.PlackettTable.Workspace(9,9),a=zeros(9),b=zeros(9))
joint_probabilities!(::Nothing,t,z,n)=nothing
function joint_probabilities!(w,t::C.AssociationTarget,z,n)
    C.logits!(w.a,t,z,n,1);C.logits!(w.b,t,z,n,2)
    C.PlackettTable.probabilities!(w.table,w.a,w.b,z.ac_log_psi)
    w.table.probability
end
function check_replication_law(r,current_schema)
    law=C.check_observation_contract(r.model)
    if r.schema==current_schema
        require(hasproperty(r,:replication_law) && r.replication_law==String(law),"replication law differs from model")
    else
        require(law===:independent_three_responses,"legacy predictive schema cannot describe dependent responses")
    end
end

# Kept separate from the saved-fit driver so the inner loop specializes on arrays.
function state!(counts,mu,variance,t,q,panel,rng;uniforms=nothing)
    fill!(counts,0);fill!(mu,0.);fill!(variance,0.)
    z=C.reconstruct(t,q);p=R.blank();buffer=zeros(9);y=zeros(Int,3);work=joint_workspace(t)
    uniforms===nothing || require(size(uniforms)==(length(panel),3) && all(u->isfinite(u)&&0<=u<1,uniforms),"uniforms must be finite N×3 values in [0,1)")
    for n in eachindex(panel)
        R.probabilities!(p,buffer,t,z,n);g=panel[n];ac=joint_probabilities!(work,t,z,n)
        u=uniforms===nothing ? rand(rng,3) : view(uniforms,n,:)
        for a in 1:3
            require(all(isfinite,p[a]) && all(>=(0),p[a]) && isapprox(sum(p[a]),1.;atol=1e-12),"invalid predictive probabilities")
            cumulative=0.;y[a]=length(p[a])
            for k in eachindex(p[a])
                cumulative+=ac!==nothing && a==2 ? ac[y[1],k]/p[1][y[1]] : p[a][k]
                if u[a]<cumulative;y[a]=k;break;end
            end
            counts[index(g,a,y[a])]+=1
            for k in eachindex(p[a])
                j=index(g,a,k);prob=p[a][k];mu[j]+=prob;variance[j]+=prob*(1-prob)
            end
        end
        counts[joint(g,y[1],y[2])]+=1
        for a in 1:9,c in 1:9
            j=joint(g,a,c);prob=ac===nothing ? p[1][a]*p[2][c] : ac[a,c];mu[j]+=prob;variance[j]+=prob*(1-prob)
        end
    end
    nothing
end

function maxima(observed,replicated,mu,variance)
    out=zeros(4)
    for g in 1:2
        ix=joint(g,1,1):joint(g,9,9)
        require(all(>(0),variance[ix]),"joint count variance underflow; predictive discrepancy unavailable")
        out[2g-1]=maximum(abs.(observed[ix].-mu[ix])./sqrt.(variance[ix]))
        out[2g]=maximum(abs.(Float64.(replicated[ix]).-mu[ix])./sqrt.(variance[ix]))
    end
    out
end

function replicate_chain!(counts,discrepancy,total,t,plan,chain,design,seed,offset)
    rng=MersenneTwister(seed);mu=zeros(202);variance=zeros(202)
    for (i,q) in enumerate(eachrow(chain.run.draws))
        row=view(counts,offset+i,:)
        state!(row,mu,variance,t,F.native_point(plan,t,q),design.panel,rng)
        total.+=mu
        discrepancy[offset+i,:]=maxima(design.observed,row,mu,variance)
    end
end

function replicate(t,f,design,seeds)
    S=f.plan.record.controls.ndraws*length(f.chains)
    maxN=maximum(design.denominators)
    require(maxN<=typemax(UInt32),"panel count exceeds supported integer storage")
    T=maxN<=typemax(UInt16) ? UInt16 : UInt32
    counts=zeros(T,S,202);discrepancy=zeros(S,4);total=zeros(202);offset=0
    for chain in f.chains
        replicate_chain!(counts,discrepancy,total,t,f.plan,chain,design,seeds[chain.chain],offset)
        offset+=size(chain.run.draws,1)
    end
    (;counts,discrepancy,conditional_expected_mean=total./S)
end

function mean_mcse(x,chains;structural=false)
    structural && return 0.
    require(length(x)%chains==0,"incomplete predictive chains")
    a=reshape(Float64.(x),:,chains)
    size(a,1)>=8 && !any(allequal,eachcol(a)) || return nothing
    v=B.MCMCDiagnosticTools.mcse(a;kind=mean,split_chains=2)
    isfinite(v) && v>=0 ? Float64(v) : nothing
end
function estimate(x,chains;structural=false)
    se=mean_mcse(x,chains;structural)
    (;estimate=mean(x),mcse=se,precision_status=structural ? :analytic_support :
        se===nothing ? :unavailable_constant_or_short_chain : :estimated_chain_mcse)
end
function endpoint(x,sorted,p,N,chains)
    q=sorted[ceil(Int,length(x)*p)]
    below=estimate(x.<q,chains;structural=q==0)
    at=estimate(x.<=q,chains;structural=q==N)
    available=below.mcse!==nothing && at.mcse!==nothing
    stable=available && below.estimate+2*below.mcse<p && at.estimate-2*at.mcse>=p
    (;probability=p,count=Int(q),cdf_below=below,cdf_at=at,
        status=!available ? :cdf_mcse_unavailable : stable ? :stable_under_pointwise_cdf_mcse_screen : :unresolved_cdf_mcse_screen,
        quantile_mcse=nothing)
end

function summarize(counts,discrepancy,design,expected,chains,interval)
    lo,hi=F.bounds(interval)
    rows=map(eachindex(design.definitions)) do j
        x=Float64.(counts[:,j]);sorted=sort(x);def=design.definitions[j];N=def.denominator;obs=design.observed[j]
        lower=endpoint(x,sorted,lo,N,chains);upper=endpoint(x,sorted,hi,N,chains)
        (;def...,observed=obs,mean=mean(x),mean_mcse=mean_mcse(x,chains),conditional_expected_mean=expected[j],
            median=sorted[ceil(Int,length(x)*.5)],lower=lower.count,upper=upper.count,
            lower_endpoint=lower,upper_endpoint=upper,
            lower_tail=estimate(x.<=obs,chains;structural=obs==N),
            upper_tail=estimate(x.>=obs,chains;structural=obs==0),ties=estimate(x.==obs,chains),
            outside_pointwise_interval=obs<lower.count || obs>upper.count)
    end
    joint_rows=map(1:2) do g
        observed=discrepancy[:,2g-1];replicated=discrepancy[:,2g]
        (;panel=g,observed_discrepancy_mean=mean(observed),replicated_discrepancy_mean=mean(replicated),
            replicated_quantiles=quantile(replicated,[lo,.5,hi]),
            upper_tail=estimate(replicated.>=observed,chains),quantile_precision=:not_computed)
    end
    (;rows,joint=joint_rows)
end

function qualification(f,report)
    if report===nothing
        return (;value=F.qualify(f),source=:computed_from_fit,report_hash=nothing,warnings=String[])
    end
    checked=F.check_report(report)
    require(checked.source_fit_hash==F.identity(f),"qualification report belongs to a different fit")
    (;value=checked.qualification,source=:validated_same_fit_report,
        report_hash=checked.content_hash,warnings=collect(checked.warnings))
end

function check(f::F.Fit;seed,interval=.95,conditioning=:existing_levels,qualification_report=nothing)
    require(conditioning===:existing_levels,"only existing-level posterior predictive replication is supported")
    require(seed isa Integer && !(seed isa Bool) && 0<=seed<=typemax(Int),"nonnegative Int seed required")
    F.bounds(interval);t=F.checked(f);c=f.plan.record.controls
    qualified=qualification(f,qualification_report)
    seeds=rand(MersenneTwister(Int(seed)),0:typemax(Int),c.chains)
    require(allunique(seeds),"duplicate predictive chain seeds")
    design=layout(t);draws=replicate(t,f,design,seeds)
    result=summarize(draws.counts,draws.discrepancy,design,draws.conditional_expected_mean,c.chains,interval)
    warnings=vcat(f.plan.record.adaptation_plan.warnings,C.observation_warnings(t))
    f.plan.record.coordinates.experimental && push!(warnings,F.CHART_WARNING)
    !qualified.value.qualified && push!(warnings,FIT_WARNING)
    append!(warnings,["Posterior predictive check: parameters come from the fitted posterior, not the prior.",
        "Existing effects and observed allocation/history are conditioned on; new-level prediction is not assessed.",
        "Count intervals describe replicated responses, not uncertainty in expected probabilities.",
        "Tail areas and pointwise outside flags are descriptive, not calibrated significance tests.",
        "Discrete endpoint CDF screens are not quantile MCSE or simultaneous confidence guarantees."])
    unresolved=count(e->e.status!==:stable_under_pointwise_cdf_mcse_screen,
        [e for r in result.rows for e in (r.lower_endpoint,r.upper_endpoint)])
    unresolved>0 && push!(warnings,"Some discrete endpoint CDF precision screens remain unresolved or unavailable.")
    body=(;schema=SCHEMA,replication_law=C.observation(t),check_type=:posterior_predictive,parameter_source=:fitted_posterior,
        conditioning,data_used_to_estimate_parameters=true,prior_predictive_performed=false,
        scientific_acceptance=false,new_fits=0,model=C.contract(t),source_fit_hash=F.identity(f),
        producer=f.plan.record.context,context=F.W.context(),coordinates=f.plan.record.coordinates,
        posterior_fit_qualified=qualified.value.qualified,qualification=qualified.value,
        qualification_source=qualified.source,qualification_report_hash=qualified.report_hash,
        source_report_warnings=qualified.warnings,warnings,
        seed=string(seed),chain_seeds=string.(seeds),seed_encoding=:decimal_strings,rng=:MersenneTwister,rng_julia_version=string(VERSION),
        chains=c.chains,draws_per_chain=c.ndraws,replications=c.chains*c.ndraws,
        chain_ids=repeat(1:c.chains;inner=c.ndraws),iterations=repeat(1:c.ndraws;outer=c.chains),
        category_support=copy(C.modeldata(t).K),direction=:higher_is_adverse,binary_coding="1=correct;2=error",
        panels=["main_222","english_20"],denominators=design.denominators,
        event_ids=copy(C.modeldata(t).labels.event),source_rows=copy(C.modeldata(t).source_rows),
        interval,interval_method=:inverse_empirical_cdf,endpoint_screen_multiplier=2.,
        predictive_precision=:reported_by_quantity,discrete_endpoints_unresolved=unresolved,
        discrepancy_definition=:max_absolute_ac_count_residual_over_conditional_sd,
        retained_response_cube=false,result...)
    safe=B.Experimental.JointRatings.W.jsonsafe(body);d=R.normalized(safe)
    d["content_hash"]=B._cache_hash(d)
    check_report(JSON3.read(JSON3.write(d)))
end

finite(x)=x isa Real && !(x isa Bool) && isfinite(x)
function check_estimate(x)
    require(finite(x.estimate) && 0<=x.estimate<=1,"invalid predictive tail/CDF estimate")
    require(x.mcse===nothing || (finite(x.mcse) && x.mcse>=0),"invalid predictive MCSE")
    require(x.precision_status in ("analytic_support","estimated_chain_mcse","unavailable_constant_or_short_chain"),"unknown precision status")
    require((x.mcse===nothing)==(x.precision_status=="unavailable_constant_or_short_chain"),"MCSE status differs")
    x.precision_status=="analytic_support" && require(x.estimate in (0,1) && x.mcse==0,"analytic support differs")
end
function check_report(r)
    check_replication_law(r,SCHEMA)
    d=R.normalized(r);h=pop!(d,"content_hash",nothing)
    require(R.hashstring(h) && B._cache_hash(d)==h,"posterior predictive report content changed")
    require(r.schema in SCHEMAS && r.check_type=="posterior_predictive" && r.parameter_source=="fitted_posterior" &&
        r.data_used_to_estimate_parameters===true && r.prior_predictive_performed===false &&
        r.conditioning=="existing_levels" && r.scientific_acceptance===false && r.new_fits==0,"predictive provenance differs")
    require(R.hashstring(r.source_fit_hash) && R.hashstring(r.producer.package),"source identity required")
    require(r.chains>=2 && r.draws_per_chain>=10 && r.replications==r.chains*r.draws_per_chain &&
        collect(r.chain_ids)==repeat(1:r.chains;inner=r.draws_per_chain) &&
        collect(r.iterations)==repeat(1:r.draws_per_chain;outer=r.chains),"predictive chain layout differs")
    require(length(r.chain_seeds)==r.chains && allunique(r.chain_seeds) && r.rng=="MersenneTwister","predictive RNG layout differs")
    if r.schema in (SCHEMA,EXACT_SEED_SCHEMA)
        require(r.seed_encoding=="decimal_strings" && valid_seed_string(r.seed) &&
            all(valid_seed_string,r.chain_seeds),"exact decimal-string predictive seeds required")
    else
        # Legacy v1 remains readable; its large stream seeds may have been rounded.
        require(all(s->s isa Integer && !(s isa Bool) && s>=0,r.chain_seeds) &&
            r.seed isa Integer && !(r.seed isa Bool) && r.seed>=0,"invalid legacy predictive seed")
    end
    require(R.normalized(r.coordinates)==R.normalized(F.coordinate_contract(Symbol(r.coordinates.name))) &&
        (!r.coordinates.experimental || F.CHART_WARNING in r.warnings),"sampler-coordinate metadata/warning differs")
    require(r.qualification_source in ("computed_from_fit","validated_same_fit_report") &&
        (r.qualification_source=="computed_from_fit" ? r.qualification_report_hash===nothing : R.hashstring(r.qualification_report_hash)),"qualification provenance differs")
    require(r.posterior_fit_qualified===r.qualification.qualified &&
        (r.posterior_fit_qualified || FIT_WARNING in r.warnings),"fitted-posterior warning lost")
    require(collect(r.category_support)==[9,9,2] && r.direction=="higher_is_adverse" &&
        r.binary_coding=="1=correct;2=error" &&
        collect(r.panels)==["main_222","english_20"] && length(r.denominators)==2 && all(>(0),r.denominators),"support or panels differ")
    N=sum(r.denominators)
    require(length(r.event_ids)==N && allunique(r.event_ids) && sort(collect(r.source_rows))==collect(1:N),"event/source identities differ")
    require(length(r.rows)==202 && length(r.joint)==2 && allunique(x.name for x in r.rows),"predictive summary scope differs")
    lo,hi=F.bounds(r.interval)
    require(r.endpoint_screen_multiplier==2 && r.interval_method=="inverse_empirical_cdf" &&
        r.predictive_precision=="reported_by_quantity" && r.retained_response_cube===false,"interval/precision contract differs")
    unresolved=0
    for (j,x) in enumerate(r.rows)
        g=div(j-1,101)+1;i=mod(j-1,101)+1
        if i<=20
            a=i<=9 ? 1 : i<=18 ? 2 : 3;k=i-(a==1 ? 0 : a==2 ? 9 : 18)
            require(x.panel==g && x.kind=="marginal" && x.outcome==F.OUTCOMES[a] && x.category==k &&
                x.a==0 && x.c==0 && x.name=="panel[$g]/$(F.OUTCOMES[a])/category[$k]","category definition differs")
        else
            a=div(i-21,9)+1;c=mod(i-21,9)+1
            require(x.panel==g && x.kind=="ac_joint" && x.outcome=="A/C" && x.category==0 &&
                x.a==a && x.c==c && x.name=="panel[$g]/joint[$a,$c]","joint-cell definition differs")
        end
        require(x.panel in (1,2) && x.denominator==r.denominators[x.panel] && x.observed isa Integer &&
            0<=x.observed<=x.denominator && 0<=x.lower<=x.median<=x.upper<=x.denominator &&
            finite(x.mean) && 0<=x.mean<=x.denominator,"invalid predictive count")
        require(x.mean_mcse===nothing || (finite(x.mean_mcse) && x.mean_mcse>=0),"invalid mean MCSE")
        require(x.outside_pointwise_interval===(x.observed<x.lower || x.observed>x.upper),"outside flag differs")
        for (e,p,q) in ((x.lower_endpoint,lo,x.lower),(x.upper_endpoint,hi,x.upper))
            require(e.probability==p && e.count==q && e.quantile_mcse===nothing,"endpoint definition differs")
            check_estimate(e.cdf_below);check_estimate(e.cdf_at)
            require(e.cdf_below.estimate<=e.cdf_at.estimate &&
                (e.cdf_below.precision_status=="analytic_support")== (q==0) &&
                (e.cdf_at.precision_status=="analytic_support")== (q==x.denominator),"CDF support differs")
            available=e.cdf_below.mcse!==nothing && e.cdf_at.mcse!==nothing
            stable=available && e.cdf_below.estimate+2*e.cdf_below.mcse<p && e.cdf_at.estimate-2*e.cdf_at.mcse>=p
            status=!available ? "cdf_mcse_unavailable" : stable ? "stable_under_pointwise_cdf_mcse_screen" : "unresolved_cdf_mcse_screen"
            require(e.status==status,"endpoint precision screen differs");unresolved+=!stable
        end
        foreach(check_estimate,(x.lower_tail,x.upper_tail,x.ties))
        require((x.lower_tail.precision_status=="analytic_support")== (x.observed==x.denominator) &&
            (x.upper_tail.precision_status=="analytic_support")== (x.observed==0) &&
            x.ties.precision_status!="analytic_support","tail support differs")
    end
    for g in 1:2
        N=r.denominators[g]
        for ix in (index(g,1,1):index(g,1,9),index(g,2,1):index(g,2,9),
                   index(g,3,1):index(g,3,2),joint(g,1,1):joint(g,9,9))
            require(sum(r.rows[j].observed for j in ix)==N &&
                isapprox(sum(r.rows[j].mean for j in ix),N;atol=1e-10,rtol=1e-12),"count denominator differs")
        end
    end
    require(r.discrete_endpoints_unresolved==unresolved,"unresolved endpoint count differs")
    for (g,x) in enumerate(r.joint)
        require(x.panel==g && x.quantile_precision=="not_computed" &&
            finite(x.observed_discrepancy_mean) && x.observed_discrepancy_mean>=0 &&
            finite(x.replicated_discrepancy_mean) && x.replicated_discrepancy_mean>=0 &&
            all(finite,x.replicated_quantiles) && issorted(x.replicated_quantiles),"invalid joint discrepancy summary")
        check_estimate(x.upper_tail)
    end
    r
end
function save(path,r)
    check_report(r);require(!(ispath(path)||islink(path)),"preserve existing predictive report")
    mkpath(dirname(abspath(path)))
    mktemp(dirname(abspath(path))) do temporary,io
        JSON3.write(io,r);close(io);hardlink(temporary,path)
    end
    (;path=abspath(path),sha256=bytes2hex(sha256(read(path))))
end
end
