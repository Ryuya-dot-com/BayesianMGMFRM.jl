module PosteriorReliabilityChecks
using BayesianMGMFRM, Test, Statistics, LinearAlgebra, Serialization
import ..CommonPredictionRefitChecks, ..CommonPredictionKfoldChecks
const B = BayesianMGMFRM
const R = CommonPredictionRefitChecks
const K = CommonPredictionKfoldChecks
include("../examples/saved_posterior_reliability.jl")
components(x; w=ones(size(x, 2)), target=:absolute) = B._posterior_reliability_components(x, w, target)

function finite_checks()
    @testset "Finite posterior mixture identities and counterexamples" begin
        noise = [-1. -1; -1 1; 1 -1; 1 1]
        zero = components(noise)
        @test zero.reliability == 0
        @test zero.between == 0 && zero.within == 1
        @test components(noise; target=:centered).reliability == 0
        x = noise .+ [-1. 1.]
        @test components(x).reliability == 1/2
        @test components(x; target=:centered).reliability ≈ 2/3
        @test components(x; w=[1,3]).reliability ≈ 3/7
        @test components(x; w=[1,3], target=:centered).reliability ≈ 2/3
        base = repeat([-1. 1.], 4, 1)
        for shift in ([-.1,-.1,.1,.1], [-2.,-2,2,2])
            r = components(base .+ shift; target=:centered)
            @test r.reliability == 1 && r.within == 0
            @test B._posterior_reliability_mcse(r,2).status === :boundary_delta_unavailable
        end
        @test components(base .+ [-2.,-2,2,2]).reliability == .2
        @test ismissing(components(ones(4,2)).reliability)
        @test B._posterior_reliability_mcse(components(ones(4,2)),2).status === :zero_total_variance
        # Enumerate the complete discrete joint distribution independently of the implementation.
        x = [1. 2 4; 2 3 5; -2 4 8; 3 -1 1; 4 5 2; -1 3 7]
        w = [.2,.3,.5]
        for target in (:absolute,:centered)
            c = components(x; w,target)
            y = target === :centered ? x * (I - w * ones(3)') : x
            m = [sum(y[:,j])/6 for j in 1:3]
            mixture_mean = sum(w[j]*m[j] for j in 1:3)
            total = sum(w[j]*(y[s,j]-mixture_mean)^2/6 for s in 1:6,j in 1:3)
            within = sum(w[j]*(y[s,j]-m[j])^2/6 for s in 1:6,j in 1:3)
            @test c.total ≈ total
            @test c.within ≈ within
            @test c.reliability ≈ 1-within/total
            @test c.reliability ≈ components(x.+23;w,target).reliability
            @test c.reliability ≈ components(-3x;w,target).reliability
            @test c.reliability ≈ components(x[:,[3,1,2]];w=w[[3,1,2]],target).reliability
            @test c.reliability ≈ components(repeat(x;outer=(3,1));w,target).reliability
            @test c.reliability ≈ components(x;w=100w,target).reliability
            @test mean(c.influence) ≈ 0 atol=1e-14
            # Perturb probability of one posterior draw; compare the ratio's directional derivative.
            ratio = function (p)
                means = vec(p' * y)
                v = [sum(p.*(y[:,j].-means[j]).^2) for j in 1:3]
                b = sum(w.*(means.-sum(w.*means)).^2)
                return b/(b+sum(w.*v))
            end
            for s in 1:6
                direction = -ones(6)/6; direction[s] += 1
                h = 1e-6
                derivative = (ratio(ones(6)/6+h*direction)-ratio(ones(6)/6-h*direction))/(2h)
                @test c.influence[s] ≈ derivative atol=2e-10
            end
        end
        @test components(x;w,target=:centered).reliability ≈
            components(x .+ collect(1.:6);w,target=:centered).reliability
        for bad in ([1.], [1.,0,1], [1.,-1,1], [1.,NaN,1], [1.,Inf,1], [true,true,true])
            @test_throws ArgumentError components(x;w=bad)
        end
        @test_throws ArgumentError components(x;target=:unknown)
        @test_throws ArgumentError components(x[1:1,:])
        @test_throws ArgumentError components(x[:,1:1])
        @test_throws ArgumentError components(fill(Inf,4,2))
        @test_throws ArgumentError components([-1e308 1e308; 1e308 -1e308])
        @test_throws ArgumentError components(x;w=[1e-300,1e300,1.])
        # Numerical MCSE agrees with the established chain-aware estimator of the analytic influence.
        long = [j + sin(s+3j) + cos(s*j/7) for s in 1:80, j in 1:3]
        c = components(long)
        mcse = B._posterior_reliability_mcse(c,2)
        native = only(posterior_mcse(reshape(c.influence,:,1);chains=2,parameter_names=["influence"]))
        @test mcse.status === :available
        @test mcse.value == native.mean_mcse
        @test B._posterior_reliability_mcse(c,1).status === :insufficient_chains
        @test B._posterior_reliability_mcse(components(long[1:8,:]),2).status === :insufficient_draws
    end
end

function checks(output)
    finite_checks()
    facet_checks()
    @testset "Saved reliability: eight fit types, dimensions, inputs and replay" begin
        cases = K.fixture_cases()
        @test length(unique(typeof(c.fit) for c in cases)) == 8
        for (i,case) in enumerate(cases)
            fit = case.fit
            catalog = B.recovery_quantities(fit)
            people = filter(r -> r.block === :person && !r.fixed, catalog.rows)
            parameters = [r.parameter for r in people if r.dimension == first(people).dimension]
            @test length(parameters) >= 2
            before = R.bytes(fit)
            outputs = []
            for target in (:absolute,:centered)
                result = B.posterior_reliability(fit;parameters,target)
                @test 0 <= result.reliability <= 1
                @test result.total_variance ≈ result.between_variance+result.within_variance
                @test result.n_levels == length(parameters)
                @test [r.parameter for r in result.rows] == parameters
                @test all(r -> r.dimension == first(people).dimension, result.rows)
                @test result.model_contract == catalog.model_contract
                @test result.source_sample_hash == catalog.source_sample_hash
                @test result.sampling_warning == B._prediction_sampling_warning(catalog.sampling_quality)
                @test result.status === :warning # Short deterministic fixtures are never scientific evidence.
                @test result.interval === :not_computed && result.strata === :not_computed
                @test result.scope === :finite_cohort_posterior_functional_not_design_reliability
                @test B._prediction_check_seal(result,"bayesianmgmfrm.posterior_reliability.v1") === nothing
                @test sum(r.weight for r in result.rows) ≈ 1
                push!(outputs,result)
            end
            @test outputs[2].within_variance <= outputs[1].within_variance + 1e-12
            @test R.bytes(fit) == before
            path = joinpath(output,"fit-$i.jls"); save_fit_cache(path,fit)
            for result in outputs
                @test isequal(saved_posterior_reliability(path;parameters,target=result.target),result)
            end
            serialize(joinpath(output,"case-$i.jls"),(;path,parameters,outputs))
            # Facet/dimension mixtures and structural anchors must not produce reassuring coefficients.
            other = findfirst(r -> r.block !== :person || r.dimension != first(people).dimension,catalog.rows)
            @test_throws ArgumentError B.posterior_reliability(fit;parameters=[first(parameters),catalog.rows[other].parameter],target=:absolute)
            fixed = filter(r -> r.fixed,catalog.rows)
            if !isempty(fixed)
                @test_throws ArgumentError B.posterior_reliability(fit;parameters=[first(parameters),first(fixed).parameter],target=:absolute)
            end
        end
        fit = cases[1].fit
        parameters = [r.parameter for r in B.recovery_quantities(fit).rows if r.block === :person]
        for bad in (String[],parameters[1:1],fill(first(parameters),2),[first(parameters),"unknown"],[:one,:two],"person")
            @test_throws ArgumentError B.posterior_reliability(fit;parameters=bad,target=:absolute)
        end
        @test_throws UndefKeywordError B.posterior_reliability(fit;parameters)
        @test_throws ArgumentError B.posterior_reliability(fit;parameters,target=:rank)
        @test_throws ArgumentError B.posterior_reliability(fit;parameters,target=:absolute,weights=2.)
        @test_throws ArgumentError B.posterior_reliability(fit;parameters,target=:absolute,weights=[1.,0.])
        bad = deepcopy(fit); reverse!(bad.chain_ids)
        @test_throws ArgumentError B.posterior_reliability(bad;parameters,target=:absolute)
        legacy = R.prediction_fixed_fixture(:legacy).fit
        @test_throws ArgumentError B.posterior_reliability(legacy;parameters,target=:absolute)
        bad = deepcopy(cases[6].fit);bad.record.run.draws[1,1]+=1
        @test_throws ArgumentError B.posterior_reliability(bad;parameters,target=:absolute)
        # Legacy numerical meaning is preserved and now has a visible migration warning.
        @test_logs (:warn,r"legacy screen requiring methodological review") B.separation_reliability_summary(fit;facets=:person)
        old = only(B.separation_reliability_summary(fit;facets=:person))
        @test old.method === :posterior_empirical_reliability
        @test :posterior_reliability ∉ names(B)
        @test B._root_api_contract() !== nothing
    end
end

function facet_checks()
    @testset "Item/rater cohorts, unequal weights and fixed anchors" begin
        for case in K.fixture_cases(), block in (:item,:rater)
            fit = case.fit
            catalog = B.recovery_quantities(fit)
            rows = filter(r -> r.block === block,catalog.rows)
            estimated = filter(r -> !r.fixed,rows)
            if length(estimated) >= 2
                parameters = [r.parameter for r in estimated]
                weights = collect(1:length(parameters))
                result = B.posterior_reliability(fit;parameters,target=:centered,weights)
                @test all(r -> r.block === block,result.rows)
                @test [r.weight for r in result.rows] ≈ weights/sum(weights)
                @test sum(r.weight*r.posterior_mean for r in result.rows) ≈ 0 atol=1e-12
                @test sum(r.weight*r.posterior_variance for r in result.rows) ≈ result.within_variance
                @test 0 <= result.reliability <= 1
                raw = B._recovery_context(fit).coordinates
                values = hcat([only(filter(r -> r.parameter == p,raw)).values for p in parameters]...)
                A = Matrix{Float64}(I,length(parameters),length(parameters)) .- ones(length(parameters))*(weights/sum(weights))'
                @test result.within_variance ≈ sum((weights/sum(weights)).*diag(A*cov(values;corrected=false)*A')) atol=1e-12
            end
            if any(r -> r.fixed,rows) && length(rows) >= 2
                parameters = [r.parameter for r in rows]
                @test_throws ArgumentError B.posterior_reliability(fit;parameters,target=:absolute)
            end
        end
    end
end
end
