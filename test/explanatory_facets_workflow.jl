using Test, BayesianMGMFRM, Statistics

# Run against an actual saved pilot, not manufactured posterior/telemetry.
function explanatory_fitted_checks(f,out)
    t=getdesign(f);A=BayesianMGMFRM.AdditiveFacets
    @testset "Explanatory saved posterior lifecycle" begin
        @test t isa A.ExplanatoryTarget
        @test validate_design(f).identified
        @test sampler_controls(f).chains==4
        selected=[n for n in parameter_names(f) if startswith(n,"coefficient[") || n=="residual_sd[assessor]"]
        rep=fit_report(f;parameters=selected)
        @test length(rep.summary.rows)==5
        @test all(r->r.lower<r.upper,rep.summary.rows)
        @test all(r->isfinite(r.mean_mcse),rep.mcse)
        @test all(r->all(x->isfinite(x.mcse),r.quantiles),rep.mcse)
        @test isequal(rep.qualification,qualify(f))
        @test !rep.scientific_acceptance
        @test_throws ArgumentError BayesianMGMFRM.posterior_contrast(f;left=selected[1],right=selected[2])
        old=f.record.content_hash
        receipt=save_report(joinpath(out,"focused.json"),rep;return_receipt=true)
        reopened=load_report(receipt.path;expected_sha256=receipt.sha256)
        @test reopened.source_sample_content_hash==old
        @test [r.lower for r in reopened.summary.rows]==[r.lower for r in rep.summary.rows]
        @test_throws ArgumentError save_report(receipt.path,rep)
        @test_throws ArgumentError load_report(receipt.path;expected_sha256="0"^64)
        save_fit(joinpath(out,"saved-fit.jls"),f)
        @test load_fit(joinpath(out,"saved-fit.jls")).record.content_hash==old
        @test_throws ArgumentError save_fit(joinpath(out,"saved-fit.jls"),f)
        ix=[7,2];p=predictive_probabilities(f;rows=ix)
        expected=zeros(length(ix),length(t.categories))
        for q in eachrow(f.record.run.draws);expected.+=predictive_probabilities(t,q)[ix,:];end
        expected./=size(f.record.run.draws,1)
        @test p.mean≈expected atol=2e-14
        @test p.conditioning==:known_owners_and_stored_owner_attributes
        @test p.interval_target==:posterior_category_probability
        new=Dict(k=>v[ix] for (k,v) in t.table if k!=t.columns.score)
        @test predictive_probabilities(f;data=new).mean==p.mean
        new[:moderation].+=.3
        altered=predictive_probabilities(f;data=new)
        ref=zeros(2,length(t.categories));term=only(p for p in t.terms if p.column===:moderation)
        for q in eachrow(f.record.run.draws)
            pr=predictive_probabilities(t,q)[ix,:]
            # Independent exponential tilt from a changed response predictor.
            beta=term.mean+term.sd*q[term.raw]
            pr.*=permutedims(exp.((0:length(t.categories)-1).*(.3beta)))
            ref.+=pr./sum(pr;dims=2)
        end
        ref./=size(f.record.run.draws,1)
        @test altered.mean≈ref atol=2e-14
        new[:experience][1]+=.1
        @test_throws ArgumentError predictive_probabilities(f;data=new)
        ppc=predictive_check(f;ndraws=40,seed=42,groupby=:assessor)
        @test ppc.kind==:posterior_predictive
        @test sum(r.observed for r in ppc.rows)==length(t.person)
        @test sum(r.mean for r in ppc.rows)≈length(t.person) atol=1e-12
        @test sum(r.n for r in ppc.groups)==length(t.person)
        @test ppc.source_sample_content_hash==old
        @test isequal(ppc,predictive_check(f;ndraws=40,seed=42,groupby=:assessor))
        @test ppc.rows!=predictive_check(f;ndraws=40,seed=43,groupby=:assessor).rows
        @test_throws ArgumentError predictive_check(f;ndraws=0,seed=42)
        @test_throws ArgumentError predictive_check(f;seed=true)
        @test_throws ArgumentError predictive_check(f;seed=42,groupby=:not_a_facet)
        receipt=save_report(joinpath(out,"ppc.json"),ppc;return_receipt=true)
        pp=load_report(receipt.path;expected_sha256=receipt.sha256)
        @test [r.median for r in pp.rows]==[r.median for r in ppc.rows]
        @test [r.mean for r in pp.groups]==[r.mean for r in ppc.groups]
        @test f.record.content_hash==old
    end
end
