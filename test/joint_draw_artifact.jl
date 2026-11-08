module JointDrawArtifactChecks
using Test, BayesianMGMFRM
const B=BayesianMGMFRM
include("fixtures/reporting_fit.jl")

const checks = @testset "Joint draw identities and public fit priors (arithmetic fixtures)" begin
    for family in (:mfrm,:gmfrm,:mgmfrm)
        println(stderr,"Checking joint artifact: ",family);flush(stderr)
        f=reporting_fit(family;ndraws=4,chains=2)
        if family===:mfrm
            prior=MFRMPrior(person_sd=2.1,rater_sd=.7,item_sd=.8,step_sd=.9)
            f=MFRMFit(f.design,prior,f.draws,
                [logposterior(f.design,vec(row),prior) for row in eachrow(f.draws)],
                f.acceptance_rate,f.chain_ids,f.iterations,f.chain_acceptance_rate,
                f.backend,f.sampler,f.warmup,f.step_size,f.sampler_stats,f.sampler_controls)
        end
        full=fit_artifact(f;include_draws=true,include_environment=false)
        public=B._public_fit_artifact_projection(full,f)
        expected_names=family===:mfrm ? f.design.parameter_names : f.diagnostic_surface.raw_parameter_names
        for a in (full,public)
            @test a.draw_index.chain_ids==[1,1,1,1,2,2,2,2]
            @test a.draw_index.iterations==[1,2,3,4,1,2,3,4]
            if family===:mfrm || a===full
                @test (family===:mfrm ? a.parameter_names : a.raw_parameter_names)==expected_names
                @test (family===:mfrm ? a.draws : a.raw_draws)==f.draws
            else
                @test !hasproperty(a,:raw_parameter_names)
                @test !hasproperty(a,:raw_draws)
            end
            @test a.content_hash.value==artifact_content_hash(a)
            if family!==:mfrm
                @test a.direct_draws==f.direct_draws
                @test a.direct_parameter_names==f.diagnostic_surface.direct_parameter_names
            end
        end
        @test isequal(public.fit_metadata.prior,fit_metadata(f;view=:public).prior)
        @test public.fit_metadata.n_chains==2
        @test public.fit_metadata.n_draws==8
        @test !hasproperty(public.fit_metadata,:design_identity)
        compact=fit_artifact(f;include_environment=false)
        @test compact.draw_index===nothing
        @test (family===:mfrm ? compact.draws : compact.raw_draws)===nothing
        oldhash=full.content_hash.value
        full.draw_index.chain_ids[1]=99
        @test f.chain_ids[1]==1 && public.draw_index.chain_ids[1]==1
        @test artifact_content_hash(full)!=oldhash
        public.draw_index.iterations[1]=99
        @test f.iterations[1]==1
        bad=deepcopy(f);bad.chain_ids[1]=99
        @test_throws ArgumentError fit_artifact(bad;include_draws=true,include_environment=false)
    end
end
end
