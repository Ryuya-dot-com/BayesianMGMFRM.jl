using BayesianMGMFRM, Test, Statistics
@testset "Portable grouped PVs and within/between imputation uncertainty" begin
    H = BayesianMGMFRM.PortableHandoff
    encode = BayesianMGMFRM.AdditiveFacets.label_encoding
    # A string and symbol with the same spelling are distinct. The large integer
    # exceeds the exact numeric range of JSON readers using double precision.
    ids = Any["p",:p,Int128(2)^90,4,5,6]
    design = (;people=encode.(ids),groups=encode.([:b,:a]),reference_index=2,
        group_index=[1,1,1,2,2,2],covariate_names=String[],covariates=[Float64[] for i in ids])
    y1=[1.,2.,3.,1.,0.,-1.]; y2=[1.,3.,2.,-1.,-2.,0.]
    draws=[(;imputation=i,chain=nothing,iteration=nothing,theta=y,parameters=nothing) for (i,y) in enumerate((y1,y2))]
    r=(;schema=H.PV_SCHEMA,method="conditional_mmle",source_hash="a"^64,qualification=(;qualified=false),
       design,seed=1,quadrature="rectangular",quad_points=31,theta_lim=5.,
       parameter_names=["population[group[:b]]","population_sd[:b]","population_sd[:a]"],
       fixed_measurement=String[],calibration=[2.,1.,1.],draws)
    pv=H.checked_pvs(r)
    s=H.group_contrast(pv;group=:b,reference=:a)
    @test s.estimate≈2.5 && s.within≈2/3 && s.between≈.5 && s.total_variance≈2/3+.75
    @test s.mcse_imputation≈.5 && !s.source_qualified
    @test H.group_contrast(pv;group=:a,reference=:b).upper≈-s.lower
    @test_throws ArgumentError H.group_contrast(pv;group="b",reference=:a)
    @test_throws ArgumentError H.group_contrast(H.PlausibleValues(merge(r,(;draws=draws[1:1])));group=:b,reference=:a)
    @test_throws ArgumentError H.checked_pvs(merge(r,(;calibration=[2.,1.,-1.])))
    @test_throws ArgumentError H.checked_pvs(merge(r,(;draws=reverse(draws))))
    joint=[merge(s,(;chain=i,iteration=1,parameters=[v,1.,1.])) for (i,(s,v)) in enumerate(zip(draws,[-2.,.5]))]
    jr=merge(r,(;method="joint_posterior",seed=nothing,calibration=nothing,draws=joint))
    @test H.group_contrast(H.checked_pvs(jr);group=:b,reference=:a).estimate≈-.75
    @test_throws ArgumentError H.checked_pvs(merge(jr,(;draws=[joint[1],merge(joint[2],(;chain=1))])))
    mktempdir() do dir
        for record in (r,jr)
            file=joinpath(dir,"exports",record.method*".json")
            receipt=save_report(file,H.checked_pvs(record);return_receipt=true)
            @test_throws ArgumentError load_report(file)
            @test_throws ArgumentError load_report(file;expected_sha256="f"^64)
            @test_throws ArgumentError save_report(file,pv)
            restored=load_report(file;expected_sha256=receipt.sha256)
            rows=collect(H.pv_rows(restored))
            @test getproperty.(rows,:person)==repeat(ids,2)
            @test getproperty.(rows,:theta)==vcat(y1,y2)
            @test getproperty.(rows,:chain)==repeat(getproperty.(record.draws,:chain),inner=6)
            @test H.group_contrast(restored;group=:b,reference=:a)==
                  H.group_contrast(H.PlausibleValues(record);group=:b,reference=:a)
        end
    end
end
