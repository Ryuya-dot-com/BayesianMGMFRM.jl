isdefined(@__MODULE__, :MGMFRMArtifactReuseChecks) || include("mgmfrm_artifact_reuse.jl")
module MGMFRMDiagnosticMemoryChecks
using BayesianMGMFRM, Test
using ..MGMFRMArtifactReuseChecks: fixtures, normalized_fixture
using ..MGMFRMCorrelated2DFixtures: target
const B = BayesianMGMFRM
const E = B.Experimental

function checks()
    @testset "D1 diagnostic reduction preserves dense results" begin
        fits = fixtures()
        c = target(; K=2, raters=1)
        s = c.base.design.spec
        scalar = mfrm_spec(s.data; family=:mgmfrm, dimensions=1,
            thresholds=:partial_credit, q_matrix=trues(4,1))
        prior = E.NormalizedMGMFRMPrior(; prior_model=:exchangeable,
            B._source_fixture_prior_values(c.prior.source_prior)...)
        for policy in (:fixed_one, :estimated_positive)
            m = E.slope_restriction(scalar; item_slopes=policy, rater_consistency=:fixed_one)
            push!(fits, normalized_fixture(B._normalized_mgmfrm_target(m, prior)))
        end
        for fit in fits
            checked = B._recorded_mgmfrm_samples(fit)
            if !(fit isa E.NormalizedMGMFRMFit) ||
                    !(B._normalized_mgmfrm_target(fit) isa B._MGMFRMSlopeLogDensity)
                @test checked.diagnostics.direct_values.pointwise_loglikelihood isa Matrix
                continue
            end
            t = B._normalized_mgmfrm_target(fit)
            run = fit.record.run
            old = B._generalized_candidate_diagnostic_tables(t, run, t.blueprint)
            new = checked.diagnostics
            @test new.direct_values.pointwise_loglikelihood === nothing
            @test new.direct_values.n_nonfinite_pointwise == 0
            @test isequal(new.direct_values.direct_draws, old.direct_values.direct_draws)
            @test isequal(new.direct_values.loglikelihood, old.direct_values.loglikelihood)
            for name in keys(old)
                name === :direct_values && continue
                @test isequal(getproperty(new,name), getproperty(old,name))
            end
            # The public prediction request must still supply actual pointwise values.
            prediction = B.prediction_observations(fit; dataset_id="fixed-memory-fixture",
                observation_ids=["row-$i" for i in 1:t.base.design.spec.data.n])
            @test prediction.pointwise_loglikelihood ≈ old.direct_values.pointwise_loglikelihood atol=2e-12
            @test !diagnostics(fit).summary.passed # Short deterministic fixtures stay unqualified.
            empty = B._generalized_candidate_direct_draw_values(t,run.draws[1:0,:];store_pointwise=false)
            @test isempty(empty.loglikelihood) && empty.n_nonfinite_pointwise == 0

            if t.item_slopes === :fixed_one
                overflow = copy(run.draws[1:1,:])
                overflow[1,first(t.blueprint.blocks[:person])] = floatmax(Float64)
                dense = B._generalized_candidate_direct_draw_values(t,overflow)
                compact = B._generalized_candidate_direct_draw_values(t,overflow;store_pointwise=false)
                @test compact.n_nonfinite_pointwise > 0
                @test compact.n_nonfinite_pointwise == count(!isfinite,dense.pointwise_loglikelihood)
                @test isequal(compact.loglikelihood,dense.loglikelihood)
            end
        end
    end
end
end
