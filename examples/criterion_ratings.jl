# Builds the supplied specification; does not fit or simulate.
using BayesianMGMFRM, JSON3
using Distributions: Normal, LogNormal

ratings = JSON3.read(read(joinpath(pkgdir(BayesianMGMFRM),
    "examples", "data", "criterion_ratings.json"), String))
spec = mfrm_spec(ratings;
    person=:speaker, performance=:talk, score=:rating,
    facets=(presentation=:talk, assessor=:judge, rubric=:aspect),
    steps=:rubric,
    category_levels=Dict("content"=>0:1, "organization"=>1:4, "delivery"=>0:4),
    decompose=(rate=(between=:mean_rate, within=:rate_change),),
    predictors=(person=(mean_rate=Normal(0,.6),),
        assessor=(experience=Normal(0,.6),),
        response=(rate_change=(by=:rubric, prior=Normal(0,.6)),)),
    population=(person=LogNormal(log(.6),.45),
        presentation=LogNormal(log(.4),.45), assessor=LogNormal(log(.35),.45)),
    prior_sd=(facets=(rubric=.4,), step=.45), intercept=Normal(0,.8))
validate_design(spec)
