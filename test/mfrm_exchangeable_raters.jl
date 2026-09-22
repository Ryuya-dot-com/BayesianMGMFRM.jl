module MFRMExchangeableRaterChecks

using Test, BayesianMGMFRM, LinearAlgebra, ForwardDiff, Serialization
const B = BayesianMGMFRM
const LD = B.LogDensityProblems
const SCALES = (; person_sd=0.7, rater_kernel_sd=0.4, item_sd=0.6, step_sd=0.5)
include("test_groups.jl")

function specification(R=3, K=4; D=2, mixed=false, labels=1:R)
    cells = [(p,i,r) for p in 1:3 for i in 1:2D for r in 1:R]
    data = FacetData((; person=first.(cells), item=getindex.(cells,2),
        rater=["R$(labels[r])" for (p,i,r) in cells],
        score=[mod(p+i+r,K) for (p,i,r) in cells]);
        person=:person, item=:item, rater=:rater, score=:score, category_levels=0:(K-1))
    q = Bool[d == cld(i,2) for i in 1:2D, d in 1:D]
    mixed && (q[2,2] = true)
    return mfrm_spec(data; dimensions=D, q_matrix=q)
end
target(spec, correlated; scales=SCALES) = B._MFRMExchangeableRatersLogDensity(
    correlated ? B.Experimental.correlated(spec; lkj_eta=3) : spec; scales)
reference(t) = B._mfrm_exchangeable_rater_reference(t)
pointwise(t,x) = B._mfrm_fixed_q_pointwise(reference(t), x[1:LD.dimension(reference(t))])

@testset "exchangeable rater normalized density and covariance" begin
    for correlated in (false,true), R in (2,3,5), K in (2,4), tau in (0.4,1.2)
        t = target(specification(R,K),correlated; scales=merge(SCALES,(;rater_kernel_sd=tau)))
        block = reference(t).blueprint.blocks[:rater_free]
        x = [0.13sin(i) for i in 1:LD.dimension(t)]
        correlated && (x[end] = atanh(0.4))
        covariance = tau^2 .* (Matrix{Float64}(I,R-1,R-1)-ones(R-1,R-1)/R)
        # Independent matrix-normal implementation checks normalization and derivatives.
        distribution = B.Turing.MvNormal(zeros(R-1),covariance)
        expected = logprior(t.base,x) - sum(B._normal_logpdf(v,tau) for v in x[block]) +
            B.Turing.logpdf(distribution,x[block])
        @test logprior(t,x) ≈ expected atol=1e-11
        @test LD.logdensity(t,x) ≈ sum(pointwise(t,x))+expected atol=1e-10
        gradient = ForwardDiff.gradient(v->logprior(t,v),x)
        hessian = ForwardDiff.hessian(v->logprior(t,v),x)
        @test gradient[block] ≈ -(covariance\x[block]) atol=1e-11
        @test hessian[block,block] ≈ -inv(covariance) atol=1e-10
        outside = setdiff(1:length(x),block)
        @test gradient[outside] ≈ ForwardDiff.gradient(v->logprior(t.base,v),x)[outside] atol=1e-11
        @test iszero(hessian[block,outside])
        @test LD.dimension(t) == LD.dimension(t.base)
        @test initial_params(t) == initial_params(t.base)
        C = vcat(Matrix{Float64}(I,R-1,R-1),-ones(1,R-1))
        full = C*covariance*C'
        record = B._mfrm_exchangeable_rater_record(t)
        @test full ≈ tau^2 .* (Matrix{Float64}(I,R,R)-ones(R,R)/R) atol=1e-12
        @test diag(full) ≈ fill(record.rater_marginal_sd^2,R)
        @test full[1,1]+full[end,end]-2full[1,end] ≈ record.rater_contrast_sd^2
        @test record.scales.rater_kernel_sd == tau
        # Common marginal matching requires an explicit conversion, not reusing
        # the old unequal-marginal rater_sd interpretation.
        matched = target(specification(R,K),correlated;
            scales=merge(SCALES,(;rater_kernel_sd=tau*sqrt(R/(R-1)))))
        @test B._mfrm_exchangeable_rater_record(matched).rater_marginal_sd ≈ tau
    end
end

@testset "rater relabelling preserves priors and response likelihoods" begin
    for (correlated,D,mixed) in ((false,2,false),(false,2,true),(false,3,false),(true,2,false)),
            R in (2,3,5)
        t = target(specification(R;D,mixed),correlated)
        block = reference(t).blueprint.blocks[:rater_free]
        x = [0.13cos(i) for i in 1:LD.dimension(t)]
        correlated && (x[end] = atanh(-0.6))
        full = B._sum_to_zero_from_raw(x[block],R)
        # Includes a non-self-inverse cycle, and a swap of the reconstructed rater.
        for labels in (reverse(1:R), [collect(2:R);1], [R;collect(2:(R-1));1])
            other = target(specification(R;D,mixed,labels),correlated)
            y = copy(x)
            y[block] .= full[invperm(collect(labels))][1:(R-1)]
            @test pointwise(other,y) ≈ pointwise(t,x) atol=1e-12
            @test logprior(other,y) ≈ logprior(t,x) atol=1e-11
            @test LD.logdensity(other,y) ≈ LD.logdensity(t,x) atol=1e-10
        end
        # The rater correction leaves the likelihood location freedom unchanged.
        shifted = copy(x)
        c = collect(range(-0.2,0.3;length=D))
        shifted[reference(t).blueprint.blocks[:person]] .+= repeat(c,3)
        shifted[reference(t).blueprint.blocks[:item]] .+= reference(t).design.spec.q_matrix*c
        @test pointwise(t,shifted) ≈ pointwise(t,x) atol=1e-12
        @test logprior(t,shifted)-logprior(t,x) ≈ logprior(t.base,shifted)-logprior(t.base,x) atol=1e-11
    end
end

@testset "distinct persisted target identities and input guards" begin
    spec = specification()
    for correlated in (false,true)
        declared = correlated ? B.Experimental.correlated(spec;lkj_eta=3) : spec
        t = target(spec,correlated)
        record = B._mfrm_exchangeable_rater_record(t)
        identity = B._mfrm_exchangeable_rater_identity(t)
        @test identity != record.base_identity
        @test B._cmdstan_generalized_data(t.base).exchangeable_raters == 0
        @test B._cmdstan_generalized_data(t).exchangeable_raters == 1
        mktempdir() do dir
            path = joinpath(dir,"target.jls")
            serialize(path,record)
            restored = B._MFRMExchangeableRatersLogDensity(declared,deserialize(path);expected_identity=identity)
            @test B._mfrm_exchangeable_rater_identity(restored) == identity
            @test logprior(restored,initial_params(t)) == logprior(t,initial_params(t))
        end
        @test_throws ArgumentError B._MFRMExchangeableRatersLogDensity(declared,record;expected_identity=record.base_identity)
        for bad in (merge(record,(;schema="old")), merge(record,(;rater_scale_convention=:marginal_sd)),
                merge(record,(;rater_marginal_sd=99.0)), merge(record,(;extra=1)),
                merge(record,(;scales=merge(SCALES,(;step_sd=0.9)))))
            @test_throws ArgumentError B._MFRMExchangeableRatersLogDensity(declared,bad;expected_identity=identity)
        end
        @test_throws ArgumentError B._MFRMExchangeableRatersLogDensity(specification(5),record;expected_identity=identity)
        @test_throws ArgumentError logprior(t,zeros(LD.dimension(t)-1))
        @test_throws ArgumentError LD.logdensity(t,fill(NaN,LD.dimension(t)))
    end
    @test B._mfrm_exchangeable_rater_identity(target(spec,false)) != B._mfrm_exchangeable_rater_identity(target(spec,true))
    for bad in (0.0,-1.0,Inf,NaN,true,"0.4")
        @test_throws ArgumentError target(spec,false;scales=merge(SCALES,(;rater_kernel_sd=bad)))
    end
    @test_throws ArgumentError target(spec,false;scales=(;rater_kernel_sd=0.4))
    @test_throws ArgumentError target(specification(;mixed=true),true)
    @test_throws ArgumentError target(specification(;D=3),true)
end

if test_flag("BAYESIANMGMFRM_CMDSTAN_TESTS")
    @testset "CmdStan exchangeable and compatibility targets (no sampling)" begin
        check = cmdstan_backend_check(;require_ready=true,include_paths=true)
        directory = mkpath(get(ENV,"BAYESIANMGMFRM_EXCHANGEABLE_OUTPUT",mktempdir()))
        for correlated in (false,true)
            family = correlated ? :mfrm_correlated_2d : :mfrm_fixed_q
            compiled = B._cmdstan_compile_model(check,family;cache_dir=joinpath(directory,"$family-build"))
            for R in (2,3,5), K in (2,4), renamed in (false,true)
                t = target(specification(R,K;labels=renamed ? reverse(1:R) : 1:R),correlated)
                x = [0.13sin(i) for i in 1:LD.dimension(t)]
                correlated && (x[end] = atanh(0.4))
                block = reference(t).blueprint.blocks[:rater_free]
                full = B._sum_to_zero_from_raw(fill(SCALES.rater_kernel_sd,R-1),R)
                x[block] .= (renamed ? reverse(full) : full)[1:(R-1)]
                points = [initial_params(t),x]
                for current in (t.base,t)
                    mode = B._cmdstan_generalized_data(current).exchangeable_raters
                    stem = joinpath(directory,"$family-$R-$K-$renamed-$mode")
                    write(stem*"-data.json",B.JSON3.write(B._cmdstan_generalized_data(current)))
                    write(stem*"-points.json",B.JSON3.write((;params_r=points)))
                    results = map((0,1)) do jacobian
                        path = stem*"-$jacobian.csv"
                        B._cmdstan_run(`$(compiled.path) log_prob unconstrained_params=$(stem*"-points.json") jacobian=$jacobian data file=$(stem*"-data.json") output file=$path sig_figs=18 refresh=0`,:density_check)
                        csv = B._cmdstan_read_csv(path,length(points))
                        for (row,point) in enumerate(points)
                            @test csv.values[row,1] ≈ LD.logdensity(current,point) atol=1e-9 rtol=1e-10
                            @test csv.values[row,2:end] ≈ ForwardDiff.gradient(v->LD.logdensity(current,v),point) atol=1e-8 rtol=1e-9
                        end
                        csv.values
                    end
                    @test results[1] == results[2]
                end
            end
            # The raw CLI must reject an ambiguous rater-kernel scale vector.
            t = target(specification(),correlated)
            data = B._cmdstan_generalized_data(t)
            sd = copy(data.reference_sd); sd[first(reference(t).blueprint.blocks[:rater_free])] *= 2
            stem = joinpath(directory,"$family-invalid")
            write(stem*"-data.json",B.JSON3.write(merge(data,(;reference_sd=sd))))
            write(stem*"-points.json",B.JSON3.write((;params_r=[initial_params(t)])))
            @test_throws B.CmdStanError B._cmdstan_run(`$(compiled.path) log_prob unconstrained_params=$(stem*"-points.json") data file=$(stem*"-data.json") output file=$(stem*".csv")`,:density_check)
        end
    end
end

end
