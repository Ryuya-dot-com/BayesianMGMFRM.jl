module ThreeIndicatorPriorChecks
using BayesianMGMFRM, Test, LinearAlgebra
using BayesianMGMFRM: JSON3
const B=BayesianMGMFRM
const T=B.Experimental.ThreeIndicator
const M=T.W.M
include("../examples/three_indicator_fit.jl")

# Closed-form normalized ratio, independently of the target's Normal factors.
function delta(t,q,name)
    name===:reference && return zero(eltype(q))
    m=[-2+4(k-1)/7 for k in 1:8];mu=t.bases.step'*m
    steps=reshape(q[t.blocks[:step_q]],7,2)
    value=sum(dot(mu,steps[:,a])-.5sum(abs2,mu) for a in 1:2)
    if name===:combined
        a=q[t.blocks[:intercept]][1:2]
        b=reshape(q[t.blocks[:beta]],t.data.P,3)[:,1:2]
        value+=(2+2t.data.P)*log(2)-3/8*sum(abs2,a)-3/2*sum(abs2,b)
    end
    value
end

function checks()
    @testset "Explicit three-outcome priors: normalized target and provenance" begin
        controls=(;ndraws=32,warmup=2,step_size=.03,target_accept=.9,max_depth=3,
            metric=:diagonal,ad_backend=:ForwardDiff)
        base=prepare_three_indicator_example(;controls,chain_seeds=collect(41:44))
        input=JSON3.read(base.input_json)
        ref=M.Target(input;prior=:reference)
        @test base.prior==M.REFERENCE_PRIOR
        @test M.initial(ref)[ref.blocks[:step_q]]==zeros(14)
        @test T.contract().priors==(:reference,:steps,:combined)
        for bad in (:current,:other,"steps",true,merge(M.STEPS_PRIOR,(;ordinal_beta_sd=.5)),
                merge(M.COMBINED_PRIOR,(;beta_sd=.5)),merge(M.REFERENCE_PRIOR,(;lkj_eta=3.)))
            @test_throws ArgumentError T.prepare(input;prior=bad,controls,chain_seeds=collect(41:44),focal=base.focal)
        end
        for name in (:reference,:steps,:combined)
            p=T.prepare(input;prior=name,controls,chain_seeds=collect(41:44),focal=base.focal)
            t=T.W.check_plan(p);spec=T.report(p).prior
            @test spec==M.prior_record(p.prior) && spec.name===name
            @test spec.intercept_sd[3]==2 && spec.beta_sd[3]==1
            @test spec.cohort_sd==1 && spec.sd_scale==(1.,1.,1.,.5,.5,.5)
            @test spec.slope_log_sd==.3 && spec.step_sd_scale==.5 && !spec.step_ordered
            @test maximum(abs,M.reconstruct(t,M.initial(t)).step.-collect(spec.step_mean))<1e-14
            for q in base.initial_points
                a=M.components(t,q);b=M.components(ref,q)
                @test a.likelihood==b.likelihood
                @test all(a[k]==b[k] for k in (:scales,:correlations,:scale_jacobian,:correlation_jacobian))
                @test isapprox(M.L.logdensity(t,q)-M.L.logdensity(ref,q),delta(ref,q,name);atol=1e-9,rtol=0)
                difference=B.ForwardDiff.gradient(v->M.L.logdensity(t,v),q)-
                    B.ForwardDiff.gradient(v->M.L.logdensity(ref,v),q)
                @test maximum(abs,difference-B.ForwardDiff.gradient(v->delta(ref,v,name),q))<1e-10
                @test M.category_logprobs(t,q)==M.category_logprobs(ref,q)
            end
            if name!==:reference
                @test_throws ArgumentError M.stan_data(t)
                unordered=collect(spec.step_mean);unordered[4],unordered[5]=unordered[5],unordered[4]
                q=M.initial(t);q[t.blocks[:step_q]]=repeat(t.bases.step'*unordered,2)
                @test any(diff(M.reconstruct(t,q).step[:,1]).<0)
                @test isfinite(M.L.logdensity(t,q))
            else
                @test M.stan_data(t).intercept_sd==2
            end
            record=JSON3.read(JSON3.write(spec))
            @test T._check_prior_record(record)==record
            for change in (x->delete!(x,"name"),x->(x["name"]="unknown"),
                    x->(x["intercept_sd"][3]=1.),x->(x["step_mean"][1]+=.1),
                    x->(x["beta_sd"][1]=true),x->(x["step_ordered"]=0),
                    x->(x["extra"]=1))
                wrong=JSON3.read(JSON3.write(spec),Dict{String,Any});change(wrong)
                @test_throws ArgumentError T._check_prior_record(JSON3.read(JSON3.write(wrong)))
            end
        end
    end
end

function report_checks(fixture)
    @testset "Artificial prior-bearing report parsing and byte preservation" begin
        for name in (:reference,:steps,:combined), producer in (T.PACKAGE_PRODUCER,T.HARD_DEPENDENCY_PRODUCER)
            x=fixture()
            x["context"]["sources"][1]["sha256"]=producer[2]
            x["context"]["sources"][3]["sha256"]=producer[3]
            x["prior"]=JSON3.read(JSON3.write(M.prior_record(name)),Dict{String,Any})
            text=JSON3.write(x);saved=T.SavedReport(text,T._digest(text),nothing,nothing)
            r=T.report(saved)
            @test r.prior==M.prior_record(name) && r.prior_provenance===:recorded
            @test !any(contains("older report"),r.warnings)
            for change in (y->delete!(y,"prior"),y->(y["prior"]["name"]="unknown"),
                    y->(y["prior"]["step_mean"][1]+=.1),
                    y->(y["context"]["sources"][3]["sha256"]=T.CONTEXT_PRODUCER[3]))
                wrong=deepcopy(x);change(wrong);s=JSON3.write(wrong)
                @test_throws ArgumentError T.SavedReport(s,T._digest(s),nothing,nothing)
            end
            mktempdir() do dir
                receipt=T.save_report(joinpath(dir,"report.json"),saved)
                restored=T.load_report(receipt.path;expected_sha256=receipt.sha256)
                @test restored.source_json==text
                @test T.report(restored).prior==r.prior
            end
        end
        text=JSON3.write(fixture());saved=T.SavedReport(text,T._digest(text),nothing,nothing)
        @test T.report(saved).prior==M.prior_record(:reference)
        @test T.report(saved).prior_provenance===:producer_reference
    end
end
end
