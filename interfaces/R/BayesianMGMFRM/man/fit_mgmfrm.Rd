\name{fit_mgmfrm}
\alias{fit_mgmfrm}
\alias{print.mgmfrm_r_fit}
\alias{summary.mgmfrm_r_fit}
\alias{print.summary.mgmfrm_r_fit}
\alias{coef.mgmfrm_r_fit}
\alias{vcov.mgmfrm_r_fit}
\alias{as_draws.mgmfrm_r_fit}
\alias{as_draws_array.mgmfrm_r_fit}
\title{Fit many-facet, generalized, and multidimensional Rasch models}
\usage{
fit_mgmfrm(data, category_levels = NULL, person = "person", item = "item",
  rater = "rater", score = "score", chains = 4L, warmup = 1000L,
  draws = 1000L, seed = 1L, variables = NULL,
  identification = c("isometric", "reference"), facets = NULL,
  steps = "auto", method = c("nuts", "mmle", "jmle", "ml", "reml"),
  model = c("mfrm", "gmfrm", "mgmfrm", "gtheory"), group = NULL, Q = NULL,
  scale_identification = c("geometric_mean_one", "anchor_item"),
  anchor_items = NULL, handoff_path = NULL,
  fixed_calibration = NULL, response_id = NULL, assessment_id = NULL,
  group_equal_sd = FALSE,
  group_sd_prior = c("lognormal", "half_normal", "half_t"),
  dff = NULL, dff_mode = c("doubly_centered", "split_rater"),
  dff_focal = NULL, slope = NULL,
  correlation = c("independent", "lkj"), lkj_eta = 2.0,
  ability_sd_prior = c("half_normal", "lognormal", "half_t"),
  location_identification = c("centered_items_free_mean",
    "zero_mean_population"), random_effects = NULL,
  random_sd_prior = c("half_normal", "half_t"), random_sd_scale = 1.0, nesting = NULL, counts = NULL, weights = NULL,
  interval = 0.95, logit_scale = NULL,
  rater_slope_scope = c("entire_linear_predictor", "ability_only"),
  aggregation = c("additive", "softmin"), softmin_kappa = NULL,
  cross_loading_average = NULL)

\method{print}{mgmfrm_r_fit}(x, ...)

\method{summary}{mgmfrm_r_fit}(object, level = 0.95, ...)

\method{coef}{mgmfrm_r_fit}(object, ...)

\method{vcov}{mgmfrm_r_fit}(object, ...)

\method{as_draws}{mgmfrm_r_fit}(x, ...)

\method{as_draws_array}{mgmfrm_r_fit}(x, ...)
}
\arguments{
  \item{nesting}{For G-theory, a named character vector mapping a child facet to its parent.}
  \item{counts}{For G-theory, a named list of positive integer counts or grids for every random facet, used to store D-study scenarios.}
  \item{weights}{For G-theory, unnormalized composite weights in score-column order; NULL uses the equal-score mean.}
  \item{interval}{Pointwise confidence level for G-theory's asymptotic delta intervals.}

\item{data}{A nonempty data frame of observed ratings, one row per observed score.}
\item{category_levels}{Either a single consecutive integer vector of ordered scores (including unobserved endpoints) or, for 1D isometric partial-credit MFRM (\code{model = "mfrm"}, \code{identification = "isometric"}, facet-owned \code{steps}), a named list mapping every observed level of the step-owning facet to its consecutive integer score sequence (e.g., \code{list(content = 0:3, delivery = 0:5)}).}
\item{person,item,rater,score}{Names of the person, item, rater, and integer score columns when \code{facets = NULL}. IDs can be character strings, factors, or finite numbers.}
\item{chains,warmup,draws}{Number of Markov chains, warmup iterations per chain, and retained draws per chain for \code{method = "nuts"}.}
\item{seed}{Nonnegative integer Julia sampler seed.}
\item{variables}{Optional character vector of physical parameter names in desired output order.}
\item{identification}{Parameterization and location-scale rule for 1D \code{model = "mfrm"}: \code{"isometric"} (default) places orthonormal Helmert zero-sum bases on facets and steps (marginal prior SD 1.0) with estimated \code{population_mean} (\code{Normal(0, 2.5)}) and \code{residual_sd[person]} (\code{HalfNormal(1.0)}); \code{"reference"} retains the legacy reference-level path (\code{item[1] = 0}, \code{rater[1] = 0}, fixed person SD 1.5).}
\item{facets}{Optional named character vector mapping measurement facet roles to column names in \code{data}, such as \code{c(item = "item", rater = "rater", task = "task")}. Defaults to \code{c(item = item, rater = rater)}.}
\item{steps}{Threshold ownership rule: \code{"auto"} (default; \code{"item"} when \code{length(category_levels) > 2} and \code{"item"} lies in \code{facets}, otherwise \code{"global"}), \code{"global"} (rating scale model), or any declared facet name in \code{facets} (partial credit thresholds owned by that facet).}
\item{method}{Estimation engine: \code{"nuts"} (default Bayesian No-U-Turn Sampler; the sole estimator supported for \code{model = "gmfrm"} and \code{model = "mgmfrm"}), or explicit 1D \code{model = "mfrm"} frequentist alternatives \code{"mmle"} (marginal maximum likelihood) and \code{"jmle"} (joint maximum likelihood).}
\item{model}{Measurement family: \code{"mfrm"} (default unit-slope many-facet Rasch model; supports \code{"nuts"}, \code{"mmle"}, and \code{"jmle"}), \code{"gmfrm"} (generalized MFRM with rater consistency and item discrimination; \code{method = "nuts"} only), or \code{"mgmfrm"} (scale-identified multidimensional generalized MFRM; \code{method = "nuts"} only).}
\item{group}{Optional column name in \code{data} assigning each person to a single group for multi-group 1D MFRM estimation.}
\item{Q}{Numeric item-by-dimension loading indicator matrix required when \code{model = "mgmfrm"}. Rows follow radix-sorted item labels unless \code{rownames(Q)} match \code{ids$item}.}
\item{scale_identification}{Multiplicative scale rule for \code{model = "mgmfrm"}: \code{"geometric_mean_one"} (default within-dimension zero-sum log loadings) or \code{"anchor_item"} (one fixed unit-loading item per dimension).}
\item{anchor_items}{Optional vector of length \code{ncol(Q)} naming the anchor item label or 1-based item index for each dimension when \code{scale_identification = "anchor_item"}.}
\item{handoff_path}{Optional file path where Julia writes a SHA-256 verified \code{PortableHandoff} JSON record during Bayesian estimation.}
\item{fixed_calibration}{Optional named list for 1D isometric \code{model = "mfrm"} specifying external hard locations (\code{facets = list(item = c(I1 = -0.5, ...))}) and/or unweighted subset mean or sum constraints (\code{groups = list(list(block = "rater", levels = c("R1", "R2"), mean = 0))}). Kept distinct from population \code{group}; standard errors and posterior intervals are conditional on the fixed values.}
\item{response_id,assessment_id}{Optional column names in \code{data} identifying shared responses (performances/essays) and rater-by-response assessment events for dependence-unit auditing. When omitted, event membership is reported as unknown.}
\item{group_equal_sd}{Logical; when \code{TRUE} with \code{group}, estimates a single homoscedastic ability SD shared across groups instead of group-specific SDs.}
\item{group_sd_prior}{Group ability SD prior family when \code{group} is supplied under \code{method = "nuts"}: \code{"lognormal"} (\code{LogNormal(0, 0.5)}, default), \code{"half_normal"} (\code{HalfNormal(1.0)}), or \code{"half_t"} (\code{HalfStudentT(df = 4, scale = 1.0)}).}
\item{dff}{Optional declared facet role name (e.g., \code{"rater"}) for differential facet functioning across \code{group} under \code{method = "nuts"} or \code{method = "mmle"}.}
\item{dff_mode}{Parameterization for \code{dff}: \code{"doubly_centered"} (orthonormal Kronecker--Helmert interaction across all levels) or \code{"split_rater"} (focal split-level contrast holding remaining anchor levels invariant).}
\item{dff_focal}{Observed level label(s) of \code{dff} to split across \code{group} when \code{dff_mode = "split_rater"}.}
\item{slope}{Optional multiplicative slope selector for \code{model = "gmfrm"} or \code{model = "mgmfrm"}: \code{"rater"}, \code{"item"}, or \code{"both"}. On \code{model = "gmfrm"}, passing \code{slope} selects the scale-identified isometric GMFRM kernel (supporting \code{steps = "global"}, \code{"item"}, or \code{"rater"}); leaving \code{slope = NULL} retains the legacy \code{gmfrm_item_sum_to_zero} kernel (\code{steps = "rater"}).}
\item{correlation}{Latent ability correlation structure for \code{model = "mgmfrm"}: \code{"independent"} (default identity correlation) or \code{"lkj"} (Cholesky-factor Fisher-z \code{LKJ(lkj_eta)} prior for 2D or 3D Q matrices).}
\item{lkj_eta}{Positive concentration hyperparameter \code{eta} for \code{correlation = "lkj"} (default \code{2.0}).}
\item{ability_sd_prior}{Prior family for dimension ability standard deviations on scale-identified \code{model = "gmfrm"} (with \code{slope}) and \code{model = "mgmfrm"}, or person residual SD in MFRM with \code{random_effects}: \code{"half_normal"} (\code{HalfNormal(1.0)}, default), \code{"lognormal"} (\code{LogNormal(0, 0.5)}), or \code{"half_t"} (\code{HalfStudentT(df = 4, scale = 1.0)}).}
\item{location_identification}{Location identification rule for scale-identified \code{model = "gmfrm"} (with \code{slope}) and \code{model = "mgmfrm"}: \code{"centered_items_free_mean"} (default isometric sum-to-zero pure items per dimension with estimated ability means) or \code{"zero_mean_population"} (zero ability means with unconstrained item locations).}
\item{random_effects}{Optional character vector naming existing facet roles to model as iid zero-mean Gaussian random effects (isometric MFRM with NUTS only). For a shared person-by-rater effect, create a unique ID for each person/rater pair across criteria, include it as a facet, and pass that role here. For person-by-testlet effects, create person/testlet pair IDs shared across the testlet items. Group effects, DFF on finite facets, and fixed calibration of finite facets can be combined. A shared facet cannot also own thresholds, fixed anchors, or fixed DFF interactions. Without groups, person residuals use \code{ability_sd_prior} and the free intercept has \code{Normal(0, 2.5)} prior. With groups, use \code{group_sd_prior} for group-specific ability scales. Without groups, person effects are deviations; add the joint \code{population_mean} draw for absolute ability on the centered-facet scale. Grouped person draws include the population mean. Infit/Outfit, reliability, and Q3 reports are available; residual checks condition on fitted effects.}
\item{random_sd_prior}{Shared-effect SD prior family: half Normal or half Student-t with 4 degrees of freedom. Both have density at zero but no point mass at zero.}
\item{random_sd_scale}{Positive scale for all named shared-effect SD priors; default 1.0.}
\item{logit_scale}{Optional logistic scaling constant (\code{1.0} or \code{1.7}) for scale-identified \code{model = "gmfrm"} (with \code{slope}) and \code{model = "mgmfrm"}. When \code{NULL}, defaults to \code{1.0} for GMFRM and \code{1.7} for MGMFRM.}
\item{rater_slope_scope}{Action scope of rater consistency on scale-identified generalized models: \code{"entire_linear_predictor"} (default; multiplies ability minus facet and step locations) or \code{"ability_only"} (multiplies latent ability only, leaving item, rater, and step locations on a common scale).}
\item{aggregation}{Cross-loading aggregation kernel for multidimensional \code{model = "mgmfrm"}: \code{"additive"} (default compensatory weighted sum) or \code{"softmin"} (smooth bottleneck noncompensatory kernel preserving balanced profiles while penalizing weak component dimensions).}
\item{softmin_kappa}{Optional positive bottleneck curvature parameter when \code{aggregation = "softmin"}: \code{NULL} (default; estimated under a \code{LogNormal(0, 1)} prior) or a fixed finite positive number.}
\item{cross_loading_average}{Optional logical flag on \code{model = "mgmfrm"} dividing cross-loaded item ability sums by the number of active dimensions (\code{FALSE} by default for \code{"additive"}; required \code{TRUE} for \code{"softmin"}).}
\item{x,object}{A fitted \code{mgmfrm_r_fit} object.}
\item{level}{Credible or confidence level between 0 and 1 for \code{summary()}.}
\item{...}{Additional arguments passed to or from methods.}
}
\value{An object of class \code{mgmfrm_r_fit} containing \code{draws} (\code{posterior::draws_array} for Bayesian fits or \code{NULL} for frequentist fits), \code{estimates} (offline summary data frame), \code{vcov} (posterior covariance matrix or frequentist constrained parameter covariance matrix), \code{ids} (radix-sorted original label dictionaries), \code{parameter_labels}, \code{fit_statistics}, \code{reliability}, \code{model}, \code{method}, \code{steps}, \code{identification}, and \code{metadata}. All S3 methods and post-estimation helpers operate offline after \code{saveRDS()} and \code{readRDS()}.}
\description{Fit Bayesian or frequentist many-facet Rasch, generalized many-facet Rasch, and scale-identified multidimensional generalized many-facet Rasch models with \code{BayesianMGMFRM.jl} after \code{\link{setup_mgmfrm}()}.}
\examples{
\dontrun{
setup_mgmfrm()
ratings <- read.csv(system.file("extdata", "ratings.csv", package = "BayesianMGMFRM"))
fit <- fit_mgmfrm(ratings, 0:3)
summary(fit)
contrast_mgmfrm(fit, facet = "rater", a = "R2", b = "R1")
diagnostics_mgmfrm(fit, type = "fit_statistics", facet = "rater")
}
}

\details{
With \code{model = "gtheory"}, supply one or more numeric column names in
\code{score}, named \code{facets}, and an explicit \code{method = "ml"} or
\code{"reml"}. Category levels and ordinal-model controls do not apply.
The return value is an \code{mgmfrm_gtheory_fit}, containing covariance component
estimates, numerical diagnostics, and requested D-study scenarios. Its
\code{coef()} returns component estimates and \code{vcov()} their approximate
sampling covariance (NA when unavailable). \code{plot()} supports variance,
signed covariance and D-study figures without Julia or re-estimation. Use
\code{saveRDS()} and \code{readRDS()} to retain the complete R result.
Intervals use observed-information delta approximations and are withheld at
covariance boundaries. Finite-sample coverage is not established; limits are
not clipped. These are confidence intervals, not posterior probabilities.
Use \code{diagnostics_mgmfrm(fit, "reliability", counts = ..., weights = ...)}
to evaluate new plans offline. For a complete balanced one-facet Gaussian
design, \code{interval_method = "exact"} supplies F intervals for G and
chi-square intervals for relative SEM using stored mean squares and
prespecified weights. It does not supply Phi or absolute SEM intervals.
With \code{interval_method = "mean_square_region"}, saved complete balanced
one/two-facet crossed or nested ANOVA mean squares provide region projections
for all four D-study metrics. These protect future designs jointly for a fixed
score/composite under independent normal effects, and may be wide.
}
