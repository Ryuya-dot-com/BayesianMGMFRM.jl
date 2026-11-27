\name{handoff_mgmfrm}
\alias{handoff_mgmfrm}
\alias{read_handoff_mgmfrm}
\title{Write and reload portable JSON fit records}
\usage{
handoff_mgmfrm(object, path, return_receipt = FALSE)

read_handoff_mgmfrm(path, variables = NULL, expected_sha256 = NULL)
}
\arguments{
\item{object}{A fitted \code{mgmfrm_r_fit} object.}
\item{path}{Path to the JSON handoff file to write or read.}
\item{return_receipt}{Logical; if \code{TRUE}, return a list containing the normalized \code{path}, file \code{sha256}, embedded \code{payload_sha256}, and payload counts instead of the path alone.}
\item{variables}{Optional character vector of physical parameter names to subset when reading a handoff.}
\item{expected_sha256}{Optional 64-character hex SHA-256 digest (with or without a \code{"sha256:"} prefix) verified against the raw file on disk before parsing.}
}
\value{\code{handoff_mgmfrm()} returns the normalized file path invisibly (or a verification receipt list when \code{return_receipt = TRUE}). \code{read_handoff_mgmfrm()} verifies checksums, array dimensions, chain/iteration indices, and parameter identities before returning a reconstructed \code{mgmfrm_r_fit} object.}
\description{Export an \code{mgmfrm_r_fit} object to a portable JSON record or reconstruct an \code{mgmfrm_r_fit} object from either an R portable fit JSON file or a native Julia \code{PortableHandoff} JSON file.}
\examples{
\dontrun{
setup_mgmfrm()
ratings <- read.csv(system.file("extdata", "ratings.csv", package = "BayesianMGMFRM"))
fit <- fit_mgmfrm(ratings, 0:3)
tmp <- tempfile(fileext = ".json")
handoff_mgmfrm(fit, tmp)
reloaded <- read_handoff_mgmfrm(tmp)
summary(reloaded)
}
}
