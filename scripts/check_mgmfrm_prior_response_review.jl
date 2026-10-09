# Independent production check of the Python prior-response study. No fitting.
# julia --startup-file=no --compiled-modules=existing --project=. scripts/check_mgmfrm_prior_response_review.jl OUTPUT_DIRECTORY
using BayesianMGMFRM, JSON3, LinearAlgebra, ForwardDiff, Test, SHA
const B = BayesianMGMFRM
length(ARGS) == 1 || error("Supply the prior-response output directory")
root = abspath(only(ARGS))
readjson(name) = JSON3.read(read(joinpath(root, name), String))
plan = readjson("plan.json")
cells = [(p, i, r) for p in String.(plan.persons) for i in String.(plan.items) for r in String.(plan.raters)]
# Cyclic placeholders construct the design only; neither the prior nor prediction
# reads their values. They are not observed or prior-predictive outcome data.
data = FacetData((; person=first.(cells), item=getindex.(cells, 2), rater=last.(cells),
    score=mod.(0:(length(cells)-1), 4) .+ 1);
    person=:person, item=:item, rater=:rater, score=:score, category_levels=1:4)
spec = mfrm_spec(data; family=:mgmfrm, dimensions=2, thresholds=:partial_credit,
    discrimination=:none, q_matrix=Bool[1 0; 1 0; 0 1; 0 1; 0 1])
matrix(rows) = reduce(vcat, permutedims.(Vector{Float64}.(rows)))
checks = Dict{String, Any}()
@testset "Joint prior predictions agree with production; no fits" begin
    @test data.person_levels == String.(plan.persons)
    @test data.item_levels == String.(plan.items)
    @test data.rater_levels == String.(plan.raters)
    for (name, expected) in pairs(plan.source_sha256)
        @test bytes2hex(sha256(read(joinpath(@__DIR__, "..", String(name))))) == expected
    end
    probes = readjson("production-probes.json")
    for (case, probe) in zip(plan.cases, probes)
        @test case.id == probe.id
        scales = (; (key => Float64(value) for (key, value) in pairs(case.scales))...)
        base = B._mgmfrm_guarded_local_fit_logdensity(spec; prior=B._SourceFixturePrior(; scales...))
        normalized = case.model == "exchangeable" ?
            B._MGMFRMNormalizedPriorLogDensity(spec; prior_model=:exchangeable, scales) : nothing
        lp = normalized === nothing ? x -> B._source_fixture_logprior(base, x) : x -> B.logprior(normalized, x)
        raw = matrix(probe.raw)
        @test size(raw) == (6, 128)
        @test base.blueprint.blocks[:person] == 1:100
        @test base.blueprint.blocks[:rater_free] == 101:104
        @test base.blueprint.blocks[:item] == 105:109
        @test base.blueprint.blocks[:log_item_dimension_discrimination] == 110:114
        @test base.blueprint.blocks[:log_rater_consistency_free] == 115:118
        @test base.blueprint.blocks[:item_steps] == 119:128
        # Prove the generator's Gaussian law using its linear map, not a finite
        # Monte Carlo moment test. Raw discards the last normal in each block.
        sd = vcat(fill(scales.person_sd, 100), fill(scales.rater_sd, 4),
            fill(scales.item_sd, 5), fill(scales.log_discrimination_sd, 5),
            fill(scales.log_consistency_sd, 4), fill(scales.step_sd, 10))
        covariance = Matrix(Diagonal(sd.^2))
        if normalized !== nothing
            blocks = [(101:104, scales.rater_sd), (115:118, scales.log_consistency_sd)]
            append!(blocks, [(start:(start+1), scales.step_sd) for start in 119:2:127])
            for (indices, tau) in blocks
                n = length(indices)+1
                projection = Matrix{Float64}(I, n, n) .- 1/n
                A = tau .* projection[1:(n-1), :]
                covariance[indices, indices] = A*A'
            end
        end
        origin = zeros(128)
        target_covariance = inv(-ForwardDiff.hessian(lp, origin))
        @test target_covariance ≈ covariance atol=1e-12
        @test norm(ForwardDiff.gradient(lp, origin)) < 1e-12
        density_error = maximum(abs(lp(vec(raw[j, :]))-probe.logprior[j]) for j in axes(raw, 1))
        @test density_error < 1e-10
        max_error = 0.
        for j in axes(raw, 1)
            direct = B._mgmfrm_source_constrained_params_from_unconstrained(base.design, vec(raw[j, :]), base.blueprint)
            actual = B._mgmfrm_predictive_probabilities_direct(base.design, permutedims(direct))[1, :, :]
            expected = matrix(probe.probabilities[j])
            max_error = max(max_error, maximum(abs.(actual-expected)))
            @test actual ≈ expected atol=1e-12 rtol=1e-12
            @test maximum(abs.(sum(actual; dims=2).-1)) < 1e-12
        end
        checks[String(case.id)] = (; n_probes=6, probability_entries=6*1250*4,
            maximum_probability_error=max_error, maximum_prior_logdensity_error=density_error,
            maximum_covariance_error=maximum(abs.(target_covariance-covariance)))
    end
    base = B._mgmfrm_guarded_local_fit_logdensity(spec)
    for probe in readjson("mechanisms.json").probes
        direct = B._mgmfrm_source_constrained_params_from_unconstrained(base.design,
            Vector{Float64}(probe.raw), base.blueprint)
        actual = B._mgmfrm_predictive_probabilities_direct(base.design, permutedims(direct))[1, 1, :]
        @test actual ≈ Vector{Float64}(probe.first_cell_probabilities) atol=1e-12
    end
end
path = joinpath(root, "production-check.json")
ispath(path) && error("Preserve existing check result: $path")
write(path, JSON3.write((; julia_version=string(VERSION), cases=checks,
    mechanism_probes=9, posterior_fits=0, passed=true)))
println("Production probabilities, prior densities and Gaussian generator covariances agree.")
