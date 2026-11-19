using Test, BayesianMGMFRM, CairoMakie
@testset "Additive caption preserves warnings and summarizes patterns" begin
    ext=Base.get_extension(BayesianMGMFRM,:BayesianMGMFRMCairoMakieExt)
    format=ext._additive_warning_caption
    issue(code,message)=(;code,message)
    rows=[issue(:unused_interior_category,"unused middle"),
        issue("unobserved_declared_endpoint","unused end"),
        issue(:constant_score_pattern,"constant A"),
        issue(:constant_score_pattern,"constant B"),
        issue(:future_type,"future warning")]
    rep=(warnings=["Numerical failure retained";getproperty.(rows,:message)],
        response_patterns=(issues=rows,))
    original=deepcopy(rep);text=format(rep)
    @test occursin("1 unused-interior-category; 1 unobserved-endpoint; 2 constant-score",text)
    @test occursin("Numerical failure retained",text)
    @test occursin("future warning",text)
    @test occursin("report.response_patterns.issues",text)
    @test occursin("not distinct people or ratings",text)
    @test !occursin("constant A",text)
    @test isequal(rep,original)
    legacy=(warnings=["legacy pattern", "legacy numerical warning"],)
    @test format(legacy)==join(legacy.warnings," ")
    empty=(warnings=["other warning"],response_patterns=(issues=NamedTuple[],))
    @test format(empty)=="other warning"
    # An audit-only entry must not be promoted into a new report warning.
    absent=(warnings=["other warning"],response_patterns=(issues=rows,))
    @test format(absent)=="other warning"
end
