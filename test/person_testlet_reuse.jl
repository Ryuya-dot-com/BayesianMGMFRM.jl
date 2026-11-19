using Test, BayesianMGMFRM, ForwardDiff, LinearAlgebra, Random, Statistics
using Distributions: Normal, LogNormal, logpdf, params

# Independent Bradlow–Wainer–Wang (1999) / Wang–Wilson (2005) scalar Rasch/PCM
# person-by-testlet target in positive u_{p,d} ~ Normal(0, sigma_u^2) coordinates:
#   eta_n = theta_{p(n)} + mu + u_{p(n), d(n)} - beta_item[i(n)] - beta_rater[r(n)]
function direct_testlet_reference(table, q_pos;
        K::Int, prior_person::LogNormal, prior_testlet::LogNormal,
        sd_item::Float64, sd_rater::Float64, sd_step::Float64, prior_intercept::Normal)
    H(m) = [i <= j ? 1 / sqrt(j * (j + 1)) : i == j + 1 ? -j / sqrt(j * (j + 1)) : 0.0 for i in 1:m, j in 1:m-1]
    people = sort(unique(table[:person])); P = length(people); p_map = Dict(x => j for (j, x) in enumerate(people))
    clusters = sort(unique(table[:person_testlet])); C = length(clusters); c_map = Dict(x => j for (j, x) in enumerate(clusters))
    items = sort(unique(table[:item])); I = length(items); i_map = Dict(x => j for (j, x) in enumerate(items))
    raters = sort(unique(table[:rater])); R = length(raters); r_map = Dict(x => j for (j, x) in enumerate(raters))

    # Raw layout matching ExplanatoryTarget:
    # person(P), person_testlet(C), item(I-1), rater(R-1), steps(K-2), intercept(1), log_sd_person(1), log_sd_testlet(1)
    Z = eltype(q_pos)
    off = 0
    z_p = q_pos[off+1:off+P]; off += P
    z_u = q_pos[off+1:off+C]; off += C
    z_i = q_pos[off+1:off+(I-1)]; off += I - 1
    z_r = q_pos[off+1:off+(R-1)]; off += R - 1
    z_s = q_pos[off+1:off+(K-2)]; off += K - 2
    z_mu = q_pos[off+1]; off += 1
    z_ls_p = q_pos[off+1]; off += 1
    z_ls_u = q_pos[off+1]; off += 1

    lp_m, lp_s = params(prior_person)
    lu_m, lu_s = params(prior_testlet)
    mu_0, sd_0 = params(prior_intercept)

    sig_p = exp(lp_m + lp_s * z_ls_p)
    sig_u = exp(lu_m + lu_s * z_ls_u)
    scale_i = sd_item * sqrt(I / (I - 1))
    scale_r = sd_rater * sqrt(R / (R - 1))
    scale_s = K > 2 ? sd_step * sqrt((K - 1) / (K - 2)) : 0.0

    theta = sig_p .* z_p
    u_pos = sig_u .* z_u
    beta_i = scale_i .* (H(I) * z_i)
    beta_r = scale_r .* (H(R) * z_r)
    tau = K > 2 ? scale_s .* (H(K - 1) * z_s) : zeros(Z, 1)
    mu = mu_0 + sd_0 * z_mu

    # Normalized white prior equals model-coordinate centered prior + Jacobian log-volume `lv`
    lprior_white = sum(logpdf.(Normal(), q_pos))
    lprior_centered = sum(logpdf.(Normal(zero(Z), sig_p), theta)) + logpdf(prior_person, sig_p) +
                      sum(logpdf.(Normal(zero(Z), sig_u), u_pos)) + logpdf(prior_testlet, sig_u) +
                      sum(logpdf.(Normal(zero(Z), scale_i), scale_i .* z_i)) +
                      sum(logpdf.(Normal(zero(Z), scale_r), scale_r .* z_r)) +
                      (K > 2 ? sum(logpdf.(Normal(zero(Z), scale_s), scale_s .* z_s)) : zero(Z)) +
                      logpdf(prior_intercept, mu)
    lv = P * log(sig_p) + log(lp_s) + log(sig_p) +
         C * log(sig_u) + log(lu_s) + log(sig_u) +
         (I - 1) * log(scale_i) + (R - 1) * log(scale_r) +
         (K > 2 ? (K - 2) * log(scale_s) : zero(Z)) + log(sd_0)

    ll = zero(Z)
    ys = table[:score]
    for n in eachindex(ys)
        eta = theta[p_map[table[:person][n]]] + mu + u_pos[c_map[table[:person_testlet][n]]] -
              beta_i[i_map[table[:item][n]]] - beta_r[r_map[table[:rater][n]]]
        y_idx = ys[n] + 1 # 0:(K-1) -> 1:K
        w = [k == 0 ? zero(Z) : k * eta - sum(tau[1:k]) for k in 0:(K-1)]
        mx = maximum(w)
        ll += w[y_idx] - mx - log(sum(exp.(w .- mx)))
    end
    (; density = lprior_white + ll, prior = lprior_white, centered_plus_volume = lprior_centered + lv, ll, volume = lv)
end

function build_testlet_fixture(; P = 6, D_testlets = 3, items_per_testlet = 2, R = 3, K = 4)
    rows = NamedTuple[]
    for p in 1:P, d in 1:D_testlets, j in 1:items_per_testlet, r in 1:R
        mod(p + d + r, 3) == 0 && continue
        item_id = "T$(d)_I$(j)"
        pt_id = "P$(p)_T$(d)"
        push!(rows, (; person = "P$(p)", testlet = "T$(d)", person_testlet = pt_id,
            item = item_id, rater = "R$(r)", score = mod(p + d + j + r, K)))
    end
    Dict{Symbol,Vector}(
        :person => [r.person for r in rows],
        :testlet => [r.testlet for r in rows],
        :person_testlet => [r.person_testlet for r in rows],
        :item => [r.item for r in rows],
        :rater => [r.rater for r in rows],
        :score => [r.score for r in rows],
    )
end

@testset "Person-by-testlet scalar reuse: target equivalence, zero reduction, identification boundaries, and new-cluster prediction" begin
    A = BayesianMGMFRM.AdditiveFacets
    for K in (2, 4)
        tbl = build_testlet_fixture(; K)
        p_per = LogNormal(log(0.75), 0.35)
        p_tst = LogNormal(log(0.45), 0.40)
        p_int = Normal(0.1, 0.8)
        step_sd = K == 2 ? 0.0 : 0.45

        spec = mfrm_spec(tbl;
            person = :person,
            performance = :person_testlet,
            score = :score,
            facets = (person_testlet = :person_testlet, item = :item, rater = :rater),
            steps = :global,
            category_levels = 0:(K-1),
            population = (person = p_per, person_testlet = p_tst),
            prior_sd = (facets = (item = 0.65, rater = 0.45), step = step_sd),
            intercept = p_int,
        )
        @test spec isa A.ExplanatoryTarget
        @test validate_design(spec).identified
        @test validate_design(spec).covariance_rank == 2

        P = length(unique(tbl[:person]))
        C = length(unique(tbl[:person_testlet]))
        u_range = (P + 1):(P + C)

        # Isometric reflection z_u -> -z_u maps positive u_{p,d} onto facet severity person_testlet[c] = -u_{p,d}
        for q_pos in (zeros(spec.dimension), 0.19 .* sin.(1:spec.dimension), collect(range(-1.4, 1.4; length = spec.dimension)))
            q_pkg = copy(q_pos)
            q_pkg[u_range] .*= -1.0
            ref = direct_testlet_reference(tbl, q_pos;
                K, prior_person = p_per, prior_testlet = p_tst,
                sd_item = 0.65, sd_rater = 0.45, sd_step = step_sd, prior_intercept = p_int)
            lp, g_pkg = logdensity_and_gradient(spec, q_pkg)
            g_ref_pos = ForwardDiff.gradient(x -> direct_testlet_reference(tbl, x;
                K, prior_person = p_per, prior_testlet = p_tst,
                sd_item = 0.65, sd_rater = 0.45, sd_step = step_sd, prior_intercept = p_int).density, q_pos)
            g_expected = copy(g_ref_pos)
            g_expected[u_range] .*= -1.0

            @test abs(lp - ref.density) / max(1.0, abs(ref.density)) <= 1e-14
            @test abs(logprior(spec, q_pkg) - ref.prior) / max(1.0, abs(ref.prior)) <= 1e-14
            @test abs(logprior(spec, q_pkg) - ref.centered_plus_volume) / max(1.0, abs(ref.prior)) <= 1e-13
            @test abs(coordinates(spec, q_pkg).log_volume - ref.volume) <= 1e-14
            @test maximum(abs.(g_pkg .- g_expected)) / max(1.0, norm(g_expected, Inf)) <= 1e-13

            v = coordinates(spec, q_pkg)
            @test v.residual_sd[:person_testlet] ≈ exp(log(0.45) + 0.40 * q_pos[end]) atol = 1e-15
        end

        # Exact zero-variance reduction (`population = (..., person_testlet = 0.0)`) vs. omitting `person_testlet`
        spec_zero = mfrm_spec(tbl;
            person = :person,
            performance = :person_testlet,
            score = :score,
            facets = (person_testlet = :person_testlet, item = :item, rater = :rater),
            steps = :global,
            category_levels = 0:(K-1),
            population = (person = p_per, person_testlet = 0.0),
            prior_sd = (facets = (item = 0.65, rater = 0.45), step = step_sd),
            intercept = p_int,
        )
        spec_omitted = mfrm_spec(tbl;
            person = :person,
            performance = :person_testlet,
            score = :score,
            facets = (item = :item, rater = :rater),
            steps = :global,
            category_levels = 0:(K-1),
            population = (person = p_per,),
            prior_sd = (facets = (item = 0.65, rater = 0.45), step = step_sd),
            intercept = p_int,
        )
        @test spec_zero.dimension == spec_omitted.dimension
        @test validate_design(spec_zero).identified
        for q0 in (zeros(spec_zero.dimension), 0.23 .* cos.(1:spec_zero.dimension))
            lp_z, g_z = logdensity_and_gradient(spec_zero, q0)
            lp_o, g_o = logdensity_and_gradient(spec_omitted, q0)
            @test abs(lp_z - lp_o) / max(1.0, abs(lp_o)) <= 1e-14
            @test maximum(abs.(g_z .- g_o)) / max(1.0, norm(g_o, Inf)) <= 1e-14
        end
        # Verify record/restore roundtrip on spec_zero and identical observation_binding with spec
        @test isequal(A.record(spec_zero), A.record(A.restore(A.record(spec_zero))))
        d_eff = BayesianMGMFRM._explanatory_profile_design(spec, :performance, :person_testlet)
        d_zero = BayesianMGMFRM._explanatory_profile_design(spec_zero, :performance, :person_testlet)
        @test d_eff.observation_binding == d_zero.observation_binding
    end

    # Identification & allocation boundaries / counterexamples
    tbl = build_testlet_fixture(; K = 4)

    # 1. Nested items in testlets: adding unconstrained finite sum-zero `testlet` aliases `item`
    spec_nested_alias = mfrm_spec(tbl;
        person = :person, performance = :person_testlet, score = :score,
        facets = (person_testlet = :person_testlet, testlet = :testlet, item = :item, rater = :rater),
        steps = :global, category_levels = 0:3,
        population = (person = LogNormal(0.0, 0.35), person_testlet = LogNormal(-0.7, 0.35)),
        prior_sd = (facets = (testlet = 0.5, item = 0.65, rater = 0.45), step = 0.45),
        intercept = Normal(0.0, 0.8),
    )
    @test !validate_design(spec_nested_alias).identified
    @test validate_design(spec_nested_alias).rank < validate_design(spec_nested_alias).columns

    # Pooling `testlet` in `population` resolves the finite-contrast colinearity (hierarchical shrinkage of item/testlet means)
    spec_nested_pooled = mfrm_spec(tbl;
        person = :person, performance = :person_testlet, score = :score,
        facets = (person_testlet = :person_testlet, testlet = :testlet, item = :item, rater = :rater),
        steps = :global, category_levels = 0:3,
        population = (person = LogNormal(0.0, 0.35), person_testlet = LogNormal(-0.7, 0.35), testlet = LogNormal(-0.5, 0.35)),
        prior_sd = (facets = (item = 0.65, rater = 0.45), step = 0.45),
        intercept = Normal(0.0, 0.8),
    )
    @test validate_design(spec_nested_pooled).identified

    # 2. One testlet per person (`person == person_testlet`) -> variance components aliased
    tbl_one_t = Dict(k => v[tbl[:testlet] .== "T1"] for (k, v) in tbl)
    spec_one_t = mfrm_spec(tbl_one_t;
        person = :person, performance = :person_testlet, score = :score,
        facets = (person_testlet = :person_testlet, item = :item, rater = :rater),
        steps = :global, category_levels = 0:3,
        population = (person = LogNormal(0.0, 0.35), person_testlet = LogNormal(-0.7, 0.35)),
        prior_sd = (facets = (item = 0.65, rater = 0.45), step = 0.45),
        intercept = Normal(0.0, 0.8),
    )
    @test !validate_design(spec_one_t).identified
    @test validate_design(spec_one_t).covariance_rank == 1

    # 3. Unreplicated `(person, testlet)` clusters (1 observation per cluster) -> refused
    first_rows = [findfirst(==(pt), tbl[:person_testlet]) for pt in unique(tbl[:person_testlet])]
    tbl_unrep = Dict(k => v[first_rows] for (k, v) in tbl)
    spec_unrep = mfrm_spec(tbl_unrep;
        person = :person, performance = :person_testlet, score = :score,
        facets = (person_testlet = :person_testlet, item = :item, rater = :rater),
        steps = :global, category_levels = 0:3,
        population = (person = LogNormal(0.0, 0.35), person_testlet = LogNormal(-0.7, 0.35)),
        prior_sd = (facets = (item = 0.65, rater = 0.45), step = 0.45),
        intercept = Normal(0.0, 0.8),
    )
    @test !validate_design(spec_unrep).identified
    @test :person_testlet in validate_design(spec_unrep).unreplicated

    # 4. Small end-to-end smoke: matched comparator held-cluster criteria + new-owner prediction + refusals
    spec_t = mfrm_spec(tbl;
        person = :person, performance = :person_testlet, score = :score,
        facets = (person_testlet = :person_testlet, item = :item, rater = :rater),
        steps = :global, category_levels = 0:3,
        population = (person = LogNormal(log(0.75), 0.35), person_testlet = LogNormal(log(0.45), 0.40)),
        prior_sd = (facets = (item = 0.65, rater = 0.45), step = 0.45),
        intercept = Normal(0.0, 0.8),
    )
    spec_0 = mfrm_spec(tbl;
        person = :person, performance = :person_testlet, score = :score,
        facets = (person_testlet = :person_testlet, item = :item, rater = :rater),
        steps = :global, category_levels = 0:3,
        population = (person = LogNormal(log(0.75), 0.35), person_testlet = 0.0),
        prior_sd = (facets = (item = 0.65, rater = 0.45), step = 0.45),
        intercept = Normal(0.0, 0.8),
    )
    f_t = fit(spec_t; chains = 2, warmup = 60, ndraws = 60, seed = 4101)
    f_0 = fit(spec_0; chains = 2, warmup = 60, ndraws = 60, seed = 4102)

    c_t = criteria(f_t; unit = :performance, integrate = :person_testlet)
    c_0 = criteria(f_0; unit = :performance, integrate = :person_testlet)
    @test all(r -> r.original.quadrature_error <= 1e-13, c_0.rows)
    cmp = compare_models("Person × testlet" => c_t, "Matched no-testlet" => c_0;
        criterion = :psis_loo, independent_model_rng = true)
    @test isfinite(cmp.difference)

    # Known person, new `(person, testlet)` cluster (`new_owners = (:person_testlet,)`)
    new_cluster_df = (;
        person = ["P1", "P1"],
        person_testlet = ["P1_TNEW", "P1_TNEW"],
        item = ["T1_I1", "T1_I2"],
        rater = ["R1", "R2"],
    )
    @test_throws ArgumentError predict(f_t; data = new_cluster_df, mode = :known_owners)
    p_nc = predict(f_t; data = new_cluster_df, mode = :new_owners, new_owners = (:person_testlet,), seed = 701)
    @test p_nc.mode === :new_owners
    @test !p_nc.zero_effect_substitution
    @test all(isapprox.(vec(sum(p_nc.mean; dims = 2)), 1.0; atol = 1e-12))

    # New person AND new `(person, testlet)` cluster (`new_owners = (:person, :person_testlet)`)
    new_person_df = (;
        person = ["P_NEW", "P_NEW"],
        person_testlet = ["P_NEW_T1", "P_NEW_T1"],
        item = ["T1_I1", "T1_I2"],
        rater = ["R1", "R2"],
    )
    # Forgetting `:person_testlet` when `:person` is new must throw!
    @test_throws ArgumentError predict(f_t; data = new_person_df, mode = :new_owners, new_owners = (:person,), seed = 702)
    p_np = predict(f_t; data = new_person_df, mode = :new_owners, new_owners = (:person, :person_testlet), seed = 702)
    @test p_np.mode === :new_owners
    @test length(p_np.expected_score_cells) == 2

    # Unseen finite sum-zero `item` must be refused even in `new_owners`!
    unseen_item_df = (;
        person = ["P1"],
        person_testlet = ["P1_TNEW"],
        item = ["UNSEEN_ITEM"],
        rater = ["R1"],
    )
    @test_throws ArgumentError predict(f_t; data = unseen_item_df, mode = :new_owners, new_owners = (:person_testlet, :item), seed = 703)

    # Save & reload report roundtrip on `p_nc`
    mktempdir() do tmp
        rp = save_report(joinpath(tmp, "new_cluster_pred.json"), p_nc; return_receipt = true)
        reloaded = load_report(rp.path; expected_sha256 = rp.sha256)
        @test [c.mean for c in reloaded.cells] ≈ [c.mean for c in p_nc.cells] atol = 1e-12
    end
end
