\name{plot.mgmfrm_gtheory_fit}
\alias{plot.mgmfrm_gtheory_fit}
\alias{print.mgmfrm_gtheory_fit}
\alias{summary.mgmfrm_gtheory_fit}
\alias{print.summary.mgmfrm_gtheory_fit}
\alias{coef.mgmfrm_gtheory_fit}
\alias{vcov.mgmfrm_gtheory_fit}
\title{Inspect and plot a saved G-theory analysis}
\usage{
\method{plot}{mgmfrm_gtheory_fit}(x,
  type = c("variance", "covariance", "dstudy"), score = "composite",
  metric = c("Phi", "G", "relative_sem", "absolute_sem"),
  counts = x$counts, weights = x$weights, interval = x$interval,
  interval_method = c("delta", "exact", "mean_square_region"), ...)
\method{print}{mgmfrm_gtheory_fit}(x, ...)
\method{summary}{mgmfrm_gtheory_fit}(object, ...)
\method{coef}{mgmfrm_gtheory_fit}(object, ...)
\method{vcov}{mgmfrm_gtheory_fit}(object, ...)
}
\arguments{
\item{x, object}{A G-theory result from \code{fit_mgmfrm()}.}
\item{type}{Variance components, signed covariances, or stored D-study scenarios.}
\item{score}{A score-column name or \code{"composite"}.}
\item{metric}{D-study coefficient or measurement error.}
\item{counts}{Named facet-count grids for a D-study plot; defaults to the stored grid. New plans do not require fitting or Julia.}
\item{weights}{Composite weights in score-column order for a D-study plot.}
\item{interval}{Pointwise confidence level for a D-study plot.}
\item{interval_method}{\code{"delta"} for asymptotic intervals; \code{"exact"} for G or relative SEM in a complete balanced one-facet Gaussian design; \code{"mean_square_region"} for all four metrics in complete balanced one/two-facet crossed or nested Gaussian designs. Weights must be prespecified. Region projections cover future plans and metrics jointly for one fixed score/composite, not different scores jointly, and can be wide.}
\item{...}{Additional graphical arguments; unused by the other methods.}
}
\description{Use stored estimates and pointwise confidence intervals without
starting Julia or fitting another model. A counts grid can be supplied when
plotting or when fitting. Covariance component boundaries retain point
estimates but suppress asymptotic intervals. Exact confidence sets use saved
Gaussian mean squares and can remain available at covariance boundaries;
empty sets are identified in the caption and omitted from interval bars.}
\value{Plot and print return the input invisibly. Summary returns stored
components, D studies and diagnostics. Coef returns a named estimate vector;
vcov returns its approximate sampling covariance, or NA at boundaries.}
