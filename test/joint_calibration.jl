using BayesianMGMFRM, Test, LinearAlgebra, ForwardDiff
using BayesianMGMFRM.GlassBox
using Distributions: Normal
@testset "Independent calibration covariance and a receiving-panel contrast" begin
    table = (person=repeat(1:12,inner=2),rating=repeat([5,6,6,7,7,5],4),audio=repeat(["b","a"],12))
    opts = (person=:person,score=:rating,facets=(recording=:audio,),category_levels=5:7)
    rows = [(block=:recording,level="a",estimate=1.1),(block=:recording,level="b",estimate=.4),
            (block=:steps,owner=:global,level=:global,upper_category=6,estimate=-.3)]
    V = [.12 .03 -.01; .03 .08 .02; -.01 .02 .05]
    cal = (coordinates=rows,covariance=V)
    fit_mean(s) = fit(s;method=:mmle,estimate_mean=true,quad_points=41)
    spec = mfrm_spec(table;opts...,calibration=cal,prior=:none)
    f = fit_mean(spec)
    s = design_summary(f)
    @test qualify(f).qualified && s.calibration.propagated_se > s.calibration.conditional_se
    @test s.population_mean_se == s.calibration.propagated_se
    @test sum(s.calibration.gradient[1:2]) ≈ 1 atol=1e-8
    order = [3,2,1]
    other = mfrm_spec(map(reverse,table);opts...,calibration=(coordinates=rows[order],covariance=V[order,order]),prior=:none)
    so = design_summary(fit_mean(other))
    @test s.population_mean ≈ so.population_mean atol=1e-9
    @test s.population_mean_se ≈ so.population_mean_se atol=1e-9
    @test s.calibration.gradient[order] ≈ so.calibration.gradient atol=1e-9
    reflected = copy(rows)
    reflected[3] = merge(rows[3],(;upper_category=7,estimate=.3))
    D = Diagonal([1.,1.,-1.])
    alt = design_summary(fit_mean(mfrm_spec(table;opts...,calibration=(coordinates=reflected,covariance=D*V*D),prior=:none)))
    @test alt.population_mean ≈ s.population_mean atol=1e-8
    @test alt.population_mean_se ≈ s.population_mean_se atol=1e-8
    # With a free receiving location, propagate through the joint nuisance/mean Hessian.
    function partial(itemmean)
        rs=[merge(rows[1],(;estimate=itemmean)),rows[3]]
        input=(coordinates=rs,covariance=V[[1,3],[1,3]])
        design_summary(fit_mean(mfrm_spec(table;opts...,calibration=input,prior=:none)))
    end
    nuisance=partial(1.1)
    @test nuisance.calibration.gradient[1] ≈ (partial(1.101).population_mean-partial(1.099).population_mean)/.002 atol=1e-5
    for j in eachindex(rows)
        function at(d)
            x = copy(rows)
            x[j] = merge(x[j],(;estimate=x[j].estimate+d))
            design_summary(fit_mean(mfrm_spec(table;opts...,calibration=(coordinates=x,covariance=V),prior=:none))).population_mean
        end
        @test s.calibration.gradient[j] ≈ (at(.001)-at(-.001))/.002 atol=2e-5
    end
    @test_throws ArgumentError fit(spec;method=:jmle)
    @test_throws ArgumentError fit(spec;method=:mmle)
    for bad in ((coordinates=rows,covariance=zeros(3,3)),(coordinates=rows,covariance=-V),
                (coordinates=rows,covariance=[1. 1 0;0 1 0;0 0 1]),
                (coordinates=[rows[1],rows[1]],covariance=ones(2,2)),
                (coordinates=[merge(rows[1],(;level="unknown"))],covariance=ones(1,1)),
                (coordinates=[rows[3],merge(rows[3],(;upper_category=7,estimate=.3))],covariance=Matrix(1.0I,2,2)))
        @test_throws ArgumentError mfrm_spec(table;opts...,calibration=bad,prior=:none)
    end
    b = mfrm_spec(table;opts...,calibration=cal,prior_sd=(person=1.,facets=(recording=0.,),step=0.),intercept=Normal())
    @test validate_design(b).identified && b.allocation.receiving_rank.structural < b.allocation.structural_rank
    facet=only(design_summary(b).facets)
    @test ismissing(facet.marginal_prior_sd) && length(facet.external_prior_sd)==2 && facet.free_parameters==2
    @test_throws ArgumentError fit_mean(b)
    q = collect(range(-.2,.3,length=length(initial_params(b))))
    @test last(logdensity_and_gradient(b,q)) ≈ ForwardDiff.gradient(x->logposterior(b,x),q) atol=1e-10
    @test isempty(b.operator.fixed_model_names)
    # Compare in the posterior draw, retaining the receiving mean/person dependence.
    bf = fit(b; chains=2, warmup=24, ndraws=24, seed=2827)
    people = ["person[2]","person[1]"]
    sel = BayesianMGMFRM.AdditiveFacets.selected(b,bf.record.run;parameters=vcat(people,"population_mean"))
    linked = BayesianMGMFRM.posterior_classification(bf;location=:linked,cutoff=0.,parameters=people)
    direct = classification(bf;cutoff=0.,parameters=people)
    @test linked.location === :linked && linked.shift_parameter == "population_mean"
    @test getproperty.(linked.rows,:parameter) == people && !hasproperty(direct,:location)
    for (i,r) in enumerate(linked.rows)
        absolute = sel.values[:,i] + sel.values[:,3]
        @test r.mean ≈ sum(absolute)/length(absolute)
        @test r.qualifying_probability == count(>=(0),absolute)/length(absolute)
        @test direct.rows[i].qualifying_probability == count(>=(0),sel.values[:,i])/length(absolute)
    end
    @test_throws ArgumentError classification(bf;location=:linked,cutoff=0.,parameters=["population_mean"])
    @test_throws ArgumentError classification(bf;location=:linked,cutoff=0.,facet=:recording)
    @test_throws ArgumentError classification(bf;location=:other,cutoff=0.)
    x = coordinates(b,q).structural_model
    labs = parameter_names(b;scale=:model)[end-length(x)+1:end]
    shifts = cholesky(Symmetric(V)).L*q[end-2:end]
    reordered = mfrm_spec(table;opts...,calibration=(coordinates=rows[order],covariance=V[order,order]),
        prior_sd=(person=1.,facets=(recording=0.,),step=0.),intercept=Normal())
    q2 = copy(q)
    q2[end-2:end] = cholesky(Symmetric(V[order,order])).L \ shifts[order]
    @test logposterior(b,q) ≈ logposterior(reordered,q2) atol=1e-11
    vals = Dict(zip(labs,x))
    @test vals["recording[\"a\"]"] ≈ 1.1+shifts[1]
    @test vals["steps[:global,6]"] ≈ -.3+shifts[3]
    @test vals["steps[:global,7]"] ≈ .3-shifts[3]
    @test_throws ArgumentError anchor_linking_summary(f;coordinates=[(parameter="a",block=:item,level=1)])
    A=zeros(2,3,3)
    for i in 1:2,k in 0:2
        A[i,k+1,i] = -k
        A[i,k+1,3] = k==1 ? -1 : 0
    end
    source=BayesianMGMFRM.MRCML.custom_spec(table;opts...,A,item_index=[x=="a" ? 1 : 2 for x in table.audio],
        parameter_names=["A","B","T"])
    first=fit(source;method=:mmle)
    mapping=[(parameter="T",block=:steps,owner=:global,level=:global,upper_category=6),
             (parameter="B",block=:recording,level="b"),(parameter="A",block=:recording,level="a")]
    extracted=anchor_linking_summary(first;coordinates=mapping)
    @test [r.estimate for r in extracted.coordinates] ≈ first.record.full_parameters[[3,2,1]]
    @test extracted.covariance ≈ first.record.covariance.matrix[[3,2,1],[3,2,1]]
    @test_throws ArgumentError anchor_linking_summary(first;coordinates=mapping[[1,1]])
    # Covariance changes are bound to the receiving fit checksum.
    corrupted=deepcopy(f)
    corrupted.record.summary.calibration.covariance[1,1] *= 2
    @test_throws ArgumentError design_summary(corrupted)
    mktempdir() do dir
        path=joinpath(dir,"mean.jls")
        save_fit(path,f)
        @test design_summary(load_fit(path)).calibration == s.calibration
        json=joinpath(dir,"mean.json")
        save_report(json, f)
        saved=load_report(json).summary.calibration
        @test all(i->collect(saved.covariance[i])==s.calibration.covariance[i,:],1:3)
        @test [r.kind for r in saved.coordinate_level_labels]==["string","string","symbol"]
    end
end
