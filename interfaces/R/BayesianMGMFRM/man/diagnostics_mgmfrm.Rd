\name{diagnostics_mgmfrm}
\alias{diagnostics_mgmfrm}
\title{Extract fit statistics, reliability, sampler, and qualification diagnostics}
\usage{
diagnostics_mgmfrm(object,
  type = c("fit_statistics", "reliability", "sampler", "qualification",
    "validation", "prior", "residual_correlation",
    "weighted_sufficient_score", "fair_average",
    "pair_bias", "classification", "ranking"),
  facet = NULL, counts = NULL, weights = NULL, interval = NULL,
  interval_method = NULL, reference_plan = NULL, threshold = NULL,
  comparisons = NULL, shared_effects = NULL,
  quadrature_orders = c(61L, 121L), quadrature_tolerance = 1e-7,
  interaction_effects = NULL,
  baseline = c("sample_mean", "zero_origin"), step_group = NULL,
  pair = NULL, min_obs = 1L,
  cutoff = NULL, pass_probability = 0.5,
  direction = c("higher", "lower"), top_k = NULL,
  dimension = NULL, parameters = NULL,
  location = c("parameter", "linked"))
}
\arguments{
\item{object}{A fitted \code{mgmfrm_r_fit} or \code{mgmfrm_gtheory_fit} object.}
\item{type}{Diagnostic table to retrieve: \code{"fit_statistics"} (Bayesian posterior-integrated vs. plug-in Infit/Outfit or frequentist MNSQ/ZSTD plus marginal Fair-M/Fair-Z), \code{"reliability"} (Bayesian finite-cohort posterior reliability and MCSE, or frequentist separation summaries), \code{"sampler"} (MCMC diagnostics), \code{"qualification"} (numerical qualification summary), \code{"validation"} (pre-fit connectedness, separation, thin-bridge, and issue diagnostics in original ID labels), \code{"prior"} (stored Bayesian prior summary including scale priors and implied pairwise contrast SDs), \code{"residual_correlation"} (posterior-integrated and plug-in Yen's Q3 / mean-adjusted Q3* criterion-pair residual correlations and posterior predictive p-values on 1D isometric Bayesian MFRM fits), \code{"weighted_sufficient_score"} (slope-weighted person sufficient scores on GMFRM and MGMFRM fits), \code{"fair_average"} (common-plan person expected scores when \code{reference_plan} is supplied, or FACETS-style marginal Fair-M / Fair-Z when \code{facet} is supplied), \code{"pair_bias"} (FACETS Table-14 cell-level residual bias screen and jointly fitted interaction logits on 1D isometric fits), \code{"classification"} (cutoff attainment probabilities, individual decision error risk, and joint cohort error counts), or \code{"ranking"} (joint-draw midranks, empirical rank intervals, and tie-aware top-k inclusion bounds).}
\item{facet}{Optional facet name (such as \code{"rater"}, \code{"item"}, or \code{"person"}) when \code{type = "fit_statistics"}, marginal \code{type = "fair_average"} (without \code{reference_plan}), \code{type = "classification"}, or \code{type = "ranking"}; or optional integer dimension index when \code{type = "weighted_sufficient_score"}.}
\item{counts}{For G-theory reliability, a named list of positive integer facet-count grids. Recalculates future designs without Julia or fitting. Nested child counts are per parent.}
\item{weights}{For G-theory reliability, composite weights in score-column order; defaults to the stored weights.}
\item{interval}{Interval probability mass in \code{(0, 1)}. Defaults to the stored level for G-theory, \code{0.95} for \code{"fair_average"} and \code{"pair_bias"}, and \code{0.90} for \code{"classification"} and \code{"ranking"}.}
\item{shared_effects}{For shared-event MRCML, explicitly choose \code{"zero"} to set shared effects to zero, or \code{"marginal_new"} to average over new Gaussian events. Omit shared-event columns from the plan.}
\item{interaction_effects}{For structured interaction/DFF models, explicitly choose \code{"fitted"} to retain interactions or \code{"zero"} to zero them only for reporting. Ability estimates retain the original fitted model. Population-roster group/context membership is held per person and recorded in \code{held_contexts}; omit it from the reference plan.}
\item{quadrature_orders}{Two increasing integer orders for shared-effect Gaussian quadrature.}
\item{quadrature_tolerance}{Maximum permitted expected-score difference between the two rules; increase orders if exceeded. This is a numerical diagnostic, not an error bound.}
\item{reference_plan}{For common-plan \code{type = "fair_average"}, a data frame of known levels of every fitted non-shared facet role and optional positive \code{Weight} values. Weights are normalized reporting weights. Cells must share a category score scale.}
\item{threshold}{Optional finite expected-score threshold for common-plan \code{type = "fair_average"}. Returns the posterior probability of exceeding or equalling it and its MCSE.}
\item{comparisons}{Optional data frame with \code{left}, \code{right} person IDs and finite \code{margin} for common-plan \code{type = "fair_average"}; reports score differences and, for Bayesian or conditional empirical-Bayes scoring, the probability that left minus right exceeds the margin. JMLE reports Wald intervals without posterior probabilities.}
\item{interval_method}{For G-theory reliability, \code{"delta"}, \code{"exact"}, or \code{"mean_square_region"}. Exact F intervals for G and chi-square intervals for relative SEM require stored mean squares from a complete balanced one-facet Gaussian design and prespecified weights. The region method uses independent chi-square pivots for complete balanced one/two-facet crossed or nested Gaussian designs and covers G, Phi and both SEM metrics. Region projections protect future plans and metrics jointly for each fixed score/composite, not different scores jointly, and can be wide. Empty confidence sets are reported explicitly.}
\item{baseline}{For marginal \code{type = "fair_average"} (without \code{reference_plan}), \code{"sample_mean"} (FACETS Fair-M) or \code{"zero_origin"} (FACETS Fair-Z).}
\item{step_group}{Optional step-owner level (e.g., criterion ID) when computing marginal \code{type = "fair_average"} across a non-owner facet under mixed category supports.}
\item{pair}{Optional length-2 character vector of distinct roles (such as \code{c("rater", "item")} or \code{c("rater", "group")}) for \code{type = "pair_bias"}.}
\item{min_obs}{Minimum cell observation count (default \code{1L}) to include in \code{type = "pair_bias"}.}
\item{cutoff}{Required finite coordinate cutoff for \code{type = "classification"}.}
\item{pass_probability}{Posterior qualification probability threshold strictly in \code{(0, 1)} (default \code{0.5}) required to classify a member as \code{"pass"} in \code{type = "classification"}.}
\item{direction}{Ordering direction \code{"higher"} (largest value is rank 1, default) or \code{"lower"} (smallest value is rank 1) for \code{type = "ranking"}.}
\item{top_k}{Optional integer in \code{1..N} for \code{type = "ranking"}; reports exact tie-aware lower and upper inclusion probabilities.}
\item{dimension}{Optional integer index or dimension label selecting a single ability dimension on multidimensional MGMFRM fits in \code{type = "classification"} or \code{type = "ranking"} (defaults to \code{1L}).}
\item{parameters}{Optional character vector of exact coordinate names or labels to evaluate in \code{type = "classification"} or \code{type = "ranking"}.}
\item{location}{For \code{type = "classification"} on 1D MFRM person abilities, \code{"parameter"} (default) compares stored person coordinates directly, while \code{"linked"} adds \code{population_mean} within each joint draw.}
}
\value{A data frame or structured list extracted from the stored fit record without requiring an active Julia session. Residual correlation reports include \code{unit_binding} and \code{n_units}, which identify and count the units used to pair criterion residuals.}
\description{Inspect stored psychometric and numerical diagnostics. For G-theory,
\code{fit_statistics} returns covariance components, \code{reliability} returns
D-study rows, and \code{qualification} returns optimization diagnostics.
Supplying D-study options recalculates rows from saved components and their
joint uncertainty, preserving the original fit.}
\details{Bayesian finite-cohort reliability is a posterior functional with numerical
MCSE. Its compatibility interval fields and additive population-reliability fields
are \code{NA}, with explicit status fields; a draw-wise proxy interval is not a
credible interval for this functional. Population/design reliability requires a
separate calculation. Stored tables from older fits retain their original values
and must be regenerated from the original joint draws using corrected reporting
code to apply this change.

Common-plan Fair Average supports additive Bayesian MFRM, shared-event
MRCML, scale-identified GMFRM/MGMFRM, and additive 1D JMLE/MMLE fits.
Bayesian scores propagate joint person and calibration uncertainty with MCSE;
JMLE uses the joint observed-information covariance in delta-method Wald intervals
and rejects posterior threshold probabilities. JMLE intervals can exceed the score
scale and are unavailable for unbounded extreme persons. Adjusted extreme-score
proxies are not handled. MMLE averages scores over the conditional empirical-Bayes
ability distribution on the fitted quadrature grid, holding calibration and fitted
population parameters fixed. Its intervals/probabilities omit their estimation
uncertainty and are not full Bayesian results. The separate \code{plugin_mean}
evaluates the score at the fitted ability/EAP or posterior-mean parameters.
All intervals concern expected scores, not future realized ratings. Fixed anchors
are treated as known. Whole-fit qualification remains applicable. Global and
single-facet steps are retained. Facet-by-facet, focal split-level or doubly
centered DFF, and facet-by-step interactions have explicit fitted/zero conditioning.
Zeroing interactions is not refitting, equalizing group abilities, or establishing
a causal bias correction. Shared-event conditioning is independent. Contexts must
be constant within a person; grouped population-mean estimation with unrestricted
person JMLE remains unidentified. LLTM/custom designs require other reference
definitions. Interaction fits store version 2 scoring metadata; older wrappers
must be updated to recompute scores. Shared-event and multidimensional models are
separate combinations, not an arbitrary composition. Reference plans can be changed
after RDS or portable handoff restoration without Julia. See
\code{plot.mgmfrm_fair_average}.}

\examples{
\dontrun{
setup_mgmfrm()
ratings <- read.csv(system.file("extdata", "ratings.csv", package = "BayesianMGMFRM"))
fit <- fit_mgmfrm(ratings, 0:3)
diagnostics_mgmfrm(fit, "qualification")
diagnostics_mgmfrm(fit, "reliability")
diagnostics_mgmfrm(fit, "fit_statistics", facet = "rater")
}
}
