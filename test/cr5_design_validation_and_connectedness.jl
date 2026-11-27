using Test
using BayesianMGMFRM

@testset "Generalized panel rejection identifies original IDs and feasible remedies" begin
    rows = [(; person = "Candidate_$p", item = "Criterion_$i", rater = "Judge_$r",
        score = mod(p + i + r, 5)) for p in 1:18 for r in (p <= 9 ? (1, 2) : (3, 4)) for i in 1:4]
    tbl = (; (k => [getproperty(row, k) for row in rows] for k in keys(first(rows)))...)
    Q = Bool[1 0; 1 0; 0 1; 0 1]
    err = try
        mfrm_spec(tbl; prior = :default, q_matrix = Q, correlation = :lkj, category_levels = 0:4)
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    msg = sprint(showerror, err)
    @test occursin("rank_deficient_design", msg)
    @test all(s -> occursin("Judge_$s", msg), 1:4)
    @test occursin("common examinees", msg)
    @test occursin("within-subset contrasts", msg)
    @test !occursin("fixed_calibration", msg)
    # The R transport uses integer codes until successful payload construction.
    levels = (; (k => sort(unique(getproperty(tbl, k))) for k in (:person, :item, :rater))...)
    encoded = (; (k => [findfirst(==(x), getproperty(levels, k)) for x in getproperty(tbl, k)]
        for k in keys(levels))..., score = tbl.score)
    fd = BayesianMGMFRM.FacetData(encoded; person = :person, item = :item,
        rater = :rater, score = :score, category_levels = 0:4)
    report = validate_design(fd)
    r_msg = sprint(showerror, BayesianMGMFRM._facet_spec_validation_error(fd, report; ids = levels))
    @test all(s -> occursin("Judge_$s", r_msg), 1:4)
    @test occursin("within-subset contrasts", r_msg)
end

@testset "CR5 Unified Pre-Fit Validation, 3-Layer Connectedness & Disjoint Subsets" begin
    # 1. Completely disconnected 2-panel rating table on MRCML (Bayesian + Frequentist)
    disj_tbl = (
        person = ["P1", "P1", "P2", "P2", "P3", "P3", "P4", "P4"],
        item   = ["I1", "I2", "I1", "I2", "I3", "I4", "I3", "I4"],
        rater  = ["R1", "R1", "R1", "R1", "R2", "R2", "R2", "R2"],
        score  = [0, 1, 2, 1, 0, 2, 1, 2],
    )
    spec_disj_b = mfrm_spec(disj_tbl; person = :person, score = :score,
        facets = (item = :item, rater = :rater), steps = :global,
        category_levels = 0:2, prior = :default)
    val_disj_b = validate_design(spec_disj_b)
    @test val_disj_b.schema == "bayesianmgmfrm.design_validation.v2"
    @test !val_disj_b.passed
    @test !val_disj_b.identified
    @test !val_disj_b.connectedness.overall_connected
    @test val_disj_b.disjoint_subsets.n_overall_subsets == 2
    @test any(i -> i isa ValidationIssue && i.code === :disconnected_design && i.severity === :error, val_disj_b.issues)
    @test val_disj_b.effective_model.family === :mfrm_mrcml
    @test val_disj_b.effective_model.paradigm === :bayesian
    @test val_disj_b.effective_model.threshold_owner === :global
    @test val_disj_b.effective_model.identification === :isometric_helmert_zero_sum_with_population

    spec_disj_f = mfrm_spec(disj_tbl; person = :person, score = :score,
        facets = (item = :item, rater = :rater), steps = :global,
        category_levels = 0:2, prior = :none)
    val_disj_f = validate_design(spec_disj_f)
    @test val_disj_f.schema == "bayesianmgmfrm.design_validation.v2"
    @test !val_disj_f.passed
    @test val_disj_f.disjoint_subsets.n_overall_subsets == 2
    @test val_disj_f.effective_model.paradigm === :frequentist

    # 2. Item-only-shared, rater-disconnected 2-panel design (overall graph connected via items,
    #    but person <-> rater bipartite graph splits into 2 disjoint subsets)
    item_only_tbl = (
        person = ["P1", "P1", "P2", "P2", "P3", "P3", "P4", "P4"],
        item   = ["I1", "I2", "I1", "I2", "I1", "I2", "I1", "I2"],
        rater  = ["R1", "R1", "R1", "R1", "R2", "R2", "R2", "R2"],
        score  = [0, 1, 2, 1, 0, 2, 1, 2],
    )
    spec_item_only = mfrm_spec(item_only_tbl; person = :person, score = :score,
        facets = (item = :item, rater = :rater), steps = :global,
        category_levels = 0:2, prior = :default)
    val_io = validate_design(spec_item_only)
    @test !val_io.identified
    @test val_io.disjoint_subsets.overall_connected
    rater_sub = only(filter(r -> r.facet === :rater, val_io.disjoint_subsets.by_facet))
    @test !rater_sub.connected
    @test rater_sub.n_subsets == 2
    @test rater_sub.bridge_suggestion !== nothing
    @test any(i -> i.code === :facet_person_disconnected_subsets, val_io.issues)

    # 3. Extreme-score-only bridge:
    #    Panel A: P1, P2 rated by R1 on I1, I2 (interior scores)
    #    Panel B: P4, P5 rated by R2 on I1, I2 (interior scores)
    #    Bridge:  P3 rated by BOTH R1 and R2 on I1, I2, but P3 gets ALL MAXIMUM scores (2,2,2,2)!
    ext_bridge_tbl = (
        person = [
            "P1", "P1", "P2", "P2",
            "P3", "P3", "P3", "P3",
            "P4", "P4", "P5", "P5",
        ],
        item = [
            "I1", "I2", "I1", "I2",
            "I1", "I2", "I1", "I2",
            "I1", "I2", "I1", "I2",
        ],
        rater = [
            "R1", "R1", "R1", "R1",
            "R1", "R1", "R2", "R2",
            "R2", "R2", "R2", "R2",
        ],
        score = [
            0, 1, 1, 2,
            2, 2, 2, 2,
            0, 1, 1, 2,
        ],
    )
    spec_eb_b = mfrm_spec(ext_bridge_tbl; person = :person, score = :score,
        facets = (item = :item, rater = :rater), steps = :global,
        category_levels = 0:2, prior = :default)
    val_eb = validate_design(spec_eb_b)
    @test val_eb.identified
    @test val_eb.connectedness.overall_connected
    @test val_eb.connectedness.all_facets_person_connected
    @test !val_eb.connectedness.score_conditioned_connected
    @test any(b -> b.scope === :rater, val_eb.connectedness.extreme_only_bridges)
    @test any(i -> i.code === :score_conditioned_disconnected_design, val_eb.issues)
    @test "P3" in val_eb.extreme_elements.person.all_maximum

    # Unadjusted MRCML JMLE must refuse fitting when removing extreme persons disconnects the design!
    spec_eb_f = mfrm_spec(ext_bridge_tbl; person = :person, score = :score,
        facets = (item = :item, rater = :rater), steps = :global,
        category_levels = 0:2, prior = :none)
    @test_throws ArgumentError fit(spec_eb_f; method = :jmle, extreme_adjustment = 0.0)

    # 4. Thin interior bridge (1 shared interior person, non-separated on items & raters) + sparse category (< 10)
    thin_tbl = (
        person = [
            "P1", "P1", "P2", "P2", "P3", "P3", "P3", "P3", "P4", "P4", "P5", "P5",
        ],
        item = [
            "I1", "I2", "I1", "I2", "I1", "I2", "I1", "I2", "I1", "I2", "I1", "I2",
        ],
        rater = [
            "R1", "R1", "R1", "R1", "R1", "R1", "R2", "R2", "R2", "R2", "R2", "R2",
        ],
        score = [
            1, 0, 1, 2, 0, 2, 2, 1, 0, 1, 2, 1,
        ],
    )
    spec_thin = mfrm_spec(thin_tbl; person = :person, score = :score,
        facets = (item = :item, rater = :rater), steps = :global,
        category_levels = 0:2, prior = :default)
    val_thin = validate_design(spec_thin; min_category_count = 10, min_bridge_overlap = 2)
    @test val_thin.identified
    @test val_thin.connectedness.score_conditioned_connected
    @test !val_thin.connectedness.one_sided_separated
    @test any(tb -> tb.facet === :rater && tb.bottleneck_shared_interior_persons == 1, val_thin.connectedness.thin_bridges)
    @test any(i -> i.code === :thin_facet_bridge && occursin("alpha_r^2", i.message), val_thin.issues)
    @test any(i -> i.code === :sparse_category_cell, val_thin.issues)

    # Empirical category-order inversion: low-scoring persons get category 2 while high-scoring get category 1
    inv_tbl = (
        person = repeat(["P1", "P2", "P3", "P4"], inner = 4),
        item   = repeat(["I1", "I2", "I1", "I2"], outer = 4),
        rater  = repeat(["R1", "R1", "R2", "R2"], outer = 4),
        score  = [
            # P1 & P2: mostly 0 with one 2 on I1 (low total score)
            2, 0, 0, 0,
            2, 0, 0, 0,
            # P3 & P4: high total score with 1 on I1 and 2 on others
            1, 2, 2, 2,
            1, 2, 2, 2,
        ],
    )
    spec_inv = mfrm_spec(inv_tbl; person = :person, score = :score,
        facets = (item = :item, rater = :rater), steps = :item,
        category_levels = 0:2, prior = :default)
    val_inv = validate_design(spec_inv)
    @test any(i -> i.code === :empirical_category_order_inversion, val_inv.issues)

    # 5. Extreme facet level (all-maximum rater) detected symmetrically in validate_design and frequentist fit
    ext_rater_tbl = (
        person = ["P1", "P1", "P1", "P2", "P2", "P2", "P3", "P3", "P3"],
        item   = ["I1", "I2", "I1", "I1", "I2", "I2", "I1", "I2", "I1"],
        rater  = ["R1", "R1", "R2", "R1", "R1", "R2", "R1", "R1", "R2"],
        score  = [0, 1, 2, 1, 2, 2, 0, 1, 2],
    )
    spec_er = mfrm_spec(ext_rater_tbl; person = :person, score = :score,
        facets = (item = :item, rater = :rater), steps = :global,
        category_levels = 0:2, prior = :none)
    val_er = validate_design(spec_er)
    rater_ext = only(filter(r -> r.facet === :rater, val_er.extreme_elements.facets))
    @test "R2" in rater_ext.all_maximum
    @test any(i -> i.code === :extreme_facet_level, val_er.issues)
    fit_er = fit(spec_er; method = :mmle)
    @test any(r -> r.facet === :rater && r.level == "R2" && r.direction === :all_maximum, fit_er.record.extreme_facet_levels)

    # 6. Auditable missing_policy = :drop_with_audit vs default :error in FacetData
    miss_tbl = (
        person = ["P1", "P1", missing, "P2", "P2"],
        item   = ["I1", "I2", "I1", "I1", "I2"],
        rater  = ["R1", "R2", "R1", "R1", "R2"],
        score  = [0, 1, 2, missing, 2],
    )
    @test_throws ArgumentError FacetData(miss_tbl; person = :person, item = :item, rater = :rater, score = :score, category_levels = 0:2)
    d_drop = @test_logs (:warn, r"dropped 2 of 5") FacetData(
        miss_tbl; person = :person, item = :item, rater = :rater, score = :score,
        category_levels = 0:2, missing_policy = :drop_with_audit,
    )
    @test d_drop.n == 3
    @test d_drop.columns.missing_policy === :drop_with_audit
    @test d_drop.columns.missing_audit.n_input_rows == 5
    @test d_drop.columns.missing_audit.n_dropped_rows == 2
    @test d_drop.columns.missing_audit.dropped_rows == [3, 4]
    @test d_drop.columns.missing_audit.dropped_by_column == Dict(:person => 1, :score => 1)

    # 7. Public validate_design on FacetSpec GMFRM exposes connectedness, thin_bridges (original IDs), and effective_model
    d_gm = FacetData(thin_tbl; person = :person, item = :item, rater = :rater, score = :score, category_levels = 0:2)
    spec_gm = mfrm_spec(d_gm; family = :gmfrm, discrimination = :rater, thresholds = :partial_credit)
    val_gm = validate_design(spec_gm; min_category_count = 10, min_bridge_overlap = 2)
    @test val_gm.passed && val_gm.identified
    @test val_gm.effective_model.family === :gmfrm
    @test val_gm.effective_model.threshold_owner === :rater
    @test val_gm.effective_model.identification === :gmfrm_item_sum_to_zero
    @test val_gm.connectedness.score_conditioned_connected
    @test any(tb -> tb.facet === :rater && tb.bottleneck_shared_interior_persons == 1 &&
        Set(tb.weakest_bridge_pair) == Set(["R1", "R2"]), val_gm.connectedness.thin_bridges)
    @test any(i -> i.code === :thin_facet_bridge, val_gm.issues)

    # 8. Reopened CR5 Counterexample 1a: 5-person x 2-rater binary panel with 1 all-maximum person removed
    #    Residual graph must NOT count the excluded extreme person as an isolated component;
    #    both FrequentistMFRM.Spec and MRCMLSpec unadjusted JMLE must pass and qualify!
    bin_5p_tbl = (
        person = ["P1", "P1", "P2", "P2", "P3", "P3", "P4", "P4", "P5", "P5"],
        rater  = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
        score  = [1, 1, 1, 0, 1, 0, 0, 1, 0, 1],
    )
    spec_5p_freq = mfrm_spec(bin_5p_tbl; person = :person, score = :score,
        facets = (rater = :rater,), steps = :global, category_levels = 0:1, prior = :none)
    spec_5p_mrcml = BayesianMGMFRM.AdditiveFacets.compile_structured_mrcml(
        bin_5p_tbl; person = :person, score = :score,
        facets = (rater = :rater,), steps = :global, category_levels = 0:1)
    @test spec_5p_freq isa BayesianMGMFRM.FrequentistMFRM.Spec
    @test spec_5p_mrcml isa BayesianMGMFRM.AdditiveFacets.MRCMLSpec
    for sp in (spec_5p_freq, spec_5p_mrcml)
        v5 = validate_design(sp)
        @test v5.identified
        @test v5.connectedness.n_score_conditioned_subsets == 1
        @test isempty(v5.connectedness.isolated_facet_levels)
        @test !v5.connectedness.one_sided_separated
        @test v5.connectedness.score_conditioned_connected
        @test !any(i -> i.code === :score_conditioned_disconnected_design, v5.issues)
        f5 = fit(sp; method = :jmle, extreme_adjustment = 0.0)
        q5 = qualify(f5)
        @test q5.qualified
    end

    # 9. Reopened CR5 Counterexample 1b: Fischer (1981) one-sided separation
    #    R1/R2 and R3/R4 each have 1/0 & 0/1; linked ONLY by P5 receiving 1 from R2 and 0 from R3.
    #    All persons and all raters have interior scores (0 and 1), yet NO finite unadjusted JMLE exists!
    sep_tbl = (
        person = [
            "P1", "P1", "P2", "P2",
            "P3", "P3", "P4", "P4",
            "P5", "P5",
        ],
        rater = [
            "R1", "R2", "R1", "R2",
            "R3", "R4", "R3", "R4",
            "R2", "R3",
        ],
        score = [
            1, 0, 0, 1,
            1, 0, 0, 1,
            1, 0,
        ],
    )
    spec_sep_freq = mfrm_spec(sep_tbl; person = :person, score = :score,
        facets = (rater = :rater,), steps = :global, category_levels = 0:1, prior = :none)
    spec_sep_mrcml = BayesianMGMFRM.AdditiveFacets.compile_structured_mrcml(
        sep_tbl; person = :person, score = :score,
        facets = (rater = :rater,), steps = :global, category_levels = 0:1)
    @test spec_sep_freq isa BayesianMGMFRM.FrequentistMFRM.Spec
    @test spec_sep_mrcml isa BayesianMGMFRM.AdditiveFacets.MRCMLSpec
    for sp in (spec_sep_freq, spec_sep_mrcml)
        vs = validate_design(sp)
        @test vs.identified
        @test vs.connectedness.overall_connected
        @test vs.connectedness.n_score_conditioned_subsets == 1
        @test vs.connectedness.one_sided_separated
        @test !vs.connectedness.score_conditioned_connected
        @test vs.connectedness.existence_check_scope === :fischer_1981_exact_dichotomous_rasch
        @test vs.connectedness.existence_check_exhaustive
        @test any(i -> i.code === :one_sided_score_separation, vs.issues)
        @test_throws ArgumentError fit(sp; method = :jmle, extreme_adjustment = 0.0)
    end

    # 10. Reopened CR5 Counterexample 2a: Reverse-scored TAM/MRCML B_pat must match estimator person extremes
    # I1 forward-scored [0, 1]; I2 reverse-scored [1, 0]:
    #   P1: (0->0) + (1->0) = 0 (ALL MINIMUM!)
    #   P2: (0->0) + (0->1) = 1 (interior)
    #   P3: (1->1) + (0->1) = 2 (ALL MAXIMUM!)
    #   P4: (1->1) + (1->0) = 1 (interior)
    resp_rev = [0 1; 0 0; 1 0; 1 1]
    A_rev = zeros(Float64, 2, 2, 1)
    A_rev[1, 2, 1] = 1.0
    A_rev[2, 2, 1] = -1.0
    B_rev = [0.0 1.0; 1.0 0.0]
    rev_spec = BayesianMGMFRM.MRCML.from_tam(
        A_rev, resp_rev;
        B = B_rev,
        pid = ["P1", "P2", "P3", "P4"],
        item_names = ["I1", "I2"],
        parameter_names = ["item_diff"],
    )
    val_rev = validate_design(rev_spec)
    @test val_rev.extreme_elements.scoring_basis === :mrcml_scoring_operator_B
    @test Set(val_rev.extreme_elements.person.all_minimum) == Set(["P1"])
    @test Set(val_rev.extreme_elements.person.all_maximum) == Set(["P3"])
    @test !(("P2" in val_rev.extreme_elements.person.all_minimum) || ("P4" in val_rev.extreme_elements.person.all_maximum))

    # 11. Reopened CR5 Counterexample 2b: Fixed/anchored all-maximum item must NOT fail qualify boundary gate
    anc_ext_tbl = (
        person = repeat(["P1", "P2", "P3", "P4", "P5", "P6"], inner = 3),
        item   = repeat(["I_fix", "I_free1", "I_free2"], outer = 6),
        score  = [
            1, 0, 1,
            1, 1, 0,
            1, 0, 0,
            1, 1, 1,
            1, 0, 1,
            1, 1, 0,
        ],
    )
    spec_anc_ext = mfrm_spec(anc_ext_tbl; person = :person, score = :score,
        facets = (item = :item,), steps = :global, category_levels = 0:1,
        fixed_calibration = (facets = (item = Dict("I_fix" => 0.0),),),
        prior = :none)
    val_anc = validate_design(spec_anc_ext)
    item_ext = only(filter(r -> r.facet === :item, val_anc.extreme_elements.facets))
    @test "I_fix" in item_ext.all_maximum
    @test "I_fix" in item_ext.fixed_extreme_levels
    @test item_ext.n_free_extreme == 0
    fit_anc = fit(spec_anc_ext; method = :mmle)
    @test any(r -> r.facet === :item && r.level == "I_fix" && r.fixed === true, fit_anc.record.extreme_facet_levels)
    q_anc = qualify(fit_anc)
    @test q_anc.boundary_gate_passed
    @test q_anc.qualified

    # 12. Reopened CR5 Counterexample 2c: missing_audit propagates from FacetData -> mfrm_spec -> validate_design -> PortableHandoff
    miss_conn_tbl = (
        person = ["P1", "P1", "P2", "P2", missing],
        item   = ["I1", "I2", "I1", "I2", "I1"],
        rater  = ["R1", "R2", "R2", "R1", "R1"],
        score  = [0, 1, 1, 0, 1],
    )
    fd_ma = @test_logs (:warn, r"dropped 1 of 5") FacetData(
        miss_conn_tbl; person = :person, item = :item, rater = :rater, score = :score,
        category_levels = 0:1, missing_policy = :drop_with_audit,
    )
    sp_ma_b = mfrm_spec(fd_ma; prior = :default)
    sp_ma_f = mfrm_spec(fd_ma; prior = :none)
    for sp_m in (sp_ma_b, sp_ma_f)
        vm = validate_design(sp_m)
        dsm = design_summary(sp_m)
        @test vm.missing_audit !== nothing && vm.missing_audit.n_input_rows == 5 && vm.missing_audit.n_dropped_rows == 1
        @test dsm.missing_audit.n_input_rows == 5 && dsm.missing_audit.n_dropped_rows == 1
    end
    fit_ma = fit(sp_ma_b; chains = 2, warmup = 15, ndraws = 15, seed = 41, progress = false)
    ho_ma = BayesianMGMFRM.PortableHandoff.export_handoff(fit_ma; scale = :model)
    @test hasproperty(ho_ma.record, :missing_audit) && ho_ma.record.missing_audit.n_dropped_rows == 1
    @test hasproperty(ho_ma.record, :draws_ieee754_sha256) && occursin(r"^[0-9a-f]{64}$", String(ho_ma.record.draws_ieee754_sha256))
    @test hasproperty(ho_ma.record, :ids) && Set(String.(ho_ma.record.ids.rater)) == Set(["R1", "R2"])
    # Verify PortableHandoff reload passes and detects tampered draws_ieee754_sha256
    mktempdir() do tmpd
        hp = joinpath(tmpd, "ma_handoff.json")
        BayesianMGMFRM.PortableHandoff.save_handoff(hp, ho_ma)
        parsed_ok = BayesianMGMFRM.JSON3.read(read(hp, String))
        reloaded_ok = BayesianMGMFRM.PortableHandoff.load_handoff(parsed_ok)
        @test reloaded_ok.record.draws_ieee754_sha256 == ho_ma.record.draws_ieee754_sha256
        # Tamper draws_ieee754_sha256 directly -> must throw
        bad_dict = Dict{Symbol,Any}(k => parsed_ok[k] for k in keys(parsed_ok))
        bad_dict[:draws_ieee754_sha256] = repeat("0", 64)
        @test_throws ArgumentError BayesianMGMFRM.PortableHandoff.load_handoff((; bad_dict...))
    end

    # 13. Reopened CR5 Counterexample 2d: Sparse thin-bridge check handles 500 levels without dense O(L^2) blowup
    big_L = 500
    big_p = vcat(collect(1:big_L), collect(1:(big_L - 1)))
    big_f = vcat(collect(1:big_L), collect(2:big_L))
    big_meta = NamedTuple[(; name = :item, levels = ["I$i" for i in 1:big_L], index = big_f, sign = -1)]
    t_tb = @elapsed tb_big = BayesianMGMFRM._cr5_thin_bridges(big_p, big_meta, collect(eachindex(big_p)); min_bridge_overlap = 2)
    @test length(tb_big) == 1 && tb_big[1].bottleneck_shared_interior_persons == 1
    @test tb_big[1].exact && tb_big[1].status === :thin_bridge_confirmed
    @test t_tb < 2.0

    # 14. CR5 350-level exact thin-bridge test: 3 shared interior persons across 350 levels must NOT falsely warn at min_bridge_overlap = 2
    w_L = 350
    w_p = repeat(1:3, inner = w_L)
    w_f = repeat(1:w_L, outer = 3)
    w_meta = NamedTuple[(; name = :item, levels = ["I$i" for i in 1:w_L], index = w_f, sign = -1)]
    tb_350 = BayesianMGMFRM._cr5_thin_bridges(w_p, w_meta, collect(eachindex(w_p)); min_bridge_overlap = 2)
    @test isempty(tb_350)

    # 15. CR5 validation_suggestions works on extended FacetSpec validate_design report
    sugg_gm = BayesianMGMFRM.validation_suggestions(val_gm)
    @test sugg_gm isa Vector
    @test any(s -> s.code === :thin_facet_bridge, sugg_gm)

    # 16. CR5 Residual components exclude levels with 0 active rows and report them separately in isolated_facet_levels
    iso2_tbl = (
        person = ["P1", "P1", "P2", "P2", "P3", "P3", "P4", "P4", "P5", "P5"],
        rater  = ["R1", "R2", "R1", "R2", "R1", "R2", "R3", "R4", "R3", "R4"],
        score  = [1, 0, 0, 1, 1, 0, 1, 1, 1, 1],
    )
    sp_iso2 = mfrm_spec(iso2_tbl; person = :person, score = :score,
        facets = (rater = :rater,), steps = :global, category_levels = 0:1, prior = :none)
    v_iso2 = validate_design(sp_iso2)
    @test v_iso2.connectedness.n_score_conditioned_subsets == 1
    @test v_iso2.connectedness.n_isolated_facet_levels == 2
    iso_r = only(filter(x -> x.facet === :rater, v_iso2.connectedness.isolated_facet_levels))
    @test Set(iso_r.levels) == Set(["R3", "R4"])

    # 17. CR5 Compiled-model finite-JMLE separation:
    # 17a. Constrained binary TAM (4 items sharing 1 coefficient with loadings (+1, -1, +1, -1)) HAS a finite optimum -> must FIT and QUALIFY!
    resp_tied = [
        1 0 1 0;
        0 1 0 1;
        1 0 0 1;
        1 1 0 0;
        0 0 1 1;
    ]
    A_tied = zeros(Float64, 4, 2, 1)
    A_tied[1, 2, 1] =  1.0
    A_tied[2, 2, 1] = -1.0
    A_tied[3, 2, 1] =  1.0
    A_tied[4, 2, 1] = -1.0
    sp_tied = BayesianMGMFRM.MRCML.from_tam(
        A_tied, resp_tied;
        pid = ["P1", "P2", "P3", "P4", "P5"],
        item_names = ["I1", "I2", "I3", "I4"],
        parameter_names = ["shared_beta"],
    )
    v_tied = validate_design(sp_tied)
    @test !v_tied.one_sided_separation.separated
    @test !v_tied.one_sided_separation.existence_check_exhaustive
    @test v_tied.one_sided_separation.existence_check_scope === :compiled_free_parameter_recession_screen
    fit_tied = fit(sp_tied; method = :jmle, extreme_adjustment = 0.0)
    q_tied = qualify(fit_tied)
    @test q_tied.qualified
    @test q_tied.max_abs_gradient < 1e-8

    # 17b. 3-category RSM with pairs (0,1), (1,0), (1,2), (2,1): threshold divergence demonstrated in compiled coordinates
    rsm3_tbl = (
        person = ["P1", "P1", "P2", "P2", "P3", "P3", "P4", "P4"],
        rater  = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
        score  = [0, 1, 1, 0, 1, 2, 2, 1],
    )
    sp_rsm3_f = mfrm_spec(rsm3_tbl; person = :person, score = :score,
        facets = (rater = :rater,), steps = :global, category_levels = 0:2, prior = :none)
    sp_rsm3_m = BayesianMGMFRM.AdditiveFacets.compile_structured_mrcml(
        rsm3_tbl; person = :person, score = :score,
        facets = (rater = :rater,), steps = :global, category_levels = 0:2)
    for sp3 in (sp_rsm3_f, sp_rsm3_m)
        v3 = validate_design(sp3)
        @test !v3.one_sided_separation.existence_check_exhaustive
        @test v3.one_sided_separation.existence_check_scope === :compiled_free_parameter_recession_screen
        @test v3.one_sided_separation.separated
        @test !isempty(v3.one_sided_separation.threshold_separations)
        @test_throws ArgumentError fit(sp3; method = :jmle, extreme_adjustment = 0.0)
    end

    # 18. CR5 PortableHandoff full-decision bundle hash binds ids & missing_audit (swapped IDs or changed dropped_rows MUST change both handoff_hash and handoff_bundle_sha256!)
    ho_a = BayesianMGMFRM.PortableHandoff.export_handoff(
        fit_ma; scale = :model,
        ids = (; person = ["P1", "P2"], item = ["I1", "I2"], rater = ["Alice", "Bea"]))
    ho_b = BayesianMGMFRM.PortableHandoff.export_handoff(
        fit_ma; scale = :model,
        ids = (; person = ["P1", "P2"], item = ["I1", "I2"], rater = ["Bea", "Alice"]))
    @test ho_a.record.draws_ieee754_sha256 == ho_b.record.draws_ieee754_sha256
    @test ho_a.record.handoff_hash != ho_b.record.handoff_hash
    @test ho_a.record.handoff_bundle_sha256 != ho_b.record.handoff_bundle_sha256
    mktempdir() do tmpd
        hp = joinpath(tmpd, "bundle_ok.json")
        BayesianMGMFRM.PortableHandoff.save_handoff(hp, ho_a)
        parsed = BayesianMGMFRM.JSON3.read(read(hp, String))
        @test BayesianMGMFRM.PortableHandoff.load_handoff(parsed).record.handoff_bundle_sha256 == ho_a.record.handoff_bundle_sha256
        # Swap rater IDs while keeping draws & hashes from ho_a -> load_handoff MUST throw!
        tampered_ids = merge(
            (; (Symbol(k) => parsed[k] for k in keys(parsed))...),
            (; ids = (; person = ["P1", "P2"], item = ["I1", "I2"], rater = ["Bea", "Alice"])),
        )
        @test_throws ArgumentError BayesianMGMFRM.PortableHandoff.load_handoff(tampered_ids)
    end

    # 19. CR5 Common-rubric 4-facet nesting, null-space estimable vs. aliased contrasts, explicit population_link MMLE, and dependence-unit audit
    # 19a. Raters nested in tasks (8 persons x 2 tasks x 4 raters x 3 common criteria, 0:2)
    rows_rn = NamedTuple[]
    for p in ["P$i" for i in 1:8]
        for (t, rs) in [("T1", ["R1", "R2"]), ("T2", ["R3", "R4"])]
            for r in rs, c in ["C1", "C2", "C3"]
                push!(rows_rn, (person = p, task = t, rater = r, criterion = c,
                    response_id = "$(p)_$(t)", score = mod(Int(hash((p, t, r, c)) % 3), 3)))
            end
        end
    end
    tbl_rn = (
        person = [x.person for x in rows_rn], task = [x.task for x in rows_rn],
        rater = [x.rater for x in rows_rn], criterion = [x.criterion for x in rows_rn],
        response_id = [x.response_id for x in rows_rn], score = [x.score for x in rows_rn],
    )
    sp_rn = BayesianMGMFRM.AdditiveFacets.compile_structured_mrcml(
        tbl_rn; person = :person, score = :score,
        facets = (task = :task, rater = :rater, criterion = :criterion),
        steps = :global, category_levels = 0:2, performance = :response_id)
    v_rn = validate_design(sp_rn)
    @test v_rn.connectedness.overall_connected
    @test !v_rn.structural_identified
    @test v_rn.nesting_and_aliasing.has_nesting
    @test any(r -> r.kind === :directional_nesting && r.nested_role === :rater && r.containing_role === :task,
        v_rn.nesting_and_aliasing.relations)
    @test any(c -> c.kind === :within_panel_nested_contrast && c.conditional_joint_estimable === true,
        v_rn.nesting_and_aliasing.estimable_contrasts)
    @test any(c -> c.kind === :common_facet_contrast && c.conditional_joint_estimable === true,
        v_rn.nesting_and_aliasing.estimable_contrasts)
    @test any(c -> c.kind === :combined_parent_plus_panel_contrast && c.conditional_joint_estimable === true,
        v_rn.nesting_and_aliasing.estimable_contrasts)
    @test any(c -> c.kind === :cross_panel_parent_contrast && c.conditional_joint_estimable === false,
        v_rn.nesting_and_aliasing.aliased_contrasts)
    # Dependence-unit audit detects multi-criterion events and independent re-rating
    @test v_rn.dependence_units.event_membership_known
    @test v_rn.dependence_units.max_criteria_per_event == 3
    @test v_rn.dependence_units.n_independently_rerated_responses == 16
    @test v_rn.dependence_units.person_response_variance_separable
    @test any(i -> i.code === :within_event_local_dependence_unmodeled, v_rn.issues)

    # 19b. Persons nested in tasks (8 persons: P1..P4 -> T1, P5..P8 -> T2; raters & criteria shared)
    rows_pn = NamedTuple[]
    for (ps, t) in [(["P1", "P2", "P3", "P4"], "T1"), (["P5", "P6", "P7", "P8"], "T2")]
        for p in ps, r in ["R1", "R2"], c in ["C1", "C2", "C3"]
            push!(rows_pn, (person = p, task = t, rater = r, criterion = c,
                response_id = "$(p)_$(t)", score = mod(Int(hash((p, t, r, c)) % 3), 3)))
        end
    end
    tbl_pn = (
        person = [x.person for x in rows_pn], task = [x.task for x in rows_pn],
        rater = [x.rater for x in rows_pn], criterion = [x.criterion for x in rows_pn],
        response_id = [x.response_id for x in rows_pn], score = [x.score for x in rows_pn],
    )
    sp_pn = BayesianMGMFRM.AdditiveFacets.compile_structured_mrcml(
        tbl_pn; person = :person, score = :score,
        facets = (task = :task, rater = :rater, criterion = :criterion),
        steps = :global, category_levels = 0:2, performance = :response_id)
    v_pn = validate_design(sp_pn)
    @test v_pn.structural_identified
    @test !v_pn.conditional_joint_identified
    @test any(r -> r.kind === :directional_nesting && r.nested_role === :person && r.containing_role === :task,
        v_pn.nesting_and_aliasing.relations)
    @test !v_pn.dependence_units.person_response_variance_separable
    # Implicit MMLE MUST refuse person-within-task linking without explicit population_link opt-in + nonblank rationale!
    @test_throws ArgumentError fit(sp_pn; method = :mmle, estimate_mean = false)
    @test_throws ArgumentError fit(sp_pn; method = :mmle, estimate_mean = false,
        population_link = :common_population)
    @test_throws ArgumentError fit(sp_pn; method = :mmle, estimate_mean = false,
        population_link = (mode = :common_population,))
    @test_throws ArgumentError fit(sp_pn; method = :mmle, estimate_mean = false,
        population_link = (mode = :common_population, rationale = ""))
    @test_throws ArgumentError fit(sp_pn; method = :mmle, estimate_mean = false,
        population_link = (mode = :common_population, rationale = "   \t\n "))
    @test_throws ArgumentError fit(sp_pn; method = :mmle, estimate_mean = false,
        population_link = (mode = :common_population, rationale = nothing))
    # Explicit opt-in population_link with nonblank rationale succeeds, qualifies, and records allocation rationale!
    fit_pn_pl = fit(sp_pn; method = :mmle, estimate_mean = false,
        population_link = (mode = :common_population, rationale = "  random assignment to tasks  "))
    @test qualify(fit_pn_pl).qualified
    @test fit_pn_pl.record.summary.population_link.mode === :common_population
    @test fit_pn_pl.record.summary.population_link.allocation_rationale == "random assignment to tasks"
    @test :task in fit_pn_pl.record.summary.population_link.bridged_facets
    @test any(w -> occursin(":common_population", w), fit_pn_pl.record.warnings)
    # Ordinary directly linked design (bridging examinee crosses T1 & T2) still fits MMLE without population_link
    rows_linked = copy(rows_pn)
    for r in ["R1", "R2"], c in ["C1", "C2", "C3"]
        push!(rows_linked, (person = "P1", task = "T2", rater = r, criterion = c,
            response_id = "P1_T2", score = mod(Int(hash(("P1", "T2", r, c)) % 3), 3)))
    end
    tbl_linked = (
        person = [x.person for x in rows_linked], task = [x.task for x in rows_linked],
        rater = [x.rater for x in rows_linked], criterion = [x.criterion for x in rows_linked],
        response_id = [x.response_id for x in rows_linked], score = [x.score for x in rows_linked],
    )
    sp_linked = BayesianMGMFRM.AdditiveFacets.compile_structured_mrcml(
        tbl_linked; person = :person, score = :score,
        facets = (task = :task, rater = :rater, criterion = :criterion),
        steps = :global, category_levels = 0:2, performance = :response_id)
    fit_linked = fit(sp_linked; method = :mmle, estimate_mean = false)
    @test qualify(fit_linked).qualified
    @test !hasproperty(fit_linked.record.summary, :population_link) || fit_linked.record.summary.population_link === nothing
    # Without performance/assessment IDs, dependence_units marks event_membership_known == false
    sp_no_ev = mfrm_spec(
        (person = tbl_pn.person, task = tbl_pn.task, rater = tbl_pn.rater, criterion = tbl_pn.criterion, score = tbl_pn.score);
        person = :person, score = :score, facets = (task = :task, rater = :rater, criterion = :criterion),
        steps = :global, category_levels = 0:2, prior = :none)
    @test !validate_design(sp_no_ev).dependence_units.event_membership_known

    # 19c. Assessment-ID-only vs. response+assessment dependence-unit audit on identical ratings:
    # 8 persons x 1 response each (8 responses), 2 raters x 3 criteria -> 16 rating events of 3 criteria each.
    tbl_ev = (
        person = tbl_pn.person,
        task = tbl_pn.task,
        rater = tbl_pn.rater,
        criterion = tbl_pn.criterion,
        response_id = tbl_pn.response_id,
        assessment_id = ["$(tbl_pn.response_id[i])_$(tbl_pn.rater[i])" for i in eachindex(tbl_pn.score)],
        score = tbl_pn.score,
    )
    for prior_mode in (:none, :default)
        sp_both = mfrm_spec(tbl_ev;
            person = :person, score = :score,
            facets = (task = :task, rater = :rater, criterion = :criterion),
            steps = :global, category_levels = 0:2,
            performance = :response_id, assessment = :assessment_id, prior = prior_mode)
        du_both = validate_design(sp_both).dependence_units
        @test du_both.event_membership_known
        @test du_both.response_id_available
        @test du_both.assessment_id_available
        @test du_both.n_events == 16
        @test du_both.min_criteria_per_event == 3
        @test du_both.max_criteria_per_event == 3
        @test du_both.mean_criteria_per_event == 3.0
        @test du_both.n_responses == 8
        @test du_both.n_independently_rerated_responses == 8
        @test du_both.n_persons_with_multiple_responses == 0
        @test du_both.person_response_variance_separable === false
        @test du_both.within_event_multi_criterion_detected

        sp_assess_only = mfrm_spec(tbl_ev;
            person = :person, score = :score,
            facets = (task = :task, rater = :rater, criterion = :criterion),
            steps = :global, category_levels = 0:2,
            assessment = :assessment_id, prior = prior_mode)
        v_ao = validate_design(sp_assess_only)
        du_ao = v_ao.dependence_units
        @test du_ao.event_membership_known
        @test !du_ao.response_id_available
        @test du_ao.assessment_id_available
        @test du_ao.response_id_column === nothing
        @test du_ao.assessment_id_column === :assessment_id
        @test du_ao.n_events == 16
        @test du_ao.min_criteria_per_event == 3
        @test du_ao.max_criteria_per_event == 3
        @test du_ao.mean_criteria_per_event == 3.0
        @test du_ao.within_event_multi_criterion_detected
        @test ismissing(du_ao.n_responses)
        @test ismissing(du_ao.n_independently_rerated_responses)
        @test ismissing(du_ao.n_persons_with_multiple_responses)
        @test ismissing(du_ao.person_response_variance_separable)
        @test occursin("missing", lowercase(du_ao.note))
        @test any(i -> i.code === :within_event_local_dependence_unmodeled, v_ao.issues)
        # Ensure JSON serialization succeeds with missing response-level fields
        parsed_ao = BayesianMGMFRM.JSON3.read(BayesianMGMFRM.JSON3.write(du_ao))
        @test parsed_ao.n_events == 16
        @test parsed_ao.n_responses === nothing
        @test parsed_ao.person_response_variance_separable === nothing
    end
end
