library(BayesianMGMFRM)
components <- data.frame(component = rep(c("person", "rater", "residual"), each = 3),
  score1 = rep(c("a", "b", "b"), 3), score2 = rep(c("a", "a", "b"), 3),
  estimate = c(1, .2, 2, .2, .05, .3, 1, .1, 1.5))
V <- diag(.01, 9); V[1, 7] <- V[7, 1] <- .002
f <- structure(list(scores = c("a", "b"), facets = c(rater = "rater"),
  weights = c(.5, .5), counts = list(), interval = .95, components = components,
  component_vcov = as.vector(V), report = list(interval_basis = "observed_information_delta",
    components = list(list(name = "person", factors = "person"), list(name = "rater", factors = "rater"),
                      list(name = "residual", factors = c("person", "rater"))),
    diagnostics = list(qualified = TRUE),
    balanced_moments = list(persons = 6L, replications = 4L, person_df = 5L, residual_df = 15L,
                           person_ms = c(5, .9, .9, 9.5), residual_ms = c(1, .1, .1, 1.5)))),
  class = "mgmfrm_gtheory_fit")
path <- tempfile(fileext = ".rds"); saveRDS(f, path); f <- readRDS(path); unlink(path)
ds <- diagnostics_mgmfrm(f, "reliability", counts = list(rater = 1:4))
row <- ds[ds$score == "a" & ds$metric == "G" & ds$count_rater == 4, ]
stopifnot(abs(row$estimate - .8) < 1e-14,
          abs(row$se - sqrt(.16^2*(.02 - .004))) < 1e-14)
scaled <- diagnostics_mgmfrm(f, "reliability", counts = list(rater = 1:4), weights = c(1, 1))
stopifnot(isTRUE(all.equal(ds$estimate[ds$metric == "G"], scaled$estimate[scaled$metric == "G"])),
          isTRUE(all.equal(2*ds$estimate[ds$metric == "relative_sem" & ds$score == "composite"],
                           scaled$estimate[scaled$metric == "relative_sem" & scaled$score == "composite"])))
exact <- diagnostics_mgmfrm(f, "reliability", counts = list(rater = 4), interval_method = "exact")
stopifnot(all(exact$status[exact$metric == "G"] == "exact_f"),
          all(exact$status[exact$metric == "relative_sem"] == "exact_chisq"),
          all(is.na(exact$lower[exact$metric == "Phi"])))
boundary <- f; boundary$component_vcov <- NULL
stopifnot(all(is.na(diagnostics_mgmfrm(boundary, "reliability", counts = list(rater = 4))$lower)),
          all(is.finite(diagnostics_mgmfrm(boundary, "reliability", counts = list(rater = 4),
                                          interval_method = "exact")$lower[c(1, 3)])))
empty <- f; empty$report$balanced_moments$person_ms <- rep(0, 4)
empty <- diagnostics_mgmfrm(empty, "reliability", counts = list(rater = 4), interval_method = "exact")
stopifnot(all(empty$status[empty$metric == "G"] == "empty_confidence_set"),
          all(is.na(empty$lower[empty$metric == "G"])))
old <- f; old$report$balanced_moments <- NULL
for (expr in list(quote(diagnostics_mgmfrm(f, "reliability", counts = list(rater = 0))),
                  quote(diagnostics_mgmfrm(f, "reliability", counts = list(rater = 3), weights = c(0, 0))),
                  quote(diagnostics_mgmfrm(old, "reliability", counts = list(rater = 3), interval_method = "exact")),
                  quote(diagnostics_mgmfrm(f, "qualification", counts = list(rater = 3)))))
  stopifnot(inherits(try(eval(expr), silent = TRUE), "try-error"))
file <- tempfile(fileext = ".pdf"); grDevices::pdf(file)
plot(f, type = "dstudy", metric = "G", counts = list(rater = 1:4), interval_method = "exact")
grDevices::dev.off(); unlink(file)
stopifnot(is.null(getFromNamespace(".mgmfrm_session", "BayesianMGMFRM")$runtime))

nested <- f
nested$scores <- "a"; nested$facets <- c(task = "task", rater = "rater"); nested$weights <- 1
nested$components <- data.frame(component = c("person", "task", "task:rater", "person:task", "residual"),
                                score1 = "a", score2 = "a", estimate = c(2, .4, .6, .8, 1.2))
nested$component_vcov <- as.vector(diag(.01, 5))
nested$report$balanced_moments <- NULL
nested$report$components <- Map(function(name, factors) list(name = name, factors = factors),
  nested$components$component, list("person", "task", c("task", "rater"), c("person", "task"), c("person", "task", "rater")))
dn <- diagnostics_mgmfrm(nested, "reliability", counts = list(task = 2, rater = 3))
stopifnot(abs(dn$estimate[1] - 2/2.6) < 1e-14, abs(dn$estimate[2] - 2/2.9) < 1e-14,
          abs(dn$estimate[3] - sqrt(.6)) < 1e-14,
          inherits(try(diagnostics_mgmfrm(nested, "reliability", counts = list(task = 2, rater = 3),
                                         interval_method = "exact"), silent = TRUE), "try-error"))

region_fit <- f
region_fit$report$n_observations <- 24L
region_fit$report$anova_moments <- list(levels = c(6L,4L,24L), df = c(5L,3L,15L),
  mean_squares = list(c(5,.9,.9,9.5), c(2.2,.4,.4,3.3), c(1,.1,.1,1.5)))
dr <- diagnostics_mgmfrm(region_fit, "reliability", counts = list(rater = c(1,4)), interval_method = "mean_square_region")
stopifnot(all(dr$status == "mean_square_region"), all(dr$lower <= dr$upper),
          all(dr$lower[dr$metric %in% c("G","Phi")] >= 0),
          all(dr$upper[dr$metric %in% c("G","Phi")] <= 1))
larger <- diagnostics_mgmfrm(region_fit, "reliability", counts = list(rater = c(1,4)), weights = c(1,1), interval_method = "mean_square_region")
keep <- dr$score == "composite" & dr$metric == "absolute_sem"
stopifnot(isTRUE(all.equal(larger$lower[keep], 2*dr$lower[keep])),
          isTRUE(all.equal(larger$upper[keep], 2*dr$upper[keep])))
region_fit$component_vcov <- NULL
stopifnot(all(diagnostics_mgmfrm(region_fit, "reliability", counts = list(rater = 4),
                                interval_method = "mean_square_region")$status == "mean_square_region"))
region_fit$report$anova_moments$mean_squares[[1]] <- region_fit$report$anova_moments$mean_squares[[1]]*1e-7
stopifnot(all(diagnostics_mgmfrm(region_fit, "reliability", counts = list(rater = 4),
                                interval_method = "mean_square_region")$status == "empty_confidence_set"))
