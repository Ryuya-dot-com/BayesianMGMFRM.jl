module PosteriorRankingChecks
using BayesianMGMFRM,Test,Statistics,Serialization
import ..CommonPredictionRefitChecks, ..CommonPredictionKfoldChecks
const B=BayesianMGMFRM;const R=CommonPredictionRefitChecks;const K=CommonPredictionKfoldChecks
function selected(fit)
    rows=filter(r->r.block===:person && !r.fixed,B.recovery_quantities(fit).rows)
    [r.parameter for r in rows if r.dimension==first(rows).dimension]
end
function options(fit)
    common=(;view=:public,include_posterior_predictive=false,include_prior_predictive=false,
        include_waic=false,include_loo=false,include_artifact=false)
    fit isa B._ModelComparisonFit ? merge(common,(;include_category_functioning=false,
        include_rater_homogeneity=false,include_calibration=false)) : common
end
function finite_checks()
@testset "Independent counting oracle for joint ranks and tie bounds" begin
    # Exhaust all three-person combinations, including exact ties, in both directions.
    x=reduce(vcat,[reshape(Float64.([a,b,c]),1,:) for a in -1:1 for b in -1:1 for c in -1:1])
    for direction in (:higher,:lower), k in (nothing,1,2,3)
        d=B._posterior_rank_draws(x,direction,k)
        best=[1+count(v->direction===:higher ? v>x[s,i] : v<x[s,i],x[s,:]) for s in axes(x,1),i in axes(x,2)]
        worst=[count(v->direction===:higher ? v>=x[s,i] : v<=x[s,i],x[s,:]) for s in axes(x,1),i in axes(x,2)]
        @test d.ranks==(best+worst)/2
        @test d.tied==(best.!=worst)
        @test vec(sum(d.ranks;dims=2))==fill(6.,size(x,1))
        @test B._posterior_rank_draws(x[:,[3,1,2]],direction,k).ranks==d.ranks[:,[3,1,2]]
        @test B._posterior_rank_draws(x .+ collect(1:size(x,1)),direction,k).ranks==d.ranks
        if k===nothing
            @test d.certain===d.possible===nothing
        else
            @test d.certain==(worst.<=k)
            @test d.possible==(best.<=k)
            @test all(vec(sum(d.certain;dims=2)).<=k) && all(vec(sum(d.possible;dims=2)).>=k)
        end
    end
    @test B._posterior_rank_draws(x,:lower,1).ranks == (4 .- B._posterior_rank_draws(x,:higher,1).ranks)
    tied=B._posterior_rank_draws([2. 2 1; 2 2 1],:higher,1)
    @test tied.ranks[1,:]==[1.5,1.5,3.]
    @test tied.certain[1,:]==[false,false,false] && tied.possible[1,:]==[true,true,false]
    signed=B._posterior_rank_draws([0. -0. 1.],:lower,1)
    @test signed.ranks==[1.5 1.5 3.]
    # Equal marginal samples can imply different ranks when joint alignment differs.
    a=B._posterior_rank_draws([0. 1.5;1 2.5;2 3.5;3 .5],:higher,1)
    b=B._posterior_rank_draws([0. .5;1 1.5;2 2.5;3 3.5],:higher,1)
    @test mean(a.certain[:,1])==.25 && mean(b.certain[:,1])==0
    # All six strict orderings give uniform rank marginals and top-one probability 1/3.
    perms=[1. 2 3;1 3 2;2 1 3;2 3 1;3 1 2;3 2 1]
    uniform=B._posterior_rank_draws(perms,:higher,1)
    @test vec(mean(uniform.ranks;dims=1))==fill(2.,3)
    @test vec(mean(uniform.certain;dims=1))==fill(1/3,3)
    @test uniform.possible==uniform.certain
    # A large tail can reverse the ranking of means relative to expected ranks.
    skew=[1000. 1 2;0 1 2;0 1 2;0 1 2]
    d=B._posterior_rank_draws(skew,:higher,nothing)
    @test B._posterior_rank_draws(mean(skew;dims=1),:higher,nothing).ranks[1,1]==1
    r=B._posterior_rank_summary(d.ranks[:,1],2,.9)
    @test r.mean==2.5 && r.median==3 && r.lower==1 && r.upper==3
    @test r.mcse.status===:insufficient_draws && r.interval_mcse===:not_computed
    # Inverse empirical CDF endpoints stay on discrete support (no invented rank 1.1).
    q=B._posterior_rank_summary([1.,3.],2,.9)
    @test (q.lower,q.median,q.upper)==(1.,1.,3.)
    constant=B._posterior_rank_summary(fill(1.5,40),2,.99)
    @test constant.mean==constant.lower==constant.upper==1.5 && ismissing(constant.mcse.value)
    @test constant.mcse.status===:degenerate_draws
    @test B._posterior_rank_draws(reshape([3.,2.,1.],1,:),:higher,1).ranks[1,2]==2
    @test B._posterior_rank_draws(reshape([2.,1.],1,:),:higher,1).ranks[1,1]==1
end
end
function checks(output)
@testset "Saved posterior ranking" begin
    finite_checks()
    cases=K.fixture_cases()
    @test length(unique(typeof(c.fit) for c in cases))==8
    for (i,c) in enumerate(cases)
        fit=c.fit;parameters=selected(fit);before=R.bytes(fit)
        request=(;parameters,direction=:higher,top_k=1,interval=.99)
        result=B.posterior_ranking(fit;request...)
        @test result.n_people==length(parameters)
        @test [r.parameter for r in result.rows]==parameters
        @test result.interval_probability==.99 && result.interval_method===:equal_tailed_empirical_inverse_cdf
        @test result.model_contract==B.recovery_quantities(fit).model_contract
        @test result.source_sample_hash==B.recovery_quantities(fit).source_sample_hash
        @test result.sampling_warning && result.status===:warning
        @test result.scientific_acceptance===:not_established
        @test result.scope===:conditional_finite_cohort_rank_uncertainty
        @test B._prediction_check_seal(result,result.schema)===nothing
        @test sum(r.rank.mean for r in result.rows)≈length(parameters)*(length(parameters)+1)/2
        @test sum(r.top_k_probability.lower.mean for r in result.rows)<=1+1e-12
        @test sum(r.top_k_probability.upper.mean for r in result.rows)>=1-1e-12
        for r in result.rows
            @test 1<=r.rank.lower<=r.rank.median<=r.rank.upper<=result.n_people
            @test r.top_k_probability.upper.mean-r.top_k_probability.lower.mean≈r.top_k_probability.boundary_tie_probability.mean atol=1e-15
            @test r.rank.interval_mcse===:not_computed
        end
        reversed=B.posterior_ranking(fit;merge(request,(;parameters=reverse(parameters)))...)
        @test isequal(reverse(result.rows),reversed.rows)
        lower=B.posterior_ranking(fit;merge(request,(;direction=:lower,top_k=nothing))...)
        @test all(r->r.top_k_probability===nothing,lower.rows)
        @test all(isapprox(r.rank.mean+l.rank.mean,result.n_people+1) for (r,l) in zip(result.rows,lower.rows))
        all_people=B.posterior_ranking(fit;merge(request,(;top_k=length(parameters)))...)
        @test all(r->r.top_k_probability.lower.mean==r.top_k_probability.upper.mean==1 &&
            r.top_k_probability.lower.mcse.value==0 && r.top_k_probability.boundary_tie_probability.mcse.status===:structurally_fixed,all_people.rows)
        @test R.bytes(fit)==before
        report=fit_report(fit;options(fit)...,reporting=(;ranking=request),require_complete=true)
        @test report.posterior_ranking.source_result_hash==result.content_hash
        @test report.posterior_ranking.rows[1].mean_rank==result.rows[1].rank.mean
        @test report.posterior_ranking.rows[1].direction===:higher
        @test any(r->r.section===:posterior_ranking,fit_report_sections(report))
        @test occursin("Conditional posterior ranks",fit_report_markdown(report))
        directory=joinpath(output,"report-$i");save_fit_report_bundle(directory,report;require_complete=true)
        loaded=load_fit_report_bundle(directory;require_complete=true)
        @test loaded["posterior_ranking"]==B._json_export_value(report.posterior_ranking)
        @test isfile(joinpath(directory,"tables/posterior_ranking__rows.json"))
        cache=joinpath(output,"fit-$i.jls");save_fit_cache(cache,fit)
        @test isequal(B.posterior_ranking(load_fit_cache(cache);request...),result)
        serialize(joinpath(output,"case-$i.jls"),(;cache,request,result,directory))
        others=filter(r->r.block!==:person || r.fixed,B.recovery_quantities(fit).rows)
        @test_throws ArgumentError B.posterior_ranking(fit;merge(request,(;parameters=[first(parameters),first(others).parameter]))...)
        people=filter(r->r.block===:person && !r.fixed,B.recovery_quantities(fit).rows)
        if length(unique(r.dimension for r in people))>1
            @test_throws ArgumentError B.posterior_ranking(fit;merge(request,(;parameters=[r.parameter for r in people]))...)
        end
    end
    fit=cases[1].fit;parameters=selected(fit);request=(;parameters,direction=:higher,top_k=1)
    for bad in (String[],parameters[1:1],fill(first(parameters),2),[first(parameters),"absent"],[:a,:b],"person")
        @test_throws ArgumentError B.posterior_ranking(fit;merge(request,(;parameters=bad))...)
    end
    for bad in (0,1.5,true,length(parameters)+1)
        @test_throws ArgumentError B.posterior_ranking(fit;merge(request,(;top_k=bad))...)
    end
    for bad in (0.,1.,true,NaN,big"1e-1000",1-big"1e-50")
        @test_throws ArgumentError B.posterior_ranking(fit;request...,interval=bad)
    end
    for bad in (0,1,true,1.5)
        @test_throws ArgumentError B.posterior_ranking(fit;request...,max_rank_cells=bad)
    end
    @test_throws ArgumentError B.posterior_ranking(fit;merge(request,(;direction=:unknown))...)
    @test_throws UndefKeywordError B.posterior_ranking(fit;parameters)
    bad=deepcopy(fit);reverse!(bad.chain_ids)
    @test_throws ArgumentError B.posterior_ranking(bad;request...)
    bad=deepcopy(cases[6].fit);bad.record.run.draws[1,1]+=1
    @test_throws ArgumentError B.posterior_ranking(bad;parameters=selected(cases[6].fit),direction=:higher)
    @test_throws ArgumentError B.posterior_ranking(R.prediction_fixed_fixture(:legacy).fit;request...)
    invalid=(;ranking=(;request...,max_rank_cells=1))
    report=fit_report(fit;options(fit)...,reporting=invalid)
    @test report.posterior_ranking.status===:error && report.report_status===:incomplete
    @test_throws ArgumentError fit_report(fit;options(fit)...,reporting=invalid,require_complete=true)
    @test_throws ArgumentError fit_report(fit;options(fit)...,reporting=invalid,on_section_error=:throw)
    @test_throws ArgumentError fit_report(fit;options(fit)...,reporting=(;ranking=(;unknown=true)))
    path=joinpath(output,"partial-report");save_fit_report_bundle(path,report)
    @test load_fit_report_bundle(path)["posterior_ranking"]["status"]=="error"
    @test_throws ArgumentError load_fit_report_bundle(path;require_complete=true)
    @test !hasproperty(fit_report(fit;options(fit)...,reporting=(;ranking=nothing)),:posterior_ranking)
    @test :posterior_ranking ∉ names(B)
end
end
end
