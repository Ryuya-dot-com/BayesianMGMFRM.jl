function argument_error_message(callable)
    try
        callable()
    catch err
        @test err isa ArgumentError
        return sprint(showerror, err)
    end
    @test false
    return ""
end

struct ExplodingTable end
Base.getindex(::ExplodingTable, args...) = error("backend exploded")

struct InternalMethodErrorTable end
_method_error_trigger(::Int) = nothing
Base.getindex(::InternalMethodErrorTable, args...) = _method_error_trigger("not an Int")

struct CollectionFailureTable end
struct CollectionFailureColumn end
Base.getindex(::CollectionFailureTable, args...) = CollectionFailureColumn()
Base.IteratorSize(::Type{CollectionFailureColumn}) = Base.SizeUnknown()
Base.eltype(::Type{CollectionFailureColumn}) = Any
Base.iterate(::CollectionFailureColumn, state = 1) =
    throw(ArgumentError("column storage not found during collection"))

function central_difference(logp, x, i; eps = 1e-5)
    xp = copy(x)
    xm = copy(x)
    xp[i] += eps
    xm[i] -= eps
    return (logp(xp) - logp(xm)) / (2eps)
end

function check_forwarddiff_gradient(logp, x; coords = nothing, atol = 1e-4, rtol = 1e-4)
    lp = logp(x)
    @test isfinite(lp)
    gradient = ForwardDiff.gradient(logp, x)
    @test length(gradient) == length(x)
    @test all(isfinite, gradient)
    check_coords = coords === nothing ? eachindex(x) : coords
    for i in check_coords
        @test gradient[i] ≈ central_difference(logp, x, i) atol = atol rtol = rtol
    end
    return gradient
end

function check_advancedhmc_smoke(target, initial;
        seed::Int,
        ndraws::Int = 2,
        step_size::Float64 = 0.03,
        max_depth::Int = 2,
        ad_backend::Symbol = :ForwardDiff)
    nparams = LogDensityProblems.dimension(target)
    @test length(initial) == nparams
    @test isfinite(LogDensityProblems.logdensity(target, initial))

    gradient_adapter = BayesianMGMFRM._logdensity_gradient_target(target, initial, ad_backend)
    lp, gradient = LogDensityProblems.logdensity_and_gradient(gradient_adapter.target, initial)
    @test gradient_adapter.ad_backend === ad_backend
    @test isfinite(lp)
    @test length(gradient) == nparams
    @test all(isfinite, gradient)

    metric = AdvancedHMC.UnitEuclideanMetric(nparams)
    hamiltonian = AdvancedHMC.Hamiltonian(
        metric,
        x -> LogDensityProblems.logdensity(gradient_adapter.target, x),
        x -> LogDensityProblems.logdensity_and_gradient(gradient_adapter.target, x),
    )
    integrator = AdvancedHMC.Leapfrog(step_size)
    kernel = AdvancedHMC.HMCKernel(AdvancedHMC.Trajectory{AdvancedHMC.MultinomialTS}(
        integrator,
        AdvancedHMC.GeneralisedNoUTurn(max_depth, 1000.0),
    ))
    samples, stats = AdvancedHMC.sample(
        MersenneTwister(seed),
        hamiltonian,
        kernel,
        copy(initial),
        ndraws,
        AdvancedHMC.NoAdaptation(),
        0;
        drop_warmup = false,
        verbose = false,
        progress = false,
    )

    @test length(samples) == ndraws
    @test length(stats) == ndraws
    for (iteration, sample) in enumerate(samples)
        @test length(sample) == nparams
        @test all(isfinite, sample)
        @test isfinite(LogDensityProblems.logdensity(target, sample))
        stat_row = BayesianMGMFRM._advancedhmc_stat_row(stats[iteration], 1, iteration)
        @test stat_row.chain == 1
        @test stat_row.iteration == iteration
        @test isfinite(stat_row.log_density)
        @test stat_row.n_steps >= 1
        @test 0 <= stat_row.tree_depth <= max_depth
        @test isfinite(stat_row.step_size) && stat_row.step_size > 0
    end
    return samples, stats
end

function has_issue(report, code::Symbol)
    return any(issue -> issue.code === code, report.issues)
end

function has_issue(report, code::Symbol, facet::Symbol)
    return any(report.issues) do issue
        issue.code === code &&
            haskey(issue.context, :facet) &&
            issue.context[:facet] === facet
    end
end

function has_doc(mod, name::Symbol)
    isdefined(mod, name) || return false
    binding = Base.Docs.Binding(mod, name)
    haskey(Base.Docs.meta(mod), binding) && return true
    try
        return BayesianMGMFRM._binding_doc(mod, name) !== nothing
    catch error
        error isa MethodError || rethrow()
        return false
    end
end

function file_sha256(path)
    return bytes2hex(open(sha256, path))
end

function check_generated_fixture_reference(root, path, recorded_sha256)
    @test isfile(joinpath(root, path))
    @test occursin(r"^[0-9a-f]{64}$", recorded_sha256)
    return nothing
end

function check_fixture_sha256_when_available(root::AbstractString,
        artifact::AbstractString,
        expected_sha256::AbstractString)
    path = normpath(joinpath(root, artifact))
    if isfile(path)
        @test expected_sha256 == file_sha256(path)
    else
        @test startswith(artifact, "../Simulation/data/")
        @test !isempty(expected_sha256)
    end
    return nothing
end

function optional_fixture_path(env_key::AbstractString, default_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    if haskey(ENV, env_key)
        fixture_path = ENV[env_key]
        isempty(fixture_path) && return ""
        RUN_RESEARCH_EVIDENCE_TESTS || throw(ArgumentError(
            "$env_key names an optional research-evidence fixture; set " *
            "BAYESIANMGMFRM_RESEARCH_EVIDENCE_TESTS=true before supplying it",
        ))
        resolved_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
        isfile(resolved_path) ||
            throw(ArgumentError("fixture path from $env_key does not exist: $fixture_path"))
        return fixture_path
    end
    RUN_RESEARCH_EVIDENCE_TESTS || return ""
    resolved_default = joinpath(root, default_path)
    return isfile(resolved_default) ? default_path : ""
end

function optional_source_bridge_fixture_path(env_key::AbstractString,
        default_path::AbstractString,
        default_stan_model::AbstractString)
    fixture_path = optional_fixture_path(env_key, default_path)
    isempty(fixture_path) && return ""
    root = dirname(dirname(@__DIR__))
    if !haskey(ENV, env_key) &&
            !isfile(joinpath(root, default_stan_model))
        return ""
    end
    return fixture_path
end

function check_source_bridge_fixture(fixture_path::AbstractString,
        target;
        expected_schema::AbstractString,
        expected_stan_model::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == expected_schema
    @test Bool(fixture[:propto]) == false
    @test Bool(fixture[:jacobian]) == false
    @test String(fixture[:stan_model]) == expected_stan_model
    stan_model_path = joinpath(root, expected_stan_model)
    @test isfile(stan_model_path)
    @test String(fixture[:stan_model_sha256]) == file_sha256(stan_model_path)
    @test Vector{String}(fixture[:julia_raw_parameter_order]) == target.blueprint.parameter_names

    data = fixture[:stan_data]
    @test Float64(data[:person_sd]) == target.prior.person_sd
    @test Float64(data[:rater_sd]) == target.prior.rater_sd
    @test Float64(data[:item_sd]) == target.prior.item_sd
    @test Float64(data[:log_discrimination_sd]) == target.prior.log_discrimination_sd
    @test Float64(data[:log_consistency_sd]) == target.prior.log_consistency_sd
    @test Float64(data[:step_sd]) == target.prior.step_sd

    x = Vector{Float64}(fixture[:x])
    @test length(x) == LogDensityProblems.dimension(target)
    tol = haskey(fixture, :tolerance) ? Float64(fixture[:tolerance]) : 1e-6
    stan_lp = Float64(fixture[:stan_log_density])
    @test LogDensityProblems.logdensity(target, x) ≈ stan_lp atol = tol rtol = tol
    if haskey(fixture, :stan_log_likelihood)
        stan_ll = Float64(fixture[:stan_log_likelihood])
        @test stan_lp - BayesianMGMFRM._source_fixture_logprior(target, x) ≈
            stan_ll atol = tol rtol = tol
        @test BayesianMGMFRM._source_fixture_loglikelihood(target, x) ≈
            stan_ll atol = tol rtol = tol
    end
    if haskey(fixture, :stan_pointwise_log_likelihood)
        stan_pointwise = Vector{Float64}(fixture[:stan_pointwise_log_likelihood])
        julia_pointwise = if target.blueprint.family === :gmfrm
            BayesianMGMFRM._gmfrm_source_pointwise_loglikelihood_from_unconstrained(
                target.design,
                x,
            )
        elseif target.blueprint.family === :mgmfrm
            BayesianMGMFRM._mgmfrm_source_pointwise_loglikelihood_from_unconstrained(
                target.design,
                x,
            )
        else
            Float64[]
        end
        @test stan_pointwise ≈ julia_pointwise atol = tol rtol = tol
        @test sum(stan_pointwise) ≈ Float64(fixture[:stan_log_likelihood]) atol = tol rtol = tol
    end

    if haskey(fixture, :stan_gradient)
        adtarget = LogDensityProblemsAD.ADgradient(:ForwardDiff, target; x = x)
        lp, gradient = LogDensityProblems.logdensity_and_gradient(adtarget, x)
        @test lp ≈ stan_lp atol = tol rtol = tol
        stan_gradient = Vector{Float64}(fixture[:stan_gradient])
        @test length(stan_gradient) == length(gradient)
        @test maximum(abs.(gradient .- stan_gradient)) < max(tol, 1e-6)
    end
end

function check_gmfrm_bridge_direct_fixture(fixture_path::AbstractString,
        target)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test haskey(fixture, :stan_constrained_parameter_order)
    @test haskey(fixture, :stan_constrained_parameter_values)
    @test haskey(fixture, :julia_direct_parameter_order)
    @test haskey(fixture, :julia_direct_parameter_values)
    @test haskey(fixture, :stan_log_likelihood)
    @test haskey(fixture, :fit_ready_candidate)

    stan_constrained_names = Vector{String}(fixture[:stan_constrained_parameter_order])
    @test "item.1" in stan_constrained_names
    @test "item_discrimination.1" in stan_constrained_names
    @test "rater_consistency.1" in stan_constrained_names
    @test length(stan_constrained_names) == length(Vector{Float64}(fixture[:stan_constrained_parameter_values]))

    x = Vector{Float64}(fixture[:x])
    transform_diagnostics =
        BayesianMGMFRM._gmfrm_promotion_candidate_transform_diagnostics(target, x)
    pointwise_fixture =
        BayesianMGMFRM._gmfrm_promotion_candidate_pointwise_fixture(target, x)
    tol = haskey(fixture, :tolerance) ? Float64(fixture[:tolerance]) : 1e-6
    @test transform_diagnostics.summary.passed
    @test pointwise_fixture.summary.passed
    @test Vector{String}(fixture[:julia_direct_parameter_order]) ==
        transform_diagnostics.direct_parameter_names
    @test pointwise_fixture.parameter_names == transform_diagnostics.direct_parameter_names
    @test Vector{Float64}(fixture[:julia_direct_parameter_values]) ≈
        transform_diagnostics.direct_parameter_values atol = tol rtol = tol
    @test Vector{Float64}(fixture[:julia_direct_parameter_values]) ≈
        pointwise_fixture.parameter_values atol = tol rtol = tol
    @test sum(transform_diagnostics.direct_pointwise_loglikelihood) ≈
        Float64(fixture[:stan_log_likelihood]) atol = tol rtol = tol
    @test pointwise_fixture.loglikelihood ≈
        Float64(fixture[:stan_log_likelihood]) atol = tol rtol = tol
    candidate = fixture[:fit_ready_candidate]
    @test String(candidate[:schema]) ==
        "bayesianmgmfrm.fit_ready_scalar_gmfrm_bridge_oracle.v1"
    @test String(candidate[:status]) == "internal_fit_ready_candidate"
    @test Bool(candidate[:public_fit]) == false
    @test Bool(candidate[:fit_ready]) == false
    @test Vector{String}(candidate[:raw_parameter_order]) == target.blueprint.parameter_names
    @test Vector{Float64}(candidate[:raw_parameter_values]) ≈ x atol = tol rtol = tol
    @test Float64(candidate[:raw_log_density]) ≈
        LogDensityProblems.logdensity(target, x) atol = tol rtol = tol
    candidate_gradient = Vector{Float64}(candidate[:raw_gradient])
    adtarget = LogDensityProblemsAD.ADgradient(:ForwardDiff, target; x = x)
    _, gradient = LogDensityProblems.logdensity_and_gradient(adtarget, x)
    @test candidate_gradient ≈ gradient atol = max(tol, 1e-6) rtol = max(tol, 1e-6)
    @test Vector{String}(candidate[:direct_parameter_order]) ==
        target.blueprint.constrained_parameter_names
    @test Vector{Float64}(candidate[:direct_parameter_values]) ≈
        pointwise_fixture.parameter_values atol = tol rtol = tol
    @test Vector{Float64}(candidate[:pointwise_log_likelihood]) ≈
        pointwise_fixture.pointwise_loglikelihood atol = tol rtol = tol
    @test Float64(candidate[:log_likelihood]) ≈
        pointwise_fixture.loglikelihood atol = tol rtol = tol
    @test Vector{String}(candidate[:stan_generated_quantity_order]) ==
        ["log_lik.$index" for index in 1:length(pointwise_fixture.pointwise_loglikelihood)]
end

function json_bool_matrix(value)
    rows = [Vector{Bool}(row) for row in value]
    isempty(rows) && return Matrix{Bool}(undef, 0, 0)
    return [rows[row][col] for row in eachindex(rows), col in eachindex(rows[1])]
end

function check_mgmfrm_bridge_confirmatory_fixture(fixture_path::AbstractString,
        target)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test haskey(fixture, :stan_constrained_parameter_order)
    @test haskey(fixture, :stan_constrained_parameter_values)
    @test haskey(fixture, :julia_direct_parameter_order)
    @test haskey(fixture, :julia_direct_parameter_values)
    @test haskey(fixture, :stan_log_likelihood)
    @test haskey(fixture, :confirmatory_candidate)

    stan_constrained_names = Vector{String}(fixture[:stan_constrained_parameter_order])
    @test "item_dimension_discrimination.1" in stan_constrained_names
    @test "rater_consistency.1" in stan_constrained_names
    @test "rater.1" in stan_constrained_names
    @test length(stan_constrained_names) == length(Vector{Float64}(fixture[:stan_constrained_parameter_values]))

    x = Vector{Float64}(fixture[:x])
    direct = BayesianMGMFRM._mgmfrm_source_constrained_params_from_unconstrained(
        target.design,
        x,
    )
    pointwise = BayesianMGMFRM._mgmfrm_source_pointwise_loglikelihood(
        target.design,
        direct,
    )
    tol = haskey(fixture, :tolerance) ? Float64(fixture[:tolerance]) : 1e-6
    @test Vector{String}(fixture[:julia_direct_parameter_order]) ==
        target.blueprint.constrained_parameter_names
    @test Vector{Float64}(fixture[:julia_direct_parameter_values]) ≈
        direct atol = tol rtol = tol
    @test sum(pointwise) ≈ Float64(fixture[:stan_log_likelihood]) atol = tol rtol = tol

    candidate = fixture[:confirmatory_candidate]
    @test String(candidate[:schema]) ==
        "bayesianmgmfrm.fit_ready_confirmatory_mgmfrm_bridge_oracle.v1"
    @test String(candidate[:status]) == "internal_fit_ready_candidate"
    @test Bool(candidate[:public_fit]) == false
    @test Bool(candidate[:fit_ready]) == false
    @test Int(candidate[:dimensions]) == target.design.spec.dimensions
    @test json_bool_matrix(candidate[:q_matrix]) == target.design.spec.q_matrix
    @test String(candidate[:latent_correlation]) == "identity_fixed"
    @test String(candidate[:ability_location]) == "zero_by_dimension"
    @test String(candidate[:ability_scale]) == "unit_variance_by_dimension"
    @test Float64(candidate[:source_scale]) == 1.7
    @test String(candidate[:interpreted_loading_sign]) == "positive"
    @test Vector{String}(candidate[:raw_parameter_order]) == target.blueprint.parameter_names
    @test Vector{Float64}(candidate[:raw_parameter_values]) ≈ x atol = tol rtol = tol
    @test Float64(candidate[:raw_log_density]) ≈
        LogDensityProblems.logdensity(target, x) atol = tol rtol = tol
    candidate_gradient = Vector{Float64}(candidate[:raw_gradient])
    adtarget = LogDensityProblemsAD.ADgradient(:ForwardDiff, target; x = x)
    _, gradient = LogDensityProblems.logdensity_and_gradient(adtarget, x)
    @test candidate_gradient ≈ gradient atol = max(tol, 1e-6) rtol = max(tol, 1e-6)
    @test Vector{String}(candidate[:direct_parameter_order]) ==
        target.blueprint.constrained_parameter_names
    @test Vector{Float64}(candidate[:direct_parameter_values]) ≈
        direct atol = tol rtol = tol
    @test Vector{Float64}(candidate[:pointwise_log_likelihood]) ≈
        pointwise atol = tol rtol = tol
    @test Float64(candidate[:log_likelihood]) ≈
        sum(pointwise) atol = tol rtol = tol
    @test Vector{String}(candidate[:stan_generated_quantity_order]) ==
        ["log_lik.$index" for index in 1:length(pointwise)]
end

function test_parameter_order_hash(names::Vector{String})
    return bytes2hex(sha256(codeunits(join(names, "\n"))))
end
