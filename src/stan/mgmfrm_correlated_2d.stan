// Private between-item MGMFRM: estimated positive loadings/consistencies,
// independent normals on base raw coordinates, and LKJ on population rho.
functions {
#include correlated_2d_functions.stan
#include mgmfrm_functions.stan
}
data {
  int<lower=1> J;
  int<lower=2> R;
  int<lower=4> I;
  int<lower=3> K;
  int<lower=2, upper=2> D;
  int<lower=1, upper=10000> lkj_eta;
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
}
transformed data {
  array[I] int item_dimension = rep_array(0, I);
  array[D] int pure_items = rep_array(0, D);
  array[J, D] int observed = rep_array(0, J, D);
  array[6] int counts = {J * D, R - 1, I, NLoadings, R - 1, I * free_steps};
  int first_parameter = 1;
  if (free_steps != K - 2 || P != sum(counts))
    reject("invalid MGMFRM raw parameter or step count");
  if (NLoadings != I)
    reject("correlated MGMFRM requires one active loading per item");
  for (l in 1:NLoadings) {
    if (item_dimension[LoadingItem[l]] != 0)
      reject("correlated MGMFRM requires distinct pure items");
    item_dimension[LoadingItem[l]] = LoadingDim[l];
    pure_items[LoadingDim[l]] += 1;
  }
  if (min(pure_items) < 2)
    reject("correlated MGMFRM requires at least two pure items per dimension");
  for (n in 1:N)
    observed[PersonID[n], item_dimension[ItemID[n]]] = 1;
  for (j in 1:J)
    if (min(observed[j]) != 1)
      reject("each person must have observations in both dimensions");
  for (block in 1:6) {
    vector[counts[block]] scales = segment(prior_sd, first_parameter, counts[block]);
    if (min(scales) <= 0 || is_inf(max(scales)) || min(scales) != max(scales))
      reject("raw normal prior requires finite positive common SDs within each block");
    first_parameter += counts[block];
  }
}
parameters {
  vector[P] beta;
  real zrho;
}
model {
  // Both parameter blocks are unconstrained. Add the tanh Jacobian once,
  // manually, and retain all normalizing constants in the raw-coordinate target.
  real logdelta = 2 * (log(2.0) - abs(zrho) - log1p_exp(-2 * abs(zrho)));
  target += -lbeta(0.5, lkj_eta) + lkj_eta * logdelta;
  for (j in 1:J)
    target += person_2d_logpdf(beta[2*j-1], beta[2*j], prior_sd[1], zrho);
  target += normal_lpdf(tail(beta, P - J * D) | 0, tail(prior_sd, P - J * D));
  for (n in 1:N)
    target += categorical_logit_lpmf(X[n] | mgmfrm_eta(
      PersonID[n], RaterID[n], ItemID[n], J, R, I, K, D,
      NLoadings, free_steps, LoadingItem, LoadingDim, beta));
}
generated quantities {
  real rho = tanh(zrho);
  vector[N] log_lik;
  for (n in 1:N)
    log_lik[n] = categorical_logit_lpmf(X[n] | mgmfrm_eta(
      PersonID[n], RaterID[n], ItemID[n], J, R, I, K, D,
      NLoadings, free_steps, LoadingItem, LoadingDim, beta));
}
