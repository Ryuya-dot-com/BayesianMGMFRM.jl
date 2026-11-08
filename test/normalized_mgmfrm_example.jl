module NormalizedExampleChecks
using Test
include("../examples/normalized_mgmfrm.jl")
const A = NormalizedMGMFRMExample
module DimensionSupportLesson end

function dimension_support_checks()
    @testset "MGMFRM lesson exposes person-level dimension gaps without fitting" begin
        text = read(joinpath(@__DIR__, "../docs/src/data-validation.md"), String)
        recipe = only([m.captures[1] for m in eachmatch(r"(?ms)^```julia\n(.*?)^```", text)
            if startswith(m.captures[1], "# MGMFRM person-dimension inspection")])
        lesson = DimensionSupportLesson
        Base.include_string(lesson, recipe, "data-validation.md")
        # Julia 1.12 versions global bindings introduced by include_string.
        lesson = Base.invokelatest() do
            m = DimensionSupportLesson
            (;m.data, m.validation, m.q_check, m.affected, m.q, m.q_by_item, m.spec, m.ratings)
        end
        p = A.example_inputs()
        @test lesson.data.n < p.data.n
        @test lesson.validation.passed && lesson.q_check.passed
        @test lesson.affected == [(;person="P1",unobserved=("dim=2",),rank=1)]
        @test !lesson.q_check.identification.conservative_stable_structure_ready
        @test all(Tuple(lesson.q[i,:]) == lesson.q_by_item[item]
            for (i,item) in enumerate(lesson.data.item_levels))
        base_text = sprint(io -> A.print_example(io,p))
        @test occursin("50/50 have full structural rank", base_text)
        limited = merge(p, (;data=lesson.data,spec=lesson.spec))
        limited_text = sprint(io -> A.print_example(io,limited))
        @test occursin("49/50 have full structural rank", limited_text)
        @test occursin("P1: no ratings for dim=2", limited_text)
        @test occursin("does not guarantee precise estimates", limited_text)

        # A cross-loading can touch both dimensions without separating them.
        keep = [person != "P1" || item == "I1"
            for (person,item) in zip(lesson.ratings.person,lesson.ratings.item)]
        data = A.FacetData(map(col -> col[keep],lesson.ratings);
            person=:person,item=:item,rater=:rater,score=:score,category_levels=1:4)
        q = copy(lesson.q); q[findfirst(==("I1"),data.item_levels),:] .= true
        spec = A.mfrm_spec(data;family=:mgmfrm,dimensions=2,q_matrix=q,
            dimension_labels=["dim=1","dim=2"])
        check = A.q_matrix_validation(spec)
        row = only(filter(r -> r.person_label == "P1",check.identification.likelihood_support.person_rows))
        @test check.passed && A.validate_design(data).passed
        @test isempty(row.unobserved_dimensions) && !row.full_column_rank
        @test occursin("P1: observed items do not separate all ability directions",
            sprint(io -> A.print_example(io,merge(p,(;data,spec)))))

        # Finite kernel evaluations, not prior draws or fitted posterior samples.
        B = A.BayesianMGMFRM
        target = B._normalized_mgmfrm_target(lesson.spec,p.prior)
        initial = B.initial_params(target)
        index = only(findall(==("person[P1,dim=2]"),target.base.blueprint.parameter_names))
        observed_index = only(findall(==("person[P1,dim=1]"),target.base.blueprint.parameter_names))
        ll0 = B._source_fixture_loglikelihood(target.base,initial)
        for change in (-2.0,1.5)
            point = copy(initial); point[index] += change
            @test B._source_fixture_loglikelihood(target.base,point) == ll0
            expected = -(point[index]^2-initial[index]^2)/(2p.prior.scales.person_sd^2)
            @test B.logprior(target,point)-B.logprior(target,initial) ≈ expected atol=1e-10
            @test B.LogDensityProblems.logdensity(target,point)-B.LogDensityProblems.logdensity(target,initial) ≈ expected atol=1e-9
        end
        point = copy(initial); point[observed_index] += 1.5
        @test B._source_fixture_loglikelihood(target.base,point) != ll0
    end
end

function entry_checks()
    @testset "Normalized MGMFRM command entry without sampling" begin
        @test A.options(String[]) == (;figures=false, saved_fit=nothing, example_mode=:inspect)
        @test A.options(["--help"]).example_mode === :help
        @test A.options(["-h"]).example_mode === :help
        @test A.options(["--demo"]).example_mode === :demo
        @test A.options(["--demo", "--figures"]).figures
        @test A.options(["--figures", "--demo"]).example_mode === :demo
        @test A.options(["--saved-fit", "a fit.jls"]).saved_fit == "a fit.jls"
        @test A.options(["--figures", "--saved-fit", "fit.jls"]).figures
        @test A.options(["--saved-fit", "fit.jls", "--figures"]).saved_fit == "fit.jls"
        @test A.options(["--inspect-example"]).example_mode === :inspect
        @test A.options(["--fit-example"]).example_mode === :fit
        @test A.options(["--fit-example", "--figures"]).figures
        for args in (["--saved-fit"], ["--unknown"], ["fit.jls"],
                ["--figures", "--figures"], ["--saved-fit", "--other"],
                ["--saved-fit", "a", "--saved-fit", "b"],
                ["--inspect-example", "--figures"], ["--inspect-example", "--fit-example"],
                ["--fit-example", "--saved-fit", "a"], ["--figures"],
                ["--help", "--figures"], ["--help", "--demo"], ["--help", "--help"],
                ["--demo", "--fit-example"], ["--demo", "--saved-fit", "a"])
            @test_throws ArgumentError A.options(args)
        end
        @test_throws ArgumentError A.main(["--unknown"])
        help = sprint(A.print_help)
        @test all(occursin(mode,help) for mode in
            ("--help", "--inspect-example", "--fit-example", "--saved-fit", "--demo", "--figures"))
        @test occursin("No arguments inspect", help)
        @test occursin("not for inference", help)
        mktempdir() do directory
            for (name,args,mode) in (("help",["--help"],:help), ("default",String[],:inspect))
                # Fail before calling main if the parser could enter a sampling route.
                A.options(args).example_mode === mode || error("Unexpected command mode")
                destination = joinpath(directory,"results-$name")
                output = joinpath(directory,"$name.txt")
                result = open(output,"w") do io
                    redirect_stdout(io) do
                        A.main(args; output_parent=destination)
                    end
                end
                @test !ispath(destination)
                text = read(output,String)
                if mode === :help
                    @test result.help_only
                    @test text == help
                else
                    @test result.inspection_only
                    @test result.prepared.data.n == 1000
                    @test occursin("50/50 have full structural rank",text)
                    @test occursin("no fit or random draws were generated",text)
                    @test !occursin("Saved fit before reporting:",text)
                end
            end
        end
    end
end

function checks()
    entry_checks()
    @testset "Normalized example: warning preservation" begin
        metadata = (;n_observations=1, n_persons=1, n_items=1, n_raters=1,
            n_draws=0, n_chains=0, dimension_labels=["Trait"], dimensions=1)
        report = (;diagnostics=(;summary=(;passed=false,flag=:insufficient_draws)),
            direct_posterior=(;rows=[(;block=:person,parameter="person[P1,Trait]",
                mean=0.0,lower=-1.0,upper=1.0)],
                mcse_rows=[(;parameter="person[P1,Trait]",mean_mcse=missing)]))
        output = sprint(io -> A.print_answer(io, report, metadata))
        @test occursin("Do not interpret", output)
        @test occursin("insufficient_draws", output)
        @test occursin("fixed at zero, not estimated", output)
        @test occursin("mean MCSE=missing", output)
    end
    @testset "Bundled MGMFRM inputs, without estimation" begin
        p=A.example_inputs()
        @test p.data.n==1000
        @test (length(p.data.person_levels),length(p.data.item_levels),length(p.data.rater_levels))==(50,5,5)
        @test p.data.category_levels==collect(1:4)
        @test A.validate_design(p.data).passed
        @test p.spec.q_matrix==Bool[1 0;1 0;0 1;0 1;0 1]
        @test p.spec.thresholds===:partial_credit
        @test (p.controls.chains,p.controls.warmup,p.controls.ndraws)==(4,1000,1000)
        @test p.prior.prior_model===:exchangeable
        text=sprint(io->A.print_example(io,p))
        @test occursin("unobserved, not zero scores",text)
        @test occursin("not a general prior recommendation",text)
        @test occursin("I1 measures dim=1",text) && occursin("I5 measures dim=2",text)
    end
    dimension_support_checks()
end
end
