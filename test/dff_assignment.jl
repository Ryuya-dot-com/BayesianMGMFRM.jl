module DFFAssignmentChecks
using BayesianMGMFRM, Test, LinearAlgebra, Statistics, Serialization
const B = BayesianMGMFRM
include("fixtures/reporting_fit.jl")

function data_for(counts)
    cells = [(r, i) for r in axes(counts, 1), i in axes(counts, 2)]
    rows = [cell for cell in cells for _ in 1:counts[cell...]]
    n = length(rows)
    return FacetData((; person=[mod1(j, 3) for j in 1:n],
        rater=[r for (r,i) in rows], item=[i for (r,i) in rows],
        score=[mod(j,3) for j in 1:n]); person=:person, rater=:rater,
        item=:item, score=:score, category_levels=0:2)
end

function synthetic_rows(counts, surface; adjustment=:assignment, slope=0.5)
    data=data_for(counts); design=getdesign(mfrm_spec(data; thresholds=:rating_scale))
    residual=reshape([surface[data.rater[j],data.item[j]] for j in 1:data.n],1,:)
    expected=reshape(Float64.(data.score),1,:) .- residual
    slopes=fill(slope, size(residual))
    return B._dff_report_rows_for_term(design,expected,residual,slopes,(:rater,:item);
        interval=.95, lower_probability=.025, upper_probability=.975,min_n=1,
        expected_score_practical_threshold=.01,logit_practical_threshold=.02,
        practical_probability_threshold=.8, adjustment)
end

# A 2x2 table has one interaction contrast, with an exact closed-form projection.
function oracle_2x2(counts, values)
    contrast=[1.,-1.,-1.,1.]; inverse_counts=1 ./ vec(counts)
    return (inverse_counts .* contrast) * (contrast' * values) /
        sum(inverse_counts .* contrast.^2)
end

function finite_checks()
@testset "DFF assignment arithmetic and support" begin
    for counts in ([9 1;1 9], [2 2;2 2], [1 20;3 2])
        projection=B._dff_assignment_projection(counts)
        @test projection.additive_rank==3 && projection.interaction_df==1
        @test projection.n_components==1 && all(projection.supported)
        values=hcat(vec([0. .2; 0. .2]),vec([.4 -.3; .2 .9]))
        answer=B._dff_project_draws(projection,values)
        @test answer ≈ oracle_2x2(counts,values) atol=1e-12
        @test all(iszero,answer[:,1])
        @test reshape(vec(counts).*answer[:,2],2,2)*ones(2) ≈ zeros(2) atol=1e-12
        @test ones(2)'*reshape(vec(counts).*answer[:,2],2,2) ≈ zeros(1,2) atol=1e-12
        @test B._dff_project_draws(projection,answer) ≈ answer atol=1e-12
        # Swapping facet labels and permuting draws preserve the corresponding result.
        swap=[2,1,4,3]; permuted=B._dff_assignment_projection(counts[[2,1],:])
        @test B._dff_project_draws(permuted,values[swap,[2,1]]) ≈ answer[swap,[2,1]] atol=1e-12
        @test B._dff_project_draws(B._dff_assignment_projection(3counts),values) ≈ answer atol=1e-12
    end
    rows=synthetic_rows([9 1;1 9],[0. .2;0. .2])
    old=synthetic_rows([9 1;1 9],[0. .2;0. .2];adjustment=:observed_margins)
    @test [r.expected_score_dff_mean for r in old] ≈ [.08,.08,-.08,-.08]
    @test all(r->r.expected_score_dff_mean==0 && r.logit_dff_mean==0,rows)
    @test all(r->r.flag===:ok && r.expected_score_dff_practical_magnitude===:practically_negligible,rows)
    @test all(r->r.assignment_n_observations==20 && r.assignment_n_observed_cells==4,rows)
    @test all(r->r.n_expected_score_dff_draws==r.n_logit_dff_draws==1,rows)
    for counts in ([1 1;0 1], reshape([4],1,1))
        p=B._dff_assignment_projection(counts)
        @test p.interaction_df==0 && !any(p.supported)
        @test all(isnan,B._dff_project_draws(p,ones(length(p.cells),2)))
    end
    bridge=[9 1 0;1 9 4;0 0 5]
    p=B._dff_assignment_projection(bridge)
    @test p.interaction_df==1 && p.n_components==1
    @test p.supported == [c[1]<=2 && c[2]<=2 for c in p.cells]
    rows=synthetic_rows(bridge,[0. .2 .3; .1 .4 -.2; .0 .0 .7])
    @test count(r->r.contrast_status===:empty_cell,rows)==3
    @test count(r->r.flag===:no_independent_cell_contrast,rows)==2
    @test all(r->isnan(r.expected_score_dff_mean),filter(r->r.contrast_status!==:supported,rows))
    @test all(r->!r.expected_score_dff_interval_excludes_zero,filter(r->r.contrast_status!==:supported,rows))
    @test all(r->r.expected_score_dff_practical_magnitude===:not_estimable,filter(r->r.contrast_status!==:supported,rows))
    # Two disconnected cycles retain local contrasts, without inventing linking.
    counts=[2 1 0 0;3 4 0 0;0 0 5 6;0 0 7 8]
    p=B._dff_assignment_projection(counts)
    @test p.n_components==2 && p.interaction_df==2 && all(p.supported)
    values=reshape(collect(1.:8.),:,1);answer=B._dff_project_draws(p,values)
    @test answer[1:4,:] ≈ oracle_2x2(counts[1:2,1:2],values[1:4,:]) atol=1e-12
    @test answer[5:8,:] ≈ oracle_2x2(counts[3:4,3:4],values[5:8,:]) atol=1e-12
    p=B._dff_assignment_projection([1 1 0;0 1 1;1 0 1])
    @test p.interaction_df==1 && all(p.supported) # six-edge cycle, no complete 2x2
    p=B._dff_assignment_projection([9 1;1 9]); values=ones(4,3);values[1,2]=NaN
    answer=B._dff_project_draws(p,values)
    @test all(isnan,answer[:,2]) && all(iszero,answer[:,[1,3]])
    @test_throws ArgumentError B._dff_project_draws(p,ones(3,2))
    @test_throws ArgumentError B._dff_assignment_projection(zeros(Int,2,2))
    rows=synthetic_rows([9 1;1 9],[0. .2;0. .2];slope=0.)
    @test all(r->r.n_logit_dff_draws==0 && isnan(r.logit_dff_mean) && r.flag===:logit_scale_unstable,rows)
end
end

function api_checks(output)
@testset "DFF public API, report and persistence without fitting" begin
    data=data_for([9 1;1 9]);fit=reporting_fit(:mfrm;data,ndraws=20,chains=2,warmup=0)
    rows=dff_report(fit;terms=(:rater,:item),interval=.99,expected_score_practical_threshold=.1)
    @test length(rows)==4 && all(r->r.adjustment===:assignment,rows)
    @test all(r->r.interval_probability==.99 && r.multiplicity_adjustment===:none,rows)
    @test all(r->r.n_expected_score_dff_draws==r.n_logit_dff_draws==40,rows)
    residuals=predictive_residuals(fit);variances=predictive_variances(fit)
    cells=[findall(j->data.rater[j]==r && data.item[j]==i,1:data.n) for r in 1:2,i in 1:2]
    means=reduce(hcat,[vec(mean(residuals[:,cell];dims=2)) for cell in cells])'
    logits=reduce(hcat,[vec(sum(residuals[:,cell];dims=2)./sum(variances[:,cell];dims=2)) for cell in cells])'
    for (values,field) in ((means,:expected_score_dff),(logits,:logit_dff))
        expected=oracle_2x2([9 1;1 9],values)
        for row in rows
            j=LinearIndices((2,2))[row.focal_level_index,row.comparison_level_index]
            @test getproperty(row,Symbol(field,:_mean)) ≈ mean(expected[j,:]) atol=1e-12
            @test getproperty(row,Symbol(field,:_lower)) ≈ quantile(expected[j,:],.005) atol=1e-12
            @test getproperty(row,Symbol(field,:_upper)) ≈ quantile(expected[j,:],.995) atol=1e-12
        end
    end
    subset=dff_report(fit;terms=(:rater,:item),draw_indices=[1,3,5])
    @test isequal(subset,dff_report(fit.design,fit.draws[[1,3,5],:];terms=(:rater,:item)))
    @test all(r->r.flag===:below_min_n,dff_report(fit;terms=(:rater,:item),min_n=10))
    legacy=@test_logs (:warn,r"Legacy observed-margin") dff_report(fit;terms=(:rater,:item),adjustment=:observed_margins)
    @test all(r->r.adjustment===:observed_margins,legacy)
    # Check historical arithmetic independently, including its nonlinear logit margins.
    for row in legacy
        ii=findall(==(row.focal_level_index),data.rater);jj=findall(==(row.comparison_level_index),data.item)
        cc=intersect(ii,jj)
        meanres(idx)=vec(mean(residuals[:,idx];dims=2))
        shift(idx)=vec(sum(residuals[:,idx];dims=2)./sum(variances[:,idx];dims=2))
        for (f,field) in ((meanres,:expected_score_dff_mean),(shift,:logit_dff_mean))
            @test getproperty(row,field) ≈ mean(f(cc)-f(ii)-f(jj)+f(1:data.n)) atol=1e-12
        end
    end
    @test_throws ArgumentError dff_report(fit;terms=(:rater,:rater))
    @test_throws ArgumentError dff_report(fit;terms=(:rater,:item),adjustment=:unknown)
    @test_throws ArgumentError dff_report(fit;terms=(:rater,:item),interval=1)
    @test_throws ArgumentError dff_report(fit;terms=(:rater,:item),min_n=0)
    @test_throws ArgumentError dff_report(fit.design,fit.draws[:,1:end-1];terms=(:rater,:item))
    kw=(;include_dff=true,dff_terms=(:rater,:item),include_posterior_predictive=false,
        include_category_functioning=false,include_rater_homogeneity=false,
        include_calibration=false,include_waic=false,include_loo=false,include_artifact=false,
        require_complete=true)
    report=fit_report(fit;kw...)
    @test report.dff.status===:computed
    @test all(r->r.adjustment===:assignment,report.dff.rows)
    legacy_report=@test_logs (:warn,r"Legacy observed-margin") fit_report(fit;kw...,dff_adjustment=:observed_margins)
    @test isequal(legacy_report.dff.rows,legacy)
    report_path=joinpath(output,"report.json");save_fit_report(report_path,report)
    loaded=load_fit_report(report_path)
    @test loaded["dff"]["rows"][1]["adjustment"]=="assignment"
    @test loaded["dff"]["rows"][1]["assignment_n_observations"]==20
    fit_path=joinpath(output,"fit.jls");save_fit_cache(fit_path,fit)
    serialize(joinpath(output,"expected-rows.jls"),rows)
    B._write_json_record(joinpath(output,"finite-example.json"),(;
        scope="Deterministic arithmetic, not posterior evidence or calibration",
        counts=[9 1;1 9],additive_surface=[0. .2;0. .2],
        assignment=synthetic_rows([9 1;1 9],[0. .2;0. .2]),
        observed_margins=synthetic_rows([9 1;1 9],[0. .2;0. .2];adjustment=:observed_margins)))
end
end

function edge_checks(output)
@testset "DFF numerical availability and saved report policy" begin
    report=load_fit_report(joinpath(output,"report.json"))
    @test report["report_policy"]["dff_adjustment"]=="assignment"
    # A missing local slope invalidates one term-draw, never a selected cell subset.
    data=data_for([9 1;1 9]);design=getdesign(mfrm_spec(data;thresholds=:rating_scale))
    residual=repeat(reshape([.1data.rater[j]*data.item[j] for j in 1:data.n],1,:),2,1)
    expected=repeat(reshape(Float64.(data.score),1,:),2,1)-residual
    slopes=fill(.5,size(residual));cell=findall(j->data.rater[j]==1 && data.item[j]==1,1:data.n)
    slopes[2,cell].=0.
    rows=B._dff_report_rows_for_term(design,expected,residual,slopes,(:rater,:item);
        interval=.99,lower_probability=.005,upper_probability=.995,min_n=1,
        expected_score_practical_threshold=.01,logit_practical_threshold=.02,
        practical_probability_threshold=.8,adjustment=:assignment)
    @test all(r->r.n_expected_score_dff_draws==2 && r.n_logit_dff_draws==1,rows)
    @test all(r->r.flag===:incomplete_logit_draws,rows)
    @test all(r->isfinite(r.logit_dff_mean),rows)
    # No zero imputation: tree and empty cells survive the actual public path.
    fit=reporting_fit(:mfrm;data=data_for([3 3;0 3]),ndraws=3,warmup=0)
    rows=dff_report(fit;terms=(:rater,:item),expected_score_practical_threshold=.1)
    @test length(rows)==4 && sum(r.n_observations for r in rows)==9
    @test count(r->r.flag===:no_independent_cell_contrast,rows)==3
    @test count(r->r.flag===:empty_cell,rows)==1
    @test all(r->isnan(r.expected_score_dff_mean) && r.n_expected_score_dff_draws==0,rows)
    @test all(r->isfinite(r.expected_score_residual_mean),filter(r->r.n_observations>0,rows))
    # Balanced score centering is the former arithmetic (constant local slope here).
    a=synthetic_rows([3 3;3 3],[.1 -.2;.3 .5])
    b=synthetic_rows([3 3;3 3],[.1 -.2;.3 .5];adjustment=:observed_margins)
    @test [r.expected_score_dff_mean for r in a] ≈ [r.expected_score_dff_mean for r in b]
    @test [r.logit_dff_mean for r in a] ≈ [r.logit_dff_mean for r in b]
    g=reporting_fit(:gmfrm;ndraws=3,warmup=0)
    @test_throws MethodError dff_report(g;terms=(:rater,:item))
    @test_throws ArgumentError dff_report(g.design,g.draws;terms=(:rater,:item))
end
end

function checks(output)
    finite_checks()
    api_checks(output)
    edge_checks(output)
end
end
