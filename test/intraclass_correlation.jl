module IntraclassCorrelationChecks
using BayesianMGMFRM, Test
const B=BayesianMGMFRM
include("fixtures/reporting_fit.jl")
published()=[9 2 5 8;6 1 3 2;8 4 6 8;7 1 2 6;10 5 6 9;6 2 4 7]
function data_from_matrix(x;people=collect(axes(x,1)))
    cells=[(u,r) for u in axes(x,1) for r in axes(x,2) if !ismissing(x[u,r])]
    table=(;person=[people[u] for (u,r) in cells],rater=last.(cells),
        item=fill("criterion",length(cells)),response=["response-$u" for (u,r) in cells],
        score=[x[u,r] for (u,r) in cells])
    FacetData(table;person=:person,rater=:rater,item=:item,score=:score,
        response_id=:response,category_levels=minimum(skipmissing(x)):max(minimum(skipmissing(x))+1,maximum(skipmissing(x))))
end
args(d)=(;item="criterion",model=:two_way_random,definition=:agreement,unit=:single,
    score_scale=:interval,dataset_id="icc-example",observation_ids=["rating-$i" for i in 1:d.n])
compute(x;kwargs...)=begin
    d=data_from_matrix(x);B.intraclass_correlation(d;merge(args(d),(;kwargs...))...)
end
# Rational pair-difference identities give total and marginal sums of squares;
# residual SS follows by subtraction, independently of centered residual code.
function oracle(x,definition,unit)
    n,k=size(x); v=vec(x); total=sum((v[a]-v[b])^2 for a in eachindex(v) for b in a+1:length(v))//(n*k)
    rt=vec(sum(x;dims=2));ct=vec(sum(x;dims=1))
    sr=sum((rt[a]-rt[b])^2 for a in 1:n for b in a+1:n)//(n*k)
    sc=sum((ct[a]-ct[b])^2 for a in 1:k for b in a+1:k)//(n*k)
    mr=sr/(n-1);mc=sc/(k-1);me=(total-sr-sc)/((n-1)*(k-1))
    den=unit===:single ? mr+(k-1)*me : mr
    definition===:agreement && (den+=(unit===:single ? k : 1)*(mc-me)/n)
    (;denominator=den,raw_ratio=den==0 ? missing : (mr-me)/den,
        icc=den<=0 ? missing : (mr-me)/den)
end
function finite_checks()
@testset "ICC equations, choice semantics and design boundaries" begin
    x=published();d=data_from_matrix(x)
    values=Dict((:agreement,:single)=>.289763779527559,
        (:agreement,:average)=>.620050547598989,
        (:consistency,:single)=>.714840714840715,
        (:consistency,:average)=>.909315542377069)
    for definition in (:agreement,:consistency),unit in (:single,:average)
        r=compute(x;definition,unit);q=oracle(x,definition,unit)
        @test r.icc≈values[(definition,unit)] atol=1e-12
        @test r.icc≈Float64(q.icc) atol=1e-12
        @test r.icc≈compute(x;definition,unit,model=:two_way_mixed).icc
        @test r.rater_generalization===:rater_population_assumed
        @test compute(x;definition,unit,model=:two_way_mixed).rater_generalization===:fixed_panel
        @test r.icc≈compute(3 .* x .+ 11;definition,unit).icc
        @test r.icc≈compute(x[end:-1:1,end:-1:1];definition,unit).icc
        @test r.n_ratings==24 && r.n_units==6 && r.n_raters==4
        @test r.n_people==6 && !r.repeated_person_units
        @test r.interval===:not_computed && r.se===:not_computed
        @test r.average_rating_count==(unit===:average ? 4 : 1)
        @test B._prediction_check_seal(r,r.schema)===nothing
        @test r.denominator≈Float64(q.denominator)
    end
    a=compute(x);c=compute(x;definition=:consistency)
    @test a.icc<c.icc
    @test compute(x .+ [0 1 2 3];definition=:consistency).icc≈c.icc
    @test compute(x .+ [0 1 2 3]).icc!=a.icc
    for definition in (:agreement,:consistency)
        s=compute(x;definition).icc
        @test compute(x;definition,unit=:average).icc≈4*s/(1+3*s)
    end
    @test compute([1 1;2 2;3 3]).icc==1
    @test compute([1 2;2 3;3 4];definition=:consistency).icc==1
    @test compute([1 2;2 3;3 4]).icc<1
    neg=compute([1 2;2 1];definition=:consistency);@test neg.icc==-1 && neg.status===:descriptive
    badavg=compute([1 2;2 1];unit=:average)
    @test badavg.status===:negative_denominator && ismissing(badavg.icc) && badavg.raw_ratio==2
    for definition in (:agreement,:consistency),unit in (:single,:average)
        constant=compute(fill(2,3,2);definition,unit)
        @test constant.status===:zero_denominator && ismissing(constant.icc) && ismissing(constant.raw_ratio)
    end
    repeated=data_from_matrix(x;people=[1,1,2,2,3,3])
    @test B.intraclass_correlation(repeated;args(repeated)...).repeated_person_units
    for opts in ((;model=:one_way),(;definition=:absolute),(;unit=:mean),
            (;score_scale=:ordinal),(;dataset_id=" "),(;item="absent"),
            (;observation_ids=fill("same",d.n)),(;response_ids=fill("same",d.n)))
        @test_throws ArgumentError B.intraclass_correlation(d;merge(args(d),opts)...)
    end
    for key in (:model,:definition,:unit,:score_scale)
        @test_throws UndefKeywordError B.intraclass_correlation(d;Base.structdiff(args(d),NamedTuple{(key,)}((nothing,)))...)
    end
    for y in (x[1:1,:],x[:,1:1],Union{Missing,Int}[1 2;missing 3],
            Union{Missing,Int}[1 2 missing;1 missing 2])
        bad=data_from_matrix(y)
        @test_throws ArgumentError B.intraclass_correlation(bad;args(bad)...)
    end
    table=facet_response_table(d)
    duplicated=(;(name=>vcat(value,first(value)) for (name,value) in pairs(table))...)
    bad=FacetData(duplicated;person=:person,rater=:rater,item=:item,score=:score,response_id=:response_id,category_levels=1:10)
    @test_throws ArgumentError B.intraclass_correlation(bad;args(bad)...)
    for code in 0:80,definition in (:agreement,:consistency),unit in (:single,:average)
        y=reshape(digits(code;base=3,pad=4),2,2)
        result=compute(y;definition,unit);truth=oracle(y,definition,unit)
        @test ismissing(truth.icc) ? ismissing(result.icc) : isapprox(result.icc,Float64(truth.icc);atol=1e-12)
        @test ismissing(truth.raw_ratio) ? ismissing(result.raw_ratio) : isapprox(result.raw_ratio,Float64(truth.raw_ratio);atol=1e-12)
    end
    @test Base.Docs.doc(B.intraclass_correlation)!==nothing
    @test :intraclass_correlation ∉ names(B)
end
end
function report_options(fit)
    opts=(;view=:full,include_posterior_predictive=false,include_prior_predictive=false,
        include_waic=false,include_loo=false,include_artifact=false)
    fit isa B._ModelComparisonFit ? merge(opts,(;include_category_functioning=false,
        include_rater_homogeneity=false,include_calibration=false)) : opts
end
function report_checks(output,cases)
@testset "ICC observed data report, persistence and retained diagnostics" begin
    @test length(unique(typeof(c.fit) for c in cases))==8
    cells=[(p,i,r) for p in 1:3 for i in 1:2 for r in 1:2]
    complete=FacetData((;person=first.(cells),item=getindex.(cells,2),rater=last.(cells),
        score=[mod(p+i+r,3) for (p,i,r) in cells]);person=:person,item=:item,rater=:rater,score=:score,category_levels=0:2)
    for (i,case) in enumerate(cases)
        fit=case.fit
        # The three legacy shared fixtures are sparse; use complete deterministic
        # reporting draws, with no sampling, for their success-path contracts.
        if fit isa B._ModelComparisonFit
            sparse=B.PredictionObservationAdapter._fit_data(fit)
            opts=(;item=first(sparse.item_levels),model=:two_way_random,definition=:agreement,
                unit=:single,score_scale=:interval)
            req=(;dataset_id="sparse-$i",observation_ids=["row-$j" for j in 1:sparse.n],
                icc=merge(opts,(;response_ids=["p-$j" for j in sparse.person])))
            @test B._saved_icc_section(fit,req,:capture).status===:error
            family=fit isa MFRMFit ? :mfrm : fit isa GMFRMFit ? :gmfrm : :mgmfrm
            fit=reporting_fit(family;data=complete,chains=2,ndraws=20,warmup=0)
        end
        data=B.PredictionObservationAdapter._fit_data(fit)
        ids=["rating-$n" for n in 1:data.n]
        response_ids=haskey(data.optional,:response_id) ? nothing : ["response-$p" for p in data.person]
        icc=(;item=first(data.item_levels),model=:two_way_mixed,definition=:consistency,
            unit=:average,score_scale=:interval,response_ids)
        request=(;dataset_id="icc-$i",observation_ids=ids,icc)
        opts=report_options(fit)
        old=fit_report(fit;opts...)
        direct=B.intraclass_correlation(data;request.dataset_id,observation_ids=ids,icc...)
        report=fit_report(fit;opts...,reporting=request,require_complete=true)
        @test !haskey(old,:intraclass_correlation)
        @test isequal(old.diagnostics,report.diagnostics)
        @test isequal(old.posterior,report.posterior)
        @test report.intraclass_correlation.status===:computed
        @test report.intraclass_correlation.source_result_hash==direct.content_hash
        @test isequal(only(report.intraclass_correlation.rows).icc,direct.icc)
        @test !haskey(report.intraclass_correlation.result,:sampling_warning)
        @test !isempty(direct.other_item_observation_ids)
        public=fit_report_public(report)
        @test occursin("Observed-score two-way ANOVA ICC",fit_report_markdown(public))
        path=joinpath(output,"icc-$i");save_fit_report_bundle(path,public;require_complete=true)
        reopened=load_fit_report_bundle(path;require_complete=true)
        @test reopened["intraclass_correlation"]==B._json_export_value(public.intraclass_correlation)
        @test isfile(joinpath(path,"tables/intraclass_correlation__anova_rows.json"))
        @test isfile(joinpath(path,"tables/intraclass_correlation__unit_rows.json"))
        @test any(r->r.section===:intraclass_correlation,fit_report_sections(reopened))
        if i==1
            bad=merge(request,(;icc=merge(icc,(;item="absent"))))
            captured=fit_report(fit;opts...,reporting=bad,on_section_error=:capture)
            @test captured.intraclass_correlation.status===:error
            @test_throws ArgumentError fit_report(fit;opts...,reporting=bad,require_complete=true)
            @test_throws ArgumentError fit_report(fit;opts...,reporting=(;icc))
            @test_throws ArgumentError fit_report(fit;opts...,reporting=merge(request,(;icc=1)))
            @test_throws ArgumentError fit_report(fit;opts...,reporting=merge(request,(;icc=merge(icc,(;dataset_id="other")))))
            alpha=(;item=icc.item,level=:ordinal,response_ids)
            both=fit_report(fit;opts...,reporting=merge(request,(;alpha)),require_complete=true)
            @test both.krippendorff_alpha.status===:computed
            @test both.intraclass_correlation.source_result_hash==direct.content_hash
        end
    end
end
end
end
