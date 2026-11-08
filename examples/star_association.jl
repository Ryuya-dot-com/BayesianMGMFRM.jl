module StarAssociationExample

using BayesianMGMFRM
const E = BayesianMGMFRM.Experimental

"Prepare a complete artificial example without fitting or generating ratings."
function inputs()
    criterion_specs = [
        (; criterion = "overall", role = :root, levels = collect(1:5)),
        (; criterion = "accuracy", role = :branch, levels = collect(1:4)),
        (; criterion = "pass_flag", role = :branch, levels = [0, 1]),
    ]
    # Teaching values, not recommended scientific defaults.
    prior = E.StarAssociation.PriorConfig(
        entity_log_sd_mean = log(0.8), rater_log_sd_mean = log(0.5),
        log_sd_sd = 0.5, entity_lkj_eta = 2.0, rater_lkj_eta = 2.0,
        mu_sd = 1.5, step_sd = 0.8, step_spacing = 0.6, phi_sd = 0.5)
    rows = NamedTuple[]
    for p in 1:4, r in 1:3
        scores = (1 + mod(p + r, 5), 1 + mod(2p + r, 4), mod(p + r, 2))
        for (c, score) in zip(criterion_specs, scores)
            push!(rows, (; observation_id = "p$(p)-r$(r)-$(c.criterion)",
                rating_event_id = "p$(p)-r$(r)", entity = "p$p", rater = "r$r",
                criterion = c.criterion, score))
        end
    end
    spec = E.joint_rating_spec(rows; criteria = criterion_specs, prior,
        association = :star, root_criterion = "overall")
    return (; rows, criterion_specs, prior, spec)
end

"Summarize an existing result; retain qualification warnings in every report."
function result(fitted)
    return (; gate = qualify(fitted), posterior = posterior_summary(fitted),
        entities = facet_summary(fitted; facet = :entity),
        difference = contrast(fitted; facet = :entity, criterion = "overall", left = "p1", right = "p2"),
        reliability = reliability(fitted; facet = :entity, criterion = "overall"),
        ranks = ranking(fitted; criterion = "overall", top_k = 3),
        decisions = classification(fitted; criterion = "overall", cutoff = 0.0),
        criteria = criteria(fitted))
end

end
