functions {
#include mgmfrm_functions.stan
}

data {
  int<lower=1> J;
  int<lower=2> R;
  int<lower=2> I;
  int<lower=3> K;
  int<lower=2> D;
  int<lower=1> N;
  int<lower=1> P;
  int<lower=1> NLoadings;
  int<lower=1> free_steps;
  array[N] int<lower=1, upper=J> PersonID;
  array[N] int<lower=1, upper=R> RaterID;
  array[N] int<lower=1, upper=I> ItemID;
  array[N] int<lower=1, upper=K> X;
  array[NLoadings] int<lower=1, upper=I> LoadingItem;
  array[NLoadings] int<lower=1, upper=D> LoadingDim;
  vector<lower=0>[P] prior_sd;
  int<lower=0, upper=2> prior_model; // 0: legacy raw, 1: source, 2: exchangeable
  int<lower=0, upper=R> source_rater;
}

transformed data {
  int expected_parameters = J * D + 2 * (R - 1) + I +
    NLoadings + I * free_steps;
  int rater_offset = J * D;
  int consistency_offset = rater_offset + R - 1 + I + NLoadings;
  int step_offset = consistency_offset + R - 1;
  if (free_steps != K - 2) {
    reject("free_steps must equal K - 2");
  }
  if (P != expected_parameters) {
    reject("P does not match the identified MGMFRM raw parameter count");
  }
  if ((prior_model == 1 && source_rater == 0) ||
      (prior_model != 1 && source_rater != 0)) {
    reject("source_rater must be set exactly for the source prior");
  }
  if (prior_model != 0) {
    // The centered normal kernels require one common SD within each block.
    array[3] int starts = {rater_offset + 1, consistency_offset + 1, step_offset + 1};
    array[3] int counts = {R - 1, R - 1, I * free_steps};
    for (block in 1:3) {
      vector[counts[block]] scales = segment(prior_sd, starts[block], counts[block]);
      if (min(scales) <= 0 || min(scales) != max(scales)) {
        reject("normalized prior requires positive, common block SDs");
      }
    }
    if (prior_model == 1 && is_inf(((R - 1.0) / (2 * R) *
        prior_sd[consistency_offset + 1]) * prior_sd[consistency_offset + 1])) {
      reject("source consistency scale gives a non-finite normalizer");
    }
  }
}

parameters {
  vector[P] beta;
}

model {
  beta ~ normal(0, prior_sd);
  if (prior_model != 0) {
    target += 0.5 * log(R) - 0.5 * square(
      sum(segment(beta, rater_offset + 1, R - 1)) / prior_sd[rater_offset + 1]);
    target += 0.5 * log(R) - 0.5 * square(
      sum(segment(beta, consistency_offset + 1, R - 1)) / prior_sd[consistency_offset + 1]);
    for (i in 1:I) {
      int first_step = step_offset + (i - 1) * free_steps + 1;
      target += 0.5 * log(K - 1) - 0.5 * square(
        sum(segment(beta, first_step, free_steps)) / prior_sd[first_step]);
    }
    if (prior_model == 1) {
      real ell = source_rater < R ? beta[consistency_offset + source_rater]
        : -sum(segment(beta, consistency_offset + 1, R - 1));
      real sd = prior_sd[consistency_offset + 1];
      target += -ell - ((R - 1.0) / (2 * R) * sd) * sd;
    }
  }
  for (n in 1:N) {
    X[n] ~ categorical_logit(mgmfrm_eta(
      PersonID[n], RaterID[n], ItemID[n], J, R, I, K, D,
      NLoadings, free_steps, LoadingItem, LoadingDim, beta));
  }
}

generated quantities {
  vector[N] log_lik;
  for (n in 1:N) {
    log_lik[n] = categorical_logit_lpmf(X[n] | mgmfrm_eta(
      PersonID[n], RaterID[n], ItemID[n], J, R, I, K, D,
      NLoadings, free_steps, LoadingItem, LoadingDim, beta));
  }
}
