module MFRMCorrelated2DChecks

using Test, BayesianMGMFRM, ForwardDiff, LinearAlgebra
import JSON3
const B = BayesianMGMFRM
include("test_groups.jl")

function specification(categories=4; mixed=false)
    cells = [(p,i,r) for p in 1:3 for i in 1:4 for r in 1:2]
    data = FacetData((; person=first.(cells), item=getindex.(cells,2), rater=last.(cells),
        score=[mod(sum(c),categories) for c in cells]);
        person=:person,item=:item,rater=:rater,score=:score,category_levels=0:(categories-1))
    q = Bool[1 0; 1 0; 0 1; 0 1]
    mixed && (q[2,2] = true)
    return mfrm_spec(data; dimensions=2, q_matrix=q, dimension_labels=["First","Second"])
end

const PRIOR = MFRMPrior(person_sd=0.7, rater_sd=0.4, item_sd=0.6, step_sd=0.5)
const BETA_NORMALIZERS = Dict(1=>2.0, 2=>4/3, 5=>256/315)

# Independent covariance-matrix formula, used away from numerical saturation.
function matrix_prior(target, x)
    z, sd = last(x), target.base.prior.person_sd
    rho = tanh(z)
    covariance = sd^2 .* [one(rho) rho; rho one(rho)]
    person = target.base.blueprint.blocks[:person]
    lp = -log(BETA_NORMALIZERS[target.lkj_eta]) +
        (target.lkj_eta-1)*log1p(-rho^2) + log1p(-rho^2)
    for i in first(person):2:last(person)
        theta = x[i:i+1]
        lp -= (2log(2pi) + logdet(covariance) + dot(theta, covariance \ theta))/2
    end
    for i in (last(person)+1):(length(x)-1)
        sigma = B._source_fixture_prior_sd(target.base,i)
        lp -= log(sigma) + (log(2pi)+(x[i]/sigma)^2)/2
    end
    return lp
end

@testset "correlated fixed-coefficient MFRM density (no sampling)" begin
    for categories in (2,4), eta in (1,2,5)
        spec = specification(categories)
        target = B._MFRMFixedQCorrelated2DLogDensity(spec; prior=PRIOR,lkj_eta=eta)
        n = B.LogDensityProblems.dimension(target)
        x = [0.2sin(i) for i in 1:n]; x[end] = 0
        base_density = v -> B.LogDensityProblems.logdensity(target.base,v)
        density = v -> B.LogDensityProblems.logdensity(target,v)
        identity = B._mfrm_correlated_2d_identity(target)
        @test initial_params(target) == zeros(n)
        @test n == B.LogDensityProblems.dimension(target.base)+1
        @test target.blueprint.parameter_names[1:end-1] == target.base.blueprint.parameter_names
        @test target.blueprint.blocks[:z_latent_correlation] == n:n
        @test density(x) ≈ base_density(x[1:end-1])-log(BETA_NORMALIZERS[eta]) atol=1e-11
        g = ForwardDiff.gradient(density,x)
        @test g[1:end-1] ≈ ForwardDiff.gradient(base_density,x[1:end-1]) atol=1e-11
        @test g[end] ≈ sum(x[i]*x[i+1]/PRIOR.person_sd^2 for i in 1:2:6) atol=1e-11
        for z in (-2.0,-0.4,0.0,0.7,2.0)
            x[end] = z
            @test logprior(target,x) ≈ matrix_prior(target,x) atol=1e-10
            @test ForwardDiff.gradient(v->logprior(target,v),x) ≈
                ForwardDiff.gradient(v->matrix_prior(target,v),x) atol=1e-8 rtol=1e-9
            @test density(x)-logprior(target,x) ≈
                base_density(x[1:end-1])-logprior(target.base,x[1:end-1]) atol=1e-10
            finite_difference = [(density(x + 1e-5*I(n)[:,i])-density(x - 1e-5*I(n)[:,i]))/2e-5 for i in 1:n]
            @test ForwardDiff.gradient(density,x) ≈ finite_difference atol=2e-6 rtol=1e-7
        end
        @test identity != B._mfrm_fixed_q_identity(target.base)
        changed = B._MFRMFixedQCorrelated2DLogDensity(spec; prior=PRIOR,lkj_eta=eta+1)
        @test identity != B._mfrm_correlated_2d_identity(changed)
        @test identity != B._mfrm_correlated_2d_identity(B._MFRMFixedQCorrelated2DLogDensity(spec))
        contract = B._mfrm_correlated_2d_contract(target)
        @test contract.ability_sd == PRIOR.person_sd && contract.correlation_prior_measure === :d_rho
        @test contract.density_measure === :d_beta_d_zrho && !contract.fitting_available && !contract.cache_available
        @test model_manifest(spec; view=:public).spec.latent_correlation === :identity_fixed
        @test_throws ArgumentError B.Experimental.fit(target)
        @test_throws ArgumentError B.Experimental.free_latent_correlation_2d_candidate(spec)
        @test B._cmdstan_generalized_family(target) === :mfrm_correlated_2d
        for bad in (x[1:end-1], [x;0.0], fill(NaN,n),fill(Inf,n))
            @test_throws ArgumentError density(bad)
        end
        before = density(x)
        spec.q_matrix .= false; spec.dimension_labels[1] = "changed"
        @test density(x) == before && B._mfrm_correlated_2d_identity(target) == identity
    end
    spec = specification()
    for eta in (true,0,-1,1.5,NaN,Inf,"2",10001,big"1e500")
        @test_throws ArgumentError B._MFRMFixedQCorrelated2DLogDensity(spec; lkj_eta=eta)
    end
    @test_throws ArgumentError B._MFRMFixedQCorrelated2DLogDensity(specification(;mixed=true))
    @test_throws ArgumentError B._MFRMFixedQCorrelated2DLogDensity(mfrm_spec(spec.data))
    @test_throws ArgumentError B._MFRMFixedQCorrelated2DLogDensity(B._mfrm_fixed_q_reference_spec(spec))
    stale=deepcopy(spec); empty!(stale.constraints)
    @test_throws ArgumentError B._MFRMFixedQCorrelated2DLogDensity(stale)
    target=B._MFRMFixedQCorrelated2DLogDensity(spec; prior=PRIOR)
    for z in (-1000.0,-20.0,20.0,1000.0), level in (0.0,0.7)
        x=initial_params(target); x[end]=z
        x[1:2:6] .= level; x[2:2:6] .= sign(z)*level
        @test isfinite(B.LogDensityProblems.logdensity(target,x))
        @test all(isfinite,ForwardDiff.gradient(v->B.LogDensityProblems.logdensity(target,v),x))
    end
end

if test_flag("BAYESIANMGMFRM_CMDSTAN_TESTS")
    @testset "CmdStan correlated density and gradient (no sampling)" begin
        check=cmdstan_backend_check(;require_ready=true,include_paths=true)
        output=get(ENV,"BAYESIANMGMFRM_CORRELATION_OUTPUT",nothing)
        directory=output === nothing ? mktempdir() : mkpath(output)
        compiled=B._cmdstan_compile_model(check,:mfrm_correlated_2d;cache_dir=joinpath(directory,"build"))
        independent=B._cmdstan_compile_model(check,:mfrm_fixed_q;cache_dir=joinpath(directory,"independent-build"))
        for categories in (2,4)
            target=B._MFRMFixedQReferenceLogDensity(specification(categories);prior=PRIOR)
            n=B.LogDensityProblems.dimension(target)
            points=[zeros(n), [0.2sin(i) for i in 1:n]]
            data=B._cmdstan_generalized_data(target)
            data_path=joinpath(directory,"independent-data-$categories.json")
            points_path=joinpath(directory,"independent-points-$categories.json")
            write(data_path,JSON3.write(data));write(points_path,JSON3.write((;params_r=points)))
            for jacobian in (0,1)
                path=joinpath(directory,"independent-density-$categories-$jacobian.csv")
                B._cmdstan_run(`$(independent.path) log_prob unconstrained_params=$points_path jacobian=$jacobian data file=$data_path output file=$path sig_figs=18 refresh=0`,:density_check)
                csv=B._cmdstan_read_csv(path,length(points))
                for (row,x) in enumerate(points)
                    # This model explicitly calls normal_lpdf, retaining its normalizer.
                    @test csv.values[row,1] ≈ B.LogDensityProblems.logdensity(target,x) atol=1e-10
                    @test csv.values[row,2:end] ≈ ForwardDiff.gradient(v->B.LogDensityProblems.logdensity(target,v),x) atol=1e-10
                end
            end
        end
        for categories in (2,4), eta in (1,2,5)
            target=B._MFRMFixedQCorrelated2DLogDensity(specification(categories);prior=PRIOR,lkj_eta=eta)
            n=B.LogDensityProblems.dimension(target)
            points=[[0.2sin(i) for i in 1:n] for _ in 1:5]
            for (x,z) in zip(points,(-2.0,-0.4,0.0,0.7,2.0)); x[end]=z; end
            for z in (-1000.0,-20.0,20.0,1000.0), level in (0.0,0.7)
                x=initial_params(target);x[end]=z;x[1:2:6].=level;x[2:2:6].=sign(z)*level
                push!(points,x)
            end
            # Shared Stan quadratic: underflowed value must retain its finite gradient.
            for z in (-372.0,372.0)
                x=initial_params(target);x[1]=nextfloat(0.0);x[end]=z
                push!(points,x)
            end
            data_path=joinpath(directory,"data-$categories-$eta.json")
            points_path=joinpath(directory,"points-$categories-$eta.json")
            write(data_path,JSON3.write(B._cmdstan_mfrm_correlated_2d_data(target)))
            write(points_path,JSON3.write((;params_r=points)))
            values=map((0,1)) do jacobian
                path=joinpath(directory,"density-$categories-$eta-$jacobian.csv")
                B._cmdstan_run(`$(compiled.path) log_prob unconstrained_params=$points_path jacobian=$jacobian data file=$data_path output file=$path sig_figs=18 refresh=0`,:density_check)
                csv=B._cmdstan_read_csv(path,length(points))
                @test csv.header == ["lp__"; ["g_beta.$i" for i in 1:(n-1)]; "g_zrho"]
                expected=[B.LogDensityProblems.logdensity(target,x) for x in points]
                @test csv.values[:,1] ≈ expected atol=1e-8 rtol=1e-10
                @test csv.values[:,1].-csv.values[1,1] ≈ expected.-expected[1] atol=1e-8 rtol=1e-10
                gradient_error=0.0
                for (row,x) in enumerate(points)
                    gradient=ForwardDiff.gradient(v->B.LogDensityProblems.logdensity(target,v),x)
                    @test csv.values[row,2:end] ≈ gradient atol=1e-8 rtol=1e-9
                    gradient_error=max(gradient_error,maximum(abs.(csv.values[row,2:end].-gradient)))
                end
                @info "Correlated density comparison" categories eta jacobian max_density_error=maximum(abs.(csv.values[:,1].-expected)) max_gradient_error=gradient_error
                csv.values
            end
            @test values[1] == values[2] # Both parameters are unconstrained; manual Jacobian remains in either mode.
        end
        target=B._MFRMFixedQCorrelated2DLogDensity(specification();prior=PRIOR)
        data=B._cmdstan_mfrm_correlated_2d_data(target)
        points_path=joinpath(directory,"bad-points.json")
        write(points_path,JSON3.write((;params_r=[initial_params(target)])))
        sd=copy(data.reference_sd); sd[2]*=2
        for bad in (merge(data,(;D=3)),merge(data,(;lkj_eta=0)),merge(data,(;lkj_eta=10001)),
                merge(data,(;reference_sd=zeros(length(sd)))),merge(data,(;reference_sd=sd)))
            path=joinpath(directory,"bad-data.json");write(path,JSON3.write(bad))
            @test_throws B.CmdStanError B._cmdstan_run(`$(compiled.path) log_prob unconstrained_params=$points_path data file=$path`,:density_check)
        end
        println("Density-check artifacts: ",directory)
    end
end

end
