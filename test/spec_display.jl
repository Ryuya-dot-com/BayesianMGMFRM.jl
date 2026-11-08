module SpecDisplayChecks
using Test, BayesianMGMFRM, Serialization
const B = BayesianMGMFRM

# Explicit arithmetic input fixture, not simulated ratings or posterior draws.
cells = [(p, i, r) for p in 1:3 for i in 1:6 for r in 1:3]
data = FacetData((person=first.(cells), item=getindex.(cells, 2), rater=last.(cells),
    score=[mod(sum(c), 3) for c in cells]); person=:person, item=:item,
    rater=:rater, score=:score, category_levels=0:2)
q = [i <= 3 ? d == 1 : d == 2 for i in 1:6, d in 1:2]
mixed = copy(q); mixed[1, 2] = true
specs = (
    pcm=mfrm_spec(data),
    rsm=mfrm_spec(data; thresholds=:rating_scale),
    gm=mfrm_spec(data; family=:gmfrm, discrimination=:rater),
    mgm1=mfrm_spec(data; family=:mgmfrm, q_matrix=trues(6, 1)),
    mgm2=mfrm_spec(data; family=:mgmfrm, dimensions=2, q_matrix=q),
    mixed=mfrm_spec(data; family=:mgmfrm, dimensions=2, q_matrix=mixed),
    fixed=mfrm_spec(data; dimensions=2, q_matrix=q),
    bias=mfrm_spec(data; bias=[(:rater, :item)]),
    blocked=mfrm_spec(data; family=:gmfrm, discrimination=:rater, thresholds=:rating_scale),
    anchor=mfrm_spec(data; anchors=[(block=:rater, level=2, value=0.25, type=:hard)]),
)
plain(s) = repr(MIME"text/plain"(), s)

@testset "Model meaning before fitting (deterministic inputs only)" begin
    for spec in values(specs)
        compact = repr(spec)
        bytes = IOBuffer(); serialize(bytes, spec); before = take!(bytes)
        contract = model_family_contract(spec)
        text = plain(spec)
        @test startswith(text, "FacetSpec: " * uppercase(string(spec.family)))
        @test occursin("Threshold option: :$(spec.thresholds)", text)
        @test occursin("scale multiplier $(contract.category.implementation_scale_constant)", text)
        @test occursin("Ratings: 54; people: 3; items: 6; raters: 3", text)
        @test occursin("Categories: [0, 1, 2]", text)
        @test occursin("Select priors and sampler settings explicitly", text)
        @test occursin("Design warnings:", text)
        @test contract.support.fit_available ? occursin(contract.support.entrypoint, text) :
            occursin("unavailable for this specification; inspection only", text)
        @test repr(spec) == compact
        @test sprint(show, MIME"text/plain"(), spec; context=:compact=>true) == compact
        bytes = IOBuffer(); serialize(bytes, spec)
        @test take!(bytes) == before  # Display did not mutate data or model fields.
        restored = deserialize(IOBuffer(before))
        @test plain(restored) == text
        if contract.support.fit_available
            @test design_identity(spec; preview=true) == design_identity(restored; preview=true)
        end
    end
    @test occursin("item-specific, shared across raters", plain(specs.pcm))
    @test occursin("shared across items and raters", plain(specs.rsm))
    @test occursin("rater-specific, shared across items", plain(specs.gm))
    @test occursin("item discrimination and rater consistency estimated", plain(specs.gm))
    @test occursin("positive item-dimension loadings and rater consistency estimated", plain(specs.mgm2))
    @test occursin("Legacy discrimination=:none does not mean fixed slopes", plain(specs.mgm2))
    @test occursin("Q: 6 items × 2 dimensions; 7 active cells", plain(specs.mixed))
    @test occursin("fixed at one", plain(specs.fixed))
    @test occursin("other coefficients fixed at zero", plain(specs.fixed))
    @test occursin("Validation-only terms (not fitted interactions): rater × item", plain(specs.bias))
    @test occursin("Anchor declarations: 1", plain(specs.anchor))
    @test !occursin("(experimental)", plain(specs.pcm))
    @test occursin("(experimental)", plain(specs.mgm1))
end
end
