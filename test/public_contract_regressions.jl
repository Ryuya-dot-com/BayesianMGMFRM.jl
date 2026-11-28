module PublicContractRegressions
using Test, BayesianMGMFRM, Distributions, StatsAPI
import LogDensityProblems as L
import ForwardDiff
const B = BayesianMGMFRM
const A = B.AdditiveFacets

@testset "Shared statistics generics and compatibility types" begin
    @test fit === StatsAPI.fit === Distributions.fit
    @test predict === StatsAPI.predict
    @test fit(Normal, [-1., 0., 1.]) isa Normal
    local_module(m) = m === B || (parentmodule(m) !== m && local_module(parentmodule(m)))
    for f in (fit, predict), method in methods(f)
        local_module(method.module) || continue
        arguments = Base.unwrap_unionall(method.sig).parameters[2:end]
        @test any(T -> all(t -> t isa Type && local_module(parentmodule(t)),
                          Base.uniontypes(T)), arguments)
    end
    for name in (:FacetDesign, :MFRMPrior, :FacetSpec, :MFRMFit)
        @test name ∉ names(B)
        @test name in names(B.Legacy)
        @test getfield(B.Legacy, name) === getfield(B, name)
    end
end

rows = [(p,i,r) for p in 1:4 for i in 1:2 for r in 1:2]
ratings = (; person=[p for (p,i,r) in rows], item=[i for (p,i,r) in rows],
    rater=[r for (p,i,r) in rows], score=[mod(p+i+r,3) for (p,i,r) in rows])
options = (;person=:person,score=:score,facets=(item=:item,rater=:rater),
           steps=:item, category_levels=0:2,prior=:default)

@testset "Validation value semantics" begin
    data = FacetData(ratings;person=:person,item=:item,rater=:rater,score=:score,category_levels=0:2)
    a, b = validate_design(data), validate_design(deepcopy(data))
    @test a == b
    @test isequal(a,b)
    @test hash(a) == hash(b)
    @test length(Set([a,b])) == 1
    push!(b.issues, ValidationIssue(:extra,:warning,"Extra",context=Dict(:rows=>[1,2])))
    @test a != b
    @test !isequal(a,b)
    for context in (Dict(:x=>[1,2]), Dict(:x=>NaN), Dict(:x=>missing))
        i = ValidationIssue(:test,:warning,"Check";context)
        j = deepcopy(i)
        @test (i == j) === true
        @test !(i != j)
        @test isequal(i,j)
        @test hash(i) == hash(j)
        @test length(Set([i,j])) == 1
        ra, rb = deepcopy(a), deepcopy(a)
        push!(ra.issues, i); push!(rb.issues, j)
        @test (ra == rb) === true
        @test !(ra != rb)
    end
    i = ValidationIssue(:test,:warning,"Check"; context=Dict(:x=>0.0))
    j = ValidationIssue(:test,:warning,"Check"; context=Dict(:x=>-0.0))
    @test i == j
    @test !isequal(i,j)
    c1 = ValidationIssue(:test,:warning,"Check"; context=Dict(:x=>complex(1.0, NaN)))
    c2 = ValidationIssue(:test,:warning,"Check"; context=Dict(:x=>complex(2.0, NaN)))
    @test (c1 == deepcopy(c1)) === true
    @test (c1 == c2) === false
    @test !isequal(c1, c2)
    for slope in (:rater,:item)
        a=mfrm_spec(ratings;options...,slope)
        b=mfrm_spec(deepcopy(ratings);options...,slope)
        @test isequal(design_summary(a),design_summary(b))
        @test isequal(validate_design(a),validate_design(b))
    end
end

@testset "Sampling charts are not public specifications" begin
    target = mfrm_spec(ratings;options...)
    chart = A._maybe_mrcml_givens_target(target)
    @test chart !== nothing
    @test !(chart isa AbstractMFRMSpec)
    @test !applicable(fit,chart)
    @test L.dimension(chart) == L.dimension(target)
    @test L.capabilities(typeof(chart)) isa L.LogDensityOrder{1}
    @test B._check_source_fixture_raw_vector(chart, zeros(L.dimension(chart))) === nothing
    @test_throws DimensionMismatch B._check_source_fixture_raw_vector(chart, [0.0])
    q = 0.1sin.(1:L.dimension(chart))
    value,gradient=L.logdensity_and_gradient(chart,q)
    @test value ≈ L.logdensity(target,A._givens_to_raw(chart,q))
    @test gradient ≈ ForwardDiff.gradient(x->L.logdensity(chart,x),q)
end

@testset "Observation models report missing population declarations" begin
    data=merge(ratings,(trials=fill(2,length(rows)),))
    for observation in ((family=:binomial,trials=:trials), (family=:beta,bounds=(0.,2.)))
        opts=(;person=:person,score=:score,facets=(item=:item,rater=:rater),
               intercept=Normal(0,1),observation,
               observation_prior=observation.family===:beta ? (precision=LogNormal(0,1),) : (;))
        input=observation.family===:beta ? merge(data,(score=0.25 .+ data.score./2,)) : data
        error_default=try mfrm_spec(input;opts...); nothing catch e; e end
        error_empty=try mfrm_spec(input;opts...,population=(;)); nothing catch e; e end
        @test error_default isa ArgumentError
        @test typeof(error_default) === typeof(error_empty)
        @test sprint(showerror,error_default) == sprint(showerror,error_empty)
    end
end

@testset "Row tables, criterion role, ScaleIdentifiedMGMFRM options/plot, and provenance" begin
    row_table = [(person="P$p", criterion="C$i", rater="R$r", score=mod(p+i+r,3)) for (p,i,r) in rows]
    dict_table = Dict(:person=>[r.person for r in row_table], :criterion=>[r.criterion for r in row_table],
                      :rater=>[r.rater for r in row_table], :score=>[r.score for r in row_table])
    # 1D mfrm_spec accepts row tables, Dict tables, and default person/score keywords
    s1_rows = mfrm_spec(row_table; facets=(criterion=:criterion, rater=:rater), steps=:criterion, category_levels=0:2, prior=:default)
    s1_dict = mfrm_spec(dict_table; facets=(criterion=:criterion, rater=:rater), steps=:criterion, category_levels=0:2, prior=:default)
    @test L.dimension(s1_rows) == L.dimension(s1_dict)
    @test_throws ArgumentError FacetData([1, 2, 3]; person=:person, item=:item, rater=:rater, score=:score)

    # Generalized mfrm_spec preserves criterion role across default/explicit priors, with_options, summaries, contrasts, and Fair Average
    g_spec = mfrm_spec(row_table; facets=(criterion=:criterion, rater=:rater), steps=:criterion,
                       category_levels=0:2, slope=:rater, prior=:default)
    g_same_pr = mfrm_spec(row_table; facets=(criterion=:criterion, rater=:rater), steps=:criterion,
                          category_levels=0:2, slope=:rater, prior=g_spec.prior)
    @test g_same_pr.prior.item_role === :criterion && g_same_pr.step_owner === :item
    custom_pr = B.ScaleIdentifiedMGMFRM.Prior(family_tag=:gmfrm, item_slopes=:fixed_one, step_owner=:item)
    g_custom = mfrm_spec(row_table; facets=(criterion=:criterion, rater=:rater), category_levels=0:2,
                         slope=:rater, prior=custom_pr)
    @test g_custom.prior.item_role === :criterion
    @test [x.name for x in A.fair_reference_basis(g_custom).facets] == [:criterion, :rater]
    @test with_options(g_spec; prior=custom_pr).prior.item_role === :criterion
    @test_throws ArgumentError mfrm_spec(ratings; options..., slope=:rater,
        prior=B.ScaleIdentifiedMGMFRM.Prior(family_tag=:gmfrm, item_slopes=:fixed_one, step_owner=:item, item_role=:criterion))

    g_opt = with_options(g_spec; slope=:item, steps=:global)
    @test g_opt.prior.item_slopes === :estimated_positive
    @test g_opt.prior.rater_consistency === :fixed_one
    @test g_opt.step_owner === :global
    @test_throws ArgumentError with_options(g_spec; steps=:rater, step_owner=:item)
    @test_throws ArgumentError with_options(g_spec; slope=:item, rater_consistency=:estimated_positive)

    t_g1 = with_options(g_spec; step_owner=:global)
    t_g2 = with_options(t_g1; steps=:global)
    t_g3 = mfrm_spec(row_table; facets=(criterion=:criterion, rater=:rater), steps=:global,
                     category_levels=0:2, slope=:rater, prior=:default)
    @test B.ScaleIdentifiedMGMFRM.target_identity(t_g1) == B.ScaleIdentifiedMGMFRM.target_identity(t_g2) == B.ScaleIdentifiedMGMFRM.target_identity(t_g3)

    rows_4c = [(person="P$p", criterion="C$i", rater="R$r", score=mod(p+i+r,3)) for p in 1:4 for i in 1:4 for r in 1:2]
    m_spec = mfrm_spec(rows_4c; facets=(criterion=:criterion, rater=:rater), steps=:criterion,
                       category_levels=0:2, q_matrix=Bool[1 0; 1 0; 0 1; 0 1], prior=:default)
    @test m_spec.prior.item_role === :criterion
    t_m1 = with_options(m_spec; step_owner=:global)
    t_m2 = with_options(t_m1; steps=:global)
    @test B.ScaleIdentifiedMGMFRM.target_identity(t_m1) == B.ScaleIdentifiedMGMFRM.target_identity(t_m2)

    g_fit = fit(g_spec; chains=2, warmup=15, ndraws=15, seed=7)
    @test facet_summary(g_fit; facet=:criterion).facet === :criterion
    @test contrast(g_fit; facet=:criterion, left="C2", right="C1").left == "item[C2]"
    @test contrast(g_fit, :criterion, "C2", "C1").right == "item[C1]"
    fa_rows = diagnostics(g_fit; kind=:fair_average, reference_plan=[(criterion="C1", rater="R1")])
    fa_dict = diagnostics(g_fit; kind=:fair_average, reference_plan=Dict(:criterion=>["C1"], :rater=>["R1"]))
    @test fa_rows.rows[1].mean ≈ fa_dict.rows[1].mean
    @test_throws ArgumentError diagnostics(g_fit; kind=:fair_average,
        reference_plan=Dict{Any,Any}(:criterion=>["C1"], "criterion"=>["C2"], :rater=>["R1"]))
    @test_throws ArgumentError mfrm_spec(Dict{Any,Any}(:person=>["P1"], "person"=>["P2"], :criterion=>["C1"], :rater=>["R1"], :score=>[0]);
        facets=(criterion=:criterion, rater=:rater), category_levels=0:2, prior=:default)

    # Prior predictive simulation tolerates single-category draws and preserves rating-scale vs partial-credit step specs
    ppc_prior = B.ScaleIdentifiedMGMFRM.prior_predictive_check(g_spec; ndraws=50, seed=1)
    @test size(ppc_prior.replicated_scores) == (50, length(row_table))
    @test length(ppc_prior.rows) == 3
    sim_glob = B.ScaleIdentifiedMGMFRM.simulate(t_m1; seed=11)
    @test sim_glob.spec.thresholds === :rating_scale
    @test sim_glob.target.step_owner === :global
    q_ext = zeros(L.dimension(t_m1))
    q_ext[t_m1.ability_mean_z_range] .= 500.0
    sim_ext = B.ScaleIdentifiedMGMFRM.simulate(t_m1; seed=12, q=q_ext)
    @test all(==(2), sim_ext.scores)
    @test !sim_ext.spec.validation.passed
    @test any(iss -> iss.code === :single_observed_category, sim_ext.spec.validation.issues)
    @test sim_ext.spec.thresholds === :rating_scale
    @test L.dimension(sim_ext.target) == L.dimension(t_m1)

    # Criterion-role PortableHandoff preserves criterion IDs, step ownership, slope metadata, and bundle SHA-256
    ho_crit = B.PortableHandoff.export_handoff(g_fit)
    @test haskey(ho_crit.record.ids, :criterion) && !haskey(ho_crit.record.ids, :item)
    @test ho_crit.record.ids.criterion == ["C1", "C2"]
    @test ho_crit.record.prior_summary.step_owner == "criterion"
    @test ho_crit.record.prior_summary.item_slopes == "fixed_one"
    @test ho_crit.record.prior_summary.rater_consistency == "estimated_positive"
    @test ho_crit.record.prior_and_reference.threshold_owner == "criterion"
    @test ho_crit.record.prior_and_reference.identification == "gmfrm_isometric_geometric_mean_one"
    g_anc = mfrm_spec(row_table; facets=(criterion=:criterion, rater=:rater), steps=:criterion,
                      category_levels=0:2, slope=:item, scale_identification=:anchor_item,
                      anchor_items=Dict(1=>"C1"), prior=:default)
    g_anc_fit = fit(g_anc; chains=2, warmup=10, ndraws=10, seed=8)
    ho_anc = B.PortableHandoff.export_handoff(g_anc_fit)
    @test ho_anc.record.prior_summary.rater_consistency == "fixed_one"
    @test ho_anc.record.prior_and_reference.identification == "gmfrm_anchor_item"
    mktempdir() do d_ho
        p_ho = joinpath(d_ho, "crit_handoff.json")
        B.PortableHandoff.save_handoff(p_ho, ho_crit)
        ho_re = B.PortableHandoff.load_handoff(p_ho)
        @test ho_re.record.handoff_bundle_sha256 == ho_crit.record.handoff_bundle_sha256
        @test ho_re.record.ids.criterion == ["C1", "C2"]
    end

    # Generalized mfrm_spec accepts missing_policy and propagates missing_audit into PortableHandoff
    row_table_miss = vcat(row_table, [(person="P1", criterion="C1", rater="R1", score=missing)])
    @test_throws ArgumentError mfrm_spec(row_table_miss; facets=(criterion=:criterion, rater=:rater),
        steps=:criterion, category_levels=0:2, slope=:rater, prior=:default)
    g_drop = @test_logs (:warn,) mfrm_spec(row_table_miss; facets=(criterion=:criterion, rater=:rater),
        steps=:criterion, category_levels=0:2, slope=:rater, prior=:default, missing_policy=:drop_with_audit)
    @test g_drop.spec.data.columns.missing_audit.n_dropped_rows == 1
    g_exp_ma = mfrm_spec(row_table; facets=(criterion=:criterion, rater=:rater), steps=:criterion,
        category_levels=0:2, slope=:rater, prior=:default,
        missing_audit=(policy=:pre_filtered, n_input_rows=20, n_dropped_rows=4, n_retained_rows=16))
    @test g_exp_ma.spec.data.columns.missing_audit.n_dropped_rows == 4

    ext = Base.get_extension(B, :BayesianMGMFRMCairoMakieExt)
    if ext === nothing
        err = try B.plot(g_fit; kind=:posterior); nothing catch e; e end
        @test err isa ArgumentError && occursin("CairoMakie", sprint(showerror, err))
    else
        @test ext._additive_model_title_prefix((api=B.ScaleIdentifiedMGMFRM.contract(m_spec),)) == "Scale-identified MGMFRM"
        pnames = B.parameter_names(g_fit; scale=:model)
        out_sub = B.plot(g_fit; kind=:posterior, parameters=pnames[1:2], max_parameters=1, annotation_io=devnull, return_data=true)
        @test length(out_sub.data.summary.rows) == 1
        @test_throws ArgumentError B.plot(g_fit; kind=:posterior, parameters=[pnames[1], "NOT_A_PARAMETER"], annotation_io=devnull)
        cap_io = IOBuffer()
        B.plot(g_fit; kind=:prediction, rows=[1], annotation_io=cap_io)
        cap_str = String(take!(cap_io))
        @test !occursin("Row attributes", cap_str) && !occursin("probability MCSE", cap_str)

        rep_tr = B.fit_report(g_fit; parameters=pnames[1:2], interval=0.80, include_draws=true)
        pred_rep = predict(g_fit; rows=[1, 2], interval=0.80)
        ppc_rep = predictive_check(g_fit; ndraws=2, interval=0.80)
        @test_throws ArgumentError B.plot(rep_tr; kind=:posterior, interval=0.99, annotation_io=devnull)
        @test_throws ArgumentError B.plot(rep_tr; kind=:posterior, scale=:raw, annotation_io=devnull)
        @test_throws ArgumentError B.plot(rep_tr; kind=:posterior, parameters=pnames[1:1], annotation_io=devnull)
        @test_throws ArgumentError B.plot(rep_tr; kind=:posterior, parameters=[pnames[1], "NOT_A_PARAMETER"], annotation_io=devnull)
        @test_throws ArgumentError B.plot(rep_tr; kind=:diagnostics, parameters=pnames[1:1], annotation_io=devnull)
        @test_throws ArgumentError B.plot(rep_tr; kind=:diagnostics, max_parameters=1, annotation_io=devnull)
        @test_throws ArgumentError B.plot(pred_rep; kind=:prediction, rows=[1], annotation_io=devnull)
        @test_throws ArgumentError B.plot(pred_rep; kind=:prediction, interval=0.99, annotation_io=devnull)

        mktempdir() do d
            p_tr = joinpath(d, "trace.json")
            p_pr = joinpath(d, "pred.json")
            p_pp = joinpath(d, "ppc.json")
            save_report(p_tr, rep_tr)
            save_report(p_pr, pred_rep)
            save_report(p_pp, ppc_rep)
            j_tr = load_report(p_tr)
            j_pr = load_report(p_pr)
            j_pp = load_report(p_pp)
            @test B.plot(j_tr; kind=:posterior, reference=0.0, annotation_io=devnull, return_data=true).data.summary.interval == 0.80
            @test length(B.plot(j_tr; kind=:diagnostics, annotation_io=devnull, return_data=true).data.traces.parameters) == 2
            @test B.plot(j_pr; kind=:prediction, annotation_io=devnull, return_data=true).data.rows == [1, 2]
            @test B.plot(j_pp; kind=:predictive, annotation_io=devnull, return_data=true).data.n_replications == 2
        end
    end

    # Provenance helpers survive active_project() === nothing and normalize paths
    old_ap, old_hp, old_lp = Base.ACTIVE_PROJECT[], Base.HOME_PROJECT[], copy(LOAD_PATH)
    try
        Base.ACTIVE_PROJECT[] = nothing
        Base.HOME_PROJECT[] = nothing
        empty!(LOAD_PATH); push!(LOAD_PATH, "@stdlib")
        @test Base.active_project() === nothing
        sig = B.Generalizability.source_signature()
        @test sig.source isa String && length(sig.source) == 64 && sig.manifest === nothing
    finally
        append!(empty!(LOAD_PATH), old_lp)
        Base.HOME_PROJECT[] = old_hp
        Base.ACTIVE_PROJECT[] = old_ap
    end

    # v0.2 empirical stress-test & post-audit regressions:
    # 1) Generalized PortableHandoff preserves exact category_levels (including 1:25) and binds them to handoff_bundle_sha256
    @test collect(Int, ho_crit.record.prior_and_reference.category_levels) == [0, 1, 2]
    row_table_25 = [(; r..., score = 1 + 12 * r.score) for r in row_table]
    g25_spec = mfrm_spec(row_table_25; facets=(criterion=:criterion, rater=:rater),
        steps=:global, category_levels=1:25, slope=:rater, prior=:default)
    g25_fit = fit(g25_spec; chains=2, warmup=8, ndraws=8, seed=29)
    ho_g25 = B.PortableHandoff.export_handoff(g25_fit)
    @test collect(Int, ho_g25.record.prior_and_reference.category_levels) == collect(1:25)
    mktempdir() do d_cat
        p25 = joinpath(d_cat, "gm25.json")
        B.PortableHandoff.save_handoff(p25, ho_g25)
        ho25_re = B.PortableHandoff.load_handoff(p25)
        @test collect(Int, ho25_re.record.prior_and_reference.category_levels) == collect(1:25)
        raw_txt = read(p25, String)
        # Tamper category_levels 1 -> 0 while keeping draws untouched -> handoff_bundle_sha256 must reject!
        bad_txt = replace(raw_txt, "\"category_levels\":[1," => "\"category_levels\":[0,"; count=1)
        @test bad_txt != raw_txt
        p25_bad = joinpath(d_cat, "gm25_tampered.json")
        write(p25_bad, bad_txt)
        @test_throws ArgumentError B.PortableHandoff.load_handoff(p25_bad)
    end

    # 2) 1D mfrm_spec accepts missing_policy = :drop_with_audit and retains validate_design(spec).missing_audit across ALL 1D branches
    onboarding_72 = [(;
        person = "P$(lpad(p, 2, '0'))",
        criterion = "C$(c)",
        rater = "R$(r)",
        score = p == 1 && c == 1 && r == 1 ? missing : mod(p + c + r, 3),
        trials = 4,
        zoib_y = p == 1 && c == 1 && r == 1 ? missing : (mod(p + c + r, 3) / 2.0),
    ) for p in 1:12 for c in 1:2 for r in 1:3]
    @test length(onboarding_72) == 72

    s72_def = @test_logs (:warn,) mfrm_spec(onboarding_72; facets=(criterion=:criterion, rater=:rater),
        steps=:criterion, category_levels=0:2, prior=:default, missing_policy=:drop_with_audit)
    s72_frq = @test_logs (:warn,) mfrm_spec(onboarding_72; facets=(criterion=:criterion, rater=:rater),
        steps=:global, category_levels=0:2, prior=:none, missing_policy=:drop_with_audit)
    psd_num = (person = 1.5, facets = (criterion = 0.8, rater = 0.8), step = 0.8)
    s72_add = @test_logs (:warn,) mfrm_spec(onboarding_72; facets=(criterion=:criterion, rater=:rater),
        steps=:criterion, category_levels=0:2, prior_sd=psd_num, missing_policy=:drop_with_audit)
    s72_mix = @test_logs (:warn,) mfrm_spec(onboarding_72; facets=(criterion=:criterion, rater=:rater),
        steps=:criterion, category_levels=Dict("C1"=>0:2, "C2"=>0:2), prior_sd=psd_num, missing_policy=:drop_with_audit)
    s72_exp = @test_logs (:warn,) mfrm_spec(onboarding_72; facets=(criterion=:criterion, rater=:rater),
        steps=:criterion, category_levels=0:2,
        prior_sd=(person = 1.5, facets = (criterion = 0.8,), step = 0.8),
        population=(rater = LogNormal(-0.2, 0.3),), missing_policy=:drop_with_audit)
    s72_cnt = @test_logs (:warn,) mfrm_spec(onboarding_72; facets=(criterion=:criterion, rater=:rater),
        observation=(family=:binomial, trials=:trials),
        population=(person=LogNormal(0.0, 0.3), criterion=LogNormal(-0.2, 0.3), rater=LogNormal(-0.2, 0.3)),
        intercept=Normal(0.0, 1.5), missing_policy=:drop_with_audit)
    s72_zoi = @test_logs (:warn,) mfrm_spec(onboarding_72; score=:zoib_y, facets=(criterion=:criterion, rater=:rater),
        observation=(family=:zero_one_inflated_beta, bounds=(0.0, 1.0)),
        observation_prior=(precision=LogNormal(1.0, 0.4), endpoint_logit=Normal(-1.0, 1.0), upper_logit=Normal(0.0, 1.0)),
        population=(person=LogNormal(0.0, 0.3), criterion=LogNormal(-0.2, 0.3), rater=LogNormal(-0.2, 0.3)),
        intercept=Normal(0.0, 1.5), missing_policy=:drop_with_audit)
    for sp72 in (s72_def, s72_frq, s72_add, s72_mix, s72_exp, s72_cnt, s72_zoi)
        ma72 = validate_design(sp72).missing_audit
        @test ma72 !== nothing
        @test ma72.n_input_rows == 72
        @test ma72.n_dropped_rows == 1
        @test ma72.n_retained_rows == 71
        @test ma72.dropped_rows == [1]
    end
    f72_add = fit(s72_add; chains=2, warmup=8, ndraws=8, seed=31)
    @test validate_design(f72_add).missing_audit.dropped_rows == [1]
    ho72_add = B.PortableHandoff.export_handoff(f72_add)
    @test ho72_add.record.missing_audit !== nothing
    @test collect(Int, ho72_add.record.missing_audit.dropped_rows) == [1]
    @test B.AdditiveFacets.restore(B.AdditiveFacets.record(s72_add)).columns.missing_audit.n_dropped_rows == 1
    mktempdir() do d_ma
        p_ma_rep = joinpath(d_ma, "add_fit_report.json")
        save_report(p_ma_rep, B.fit_report(f72_add))
        re_ma_rep = load_report(p_ma_rep)
        @test re_ma_rep.api.record.columns.missing_audit.n_dropped_rows == 1
        @test collect(Int, re_ma_rep.api.record.columns.missing_audit.dropped_rows) == [1]
    end

    @test_throws ArgumentError mfrm_spec(row_table_miss; facets=(criterion=:criterion, rater=:rater),
        steps=:criterion, category_levels=0:2, prior=:default, missing_policy=:drop_rows)

    # 2) Omitted reference_plan in diagnostics(...; kind=:fair_average) and omitted args in prior_sensitivity throw ArgumentError, never UndefKeywordError
    f1_mmle = fit(mfrm_spec(row_table; facets=(criterion=:criterion, rater=:rater),
        steps=:global, category_levels=0:2, prior=:none); method=:mmle)
    @test_throws ArgumentError diagnostics(f1_mmle; kind=:fair_average)
    @test_throws ArgumentError diagnostics(g_fit; kind=:fair_average)
    @test_throws ArgumentError prior_sensitivity(g_fit)
    @test_throws ArgumentError prior_sensitivity(f1_mmle)

    # 3) Positional and arbitrary-order Pair cross-family compare_models work cleanly
    s1_fit = fit(s1_rows; chains=2, warmup=10, ndraws=10, seed=19)
    @test_throws ArgumentError prior_sensitivity(s1_fit)
    cmp_pos = compare_models(s1_fit, g_fit, g_anc_fit)
    @test length(cmp_pos.rows) == 3
    cmp_pair3 = compare_models(:m1 => s1_fit, :m2 => s1_fit, :m3 => g_fit)
    @test Set(Symbol(m.model_label) for m in cmp_pair3.rows) == Set([:m1, :m2, :m3])
end

end
