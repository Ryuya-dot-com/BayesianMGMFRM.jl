module MFRMFixedQSpecChecks

using BayesianMGMFRM, Test, ForwardDiff, LogDensityProblems
const B = BayesianMGMFRM

function fixture(dimensions, categories; mixed = false)
    cells = [(p,i,r) for p in 1:2 for i in 1:(2dimensions) for r in 1:3]
    data = FacetData((; person = first.(cells), item = getindex.(cells, 2), rater = last.(cells),
        score = [mod(sum(cell), categories) for cell in cells]);
        person = :person, item = :item, rater = :rater, score = :score, category_levels = 0:(categories-1))
    q = [cld(i,2) == d for i in 1:(2dimensions), d in 1:dimensions]
    mixed && (q[2,2] = true)
    return mfrm_spec(data; dimensions, q_matrix = q,
        dimension_labels = ["Ability $d" for d in 1:dimensions])
end

# Independent adjacent-category formula on the declared free unit-logit measure.
function independent_density(spec, prior, x)
    data = spec.data
    D, P, R, I, K = spec.dimensions, length(data.person_levels),
        length(data.rater_levels), length(data.item_levels), length(data.category_levels)
    theta = reshape(x[1:(D*P)], D, P)
    raters = [x[(D*P+1):(D*P+R-1)]; -sum(x[(D*P+1):(D*P+R-1)])]
    items = x[(D*P+R):(D*P+R+I-1)]
    steps = reshape(x[(D*P+R+I):end], K-2, I)
    lp = zero(eltype(x))
    for row in 1:data.n
        p, i, r = data.person[row], data.item[row], data.rater[row]
        location = sum(theta[d,p] for d in 1:D if spec.q_matrix[i,d]) - items[i] - raters[r]
        step = [steps[:,i]; -sum(steps[:,i])]
        eta = [zero(eltype(x)); cumsum(location .- step)]
        maximum_eta = maximum(eta)
        lp += eta[data.category[row]] - maximum_eta - log(sum(exp.(eta .- maximum_eta)))
    end
    scales = [fill(prior.person_sd,D*P); fill(prior.rater_sd,R-1);
        fill(prior.item_sd,I); fill(prior.step_sd,I*(K-2))]
    return lp + sum(-log(sd) - (log(2pi)+(v/sd)^2)/2 for (v,sd) in zip(x,scales))
end

@testset "canonical multidimensional MFRM specification (no sampling)" begin
    prior = MFRMPrior(person_sd=0.7, rater_sd=0.4, item_sd=0.6, step_sd=0.5)
    for dimensions in (2,3), categories in (2,4), mixed in (false,true)
        spec = fixture(dimensions,categories; mixed)
        design = getdesign(spec; preview = true)
        target = B._MFRMFixedQReferenceLogDensity(spec; prior)
        legacy = B._MFRMFixedQReferenceLogDensity(B._mfrm_fixed_q_reference_spec(spec); prior)
        @test spec.family === :mfrm && spec.estimation_status === :specified_only
        @test design.parameter_names == target.blueprint.parameter_names == legacy.blueprint.parameter_names
        @test design.blocks == target.blueprint.blocks
        @test Set(keys(design.blocks)) == Set((:person,:rater_free,:item,:item_steps))
        @test design.identification[:item] === design.identification[:person] === :prior_anchored
        @test design.identification[:rater_free] === :sum_to_zero
        @test all(row.density_space === :unit_logit_free for row in spec.prior_blocks)
        @test length(design.parameter_names) == dimensions*2+2+2dimensions+2dimensions*(categories-2)
        identity = design_identity(design)
        @test identity.value == design_identity(spec; preview=true).value
        @test identity.value == design_identity(target.design).value
        @test identity.value != design_identity(legacy.design).value
        @test B._mfrm_fixed_q_identity(target) != B._mfrm_fixed_q_identity(legacy)
        @test B._mfrm_fixed_q_identity(target) != B._mfrm_fixed_q_identity(B._MFRMFixedQReferenceLogDensity(spec; prior=MFRMPrior()))
        @test B._cmdstan_generalized_data(target) == B._cmdstan_generalized_data(legacy)
        @test isequal(q_matrix_validation(spec).rows[2:end], q_matrix_validation(legacy.design).rows[2:end])
        for x in (zeros(length(design.parameter_names)), 0.2sin.(1:length(design.parameter_names)))
            f = x -> LogDensityProblems.logdensity(target,x)
            expected = x -> independent_density(spec,prior,x)
            @test f(x) ≈ expected(x) atol=1e-10
            @test f(x) == LogDensityProblems.logdensity(legacy,x)
            @test ForwardDiff.gradient(f,x) ≈ ForwardDiff.gradient(expected,x) atol=1e-10
        end
        for view in (:full,:public)
            manifest = model_manifest(design; view)
            @test manifest.spec.model === :mfrm_fixed_q
            @test manifest.spec.scale_convention === :unit_logit
            @test manifest.spec.latent_correlation === :identity_fixed
            @test manifest.spec.location === :prior_anchored
            @test manifest.spec.q_matrix_validation.passed
            @test manifest.design.raw_parameterization.density_space === :unit_logit_free
            layout = fit_ready_parameter_layout(design; view)
            @test !(view === :full ? layout.fit_ready : layout.fit_available)
        end
        contract = model_family_contract(spec)
        @test contract.branch === :mfrm_fixed_q
        @test contract.dimensionality.current_loading_policy === :fixed_q_coefficients
        @test contract.dimensionality.classification === (mixed ? :mixed_between_and_within_item : :between_item)
        @test contract.category.implementation_scale_constant == 1
        @test !contract.category.generalized_discrimination
        @test contract.steps.constraint === :first_step_zero_remaining_steps_sum_to_zero
        @test !contract.support.fit_available && !contract.support.scientific_validation_implied
        @test !model_equation(spec).fit_ready && !model_equation(spec).experimental_fit_available
        @test model_manifest(spec; view=:public).spec.availability.fit_available === false
        surface = model_surface_audit(spec; view=:public)
        @test any(row.block === :q_matrix && row.constraint === :fixed_mask && isempty(row.parameter_names) for row in surface)
        @test any(row.block === :item_steps && row.prior === :normal for row in surface)
        @test all(row.block !== :item_dimension_discrimination for row in surface)
        @test_throws ArgumentError design_row_table(design)
        @test_throws ArgumentError getdesign(spec)
        for backend in (:julia,:advancedhmc,:cmdstan)
            @test_throws ArgumentError fit(spec; backend)
            @test_throws ArgumentError fit(design; backend)
            @test_throws ArgumentError B.Experimental.fit(spec; backend)
            @test_throws ArgumentError fit_cache_key(spec; backend, seed=1)
            @test_throws ArgumentError fit_cache_key(design; backend, seed=1)
            @test_throws ArgumentError B._mfrm_fixed_q_sample(target; backend, ndraws=0)
        end
        for mutate! in (s -> push!(s.dimension_labels,"extra"),
                s -> (s.q_matrix[1,:] .= false), s -> empty!(s.prior_blocks),
                s -> empty!(s.constraints), s -> (s.data.category[1] = 99))
            stale = deepcopy(spec); mutate!(stale)
            @test_throws ArgumentError getdesign(stale; preview=true)
            @test_throws ArgumentError B._MFRMFixedQReferenceLogDensity(stale; prior)
        end
        corrupt = deepcopy(design); reverse!(corrupt.parameter_names)
        @test_throws ArgumentError design_identity(corrupt)
        spec.dimension_labels[1] = "changed"
        @test design_identity(target.design).value == identity.value
    end
    spec = fixture(2,4)
    branch = only(row for row in model_family_contract().branches if row.branch === :mfrm_fixed_q)
    @test !branch.fit_available && branch.implementation_status === :specified_only
    for kwargs in ((; thresholds=:rating_scale), (; discrimination=:rater),
            (; bias=[(:item,:rater)]), (; anchors=[(; block=:rater,level=1,value=0.0)]))
        @test_throws ArgumentError mfrm_spec(spec.data; dimensions=2,q_matrix=spec.q_matrix,kwargs...)
    end
    for q in (nothing, ones(4,2), Bool[1 0;1 0;0 0;0 1], fill(0.5,4,2))
        @test_throws ArgumentError mfrm_spec(spec.data; dimensions=2,q_matrix=q)
    end
    @test_throws ArgumentError mfrm_spec(spec.data; dimensions=2,q_matrix=spec.q_matrix,dimension_labels=["same","same"])
end

end
