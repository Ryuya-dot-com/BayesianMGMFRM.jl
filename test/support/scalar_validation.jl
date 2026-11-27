function test_logsumexp(vals)
    m = maximum(vals)
    return m + log(sum(exp(v - m) for v in vals))
end

function test_normal_logpdf(x, sd)
    z = x / sd
    return -log(sd) - 0.5 * (log(2.0 * pi) + z * z)
end

function test_sample_variance(vals)
    n = length(vals)
    m = sum(Float64, vals) / n
    return sum((Float64(v) - m)^2 for v in vals) / (n - 1)
end

function raw_pcm_pointwise(data, person, rater, item, steps_by_item)
    K = length(data.category_levels)
    out = Vector{Float64}(undef, data.n)
    for n in 1:data.n
        location = person[data.person[n]] - rater[data.rater[n]] - item[data.item[n]]
        steps = steps_by_item[data.item[n]]
        etas = [
            (category - 1) * location - sum(steps[1:(category - 1)]; init = 0.0)
            for category in 1:K
        ]
        out[n] = etas[data.category[n]] - test_logsumexp(etas)
    end
    return out
end

function scalar_validation_fixture_data(fixture)
    data = fixture[:data]
    return ScalarValidationData(
        X = Vector{Int}(data[:X]),
        examinee = Vector{Int}(data[:examinee]),
        rater = Vector{Int}(data[:rater]),
        J = Int(data[:J]),
        R = Int(data[:R]),
        K = Int(data[:K]),
        N = Int(data[:N]),
    )
end

function check_scalar_validation_stan_pair(known_fixture_path::AbstractString,
        stan_fixture_path::AbstractString;
        expected_size::Union{Nothing,String} = nothing,
        expected_counts::Union{Nothing,NTuple{4,Int}} = nothing)
    known = JSON3.read(read(known_fixture_path, String))
    @test String(known[:schema]) == "bayesianmgmfrm.scalar_validation_known_value.v1"
    if expected_size !== nothing
        @test String(known[:size]) == expected_size
    end
    fd = scalar_validation_fixture_data(known)
    if expected_counts !== nothing
        @test (fd.J, fd.R, fd.K, fd.N) == expected_counts
    end
    x = Vector{Float64}(known[:x])
    @test length(x) == scalar_validation_num_params(fd)
    lp, gradient = scalar_validation_logposterior_and_gradient(x, fd)
    known_tol = Float64(known[:tolerance])
    @test lp ≈ Float64(known[:log_density]) atol = known_tol rtol = known_tol
    @test maximum(abs.(gradient .- Vector{Float64}(known[:gradient]))) < known_tol

    stan = JSON3.read(read(stan_fixture_path, String))
    @test String(stan[:schema]) == "bayesianmgmfrm.scalar_stan_logdensity.v1"
    if expected_size !== nothing
        @test String(stan[:size]) == expected_size
    end
    @test Bool(stan[:propto]) == false
    @test Bool(stan[:jacobian]) == true
    @test String(stan[:stan_model]) == "test/stan/scalar_gmfrm.stan"
    @test String(stan[:stan_model_sha256]) ==
        file_sha256(joinpath(dirname(@__DIR__), "stan", "scalar_gmfrm.stan"))
    @test String(stan[:known_fixture]) ==
        "test/fixtures/$(basename(known_fixture_path))"
    @test String(stan[:known_fixture_sha256]) == file_sha256(known_fixture_path)
    stan_data = stan[:stan_data]
    @test (Int(stan_data[:J]), Int(stan_data[:R]), Int(stan_data[:K]), Int(stan_data[:N])) ==
        (fd.J, fd.R, fd.K, fd.N)
    @test Vector{Float64}(stan[:x]) == x
    @test length(Vector{String}(stan[:stan_parameter_order])) == length(x)
    stan_tol = Float64(stan[:tolerance])
    stan_lp = Float64(stan[:stan_log_density])
    stan_gradient = Vector{Float64}(stan[:stan_gradient])
    @test lp ≈ Float64(stan[:stan_log_density]) atol = stan_tol rtol = stan_tol
    @test maximum(abs.(gradient .- stan_gradient)) < max(stan_tol, 1e-9)
    validation_row = stan_validation_row(fd, x, stan_lp;
        stan_gradient,
        tolerance = stan_tol,
        label = expected_size === nothing ? :scalar_validation : Symbol("scalar_", expected_size),
        size = expected_size === nothing ? nothing : Symbol(expected_size),
        known_log_density = Float64(known[:log_density]),
        known_gradient = Vector{Float64}(known[:gradient]),
        known_tolerance = known_tol,
        fixture_path = relpath(stan_fixture_path, dirname(dirname(@__DIR__))),
        known_fixture_path = relpath(known_fixture_path, dirname(dirname(@__DIR__))),
        stan_model = String(stan[:stan_model]),
        fixture_sha256 = file_sha256(stan_fixture_path),
        known_fixture_sha256 = file_sha256(known_fixture_path),
        stan_model_sha256 = String(stan[:stan_model_sha256]),
    )
    @test validation_row.passed
    @test validation_row.gradient_checked
    @test validation_row.known_gradient_checked
    @test validation_row.n_observations == fd.N
    @test validation_row.n_parameters == length(x)
    return (;
        known,
        stan,
        data = fd,
        x,
        log_density = lp,
        gradient,
        validation_row,
    )
end
