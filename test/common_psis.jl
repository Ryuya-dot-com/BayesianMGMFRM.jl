module CommonPSISChecks
using BayesianMGMFRM, Test, JSON3, Serialization
const B=BayesianMGMFRM
include("common_prediction_fixtures.jl")
vec(x) = x isa AbstractVector ? collect(x) : [x]

function reference_check(directory, name, r; supplied=false)
    S,N=Int(r.rows),Int(r.columns)
    ll=open(io->read!(io,zeros(S,N)),joinpath(directory,name*"-loglik.bin"))
    weights=open(io->read!(io,zeros(S,N)),joinpath(directory,name*"-weights.bin"))
    ids=repeat(1:Int(r.chains);inner=div(S,Int(r.chains)))
    stat=supplied ? psis_loo(ll;r_eff=Float64.(vec(r.r_eff))) : psis_loo(ll;chain_ids=ids)
    @test stat.estimator === :psis_zhang_stephens
    # R posterior 1.7.0 treats the empty initial-positive sequence differently
    # for the exact period-two probe. Both tail fits are explicitly unusable.
    boundary = name == "deterministic" ? [5] : Int[]
    checked = setdiff(1:N,boundary)
    @test stat.pointwise.r_eff[checked] ≈ Float64.(vec(r.r_eff))[checked] rtol=1e-6
    if !isempty(boundary)
        @test stat.pointwise.r_eff[5] ≈ log10(S)
        @test r.r_eff[5] == .5
        @test stat.pointwise.pareto_k[5] == Inf
    end
    @test stat.pointwise.elpd_loo ≈ Float64.(vec(r.elpd)) atol=1e-9 rtol=0
    @test stat.pointwise.p_loo ≈ Float64.(vec(r.p_loo)) atol=1e-9 rtol=0
    @test stat.pointwise.effective_sample_size[checked] ≈ Float64.(vec(r.n_eff))[checked] rtol=1e-7
    @test stat.pointwise.tail_draws[checked] == Int.(vec(r.tail_len))[checked]
    for j in 1:N
        if r.infinite_k[j]
            @test stat.pointwise.pareto_k[j] == Inf
        else
            @test stat.pointwise.pareto_k[j] ≈ Float64(r.pareto_k[j]) atol=1e-8 rtol=0
        end
        ps=B.Experimental.StarAssociation._psis_smooth_log_ratios(-ll[:,j];r_eff=stat.pointwise.r_eff[j])
        @test ps.norm_log_weights ≈ weights[:,j] atol=1e-8 rtol=0
    end
    @test stat.relative_efficiency_unavailable == Int.(vec(r.fallback))
    return stat
end

@testset "Common PSIS: independent R arithmetic, tail failures and efficiency" begin
    dir=joinpath(@__DIR__,"fixtures/common_psis")
    r=JSON3.read(read(joinpath(dir,"reference.json"),String))
    reference_check(dir,"deterministic",r.cases.deterministic)
    reference_check(dir,"supplied",r.cases.supplied;supplied=true)
    L=[-1-.1sin(i*j) for i in 1:40,j in 1:3]
    @test :relative_efficiency_not_supplied in psis_loo(L).warnings
    @test psis_loo(L;r_eff=1).relative_efficiency===:supplied
    @test_throws ArgumentError psis_loo(L;r_eff=0)
    @test_throws ArgumentError psis_loo(L;r_eff=[1,2])
    @test_throws ArgumentError psis_loo(L;r_eff=NaN)
    @test_throws ArgumentError psis_loo(L;chain_ids=repeat(1:2,20))
    @test_throws ArgumentError psis_loo(L;chain_ids=ones(Int,39))
    @test_throws ArgumentError psis_loo(L;chain_ids=ones(Int,40),r_eff=1)
    @test_throws ArgumentError psis_loo(L;tail_fraction=.3)
    @test_throws ArgumentError psis_loo(L;min_tail_draws=4)
    @test_throws ArgumentError psis_loo(L[1:4,:];r_eff=1)
    @test_throws ArgumentError psis_loo(fill(NaN,10,2);r_eff=1)
    constant=psis_loo(fill(-2.,40,3);chain_ids=repeat(1:2;inner=20))
    @test constant.pointwise.elpd_loo ≈ fill(-2.,3)
    @test all(isinf,constant.pointwise.pareto_k)
    @test :high_pareto_k in constant.warnings
    @test :relative_efficiency_unavailable in constant.warnings
    @test length(loo_diagnostics(fill(-2.,40,3);psis_smoothing=true,r_eff=1,only_flagged=true))==3
end

@testset "Same standard estimator across fitted, named criteria and comparisons" begin
    record=F.synthetic_record(F.target())
    fits=Any[reporting_fit(k;ndraws=20,chains=2) for k in (:mfrm,:gmfrm,:mgmfrm)]
    append!(fits,[normalized_fixture(record),B.Experimental.CorrelatedMGMFRMFit(record;expected_identity=record.target_identity)])
    append!(fits,[prediction_fixed_fixture(k).fit for k in (:fixed,:correlated,:exchangeable,:exchangeable_correlated)])
    for fit in fits
        n=B.PredictionObservationAdapter._fit_data(fit).n
        kw=(;dataset_id="fixture",observation_ids=["r$i" for i in 1:n])
        p=B.prediction_observations(fit;kw...,include_probabilities=false)
        expected=psis_loo(p.pointwise_loglikelihood;chain_ids=p.chain_ids)
        named=criteria(fit;kw...,criteria=(:waic,:psis_loo,:hill_smoothed_loo,:raw_loo))
        @test isequal(criteria(fit).psis_loo,expected)
        @test isequal(named.scores.psis_loo,expected)
        @test isequal(named.scores.hill_smoothed_loo,B._hill_smoothed_loo(p.pointwise_loglikelihood))
        @test isequal(named.scores.raw_loo,loo(p.pointwise_loglikelihood))
        @test isequal(named.scores.waic,waic(p.pointwise_loglikelihood))
        @test named.sampling_warning
        @test named.reference_psis_validation===:finite_reference_checks
        compared=compare_models("base"=>fit,"same"=>fit;kw...,comparison_axis=:model,criterion=:psis_loo)
        @test compared.rows[2].elpd_difference==0
        @test compared.rows[1].estimator===:psis_zhang_stephens
        @test compared.uncertainty.mcmc_mcse===:not_computed
        @test compared.uncertainty.relative_efficiency===:chain_basic_ess
        @test_throws ArgumentError criteria(fit;criteria=(:psis_loo,),tail_fraction=.3)
        @test_throws ArgumentError criteria(fit;draw_indices=[1,2])
        if fit isa B._ModelComparisonFit
            @test isequal(psis_loo(fit),expected)
            @test_throws ArgumentError psis_loo(fit;draw_indices=[1,2])
            @test length(loo_diagnostics(fit;psis_smoothing=true))==n
            @test first(compare_models(fit,fit;criterion=:psis_loo)).pareto_k_estimator===:zhang_stephens
        end
    end
    fit=first(fits)
    mktempdir() do dir
        save_fit(joinpath(dir,"fit.jls"),fit)
        @test isequal(criteria(load_fit(joinpath(dir,"fit.jls"))),criteria(fit))
    end
end
end
