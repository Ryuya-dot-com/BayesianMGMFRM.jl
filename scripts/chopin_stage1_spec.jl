module ChopinStage1Spec

using JSON3, SHA
import BayesianMGMFRM as B

"Load the audited raw-score input and compile the existing one-dimensional path; never fit."
function prepare(directory::AbstractString)
    manifest = JSON3.read(read(joinpath(directory,"manifest.json"),String))
    manifest.schema == "bayesianmgmfrm.chopin_stage1_input.v1" ||
        throw(ArgumentError("unsupported input schema"))
    collect(manifest.category_levels) == collect(1:25) ||
        throw(ArgumentError("the declared score scale must remain 1:25"))
    for name in ("ratings.json","cells.json","performances.json","judges.json","stage1-layout.txt")
        bytes2hex(sha256(read(joinpath(directory,name)))) == manifest.files[Symbol(name)] ||
            throw(ArgumentError("input digest mismatch: $name"))
    end
    rows = JSON3.read(read(joinpath(directory,"ratings.json"),String))
    length(rows) == 1395 || throw(ArgumentError("expected 1395 raw scores"))
    table = (;person=String[r.person for r in rows],rater=String[r.rater for r in rows],
        item=String[r.item for r in rows],score=Int[r.score for r in rows],
        observation_id=String[r.observation_id for r in rows])
    length(unique(table.observation_id)) == length(rows) || throw(ArgumentError("duplicate observation IDs"))
    data = B.FacetData(table;person=:person,rater=:rater,item=:item,score=:score,
        response_id=:observation_id,category_levels=1:25)
    data.rater_levels == ["J"*lpad(r,2,'0') for r in 1:17] ||
        throw(ArgumentError("unexpected judge order"))
    data.person_levels == ["2025-S1-C"*lpad(p,3,'0') for p in 1:84] ||
        throw(ArgumentError("unexpected performance order"))
    data.item_levels == ["stage1_overall"] || throw(ArgumentError("unexpected criterion"))
    report = B.validate_design(data)
    spec = B.mfrm_spec(data;family=:mfrm,dimensions=1,discrimination=:none,
        thresholds=:partial_credit,validation_report=report)
    design = B.getdesign(spec)
    # Explicit engineering candidate, not an accepted scientific prior choice.
    prior = B.MFRMPrior(;person_sd=1.5,rater_sd=1.,item_sd=1.,step_sd=1.)
    return (;data,spec,design,prior,report,manifest,observation_ids=table.observation_id)
end

function write_report(input, output)
    ispath(output) && throw(ArgumentError("report already exists"))
    x = prepare(input)
    B._write_json_record(output,(;
        schema="bayesianmgmfrm.chopin_stage1_spec.v1",posterior_fitted=false,
        input_manifest_sha256=bytes2hex(sha256(read(joinpath(input,"manifest.json")))),
        adapter_sha256=bytes2hex(sha256(read(@__FILE__))),julia_version=string(VERSION),
        observations=x.data.n,performances=length(x.data.person_levels),
        judges=length(x.data.rater_levels),category_levels=x.data.category_levels,
        parameter_count=length(x.design.parameter_names),
        parameter_names=x.design.parameter_names,constraints=B.constraint_table(x.design),
        validation_passed=x.report.passed,
        issues=[(;code=i.code,severity=i.severity,message=i.message) for i in x.report.issues],
        engineering_prior=(;person_sd=1.5,rater_sd=1.,item_sd=1.,step_sd=1.),
        prior_status="not scientifically accepted; review anchor dependence and asymmetric last-step variance before fitting",
        prediction_target="existing stage-1 performances and judges; no imputation of recusals or unknown-level integration"))
    return x
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("usage: julia --project=. scripts/chopin_stage1_spec.jl INPUT_DIRECTORY NEW_REPORT.json")
    ChopinStage1Spec.write_report(ARGS...)
end
