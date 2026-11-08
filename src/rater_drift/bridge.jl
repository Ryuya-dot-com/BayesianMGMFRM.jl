"""RW1 conditional-bridge reports. No sampler or random generation.

Keep the original report intact. Only eligible isolated empty-bin contrasts
receive an additional normal-mixture summary; original fit qualification,
observed-year rows, sampler/model diagnostics and warnings remain available.
"""
module RaterDriftBridge
using Statistics, Serialization, JSON3, SHA
const W=parentmodule(@__MODULE__).RaterDriftWorkflow
const R=W.R
const M=W.M
const B=W.B
const D=B.Distributions
const MC=B.MCMCDiagnosticTools
const SCHEMA="bayesianmgmfrm.rw1_package_report.v2"
const POLICY=(;batch_sizes=(100,200,400,800),primary_batch=200,
    diagnostic_method=:cdf_and_unrounded_normal_coordinate,
    root_cdf_tolerance=1e-10,comparison_flag_mcse=3.)
const LIMITS="Conditional integration only for isolated unrated interior RW1 bins; static changes are structural zeros. Retrospective fixed-judge contrasts. MCSE is asymptotic, not an error bound. No coverage, causal or scientific acceptance."
normal_cdf(x)=D.cdf(D.Normal(),x)
normal_pdf(x)=D.pdf(D.Normal(),x)
nullable(x)=isfinite(x) ? Float64(x) : nothing

function check_arrays(mu,sd)
    mu isa Matrix{Float64} && sd isa Matrix{Float64} &&
        size(mu)==size(sd) && !isempty(mu) && all(isfinite,mu) &&
        all(x->isfinite(x) && x>0,sd) ||
        throw(ArgumentError("finite draw-by-chain means and positive SDs required"))
end

function batch_mcse(x,b)
    x isa AbstractMatrix && size(x,2)>=2 && all(isfinite,x) &&
        b isa Int && b>0 && size(x,1)%b==0 && div(size(x,1),b)>=10 ||
        throw(ArgumentError("at least ten complete batches per chain required"))
    n,c=size(x);a=div(n,b)
    variances=[var([mean(view(x,(j-1)*b+1:j*b,k)) for j in 1:a]) for k in 1:c]
    sqrt(b*sum(variances)/(n*c*c))
end
batch_rows(x)=[(;batch_size=b,mcse=batch_mcse(x,b)) for b in POLICY.batch_sizes]

function diagnostics(x)
    # Keep the same full-lag rule for MCSE and both ESS diagnostics.
    maxlag=size(x,1)
    (;mcse=nullable(MC.mcse(x;kind=mean,split_chains=2,maxlag)),
      rhat=nullable(MC.rhat(x;kind=:rank,split_chains=2)),
      bulk_ess=nullable(MC.ess(x;kind=:bulk,split_chains=2,maxlag)),
      tail_ess=nullable(MC.ess(x;kind=:tail,split_chains=2,maxlag)))
end
diagnostic_ok(d)=W.finite(d.rhat) && 0<d.rhat<W.POLICY.rhat_max &&
    W.finite(d.bulk_ess) && d.bulk_ess>=W.POLICY.bulk_ess_min &&
    W.finite(d.tail_ess) && d.tail_ess>=W.POLICY.tail_ess_min

function mixture_quantile(mu,sd,p)
    check_arrays(mu,sd)
    W.finite(p) && 0<p<1 || throw(ArgumentError("quantile probability outside (0,1)"))
    bounds=mu.+D.quantile(D.Normal(),p).*sd
    all(isfinite,bounds) || throw(ArgumentError("nonfinite quantile bracket"))
    lo,hi=extrema(bounds)
    for _ in 1:100
        q=lo+(hi-lo)/2
        f=mean(normal_cdf.((q.-mu)./sd))-p
        (abs(f)<=1e-13 || hi-lo<=1e-12) && return q
        f>0 ? (hi=q) : (lo=q)
    end
    throw(ArgumentError("normal-mixture quantile did not reach root tolerance"))
end
mixture_density(mu,sd,q)=mean(normal_pdf.((q.-mu)./sd)./sd)

function cdf_diagnostics(mu,sd,q)
    z=(q.-mu)./sd;h=normal_cdf.(z)
    all(isfinite,z) || throw(ArgumentError("nonfinite standardized conditional coordinates"))
    hd=diagnostics(h);zd=diagnostics(z)
    # Recover theoretical CDF ranks before floating-point saturation at 0/1.
    cutoffs=quantile(vec(h),[.05,.95])
    constant_tail=any(a->all(h.<=a) || all(h.>a),cutoffs)
    saturation=constant_tail && (any(==(0),h) || any(==(1),h))
    tail_available=!isnothing(hd.tail_ess)
    tail_ok=tail_available ? hd.tail_ess>=W.POLICY.tail_ess_min : saturation
    ok=diagnostic_ok(zd) && W.finite(hd.rhat) && 0<hd.rhat<W.POLICY.rhat_max &&
       W.finite(hd.bulk_ess) && hd.bulk_ess>=W.POLICY.bulk_ess_min && tail_ok
    (;h,z,cdf=hd,unrounded=zd,diagnostic_passed=ok,
      tail_status=tail_available ? :available : saturation ? :rounded_constant_indicator : :unresolved,
      exact_zeros=count(==(0),h),exact_ones=count(==(1),h))
end

"""Equal-tailed marginal intervals; no event probabilities or counts are inferred.

Raw event summaries remain in original_report. The maximum over fixed batch
sizes and the ESS-based estimate is a sensitivity screen, not an upper bound.
"""
function summarize(mu,sd,raw;interval)
    check_arrays(mu,sd)
    size(raw)==size(mu) && all(isfinite,raw) || throw(ArgumentError("raw contrast differs"))
    W.finite(interval) && 0<interval<1 || throw(ArgumentError("invalid interval mass"))
    mean_batches=batch_rows(mu);md=diagnostics(mu)
    qm=NamedTuple[]
    for p in ((1-interval)/2,.5,(1+interval)/2)
        q=mixture_quantile(mu,sd,p);density=mixture_density(mu,sd,q)
        W.positive(density) || throw(ArgumentError("nonpositive quantile density"))
        cd=cdf_diagnostics(mu,sd,q);h=cd.h
        residual=mean(h)-p
        abs(residual)<=POLICY.root_cdf_tolerance || throw(ArgumentError("quantile CDF residual too large"))
        bs=[(;batch_size=b,mcse=batch_mcse(h,b)/density) for b in POLICY.batch_sizes]
        ess_mcse=isnothing(cd.cdf.mcse) ? nothing : cd.cdf.mcse/density
        qr=quantile(vec(raw),p);fr=mixture_density(mu,sd,qr)
        W.positive(fr) || throw(ArgumentError("nonpositive raw-quantile density"))
        paired=(p.-h)./density.-(p.-(raw.<=qr))./fr
        paired_mcse=batch_mcse(paired,POLICY.primary_batch)
        cdf_difference=Float64.(raw.<=q).-h
        cdf_mcse=batch_mcse(cdf_difference,POLICY.primary_batch)
        push!(qm,(;probability=p,quantile=q,density,cdf_residual=residual,batches=bs,ess_mcse,
            mcse=isnothing(ess_mcse) ? nothing : max(maximum(x.mcse for x in bs),ess_mcse),
            cdf_diagnostics=cd.cdf,unrounded_diagnostics=cd.unrounded,
            diagnostic_passed=cd.diagnostic_passed,cdf_tail_status=cd.tail_status,
            exact_zeros=cd.exact_zeros,exact_ones=cd.exact_ones,
            raw_quantile=qr,paired_difference=q-qr,paired_mcse,
            paired_flag=abs(q-qr)>POLICY.comparison_flag_mcse*paired_mcse,
            paired_cdf_difference=mean(cdf_difference),paired_cdf_mcse=cdf_mcse,
            paired_cdf_flag=abs(mean(cdf_difference))>POLICY.comparison_flag_mcse*cdf_mcse))
    end
    mu_mean=mean(mu);mean_difference=mu_mean-mean(raw)
    paired_mean_mcse=batch_mcse(mu.-raw,POLICY.primary_batch)
    (;mean=mu_mean,sd=sqrt(mean(sd.^2 .+(mu.-mu_mean).^2)),
      lower=qm[1].quantile,median=qm[2].quantile,upper=qm[3].quantile,
      precision=(;mean_mcse=isnothing(md.mcse) ? nothing : max(maximum(x.mcse for x in mean_batches),md.mcse),
          mean_batches,mean_ess_mcse=md.mcse,quantiles=qm),
      mean_diagnostics=md,diagnostic_passed=diagnostic_ok(md) && all(x->x.diagnostic_passed,qm),
      paired_mean_difference=mean_difference,paired_mean_mcse,
      paired_mean_flag=abs(mean_difference)>POLICY.comparison_flag_mcse*paired_mean_mcse,
      method=:conditional_normal_mixture,event_probabilities=:see_original_joint_draw_report)
end

function eligible(t,j,ref,weights,rated)
    !t.static && 1<j<length(t.time_ticks) && j!=ref || return false
    active=findall(>(0),weights)
    !isempty(active) && all(r->!rated[r,j] && rated[r,j-1] && rated[r,j+1] && rated[r,ref],active)
end

function check_original(saved,original,expected_hash)
    expected_hash isa String && occursin(r"\A[0-9a-f]{64}\z",expected_hash) &&
        B._cache_hash(original)==expected_hash || throw(ArgumentError("original report checksum differs"))
    p=saved.plan
    original.schema=="bayesianmgmfrm.rw1_chain_report.v1" &&
        original.plan_hash==p.content_hash && original.chain_hashes==[c.content_hash for c in saved.chains] &&
        original.kind==p.kind && original.context==p.context && original.target==p.target &&
        original.reference==p.reference && original.interval_mass==p.interval &&
        original.panel_weights==p.panel_weights && original.precision_policy==p.precision &&
        original.policy==p.policy || throw(ArgumentError("original report does not match saved chains"))
    original
end

"""Add reviewed interval summaries, preserving the complete original report.

Omit original to compute it with the unchanged raw workflow. When reusing a
saved report, supply its independently retained expected_original_hash.
Eligibility is explicit per row; unsupported/mixed empty configurations keep
the original joint-draw result and its qualification.
"""
function report(saved;original=nothing,expected_original_hash=nothing)
    t=W.check_plan(saved.plan)
    [c.chain for c in saved.chains]==collect(1:4) || throw(ArgumentError("four complete ordered chains required"))
    foreach(c->W.check_chain(saved.plan,c;t),saved.chains)
    if isnothing(original)
        isnothing(expected_original_hash) || throw(ArgumentError("no original report supplied"))
        original=W.report(saved);expected_original_hash=B._cache_hash(original)
    end
    check_original(saved,original,expected_original_hash)
    p=saved.plan;n=p.controls.ndraws;T=length(t.time_ticks)
    batches_supported=all(b->n%b==0 && div(n,b)>=10,POLICY.batch_sizes)
    ref=only(findall(==(p.reference),t.time_labels))
    design=M.design_review(t;reference=ref)
    states=Array{Float64}(undef,n,4,t.R,T);sigma=Array{Float64}(undef,n,4,t.R)
    for c in 1:4,i in 1:n
        s=M.coordinates(t,view(saved.chains[c].run.draws,i,:))
        states[i,c,:,:]=s.severity
        !t.static && (sigma[i,c,:]=s.sigma)
    end
    trajectory=NamedTuple[];count_integrated=0
    for row in original.trajectory
        j=only(findall(==(row.tick),t.time_ticks))
        weights=isnothing(row.rater) ? p.panel_weights : Float64.(t.rater_labels.==row.rater)
        can_integrate=!row.structurally_fixed && eligible(t,j,ref,weights,design.rated)
        if can_integrate && batches_supported
            mu=zeros(n,4);v=zeros(n,4);raw=zeros(n,4)
            for r in findall(>(0),weights)
                w=weights[r]
                mu .+= w.*((states[:,:,r,j-1].+states[:,:,r,j+1])./2 .-states[:,:,r,ref])
                v .+= w^2 .* sigma[:,:,r].^2 ./2
                raw .+= w.*(states[:,:,r,j].-states[:,:,r,ref])
            end
            summary=summarize(mu,sqrt.(v),raw;interval=p.interval)
            push!(trajectory,merge(row,(;summary,estimator=:conditional_gaussian_bridge,
                integration_status=:applied,diagnostic_passed=summary.diagnostic_passed,
                precision_passed=W.precision_ok(summary,p.precision))))
            count_integrated+=1
        else
            outside=!row.structurally_fixed && any(r->weights[r]>0 && !design.rated[r,j],1:t.R)
            push!(trajectory,merge(row,(;estimator=row.structurally_fixed ? :structural_zero : :joint_draws,
                integration_status=can_integrate && !batches_supported ? :insufficient_retained_batches :
                    outside ? :outside_isolated_bin_scope : :not_applicable)))
        end
    end
    focal=filter(x->!x.structurally_fixed,trajectory)
    precision_passed=all(x->x.precision_passed,focal)
    diagnostic_passed=all(x->x.diagnostic_passed,focal)
    # Raw parameter/contrast failures and sampler failures cannot be cured here.
    qualified=p.kind===:posterior && original.parameter_passed && original.sampler_passed &&
        precision_passed && diagnostic_passed
    R.seal((;schema=SCHEMA,kind=p.kind,posterior=p.kind===:posterior,adapter_sha256=R.digest(@__FILE__),
        context=R.context(),policy=POLICY,limitations=LIMITS,plan_hash=p.content_hash,
        original_report_hash=expected_original_hash,original_report=original,
        original_numerical_qualified=original.numerical_qualified,
        numerical_qualified=qualified,precision_passed,diagnostic_passed,
        statistical_acceptance=false,public_api=true,trajectory,count_integrated,
        locations=parentmodule(@__MODULE__)._location_summaries(saved),
        locations_adapter_sha256=R.digest(joinpath(@__DIR__,"comparison.jl")),
        new_fits=0,new_model_random_draws=0))
end

end
