// Private unit-logit fixed-Q MFRM; beta contains only the reduced coordinates.
functions {
#include mgmfrm_functions.stan
  vector fixed_q_raw(vector beta, int locations, int n_steps, int step_offset) {
    vector[step_offset + n_steps] raw = rep_vector(0, step_offset + n_steps);
    raw[1:locations] = beta[1:locations] / 1.7;
    raw[(step_offset + 1):(step_offset + n_steps)] =
      beta[(locations + 1):(locations + n_steps)] / 1.7;
    return raw;
  }
}
data {
  int<lower=1> J;
  int<lower=2> R;
  int<lower=2> I;
  int<lower=2> K;
  int<lower=2> D;
  int<lower=0, upper=1> exchangeable_raters;
  int<lower=1> N;
  int<lower=1> NLoadings;
  array[N] int<lower=1, upper=J> PersonID;
  array[N] int<lower=1, upper=R> RaterID;
  array[N] int<lower=1, upper=I> ItemID;
  array[N] int<lower=1, upper=K> X;
  array[NLoadings] int<lower=1, upper=I> LoadingItem;
  array[NLoadings] int<lower=1, upper=D> LoadingDim;
  vector<lower=0>[J * D + R - 1 + I + I * (K - 2)] reference_sd;
}
transformed data {
  int locations = J * D + R - 1 + I;
  int free_steps = K - 2;
  int n_steps = I * free_steps;
  int step_offset = locations + NLoadings + R - 1;
  if (min(reference_sd) <= 0)
    reject("reference_sd must be strictly positive");
  if (exchangeable_raters)
    for (r in 1:(R-1))
      if (reference_sd[J*D+r] != reference_sd[J*D+1])
        reject("exchangeable rater kernel scales must be identical");
}
parameters {
  vector[locations + n_steps] beta;
}
model {
  vector[step_offset + n_steps] raw = fixed_q_raw(beta, locations, n_steps, step_offset);
  target += normal_lpdf(beta | 0, reference_sd);
  if (exchangeable_raters)
    target += 0.5 * log(R) - 0.5 * square(sum(segment(beta, J*D+1, R-1)) / reference_sd[J*D+1]);
  for (n in 1:N) {
    target += categorical_logit_lpmf(X[n] | mgmfrm_eta(
      PersonID[n], RaterID[n], ItemID[n], J, R, I, K, D,
      NLoadings, free_steps, LoadingItem, LoadingDim, raw));
  }
}
generated quantities {
  vector[N] log_lik;
  {
    vector[step_offset + n_steps] raw = fixed_q_raw(beta, locations, n_steps, step_offset);
    for (n in 1:N) {
      log_lik[n] = categorical_logit_lpmf(X[n] | mgmfrm_eta(
        PersonID[n], RaterID[n], ItemID[n], J, R, I, K, D,
        NLoadings, free_steps, LoadingItem, LoadingDim, raw));
    }
  }
}
