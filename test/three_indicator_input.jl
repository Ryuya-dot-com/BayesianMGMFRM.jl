module ThreeIndicatorInputChecks
using BayesianMGMFRM, Test
using BayesianMGMFRM: JSON3, SHA
const T=BayesianMGMFRM.Experimental.ThreeIndicator
const INPUT=joinpath(pkgdir(BayesianMGMFRM),"examples/data/three_indicator_165.json")
object(x)=JSON3.read(JSON3.write(x))

function checks()
    @testset "Three-outcome input: existing synthetic data and malformed copies" begin
        text=read(INPUT,String);digest=bytes2hex(SHA.sha256(text))
        x=JSON3.read(text,Dict{String,Any})
        before=JSON3.write(x);r=T.inspect_input(object(x))
        @test r.counts==(events=165,listeners=5,speaker_styles=11,words=3,recordings=33,cohorts=2)
        @test r.fixed_design==(rank=17,columns=17)
        @test r.ratings_per_listener==fill(33,5)
        @test r.ratings_per_recording==fill(5,33)
        @test length(r.block_start_events)==20
        @test all(sum(c)==165 for c in r.category_counts)
        @test !r.scientific_acceptance && !r.fitting
        @test r.labels==object(x).labels && r.metadata==object(x).metadata
        @test JSON3.write(x)==before
        @test T.inspect_input(INPUT;expected_sha256=digest).source_sha256==digest
        @test_throws ArgumentError T.inspect_input(INPUT;expected_sha256="0"^64)
        for change in (
            y->delete!(y,"metadata"),
            y->(y["N"]=true),
            y->(y["use_state"]=1),
            y->(y["K"]=[9,9,9]),
            y->reverse!(y["predictor_names"]),
            y->(y["metadata"]["binary_coding"]="1=incorrect;2=correct"),
            y->(y["metadata"]["predictor_units"]=""),
            y->(y["y"][1][3]=0),
            y->(y["y"][1][1]=1.5),
            y->pop!(y["y"][1]),
            y->(y["rater"][1]=true),
            y->(y["token"][1]=y["token"][2]),
            y->(y["token_lookup"][1][1]=y["token_lookup"][1][2]),
            y->(y["l1"][1]=1),
            y->(y["previous_trial"][2]=0),
            y->(y["previous_trial"][10]=0), # Blocks reset history, not trial links.
            y->(y["trial"][2]=3),
            y->(y["speaker_cell"][1]=2),
            y->(y["labels"]["speaker"][1]=y["labels"]["speaker"][2]),
            y->(y["within_time"][1]=100.),
            y->(y["X"][1][5]=.5),
            y->(y["l1_contrast"][1][1]+=.1),
            y->(y["X"][1][1]=0),
            y->(y["X"][2][9]=0),
            y->(y["X"][10][13]=0),
            y->(y["X"][2][13]=1),
            y->foreach(row->(row[15]=row[14]),y["X"]))
            wrong=deepcopy(x);change(wrong)
            @test_throws ArgumentError T.inspect_input(object(wrong))
        end
        for (event,column,description) in ((1,1,"current-condition"),(2,9,"previous-condition"),(10,13,"previous-condition"))
            wrong=deepcopy(x);wrong["X"][event][column]=0
            failure=try T.inspect_input(object(wrong));nothing catch e;e end
            @test failure isa ArgumentError && occursin(description,sprint(showerror,failure))
        end
        sparse=deepcopy(x)
        foreach(row->(row[1]=1),sparse["y"])
        r=T.inspect_input(object(sparse))
        @test r.categories==[9,9,2] && r.category_counts[1]==[165;zeros(Int,8)]
        @test any(contains("unobserved"),r.warnings)
        @test Base.Docs.doc(T.inspect_input)!==nothing
    end
end
function interface_checks()
    @testset "In-memory named input and native matrices" begin
        x=JSON3.read(read(INPUT,String))
        named=(;pairs(x)...)
        @test T.inspect_input(named).counts==T.inspect_input(x).counts
        matrix=merge(named,(;X=reduce(vcat,permutedims.(collect.(x.X))),
            y=reduce(vcat,permutedims.(collect.(x.y))),
            token_lookup=reduce(vcat,permutedims.(collect.(x.token_lookup))),
            l1_contrast=reduce(vcat,permutedims.(collect.(x.l1_contrast)))))
        before=copy(matrix.X)
        @test T.inspect_input(matrix).category_counts==T.inspect_input(x).category_counts
        @test matrix.X==before
        bad=copy(matrix.X);bad[1,1]=NaN
        @test_throws ArgumentError T.inspect_input(merge(matrix,(;X=bad)))
        @test_throws ArgumentError T.inspect_input(merge(matrix,(;X=fill(true,size(matrix.X)))))
    end
end
end
