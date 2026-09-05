functions {
  vector mfrm_eta(
      int person_id,
      int rater_id,
      int item_id,
      int J,
      int R,
      int I,
      int K,
      int free_steps,
      int threshold_model,
      vector beta) {
    vector[K] eta;
    int rater_offset = J;
    int item_offset = J + R - 1;
    int threshold_offset = J + R + I - 1;
    real person = beta[person_id];
    real rater = rater_id == 1 ? 0 : beta[rater_offset + rater_id - 1];
    real item = item_id == 1 ? 0 : beta[item_offset + item_id - 1];
    real location = person - rater - item;
    real cumulative = 0;

    eta[1] = 0;
    for (k in 2:K) {
      int step_number = k - 1;
      real step = 0;
      if (free_steps > 0) {
        int first_step = threshold_model == 1
          ? threshold_offset
          : threshold_offset + (item_id - 1) * free_steps;
        if (step_number <= free_steps) {
          step = beta[first_step + step_number - 1];
        } else {
          step = -sum(segment(beta, first_step, free_steps));
        }
      }
      cumulative += location - step;
      eta[k] = cumulative;
    }
    return eta;
  }
}

data {
  int<lower=1> J;
  int<lower=1> R;
  int<lower=1> I;
  int<lower=2> K;
  int<lower=1> N;
  int<lower=1> P;
  int<lower=0> free_steps;
  int<lower=1, upper=2> threshold_model;
  array[N] int<lower=1, upper=J> PersonID;
  array[N] int<lower=1, upper=R> RaterID;
  array[N] int<lower=1, upper=I> ItemID;
  array[N] int<lower=1, upper=K> X;
  vector<lower=0>[P] prior_sd;
}

transformed data {
  int expected_steps = threshold_model == 1 ? free_steps : I * free_steps;
  int expected_parameters = J + (R - 1) + (I - 1) + expected_steps;
  if (free_steps != K - 2) {
    reject("free_steps must equal K - 2");
  }
  if (P != expected_parameters) {
    reject("P does not match the identified MFRM parameter count");
  }
}

parameters {
  vector[P] beta;
}

model {
  beta ~ normal(0, prior_sd);
  for (n in 1:N) {
    X[n] ~ categorical_logit(mfrm_eta(
      PersonID[n], RaterID[n], ItemID[n], J, R, I, K,
      free_steps, threshold_model, beta));
  }
}

generated quantities {
  vector[N] log_lik;
  for (n in 1:N) {
    log_lik[n] = categorical_logit_lpmf(X[n] | mfrm_eta(
      PersonID[n], RaterID[n], ItemID[n], J, R, I, K,
      free_steps, threshold_model, beta));
  }
}
