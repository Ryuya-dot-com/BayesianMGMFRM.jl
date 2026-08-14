functions {
  vector gmfrm_eta(
      int person_id,
      int rater_id,
      int item_id,
      int J,
      int R,
      int I,
      int K,
      int free_steps,
      vector beta) {
    vector[K] eta;
    int rater_offset = J;
    int item_offset = J + R;
    int log_discrimination_offset = J + R + I - 1;
    int log_consistency_offset = J + R + 2 * (I - 1);
    int step_offset = J + 2 * R + 2 * (I - 1);
    real person = beta[person_id];
    real rater = beta[rater_offset + rater_id];
    real item = item_id < I
      ? beta[item_offset + item_id]
      : -sum(segment(beta, item_offset + 1, I - 1));
    real log_discrimination = item_id < I
      ? beta[log_discrimination_offset + item_id]
      : -sum(segment(beta, log_discrimination_offset + 1, I - 1));
    real discrimination = exp(log_discrimination);
    real consistency = exp(beta[log_consistency_offset + rater_id]);
    real location = person - item - rater;
    real scale = discrimination * consistency;
    real cumulative = 0;

    eta[1] = 0;
    for (k in 2:K) {
      int step_number = k - 1;
      int first_step = step_offset + (rater_id - 1) * free_steps + 1;
      real step = step_number <= free_steps
        ? beta[first_step + step_number - 1]
        : -sum(segment(beta, first_step, free_steps));
      cumulative += scale * (location - step);
      eta[k] = cumulative;
    }
    return eta;
  }
}

data {
  int<lower=1> J;
  int<lower=1> R;
  int<lower=2> I;
  int<lower=3> K;
  int<lower=1> N;
  int<lower=1> P;
  int<lower=1> free_steps;
  array[N] int<lower=1, upper=J> PersonID;
  array[N] int<lower=1, upper=R> RaterID;
  array[N] int<lower=1, upper=I> ItemID;
  array[N] int<lower=1, upper=K> X;
  vector<lower=0>[P] prior_sd;
}

transformed data {
  int expected_parameters = J + 2 * R + 2 * (I - 1) + R * free_steps;
  if (free_steps != K - 2) {
    reject("free_steps must equal K - 2");
  }
  if (P != expected_parameters) {
    reject("P does not match the identified GMFRM raw parameter count");
  }
}

parameters {
  vector[P] beta;
}

model {
  beta ~ normal(0, prior_sd);
  for (n in 1:N) {
    X[n] ~ categorical_logit(gmfrm_eta(
      PersonID[n], RaterID[n], ItemID[n], J, R, I, K,
      free_steps, beta));
  }
}

generated quantities {
  vector[N] log_lik;
  for (n in 1:N) {
    log_lik[n] = categorical_logit_lpmf(X[n] | gmfrm_eta(
      PersonID[n], RaterID[n], ItemID[n], J, R, I, K,
      free_steps, beta));
  }
}
