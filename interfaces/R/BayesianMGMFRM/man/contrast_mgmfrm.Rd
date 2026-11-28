\name{contrast_mgmfrm}
\alias{contrast_mgmfrm}
\title{Compute pairwise or weighted linear contrasts of facet parameters}
\usage{
contrast_mgmfrm(object, facet = "rater", a = NULL, b = NULL,
  weights = NULL, level = 0.95)
}
\arguments{
\item{object}{A fitted \code{mgmfrm_r_fit} object.}
\item{facet}{Name of the facet or parameter block (for example \code{"rater"}, \code{"item"}, or \code{"group"}).}
\item{a,b}{Focal level \code{a} and reference level \code{b} for a pairwise difference \code{a - b} using original user labels in \code{object$ids[[facet]]} or exact physical parameter names.}
\item{weights}{Optional named numeric vector of contrast weights keyed by original user labels in \code{object$ids[[facet]]} or exact physical parameter names. Supply either \code{a} and \code{b} or \code{weights}.}
\item{level}{Credible or confidence interval probability between 0 and 1 (default \code{0.95}).}
}
\value{A single-row data frame reporting the contrast label, point estimate, uncertainty (\code{sd} or full-covariance \code{se}), lower and upper interval bounds, and either posterior tail probability and MCMC diagnostics (for Bayesian fits) or \code{se_diagonal_only} and Wald \code{z} statistic (for frequentist fits).}
\description{Evaluate draw-by-draw posterior contrasts for Bayesian fits or full-covariance Wald contrasts (propagating off-diagonal constrained-subspace covariances) for frequentist fits.}
\examples{
\dontrun{
setup_mgmfrm()
ratings <- read.csv(system.file("extdata", "ratings.csv", package = "BayesianMGMFRM"))
fit <- fit_mgmfrm(ratings, 0:3)
contrast_mgmfrm(fit, facet = "rater", a = "R2", b = "R1")
contrast_mgmfrm(fit, facet = "rater", weights = c(R1 = -0.5, R2 = 1.0, R3 = -0.5))
}
}
