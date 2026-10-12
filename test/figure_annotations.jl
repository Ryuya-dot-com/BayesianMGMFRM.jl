# Optional CairoMakie checks; deterministic fixtures, no posterior fitting.
module FigureAnnotationChecks
using BayesianMGMFRM, CairoMakie, Test, Random, SHA
const B = BayesianMGMFRM
include("common_prediction_fixtures.jl")
labels(fig) = [String(x.text[]) for x in fig.content if x isa Label]
axes(fig) = filter(x -> x isa Axis || x isa Axis3, fig.content)

function check_annotations(directory)
    @testset "external figure text and embedded compatibility" begin
        old = [reporting_fit(family; chains = 2, ndraws = 8) for family in (:mfrm, :gmfrm, :mgmfrm)]
        fixed = [prediction_fixed_fixture(kind; ndraws = 8).fit for kind in
            (:independent, :correlated, :exchangeable, :exchangeable_correlated)]
        record = F.synthetic_record(F.target())
        correlated = B.Experimental.CorrelatedMGMFRMFit(record; expected_identity = record.target_identity)
        normalized = normalized_fixture(record)
        for fit in vcat(old, fixed, [correlated, normalized])
            for (plot, options) in ((B.plot_posterior, (; block = :rater)),
                    (B.plot_diagnostics, (; block = :rater)),
                    (B.plot_predictive, (; ndraws = 4, seed = 12)))
                text = IOBuffer()
                figure = plot(fit; options..., annotation_io = text)
                note = String(take!(text))
                @test figure isa Figure
                @test occursin("\n\nNote. ", note)
                @test occursin("MCMC ", note)
                @test !occursin("\n\nNote. ", join(labels(figure)))
                embedded = plot(fit; options..., annotation_io = nothing)
                embedded_labels = labels(embedded)
                @test length(embedded_labels) == length(labels(figure)) + 2
                @test note == replace(embedded_labels[end-1], '\n' => ' ') * "\n\nNote. " * embedded_labels[end] * "\n"
                @test length(axes(figure)) == length(axes(embedded))
                @test [length(ax.scene.plots) for ax in axes(figure)] == [length(ax.scene.plots) for ax in axes(embedded)]
                @test_throws ArgumentError plot(fit; options..., annotation_io = "not an IO stream")
            end
            GC.gc()
        end
        fit = first(old)
        mktemp() do _, io
            figure = redirect_stdout(io) do
                B.plot_wright(fit)
            end
            flush(io); seekstart(io)
            note = read(io, String)
            @test isempty(labels(figure))
            @test startswith(note, "MFRM Wright map Shared logit scale\n\nNote. ")
            @test occursin("MCMC ", note)
            @test content(figure[1, 1]) isa Axis
            for suffix in ("svg", "pdf")
                save(joinpath(directory, "wright.$suffix"), figure)
                @test filesize(joinpath(directory, "wright.$suffix")) > 1000
            end
        end
        closed = IOBuffer(); close(closed)
        for io in (false, closed, IOBuffer("read only"))
            @test_throws ArgumentError B.plot_wright(fit; annotation_io = io)
        end
        path = joinpath(directory, "fit.jls")
        save_fit_cache(path, fit)
        hash = sha256(read(path))
        original_note, replay_note = IOBuffer(), IOBuffer()
        first_figure = B.plot_wright(fit; annotation_io = original_note)
        replay = B.plot_wright(load_fit_cache(path); annotation_io = replay_note)
        @test take!(original_note) == take!(replay_note)
        @test sha256(read(path)) == hash
        @test [ax.xticks[] for ax in axes(first_figure)] == [ax.xticks[] for ax in axes(replay)]
        for category in (:all, nothing, 1)
            text = IOBuffer()
            figure = B.plot_response_surface(old[3]; item = 1, rater = 1,
                x = [-1., 0., 1.], y = [-1., 0., 1.], category, annotation_io = text)
            note = String(take!(text))
            @test isempty(labels(figure))
            @test occursin("Item $(first(old[3].design.spec.data.item_levels))", note) &&
                occursin("Rater $(first(old[3].design.spec.data.rater_levels))", note)
            @test occursin("whole fit", note)
            @test only(filter(x -> x isa Axis3, figure.content)).zlabel[] != ""
        end
        for fit in fixed[1:2]
            r = fit.record
            model = fit isa B.Experimental.CorrelatedMFRMFit ?
                B.Experimental.correlated(r.base_spec; lkj_eta = r.prior.correlation.lkj_eta) : r.spec
            check = B.Experimental.prior_predictive_check(model; ndraws = 8, rng = MersenneTwister(8))
            for (plot, options) in ((B.plot_prior, (; block = :rater)), (B.plot_predictive, (;)))
                io = IOBuffer(); figure = plot(check; options..., annotation_io = io)
                note = String(take!(io))
                @test isempty(labels(figure))
                @test occursin("prior", lowercase(note))
                @test occursin("no posterior fitting", lowercase(note))
            end
        end
        for (name, fit) in (("stable", first(old)), ("fixed", fixed[1]), ("correlated", correlated))
            # Each of the three report callbacks must supply the same exact external note.
            choices = name == "stable" ? (; posterior = (; block = :rater), wright = (;)) :
                (; posterior = (; block = :rater), prior = (; block = :rater), prior_predictive = (;))
            options = name == "stable" ? (; include_artifact = false, include_loo = false,
                include_waic = false, include_calibration = false, include_category_functioning = false,
                include_rater_homogeneity = false, include_grouped_predictive = false) :
                (; include_artifact = false, include_prior_predictive = true, prior_predictive_ndraws = 8)
            folder = joinpath(directory, name)
            manifest = save_fit_report_bundle(folder, fit; figures = choices, seed = 8, options...)
            markdown = read(joinpath(folder, "fit_report.md"), String)
            @test occursin("**Figure 1**", markdown)
            @test load_fit_report_bundle(folder; return_manifest = true)["schema"] == manifest.schema
            for row in manifest.figures
                payload = B.JSON3.read(read(joinpath(folder, "figures", "$(row.kind).json"), String))
                @test payload.figure_title == row.figure_title
                @test payload.annotation_text == row.figure_title * "\n\nNote. " * row.caption * "\n"
                @test occursin("*$(row.figure_title)*", markdown)
                @test occursin("*Note.* " * row.caption, markdown)
            end
        end
    end
end
mktempdir(check_annotations)
end
