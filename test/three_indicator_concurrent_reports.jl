module ThreeIndicatorConcurrentReportChecks
using BayesianMGMFRM, Test, JSON3, SHA
const B=BayesianMGMFRM
const T=B.Experimental.ThreeIndicator
const C=T.Concurrent
const R=T.ConcurrentReports
import ..ThreeIndicatorConcurrentChecks as F
function rehash(d)
    delete!(d,"content_hash");d["content_hash"]=B._cache_hash(d);JSON3.read(JSON3.write(d))
end
function checks()
    rows=F.fixture();input=T.ConcurrentInput(rows;source_sha256="a"^64)
    @testset "Concurrent probabilities and original contrasts" begin
        for interaction in (:none,:diagonal,:full)
            t=getdesign(input;prior=:steps,interaction);q=initial_params(t)+.075sin.(.17*(1:t.size))
            report=event_probabilities(t,q;rows=[1,100,400,401,700])
            ll=pointwise_loglikelihood(t,q)
            @test all(abs(sum(p)-1)<1e-12 for row in report.rows for p in row.probabilities)
            @test all(sum(log(row.probabilities[a][t.data.y[row.target_row,a]]) for a in 1:3)≈ll[row.target_row] for row in report.rows)
            @test all(row.correct_probability==row.probabilities[3][1] for row in report.rows)
            c=contrast(t,q)
            @test length(c.comparisons)==8
            @test [x.n_left for x in c.comparisons]==[80,80,80,80,80,80,100,200]
            @test all(x.raters_left==x.raters_right==4 for x in c.comparisons)
            @test c.selection.additional_row_weight==0
            @test all(abs(sum(p))<1e-12 for row in c.comparisons for p in row.difference.probabilities)
            @test all(abs(x.difference.correct_probability+x.difference.probabilities[3][2])<1e-12 for x in c.comparisons)
            ref=event_probabilities(t,q;panel=:eng_reference)
            @test length(ref.recordings)==10 && length(ref.speakers)==2
            @test ref.reference.listener_weight==1/4 && ref.reference.word_weight==1/5
            @test all(!x.cross_study_extrapolation for x in ref.recordings)
            @test ref.reference.within_block_position==13 && ref.reference.within_time==0
            @test !ref.posterior && ref.uncertainty.interval===nothing && ref.uncertainty.mcse===nothing
            # The zero location, unit-slope point has identical probabilities for every event.
            symmetric=initial_params(t);zero_contrasts=contrast(t,symmetric)
            @test maximum(abs(v) for x in zero_contrasts.comparisons for p in x.difference.probabilities for v in p)<1e-12
            # Refuse silent indexing, context or posterior substitutions.
            for bad in ([0],[1,1],[t.data.N+1],[true],Int[])
                @test_throws ArgumentError event_probabilities(t,q;rows=bad)
            end
            @test_throws ArgumentError event_probabilities(t,q;panel=:other)
            @test_throws ArgumentError event_probabilities(t,q;panel=:eng_reference,rows=[1])
            @test_throws MethodError event_probabilities(t,q;new_listener="new")
            @test_throws ArgumentError contrast(t,q[1:end-1])
            bad=copy(q);bad[1]=NaN
            @test_throws ArgumentError contrast(t,bad)
            mktempdir() do out
                model=save_report(joinpath(out,"model.json"),t)
                restored=load_report(model.path;expected_sha256=model.sha256)
                @test contract(restored)==contract(t)
                @test event_probabilities(restored,q;rows=[1]).rows[1].probabilities==report.rows[1].probabilities
                @test_throws ArgumentError load_report(model.path)
                for (i,r) in enumerate((report,c,ref))
                    receipt=save_report(joinpath(out,"report$i.json"),r)
                    loaded=load_report(receipt.path;expected_sha256=receipt.sha256)
                    @test loaded==r
                    @test_throws ArgumentError load_report(receipt.path)
                    @test_throws ArgumentError load_report(receipt.path;expected_sha256="0"^64)
                    @test_throws ArgumentError load_report(receipt.path;expected_sha256=receipt.sha256,require_complete=true)
                    @test_throws ArgumentError save_report(receipt.path,r)
                    @test_throws ArgumentError save_report(joinpath(out,"unsupported$i.json"),r;overwrite=true)
                    d=R.normalized(r);d["posterior"]=true
                    @test_throws ArgumentError R.check(JSON3.read(JSON3.write(d)))
                    @test_throws ArgumentError R.check(rehash(d))
                end
            end
            for (r,mutate) in ((report,d->(d["rows"][1]["correct_probability"]=.123)),
                (c,d->(d["comparisons"][1]["left_weight"]=-1/80)),
                (c,d->(d["selection"]["additional_row_weight"]=1/300)),
                (ref,d->(d["reference"]["listener_weight"]=1/6)),
                (ref,d->(d["reference"]["within_block_position"]=1)),
                (ref,d->(d["recordings"][1]["cross_study_extrapolation"]=true)))
                d=R.normalized(r);mutate(d)
                @test_throws ArgumentError R.check(rehash(d))
            end
        end
        # Source row order changes mappings, not the labelled target or arithmetic.
        t=getdesign(input;prior=:steps,interaction=:full)
        tr=getdesign(T.ConcurrentInput(reverse(rows);source_sha256="b"^64);prior=:steps,interaction=:full)
        q=initial_params(t)+.075sin.(.17*(1:t.size))
        a=event_probabilities(t,q;rows=[1,401]);b=event_probabilities(tr,q;rows=[1,401])
        @test [x.probabilities for x in a.rows]==[x.probabilities for x in b.rows]
        @test [x.source_row for x in b.rows]==(701 .- [x.source_row for x in a.rows])
        @test contrast(t,q).comparisons==contrast(tr,q).comparisons
        # Averaging probabilities differs from evaluating a mean latent location.
        z=C.reconstruct(t,q);ref=event_probabilities(t,q;panel=:eng_reference)
        s=findfirst(==(1),t.data.speaker_cell);w=1;j=t.data.token_lookup[s,w];rs=findall(<(3),t.data.rater_group)
        logits=[z.word_slope[w,3]*z.rater_slope[r,3]*(z.mean[t.data.rater_group[r],3]+z.speaker[s,3]+z.word[w,3]+z.rater[r,3]+z.token[j,3]+z.pair[r,w,3]+sum(t.data.l1_contrast[1,h]*z.l1[h][r,3] for h in 1:2)) for r in rs]
        correct=sum(1/(1+exp(v)) for v in logits)/length(rs)
        @test ref.recordings[1].correct_probability≈correct atol=1e-12
        @test abs(correct-1/(1+exp(sum(logits)/length(rs))))>1e-8
        t.data.X[1,1]+=.1
        @test_throws ArgumentError event_probabilities(t,q;rows=[1])
    end
end
function support_checks()
    @testset "Declared contrast and reference support" begin
        rows=F.fixture()
        partial=filter(x->!(x.rater_id=="r1" && x.trial_index==100),rows)
        t=getdesign(T.ConcurrentInput(partial;source_sha256="a"^64);prior=:steps)
        @test_throws ArgumentError contrast(t,initial_params(t))
        missing_pair=map(rows) do x
            x.rater_id=="r1" && x.word_number=="5" ? merge(x,(;word_number="4",target_word="word4",token_id="$(x.speaker_style_id)-w4")) : x
        end
        t=getdesign(T.ConcurrentInput(missing_pair;source_sha256="a"^64);prior=:steps)
        @test_throws ArgumentError event_probabilities(t,initial_params(t);panel=:eng_reference)
    end
end
end
