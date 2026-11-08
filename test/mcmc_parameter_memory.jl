module MCMCParameterMemoryChecks
using BayesianMGMFRM, Test, Statistics
const B=BayesianMGMFRM
# Deliberately evaluate every lag as an independent reference for the exit rule.
function full_lag_ess(v)
    n,c,_=size(v);means=vec(mean(v[:,:,1];dims=1))
    W=mean(var(v[:,j,1]) for j in 1:c)
    rho=[sum(sum((v[i,j,1]-means[j])*(v[i+lag,j,1]-means[j])
        for i in 1:(n-lag))/(n-1) for j in 1:c)/(c*W) for lag in 1:(n-1)]
    positive=0.
    for lag in 1:2:length(rho)
        pair=lag==length(rho) ? rho[lag] : rho[lag]+rho[lag+1]
        pair>0 || break
        positive+=pair
    end
    clamp(n*c/max(1.,1+2positive),1.,Float64(n*c))
end
function lag_checks()
    @testset "Classical ESS retains the original positive-lag criterion" begin
        for n in (2,3,4,33,64,127),mode in (:oscillating,:persistent,:alternating)
            v=[mode===:oscillating ? sin(i+.3c) : mode===:persistent ? sin(.003i+.1c) : (-1.)^i+.01c
                for i in 1:n,c in 1:4,p in 1:1]
            @test B._rhat_and_ess(v,1).ess≈full_lag_ess(v) rtol=1e-12 atol=1e-12
        end
    end
end
function checks()
    @testset "Per-parameter diagnostics avoid unrelated chain copies" begin
        for n in (3,4,5,33), chains in (1,2,4), split in (false,true)
            values=[sin(i+.3c+.2p) for i in 1:n,c in 1:chains,p in 1:7]
            for p in (1,7)
                metric=B._mcmc_parameter_metrics(values,p;split_chains=split)
                one=B._mcmc_parameter_metrics(values[:,:,p:p],1;split_chains=split)
                @test isequal(metric,one)
                old=B._rhat_and_ess(split && chains>=2 && n>=4 ? B._split_chain_array(values) : values,p)
                @test isequal(metric.rhat,old.rhat) && isequal(metric.ess,old.ess)
            end
        end
        small=[sin(i+.3c) for i in 1:40,c in 1:4,p in 1:1]
        large=repeat(small;outer=(1,1,64))
        metric(v)=B._mcmc_parameter_metrics(v,1;split_chains=true)
        metric(small);metric(large)
        a=@allocated metric(small);b=@allocated metric(large)
        @test b<=a+4096
    end
end
end
