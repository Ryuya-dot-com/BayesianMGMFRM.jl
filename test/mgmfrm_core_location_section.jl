module MGMFRMCoreLocationSectionChecks
using Test, LinearAlgebra, ForwardDiff, Statistics, BayesianMGMFRM
include("../scripts/mgmfrm_core_location_section.jl")
const S = MGMFRMCoreLocationSection
const B = BayesianMGMFRM

function fixture(n, Q)
    cells = [(p,i,r) for p in 1:n for i in axes(Q,1) for r in 1:3]
    data = FacetData((;person=first.(cells), item=getindex.(cells,2), rater=last.(cells),
        score=[mod(sum(c),3) for c in cells]); person=:person,item=:item,rater=:rater,
        score=:score,category_levels=0:2)
    spec = mfrm_spec(data;family=:mgmfrm,dimensions=size(Q,2),q_matrix=Q,thresholds=:partial_credit)
    base = B._mgmfrm_guarded_local_fit_logdensity(spec;
        prior=B._SourceFixturePrior(person_sd=1.3,item_sd=.7))
    raw = [.35sin(.7i) for i in 1:B.LogDensityProblems.dimension(base)]
    return base, raw
end

@testset "Gaussian location sections and deterministic library dynamics" begin
    for (n,Q) in ((1,Bool[1 0;0 1]), (5,Bool[1 0;1 1;0 1]),
            (4,Bool[1 0 0;0 1 0;0 0 1;1 1 1]))
        base, raw = fixture(n,Q)
        original = copy(raw)
        sections = [S.location_section(base,raw;coordinates=c) for c in
            (:person_mean,:orthogonal_person_mean,:whitened)]
        mu, u, white = sections
        D = length(mu.center)
        @test u.center ≈ sqrt(n)*mu.center
        @test u.covariance ≈ n*mu.covariance
        @test white.precision ≈ Matrix{Float64}(I,D,D)
        @test mu.raw_at(mu.center) ≈ u.raw_at(u.center) ≈ white.raw_at(white.center)
        @test base.blueprint.parameter_names == B._mgmfrm_fit_ready_candidate_blueprint(base.design).parameter_names
        # Equal physical dynamics require transforming momenta AND the metric.
        pmu = S.dynamics_probe(mu;step_size=.11)
        pu = S.dynamics_probe(u;inverse_mass=fill(Float64(n),D),step_size=.11)
        transform = Diagonal(vcat(fill(sqrt(n),D),fill(inv(sqrt(n)),D)))
        @test pu.observed_map ≈ transform*pmu.observed_map/transform atol=2e-8
        @test pu.phase_covariance ≈ transform*pmu.phase_covariance*transform' atol=2e-8
        for section in sections
            density = section.logdensity
            q = section.center + collect(range(-.4,.7;length=D))
            change = density(q)-density(section.center)
            @test change ≈ -dot(q-section.center,section.precision*(q-section.center))/2 atol=1e-9
            @test ForwardDiff.gradient(density,q) ≈ -section.precision*(q-section.center) atol=2e-9
            @test ForwardDiff.hessian(density,q) ≈ -section.precision atol=2e-9
            @test B._source_fixture_loglikelihood(base,section.raw_at(q)) ≈
                B._source_fixture_loglikelihood(base,raw) atol=1e-9
            for mass in (ones(D),collect(range(.6,1.7;length=D))), h in (.03,.11), steps in (3,-3)
                probe = S.dynamics_probe(section;inverse_mass=mass,step_size=h,steps)
                for field in (:origin_error,:map_error,:off_basis_error,:reversal_error,
                        :volume_error,:exact_covariance_error)
                    @test getproperty(probe,field) < 2e-8
                end
                @test probe.energy_change ≈ probe.energy_reference atol=2e-8
                # A symplectic, reversible integrator is not an exact target draw.
                @test probe.unadjusted_covariance_change > 1e-10
            end
        end
        @test raw == original
        for bad in ((;inverse_mass=[0.,1.]),(;inverse_mass=[NaN,1.]),
                (;inverse_mass=Float64[]),(;step_size=0.),(;step_size=Inf),
                (;step_size=true),(;steps=0),(;steps=1.5),(;steps=true))
            @test_throws ArgumentError S.dynamics_probe(mu;bad...)
        end
        @test_throws ArgumentError S.location_section(base,raw;coordinates=:unknown)
        @test_throws ArgumentError mu.raw_at(zeros(D+1))
    end
end

@testset "Controls expose the limits of deterministic dynamics checks" begin
    base, raw = fixture(5,Bool[1 0;1 1;0 1])
    mu = S.location_section(base,raw)
    u = S.location_section(base,raw;coordinates=:orthogonal_person_mean)
    white = S.location_section(base,raw;coordinates=:whitened)
    # Omitting sqrt(N) changes the target curvature by a factor N.
    @test norm(ForwardDiff.hessian(mu.logdensity,u.center)+u.precision) > 1
    # A pure-Q diagonal conditional cannot expose a transposed Cholesky solve.
    R = cholesky(Symmetric(mu.precision)).U
    wrong_whitening(q) = mu.logdensity(mu.center + R' \ q)
    @test norm(ForwardDiff.hessian(wrong_whitening,zeros(2))+I) > .01
    # A wrong force can remain reversible and volume preserving.
    wrong = merge(white,(;logdensity=q -> 2white.logdensity(q)))
    probe = S.dynamics_probe(wrong;step_size=.11,steps=3)
    @test probe.map_error > .01
    @test probe.reversal_error < 2e-8 && probe.volume_error < 2e-8
    @test S.dynamics_probe(white;step_size=.11,steps=3).map_error < 2e-8
    # Identity preserves any covariance while making no progress at all.
    frozen = Matrix{Float64}(I,2,2)
    @test frozen*mu.covariance*frozen' == mu.covariance
    @test frozen*[.3,-.2] == [.3,-.2]
end
end
