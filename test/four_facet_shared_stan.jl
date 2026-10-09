# Explicit native check: julia --project=. test/four_facet_shared_stan.jl [fresh-output-directory]
module FourFacetSharedStanChecks
using Test, BayesianMGMFRM, ForwardDiff, JSON3, SHA
import LogDensityProblems as L
const B = BayesianMGMFRM
include("../scripts/four_facet_shared_target.jl")
include("../scripts/four_facet_shared_stan.jl")
const F, S = FourFacetSharedTarget, FourFacetSharedStan
const DEFAULT_PRIOR = (.8,.4,.3,.5,.6,.7)
const CASES = (
    (;P=3,T=2,R=2,K=2,dims=[1,1,2,2],scales=DEFAULT_PRIOR),
    (;P=3,T=2,R=2,K=4,dims=[1,1,2,2],scales=DEFAULT_PRIOR),
    (;P=2,T=3,R=3,K=3,dims=[2,1,2,1,2],scales=(1.2,.3,.8,.4,.9,1.1)),
    (;P=3,T=3,R=3,K=5,dims=[2,1,1,2,1,2],scales=(.6,.8,.5,1.1,.3,.25)))

function fixture(case)
    (;P,T,R,K,dims,scales) = case
    # Reverse row order to keep group/criterion indexing independent of row order.
    cells = reverse([(p,t,r,c) for p in 1:P for t in 1:T for r in 1:R for c in eachindex(dims)])
    table = (;person=first.(cells),task=getindex.(cells,2),rater=getindex.(cells,3),
        criterion=last.(cells),score=[mod(p+t+r+c,K) for (p,t,r,c) in cells],
        response=["p$p-t$t" for (p,t,r,c) in cells])
    data = FacetData(table;person=:person,task=:task,rater=:rater,item=:criterion,
        score=:score,response_id=:response,category_levels=0:(K-1))
    q = Bool[dims[c]==d for c in data.item_levels,d in 1:2]
    spec = mfrm_spec(data;dimensions=2,q_matrix=q,thresholds=:partial_credit)
    return F.SharedTaskTarget(spec;prior=NamedTuple{F.SCALE_NAMES}(scales),category_direction=:higher_is_more)
end

function points(target)
    D = L.dimension(target)
    xs = [zeros(D)]
    for sigma in (.05,.4,1.5)
        x = [.2sin(i+sigma) for i in 1:D]
        x[end] = log(sigma)
        push!(xs,x)
    end
    x = [.15cos(i) for i in 1:D]
    x[target.blocks.z] .= 0
    x[end] = log(.7)
    push!(xs,x) # Exact zero shared effect, finite positive scale.
    x = copy(xs[3])
    x[1:2:last(target.blocks.theta)] .= 800
    x[2:2:last(target.blocks.theta)] .= -800
    push!(xs,x) # Stable category normalization under extreme logits.
    x = copy(xs[3]); x[end] = -1000
    push!(xs,x) # exp(log_sigma) underflows; density in log_sigma remains finite.
    return xs
end

function native_checks(directory)
    compiled = S.compile_stan(joinpath(directory,"build"))
    records = NamedTuple[]
    @testset "Four-facet Julia/Stan density, gradient and conditional probabilities" begin
        for (case_id,case) in enumerate(CASES)
            t = fixture(case)
            data = S.stan_data(t)
            @test data.prior_scale == collect(case.scales)
            @test data.criterion_dim == case.dims
            copied = S.stan_data(t); copied.task[1] = 0
            @test t.task[1] != 0
            stale = deepcopy(t); stale.group[1] = 0
            @test_throws ArgumentError S.stan_data(stale)
            xs = points(t)
            prefix = joinpath(directory,"case-$case_id")
            data_path, points_path = prefix*"-data.json",prefix*"-points.json"
            write(data_path,JSON3.write(data))
            write(points_path,JSON3.write((;params_r=xs)))
            expected = [L.logdensity(t,x) for x in xs]
            gradients = [ForwardDiff.gradient(v->L.logdensity(t,v),x) for x in xs]
            outputs = map((0,1)) do jacobian
                path = prefix*"-density-$jacobian.csv"
                B._cmdstan_run(`$(compiled.path) log_prob unconstrained_params=$points_path jacobian=$jacobian data file=$data_path output file=$path sig_figs=18 refresh=0`,:density_check)
                csv = B._cmdstan_read_csv(path,length(xs))
                @test csv.header == ["lp__";["g_beta.$i" for i in 1:L.dimension(t)]]
                @test all(isfinite,csv.values)
                @test all(isapprox.(csv.values[:,1],expected;atol=1e-8,rtol=1e-10))
                @test all(isapprox.(csv.values[:,1].-csv.values[1,1],expected.-expected[1];atol=1e-8,rtol=1e-10))
                for (row,g) in enumerate(gradients)
                    @test all(isapprox.(csv.values[row,2:end],g;atol=1e-8,rtol=1e-9))
                end
                csv.values
            end
            @test outputs[1] == outputs[2]
            csv_path = prefix*"-parameters.csv"
            open(csv_path,"w") do io
                println(io,join(["beta.$i" for i in 1:L.dimension(t)],','))
                for x in xs; println(io,join(x,',')); end
            end
            gq_path = prefix*"-quantities.csv"
            B._cmdstan_run(`$(compiled.path) generate_quantities fitted_params=$csv_path data file=$data_path output file=$gq_path sig_figs=18 refresh=0`,:density_check)
            gq = B._cmdstan_read_csv(gq_path,length(xs))
            logcols = [B._cmdstan_required_column(gq.header,"log_lik.$i") for i in 1:data.N]
            probcols = [B._cmdstan_required_column(gq.header,"log_probs.$i.$k") for i in 1:data.N,k in 1:data.K]
            priorcol = B._cmdstan_required_column(gq.header,"prior_lp")
            prior_error = pointwise_error = probability_error = 0.
            for (row,x) in enumerate(xs)
                ll, lp = F.pointwise_loglikelihood(t,x), F.category_logprobs(t,x)
                actual_probs = reshape(gq.values[row,vec(probcols)],data.N,data.K)
                @test isapprox(gq.values[row,priorcol],F.logprior(t,x);atol=1e-8,rtol=1e-10)
                @test all(isapprox.(gq.values[row,logcols],ll;atol=1e-10,rtol=1e-10))
                @test all(isapprox.(actual_probs,lp;atol=1e-10,rtol=1e-10))
                @test all(isapprox.(sum(exp.(actual_probs);dims=2),1;atol=1e-12,rtol=0))
                prior_error = max(prior_error,abs(gq.values[row,priorcol]-F.logprior(t,x)))
                pointwise_error = max(pointwise_error,maximum(abs.(gq.values[row,logcols].-ll)))
                probability_error = max(probability_error,maximum(abs.(actual_probs.-lp)))
            end
            push!(records,(;case_id,case,N=data.N,D=L.dimension(t),
                target_identity=B._cache_hash(F.target_record(t)),points=length(xs),
                max_density_error=maximum(abs.(outputs[1][:,1].-expected)),
                max_gradient_error=maximum(maximum(abs.(outputs[1][row,2:end].-g)) for (row,g) in enumerate(gradients)),
                max_prior_error=prior_error,max_pointwise_error=pointwise_error,max_logprob_error=probability_error))
        end
        t = fixture(CASES[1]); data = S.stan_data(t)
        points_path = joinpath(directory,"invalid-points.json")
        write(points_path,JSON3.write((;params_r=[zeros(L.dimension(t))])))
        # Native trust boundary: malformed JSON must not silently change the model.
        duplicate = merge(data,NamedTuple{(:person,:task,:rater,:criterion)}(
            Tuple([v[2];v[2:end]] for v in (data.person,data.task,data.rater,data.criterion))))
        invalid = (
            (;reason="incomplete design",data=merge(data,(;P=data.P+1))),
            (;reason="duplicate rating cell",data=duplicate),
            (;reason="response reused across groups",data=merge(data,(;response=ones(Int,data.N)))),
            (;reason="multiple responses in a group",data=merge(data,(;response=[mod1(data.response[1]+1,data.P*data.T);data.response[2:end]]))),
            (;reason="unsupported Q",data=merge(data,(;criterion_dim=ones(Int,data.C)))),
            (;reason="zero prior scale",data=merge(data,(;prior_scale=[0.;data.prior_scale[2:end]]))),
            (;reason="negative prior scale",data=merge(data,(;prior_scale=[-1.;data.prior_scale[2:end]]))))
        for (i,bad) in enumerate(invalid)
            path = joinpath(directory,"invalid-data-$i.json")
            output = joinpath(directory,"invalid-output-$i.csv")
            write(path,JSON3.write(bad.data))
            @test_throws CmdStanError B._cmdstan_run(`$(compiled.path) log_prob unconstrained_params=$points_path data file=$path output file=$output refresh=0`,:density_check)
        end
        # Persist measured errors even if an assertion above fails; the test process determines acceptance.
        B._write_json_record(joinpath(directory,"numerical-comparison.json"),
            (;schema="bayesianmgmfrm.four_facet_shared_stan_check.v1",julia_version=string(VERSION),
                executable=compiled,new_sampling=false,scientific_acceptance=false,
                tolerance=(;density_atol=1e-8,density_rtol=1e-10,gradient_atol=1e-8,
                    gradient_rtol=1e-9,logprob_atol=1e-10,logprob_rtol=1e-10),
                source_sha256=Dict(path=>bytes2hex(sha256(read(path))) for path in
                    (S.STAN_SOURCE,joinpath(@__DIR__,"../scripts/four_facet_shared_target.jl"),
                     joinpath(@__DIR__,"../scripts/four_facet_shared_stan.jl"),@__FILE__)),
                records,rejected_inputs=[bad.reason for bad in invalid]))
    end
end

if isempty(ARGS)
    mktempdir(native_checks)
else
    length(ARGS) == 1 || error("expected one fresh output directory")
    ispath(only(ARGS)) && error("select a fresh output directory")
    native_checks(mkdir(only(ARGS)))
end
end
