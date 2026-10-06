# Standalone, sampler-free audit against the saved fixed-facet inputs.
using Test, Random, Serialization, JSON3
include(joinpath(@__DIR__,"../scripts/mgmfrm_foundation_prediction.jl"))
const C=MGMFRMFoundationPrediction
const B=C.B
const E=C.E
length(ARGS)==2 || error("usage: mgmfrm_foundation_prediction.jl ASSESSMENT_ROOT NEW_RECEIPT.json")
root,output=ARGS
ispath(output) && error("Never overwrite a receipt")
seed=20261006070001
inputs=[joinpath(root,"inputs","B01-$condition.json") for condition in ("R0","R1")]
panels=[C.prepare(path,C.F.digest(path);split_seed=seed) for path in inputs]
metadata(c)=(;spec=c.spec,prior=c.binding.prior,target_identity=c.binding.target_identity)
records=NamedTuple[]

@testset "Normalized-C training targets and heldout identities" begin
    @test panels[1].binding.folds==panels[2].binding.folds
    for panel in panels, sd in (.25,.5,1.), fold in 1:5
        c=C.fold_context(panel,fold,sd)
        full=B._normalized_mgmfrm_target(panel.p.spec,c.prior)
        @test c.binding.target_identity!=B._mgmfrm_normalized_prior_identity(full)
        @test B._mgmfrm_normalized_prior_identity(C.check_target(c,metadata(c)))==c.binding.target_identity
        @test c.spec.data.n==1000 && c.score_design.spec.data.n==250
        @test c.spec.data.person_levels==panel.p.spec.data.person_levels
        @test c.spec.data.item_levels==panel.p.spec.data.item_levels
        @test c.spec.data.rater_levels==panel.p.spec.data.rater_levels
        @test c.score_design.parameter_names==c.target.base.design.parameter_names
        @test c.spec.q_matrix==C.F.Q
        # At fixed coordinates, deleting heldout likelihood terms is the entire target change.
        for raw in (Float64.(panel.p.x.raw_truth),zeros(128),.3sin.(1:128))
            direct=permutedims(B._mgmfrm_source_constrained_params_from_unconstrained(c.target.base.design,raw))
            logs=E.mean_log_probabilities(c.score_design,direct)
            expected=sum(logs[n,c.score_design.spec.data.category[n]] for n in 1:250)
            @test B.LogDensityProblems.logdensity(full,raw)-B.LogDensityProblems.logdensity(c.target,raw)≈expected atol=1e-9
            location=B._MGMFRMNormalizedLocationLogDensity(c.target)
            coordinates=B._mgmfrm_location_from_raw(location,raw)
            @test B._mgmfrm_location_to_raw(location,coordinates)≈raw atol=1e-13
            @test B.LogDensityProblems.logdensity(location,coordinates)≈B.LogDensityProblems.logdensity(c.target,raw) atol=1e-9
        end
        push!(records,(;condition=panel.p.x.condition,c.binding...))
    end
    @test length(unique(r.target_identity for r in records))==30
    @test sum(sum(C.fold_context(panels[1],f,.5).binding.weights) for f in 1:5)≈1.
end
flush(stdout)

@testset "Reject leakage, wrong priors/rows and changed bindings" begin
    panel=panels[1];c=C.fold_context(panel,1,.5)
    saved=open(deserialize,joinpath(root,"attempts","B01-R0-050","samples.jls"))
    @test_throws ArgumentError C.check_fit(c,saved;seed=saved.run.controls.rng.seed)
    @test_throws ArgumentError C.check_target(c,merge(metadata(c),(;spec=panel.p.spec)))
    @test_throws ArgumentError C.check_target(c,metadata(C.fold_context(panel,2,.5)))
    @test_throws ArgumentError C.check_target(c,metadata(C.fold_context(panel,1,.25)))
    @test_throws ArgumentError C.check_target(c,merge(metadata(c),(;
        prior=C.fold_context(panel,1,.25).binding.prior)))
    @test_throws ArgumentError C.prepare(inputs[1],repeat("0",64);split_seed=seed)
    @test_throws ArgumentError C.prepare(inputs[1],C.F.digest(inputs[1]);split_seed=true)
    @test_throws ArgumentError C.fold_context(panel,true,.5)
    @test_throws ArgumentError C.fold_context(panel,1,true)
    @test_throws ArgumentError C.fold_context(panel,6,.5)
    @test_throws ArgumentError C.fold_context(panel,1,.75)
    changed=deepcopy(panel);changed.binding.folds.fold_rows[1].training_observations[1]=0
    @test_throws ArgumentError C.fold_context(changed,1,.5)
    changed=deepcopy(panel);changed.p.spec.data.score[1]=mod1(changed.p.spec.data.score[1]+1,4)
    @test_throws ArgumentError C.fold_context(changed,1,.5)
    # Facet presence alone is insufficient: remove one person's D1 support.
    data=panel.p.spec.data
    absent=findall(n->data.person[n]==1 && C.F.Q[data.item[n],1],1:1250)
    other=shuffle(MersenneTwister(20261006070003),setdiff(collect(1:1250),absent))
    heldout=[sort([absent;other[1:240]]);other[241:end]]
    rows=[merge(panel.binding.folds.fold_rows[f],(;
        heldout_observations=sort(heldout[(250*f-249):(250*f)]),
        training_observations=sort(setdiff(1:1250,heldout[(250*f-249):(250*f)])))) for f in 1:5]
    bad=merge(panel.binding.folds,(;fold_rows=rows))
    @test B.kfold_plan_diagnostics(data,bad;facets=:all).passed
    @test_throws "Missing training person/dimension support" C.check_split(data,bad)
end
flush(stdout)

@testset "Heldout outcomes cannot change training target; training outcomes can" begin
    panel=panels[1];c=C.fold_context(panel,1,.5)
    mktempdir() do dir
        for (position,should_match) in ((first(c.binding.heldout_observations),true),
                (first(c.binding.training_observations),false))
            payload=JSON3.read(read(inputs[1],String),Dict{String,Any})
            payload["observations"][position]["score"]=mod1(payload["observations"][position]["score"]+1,4)
            file=joinpath(dir,"changed-$position.json");write(file,JSON3.write(payload))
            p=C.prepare(file,C.F.digest(file);split_seed=seed)
            other=C.fold_context(p,1,.5)
            @test (other.binding.target_identity==c.binding.target_identity)==should_match
            @test other.binding.panel_identity!=c.binding.panel_identity
            if should_match
                @test other.binding.score_fingerprint!=c.binding.score_fingerprint
            end
        end
    end
end
flush(stdout)

@testset "Log-domain fold scores and MCSE keep global weights and draw covariance" begin
    panel=panels[1];c=C.fold_context(panel,1,.5)
    rng=MersenneTwister(20261006070002)
    raw=.1randn(rng,4000,128)
    direct=reduce(vcat,[permutedims(B._mgmfrm_source_constrained_params_from_unconstrained(c.target.base.design,collect(r))) for r in eachrow(raw)])
    chains=repeat(1:4;inner=1000);iterations=repeat(1:1000;outer=4)
    scored=C.score_draws(c,direct;chain_ids=chains,iterations)
    # Materialize this one small fold only as an independent traversal check.
    probabilities=B._mgmfrm_predictive_probabilities_direct(c.score_design,direct)
    expected=log.(dropdims(sum(probabilities;dims=1);dims=1)./4000)
    @test scored.log_probabilities≈expected atol=1e-12
    weights=c.binding.weights;cats=c.score_design.spec.data.category
    nll=first(scored.monte_carlo_error.rows)
    @test nll.estimate≈-sum(weights[n]*expected[n,cats[n]] for n in 1:250) atol=1e-12
    influence=[-sum(weights[n]*(probabilities[s,n,cats[n]]/exp(expected[n,cats[n]])-1) for n in 1:250) for s in 1:4000]
    mcse=only(B.posterior_mcse(reshape(influence,:,1);chains=4,parameter_names=["independent_nll"],probabilities=())).mean_mcse
    @test nll.mcse≈mcse rtol=1e-9
    @test scored.monte_carlo_error.n_prediction_draws==4000
    @test scored.monte_carlo_error.weighting===:global_equal_person_equal_dimension
    @test !scored.monte_carlo_error.resolution.bias_bound_available
    @test scored.monte_carlo_error.resolution.n_prediction_draws==4000
    @test_throws ArgumentError C.score_draws(c,direct;chain_ids=reverse(chains),iterations)
    changed=deepcopy(c);changed.binding.weights[1]*=2
    @test_throws ArgumentError C.score_draws(changed,direct;chain_ids=chains,iterations)
    changed=merge(c,(;score_design=C.fold_context(panel,2,.5).score_design))
    @test_throws ArgumentError C.score_draws(changed,direct;chain_ids=chains,iterations)
end

B._write_json_record(output,(;status=:passed,posterior_fits=0,independent_evaluation_credit=0,
    input_sha256=C.F.digest.(inputs),split_seed=seed,contexts=records,
    script_sha256=C.F.digest(joinpath(@__DIR__,"../scripts/mgmfrm_foundation_prediction.jl")),
    test_sha256=C.F.digest(@__FILE__),scientific_acceptance=false,
    scope=:binding_likelihood_partition_scoring_arithmetic_not_fitted_CV))
