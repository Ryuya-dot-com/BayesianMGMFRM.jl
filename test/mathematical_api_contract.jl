module MathematicalAPIContractChecks
using BayesianMGMFRM, Test
const B = BayesianMGMFRM
const SA = B.Experimental.StarAssociation
include("fixtures/experimental_diagnostic_record.jl")

@testset "Experimental qualification obeys controls and original diagnostic scope" begin
    for kind in (:RaterItemInteractions, :RaterGroupEffects, :CriterionCollapse)
        r = diagnostic_record(kind)
        original = diagnostics(r)
        @test original.qualified  # Loose manufactured-record gate only.
        q = qualify(r;max_rhat=1.5,min_ess=1)
        @test q.qualified && q.telemetry_complete
        @test q.thresholds.minimum_chains == 4
        @test q.focal_precision_qualification === :not_assessed
        @test isequal(q.diagnostics, original)
        @test !qualify(r;max_rhat=1.5,min_ess=1e9).qualified
        @test !qualify(r;max_rhat=1.5,min_ess=1,min_bfmi=100).qualified
        @test qualify(r;max_rhat=1.5,min_ess=1).thresholds.min_ess == 1
        for bad in ((max_rhat=NaN,), (max_rhat=1.,), (min_ess=0.,), (min_ess=Inf,),
                    (min_bfmi=NaN,), (min_bfmi=0.,), (min_bfmi=true,))
            @test_throws ArgumentError qualify(r;bad...)
        end
        @test_throws MethodError diagnostics(r;min_ess=10)
        @test !qualify(diagnostic_record(kind;chains=2);max_rhat=1.5,min_ess=1).qualified
    end
end

@testset "Raw, conditional, fixed and telemetry failures cannot disappear" begin
    r = diagnostic_record(:RaterItemInteractions)
    d = diagnostics(r)
    checked = B._check_diagnostic_thresholds(1.5,1)
    gate(diag, run=r.run) = B._qualify_experimental_diagnostics(diag,run,checked,.3)
    @test gate(d).qualified
    bad = merge(first(d.raw), (;rank_normalized_rhat=2.))
    @test !gate(merge(d,(;raw=[bad]))).parameter_gate_passed
    @test !gate(merge(d,(;conditional=[bad]))).parameter_gate_passed
    @test !gate((;raw_diagnostics=[bad],model_diagnostics=d.model,sampler=d.sampler)).qualified
    @test gate((;raw_diagnostics=d.raw,model_diagnostics=d.model,sampler=d.sampler)).qualified
    fixed = merge(first(d.raw),(;quality_gate_applicable=false,flag=:structurally_fixed,
        rank_normalized_rhat=NaN,bulk_ess=NaN,tail_ess=NaN))
    @test gate(merge(d,(;conditional=[fixed]))).qualified
    @test !gate(merge(d,(;conditional=[merge(fixed,(;flag=:degenerate_draws))]))).qualified
    @test !gate(merge(d,(;raw=NamedTuple[],model=NamedTuple[]))).qualified
    for stats in (r.run.sampler_stats[1:end-1], reverse(r.run.sampler_stats),
                  [merge(s,(;hamiltonian_energy=missing)) for s in r.run.sampler_stats])
        q = gate(d,merge(r.run,(;sampler_stats=stats)))
        @test !q.qualified && !q.telemetry_complete
    end
    @test !gate(merge(d,(;sampler=d.sampler[1:end-1]))).qualified
    @test !gate(merge(d,(;sampler=[merge(s,(;n_divergences=1)) for s in d.sampler]))).qualified
    # Lowering a requested gate must not erase original stored warnings.
    q = gate(merge(d,(;qualified=false,sampling_warning=true)))
    @test q.qualified && q.sampling_warning && !q.diagnostics.qualified
end

@testset "Reference information is a working approximation" begin
    exact_variance(mc,spacing) = begin
        logits = vcat(0.,cumsum([-spacing*(k-.5*(mc+1)) for k in 1:mc]))
        p = exp.(logits.-maximum(logits));p ./= sum(p)
        sum((0:mc).^2 .* p)-sum((0:mc).*p)^2
    end
    for mc in (1,2,4,10)
        @test SA._pcm_reference_fisher(mc,0.) ≈ mc*(mc+2)/12
    end
    @test exact_variance(4,-20.) > SA._pcm_reference_fisher(4,-20.)
    @test exact_variance(4,1000.) < SA._pcm_reference_fisher(4,1000.)
    @test SA._pcm_reference_fisher(4,1000.) == 1e-6
    @test SA._prs_min_effective_count(log(.5),0.,[3],8.) ≈ 25.6
    @test SA._prs_min_effective_count(log(1.),0.,[3],8.) ≈ 25.6/4
end

@testset "Default step-size search has no hidden clip or silent fallback" begin
    cfg = SA._build_sampler_config(ndraws=5,warmup=5,chains=2)
    limited = SA._build_sampler_config(ndraws=5,warmup=5,chains=2,adaptation=:clamped_regularized)
    for x in (1e-12,1e-8,.03,100.,1e4)
        @test SA._checked_initial_stepsize(x,cfg) == x
        @test SA._checked_initial_stepsize(x,limited) == clamp(x,limited.step_size_bounds...)
    end
    for x in (NaN,Inf,-Inf,0.,-1.)
        @test_throws ArgumentError SA._checked_initial_stepsize(x,cfg)
        @test_throws ArgumentError SA._checked_initial_stepsize(x,limited)
    end
end
end
