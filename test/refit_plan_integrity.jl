module RefitPlanIntegrityChecks
using Test, BayesianMGMFRM, Random, Serialization
const B = BayesianMGMFRM

function panel()
    rows = [(;person="P$p", rater="R$r", item="I$i", score=mod(p+r+i+e,3), event="E$e")
        for e in 1:3 for p in 1:3 for r in 1:2 for i in 1:4]
    table = (;(k=>getproperty.(rows,k) for k in keys(first(rows)))...)
    FacetData(table;person=:person,rater=:rater,item=:item,score=:score,occasion=:event,
        category_levels=0:2)
end
bytes(x) = (io=IOBuffer();serialize(io,x);take!(io))
function change_row(plan, index; kwargs...)
    result=deepcopy(plan)
    result.fold_rows[index]=merge(result.fold_rows[index],(;kwargs...))
    return result
end
caught(f) = try f(); nothing catch error; error end

checks = @testset "Refit plan integrity before sampling (no MCMC)" begin
    data=panel(); spec=mfrm_spec(data)
    plan=kfold_plan(data;k=3,group_by=:occasion,shuffle=true,rng=MersenneTwister(61),fold_ids=[:a,:b,:c])
    original=bytes(plan)
    @test B._check_kfold_refit_plan_for_execution(data,plan).passed
    @test bytes(plan)==original
    @test !kfold_plan_diagnostics(data,plan).passed # Heldout occasion is metadata only.
    for grouped in (nothing,:observation)
        plain=kfold_plan(data;k=3,group_by=grouped,shuffle=true,rng=MersenneTwister(81))
        @test B._check_kfold_refit_plan_for_execution(data,plain).passed
    end
    # Training row order may change, but scoring labels must match heldout order.
    reversed=deepcopy(plan)
    reverse!(reversed.fold_rows[2].training_observations)
    reverse!(reversed.fold_rows[2].heldout_observations)
    reverse!(reversed.heldout_observation_indices[2])
    @test B._check_kfold_refit_plan_for_execution(data,reversed).passed
    flat=merge(plan,(;heldout_observation_indices=vcat(plan.heldout_observation_indices...)))
    @test B._check_kfold_refit_plan_for_execution(data,flat).passed
    mktemp() do path,io
        serialize(io,plan);close(io)
        @test B._check_kfold_refit_plan_for_execution(data,deserialize(path)).passed
    end

    invalid=Pair{String,Any}[]
    leak=deepcopy(plan);push!(leak.fold_rows[end].training_observations,first(leak.fold_rows[end].heldout_observations))
    push!(invalid,"late training/heldout overlap"=>leak)
    omitted=deepcopy(plan);pop!(omitted.fold_rows[2].training_observations)
    push!(invalid,"missing training complement"=>omitted)
    wrong=deepcopy(plan);reverse!(wrong.heldout_observation_indices[1])
    push!(invalid,"wrong scored row labels"=>wrong)
    wrong=deepcopy(plan);wrong.observation_fold[1]=:wrong
    push!(invalid,"wrong observation-to-fold map"=>wrong)
    push!(invalid,"wrong fold order"=>merge(plan,(;folds=reverse(plan.folds))))
    push!(invalid,"duplicate fold ID"=>merge(plan,(;folds=fill(:same,3))))
    push!(invalid,"missing fold IDs"=>merge(plan,(;folds=nothing)))
    push!(invalid,"missing scored row IDs"=>merge(plan,(;heldout_observation_indices=nothing)))
    push!(invalid,"wrong fold count"=>merge(plan,(;n_folds=2)))
    push!(invalid,"wrong declared k"=>merge(plan,(;k=4)))
    push!(invalid,"wrong total rows"=>merge(plan,(;n_observations=data.n-1)))
    push!(invalid,"noninteger row count"=>merge(plan,(;n_observations=Float64(data.n))))
    push!(invalid,"wrong refit count"=>merge(plan,(;refits_per_model_required=2)))
    push!(invalid,"wrong unit count"=>merge(plan,(;n_units=2)))
    push!(invalid,"wrong heldout counts"=>merge(plan,(;n_heldout_by_fold=[1,1,1])))
    push!(invalid,"wrong per-fold count"=>change_row(plan,2;n_training_observations=0))
    push!(invalid,"empty heldout fold"=>change_row(plan,2;heldout_observations=Int[]))
    push!(invalid,"empty training fold"=>change_row(plan,2;training_observations=Int[]))
    push!(invalid,"implicit training rows"=>change_row(plan,2;training_observations=nothing))
    push!(invalid,"repeated training row"=>change_row(plan,2;training_observations=[plan.fold_rows[2].training_observations;1;1]))
    push!(invalid,"boolean heldout index"=>change_row(plan,2;heldout_observations=[true]))
    push!(invalid,"out-of-range heldout index"=>change_row(plan,2;heldout_observations=[data.n+1]))
    push!(invalid,"wrong unit labels"=>change_row(plan,2;heldout_units=["wrong"]))
    push!(invalid,"wrong unit counts"=>change_row(plan,2;n_heldout_units=2))
    duplicate=deepcopy(plan)
    duplicate.fold_rows[2]=merge(duplicate.fold_rows[1],(;fold=plan.folds[2]))
    push!(invalid,"repeated heldout rows across folds"=>duplicate)
    incomplete=merge(plan,(;k=2,n_folds=2,folds=plan.folds[1:2],fold_rows=plan.fold_rows[1:2]))
    push!(invalid,"incomplete K-fold coverage"=>incomplete)
    fragmented=merge(kfold_plan(data;k=2),(;group_by=:occasion))
    push!(invalid,"split grouping unit"=>fragmented)
    for (name,bad) in invalid
        @testset "$name" begin
            @test_throws ArgumentError B._check_kfold_refit_plan_for_execution(data,bad)
        end
    end

    # Deliberately invalid sampling controls ensure a regression cannot start MCMC.
    # The specific partition error must precede validation of those controls.
    for call in (
            ()->kfold_refit(spec,leak;backend=:invalid_backend,ndraws=0),
            ()->kfold_refit_comparison("a"=>spec,"b"=>getdesign(spec);
                plan=leak,backend=:invalid_backend,ndraws=0))
        error=caught(call)
        @test error isa ArgumentError
        @test occursin("training and heldout observations overlap",sprint(showerror,error))
    end

    loo=loo_refit_plan(data;observations=[2,1],fold_ids=[:two,:one])
    @test B._check_loo_refit_plan_for_execution(data,loo).passed
    @test B._check_loo_refit_plan_for_execution(data,loo_refit_plan(data)).passed
    empty_plan=loo_refit_plan(data,(;criterion=:loo,n_observations=data.n,
        pointwise=(;pareto_k=fill(0.1,data.n))))
    empty_result=loo_refit(spec,empty_plan;backend=:invalid_backend,ndraws=0)
    @test empty_result.n_refits==0
    @test empty_result.warning===:no_refits_required
    bad_loo=deepcopy(loo);push!(bad_loo.fold_rows[2].training_observations,1)
    for call in (
            ()->loo_refit(spec,bad_loo;backend=:invalid_backend,ndraws=0),
            ()->loo_refit_comparison("a"=>spec,"b"=>getdesign(spec);
                plan=bad_loo,backend=:invalid_backend,ndraws=0))
        error=caught(call)
        @test error isa ArgumentError
        @test occursin("training and heldout observations overlap",sprint(showerror,error))
    end
    @test_throws ArgumentError B._check_loo_refit_plan_for_execution(data,
        change_row(loo,2;heldout_observations=[1,3]))
    @test_throws ArgumentError B._check_loo_refit_plan_for_execution(data,
        merge(loo,(;group_by=:occasion)))
    @test_throws ArgumentError B._check_loo_refit_plan_for_execution(data,
        merge(loo,(;heldout_observation_indices=[[1],[2]])))
    @test_throws ArgumentError B._check_loo_refit_plan_for_execution(data,
        change_row(loo,2;heldout_observations=[2],training_observations=setdiff(1:data.n,[2])))
    @test_throws ArgumentError B._check_loo_refit_plan_for_execution(data,
        merge(empty_plan,(;folds=[:unexpected])))
    for facet in (:person,:rater,:item)
        @test_throws ArgumentError B._check_kfold_refit_plan_for_execution(data,
            kfold_plan(data;k=2,group_by=facet))
    end

    training_rows=reverse(plan.fold_rows[1].training_observations)
    training_data=B._loo_refit_training_data(data,training_rows)
    q=Bool[1 0;1 0;0 1;0 1]
    for family in (:mfrm,:gmfrm,:mgmfrm)
        opts=family===:mgmfrm ? (;dimensions=2,q_matrix=q,dimension_labels=["Vocabulary","Grammar"]) :
            (;dimensions=1,dimension_labels=["Ability"],discrimination=family===:gmfrm ? :rater : :none)
        source=mfrm_spec(data;family,opts...);before=bytes(source)
        training=B._refit_training_spec(source,training_data)
        @test training.dimension_labels==source.dimension_labels
        @test training.family==source.family
        @test training.thresholds==source.thresholds
        @test training.discrimination==source.discrimination
        @test training.anchors==source.anchors
        @test training.data.category_levels==source.data.category_levels
        @test training.data.score==data.score[training_rows]
        @test bytes(source)==before
        if family===:mgmfrm
            @test training.q_matrix==source.q_matrix[[findfirst(==(id),source.data.item_levels)
                for id in training.data.item_levels],:]
            default=mfrm_spec(training_data;family,dimensions=2,q_matrix=training.q_matrix)
            target=B._mgmfrm_guarded_local_fit_logdensity(getdesign(training;preview=true))
            reference=B._mgmfrm_guarded_local_fit_logdensity(getdesign(default;preview=true))
            x=initial_params(target)
            for shift in (0.0,0.1,-0.2)
                @test B._source_fixture_logposterior(target,x.+shift)==
                    B._source_fixture_logposterior(reference,x.+shift)
            end
        end
        training.dimension_labels[1]="Changed"
        @test bytes(source)==before
    end
end
end
