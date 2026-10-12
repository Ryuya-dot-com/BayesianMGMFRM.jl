using BayesianMGMFRM, Test, Statistics, Serialization, SHA, TOML
const B = BayesianMGMFRM
include("common_prediction_fixtures.jl")
include("../examples/saved_model_comparison.jl")
const compare = B.compare_predictions
const extract = B.prediction_observations
ids(n) = ["rating-$i" for i in 1:n]
bytes(x) = (io=IOBuffer(); serialize(io,x); take!(io))
bundle(fit,n) = extract(fit; dataset_id="synthetic-api-check", observation_ids=ids(n), include_probabilities=false)

function common_prediction_comparison_checks(output=nothing)
started = time()
checks = @testset "Common prediction comparison candidate (no MCMC)" begin
    @info "Checking analytic scores, alignment, errors and legacy behavior"
    mfrm = reporting_fit(:mfrm; chains=2, ndraws=20, warmup=0)
    gmfrm = reporting_fit(:gmfrm; chains=2, ndraws=30, warmup=0)
    mgmfrm = reporting_fit(:mgmfrm; chains=2, ndraws=20, warmup=0)
    a = bundle(mfrm,6)
    # Constant log likelihood across draws gives analytically known WAIC/LOO.
    ll = log.([.3,.4,.2,.5,.6,.4])
    delta = [.05,-.02,.01,-.03,.02,.01]
    x = merge(a,(; pointwise_loglikelihood=repeat(ll';outer=(40,1))))
    y = merge(a,(; pointwise_loglikelihood=repeat((ll.+delta)';outer=(40,1))))
    for criterion in (:waic,:raw_loo,:hill_smoothed_loo)
        result = compare("base"=>x,"other"=>y; comparison_axis=:model,criterion,se_unit=:observation)
        @test result.schema == "bayesianmgmfrm.prediction_comparison.v1"
        @test result.rows[1].elpd ≈ sum(ll)
        @test result.rows[2].elpd_difference ≈ sum(delta) atol=1e-13
        @test result.rows[2].se_elpd_difference ≈ sqrt(6var(delta)) atol=1e-13
        @test result.rows[1].se_elpd_difference == 0
        @test result.rows[2].pointwise_difference ≈ delta atol=1e-13
        @test result.model_selection === :not_performed
        @test result.scientific_acceptance === :not_established
        @test result.reference_psis_validation === :not_established
        @test result.prediction_target === :training_rows_existing_levels
        @test result.conditioning === :joint_posterior_existing_levels
        @test result.rows[2].sampling_warning
        @test result.rows[2].status === :warning
    end
    grouped = compare("a"=>x,"b"=>y; comparison_axis=:model,se_unit=:person)
    @test grouped.rows[2].se_elpd_difference ≈ sqrt(2var([sum(delta[1:3]),sum(delta[4:6])])) atol=1e-13
    @test grouped.rows[2].n_uncertainty_units == 2
    default = compare("a"=>x,"b"=>y; comparison_axis=:model)
    @test ismissing(default.rows[2].se_elpd_difference)
    @test default.uncertainty.standard_error === :not_requested
    reversebase = compare("a"=>x,"b"=>y; comparison_axis=:model,baseline="b")
    @test [r.model for r in reversebase.rows] == ["a","b"]
    @test reversebase.rows[1].elpd_difference ≈ -sum(delta) atol=1e-13
    perm = [6,2,4,1,5,3]
    yp = merge(y,(; observation_ids=y.observation_ids[perm], observations=y.observations[perm],
        source_row_indices=y.source_row_indices[perm],pointwise_loglikelihood=y.pointwise_loglikelihood[:,perm]))
    @test isequal(compare("a"=>x,"b"=>yp; comparison_axis=:model), default)
    lone = B._prediction_difference_se([.2],[(;person="only")],:person)
    @test lone.status === :insufficient_units && ismissing(lone.value)

    for extra in ((;baseline="absent"),(;criterion=:psis_loo),(;criterion=:loo),
                  (;se_unit=:rater),(;dataset_id="redundant"),(;observation_ids=ids(6)))
        @test_throws ArgumentError compare("a"=>x,"b"=>y; comparison_axis=:model,extra...)
    end
    @test_throws ArgumentError compare("a"=>x,"b"=>y; comparison_axis=:implicit)
    @test_throws ArgumentError compare("a"=>x; comparison_axis=:model)
    @test_throws ArgumentError compare("a"=>x,"a"=>y; comparison_axis=:model)
    @test_throws ArgumentError compare(" "=>x,"b"=>y; comparison_axis=:model)
    @test_throws ArgumentError compare("a"=>mfrm,"b"=>y; comparison_axis=:model)
    @test_throws ArgumentError compare("a"=>mfrm,"b"=>gmfrm; comparison_axis=:model)
    for change in ((;dataset_id="other"),(;category_levels=[1,2,3]),
                   (;conditioning=:new_person),(;weighting=:equal_person),
                   (;training_binding="other"),(;prediction_target=:heldout),
                   (;observation_ids=fill("duplicate",6)),(;draw_indices=collect(40:-1:1)),
                   (;chain_ids=ones(Int,40)),(;iterations=ones(Int,40)),
                   (;pointwise_loglikelihood=fill(NaN,40,6)))
        @test_throws ArgumentError compare("a"=>x,"b"=>merge(y,change); comparison_axis=:model)
    end
    changed = deepcopy(y.observations)
    changed[1] = merge(changed[1],(;score=2))
    @test_throws ArgumentError compare("a"=>x,"b"=>merge(y,(;observations=changed)); comparison_axis=:model)
    forged = merge(y,(;observations=changed))
    @test_throws ArgumentError compare("a"=>forged,"b"=>forged; comparison_axis=:model)
    subset = extract(mfrm;dataset_id=a.dataset_id,observation_ids=ids(6),draw_indices=[1,2])
    @test_throws ArgumentError compare("a"=>a,"b"=>subset; comparison_axis=:model)
    badll = copy(x.pointwise_loglikelihood); badll[:,2] .= repeat([-8.,-.01];outer=20)
    warning = compare("a"=>x,"b"=>merge(x,(;pointwise_loglikelihood=badll)); comparison_axis=:model)
    @test warning.rows[2].criterion_warning !== :ok
    @test "rating-2" in warning.rows[2].problem_observation_ids
    @test warning.rows[2].status === :warning

    @test_throws ArgumentError compare("MFRM"=>mfrm,"MGMFRM"=>mgmfrm; comparison_axis=:model,
        dataset_id=a.dataset_id,observation_ids=ids(6))
    across = compare("MFRM"=>mfrm,"GMFRM"=>gmfrm,"MGMFRM"=>mgmfrm; comparison_axis=:dimensions,
        dataset_id=a.dataset_id,observation_ids=ids(6))
    @test [r.model_contract.dimensions for r in across.rows] == [1,1,2]
    @test [r.n_retained_draws for r in across.rows] == [40,60,40]
    @test across.rows[2].pointwise_elpd ≈ B.waic(pointwise_loglikelihood_matrix(gmfrm)).pointwise.elpd_waic
    legacy = compare_models("MFRM"=>mfrm,"GMFRM"=>gmfrm)
    @test legacy !== nothing
    @test_throws ArgumentError compare_models("MFRM"=>mfrm,"MGMFRM"=>mgmfrm)
    @test all(name->name ∉ names(B),(:prediction_observations,:prediction_criteria,:compare_predictions,:observation_alignment))
    @test B._root_api_contract() !== nothing

    @info "Checking normalized/correlated saved fits and public saved-model example"
    r = F.synthetic_record(F.target())
    normalized = normalized_fixture(r)
    correlated = B.Experimental.CorrelatedMGMFRMFit(r;expected_identity=r.target_identity)
    fits = ["MFRM"=>reporting_fit(:mfrm;data=r.spec.data,chains=2,ndraws=20,warmup=0),
            "GMFRM"=>reporting_fit(:gmfrm;data=r.spec.data,chains=2,ndraws=20,warmup=0),
            "MGMFRM"=>normalized,"correlated MGMFRM"=>correlated]
    before = bytes.(last.(fits))
    direct = compare(fits...; comparison_axis=:dimensions,dataset_id="shared",observation_ids=ids(r.spec.data.n))
    @test [row.model_contract.family for row in direct.rows] == [:mfrm,:gmfrm,:mgmfrm,:mgmfrm]
    @test direct.rows[3].source_hash_status === :validated
    @test direct.rows[4].model_contract.latent_correlation === :free_2d
    mktempdir() do dir
        caches = [name=>joinpath(dir,"model-$i.jls") for (i,(name,_)) in enumerate(fits)]
        for ((_,fit),(_,path)) in zip(fits,caches)
            save_fit_cache(path,fit)
        end
        hashes = [sha256(read(path)) for (_,path) in caches]
        restored = saved_model_comparison(caches...; comparison_axis=:dimensions,dataset_id="shared",observation_ids=ids(r.spec.data.n))
        @test isequal(direct,restored)
        @test hashes == [sha256(read(path)) for (_,path) in caches]
    end
    @test before == bytes.(last.(fits))

    @info "Checking fixed-coefficient fit variants and explicit Q/dimension axes"
    fixed = [prediction_fixed_fixture(k).fit for k in (:independent,:correlated,:exchangeable,:exchangeable_correlated)]
    for (i,fit) in enumerate(fixed)
        data = B.PredictionObservationAdapter._fit_data(fit)
        reference = reporting_fit(:mfrm;data,chains=2,ndraws=20,warmup=0)
        result = compare("one dimension"=>reference,"fixed Q"=>fit;comparison_axis=:dimensions,
            dataset_id="fixed-$i",observation_ids=ids(data.n))
        @test result.rows[2].model_contract.family === :mfrm
        @test result.rows[2].source_hash_status === :validated
        @test result.rows[2].n_retained_draws == 40
        @test all(isfinite,result.rows[2].pointwise_elpd)
    end
    mixed = prediction_fixed_fixture(:independent;mixed=true).fit
    n = B.PredictionObservationAdapter._fit_data(mixed).n
    @test_throws ArgumentError compare("pure"=>fixed[1],"mixed"=>mixed;comparison_axis=:model,dataset_id="Q",observation_ids=ids(n))
    qresult = compare("pure"=>fixed[1],"mixed"=>mixed;comparison_axis=:q_matrix,dataset_id="Q",observation_ids=ids(n))
    @test qresult.rows[1].model_contract.q_matrix != qresult.rows[2].model_contract.q_matrix
    fit3 = prediction_fixed_fixture(:independent;D=3).fit
    data3 = B.PredictionObservationAdapter._fit_data(fit3)
    ref3 = reporting_fit(:mfrm;data=data3,chains=2,ndraws=20,warmup=0)
    d3 = compare("D1"=>ref3,"D3"=>fit3;comparison_axis=:dimensions,dataset_id="D3",observation_ids=ids(data3.n))
    @test [row.model_contract.dimensions for row in d3.rows] == [1,3]
    @test_throws ArgumentError compare("D1"=>ref3,"D3"=>fit3;comparison_axis=:q_matrix,dataset_id="D3",observation_ids=ids(data3.n))

    @info "Checking native row labels with differently ordered fit inputs"
    table = (;person=[1,1,1,2,2,2],item=[1,1,2,1,2,2],rater=[1,2,1,1,2,1],score=[0,1,2,1,0,2])
    data(t) = FacetData(t;person=:person,item=:item,rater=:rater,score=:score,category_levels=0:2)
    original = reporting_fit(:mfrm;data=data(table),chains=2,ndraws=20,warmup=0,amplitude=0.)
    reordered = reporting_fit(:mfrm;data=data(map(v->v[perm],table)),chains=2,ndraws=20,warmup=0,amplitude=0.)
    keyed = compare("original"=>original,"reordered"=>reordered;comparison_axis=:model,dataset_id="permutation",
        observation_ids=Dict("original"=>ids(6),"reordered"=>ids(6)[perm]))
    @test keyed.rows[2].elpd_difference == 0
    @test_throws ArgumentError compare("a"=>original,"b"=>reordered;comparison_axis=:model,
        dataset_id="permutation",observation_ids=ids(6))
    @test_throws ArgumentError compare("a"=>original,"b"=>reordered;comparison_axis=:model,
        dataset_id="permutation",observation_ids=Dict("a"=>ids(6)))
end
counts = Test.get_test_counts(checks)
if output !== nothing
    open(output,"w") do io
        TOML.print(io,Dict("status"=>"passed","passed"=>counts.passes+counts.cumulative_passes,
            "seconds"=>time()-started,"new_posterior_fits"=>0,
            "candidate_source"=>pathof(B),"scope"=>"synthetic API/analytic score/saved-cache checks; not statistical acceptance"))
    end
end
return checks
end

if abspath(PROGRAM_FILE)==@__FILE__
    common_prediction_comparison_checks(isempty(ARGS) ? nothing : ARGS[1])
end
