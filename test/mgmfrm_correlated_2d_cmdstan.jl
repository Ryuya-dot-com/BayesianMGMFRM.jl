module MGMFRMCorrelated2DCmdStanChecks
using Test, BayesianMGMFRM, ForwardDiff, LinearAlgebra
import JSON3
const B = BayesianMGMFRM
include("test_groups.jl")

# Every category occurs for each person/item/rater, so log_lik also checks
# the entire categorical probability vector, including the reconstructed rater.
function specification(K=4;labels=["First","Second"],q=Bool[1 0;0 1;1 0;0 1])
    cells = [(p,i,r,k) for p in 1:3 for i in 1:4 for r in 1:3 for k in 0:(K-1)]
    data = FacetData((;person=first.(cells),item=getindex.(cells,2),
        rater=getindex.(cells,3),score=last.(cells));
        person=:person,item=:item,rater=:rater,score=:score,category_levels=0:(K-1))
    return mfrm_spec(data;family=:mgmfrm,dimensions=2,
        q_matrix=q,dimension_labels=labels)
end
const SCALES = (;person_sd=0.7,rater_sd=0.4,item_sd=0.6,
    log_discrimination_sd=0.3,log_consistency_sd=0.2,step_sd=0.5)
target(spec=specification();eta=2,scales=SCALES) =
    B._mgmfrm_free_latent_correlation_2d_logdensity(spec;
        prior=B._SourceFixturePrior(;scales...),lkj_eta=eta)

# Equation-level oracle with an ordinary covariance solve; only used away
# from rho saturation. No package reconstruction or likelihood helper is used.
function equation(t,x)
    spec=t.base.design.spec; data=spec.data; blocks=t.base.blueprint.blocks
    J=length(data.person_levels); R=length(data.rater_levels)
    I=length(data.item_levels); K=length(data.category_levels)
    theta=reshape(x[blocks[:person]],2,J)
    free_r=x[blocks[:rater_free]]; rater=[free_r;-sum(free_r)]
    item=x[blocks[:item]]
    loading=exp.(x[blocks[:log_item_dimension_discrimination]])
    free_c=x[blocks[:log_rater_consistency_free]]; consistency=exp.([free_c;-sum(free_c)])
    free_s=reshape(x[blocks[:item_steps]],K-2,I)
    steps=vcat(free_s,-sum(free_s;dims=1))
    pointwise=map(1:data.n) do n
        p,r,i,k=data.person[n],data.rater[n],data.item[n],data.category[n]
        d=findfirst(spec.q_matrix[i,:])
        eta=[zero(eltype(x));cumsum(1.7*consistency[r].*(loading[i]*theta[d,p]-item[i]-rater[r].-steps[:,i]))]
        m=maximum(eta)
        eta[k]-m-log(sum(exp.(eta.-m)))
    end
    rho=tanh(last(x)); sigma=t.prior.source_prior.person_sd
    covariance=sigma^2 .* [one(rho) rho;rho one(rho)]
    prior=sum(-(2log(2pi)+logdet(covariance)+dot(theta[:,p],covariance\theta[:,p]))/2 for p in 1:J)
    for (block,scale) in ((:rater_free,:rater_sd),(:item,:item_sd),
            (:log_item_dimension_discrimination,:log_discrimination_sd),
            (:log_rater_consistency_free,:log_consistency_sd),(:item_steps,:step_sd))
        sd=getproperty(t.prior.source_prior,scale)
        for i in blocks[block]
            prior -= log(sd)+(log(2pi)+(x[i]/sd)^2)/2
        end
    end
    beta=Dict(1=>2.0,2=>4/3,5=>256/315)[t.prior.lkj_eta]
    prior += -log(beta)+t.prior.lkj_eta*log1p(-rho^2)
    return (;pointwise,logposterior=prior+sum(pointwise))
end

@testset "generalized correlation target and transport (no sampling)" begin
    for K in (3,4), eta in (1,2,5)
        spec=specification(K); t=target(spec;eta); n=B.LogDensityProblems.dimension(t)
        contract=B._mgmfrm_correlated_2d_contract(t)
        identity=B._mgmfrm_correlated_2d_identity(t)
        @test contract.likelihood_scale==1.7 && contract.base_prior===:independent_normal_raw_coordinates
        @test contract.scales==SCALES && contract.lkj_eta==eta
        @test contract.density_measure===:d_raw_d_zrho && contract.correlation_prior_measure===:d_rho
        @test identity==B._mgmfrm_correlated_2d_identity(target(deepcopy(spec);eta))
        @test identity!=B._mgmfrm_correlated_2d_identity(target(spec;eta=eta+1))
        for name in keys(SCALES)
            @test identity!=B._mgmfrm_correlated_2d_identity(target(spec;eta,
                scales=merge(SCALES,NamedTuple{(name,)}((2*SCALES[name],)))))
        end
        changed=specification(K;labels=["renamed","Second"])
        @test identity!=B._mgmfrm_correlated_2d_identity(target(changed;eta))
        data=B._cmdstan_generalized_data(t)
        @test B._cmdstan_generalized_family(t)===:mgmfrm_correlated_2d
        @test data.D==2 && data.P==n-1 && data.NLoadings==data.I && data.lkj_eta==eta
        @test !hasproperty(data,:prior_model) && !hasproperty(data,:source_rater)
        for z in (-2.0,0.0,0.7)
            x=[0.2sin(i) for i in 1:n];x[end]=z
            reference=equation(t,x)
            @test B.LogDensityProblems.logdensity(t,x)≈reference.logposterior atol=1e-10
            @test ForwardDiff.gradient(v->B.LogDensityProblems.logdensity(t,v),x)≈
                ForwardDiff.gradient(v->equation(t,v).logposterior,x) atol=1e-9 rtol=1e-9
            @test B._mgmfrm_free_latent_correlation_2d_pointwise_loglikelihood(t,x)≈reference.pointwise atol=1e-12
            @test B._cmdstan_generalized_initial(t,x)==(;beta=x[1:end-1],zrho=z)
            if z==0
                base_lp=B.LogDensityProblems.logdensity(t.base,x[1:end-1])
                @test reference.logposterior≈base_lp-t.prior.log_beta_half_eta atol=1e-10
            end
        end
        for bad in (zeros(n-1),zeros(n+1),fill(NaN,n),fill(Inf,n))
            @test_throws ArgumentError B._cmdstan_generalized_initial(t,bad)
        end
        @test_throws ArgumentError B.Experimental.fit(t)
        @test !B.Experimental.free_latent_correlation_2d_contract().fit_enabled
        # Named-column parsing must bind z and reject wrong pointwise/prior values.
        x=[0.1sin(i) for i in 1:n];x[end]=0.4
        ref=equation(t,x)
        header=["lp__","accept_stat__","stepsize__","treedepth__","n_leapfrog__","divergent__","energy__",
            "zrho",["beta.$i" for i in 1:(n-1)]...,["log_lik.$i" for i in eachindex(ref.pointwise)]...]
        values=[ref.logposterior,0.8,0.03,1,1,0,10,x[end],x[1:end-1]...,ref.pointwise...]
        mktempdir() do dir
            path=joinpath(dir,"synthetic.csv")
            save()=write(path,join(reverse(header),',')*"\n"*join(reverse(values),',')*"\n")
            save(); parsed=B._cmdstan_generalized_chain_result(path,t,2,1)
            @test parsed.draws==reshape(x,1,:) && only(parsed.stats).chain==2
            @test only(parsed.logps)≈ref.logposterior atol=1e-10
            for i in (1,8,length(values))
                old=values[i]; values[i]+=0.5;save()
                @test_throws CmdStanError B._cmdstan_generalized_chain_result(path,t,2,1)
                values[i]=old
            end
            header[8]="absent_zrho";save()
            @test_throws CmdStanError B._cmdstan_generalized_chain_result(path,t,2,1)
        end
        spec.q_matrix.=false
        @test identity==B._mgmfrm_correlated_2d_identity(t) # caller's spec was snapshotted
    end
    spec=specification(;q=Bool[1 1;0 1;1 0;0 1])
    @test_throws ArgumentError target(spec)
end

function native_checks(directory)
    check=cmdstan_backend_check(;require_ready=true,include_paths=true)
    compiled=B._cmdstan_compile_model(check,:mgmfrm_correlated_2d;cache_dir=joinpath(directory,"build"))
    records=NamedTuple[]
    for K in (3,4), eta in (1,2,5,10000)
        t=target(specification(K);eta);n=B.LogDensityProblems.dimension(t)
        points=[[0.2sin(i) for i in 1:n] for _ in 1:5]
        for (x,z) in zip(points,(-2.0,-0.4,0.0,0.7,2.0));x[end]=z;end
        for z in (-1000.0,-20.0,20.0,1000.0),level in (0.0,0.7)
            x=initial_params(t);x[end]=z;x[1:2:6].=level;x[2:2:6].=sign(z)*level
            push!(points,x)
        end
        # A squared contribution may underflow while its first derivative is finite.
        for z in (-372.0,372.0)
            x=initial_params(t);x[1]=nextfloat(0.0);x[end]=z;push!(points,x)
        end
        data=B._cmdstan_generalized_data(t)
        prefix=joinpath(directory,"$K-$eta")
        data_path=prefix*"-data.json";points_path=prefix*"-points.json"
        write(data_path,JSON3.write(data));write(points_path,JSON3.write((;params_r=points)))
        expected=[B.LogDensityProblems.logdensity(t,x) for x in points]
        gradients=[ForwardDiff.gradient(v->B.LogDensityProblems.logdensity(t,v),x) for x in points]
        outputs=map((0,1)) do jacobian
            path=prefix*"-density-$jacobian.csv"
            B._cmdstan_run(`$(compiled.path) log_prob unconstrained_params=$points_path jacobian=$jacobian data file=$data_path output file=$path sig_figs=18 refresh=0`,:density_check)
            csv=B._cmdstan_read_csv(path,length(points))
            @test csv.header==["lp__";["g_beta.$i" for i in 1:(n-1)];"g_zrho"]
            @test all(isfinite,csv.values)
            @test all(isapprox.(csv.values[:,1],expected;atol=1e-8,rtol=1e-10))
            @test all(isapprox.(csv.values[:,1].-csv.values[1,1],expected.-expected[1];atol=1e-8,rtol=1e-10))
            for (row,g) in enumerate(gradients)
                @test all(isapprox.(csv.values[row,2:end],g;atol=1e-8,rtol=1e-9))
            end
            csv.values
        end
        @test outputs[1]==outputs[2]
        # Standalone generated quantities evaluate declared points, with no sampler.
        # Stan's CSV reader turns out-of-range lexical conversions of subnormal
        # numbers into NaN. Those two cases retain JSON log_prob/gradient checks;
        # GQ uses the remaining points (including exact zero and saturated rho).
        gq_points=filter(x->all(v->v==0 || abs(v)>=floatmin(Float64),x),points)
        csv_path=prefix*"-parameters.csv"
        open(csv_path,"w") do io
            println(io,join([["beta.$i" for i in 1:(n-1)];"zrho"],','))
            for x in gq_points;println(io,join(x,','));end
        end
        gq_path=prefix*"-quantities.csv"
        B._cmdstan_run(`$(compiled.path) generate_quantities fitted_params=$csv_path data file=$data_path output file=$gq_path sig_figs=18 refresh=0`,:density_check)
        gq=B._cmdstan_read_csv(gq_path,length(gq_points))
        logcols=[B._cmdstan_required_column(gq.header,"log_lik.$i") for i in 1:data.N]
        rhocol=B._cmdstan_required_column(gq.header,"rho")
        for (row,x) in enumerate(gq_points)
            actual=gq.values[row,logcols]
            @test actual≈B._mgmfrm_free_latent_correlation_2d_pointwise_loglikelihood(t,x) atol=1e-10 rtol=1e-10
            @test all(isapprox.(vec(sum(reshape(exp.(actual),K,:);dims=1)),1;atol=1e-12))
            @test gq.values[row,rhocol]==tanh(last(x))
        end
        push!(records,(;K,eta,identity=B._mgmfrm_correlated_2d_identity(t),points=length(points),
            generated_quantities_points=length(gq_points),
            max_density_error=maximum(abs.(outputs[1][:,1].-expected)),
            max_gradient_error=maximum(maximum(abs.(outputs[1][row,2:end].-g)) for (row,g) in enumerate(gradients))))
    end
    t=target();data=B._cmdstan_generalized_data(t)
    points_path=joinpath(directory,"invalid-points.json")
    write(points_path,JSON3.write((;params_r=[initial_params(t)])))
    bad_scales=copy(data.prior_sd);bad_scales[2]*=2
    invalid=(merge(data,(;D=3)),merge(data,(;lkj_eta=0)),merge(data,(;lkj_eta=10001)),
        merge(data,(;P=data.P+1,prior_sd=[data.prior_sd;1])),merge(data,(;free_steps=3)),
        merge(data,(;prior_sd=zeros(data.P))),merge(data,(;prior_sd=bad_scales)),
        merge(data,(;LoadingItem=[1,1,3,4])),merge(data,(;LoadingDim=ones(Int,4))),
        merge(data,(;ItemID=ones(Int,data.N))))
    for (i,bad) in enumerate(invalid)
        path=joinpath(directory,"invalid-data-$i.json");write(path,JSON3.write(bad))
        output=joinpath(directory,"invalid-output-$i.csv")
        @test_throws CmdStanError B._cmdstan_run(`$(compiled.path) log_prob unconstrained_params=$points_path data file=$path output file=$output refresh=0`,:density_check)
    end
    B._write_json_record(joinpath(directory,"numerical-comparison.json"),
        (;julia_version=string(VERSION),cmdstan_version=check.cmdstan_version,executable=compiled,
            new_sampling=false,scientific_acceptance=false,records))
end

if test_flag("BAYESIANMGMFRM_CMDSTAN_TESTS")
    @testset "CmdStan generalized correlated density, gradient and probabilities" begin
        root=get(ENV,"BAYESIANMGMFRM_GENERALIZED_CORRELATION_OUTPUT",nothing)
        root===nothing ? mktempdir(native_checks) : native_checks(mkpath(root))
    end
end
end
