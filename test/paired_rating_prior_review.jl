module PairedRatingPriorReviewChecks

using Test, Random, Statistics
include(joinpath(@__DIR__,"..","scripts","paired_rating_prior_review.jl"))
const R=PairedRatingPriorReview
const A=R.A
const PRIOR=(;word_sd=1.0,rater_sd=(0.5,0.6),step_sd=(0.7,0.8),
    recording_log_sd_mean=(log(0.5),log(0.6)),recording_log_sd_sd=(0.5,0.6),
    person_lkj_eta=2,recording_lkj_eta=5)
rows(K)=[(;person="P$p",word="W$w",rater="R$r",recording="S$p-$w",criterion="C$c",score=mod(p+w+r+c,K))
    for p in 1:3 for w in 1:2 for r in 1:3 for c in 1:2 if !(p==1 && w==1 && r==1 && c==1)]
target(K)=A.Target(rows(K);categories=K,criteria=["C1","C2"],prior=PRIOR)

@testset "PCM step geometry and order contrasts" begin
    rng=MersenneTwister(92181)
    for K in (2,4,9)
        H=K-1
        increasing=H==1 ? zeros(2) : [0.;collect(range(-1.5,1.5;length=H))]
        @test all(r.has_interval for r in R.modal_intervals(increasing))
        @test count(r->r.has_interval,R.modal_intervals(zeros(K)))==2
        @test count(r->r.has_interval,R.modal_intervals([0.;reverse(increasing[2:end])]))==2
        for _ in 1:12
            steps=randn(rng,H);steps.-=mean(steps);s=[0.;steps]
            ordered=[0.;sort(steps)]
            reversed=[0.;sort(steps;rev=true)]
            for eta in (-3.,-0.2,0.,0.8,3.)
                p=A.B._ld1_pcm_probabilities(eta,steps)
                low=A.B._ld1_pcm_probabilities(eta,ordered[2:end])
                high=A.B._ld1_pcm_probabilities(eta,reversed[2:end])
                @test low[1]+low[end]<=p[1]+p[end]+1e-13
                @test p[1]+p[end]<=high[1]+high[end]+1e-13
                @test sum((k-1)*p[k] for k in 1:K) < sum((k-1)*A.B._ld1_pcm_probabilities(eta+0.01,steps)[k] for k in 1:K)
            end
            for interval in R.modal_intervals(s)
                interval.has_interval || continue
                eta=if isinf(interval.lower)
                    interval.upper-1
                elseif isinf(interval.upper)
                    interval.lower+1
                else
                    (interval.lower+interval.upper)/2
                end
                prob=A.B._ld1_pcm_probabilities(eta,steps)
                @test argmax(prob)-1==interval.category
            end
        end
    end
    @test_throws ArgumentError R.modal_intervals([1.,0.])
    @test_throws ArgumentError R.modal_intervals([0.,NaN])
end
flush(stdout)

@testset "A0 prior review transformations and paired statistics" begin
    for K in (2,4,9)
        t=target(K);raw=A.prior_draws(t;ndraws=8,seed=92182);saved=copy(raw)
        @test R.transform_draws(t,raw,:baseline)==raw
        for case in R.CASES
            tr=R.transform_draws(t,raw,case.id)
            @test tr[:,t.blocks.person_white]==raw[:,t.blocks.person_white]
            @test tr[:,t.blocks.z_correlation]==raw[:,t.blocks.z_correlation]
            @test tr[:,t.blocks.recording_white]==raw[:,t.blocks.recording_white]
            for i in 1:8
                x=A.coordinates(t,raw[i,:]);y=A.coordinates(t,tr[i,:])
                @test y.theta==x.theta
                @test y.word≈case.nuisance*x.word
                @test y.rater≈case.nuisance*x.rater
                @test y.u≈case.nuisance*x.u
                @test maximum(abs.(sum(y.steps;dims=1)))<1e-12
                if case.steps===:ascending
                    @test y.steps[2:end,:]≈sort(x.steps[2:end,:];dims=1) atol=1e-12
                    @test sum(abs2,y.steps)≈sum(abs2,x.steps) atol=1e-12
                elseif case.steps===:double_sd
                    @test y.steps≈2x.steps
                elseif case.steps===:zero
                    @test all(iszero,y.steps)
                else
                    @test y.steps==x.steps
                end
            end
            metadata=R.scenario_metadata(t,case.id)
            @test isnothing(metadata.fit_prior)==(case.steps in (:ascending,:zero))
            if !isnothing(metadata.fit_prior)
                @test A.checked_prior(metadata.fit_prior)==metadata.fit_prior
                @test metadata.fit_prior.word_sd==PRIOR.word_sd*case.nuisance
            end
        end
        @test raw==saved
    end
    t=target(4);raw=A.prior_draws(t;ndraws=16,seed=92182)
    review=R.review(t,raw;prediction_seed=92183)
    baseline=review.results[1].category_expected_by_draw
    original=A.prediction_summary(t,raw,A.prediction_rows(t);recording_effect=:existing,seed=92183,integrations=1)
    @test baseline==original.category_expected_by_draw
    @test all(s->iszero(s.paired_endpoint_change.mean),review.results[1].summary)
    for r in review.results
        for c in 1:2
            cols=(c-1)*4 .+ (1:4)
            vals=r.category_expected_by_draw[:,cols]
            @test all(isapprox.(sum(vals;dims=2),1;atol=1e-13))
            delta=vals[:,1]+vals[:,end]-baseline[:,first(cols)]-baseline[:,last(cols)]
            @test r.summary[c].paired_endpoint_change.mean≈mean(delta) atol=1e-14
            @test r.summary[c].paired_endpoint_change.iid_mean_mcse≈std(delta)/4 atol=1e-14
        end
    end
    zero=A.Target([merge(r,(;score=0)) for r in rows(4)];categories=4,criteria=["C1","C2"],prior=PRIOR)
    changed=R.review(zero,raw;prediction_seed=92183)
    @test getproperty.(review.results,:category_expected_by_draw)==getproperty.(changed.results,:category_expected_by_draw)
    @test review.base_target_identity!=changed.base_target_identity
    @test_throws ArgumentError R.transform_draws(t,raw,:best_prior)
    @test_throws ArgumentError R.transform_draws(t,fill(NaN,size(raw)),:baseline)
    @test_throws ArgumentError R.transform_draws(t,raw[1:1,:],:baseline)
end
flush(stdout)

end # module
