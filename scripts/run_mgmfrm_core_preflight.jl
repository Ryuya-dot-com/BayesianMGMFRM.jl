# Sampler-free worker. The Python parent owns the finite roster and resource guard.
include(joinpath(@__DIR__,"mgmfrm_core_evaluation.jl"))
const E=MGMFRMCoreEvaluation
const P=E.P
contract_path,job_id=ARGS
c=P.readjson(contract_path)
c.mode=="input_preflight_only" && c.execution_allowed===false || error("Preparation only")
j=only(filter(j -> j.job_id==job_id,c.jobs))
for (name,expected) in pairs(c.source_sha256)
    P.digest(joinpath(pwd(),String(name)))==expected || error("Changed worker source")
end
recipe=c.plan
plan=E.evaluation_plan(String.(recipe.ids);mode=Symbol(recipe.mode),
    condition=recipe.condition,backend=Symbol(recipe.backend),generator_sha256=recipe.generator_sha256)
hashes=(;generation=String(j.hashes.generation),raw_truth=String(j.hashes.raw_truth),
    truth=String(j.hashes.truth),observed=String(j.hashes.observed))
input=E.bind_panel(plan,j.dataset_id;directory=j.directory,hashes)
split=j.fold===nothing ? nothing : E.bind_folds(plan,input;seed=j.split_seed)
check=E.input_preflight(plan,input;split,fold=j.fold)
out=joinpath(c.directory,job_id)
P.writejson(joinpath(out,"preflight.json"),check)
archive=joinpath(out,"prepared.jls")
ispath(archive) && error("Do not overwrite prepared evidence")
E.serialize(archive,(;plan,input,split,preflight=check))
P.writejson(joinpath(out,"result.json"),(;contract_sha256=P.digest(contract_path),job_id,
    dataset_id=j.dataset_id,fold=j.fold,status=check.passed ? :preflight_passed : :pre_fit_rejected,
    artifact_sha256=Dict(name=>P.digest(joinpath(out,name)) for name in ("preflight.json","prepared.jls")),
    new_sampler_runs=0,scientific_acceptance=false))
