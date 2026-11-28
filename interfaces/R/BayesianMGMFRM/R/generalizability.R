.fit_gtheory <- function(data, person, scores, facets, nesting, method, counts, weights, interval) {
  if (!(method %in% c("ml", "reml"))) stop("G-theory in R requires method = 'ml' or 'reml'.")
  if (!is.data.frame(data) || !nrow(data) || anyDuplicated(names(data))) stop("Supply a nonempty data frame with distinct columns.")
  if (!is.character(person) || length(person) != 1L || is.na(person) || !nzchar(person) ||
      !is.character(scores) || !length(scores) || anyNA(scores) || anyDuplicated(scores) || any(!nzchar(scores)))
    stop("person and score must name the ID column and one or more numeric score columns.")
  if (!is.character(facets) || !(length(facets) %in% 1:2) || is.null(names(facets)) ||
      anyNA(facets) || anyNA(names(facets)) || any(!nzchar(names(facets))) || anyDuplicated(names(facets)) || "person" %in% names(facets))
    stop("facets must name one or two measurement facets, e.g. c(rater = 'Rater').")
  cols <- c(person, unname(facets), scores)
  if (anyDuplicated(cols) || !all(cols %in% names(data))) stop("ID, facet and score columns must exist and be distinct.")
  if (!all(vapply(data[scores], function(x) is.numeric(x) && all(is.finite(x)), logical(1)))) stop("Scores must be finite numeric values.")
  ids <- data[c(person, unname(facets))]
  if (anyNA(ids) || any(vapply(ids, function(x) any(!nzchar(as.character(x))) || (is.numeric(x) && any(!is.finite(x))), logical(1))) || anyDuplicated(ids))
    stop("IDs must be nonmissing and nonempty, with one row per person/facet cell.")
  if (is.null(nesting)) nesting <- character()
  if (length(nesting) && (!is.character(nesting) || length(nesting) != 1L ||
      is.null(names(nesting)) || !all(c(names(nesting), nesting) %in% names(facets)) || names(nesting) == nesting))
    stop("nesting must map a child facet to its parent.")
  if (!is.numeric(interval) || length(interval) != 1L || !is.finite(interval) || interval <= 0 || interval >= 1)
    stop("interval must be between zero and one.")
  if (is.null(weights)) weights <- rep(1/length(scores), length(scores))
  if (!is.numeric(weights) || length(weights) != length(scores) || any(!is.finite(weights)) || !any(weights != 0))
    stop("weights must be a finite nonzero vector in score-column order.")
  if (is.null(counts)) counts <- list()
  if (length(counts)) {
    if (is.null(names(counts)) || anyDuplicated(names(counts)) || !setequal(names(counts), names(facets)))
      stop("counts must name every measurement facet.")
    counts <- counts[names(facets)]
    if (!all(vapply(counts, function(x) is.numeric(x) && length(x) > 0L && all(is.finite(x) & x > 0 & x == floor(x) & x <= .Machine$integer.max) && !anyDuplicated(x), logical(1))))
      stop("Each counts grid must contain distinct positive integers.")
  }
  plans <- if (length(counts)) do.call(expand.grid, c(counts, KEEP.OUT.ATTRS = FALSE)) else data.frame()
  payload <- .with_mgmfrm(.mgmfrm_session$runtime, {
    fn <- JuliaConnectoR::juliaEval("Base.invokelatest(getfield, Base.invokelatest(getfield, Main, :MGMFRMRBridge), :fit_generalizability)")
    JuliaConnectoR::juliaCall("Base.invokelatest", fn, person, as.character(data[[person]]),
      names(facets), unname(facets), unlist(lapply(data[unname(facets)], as.character), use.names = FALSE),
      scores, as.double(as.matrix(data[scores])), if (length(nesting)) names(nesting) else character(), unname(nesting), method,
      as.integer(as.matrix(plans)), nrow(plans), as.double(weights), as.double(interval))
  })
  out <- jsonlite::fromJSON(payload, simplifyVector = FALSE)
  structure(list(model = "gtheory", method = method, report = out$report,
    components = .rows_to_df(out$components), dstudy = .rows_to_df(out$dstudy), component_vcov = out$component_vcov,
    ids = ids, scores = scores, facets = facets, nesting = nesting, counts = counts,
    weights = weights, interval = interval), class = "mgmfrm_gtheory_fit")
}

print.mgmfrm_gtheory_fit <- function(x, ...) {
  cat("Gaussian G-theory (", toupper(x$method), "), ", length(x$scores), " score(s)\n", sep = "")
  print(x$components, row.names = FALSE)
  if (nrow(x$dstudy)) print(x$dstudy, row.names = FALSE)
  cat(paste(unlist(x$report$diagnostics$warnings), collapse = "\n"), "\n")
  invisible(x)
}
summary.mgmfrm_gtheory_fit <- function(object, ...) {
  structure(list(method = object$method, components = object$components, dstudy = object$dstudy,
       diagnostics = object$report$diagnostics, interval = object$interval),
       class = "summary.mgmfrm_gtheory_fit")
}
print.summary.mgmfrm_gtheory_fit <- function(x, ...) {
  cat("Summary of Gaussian G-theory (", toupper(x$method), "), ", 100 * x$interval, "% intervals\n", sep = "")
  cat("Numerically qualified:", isTRUE(x$diagnostics$qualified), "\n")
  print(x$components, row.names = FALSE)
  if (nrow(x$dstudy)) print(x$dstudy, row.names = FALSE)
  if (length(x$diagnostics$warnings)) cat(paste(unlist(x$diagnostics$warnings), collapse = "\n"), "\n")
  invisible(x)
}
coef.mgmfrm_gtheory_fit <- function(object, ...) {
  d <- object$components
  setNames(d$estimate, paste(d$component, d$score1, d$score2, sep = ":"))
}
vcov.mgmfrm_gtheory_fit <- function(object, ...) {
  labels <- names(coef(object)); n <- length(labels)
  out <- matrix(if (is.null(object$component_vcov)) NA_real_ else unlist(object$component_vcov), n, n,
                dimnames = list(labels, labels))
  attr(out, "basis") <- object$report$interval_basis
  out
}
plot.mgmfrm_gtheory_fit <- function(x, type = c("variance", "covariance", "dstudy"),
                                   score = "composite", metric = c("Phi", "G", "relative_sem", "absolute_sem"),
                                   counts = x$counts, weights = x$weights, interval = x$interval,
                                   interval_method = c("delta", "exact", "mean_square_region"), ...) {
  type <- match.arg(type); metric <- match.arg(metric)
  interval_method <- match.arg(interval_method)
  if (type != "dstudy" && (interval_method != "delta" || !missing(counts) || !missing(weights) || !missing(interval)))
    stop("D-study options require type = 'dstudy'.")
  note <- paste0(100*interval, "% pointwise asymptotic confidence intervals; unavailable intervals omitted.")
  if (type != "dstudy") {
    d <- x$components
    d <- d[if (type == "variance") d$score1 == d$score2 else d$score1 != d$score2, , drop = FALSE]
    if (!nrow(d)) stop("No components for the requested plot.")
    labs <- paste(d$component, d$score1, d$score2, sep = ": ")
    old <- graphics::par(mar = c(5, 12, 4, 2)); on.exit(graphics::par(old))
    lim <- range(c(0, d$estimate, d$lower, d$upper), na.rm = TRUE)
    graphics::plot(d$estimate, seq_len(nrow(d)), xlim = lim, yaxt = "n", pch = 19,
                   xlab = "Variance / covariance (products of score units)", ylab = "", main = "G-study components", sub = note, ...)
    graphics::axis(2, at = seq_len(nrow(d)), labels = labs, las = 1)
    graphics::abline(v = 0, lty = 3, col = "grey60")
    ok <- is.finite(d$lower) & is.finite(d$upper)
    graphics::segments(d$lower[ok], which(ok), d$upper[ok], which(ok))
  } else {
    if (interval_method == "exact" && !metric %in% c("G", "relative_sem"))
      stop("Exact plots support G or relative_sem.")
    d <- .gtheory_dstudy(x, counts, weights, interval, interval_method)
    d <- d[d$score == score & d$metric == metric, , drop = FALSE]
    if (!nrow(d)) stop("Unknown score or metric.")
    if (interval_method == "exact") {
      note <- paste0(100*interval, "% exact Gaussian ", if (metric == "G") "F" else "chi-square", " intervals; ML/REML points.")
      omitted <- unique(d$status[!d$status %in% c("exact_f", "exact_chisq")])
      if (length(omitted)) note <- paste(note, "Omitted:", paste(gsub("_", " ", omitted), collapse = ", "))
    } else if (interval_method == "mean_square_region") {
      note <- paste0(100*interval, "% Gaussian mean-square region: joint over plans/metrics for this fixed score.")
      omitted <- unique(d$status[d$status != "mean_square_region"])
      if (length(omitted)) note <- paste(note, "Omitted:", paste(gsub("_", " ", omitted), collapse = ", "))
    }
    facet <- names(x$facets)[1L]; other <- names(x$facets)[-1L]
    xx <- d[[paste0("count_", facet)]]
    group <- if (length(other)) as.character(d[[paste0("count_", other)]]) else rep(score, nrow(d))
    ylim <- range(c(d$estimate, d$lower, d$upper), na.rm = TRUE)
    graphics::plot(range(xx), ylim, type = "n", xaxt = "n", xlab = paste("Number of", facet, "levels"),
                   ylab = switch(metric, G = "Relative generalizability (G)", Phi = "Absolute dependability (Phi)",
                                 relative_sem = "Relative SEM", absolute_sem = "Absolute SEM"),
                   main = paste("D study:", score), sub = note, ...)
    graphics::axis(1, at = sort(unique(xx)))
    for (i in seq_along(unique(group))) {
      idx <- which(group == unique(group)[i]); idx <- idx[order(xx[idx])]
      graphics::lines(xx[idx], d$estimate[idx], type = "b", pch = 19, col = i)
      ok <- idx[is.finite(d$lower[idx]) & is.finite(d$upper[idx])]
      graphics::segments(xx[ok], d$lower[ok], xx[ok], d$upper[ok], col = i)
    }
    if (length(other)) graphics::legend("bottomright", legend = paste(other, unique(group), sep = "="), col = seq_along(unique(group)), lty = 1, pch = 19)
  }
  if (!isTRUE(x$report$diagnostics$qualified)) graphics::mtext("Numerical diagnostics require review", side = 3, col = "red3")
  invisible(x)
}
