module CriterionCollapseLOOChecks
using BayesianMGMFRM,Test,Statistics
const B=BayesianMGMFRM
const C=B.Experimental.CriterionCollapse
include("fixtures/experimental_diagnostic_record.jl")

function enumerate_likelihood(t,q,ns;ordinary=false)
    c=C.category_logprobs(t,q);s=C.coordinates(t,q)
    sum(prod(z[r]==0 ? exp(s.log1mpi) : exp(s.logpi) for r in 1:t.R)*
        prod(exp((z[t.rater[n]]==0 ? c.ordinary : c.halo)[n,t.score[n]+1]) for n in ns)
        for z in Iterators.product(fill(0:1,t.R)...) if !ordinary || all(iszero,z))
end

@testset "Conditional profile LOO and induced ordinary comparison" begin
    result=diagnostic_record(:CriterionCollapse);t=C._restore(result)
    design=C._heldout_design(t,:performance_rater)
    x=C._heldout_values(t,result.run.draws,design)
    @test length(design.groups)==12
    for j in (1,17),h in eachindex(design.groups)
        q=result.run.draws[j,:];keep=setdiff(1:t.data.n,design.groups[h])
        all=enumerate_likelihood(t,q,1:t.data.n);train=enumerate_likelihood(t,q,keep)
        a=enumerate_likelihood(t,q,1:t.data.n;ordinary=true)
        am=enumerate_likelihood(t,q,keep;ordinary=true)
        @test x.mixture[j,h]≈log(all/train) atol=1e-13
        @test x.ordinary[j,h]≈log(a/am) atol=1e-13
        @test x.loga[j]-x.ordinary[j,h]≈log(am/train)-x.mixture[j,h] atol=1e-13
    end
    @test !isapprox(sum(x.mixture[1,:]),C.components(t,result.run.draws[1,:]).loglikelihood;atol=1e-6)
    for model in (:mixture,:all_ordinary)
        low=pointwise_loglikelihood(result;unit=:performance_rater,model)
        @test low.log_density==(model===:mixture ? x.mixture : x.ordinary)
        @test low.factorizes_joint===false && low.likelihood_kind===:conditional_holdout_ratio
        @test low.chain_ids==result.run.chain_ids && low.iterations==result.run.iterations
        @test low.profiles==design.profiles
        report=criteria(result;unit=:performance_rater,model)
        @test C._operation_report_check(report)===report
        @test report.result.elpd≈sum(p.log_score for p in report.result.pointwise)
        @test ismissing(report.sampling_standard_error)
        @test report.result.model===model
        mktempdir() do dir
            receipt=save_report(joinpath(dir,"criteria.json"),report;return_receipt=true)
            restored=load_report(receipt.path;expected_sha256=receipt.sha256)
            @test restored.result.elpd≈report.result.elpd
            @test restored.profiles[1].person==design.profiles[1].person
        end
        @test_throws ArgumentError C._operation_report_check(merge(report,(;factorizes_joint=true)))
        @test_throws ArgumentError C._operation_report_check(merge(report,(;sampling_standard_error=.1)))
    end
    c=compare_models(result;criterion=:loo,unit=:performance_rater)
    @test c.difference.estimate≈c.mixture.elpd-c.all_ordinary.elpd
    @test_throws ArgumentError C._operation_report_check(merge(c,(;difference=merge(c.difference,(;mean_difference=99.)))))
    @test_throws ArgumentError C._operation_report_check(merge(c,(;mcse_warning=!c.mcse_warning)))
    m=C._heldout_evaluation(x,result.run,:mixture);a=C._heldout_evaluation(x,result.run,:all_ordinary)
    good=isempty(m.report.problem_profiles) && isempty(a.report.problem_profiles)
    ref=C._heldout_precision(vec(sum(m.influences-a.influences;dims=2)),result.run,good)
    @test isequal(ref.mcse,c.difference.mcse)
    @test compare_models(result).kind===:criterion_collapse_model_comparison
    mktempdir() do dir
        receipt=save_report(joinpath(dir,"comparison.json"),c;return_receipt=true)
        restored=load_report(receipt.path;expected_sha256=receipt.sha256)
        @test restored.difference.estimate≈c.difference.estimate
        @test restored.sampling_uncertainty=="not_assessed_crossed_overlapping_folds"
    end
    @test_throws ArgumentError criteria(result)
    @test_throws ArgumentError criteria(result;unit=:rater)
    @test_throws ArgumentError criteria(result;unit=:performance_rater,model=:new_rater)
    @test_throws MethodError criteria(result;unit=:performance_rater,ndraws=10)
    @test_throws ArgumentError compare_models(result;criterion=:waic,unit=:performance_rater)
    @test_throws ArgumentError compare_models(result;unit=:performance_rater)
    @test_throws ArgumentError pointwise_loglikelihood(result;unit=:row)
    for lr in (zeros(result.run.total_draws),[0.;fill(1000.,result.run.total_draws-1)])
        z=C._profile_score(fill(-1.,length(lr)),lr,result.run)
        @test z.row.importance_status===:diagnostic_only
        @test ismissing(z.row.mcse)
        @test isfinite(z.row.log_score)
    end
    # A partial profile is an observed subset; no category or missing row is invented.
    table=C.RI._table(t.data);mask=collect(2:t.data.n)
    subset=(;(k=>v[mask] for (k,v) in pairs(table))...)
    td=C.model(FacetData(subset;person=:person,item=:item,rater=:rater,score=:score,category_levels=0:2);prior=t.prior)
    partial=C._heldout_design(td,:performance_rater)
    @test sum(p.n_ratings for p in partial.profiles)==t.data.n-1
    @test any(p->p.n_ratings==1,partial.profiles)
    reordered=(;(k=>reverse(v) for (k,v) in pairs(table))...)
    tr=C.model(FacetData(reordered;person=:person,item=:item,rater=:rater,score=:score,category_levels=0:2);prior=t.prior)
    dr=C._heldout_design(tr,:performance_rater)
    @test Set((p.person,p.rater,Tuple(sort(p.criteria))) for p in dr.profiles)==
        Set((p.person,p.rater,Tuple(sort(p.criteria))) for p in design.profiles)
    @test dr.observation_binding!=design.observation_binding
    mask=findall(n->t.person[n]!=1 || t.rater[n]==1,1:t.data.n)
    subset=(;(k=>v[mask] for (k,v) in pairs(table))...)
    weak=C.model(FacetData(subset;person=:person,item=:item,rater=:rater,score=:score,category_levels=0:2);prior=t.prior)
    @test_throws ArgumentError C._heldout_design(weak,:performance_rater)
end
end
