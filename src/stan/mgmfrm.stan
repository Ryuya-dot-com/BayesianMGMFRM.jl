functions {
  vector mgmfrm_eta(
      int person_id,
      int rater_id,
      int item_id,
      int J,
      int R,
      int I,
      int K,
      int D,
      int NLoadings,
      int free_steps,
      array[] int LoadingItem,
      array[] int LoadingDim,
      vector beta) {
    vector[K] eta;
    int rater_offset = J * D;
    int item_offset = rater_offset + R - 1;
    int loading_offset = item_offset + I;
    int consistency_offset = loading_offset + NLoadings;
    int step_offset = consistency_offset + R - 1;
    real rater = rater_id < R
      ? beta[rater_offset + rater_id]
      : -sum(segment(beta, rater_offset + 1, R - 1));
    real log_consistency = rater_id < R
      ? beta[consistency_offset + rater_id]
      : -sum(segment(beta, consistency_offset + 1, R - 1));
    real item = beta[item_offset + item_id];
    real ability_score = 0;
    real cumulative = 0;
    real scale = 1.7 * exp(log_consistency);

    for (loading in 1:NLoadings) {
      if (LoadingItem[loading] == item_id) {
        int dimension = LoadingDim[loading];
        real discrimination = exp(beta[loading_offset + loading]);
        ability_score += discrimination *
          beta[(person_id - 1) * D + dimension];
      }
    }

    eta[1] = 0;
    for (k in 2:K) {
      int step_number = k - 1;
      int first_step = step_offset + (item_id - 1) * free_steps + 1;
      real step = step_number <= free_steps
        ? beta[first_step + step_number - 1]
        : -sum(segment(beta, first_step, free_steps));
      cumulative += scale * (ability_score - item - rater - step);
      eta[k] = cumulative;
    }
    return eta;
  }
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
}

transformed data {
  int expected_parameters = J * D + 2 * (R - 1) + I +
    NLoadings + I * free_steps;
  if (free_steps != K - 2) {
    reject("free_steps must equal K - 2");
  }
  if (P != expected_parameters) {
    reject("P does not match the identified MGMFRM raw parameter count");
  }
}

parameters {
  vector[P] beta;
}

model {
  beta ~ normal(0, prior_sd);
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
