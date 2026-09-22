module PairedRatingPrecisionChecks

using Test, LinearAlgebra, Statistics, Random
include(joinpath(@__DIR__,"..","scripts","paired_rating_reference.jl"))
const A=PairedRatingReference
const PRIOR=(;word_sd=1.0,rater_sd=(0.5,0.6),step_sd=(0.7,0.8),
    recording_log_sd_mean=(log(0.5),log(0.6)),recording_log_sd_sd=(0.5,0.6),
    person_lkj_eta=2,recording_lkj_eta=5)
rows(K)=[(;person="P$p",word="W$w",rater="R$r",recording="S$p-$w",criterion="C$c",score=mod(p+w+r+c,K))
    for (p,w) in ((1,1),(1,2),(2,2),(2,3),(3,1),(3,3)) for r in 1:3 for c in 1:2
    if !(p==1 && w==1 && r==1 && c==1)]
target(K)=A.Target(rows(K);categories=K,criteria=["C1","C2"],prior=PRIOR)
function pcm(eta,s)
    logits=[k*eta-sum(s[1:k]) for k in 0:length(s)]
    v=exp.(logits.-maximum(logits));v/sum(v)
end

@testset "A0 draw-level normal marginal integration" begin
    nodes=eigen(SymTridiagonal(zeros(160),sqrt.(collect(1:159))))
    for K in (2,4,9),eta in (-1.2,0.,0.9),sd in (0.2,0.8)
        s=sin.(collect(1:K-1));s.-=mean(s)
        out=A.marginal_pcm(eta,sd,s;atol=1e-9,maxevals=10000)
        independent=sum(nodes.vectors[1,j]^2 .*pcm(eta+sd*nodes.values[j],s) for j in 1:160)
        @test out.values[1:K]≈independent atol=2e-8
        @test out.values[K+1:end]≈cumsum(independent)[1:end-1] atol=2e-8
        @test out.estimated_error<=1e-9 && out.evaluations<=10000
        @test out.tail_bound<3e-19
    end
    for sd in (1e-6,1.,1e4)
        out=A.marginal_pcm(0.,sd,[0.];atol=1e-9,maxevals=10000)
        @test out.values≈[0.5,0.5,0.5] atol=1e-9
    end
    tiny=A.marginal_pcm(1.2,1e-10,[-0.7,0.1,0.6];atol=1e-9,maxevals=10000)
    @test tiny.values[1:4]≈pcm(1.2,[-0.7,0.1,0.6]) atol=1e-9
    # Composite Simpson integration is independent of both Gaussian quadrature rules.
    s=[1.2,-0.7,0.4,-0.9,0.5,-1.,0.8,-0.3];s.-=mean(s)
    h=0.0005;independent=zeros(9)
    for i in 0:40000
        z=-10+i*h;weight=i in (0,40000) ? 1 : isodd(i) ? 4 : 2
        independent .+= weight.*pcm(-3.2+6z,s).*(exp(-z^2/2)/sqrt(2pi))
    end
    independent.*=h/3
    out=A.marginal_pcm(-3.2,6.,s;atol=1e-9,maxevals=10000)
    @test out.values[1:9]≈independent atol=1e-8
    @test_throws ArgumentError A.marginal_pcm(0.,1.,s;atol=1e-9,maxevals=10)
    @test_throws ArgumentError A.marginal_pcm(0.,0.,s;atol=1e-9,maxevals=10000)
    @test_throws ArgumentError A.marginal_pcm(0.,1.,s;atol=0.,maxevals=10000)
end
flush(stdout)

@testset "A0 focal contrasts, labels and conditioning" begin
    for K in (2,4,9)
        t=target(K);design=A.focal_design(t;recordings=1)
        raw=A.prior_draws(t;ndraws=2,seed=92191)
        result=A.focal_draws(t,raw;existing_rows=design.existing,new_rows=design.new,quadrature_atol=1e-8,quadrature_maxevals=10000)
        @test length(design.existing)==length(design.new)==6
        @test size(result.draws)==(2,16+12*(2K-1))
        @test length(unique(getproperty.(result.columns,:name)))==size(result.draws,2)
        @test all(result.integration.error_estimates.<=1e-8)
        x=A.coordinates(t,raw[1,:]);columns=result.columns
        for (i,col) in enumerate(columns)
            if col.kind in (:person_contrast,:rater_contrast)
                ids=col.kind===:person_contrast ? t.data.levels.person : t.data.levels.rater
                values=col.kind===:person_contrast ? x.theta : permutedims(x.rater)
                a=findfirst(==(col.first_id),ids);b=findfirst(==(col.second_id),ids)
                c=findfirst(==(col.criterion),t.data.levels.criterion)
                @test result.draws[1,i]≈values[c,a]-values[c,b]
            elseif col.kind===:correlation
                @test result.draws[1,i]≈x.rho[col.name=="rho_person" ? 1 : 2]
            elseif col.kind===:recording_sd
                @test result.draws[1,i]≈x.sd[col.name=="recording_sd[1]" ? 1 : 2]
            elseif col.recording_effect===:existing
                d=A.prediction_design(t,design.existing;recording_effect=:existing);n=col.row;c=d.criterion[n]
                eta=x.theta[c,d.person[n]]-x.word[c,d.word[n]]-x.rater[d.rater[n],c]+x.u[c,d.trained_index[d.group[n]]]
                p=pcm(eta,x.steps[2:end,c])
                @test result.draws[1,i]≈(col.kind===:probability ? p[col.category+1] : sum(p[1:col.category+1])) atol=1e-13
            end
        end
        altered=copy(raw);altered[:,t.blocks.z_correlation[2]].*=-1;altered[:,t.blocks.recording_white].+=2
        again=A.focal_draws(t,altered;existing_rows=design.existing,new_rows=design.new,quadrature_atol=1e-8,quadrature_maxevals=10000)
        newcols=findall(c->hasproperty(c,:recording_effect) && c.recording_effect===:new,columns)
        oldcols=findall(c->hasproperty(c,:recording_effect) && c.recording_effect===:existing,columns)
        @test result.draws[:,newcols]==again.draws[:,newcols]
        @test result.draws[:,oldcols]!=again.draws[:,oldcols]
        @test_throws ArgumentError A.focal_draws(t,raw;existing_rows=design.existing,new_rows=design.existing,quadrature_atol=1e-8,quadrature_maxevals=10000)
    end
end
flush(stdout)

@testset "Precision availability and numerical decisions" begin
    p=A.FOCAL_PRECISION_PROPOSAL
    @test A.checked_precision(p)==p
    @test_throws ArgumentError A.checked_precision(merge(p,(;mean_sd_ratio=0.)))
    @test_throws ArgumentError A.checked_precision(merge(p,(;min_chains=true)))
    s=(;sd=1.,lower=-2.,upper=2.)
    m=(;mcse_status=:available,mean_mcse=0.02,quantiles=((;probability=.025,mcse=.04),(;probability=.5,mcse=.02),(;probability=.975,mcse=.04)))
    @test A.focal_precision_decision(s,m,:person_contrast,p).status===:precision_met
    @test A.focal_precision_decision(s,m,:probability,p).status===:precision_insufficient
    @test A.focal_precision_decision(s,merge(m,(;mean_mcse=.001)),:probability,p).status===:precision_met
    @test A.focal_precision_decision(s,merge(m,(;mcse_status=:insufficient_draws,mean_mcse=missing)),:person_contrast,p).status===:mcse_unavailable
    @test A.focal_precision_decision(merge(s,(;sd=0.)),m,:person_contrast,p).status===:precision_insufficient
    @test A.focal_precision_decision(merge(s,(;upper=-2.)),m,:person_contrast,p).status===:precision_insufficient
    diag=(;quality_gate_applicable=true,rank_normalized_rhat=1.001,bulk_ess=500.,tail_ess=450.,flag=:ok)
    @test A.focal_diagnostic_ok(diag,p)
    @test !A.focal_diagnostic_ok(merge(diag,(;rank_normalized_rhat=1.02)),p)
    @test !A.focal_diagnostic_ok(merge(diag,(;tail_ess=NaN)),p)
    # Actual estimator availability on independent test draws, not a fitted A0 posterior.
    draws=randn(MersenneTwister(3),4000,1)
    mcse=only(A.B._posterior_mcse_rows(draws,["test_normal"],4;parameter_space=:test_only))
    summary=only(A.B._posterior_summary_rows(draws,["test_normal"];lower=.025,upper=.975,intervals=(.95,),reference=0.,rope=nothing,rope_probability_threshold=.95))
    @test mcse.mcse_status===:available
    @test A.focal_precision_decision(summary,mcse,:person_contrast,p).status===:precision_met
end
flush(stdout)

end # module
