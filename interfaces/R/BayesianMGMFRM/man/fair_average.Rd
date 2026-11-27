\name{plot.mgmfrm_fair_average}
\alias{plot.mgmfrm_fair_average}
\alias{print.mgmfrm_fair_average}
\title{Display Common-Plan Fair Average Scores}
\usage{
\method{plot}{mgmfrm_fair_average}(x, ...)
\method{print}{mgmfrm_fair_average}(x, ...)
}
\arguments{
\item{x}{A common-plan report returned by \code{diagnostics_mgmfrm}.}
\item{...}{Additional arguments to the underlying plot or data-frame print method.}
}
\description{Plot expected scores and method-specific intervals beside
observed averages. Full captions and numerical qualification are printed to the
console. These intervals concern expected scores, not future realized ratings.
Bayesian means use joint credible intervals; JMLE uses Wald intervals; MMLE uses
conditional empirical-Bayes intervals with calibration and population parameters
fixed. Printing shows score and requested contrast tables. Saved reports need no Julia
session or refitting.}
\value{The report, invisibly.}
