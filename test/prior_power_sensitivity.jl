module PriorPowerSensitivityTests
using Test, BayesianMGMFRM, Statistics, SHA
const B=BayesianMGMFRM
const fixture=Main.MeanProfileSensitivityTests.profile_fit

@testset "Scientific PCM powers, identity, guards and shared persistence" begin
    fit=fixture(ndraws=40)
    args=(;estimands=["Judge contrast"=>("rater[3]","rater[1]")],
        dataset_id="deterministic-contract-fixture",observation_ids=string.(1:fit.record.spec.data.n),
        scale=:unit_logit,max_mean_mcse=.01)
    powers=["same"=>(factors=["rater_severity"],alpha=1.),
            "wide"=>(factors=["rater_severity"],alpha=.25),
            "both"=>(factors=["rater_severity","item_step_residual"],alpha=.25)]
    factors=B.logprior(fit)
    t=B._normalized_mgmfrm_target(fit)
    # Independent full-block calculation, including the nonorthogonal-volume constant.
    for f in factors.factors, s in (1,40)
        expected=0.
        for ix in f.groups
            x=fit.record.run.draws[s,ix]-f.means[ix]
            n=length(ix)+1
            expected+=log(n)/2-length(ix)*log(f.sd*sqrt(2pi))-
                (sum(abs2,x)+sum(x)^2)/(2*f.sd^2)
        end
        @test f.log_density[s]≈expected atol=1e-12
        @test f.normalization===:included && !f.jacobian_powered
    end
    wide=fixture(ndraws=60,rater_sd=.8)
    both=fixture(ndraws=60,rater_sd=.8,step_sd=1.)
    rep=B.prior_sensitivity(fit;args...,powers,alternatives=["wide"=>wide,"both"=>both])
    same=rep.cases[1]
    @test same.reweighting.identity
    @test same.reweighting.pareto_k===nothing
    @test same.rows[1].mean_shift===0.
    @test same.rows[1].paired_shift_mcse===0.
    @test same.rows[1].baseline_mean_mcse!==nothing
    @test same.sampling_warning # Fake chains never become scientifically qualified.
    @test same.rows[1].precision_qualified===false
    @test rep.factor_record.chain_ids==fit.record.run.chain_ids
    @test rep.factor_record.iterations==fit.record.run.iterations
    @test rep.factor_record.target_identity==fit.record.target_identity
    @test rep.cases[2].alternative.source_sample_hash==wide.record.content_hash
    @test rep.cases[2].alternative.sampling_warning
    @test rep.cases[3].alternative.prior==both.record.prior
    direct=rep.cases[2].alternative.rows[1]
    @test direct.mean_shift==direct.mean-rep.cases[2].rows[1].baseline_mean
    @test direct.mean_shift_mcse_upper_bound==direct.mean_mcse+rep.cases[2].rows[1].baseline_mean_mcse
    raw=B.prior_sensitivity(fit;merge(args,(;scale=:model))...,powers)
    @test raw.cases[2].reweighting.weights==rep.cases[2].reweighting.weights
    @test rep.cases[1].rows[1].mean≈1.7*raw.cases[1].rows[1].mean
    @test rep.cases[1].rows[1].mean_mcse≈1.7*raw.cases[1].rows[1].mean_mcse
    @test rep.quantile_precision===:not_computed && rep.decision_precision===:not_computed
    for wrong in (fixture(rater_sd=.7),fixture(rater_sd=.8,step_sd=.6),fixture(rater_sd=.8,location=.1),fixture(K=3,rater_sd=.8))
        @test_throws ArgumentError B.prior_sensitivity(fit;args...,powers,alternatives=["wide"=>wrong])
    end
    for unsupported in (fixture(profiled=false),fixture(policy=:estimated_positive,profiled=false))
        @test_throws ArgumentError B.logprior(unsupported)
    end
    for alpha in (0.,-1.,NaN,Inf,true)
        @test_throws ArgumentError B.prior_sensitivity(fit;args...,powers=["bad"=>(factors=["rater_severity"],alpha)])
    end
    @test_throws ArgumentError B.prior_sensitivity(fit;args...,powers=["bad"=>(factors=["arbitrary"],alpha=.5)])
    @test_throws ArgumentError B.prior_sensitivity(fit;args...,powers,alternatives=["unplanned"=>wide])
    @test_throws ArgumentError B.prior_sensitivity(fit;args...,powers,r_eff=0.)
    @test_throws ArgumentError B.prior_sensitivity(fit;merge(args,(;scale=:unknown))...,powers)
    binary=fixture(K=2,ndraws=40)
    constant=B.prior_sensitivity(binary;args...,powers=["steps"=>(factors=["item_step_residual"],alpha=.25)])
    @test constant.cases[1].reweighting.identity # No free binary residual-step prior.
    empirical=B._power_weights(fill(2.,80),.25,2,.7)
    @test !empirical.identity && !empirical.reliable
    @test empirical.status===:empirical_constant_not_identity
    @test empirical.pareto_k==Inf
    record=deepcopy(fit.record)
    record.run.draws[:,t.blueprint.blocks[:rater_free]].=0.
    constantfit=Main.MeanProfileSensitivityTests.normalized_fixture(record;target=t)
    failed=B.prior_sensitivity(constantfit;args...,powers=powers[2:2],alternatives=["wide"=>wide])
    @test failed.cases[1].selected_source===:supplied_alternative
    @test failed.cases[1].reweighting.status===:empirical_constant_not_identity
    @test failed.cases[1].rows[1].mean_mcse===nothing
    @test failed.cases[1].rows[1].precision_qualified===false
    @test failed.cases[1].alternative.sampling_warning
    @test B._power_mean_mcse(ones(80),2)===nothing
    @test B._power_mean_mcse(ones(80),2;fixed=true)==0.
    # Structural constants retain exact means even when normalized weights round.
    fixed=(;label="fixed",values=fill(.3,80),fixed=true)
    exact=B._power_focal(fixed,merge(empirical,(;weights=fill(.013,80))),2,.01,true)
    @test exact.mean===exact.baseline_mean && exact.mean_shift===0.
    mktempdir() do dir
        p=joinpath(dir,"power.json")
        saved=B.save_report(p,rep;return_receipt=true)
        restored=B.load_report(p;expected_sha256=saved.sha256)
        @test restored.schema==rep.schema
        @test restored.cases[2].alternative.source_sample_hash==wide.record.content_hash
        @test restored.cases[1].rows[1].mean==same.rows[1].mean
        @test restored.factor_record.chain_ids==fit.record.run.chain_ids
        @test restored.baseline.sampling_warning
        @test_throws ArgumentError B.load_report(p)
        @test_throws ArgumentError B.load_report(p;expected_sha256="0"^64)
        @test_throws ArgumentError B.load_report(p;expected_sha256=saved.sha256,verify_hash=false)
        @test_throws ArgumentError B.save_report(p,rep)
        @test_throws ArgumentError B.save_report(joinpath(dir,"bad.json"),merge(rep,(;new_fits=1)))
        badpath=joinpath(dir,"failed.json")
        badreceipt=B.save_report(badpath,failed;return_receipt=true)
        badrestored=B.load_report(badpath;expected_sha256=badreceipt.sha256)
        @test badrestored.cases[1].reweighting.pareto_k.nonfinite=="Inf"
        @test badrestored.cases[1].rows[1].mean_mcse===nothing
        @test badrestored.cases[1].selected_source=="supplied_alternative"
    end
end
end
