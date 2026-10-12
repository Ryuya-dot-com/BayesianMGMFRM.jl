# Artificial display inputs; never fitted posterior or recovery evidence.
function wright_histogram_fit(; npeople = 80, thresholds = :rating_scale,
        categories = 0:3, anchors = nothing)
    persons = ["P$p" for p in 1:npeople for i in 1:4 for r in 1:3]
    items = ["I$i" for p in 1:npeople for i in 1:4 for r in 1:3]
    raters = ["R$r" for p in 1:npeople for i in 1:4 for r in 1:3]
    scores = [categories[mod1(p + i + r, length(categories))] for p in 1:npeople for i in 1:4 for r in 1:3]
    data = FacetData((; person = persons, item = items, rater = raters, score = scores);
        person = :person, item = :item, rater = :rater, score = :score, category_levels = categories)
    options = anchors === nothing ? (;) : (; anchors)
    fit = reporting_fit(:mfrm; data, thresholds, chains = 2, ndraws = 20,
        amplitude = 0.18, options...)
    for (p, column) in enumerate(fit.design.blocks[:person])
        fit.draws[:, column] .+= 0.5 * log((p - 0.5) / (npeople - p + 0.5))
    end
    for (column, shift) in zip(fit.design.blocks[:item], [-1.0, 0.4, 1.2])
        fit.draws[:, column] .+= shift
    end
    for (column, shift) in zip(fit.design.blocks[:rater], [-0.35, 0.55])
        fit.draws[:, column] .+= shift
    end
    for (k, column) in enumerate(fit.design.blocks[:thresholds])
        fit.draws[:, column] .+= isodd(k) ? -0.6 : 0.0
    end
    fit.log_posterior .= [logposterior(fit.design, row) for row in eachrow(fit.draws)]
    for d in eachindex(fit.sampler_stats)
        fit.sampler_stats[d] = merge(fit.sampler_stats[d], (; log_density = fit.log_posterior[d]))
    end
    return fit
end
