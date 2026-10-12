using BayesianMGMFRM

"""
    matched_slope_workflow(spec; prior, output_dir, ndraws, warmup, chains, seed)

Fit fixed-one and estimated-positive item slopes on the same D1 item-step
specification and explicit normalized exchangeable prior. Rater consistency is
fixed at one in both models. Save and reopen each fit, retaining diagnostics.
`output_dir` must not already exist. Numerical controls are explicit: this
example does not select a scientific prior, sample budget or winning model.
Use the common K-fold refit API for heldout prediction on a declared split.
"""
function matched_slope_workflow(spec; prior, output_dir::AbstractString,
        ndraws::Int, warmup::Int, chains::Int, seed::Int)
    E=BayesianMGMFRM.Experimental
    policies=(:fixed_one,:estimated_positive)
    models=[E.slope_restriction(spec;item_slopes=p,rater_consistency=:fixed_one) for p in policies]
    foreach(m->E.surface_contract(m;prior),models)
    ispath(output_dir) && throw(ArgumentError("output_dir already exists"))
    nextseed=Base.checked_add(seed,1)
    mkpath(output_dir)
    fits=Pair[];paths=Pair[]
    for (i,model) in enumerate(models)
        fit=E.fit(model;prior,backend=:advancedhmc,ndraws,warmup,chains,
            seed=i==1 ? seed : nextseed)
        path=joinpath(output_dir,"$(policies[i]).jls")
        save_fit_cache(path,fit)
        restored=load_fit_cache(path)
        push!(fits,policies[i]=>restored);push!(paths,policies[i]=>path)
        println(policies[i], ": ", diagnostics(restored).summary.flag)
    end
    (;fits,paths,scientific_acceptance=:not_established)
end
