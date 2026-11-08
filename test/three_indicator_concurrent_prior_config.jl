module ThreeIndicatorConcurrentPriorConfigChecks
using BayesianMGMFRM,Test,JSON3,Random,LinearAlgebra,Statistics
import ..ThreeIndicatorConcurrentChecks as Fixtures
const B=BayesianMGMFRM
const Normal=B.Distributions.Normal
const logpdf=B.Distributions.logpdf
const T=B.Experimental.ThreeIndicator
const C=T.Concurrent
const F=T.ConcurrentWorkflow
const P=T.ConcurrentPriorPredictive
prior()=T.ConcurrentPrior(:steps;sd_scale=(.8,1.2,.6,.4,.7,.9),step_sd_scale=.35,
    slope_log_sd=.2,intercept_sd=(1.4,1.6,2.2),cohort_sd=.75,beta_sd=(.6,.8,1.1),
    lkj_eta=1.3,step_mean=(-1.6,-1.1,-.6,-.2,.2,.6,1.1,1.6),step_coordinate_sd=.7,
    pair_sd_scale=.25,pair_lkj_eta=4.)
input()=T.ConcurrentInput(Fixtures.fixture();source_sha256="a"^64)
function chart_checks()
    @testset "Custom prior coordinate transformation" begin
        t=getdesign(input();prior=prior(),interaction=:full)
        q=initial_params(t)+.075sin.(.17*(1:t.size))
        p=prepare_fit(t;ndraws=10,warmup=10,seed=42,initial=q,parameterization=:pair_132)
        k=F.sampling_target(p,t);v=p.record.initial
        @test C.L.logdensity(k,v)≈logposterior(t,q) atol=1e-10
        @test T.ConcurrentCoordinates.convert_coordinates(k,v)≈q atol=1e-14
        value,g=C.L.logdensity_and_gradient(k,v)
        ad=B.ForwardDiff.gradient(x->C.L.logdensity(k,x),v)
        @test g≈ad atol=2e-8 rtol=2e-9
        @test contract(F.check_plan(p))==contract(t)
    end
end
function checks()
    chart_checks()
    @testset "Explicit concurrent numerical priors" begin
        p=prior();t=getdesign(input();prior=p,interaction=:full)
        @test contract(t).prior.name===:custom
        @test contract(t).pair_prior==(;sd_scale=.25,lkj_eta=4.)
        @test C.prior_record(T.ConcurrentPrior(:steps)).name===:steps
        for options in ((;bad=1),(;pair_sd_scale=true),(;pair_sd_scale=0.),(;lkj_eta=Inf),
            (;step_coordinate_sd=-1.),(;pair_lkj_eta=NaN),(;sd_scale=[1.,2.]),
            (;intercept_sd=1.),(;beta_sd=(1.,false,1.)),(;step_mean=ones(8)),
            (;step_mean=[0.,0.]))
            @test_throws ArgumentError T.ConcurrentPrior(:steps;options...)
        end
        @test_throws ArgumentError T.ConcurrentPrior(:unknown)
        x=ones(6);owned=T.ConcurrentPrior(:steps;sd_scale=x);x[1]=9
        @test owned.sd_scale[1]==1
        @test_throws ArgumentError C.M.resolve_prior(p) # preliminary scope stays separate
        for preset in (:reference,:steps,:combined),interaction in (:none,:diagonal,:full)
            old=getdesign(input();prior=preset,interaction)
            explicit=getdesign(input();prior=T.ConcurrentPrior(preset),interaction)
            q=initial_params(old)+.05sin.(1:old.size)
            @test initial_params(old)==initial_params(explicit)
            @test logdensity_and_gradient(old,q)==logdensity_and_gradient(explicit,q)
            @test P.parameter_draw(MersenneTwister(10),old)==P.parameter_draw(MersenneTwister(10),explicit)
        end
        for interaction in (:none,:diagonal,:full)
            target=getdesign(input();prior=p,interaction)
            q=initial_params(target)+.065sin.(.3*(1:target.size))
            q[target.blocks[:correlation]].+=.35
            q[target.blocks[:pair_correlation]].-=.45
            v,g=logdensity_and_gradient(target,q)
            fd=B.ForwardDiff.gradient(x->C.L.logdensity(target,x),q)
            @test v≈C.L.logdensity(target,q) rtol=1e-12
            @test g≈fd atol=2e-8 rtol=2e-9
            # Independent change-of-prior calculation at one physical covariance/step point.
            base=getdesign(input();prior=:steps,interaction)
            z=C.reconstruct(target,q);z0=C.reconstruct(base,q)
            half(x,s)=sum(logpdf.(Normal(0,s),x))+length(x)*log(2)
            lkj3(v,e)=sum(log(1-tanh(v[k])^2)*(e+(3-j-1)/2) -
                B.SpecialFunctions.logbeta(.5,e+(3-j-1)/2) for (k,j) in enumerate((1,1,2)))
            expected=sum(half(z.f.sd[:,b],p.sd_scale[b])-half(z.f.sd[:,b],base.prior.sd_scale[b]) for b in 1:6)
            expected+=half(z.f.step_sd,p.step_sd_scale)-half(z.f.step_sd,base.prior.step_sd_scale)
            for b in 0:5
                vv=q[target.blocks[:correlation]][3b+1:3b+3]
                expected+=lkj3(vv,p.lkj_eta)-lkj3(vv,2.)
            end
            if interaction!==:none
                expected+=half(z.f.pair_sd,p.pair_sd_scale)-half(z.f.pair_sd,.5)
            end
            if interaction===:full
                vv=q[target.blocks[:pair_correlation]]
                expected+=lkj3(vv,p.pair_lkj_eta)-lkj3(vv,2.)
            end
            @test C.hyper_prior(target,q[target.hyper_indices])-C.hyper_prior(base,q[base.hyper_indices])≈expected atol=1e-10
            mu=target.bases.step'*collect(p.step_mean);m0=base.bases.step'*collect(base.prior.step_mean)
            step=reshape(q[target.blocks[:step_q]],7,2)
            ordinary=sum(logpdf(Normal(mu[k],p.step_coordinate_sd),step[k,a])-logpdf(Normal(m0[k],1),step[k,a]) for k in 1:7,a in 1:2)
            beta=reshape(q[target.blocks[:beta]],24,3)
            ordinary+=sum(logpdf(Normal(0,p.beta_sd[a]),beta[k,a])-logpdf(Normal(0,1),beta[k,a]) for k in 1:24,a in 1:3)
            @test C.ordinary_prior(target,q)-C.ordinary_prior(base,q)≈ordinary atol=1e-10
            if interaction===:full
                data=stan_data(target)
                @test data["pair_lkj_eta"]==4. && data["step_coordinate_sd"]==.7
            else
                @test_throws ArgumentError stan_data(target)
            end
            plan=prepare_fit(target;ndraws=10,warmup=10,chains=2,seed=41,max_depth=2)
            rebuilt=F.check_plan(plan)
            @test contract(rebuilt)==contract(target)
            @test logdensity_and_gradient(rebuilt,q)==(v,g)
            @test F.model(rebuilt)==F.model(target)
        end
        # Independent theoretical moments, with a predeclared 6-SE tolerance.
        rng=MersenneTwister(51);draws=[P.parameter_draw(rng,t) for _ in 1:4096]
        step=hcat([q[t.blocks[:step_q]][1:7] for q in draws]...)
        mu=t.bases.step'*collect(p.step_mean)
        @test all(abs.(vec(mean(step;dims=2))-mu).<6p.step_coordinate_sd/sqrt(4096))
        @test all(abs.(vec(var(step;dims=2)).-p.step_coordinate_sd^2).<6p.step_coordinate_sd^2*sqrt(2/4095))
        for (block,scale) in ((:log_sd,p.sd_scale[1]),(:log_step_sd,p.step_sd_scale),(:pair_log_sd,p.pair_sd_scale))
            x=[exp(q[first(t.blocks[block])]) for q in draws]
            @test abs(mean(x)-scale*sqrt(2/pi))<6scale*sqrt((1-2/pi)/4096)
        end
        for (block,eta) in ((:correlation,p.lkj_eta),(:pair_correlation,p.pair_lkj_eta))
            for (k,j) in enumerate((1,1,2))
                a=eta+(3-j-1)/2;x=[tanh(q[t.blocks[block]][k])^2 for q in draws]
                expectation=1/(2a+1);variance=3/((2a+1)*(2a+3))-expectation^2
                @test abs(mean(x)-expectation)<6sqrt(variance/4096)
            end
        end
        # Round trips retain full settings; a legacy model specification remains readable.
        mktempdir() do dir
            receipt=save_report(joinpath(dir,"model.json"),t)
            restored=load_report(receipt.path;expected_sha256=receipt.sha256)
            @test contract(restored)==contract(t)
            @test P.parameter_draw(MersenneTwister(13),restored)==P.parameter_draw(MersenneTwister(13),t)
            r=prior_predictive_check(t;ndraws=4,seed=72)
            rr=save_report(joinpath(dir,"prior.json"),r;return_receipt=true)
            @test load_report(rr.path;expected_sha256=rr.sha256)==r
            @test r.model.prior.step_coordinate_sd==.7 && r.model.pair_prior.lkj_eta==4.
            record=JSON3.read(JSON3.write(C.prior_spec(p)),Dict{String,Any})
            delete!(record["parameters"],"pair_lkj_eta")
            @test_throws ArgumentError C.resolve_prior(JSON3.read(JSON3.write(record)))
            legacy=(;schema="bayesianmgmfrm.concurrent_three_indicator_model.v1",rows=t.input.rows,
                source_sha256=t.input.source_sha256,prior=:steps,interaction=:full)
            path=joinpath(dir,"legacy.json");write(path,JSON3.write(legacy))
            @test contract(load_report(path;expected_sha256=bytes2hex(C.sha256(read(path))))).prior.name===:steps
        end
    end
end
end
