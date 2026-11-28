\name{setup_mgmfrm}
\alias{setup_mgmfrm}
\title{Prepare the Julia environment and connect the R session}
\usage{
setup_mgmfrm(project = file.path(tools::R_user_dir("BayesianMGMFRM", "cache"),
  "julia-850721b6"), source_dir = NULL, julia = Sys.which("julia"))
}
\arguments{
\item{project}{Dedicated persistent directory for the Julia environment.}
\item{source_dir}{Optional local BayesianMGMFRM.jl source tree. Choose a separate project directory for each source.}
\item{julia}{Path to a Julia executable.}
}
\description{Install the pinned Julia development commit, instantiate and precompile dependencies, and open a local JuliaConnectoR connection. A local source tree can be selected explicitly. First-time setup can require network access. Use a fresh R session when switching projects.}
\value{The active project directory, invisibly.}
