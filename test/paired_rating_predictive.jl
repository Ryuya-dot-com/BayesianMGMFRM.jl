module PairedRatingPredictiveChecks

using Test, Random, LinearAlgebra, Statistics
include(joinpath(@__DIR__,"..","scripts","paired_rating_reference.jl"))
const A=PairedRatingReference
const PRIOR=(;word_sd=1.0,rater_sd=(0.5,0.6),step_sd=(0.7,0.8),
    recording_log_sd_mean=(log(0.5),log(0.6)),recording_log_sd_sd=(0.5,0.6),
    person_lkj_eta=2,recording_lkj_eta=5)
rows(K=4)=[(;person="P$p",word="W$w",recording="S$p-$w",rater="R$r",criterion="C$c",score=mod(p+w+r+c,K))
    for (p,w) in ((1,1),(1,2),(2,2),(2,3),(3,1),(3,3)) for r in 1:3 for c in 1:2
    if !(p==1 && w==1 && r==1 && c==1)]
target(K=4)=A.Target(rows(K);categories=K,criteria=["C1","C2"],prior=PRIOR)
newrows()=[(;person="P$p",word="W$w",recording="NEW$p-$w",rater="R$r",criterion="C$c")
    for (p,w) in ((1,3),(2,1),(3,2)) for r in 1:3 for c in 1:2]

# Separate PCM formula and Gaussian quadrature provide an oracle for marginal
# integration. No simulator helper or product of marginal probabilities is used.
function pcm(eta,steps)
    logits=[k*eta-sum(steps[2:k+1]) for k in 0:length(steps)-1]
    weights=exp.(logits.-maximum(logits));weights/sum(weights)
end
function marginal(t,q,row)
    x=A.coordinates(t,q);d=t.data
    c=findfirst(==(row.criterion),d.levels.criterion)
    p=findfirst(==(row.person),d.levels.person);w=findfirst(==(row.word),d.levels.word)
    r=findfirst(==(row.rater),d.levels.rater)
    eta=x.theta[c,p]-x.word[c,w]-x.rater[r,c]
    e=eigen(SymTridiagonal(zeros(80),sqrt.(collect(1:79))))
    sum(e.vectors[1,j]^2 .*pcm(eta+x.sd[c]*e.values[j],x.steps[:,c]) for j in 1:80)
end

@testset "A0 joint prior sampling" begin
    t=target();b=t.blocks;S=16000
    raw=A.prior_draws(t;ndraws=S,seed=92171)
    @test raw==A.prior_draws(t;ndraws=S,seed=92171)
    @test raw!=A.prior_draws(t;ndraws=S,seed=92172)
    @test all(isfinite,raw)
    xs=[A.coordinates(t,q) for q in eachrow(raw)]
    for (field,n,scales) in ((:rater,t.data.R,t.prior.rater_sd),(:steps,t.data.K-1,t.prior.step_sd)), c in 1:2
        full=reduce(vcat,[permutedims(field===:rater ? x.rater[:,c] : x.steps[2:end,c]) for x in xs])
        @test maximum(abs.(sum(full;dims=2)))<1e-12
        @test maximum(abs.(mean(full;dims=1)))<0.025
        # Includes the reconstructed last entry, detecting independent-free priors.
        expected=scales[c]^2 .* (Matrix{Float64}(I,n,n).-1/n)
        covariance_se=sqrt.((expected.^2+diag(expected)*diag(expected)')./(S-1))
        @test all(abs.(cov(full)-expected).<=6 .*covariance_se)
    end
    for (j,eta) in enumerate((2,5))
        rho=tanh.(raw[:,b.z_correlation[j]])
        @test abs(mean(rho))<0.015
        @test var(rho)≈1/(2eta+1) atol=0.009
        v=raw[:,b.log_recording_sd[j]]
        @test mean(v)≈t.prior.recording_log_sd_mean[j] atol=0.015
        @test std(v)≈t.prior.recording_log_sd_sd[j] atol=0.015
    end
    # The person marginal is N(0,1), without finite-panel centering/scaling.
    @test mean([x.theta[2,1] for x in xs])≈0 atol=0.03
    @test var([x.theta[2,1] for x in xs])≈1 atol=0.05
    @test var([mean(x.theta[1,:]) for x in xs])≈1/t.data.P atol=0.02
    @test cov(raw[:,b.person_white[1:2]])≈Matrix{Float64}(I,2,2) atol=0.04
    @test var(raw[:,first(b.word)])≈t.prior.word_sd^2 atol=0.04
    @test all(iszero,A.coordinates(target(2),first(eachrow(A.prior_draws(target(2);ndraws=1,seed=1)))).steps)
    for (count,seed) in ((0,1),(true,1),(1,-1),(1,true),(1,1.2))
        @test_throws ArgumentError A.prior_draws(t;ndraws=count,seed)
    end
    check=A.prior_predictive_check(t;ndraws=12,parameter_seed=1,prediction_seed=2)
    zero=A.Target([merge(r,(;score=0)) for r in rows()];categories=4,criteria=["C1","C2"],prior=PRIOR)
    other=A.prior_predictive_check(zero;ndraws=12,parameter_seed=1,prediction_seed=2)
    @test check.raw_parameter_draws==other.raw_parameter_draws
    @test check.probabilities==other.probabilities
    @test check.category_replicated==other.category_replicated
    @test check.observed_category_frequencies!=other.observed_category_frequencies
    @test check.conditioning===:joint_prior_on_observed_design
end
flush(stdout)

@testset "A0 prediction design, sharing and conditional probabilities" begin
    t=target();q=A.initial(t)+0.2sin.(1:A.LDP.dimension(t));rs=A.prediction_rows(t)
    for K in (2,4,9)
        tk=target(K);qk=A.initial(tk)+0.2sin.(1:A.LDP.dimension(tk))
        design=A.prediction_design(tk,A.prediction_rows(tk);recording_effect=:existing)
        out=A.simulate_prediction(tk,qk,design,MersenneTwister(3))
        oracle=reduce(vcat,[permutedims(exp.(p)) for p in A.logprobabilities(tk,qk)])
        @test out.probabilities≈oracle atol=2e-14
        @test all(0 .<= out.scores .< K)
        @test all(isapprox.(sum(out.probabilities;dims=2),1;atol=1e-14))
    end
    existing=A.prediction_design(t,rs;recording_effect=:existing)
    @test all(sum(existing.weights[existing.criterion.==c])≈1 for c in 1:2)
    @test sum(existing.weights[(existing.group.==1).&(existing.criterion.==1)])≈1/6
    for mode in (:existing,:new)
        rr=mode===:existing ? rs : newrows()
        d=A.prediction_design(t,rr;recording_effect=mode)
        rev=A.prediction_design(t,reverse(rr);recording_effect=mode)
        out=A.simulate_prediction(t,q,d,MersenneTwister(4))
        out2=A.simulate_prediction(t,q,rev,MersenneTwister(4))
        @test reverse(out.probabilities;dims=1)==out2.probabilities
        @test reverse(out.scores)==out2.scores
        @test out.recording_effects==out2.recording_effects
        # Each row reconstructs from precisely the one group effect.
        x=A.coordinates(t,q)
        for n in eachindex(rr)
            c=d.criterion[n]
            eta=x.theta[c,d.person[n]]-x.word[c,d.word[n]]-x.rater[d.rater[n],c]+out.recording_effects[c,d.group[n]]
            @test out.probabilities[n,:]≈pcm(eta,x.steps[:,c]) atol=1e-14
        end
    end
    q2=copy(q);q2[t.blocks.recording_white].+=100
    dnew=A.prediction_design(t,newrows();recording_effect=:new)
    @test A.simulate_prediction(t,q,dnew,MersenneTwister(5))==A.simulate_prediction(t,q2,dnew,MersenneTwister(5))
    @test A.simulate_prediction(t,q,existing,MersenneTwister(5)).probabilities!=A.simulate_prediction(t,q2,existing,MersenneTwister(5)).probabilities
    for bad in (rows(),[first(rs),first(rs)],NamedTuple[],[merge(first(rs),(;word="unseen"))],
            [merge(first(rs),(;rater="unseen"))],[merge(first(rs),(;person="unseen"))],
            [merge(first(rs),(;criterion="unseen"))],[merge(first(rs),(;score=0))])
        @test_throws ArgumentError A.prediction_design(t,bad;recording_effect=:existing)
    end
    @test_throws ArgumentError A.prediction_design(t,rs;recording_effect=:automatic)
    @test_throws ArgumentError A.prediction_design(t,newrows();recording_effect=:existing)
    @test_throws ArgumentError A.prediction_design(t,rs;recording_effect=:new)
    @test_throws ArgumentError A.prediction_design(t,[merge(first(rs),(;recording="renamed"))];recording_effect=:new)
    @test_throws ArgumentError A.prediction_design(t,[merge(first(newrows()),(;recording=first(rs).recording))];recording_effect=:new)
    @test_throws ArgumentError A.prediction_design(t,[first(newrows()),merge(newrows()[2],(;word="W2"))];recording_effect=:new)
    # Whole-record exclusion is necessary, and dropping a singleton word is new-word prediction.
    held="S1-1";heldrows=[Base.structdiff(r,(;score=nothing)) for r in rows() if r.recording==held]
    training=A.Target([r for r in rows() if r.recording!=held];categories=4,criteria=["C1","C2"],prior=PRIOR)
    @test length(A.prediction_design(training,heldrows;recording_effect=:new).recording_ids)==1
    @test_throws ArgumentError A.prediction_design(t,heldrows;recording_effect=:new)
    single=[r for r in rows() if r.word!="W1" || r.recording==held]
    training=A.Target([r for r in single if r.recording!=held];categories=4,criteria=["C1","C2"],prior=PRIOR)
    @test_throws ArgumentError A.prediction_design(training,heldrows;recording_effect=:new)
end
flush(stdout)

@testset "A0 new-recording integration and uncertainty accounting" begin
    t=target();q=A.initial(t);q[t.blocks.person_white[1]]=1.2
    q[t.blocks.log_recording_sd]=log.([0.8,1.1]);q[t.blocks.z_correlation[2]]=atanh(0.7)
    rr=newrows()[1:6];d=A.prediction_design(t,rr;recording_effect=:new)
    rng=MersenneTwister(21)
    us=reduce(vcat,[permutedims(A.simulate_prediction(t,q,d,rng).recording_effects[:,1]) for _ in 1:6000])
    @test vec(mean(us;dims=1))≈zeros(2) atol=0.04
    expected_covariance=[0.8^2 0.7*0.8*1.1;0.7*0.8*1.1 1.1^2]
    covariance_se=sqrt.((expected_covariance.^2+diag(expected_covariance)*diag(expected_covariance)')./(size(us,1)-1))
    @test all(abs.(cov(us)-expected_covariance).<=6 .*covariance_se)
    pred=A.prediction_summary(t,permutedims(q),rr;recording_effect=:new,seed=24,integrations=4096)
    exact=reduce(vcat,[permutedims(marginal(t,q,r)) for r in rr])
    @test all(abs.(pred.probabilities-exact).<=6 .*pred.integration_mcse.+1e-5)
    @test all(isapprox.(pred.cumulative_probabilities[:,end],1;atol=1e-13))
    # Marginalizing a random effect is not equivalent to substituting u=0.
    plug=pcm(1.2,A.coordinates(t,q).steps[:,1])
    @test maximum(abs.(exact[1,:]-plug))>0.04
    @test all(pred.integration_mcse.>0)
    @test pred.category_integration_mcse[1:4]≈pred.integration_mcse[1,:] atol=1e-14
    @test pred.category_expected_by_draw[1,1:4]≈pred.probabilities[1,:] atol=1e-14
    # Independently replay all inner draws and use Statistics.var to verify
    # both the 1/S factor and covariance-preserving aggregate MCSE.
    raw=reduce(vcat,[permutedims(q),permutedims(q+0.1sin.(1:length(q)))])
    small=A.prediction_summary(t,raw,rr;recording_effect=:new,seed=9,integrations=11)
    rng=MersenneTwister(9); probability_variance=zeros(length(rr)*t.data.K); frequency_variance=zeros(8)
    for v in eachrow(raw)
        reps=[A.simulate_prediction(t,v,d,rng) for _ in 1:11]
        probabilities=reduce(hcat,[vec(r.probabilities) for r in reps])
        frequencies=reduce(hcat,[[mean(r.probabilities[c:2:6,k]) for c in 1:2 for k in 1:4] for r in reps])
        probability_variance .+= vec(var(probabilities;dims=2))./11
        frequency_variance .+= vec(var(frequencies;dims=2))./11
    end
    @test small.integration_mcse≈reshape(sqrt.(probability_variance)./2,length(rr),t.data.K) atol=1e-14
    @test small.category_integration_mcse≈sqrt.(frequency_variance)./2 atol=1e-14
    # Criterion-2 marginal is independent of rho_recording; joint samples are not.
    qneg=copy(q);qneg[t.blocks.z_correlation[2]]=atanh(-0.7)
    @test marginal(t,q,rr[2])==marginal(t,qneg,rr[2])
    rng=MersenneTwister(21)
    uneg=reduce(vcat,[permutedims(A.simulate_prediction(t,qneg,d,rng).recording_effects[:,1]) for _ in 1:6000])
    @test cov(uneg)[1,2]<-0.55
    # Small-SD limit, exact existing-row calculation, and replay controls.
    tiny=copy(q);tiny[t.blocks.log_recording_sd].=log(1e-10)
    almost=A.prediction_summary(t,permutedims(tiny),rr;recording_effect=:new,seed=1,integrations=8)
    @test almost.probabilities[1,:]≈plug atol=1e-9
    existing=A.prediction_summary(t,permutedims(q),A.prediction_rows(t);recording_effect=:existing,seed=1,integrations=1)
    @test all(iszero,existing.integration_mcse)
    @test all(iszero,existing.category_integration_mcse)
    @test isequal(existing,A.prediction_summary(t,permutedims(q),A.prediction_rows(t);recording_effect=:existing,seed=1,integrations=1))
    for mode in (:existing,:new), count in (0,true,1.2)
        @test_throws ArgumentError A.prediction_summary(t,permutedims(q),rr;recording_effect=mode,seed=1,integrations=count)
    end
    @test_throws ArgumentError A.prediction_summary(t,permutedims(q),rr;recording_effect=:new,seed=1,integrations=1)
    @test_throws ArgumentError A.prediction_summary(t,permutedims(q),A.prediction_rows(t);recording_effect=:existing,seed=1,integrations=2)
    @test_throws ArgumentError A.prediction_summary(t,fill(NaN,1,length(q)),rr;recording_effect=:new,seed=1,integrations=2)
    @test_throws ArgumentError A.prediction_summary(t,zeros(0,length(q)),rr;recording_effect=:new,seed=1,integrations=2)
    bad=copy(q);bad[t.blocks.log_recording_sd].=1000
    @test_throws ArgumentError A.prediction_summary(t,permutedims(bad),rr;recording_effect=:new,seed=1,integrations=2)
    @test occursin("excludes posterior MCMC",pred.integration_mcse_scope)
    @test occursin("not joint",pred.marginal_warning)
end
flush(stdout)

end # module
