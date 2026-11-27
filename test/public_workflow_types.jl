module PublicWorkflowTypesTests
using Test, BayesianMGMFRM
using Distributions: Normal, truncated
const B = BayesianMGMFRM

# This module deliberately imports only root exports for its annotations.
describe_spec(s::AbstractMFRMSpec) = design_summary(s)
describe_fit(f::AbstractMFRMFit) = design_summary(f)

module LegacyFixture
using BayesianMGMFRM
using BayesianMGMFRM.GlassBox
using BayesianMGMFRM.Legacy
const B = BayesianMGMFRM
include("fixtures/reporting_fit.jl")
end

@testset "Public workflow types and legacy imports" begin
    rc = B._root_api_contract()
    @test length(rc.layer1_practitioner) == 41
    @test Set(names(B)) == Set((:BayesianMGMFRM, rc.layer1_practitioner...))
    @test isempty(intersect(Set(rc.layer1_practitioner), Set(rc.legacy)))
    for (old, new) in ((:FacetSpec, :AbstractMFRMSpec), (:MFRMFit, :AbstractMFRMFit))
        @test old ∉ names(B)
        @test old in names(B.Legacy)
        @test getfield(B.Legacy, old) === getfield(B, old)
        @test getfield(B, old) <: getfield(B, new)
        @test new in names(B)
        @test B._binding_doc(B, new) !== nothing
    end
    for T in (B.MultidimensionalMFRMFit, B._CorrelatedMFRMFit,
              B._ExchangeableMFRMFit, B._NormalizedMGMFRMFit, B._CorrelatedMGMFRMFit)
        @test T <: AbstractMFRMFit
    end

    rows = [(p, i, r) for p in 1:8 for i in 1:4 for r in 1:3]
    ratings = (; person = ["P$p" for (p,i,r) in rows],
        item = ["I$i" for (p,i,r) in rows], rater = ["R$r" for (p,i,r) in rows],
        score = [mod(p + 2i + r, 4) for (p,i,r) in rows])
    common = (; person = :person, score = :score,
        facets = (item = :item, rater = :rater), steps = :item, category_levels = 0:3)
    standard = mfrm_spec(ratings; common..., prior = :default)
    prior_free = mfrm_spec(ratings; common..., prior = :none)
    structured_free = mfrm_spec(ratings; common..., prior = :none,
        interactions = ((:rater, :item),))
    gmfrm = mfrm_spec(ratings; common..., prior = :default, slope = :rater)
    mgmfrm = mfrm_spec(ratings; common..., prior = :default,
        q_matrix = Bool[1 0; 1 0; 0 1; 0 1])
    events = ["$(p)-$(r)" for (p,r) in zip(ratings.person, ratings.rater)]
    shared = mfrm_spec(merge(ratings, (; event = events)); common...,
        facets = (item = :item, rater = :rater, event = :event), assessment = :event,
        prior = :default, random_effects = (event = truncated(Normal(0, .5), 0, Inf),))
    data = FacetData(ratings; person = :person, score = :score,
        item = :item, rater = :rater, category_levels = 0:3)
    legacy_spec = mfrm_spec(data; identification = :reference)
    converted = mfrm_spec(data; prior = :default, validation_report = validate_design(data))
    @test legacy_spec isa B.Legacy.FacetSpec
    @test converted isa B.AdditiveFacets.MRCMLTarget
    for s in (standard, prior_free, structured_free, gmfrm, mgmfrm, shared, legacy_spec, converted)
        @test s isa AbstractMFRMSpec
        @test isequal(describe_spec(s), design_summary(s))
    end

    # Short fixed-data fits check dispatch/persistence, not convergence or recovery.
    controls = (; chains = 2, warmup = 30, ndraws = 30, progress = false)
    frequentist_fits = AbstractMFRMFit[]
    for method in (:jmle, :mmle)
        push!(frequentist_fits, fit(prior_free; method))
    end
    @test_throws ArgumentError fit(standard; method = :jmle)
    fits = AbstractMFRMFit[fit(s; controls..., seed = 621 + i)
        for (i,s) in enumerate((standard, gmfrm, mgmfrm, shared))]
    append!(fits, frequentist_fits)
    append!(fits, [LegacyFixture.reporting_fit(family) for family in (:mfrm, :gmfrm, :mgmfrm)])
    @test length(fits) == 9
    mktempdir() do directory
        for (i,f) in enumerate(fits)
            @test f isa AbstractMFRMFit
            @test describe_fit(f).n_observations == (i <= 6 ? length(ratings.score) : 6)
            path = joinpath(directory, "fit-$i.jls")
            save_fit(path, f)
            restored = load_fit(path)
            @test typeof(restored) === typeof(f)
            @test restored isa AbstractMFRMFit
            @test describe_fit(restored).n_observations == describe_fit(f).n_observations
            if f isa B.FrequentistMFRM.Fit
                @test restored.record.content_hash == f.record.content_hash
                @test isequal(restored.record.summary, f.record.summary)
                @test_throws ArgumentError posterior_summary(f)
            else
                @test isequal(posterior_summary(restored), posterior_summary(f))
            end
            if i <= 4
                handoff = B.PortableHandoff.export_handoff(f)
                handoff_path = joinpath(directory, "fit-$i.json")
                B.PortableHandoff.save_handoff(handoff_path, handoff)
                reopened = B.PortableHandoff.load_handoff(handoff_path)
                @test reopened.record.handoff_bundle_sha256 == handoff.record.handoff_bundle_sha256
                @test !(reopened isa AbstractMFRMFit)
            end
        end
        # Exercise dispatch after native restoration in a fresh Julia process.
        code = """
            using BayesianMGMFRM
            describe_fit(f::AbstractMFRMFit) = design_summary(f)
            for path in readdir(ARGS[1]; join = true)
                endswith(path, ".jls") || continue
                f = load_fit(path)
                @assert f isa AbstractMFRMFit
                @assert describe_fit(f).n_observations == design_summary(f).n_observations
            end
            println("9 native fits restored through the public type contract")
            """
        project = dirname(Base.active_project())
        @test success(`$(Base.julia_cmd()) --startup-file=no --project=$project -e $code $directory`)
    end
end
end
