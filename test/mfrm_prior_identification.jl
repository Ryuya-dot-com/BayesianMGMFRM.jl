module MFRMPriorIdentificationChecks

using Test, BayesianMGMFRM, LinearAlgebra, ForwardDiff
const B = BayesianMGMFRM
include("test_groups.jl")
const PRIOR = MFRMPrior(person_sd=0.7, rater_sd=0.4, item_sd=0.6, step_sd=0.5)

function specification(R=3, K=4; rater_order=1:R, reverse_rows=false, mixed=false)
    cells = [(p,i,r) for p in 1:3 for i in 1:4 for r in 1:R]
    reverse_rows && reverse!(cells)
    data = FacetData((; person=first.(cells), item=getindex.(cells,2),
        rater=["R$(rater_order[r])" for (p,i,r) in cells],
        score=[mod(p+i+r,K) for (p,i,r) in cells]);
        person=:person, item=:item, rater=:rater, score=:score, category_levels=0:(K-1))
    q = Bool[1 0; 1 0; 0 1; 0 1]
    mixed && (q[2,2] = true)
    return mfrm_spec(data; dimensions=2, q_matrix=q, dimension_labels=["First","Second"])
end

target(spec, correlated) = B._fixed_q_prior_target(
    correlated ? B.Experimental.correlated(spec; lkj_eta=3) : spec, PRIOR)
base(t) = t isa B._MFRMFixedQCorrelated2DLogDensity ? t.base : t
pointwise(t, x) = B._mfrm_fixed_q_pointwise(base(t), x[1:B.LogDensityProblems.dimension(base(t))])
normal_lp(v, sd) = sum(B._normal_logpdf(x, sd) for x in v)
reconstruction(n) = vcat(Matrix{Float64}(I,n-1,n-1), -ones(1,n-1))

@testset "fixed-coefficient reconstructed prior covariance (no sampling)" begin
    for R in (2,3,5), K in (2,3,4,6)
        t = target(specification(R,K), false)
        n = B.LogDensityProblems.dimension(t)
        # Basis images recover the exact covariance of the implemented linear map.
        # These rows are deterministic basis vectors, not simulated prior draws.
        basis = Matrix(Diagonal([B._source_fixture_prior_sd(t,i) for i in 1:n]))
        rows = B._mfrm_fixed_q_model_coordinates(t, basis)
        rater = hcat([r.values for r in rows if r.block === :rater]...)
        steps = hcat([r.values for r in rows if r.block === :item_steps]...)
        C = reconstruction(R)
        covariance = PRIOR.rater_sd^2 .* (C*C')
        @test rater' * rater ≈ covariance atol=1e-12
        @test diag(covariance) ≈ PRIOR.rater_sd^2 .* [ones(R-1); R-1]
        @test covariance[1,end] ≈ -PRIOR.rater_sd^2
        @test covariance[1,1] + covariance[end,end] - 2covariance[1,end] ≈ (R+2)*PRIOR.rater_sd^2
        R > 2 && @test covariance[1,1] + covariance[2,2] - 2covariance[1,2] ≈ 2PRIOR.rater_sd^2
        expected = zeros(K,K)
        expected[2:end,2:end] = PRIOR.step_sd^2 .* (reconstruction(K-1)*reconstruction(K-1)')
        for i in 1:4
            block = steps[:,((i-1)*K+1):(i*K)]
            @test block' * block ≈ expected atol=1e-12
            @test all(iszero, block[:,1])
            @test expected[end,end] ≈ (K-2)*PRIOR.step_sd^2
        end
        @test iszero(rater' * steps)
        @test iszero(steps[:,1:K]' * steps[:,(K+1):2K])
    end
end

@testset "changing the free chart versus changing the prior (no sampling)" begin
    for n in (2,3,5), sd in (0.4,1.2)
        C = reconstruction(n)
        permutation = reverse(1:n)
        T = C[permutation[1:(n-1)],:]
        v = sd .* ones(n-1)
        u = T*v
        @test C*v ≈ B._sum_to_zero_from_raw(v,n)
        @test C*u ≈ (C*v)[permutation]
        @test abs(det(T)) ≈ 1 atol=1e-12
        # Carrying the old density into the new chart preserves its meaning.
        carried = B.Turing.MvNormal(zeros(n-1), sd^2 .* (T*T'))
        @test B.Turing.logpdf(carried,u) ≈ normal_lp(v,sd) atol=1e-12
        # Resetting the same independent free normals generally changes it.
        @test normal_lp(u,sd)-normal_lp(v,sd) ≈ -n*(n-2)/2 atol=1e-12
        # Existing normalized zero-sum correction supplies a distinct symmetric reference.
        covariance = sd^2 .* (Matrix{Float64}(I,n-1,n-1)-ones(n-1,n-1)/n)
        exchangeable = B.Turing.MvNormal(zeros(n-1), covariance)
        lp = normal_lp(v,sd) + B._zero_sum_prior_correction(v,sd)
        @test lp ≈ B.Turing.logpdf(exchangeable,v) atol=1e-12
        @test lp ≈ normal_lp(u,sd) + B._zero_sum_prior_correction(u,sd) atol=1e-12
        full_covariance = C*covariance*C'
        @test full_covariance ≈ sd^2 .* (Matrix{Float64}(I,n,n)-ones(n,n)/n) atol=1e-12
        @test diag(full_covariance) ≈ fill(sd^2*(n-1)/n,n)
        @test full_covariance[permutation,permutation] ≈ full_covariance atol=1e-12
    end
end

@testset "fixed-coefficient rater relabelling and row order (no sampling)" begin
    for correlated in (false,true), R in (2,3,5), K in (2,4)
        original = target(specification(R,K),correlated)
        renamed = target(specification(R,K; rater_order=reverse(1:R)),correlated)
        shuffled = target(specification(R,K; reverse_rows=true),correlated)
        n = B.LogDensityProblems.dimension(original)
        x = [0.13sin(i) for i in 1:n]
        correlated && (x[end] = atanh(0.4))
        block = base(original).blueprint.blocks[:rater_free]
        for amplitude in (0.0,1.0)
            x[block] .= amplitude*PRIOR.rater_sd
            y = copy(x)
            y[block] .= reverse(B._sum_to_zero_from_raw(x[block],R))[1:(R-1)]
            @test pointwise(original,x) ≈ pointwise(renamed,y) atol=1e-12
            delta = -amplitude^2*R*(R-2)/2
            @test logprior(renamed,y)-logprior(original,x) ≈ delta atol=1e-12
            @test B.LogDensityProblems.logdensity(renamed,y)-B.LogDensityProblems.logdensity(original,x) ≈ delta atol=1e-10
        end
        @test base(original).design.spec.data.rater_levels == base(shuffled).design.spec.data.rater_levels
        @test pointwise(shuffled,x) ≈ reverse(pointwise(original,x)) atol=1e-12
        @test logprior(shuffled,x) == logprior(original,x)
        @test B.LogDensityProblems.logdensity(shuffled,x) ≈ B.LogDensityProblems.logdensity(original,x) atol=1e-10
    end
end

@testset "likelihood location freedom and fixed ability scales (no sampling)" begin
    for (correlated,mixed) in ((false,false),(false,true),(true,false))
        spec = specification(; mixed)
        t = target(spec,correlated)
        n = B.LogDensityProblems.dimension(t)
        x = [0.13cos(i) for i in 1:n]
        correlated && (x[end] = atanh(0.4))
        blocks = base(t).blueprint.blocks
        c = [0.25,-0.4]
        shift = zeros(n)
        shift[blocks[:person]] .= repeat(c,3)
        shift[blocks[:item]] .= spec.q_matrix*c
        rho = correlated ? tanh(x[end]) : 0.0
        covariance = PRIOR.person_sd^2 .* [1 rho; rho 1]
        expected_delta = sum(-dot(x[i:i+1],covariance\c)-dot(c,covariance\c)/2 for i in 1:2:6)
        item, item_shift = x[blocks[:item]], shift[blocks[:item]]
        expected_delta -= (2dot(item,item_shift)+dot(item_shift,item_shift))/(2PRIOR.item_sd^2)
        @test pointwise(t,x+shift) ≈ pointwise(t,x) atol=1e-12
        @test logprior(t,x+shift)-logprior(t,x) ≈ expected_delta atol=1e-11
        @test abs(expected_delta) > 0.1
        @test abs(ForwardDiff.derivative(a -> sum(pointwise(t,x+a*shift)),0.0)) < 1e-10
        curvature = ForwardDiff.derivative(a -> ForwardDiff.derivative(b -> logprior(t,x+b*shift),a),0.0)
        @test curvature ≈ -3dot(c,covariance\c)-dot(item_shift,item_shift)/PRIOR.item_sd^2 atol=1e-10
        @test diag(covariance) == fill(PRIOR.person_sd^2,2)
        # Exchange names of both ability dimensions and their Q columns together.
        swapped = mfrm_spec(spec.data; dimensions=2, q_matrix=spec.q_matrix[:,[2,1]],
            dimension_labels=reverse(spec.dimension_labels))
        other = target(swapped,correlated)
        y = copy(x)
        y[blocks[:person]] .= vec(reshape(x[blocks[:person]],2,3)[[2,1],:])
        @test pointwise(other,y) ≈ pointwise(t,x) atol=1e-12
        @test logprior(other,y) ≈ logprior(t,x) atol=1e-12
    end
end

if test_flag("BAYESIANMGMFRM_CMDSTAN_TESTS")
    @testset "CmdStan relabelled and location-shifted densities (no sampling)" begin
        check = cmdstan_backend_check(; require_ready=true, include_paths=true)
        directory = mkpath(get(ENV,"BAYESIANMGMFRM_IDENTIFICATION_OUTPUT",mktempdir()))
        for correlated in (false,true)
            family = correlated ? :mfrm_correlated_2d : :mfrm_fixed_q
            compiled = B._cmdstan_compile_model(check,family; cache_dir=joinpath(directory,"$family-build"))
            for R in (3,5), K in (2,4), renamed in (false,true)
                spec = specification(R,K; rater_order=renamed ? reverse(1:R) : 1:R)
                t = target(spec,correlated)
                blocks = base(t).blueprint.blocks
                x = [0.13sin(i) for i in 1:B.LogDensityProblems.dimension(t)]
                correlated && (x[end] = atanh(0.4))
                severities = B._sum_to_zero_from_raw(fill(PRIOR.rater_sd,R-1),R)
                x[blocks[:rater_free]] .= (renamed ? reverse(severities) : severities)[1:(R-1)]
                zero_raters = copy(x); zero_raters[blocks[:rater_free]] .= 0
                shifted = copy(x)
                shifted[blocks[:person]] .+= repeat([0.25,-0.4],3)
                shifted[blocks[:item]] .+= spec.q_matrix*[0.25,-0.4]
                points = [zero_raters,x,shifted]
                stem = joinpath(directory,"$family-$R-$K-$renamed")
                write(stem*"-data.json",B.JSON3.write(B._cmdstan_generalized_data(t)))
                write(stem*"-points.json",B.JSON3.write((;params_r=points)))
                results = map((0,1)) do jacobian
                    path = stem*"-$jacobian.csv"
                    B._cmdstan_run(`$(compiled.path) log_prob unconstrained_params=$(stem*"-points.json") jacobian=$jacobian data file=$(stem*"-data.json") output file=$path sig_figs=18 refresh=0`,:density_check)
                    csv = B._cmdstan_read_csv(path,length(points))
                    for (row,point) in enumerate(points)
                        @test csv.values[row,1] ≈ B.LogDensityProblems.logdensity(t,point) atol=1e-9 rtol=1e-10
                        @test csv.values[row,2:end] ≈ ForwardDiff.gradient(v->B.LogDensityProblems.logdensity(t,v),point) atol=1e-8 rtol=1e-9
                    end
                    csv.values
                end
                @test results[1] == results[2]
            end
        end
    end
end

end
