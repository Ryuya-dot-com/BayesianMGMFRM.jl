// Opt-in deterministic reference for FourFacetSharedTarget; no fitting adapter.
functions {
  vector zero_sum(vector free) {
    int q = num_elements(free);
    vector[q + 1] out = rep_vector(0, q + 1);
    if (q > 0) {
      vector[q] scaled;
      real remaining;
      for (j in 1:q) scaled[j] = free[j] / sqrt(j * (j + 1.0));
      remaining = sum(scaled);
      out[1] = remaining;
      for (j in 1:q) {
        remaining -= scaled[j];
        out[j + 1] = remaining - j * scaled[j];
      }
    }
    return out;
  }
  vector pcm_logits(real location, vector steps) {
    int K = num_elements(steps) + 1;
    vector[K] eta;
    eta[1] = 0;
    for (k in 2:K) eta[k] = eta[k - 1] + location - steps[k - 1];
    return eta;
  }
  real full_prior(vector beta, vector sd, real A) {
    int D = num_elements(beta);
    // Complete density in orthonormal locations, standard-normal z and d log(sigma).
    return normal_lpdf(head(beta, D - 1) | 0, sd)
           + normal_lpdf(exp(beta[D]) | 0, A) + log(2.0) + beta[D];
  }
}
data {
  int<lower=2> P;
  int<lower=2> T;
  int<lower=2> R;
  int<lower=4> C;
  int<lower=2> K;
  int<lower=1> N;
  array[N] int<lower=1, upper=P> person;
  array[N] int<lower=1, upper=T> task;
  array[N] int<lower=1, upper=R> rater;
  array[N] int<lower=1, upper=C> criterion;
  array[N] int<lower=1, upper=P*T> response;
  array[N] int<lower=1, upper=K> y;
  array[C] int<lower=1, upper=2> criterion_dim;
  vector<lower=0>[6] prior_scale;
}
transformed data {
  int task_offset = 2 * P;
  int rater_offset = task_offset + T - 1;
  int criterion_offset = rater_offset + R - 1;
  int steps_offset = criterion_offset + C - 2;
  int z_offset = steps_offset + C * (K - 2);
  int D = z_offset + P * T + 1;
  array[2] int ncrit = rep_array(0, 2);
  array[N] int seen = rep_array(0, N);
  array[P*T] int group_response = rep_array(0, P*T);
  array[P*T] int response_group = rep_array(0, P*T);
  vector[D - 1] sd = rep_vector(1, D - 1);
  for (s in 1:6)
    if (prior_scale[s] <= 0 || is_inf(prior_scale[s]) || is_nan(prior_scale[s]))
      reject("prior scales must be finite and strictly positive");
  for (c in 1:C) ncrit[criterion_dim[c]] += 1;
  if (min(ncrit) < 2) reject("each dimension needs at least two criteria");
  if (N != P*T*R*C) reject("complete crossed design required");
  for (n in 1:N) {
    int g = (person[n] - 1) * T + task[n];
    int r = response[n];
    int cell = ((g-1)*R+rater[n]-1)*C+criterion[n];
    if (seen[cell] != 0)
      reject("duplicate rating cell");
    seen[cell] = 1;
    if ((group_response[g] != 0 && group_response[g] != r)
        || (response_group[r] != 0 && response_group[r] != g))
      reject("exactly one distinct response per person-task is required");
    group_response[g] = r;
    response_group[r] = g;
  }
  sd[1:task_offset] = rep_vector(prior_scale[1], 2*P);
  sd[(task_offset+1):rater_offset] = rep_vector(prior_scale[2], T-1);
  sd[(rater_offset+1):criterion_offset] = rep_vector(prior_scale[3], R-1);
  sd[(criterion_offset+1):steps_offset] = rep_vector(prior_scale[4], C-2);
  if (K > 2) sd[(steps_offset+1):z_offset] = rep_vector(prior_scale[5], C*(K-2));
}
parameters {
  vector[D] beta;
}
transformed parameters {
  matrix[2,P] theta = to_matrix(head(beta, 2*P), 2, P);
  vector[T] task_effect = zero_sum(segment(beta, task_offset+1, T-1));
  vector[R] rater_effect = zero_sum(segment(beta, rater_offset+1, R-1));
  vector[C] criterion_effect;
  matrix[K-1,C] steps;
  vector[P*T] shared = exp(beta[D]) * segment(beta, z_offset+1, P*T);
  {
    int block_start = criterion_offset;
    for (d in 1:2) {
      vector[ncrit[d]] effects = zero_sum(segment(beta, block_start+1, ncrit[d]-1));
      int j = 1;
      for (c in 1:C) {
        if (criterion_dim[c] == d) {
          criterion_effect[c] = effects[j];
          j += 1;
        }
      }
      block_start += ncrit[d]-1;
    }
  }
  for (c in 1:C)
    steps[,c] = zero_sum(segment(beta, steps_offset+1+(c-1)*(K-2), K-2));
}
model {
  target += full_prior(beta, sd, prior_scale[6]);
  for (n in 1:N) {
    int c = criterion[n];
    real location = theta[criterion_dim[c],person[n]] - task_effect[task[n]]
                    - rater_effect[rater[n]] - criterion_effect[c]
                    + shared[(person[n]-1)*T+task[n]];
    target += categorical_logit_lpmf(y[n] | pcm_logits(location, steps[,c]));
  }
}
generated quantities {
  real prior_lp = full_prior(beta, sd, prior_scale[6]);
  vector[N] log_lik;
  matrix[N,K] log_probs;
  for (n in 1:N) {
    int c = criterion[n];
    real location = theta[criterion_dim[c],person[n]] - task_effect[task[n]]
                    - rater_effect[rater[n]] - criterion_effect[c]
                    + shared[(person[n]-1)*T+task[n]];
    log_probs[n,] = log_softmax(pcm_logits(location, steps[,c]))';
    log_lik[n] = log_probs[n,y[n]];
  }
}
