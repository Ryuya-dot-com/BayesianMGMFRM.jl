module KrippendorffAlphaChecks
using BayesianMGMFRM, Test, Random
const B=BayesianMGMFRM

function data_from_matrix(x;levels=1:5)
    cells=[(r,u) for u in axes(x,2) for r in axes(x,1) if !ismissing(x[r,u])]
    table=(;person=last.(cells),rater=first.(cells),item=fill("criterion",length(cells)),
        response=["response-$u" for (r,u) in cells],score=[x[r,u] for (r,u) in cells])
    FacetData(table;person=:person,rater=:rater,item=:item,score=:score,
        response_id=:response,category_levels=levels)
end

args(data;level=:nominal)=(;item="criterion",level,dataset_id="observed-example",
    observation_ids=["rating-$i" for i in 1:data.n])

published()=Union{Missing,Int}[
    1 2 3 3 2 1 4 1 2 missing missing missing;
    1 2 3 3 2 2 4 1 2 5 missing 3;
    missing 3 3 3 2 3 4 2 2 5 1 missing;
    1 2 3 3 2 4 4 1 2 5 1 missing]

# Independent rational arithmetic enumerates actual rating pairs, not category
# outer products or the implementation's cumulative midpoint distance.
function oracle(x,K,level)
    units=[collect(skipmissing(x[:,u])) for u in axes(x,2)]
    paired=filter(v->length(v)>=2,units)
    values=reduce(vcat,paired;init=Int[])
    n=length(values);n==0 && return missing
    counts=[count(==(k),values) for k in 1:K]
    distance(c,k)=level===:nominal ? (c!=k)//1 :
        (sum(counts[min(c,k):max(c,k)])-(counts[c]+counts[k])//2)^2
    do_sum=sum((distance(v[i],v[j])//(length(v)-1) for v in paired
        for i in eachindex(v) for j in eachindex(v) if i!=j);init=0//1)
    de_sum=sum((distance(values[i],values[j]) for i in 1:n for j in 1:n if i!=j);init=0//1)//(n-1)
    de_sum==0 ? missing : 1-do_sum/de_sum
end

function finite_checks()
@testset "Observed alpha equations, identities and unavailable results" begin
    x=published();data=data_from_matrix(x);a=B.krippendorff_alpha(data;args(data)...)
    @test a.n_ratings==41 && a.n_pairable_ratings==40
    @test a.n_units==12 && a.n_pairable_units==11 && a.n_singleton_units==1
    @test a.marginal_counts==[9,13,10,5,3]
    @test a.observed_coincidences ≈ [7 4/3 1/3 1/3 0;4/3 10 4/3 1/3 0;
        1/3 4/3 8 1/3 0;1/3 1/3 1/3 4 0;0 0 0 0 3]
    @test a.alpha ≈ 1-312/1216
    @test round(a.alpha;digits=3)==.743
    @test a.observed_disagreement≈.2
    @test sum(a.observed_coincidences;dims=2)[:]≈a.marginal_counts
    @test sum(a.expected_coincidences;dims=2)[:]≈a.marginal_counts
    ordinal=B.krippendorff_alpha(data;args(data;level=:ordinal)...)
    @test ordinal.squared_distances[1,3]==22.5^2
    @test round(ordinal.alpha;digits=3)==.815
    @test ordinal.alpha≈Float64(oracle(x,5,:ordinal))
    @test a.alpha≈Float64(oracle(x,5,:nominal))
    @test a.interval===:not_computed && a.se===:not_computed
    @test B._prediction_check_seal(a,a.schema)===nothing
    @test isempty(a.other_item_observation_ids)
    @test length(a.singleton_observation_ids)==1
    @test a.n_pairable_ratings!=sum(length(v)*(length(v)-1) for v in [collect(skipmissing(x[:,u])) for u in axes(x,2)])

    # Relabeling changes no nominal distance; monotone recoding and unused ranks
    # change neither ordinal alpha nor the pairable ordinal distances.
    for (codes,level) in (([5,1,4,2,3],:nominal),([1,2,3,4,6],:ordinal))
        y=map(v->ismissing(v) ? missing : codes[v],x)
        d=data_from_matrix(y;levels=1:maximum(codes))
        result=B.krippendorff_alpha(d;args(d;level)...)
        @test result.alpha≈(level===:nominal ? a.alpha : ordinal.alpha)
    end
    permuted=data_from_matrix(x[end:-1:1,end:-1:1])
    @test B.krippendorff_alpha(permuted;args(permuted)...).alpha≈a.alpha
    changed=copy(x);changed[2,12]=5
    d=data_from_matrix(changed)
    @test B.krippendorff_alpha(d;args(d;level=:ordinal)...).alpha≈ordinal.alpha
    negative=data_from_matrix([1 2 1;2 1 2];levels=1:2)
    @test B.krippendorff_alpha(negative;args(negative)...).alpha≈-2/3
    for (y,status) in ((fill(1,2,3),:zero_expected_disagreement),
            (Union{Missing,Int}[1 missing;missing 2],:no_pairable_units))
        d=data_from_matrix(y;levels=1:2);r=B.krippendorff_alpha(d;args(d)...)
        @test r.status===status && ismissing(r.alpha)
    end
    perfect=data_from_matrix([1 2 3;1 2 3])
    @test B.krippendorff_alpha(perfect;args(perfect;level=:ordinal)...).alpha==1
    for opts in ((;level=:interval),(;item="absent"),(;dataset_id=" "),
            (;max_category_pairs=24),(;max_category_pairs=true),
            (;observation_ids=fill("duplicate",data.n)))
        @test_throws ArgumentError B.krippendorff_alpha(data;merge(args(data),opts)...)
    end
    duplicate=facet_response_table(data)
    table=(; (name=>vcat(value,first(value)) for (name,value) in pairs(duplicate))...)
    d=FacetData(table;person=:person,rater=:rater,item=:item,score=:score,
        response_id=:response_id,category_levels=1:5)
    @test_throws ArgumentError B.krippendorff_alpha(d;args(d)...)
    bad=copy(a.response_ids);bad[1]="wrong"
    @test_throws ArgumentError B.krippendorff_alpha(data;args(data)...,response_ids=bad)
    @test_throws UndefKeywordError B.krippendorff_alpha(data;Base.structdiff(args(data),(;level=nothing))...)

    # Exhaustive small complete/incomplete arrays, independent rational oracle.
    for code in 0:255,level in (:nominal,:ordinal)
        values=digits(code;base=4,pad=4)
        y=reshape(Union{Missing,Int}[v==0 ? missing : v for v in values],2,2)
        all(ismissing,y) && continue
        d=data_from_matrix(y;levels=1:3)
        result=B.krippendorff_alpha(d;args(d;level)...)
        truth=oracle(y,3,level)
        @test ismissing(truth) ? ismissing(result.alpha) : result.alpha≈Float64(truth)
    end
    @test Base.Docs.doc(B.krippendorff_alpha)!==nothing
    @test :krippendorff_alpha ∉ names(B)
end
end

function report_checks(output,cases)
@testset "Alpha report integration without model-based reliability claims" begin
    for (i,case) in enumerate(cases)
        fit=case.fit;data=B.PredictionObservationAdapter._fit_data(fit)
        ids=["rating-$n" for n in 1:data.n]
        responses=get(data.optional,:response_id,nothing)===nothing ?
            ["response-$p" for p in data.person] : nothing
        options=(;view=:full,include_posterior_predictive=false,include_prior_predictive=false,
            include_waic=false,include_loo=false,include_artifact=false)
        if fit isa B._ModelComparisonFit
            options=merge(options,(;include_category_functioning=false,
                include_rater_homogeneity=false,include_calibration=false))
        end
        alpha=(;item=first(data.item_levels),level=:ordinal,response_ids=responses)
        request=(;dataset_id="alpha-$i",observation_ids=ids,alpha)
        direct=B.krippendorff_alpha(data;request.dataset_id,observation_ids=ids,alpha...)
        @test !isempty(direct.other_item_observation_ids)
        @test all(n->data.item[n]==1,[findfirst(==(id),ids) for id in direct.included_observation_ids])
        old=fit_report(fit;options...)
        report=fit_report(fit;options...,reporting=request,require_complete=true)
        @test !haskey(old,:krippendorff_alpha)
        @test isequal(old.diagnostics,report.diagnostics)
        @test isequal(old.posterior,report.posterior)
        @test report.krippendorff_alpha.status===:computed
        @test report.krippendorff_alpha.source_result_hash==direct.content_hash
        @test isequal(only(report.krippendorff_alpha.rows).alpha,direct.alpha)
        @test !haskey(report.krippendorff_alpha.result,:sampling_warning)
        public=fit_report_public(report)
        @test public.krippendorff_alpha.result.included_observation_ids==direct.included_observation_ids
        @test occursin("Observed-score Krippendorff alpha",fit_report_markdown(public))
        path=joinpath(output,"alpha-$i");save_fit_report_bundle(path,public;require_complete=true)
        reopened=load_fit_report_bundle(path;require_complete=true)
        @test reopened["krippendorff_alpha"]==B._json_export_value(public.krippendorff_alpha)
        @test isfile(joinpath(path,"tables/krippendorff_alpha__rows.json"))
        @test isfile(joinpath(path,"tables/krippendorff_alpha__unit_rows.json"))
        @test any(r->r.section===:krippendorff_alpha,fit_report_sections(reopened))
        if i==1
            bad=merge(request,(;alpha=merge(alpha,(;item="absent"))))
            captured=fit_report(fit;options...,reporting=bad,on_section_error=:capture)
            @test captured.krippendorff_alpha.status===:error
            @test_throws ArgumentError fit_report(fit;options...,reporting=bad,require_complete=true)
            @test_throws ArgumentError fit_report(fit;options...,reporting=(;alpha))
            @test_throws ArgumentError fit_report(fit;options...,reporting=merge(request,(;alpha=1)))
            @test_throws ArgumentError fit_report(fit;options...,reporting=merge(request,(;alpha=merge(alpha,(;dataset_id="other")))))
        end
    end
end
end
end
