using BayesianMGMFRM
using Test

@testset "Stan/brms NUTS control aliases, help guidance & migration docs" begin
    tbl = (;
        person = repeat(["P1", "P2", "P3", "P4"], inner = 6),
        rater = repeat(repeat(["R1", "R2", "R3"], inner = 2), outer = 4),
        item = repeat(["I1", "I2"], outer = 12),
        score = [0, 1, 1, 2, 0, 2,  1, 1, 2, 2, 1, 2,  0, 0, 1, 1, 0, 1,  1, 2, 2, 2, 1, 2],
    )
    fd = FacetData(tbl; person = :person, rater = :rater, item = :item, score = :score, category_levels = [0, 1, 2])
    spec = mfrm_spec(fd; thresholds = :rating_scale)

    # 1. Canonical fit emits no alias info; alias fit emits helpful @info and yields 0.0-ULP identical draws
    f_canon = @test_logs fit(spec;
        backend = :advancedhmc, chains = 2, warmup = 30, ndraws = 30,
        target_accept = 0.92, max_depth = 11, seed = 20261118)

    f_alias = @test_logs (:info, r"adapt_delta = 0\.92.*target_accept.*\?BayesianMGMFRM\.fit") (:info, r"max_treedepth = 11.*max_depth.*\?BayesianMGMFRM\.fit") fit(spec;
        backend = :advancedhmc, chains = 2, warmup = 30, ndraws = 30,
        adapt_delta = 0.92, max_treedepth = 11, seed = 20261118)

    @test f_alias.draws == f_canon.draws
    @test f_alias.log_posterior == f_canon.log_posterior
    @test sampler_controls(f_alias).target_accept == 0.92
    @test sampler_controls(f_alias).max_depth == 11

    # Random-walk backend warns that :julia is not NUTS when alias is supplied
    @test_logs (:info, r"backend = :julia.*random-walk Metropolis") fit(spec;
        backend = :julia, chains = 1, warmup = 10, ndraws = 10, adapt_delta = 0.85, seed = 11)

    # 2. Exact cache-key & cached_fit parity
    k_canon = fit_cache_key(spec; backend = :advancedhmc, chains = 2, warmup = 30, ndraws = 30,
        target_accept = 0.92, max_depth = 11, seed = 20261118)
    k_alias = fit_cache_key(spec; backend = :advancedhmc, chains = 2, warmup = 30, ndraws = 30,
        adapt_delta = 0.92, max_treedepth = 11, seed = 20261118)
    @test k_alias == k_canon

    mktempdir() do dir
        cp1 = joinpath(dir, "cache1.jls")
        c1 = @test_logs (:info, r"adapt_delta") (:info, r"max_treedepth") cached_fit(spec;
            cache_path = cp1, backend = :advancedhmc, chains = 2, warmup = 25, ndraws = 25,
            adapt_delta = 0.91, max_treedepth = 9, seed = 77)
        c2 = cached_fit(spec;
            cache_path = cp1, backend = :advancedhmc, chains = 2, warmup = 25, ndraws = 25,
            target_accept = 0.91, max_depth = 9, seed = 77)
        @test c2.draws == c1.draws
    end

    # 3. Generalized AdditiveFacets / ExplanatoryTarget & CriterionCollapse & StarAssociation
    af_spec = mfrm_spec(tbl; person = :person, score = :score,
        facets = (rater = :rater, item = :item), steps = :global, category_levels = 0:2,
        prior_sd = (person = 1.0, facets = (rater = 1.0, item = 1.0), step = 1.0))
    af_canon = fit(af_spec; chains = 2, warmup = 25, ndraws = 25, target_accept = 0.93, max_depth = 9, seed = 55)
    af_alias = @test_logs (:info, r"adapt_delta = 0\.93") (:info, r"max_treedepth = 9") fit(af_spec;
        chains = 2, warmup = 25, ndraws = 25, adapt_delta = 0.93, max_treedepth = 9, seed = 55)
    @test af_alias.record.run.draws == af_canon.record.run.draws
    @test sampler_controls(af_alias).target_accept == 0.93
    @test sampler_controls(af_alias).max_depth == 9

    cc_prior = BayesianMGMFRM.Experimental.CriterionCollapse.Prior(
        person_precision_shape = 2.0, person_precision_rate = 1.0,
        rater_precision_shape = 2.0, rater_precision_rate = 1.0,
        step_sd = 1.5, class_alpha = 2.0, class_beta = 2.0)
    cc_t = BayesianMGMFRM.Experimental.CriterionCollapse.model(fd; prior = cc_prior)
    cc_alias = @test_logs (:info, r"adapt_delta = 0\.94") (:info, r"max_treedepth = 8") fit(cc_t;
        chains = 4, warmup = 20, ndraws = 20, adapt_delta = 0.94, max_treedepth = 8, seed = 88)
    @test sampler_controls(cc_alias).target_accept == 0.94
    @test sampler_controls(cc_alias).max_depth == 8

    star_criteria = [
        (; criterion = "C1", role = :root, levels = [0, 1, 2], direction = :higher_is_more),
        (; criterion = "C2", levels = [0, 1, 2], direction = :higher_is_more),
    ]
    star_prior = (;
        entity_log_sd_mean = log(0.8), rater_log_sd_mean = log(0.5), log_sd_sd = 0.5,
        entity_lkj_eta = 2.0, rater_lkj_eta = 2.0, mu_sd = 1.5, step_sd = 0.8, step_spacing = 0.6, phi_sd = 0.5,
    )
    star_rows = [
        (; observation_id = "o_$(p)_$(r)_$(c)", rating_event_id = "ev_$(p)_$(r)",
           entity = "E$p", rater = "R$r", criterion = c, score = mod(p + r + (c == "C2"), 3))
        for p in 1:4 for r in 1:3 for c in ("C1", "C2")
    ]
    star_spec = BayesianMGMFRM.Experimental.joint_rating_spec(star_rows;
        criteria = star_criteria, prior = star_prior, association = :star)
    star_alias = @test_logs (:info, r"adapt_delta = 0\.88") (:info, r"max_treedepth = 8") fit(star_spec;
        chains = 2, warmup = 15, ndraws = 15, adapt_delta = 0.88, max_treedepth = 8, seed = 99)
    @test sampler_controls(star_alias).target_accept == 0.88
    @test sampler_controls(star_alias).max_depth == 8

    # 4. qualify BFMI aliases (`min_bfmi`, `ebfmi_min`, `bfmi_min`)
    q1 = qualify(f_canon; min_bfmi = 0.25)
    q2 = @test_logs (:info, r"ebfmi_min = 0\.25.*min_bfmi") qualify(f_canon; ebfmi_min = 0.25)
    q3 = @test_logs (:info, r"bfmi_min = 0\.25.*min_bfmi") qualify(f_canon; bfmi_min = 0.25)
    @test q1.thresholds.min_bfmi == 0.25
    @test q2.thresholds.min_bfmi == 0.25
    @test q3.thresholds.min_bfmi == 0.25
    @test_throws ArgumentError qualify(f_canon; min_bfmi = 0.25, ebfmi_min = 0.25)
    @test_throws ArgumentError qualify(f_canon; ebfmi_min = 0.25, bfmi_min = 0.25)
    @test qualify(star_alias; bfmi_min = 0.25).result.thresholds.ebfmi_min == 0.25
    @test_throws ArgumentError qualify(star_alias; min_bfmi = 0.25, bfmi_min = 0.25)

    # 5. Deterministic conflict & invalid-value errors
    @test_throws ArgumentError fit(spec; backend = :advancedhmc, target_accept = 0.9, adapt_delta = 0.9)
    @test_throws ArgumentError fit(spec; backend = :advancedhmc, max_depth = 10, max_treedepth = 10)
    @test_throws ArgumentError fit(spec; backend = :advancedhmc, adapt_delta = 1.0)
    @test_throws ArgumentError fit(spec; backend = :advancedhmc, adapt_delta = 0.0)
    @test_throws ArgumentError fit(spec; backend = :advancedhmc, adapt_delta = true)
    @test_throws ArgumentError fit(spec; backend = :advancedhmc, max_treedepth = 0)
    @test_throws TypeError fit(spec; backend = :advancedhmc, max_treedepth = 10.5)
    @test_throws ArgumentError fit(spec; method = :jmle, adapt_delta = 0.9)
    @test_throws ArgumentError fit(af_spec; chains = 2, warmup = 10, ndraws = 10, seed = 1, target_accept = 0.9, adapt_delta = 0.9)

    # 6. StanAdapter.fit_stan & import_csv alias checks
    if cmdstan_backend_check().runtime_ready
        mktempdir() do sdir
            stan_code = """
            data { int<lower=1> N; array[N] int<lower=0, upper=1> y; }
            parameters { real theta; }
            model { theta ~ normal(0, 1); y ~ bernoulli_logit(theta); }
            """
            sdata = Dict("N" => 6, "y" => [1, 0, 1, 1, 0, 1])
            sroles = (parameters = (person = ["theta"],),)
            sf_canon = BayesianMGMFRM.StanAdapter.fit_stan(stan_code, sdata;
                roles = sroles, chains = 2, warmup = 30, ndraws = 30,
                target_accept = 0.91, max_depth = 9, seed = 20261118)
            sf_alias = @test_logs (:info, r"adapt_delta = 0\.91") (:info, r"max_treedepth = 9") BayesianMGMFRM.StanAdapter.fit_stan(
                stan_code, sdata;
                roles = sroles, chains = 2, warmup = 30, ndraws = 30,
                adapt_delta = 0.91, max_treedepth = 9, seed = 20261118)
            @test sf_alias.record.run.draws == sf_canon.record.run.draws
            @test sampler_controls(sf_alias).target_accept == 0.91
            @test sampler_controls(sf_alias).max_depth == 9
            @test_throws ArgumentError BayesianMGMFRM.StanAdapter.fit_stan(stan_code, sdata;
                roles = sroles, chains = 2, warmup = 20, ndraws = 20,
                target_accept = 0.9, adapt_delta = 0.9, seed = 1)
        end
    end

    # 7. Specialist documentation & mutual cross-links check
    docs_src = normpath(joinpath(@__DIR__, "..", "docs", "src"))
    guide_path = joinpath(docs_src, "migration-stan-brms.md")
    @test isfile(guide_path)
    guide_txt = read(guide_path, String)
    for kw in ("adapt_delta", "max_treedepth", "target_accept", "max_depth", "E-BFMI", "min_bfmi", "brms", "cmdstanr", "migration-facets-conquest.md", "stan-adapter.md")
        @test occursin(kw, guide_txt)
    end
    for referring_doc in ("index.md", "fitting.md", "stan-adapter.md", "migration-facets-conquest.md")
        @test occursin("migration-stan-brms.md", read(joinpath(docs_src, referring_doc), String))
    end
end
