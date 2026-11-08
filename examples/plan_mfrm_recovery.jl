module MFRMRecoveryExample

using BayesianMGMFRM, SHA
const P = BayesianMGMFRM.Experimental.RecoveryPlanning

"""
    provenance(; manifest, project=Base.active_project())

Record the installed package's src tree and the chosen environment files.
`manifest` must be the Manifest.toml or version-specific manifest actually used
by that project. The source hash covers sorted relative paths and file SHA-256s
under src, not the entire distribution. This reads files only; it does not prove
which source/environment a later worker actually used.
"""
function provenance(; manifest, project=Base.active_project())
    project === nothing && throw(ArgumentError("activate a project first"))
    root = joinpath(pkgdir(BayesianMGMFRM), "src")
    files = sort([relpath(joinpath(dir, name), root)
        for (dir, _, names) in walkdir(root) for name in names])
    digest(path) = bytes2hex(sha256(read(path)))
    listing = join((join(splitpath(path), "/") * " " * digest(joinpath(root,path))
        for path in files), "\n")
    (; source_sha256=bytes2hex(sha256(listing)),
        source_scope="Sorted src-relative paths and SHA-256s, joined with LF; not the full distribution",
        project_sha256=digest(project), manifest_sha256=digest(manifest),
        julia_version=string(VERSION), rng_algorithm="Random.MersenneTwister")
end

"""
    example_plan(; allocation=:distributed, provenance)

Prepare a teaching plan with 12 people, three raters, four items and 72 ratings.
`:concentrated` shares all items for three people across all raters;
`:distributed` shares all items for six people with a second rater.
Both assign 24 ratings per rater. One dataset per allocation demonstrates a
workflow, not a design comparison. Truths, priors and MCSE limits are examples,
not recommended study defaults. No scores, random draws or fits are produced.
"""
function example_plan(; allocation=:distributed, provenance)
    allocation in (:concentrated,:distributed) ||
        throw(ArgumentError("allocation must be :concentrated or :distributed"))
    levels = (;person=["P$p" for p in 1:12], rater=["R$r" for r in 1:3],
        item=["I$i" for i in 1:4])
    rows = [(;person="P$p", rater="R$(mod1(p,3))", item="I$i")
        for p in 1:12 for i in 1:4]
    for p in 1:(allocation === :concentrated ? 3 : 6), i in 1:4
        extra = allocation === :concentrated ? filter(!=(mod1(p,3)),1:3) : [mod1(p+1,3)]
        append!(rows, [(;person="P$p", rater="R$r", item="I$i") for r in extra])
    end
    truth = Dict("person[P$p]"=>-1.1+.2*(p-1) for p in 1:12)
    merge!(truth, Dict("rater[R1]"=>0., "rater[R2]"=>.25, "rater[R3]"=>-.25,
        "item[I1]"=>0., "item[I2]"=>-.2, "item[I3]"=>.2, "item[I4]"=>.5))
    for i in 1:4, (k, step) in enumerate((-.6+.05*i, .1, .5-.05*i))
        truth["step[item=I$i,$k]"] = step
    end
    index = allocation === :concentrated ? 1 : 2
    P.prepare(rows; levels, category_levels=0:3, truth,
        prior=MFRMPrior(person_sd=1.5,rater_sd=1.,item_sd=1.,step_sd=1.),
        jobs=[(;dataset_id="$(allocation)-001",response_seed=2026101400+2index-1,
            fit_seed=2026101400+2index)],
        parameters=["rater[R2]"],interval=.90,
        sampler=(;backend=:advancedhmc,algorithm=:nuts,ndraws=1000,warmup=1000,
            chains=4,step_size=.05,init_jitter=.1,target_accept=.9,max_depth=10,
            max_energy_error=1000.,metric=:diagonal,ad_backend=:ForwardDiff,
            gradient_backend=:ad),provenance,
        precision=Dict("rater[R2]"=>(;mean_mcse_max=.01,endpoint_mcse_max=.02)))
end

end
