module ThreeIndicatorConcurrentAssociationChecks
using BayesianMGMFRM,Test,Random,LinearAlgebra
import ..ThreeIndicatorConcurrentChecks as Fixtures
const C=BayesianMGMFRM.Experimental.ThreeIndicator.Concurrent
function checks()
    input=C.Input(Fixtures.fixture();source_sha256="a"^64)
    @testset "Marginal-preserving concurrent association contract" begin
        for interaction in (:none,:diagonal,:full)
            t=getdesign(input;prior=:steps,interaction,association=:plackett,association_log_sd=1.)
            q=vcat(initial_params(t.base)+.05sin.(1:t.base.size),0.)
            v,g=logdensity_and_gradient(t,q);v0,g0=logdensity_and_gradient(t.base,q[1:end-1])
            @test v-v0≈-log(2pi)/2 atol=1e-9
            @test g[1:end-1]≈g0 atol=2e-8 rtol=0
            @test abs(g[end])>1e-3
            @test length(parameter_names(t))==length(q)==design_summary(t).free_parameters
            @test coordinates(t,q).ac_log_psi==0
            @test contract(t).association.measure===:log_psi
            @test contract(t).fitting && contract(t).posterior_reporting && contract(t).prior_predictive
            if interaction===:full
                @test stan_data(t)["association_log_sd"]==1.
            else
                @test_throws ArgumentError stan_data(t)
            end
            mktempdir() do dir
                saved=save_report(joinpath(dir,"model.json"),t)
                restored=load_report(saved.path;expected_sha256=saved.sha256)
                @test contract(restored)==contract(t)
                @test logdensity_and_gradient(restored,q)==(v,g)
                @test_throws ArgumentError load_report(saved.path;expected_sha256="0"^64)
            end
            plan=prepare_fit(t;ndraws=10,warmup=10,seed=1)
            @test contract(C.B.Experimental.ThreeIndicator.ConcurrentWorkflow.check_plan(plan))==contract(t)
            @test event_probabilities(t,q;rows=[1]).probability_scope=="outcome_marginals"
            @test length(contrast(t,q).comparisons)==8
            reference=event_probabilities(t,q;panel=:eng_reference)
            baseline=event_probabilities(t.base,q[1:end-1];panel=:eng_reference)
            @test reference.recordings==baseline.recordings && reference.speakers==baseline.speakers
            @test_throws ArgumentError predictive_check(t;ndraws=1,seed=1)
            @test_throws ArgumentError prior_predictive_check(t;ndraws=10,seed=true)
        end
        for bad in (nothing,true,0.,-1.,Inf,NaN)
            @test_throws ArgumentError getdesign(input;prior=:steps,association=:plackett,association_log_sd=bad)
        end
        @test_throws ArgumentError getdesign(input;prior=:steps,association=:unknown)
        @test_throws ArgumentError getdesign(input;prior=:steps,association_log_sd=1.)
    end
end

const T=BayesianMGMFRM.Experimental.ThreeIndicator
const P=T.ConcurrentPredictive
const F=T.ConcurrentWorkflow
const K=T.ConcurrentCoordinates
const R=T.ConcurrentReports
const PP=T.ConcurrentPriorPredictive
function lifecycle_checks()
    input=C.Input(Fixtures.fixture();source_sha256="a"^64)
    t=getdesign(input;prior=:steps,interaction=:full,association=:plackett,association_log_sd=2.)
    @testset "Association coordinates, prior draws and process precision" begin
        q=vcat(initial_params(t.base)+.07sin.(.17*(1:t.base.size)),1.2)
        p=prepare_fit(t;ndraws=10,warmup=10,chains=2,seed=42,initial=q,parameterization=:pair_132)
        kernel=F.sampling_target(p,t);v=p.record.initial
        @test v[end]==q[end]
        @test K.convert_coordinates(kernel,v)≈q atol=1e-14
        value,g=C.L.logdensity_and_gradient(kernel,v)
        @test value≈logposterior(t,q) atol=1e-9
        # Differentiate only the exact chart map; avoid cancellation in full-density differences.
        native_gradient=logdensity_and_gradient(t,q)[2]
        ad=BayesianMGMFRM.ForwardDiff.gradient(x->dot(native_gradient,K.convert_coordinates(kernel,x)),v)
        @test maximum(abs.(ad-g)./max.(1.,abs.(ad),abs.(g)))<1e-7
        @test last(F.raw_names(t;parameterization=:pair_132))=="ac_log_psi"
        @test last(F.model_values(t,q).values)==q[end]
        @test last(F.model_values(t,q).names)=="ac_log_psi"
        @test fit_report(p).raw_draw_bytes==8*10*2*length(q)
        for seed in (1,17,45)
            a=MersenneTwister(seed);b=MersenneTwister(seed)
            draw=PP.parameter_draw(a,t);base=PP.parameter_draw(b,t.base)
            @test draw[1:end-1]==base
            @test draw[end]==2randn(b)
        end
        # Force different high-precision branches concurrently, sharing one lock.
        before=precision(BigFloat);ell=[-40.,6.,40.,-10.]
        evaluate(e)=begin
            a=collect(-4.:4.);b=reverse(a)
            x=C.Plackett.cell(a,b,2,8,e);w=C.PlackettTable.Workspace(9,9)
            bits=C.PlackettTable.probabilities!(w,a,b,e)
            (;lp=x.lp,ga=x.ga,gb=x.gb,ge=x.ge,table=copy(w.logp),bits)
        end
        expected=evaluate.(ell)
        tasks=[Threads.@spawn evaluate(e) for e in ell]
        @test fetch.(tasks)==expected
        @test precision(BigFloat)==before
        @test all(r->r.bits>53,expected)
    end
    @testset "Deterministic joint generator and conditional count moments" begin
        q=vcat(initial_params(t.base)+.05sin.(1:t.base.size),2.)
        design=P.layout(t);N=t.base.data.N
        uniforms=[(mod(31n+17a,997)+.5)/997 for n in 1:N,a in 1:3]
        counts=zeros(UInt16,202);mu=zeros(202);variance=zeros(202)
        P.state!(counts,mu,variance,t,q,design.panel,MersenneTwister(1);uniforms)
        z=C.reconstruct(t,q);expected=zeros(Int,202);em=zeros(202);ev=zeros(202)
        maximum_log_error=0.
        setprecision(BigFloat,256) do
            a=zeros(9);b=zeros(9);buffer=zeros(9);marginals=R.blank();w=C.PlackettTable.Workspace(9,9)
            for n in 1:N
                C.logits!(a,t,z,n,1);C.logits!(b,t,z,n,2)
                pa=C.Plackett.softmax(BigFloat.(a));pb=C.Plackett.softmax(BigFloat.(b))
                u=vcat(BigFloat(0),cumsum(pa));v=vcat(BigFloat(0),cumsum(pb));u[end]=1;v[end]=1
                H=[C.Plackett.corner(x,y,BigFloat(q[end]))[1] for x in u,y in v]
                ac=Float64.([H[i+1,j+1]-H[i,j+1]-H[i+1,j]+H[i,j] for i in 1:9,j in 1:9])
                C.PlackettTable.probabilities!(w,a,b,q[end])
                maximum_log_error=max(maximum_log_error,maximum(abs.(log.(ac)-w.logp)))
                R.probabilities!(marginals,buffer,t,z,n)
                y1=searchsortedlast(cumsum(Float64.(pa)),uniforms[n,1])+1
                y2=searchsortedlast(cumsum(ac[y1,:]/Float64(pa[y1])),uniforms[n,2])+1
                y3=searchsortedlast(cumsum(marginals[3]),uniforms[n,3])+1
                g=design.panel[n]
                for (a,y) in enumerate((y1,y2,y3));expected[P.index(g,a,y)]+=1;end
                expected[P.joint(g,y1,y2)]+=1
                for a in 1:3,k in eachindex(marginals[a])
                    j=P.index(g,a,k);prob=marginals[a][k];em[j]+=prob;ev[j]+=prob*(1-prob)
                end
                for a in 1:9,c in 1:9
                    j=P.joint(g,a,c);prob=ac[a,c];em[j]+=prob;ev[j]+=prob*(1-prob)
                end
            end
        end
        @test maximum_log_error<2e-8
        @test counts==expected
        @test maximum(abs.(mu-em))<1e-9
        @test maximum(abs.(variance-ev))<1e-9
        @test all(isfinite,P.maxima(design.observed,counts,mu,variance))
        # Dependence changes joint expectations, retaining the same conditional margins.
        c0=similar(counts);m0=similar(mu);v0=similar(variance)
        P.state!(c0,m0,v0,t.base,q[1:end-1],design.panel,MersenneTwister(1);uniforms)
        @test mu[1:20]==m0[1:20] && mu[102:121]==m0[102:121]
        @test maximum(abs.(mu-m0))>.1
        q[end]=0.;P.state!(counts,mu,variance,t,q,design.panel,MersenneTwister(1);uniforms)
        @test counts==c0
        @test maximum(abs.(mu-m0))<1e-9
        @test maximum(abs.(variance-v0))<1e-9
        @test_throws ArgumentError P.state!(counts,mu,variance,t,q,design.panel,MersenneTwister(1);uniforms=fill(-.1,N,3))
    end
end
end
