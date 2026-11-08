module StarPriorIdentityChecks
using BayesianMGMFRM, Test, Statistics
const B = BayesianMGMFRM
const SA = B.Experimental.StarAssociation
include("../examples/star_association.jl")

function fixture(; parameterization=:cp, reference_prior=true, constant=false)
    m = with_options(StarAssociationExample.inputs().spec; parameterization, reference_prior)
    cfg = SA._build_sampler_config(ndraws=12, warmup=5, chains=2)
    draws = constant ? zeros(24, m.dim) : [.1sin(i+j) for i in 1:24, j in 1:m.dim]
    # Deterministic coordinates, deliberately not qualified posterior samples.
    return SA._build_star_result(m, cfg, draws, NamedTuple[], NamedTuple[];
        provenance=(; operation=:deterministic_identity_fixture))
end

@testset "Star prior identity is declared, not inferred from weights" begin
    for (chart, reference) in ((:cp, true), (:ncp, false))
        r = fixture(; parameterization=chart, reference_prior=reference)
        original_draws = copy(r.draws)
        original_hash = r.content_hash
        nt = SA._prior_namedtuple(r.model.prior)
        aliases = (; image_log_sd_mean=nt.entity_log_sd_mean,
            rater_log_sd_mean=nt.rater_log_sd_mean, log_sd_sd=nt.log_sd_sd,
            lkj_eta=nt.entity_lkj_eta, intercept_sd=nt.mu_sd,
            step_sd=nt.step_sd, step_spacing=nt.step_spacing, phi_sd=nt.phi_sd)
        rep = prior_sensitivity(r, [:config=>r.model.prior, :named=>nt, :aliases=>aliases];
            verify_draws=2, retain_weights=true)
        @test r.sampling_warning
        @test rep.sampling_warning == r.sampling_warning
        @test isequal(rep.sampling_quality, r.sampling_quality)
        @test rep.warnings == r.warnings
        @test rep.provenance == r.provenance
        @test rep.target_identity == r.target_identity
        @test rep.source_sample_content_hash == original_hash
        sub = SA._extract_substantive_draws(r.model, r.draws)
        for v in rep.result.variants
            @test v.status === :unchanged_prior
            @test v.prior == nt
            @test v.pareto_k === nothing && v.r_eff === nothing && v.psis_n_eff === nothing
            @test all(iszero, v.raw_log_ratios)
            @test all(==(-log(24)), v.smoothed_norm_log_weights)
            @test v.max_physical_coord_error == v.max_likelihood_invariance_error == 0
            @test any(e -> e.alt_psis_sd > 0, v.estimands)
            for e in v.estimands
                col = sub.draws[:, findfirst(==(e.parameter), sub.names)]
                @test e.alt_psis_mean == e.baseline_mean == mean(col)
                @test e.mean_shift == 0
                @test e.alt_psis_sd ≈ std(col; corrected=false)
                for (p, q) in zip((.025,.5,.975), (e.alt_psis_q025,e.alt_psis_median,e.alt_psis_q975))
                    @test q in col
                    @test count(<=(q), col)/length(col) >= p - 1e-14
                    @test count(<(q), col)/length(col) <= p + 1e-14
                end
            end
        end
        single = only(prior_sensitivity(r, nt).result.variants)
        @test single.status === :unchanged_prior
        @test !hasproperty(single, :raw_log_ratios)
        @test isequal(single.estimands, first(rep.result.variants).estimands)
        @test r.draws == original_draws && r.content_hash == original_hash
        @test SA._verify_result(r) === r
    end

    r = fixture(; constant=true)
    nt = SA._prior_namedtuple(r.model.prior)
    # Every parameter participates, including an arbitrarily small real change.
    alternatives = [k => merge(nt, NamedTuple{(k,)}((getproperty(nt,k)+.1,))) for k in keys(nt)]
    push!(alternatives, :one_ulp => merge(nt, (; phi_sd=nextfloat(nt.phi_sd))))
    rep = prior_sensitivity(r, alternatives; retain_weights=true)
    for v in rep.result.variants
        @test all(==(first(v.raw_log_ratios)), v.raw_log_ratios)
        @test v.status === :refit_required_high_pareto_k
        @test v.pareto_k == Inf
        @test v.prior != nt
    end
    @test SA._psis_smooth_log_ratios(zeros(24); r_eff=1.0).pareto_k == Inf
    @test_throws ArgumentError prior_sensitivity(r, (;phi_sd=nt.phi_sd))
    corrupt = deepcopy(r)
    corrupt.draws[1,1] += .1
    @test_throws ArgumentError prior_sensitivity(corrupt, corrupt.model.prior)

    mktempdir() do dir
        r = fixture()
        rep = prior_sensitivity(r, r.model.prior; retain_weights=true)
        path = joinpath(dir, "identity.json")
        save_report(path, rep)
        reopened = load_report(path)
        v = only(reopened.result.variants)
        @test v.status == "unchanged_prior"
        @test v.pareto_k === nothing && v.r_eff === nothing && v.psis_n_eff === nothing
        @test reopened.sampling_warning == r.sampling_warning
        @test reopened.warnings == r.warnings
        @test reopened.source_sample_content_hash == r.content_hash
        @test all(e -> e.mean_shift == 0, v.estimands)
        @test_throws ArgumentError save_report(path, rep)
    end
end
end
