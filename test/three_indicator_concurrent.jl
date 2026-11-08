module ThreeIndicatorConcurrentChecks
using BayesianMGMFRM, Test, LinearAlgebra
const B=BayesianMGMFRM
const T=B.Experimental.ThreeIndicator
const C=T.Concurrent

function fixture()
    rows=NamedTuple[]
    for g in 1:3,r0 in 1:2
        r=2(g-1)+r0;study=g==3 ? "english_20" : "main_222"
        cells=g==3 ? (1:1) : (1:5)
        tokens=[(c,s,w) for c in cells for s in 1:2 for w in 1:5]
        count=g==3 ? 150 : 100;n=0;epoch=0
        while n<count
            epoch+=1
            for index in sortperm(1:length(tokens);by=i->mod((i+7r+13epoch)^3,101))
                n+=1;n>count && break
                c,s,w=tokens[index];l1=c==1 ? "ENG" : c<=3 ? "JPN" : "CHN"
                style=c in (3,5) ? "accented" : "natural";ss="$l1-$style-$s"
                push!(rows,(;source=C.SOURCES[g],experiment=study,trial_index=n,
                    block_index=div(n-1,25)+1,within_block_index=mod(n-1,25)+1,
                    speaker_id="$l1-$s",speaker_l1=l1,style,word_number=string(w),target_word="word$w",
                    rater_id="r$r",token_id="$ss-w$w",speaker_style_id=ss,
                    accentedness=mod(n+r+s,9)+1,comprehensibility=mod(2n+w,9)+1,intelligibility_exact=mod(n+r+w,2)))
            end
        end
    end
    rows
end

function checks()
    rows=fixture();input=T.ConcurrentInput(rows;source_sha256="a"^64)
    @testset "Concurrent target and independent full ForwardDiff" begin
        @test input.data.N==700 && input.data.P==24 && input.data.G==3
        @test all(input.data.X[input.data.rater_group[input.data.rater].==3,1:15].==0)
        for n in (2,5,50,242)
            z=reshape(sin.(1:3(n-1)),n-1,3);x=reshape(cos.(1:3n),n,3)
            @test C.hmul(z)≈C.M.helmert(n)*z atol=1e-12
            @test C.htmul(x)≈C.M.helmert(n)'*x atol=1e-12
        end
        for (prior,interaction) in ((:steps,:none),(:steps,:diagonal),(:steps,:full),(:combined,:full),(:reference,:none))
            t=getdesign(input;prior,interaction);q=initial_params(t)+.075sin.(.17*(1:t.size))
            q[t.blocks[:correlation]].+=.2
            q[t.blocks[:pair_correlation]].-=.3
            val,g=logdensity_and_gradient(t,q)
            fd=B.ForwardDiff.gradient(v->logposterior(t,v),q)
            @test isfinite(val) && all(isfinite,g)
            @test val≈logposterior(t,q) atol=1e-8
            @test maximum(abs.(g-fd)./(1 .+abs.(fd)))<2e-9
            @test logprior(t,q)+loglikelihood(t,q)≈val atol=1e-8
            @test sum(pointwise_loglikelihood(t,q))≈loglikelihood(t,q) atol=1e-10
            @test length(parameter_names(t))==t.size
            z=coordinates(t,q)
            @test z.meaning==:effective_finite_grid
            @test maximum(abs,sum(z.pair;dims=1))<1e-12
            @test maximum(abs,sum(z.pair;dims=2))<1e-12
            @test contract(t).interaction==interaction && contract(t).fitting
            @test design_summary(t).fixed_design_rank==27
            bad=copy(q);bad[t.blocks[:log_sd][1]]=1000
            @test logposterior(t,bad)==-Inf
            @test logdensity_and_gradient(t,bad)==(-Inf,zeros(t.size))
            @test_throws ArgumentError logposterior(t,q[1:end-1])
            mktempdir() do dir
                receipt=save_report(joinpath(dir,"model.json"),t)
                restored=T.ConcurrentTarget(receipt.path;expected_sha256=receipt.sha256)
                @test contract(restored)==contract(t)
                @test logposterior(restored,q)==logposterior(t,q)
                @test_throws ArgumentError save_report(receipt.path,t)
                @test_throws ArgumentError T.ConcurrentTarget(receipt.path;expected_sha256="0"^64)
            end
        end
        for (index,change) in ((1,(;intelligibility_exact=2)),(1,(;block_index=2)),
                (1,(;source="unknown")),(1,(;speaker_id="wrong")),(1,(;target_word="different")),
                (2,(;trial_index=1)),(401,(;speaker_l1="JPN")),(1,(;accentedness=true)))
            wrong=copy(rows);wrong[index]=merge(wrong[index],change)
            @test_throws ArgumentError T.ConcurrentInput(wrong;source_sha256="a"^64)
        end
        @test_throws ArgumentError getdesign(input;prior=:steps,interaction=:other)
        @test_throws ArgumentError getdesign(input;prior=:other)
        @test_throws ArgumentError T.ConcurrentInput(rows;source_sha256="invalid")
    end
end
function persistence_checks()
    @testset "Concurrent model persistence rejects mutated compilation" begin
        for mutate in (t->(t.data.X[1,1]+=.1),t->(t.bases.step[1,1]+=.1),
                t->(t.hyper_indices[1]+=1),t->(t.blocks[:beta]=1:72),
                t->(t.input.rows[1]=merge(t.input.rows[1],(;accentedness=2))))
            t=getdesign(T.ConcurrentInput(fixture();source_sha256="a"^64);prior=:steps)
            mutate(t)
            mktempdir() do dir
                path=joinpath(dir,"model.json")
                @test_throws ArgumentError save_report(path,t)
                @test !ispath(path)
            end
        end
    end
end
end
