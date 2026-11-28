.gtheory_region <- function(object, weights, interval) {
  m <- object$report$anova_moments
  if (is.null(m)) stop("Mean-square regions require stored ANOVA mean squares from a complete balanced crossed or nested design.")
  terms <- object$report$components; K <- length(terms); C <- length(weights)
  if (length(m$df) != K || length(m$levels) != K || length(m$mean_squares) != K)
    stop("Invalid stored ANOVA dimensions.")
  ms <- vapply(m$mean_squares, function(x) drop(crossprod(weights, matrix(unlist(x), C, C) %*% weights)), numeric(1))
  unavailable <- function(status) list(vertices = matrix(numeric(), K, 0), status = status)
  if (any(!is.finite(ms) | ms <= 0)) return(unavailable("degenerate_mean_squares"))
  scale <- max(ms); tail <- -expm1(log(interval)/K)/2; df <- unlist(m$df)
  lo <- ms/scale*df/stats::qchisq(tail, df, lower.tail = FALSE)
  hi <- ms/scale*df/stats::qchisq(tail, df)
  tolerance <- 512*.Machine$double.eps*max(1, hi)
  if (any(!is.finite(c(lo, hi))) || any(hi <= lo) || min(lo) <= tolerance)
    return(unavailable("numeric_resolution"))
  factors <- lapply(terms, function(x) unlist(x$factors, use.names = FALSE))
  B <- do.call(rbind, lapply(factors, function(a) vapply(factors, function(b) all(a %in% b), logical(1))))*1
  constraints <- rbind(B, -B, -diag(K)); rhs <- c(hi, -lo, rep(0, K))
  choices <- utils::combn(3*K, K); vertices <- list(); worst <- 0
  for (i in seq_len(ncol(choices))) {
    active <- choices[, i]
    if (any((active[active <= K] + K) %in% active)) next
    M <- constraints[active, , drop = FALSE]
    if (abs(det(M)) <= .5) next
    x <- drop(solve(M, rhs[active]))
    if (all(is.finite(x)) && max(constraints %*% x - rhs) <= tolerance) {
      x <- pmax(x, 0); residual <- max(0, constraints %*% x - rhs)
      if (residual <= tolerance) { vertices[[length(vertices) + 1L]] <- x; worst <- max(worst, residual) }
    }
  }
  if (!length(vertices)) return(unavailable("empty_confidence_set"))
  V <- sweep(do.call(cbind, vertices)*scale, 1, object$report$n_observations/unlist(m$levels), "/")
  if (any(!is.finite(V))) return(unavailable("numeric_range"))
  list(vertices = V, status = "mean_square_region", max_residual = worst, tail = tail)
}

.gtheory_region_intervals <- function(region, relative, absolute) {
  out <- data.frame(lower = rep(NA_real_, 4), upper = NA_real_, status = region$status)
  if (region$status != "mean_square_region") return(out)
  V <- region$vertices; signal <- V[1, ]; rel <- drop(relative %*% V); abs <- drop(absolute %*% V)
  if (any(!is.finite(c(signal, rel, abs))) || min(rel, abs) <= 0) {
    out$status <- "numeric_range"; return(out)
  }
  values <- rbind(signal/(signal + rel), signal/(signal + abs), sqrt(rel), sqrt(abs))
  out$lower <- apply(values, 1, min); out$upper <- apply(values, 1, max)
  out
}
