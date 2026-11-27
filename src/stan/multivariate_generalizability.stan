data {
  int<lower=1> N;
  int<lower=2> C;
  int<lower=3> K;
  int<lower=1> Q;
  array[K] int<lower=1> J;
  array[K] int<lower=1> cov_start;
  array[K] int<lower=1> latent_start;
  array[N, K] int<lower=1> index;
  matrix[N,C] y;
  real mean_location;
  real<lower=0> mean_sd;
  real<lower=0> sd_scale;
  real<lower=0> lkj_eta;
}
parameters { vector[Q] q; }
model {
  array[K] matrix[C,C] factors;
  matrix[N,C] mu;
  target += std_normal_lpdf(q[1:C]);
  for (n in 1:N) mu[n] = (mean_location + mean_sd * q[1:C])';
  for (k in 1:K) {
    matrix[C,C] L = diag_matrix(rep_vector(1,C));
    vector[C] sd = exp(segment(q,cov_start[k],C));
    real jac = 0;
    int cursor = cov_start[k]+C;
    for (i in 2:C) {
      real log_remaining = 0;
      for (j in 1:(i-1)) {
        real z = q[cursor];
        real rho = tanh(z);
        real ls = -2 * (abs(z) + log1p_exp(-2*abs(z)) - log(2));
        L[i,j] = rho * exp(log_remaining/2);
        log_remaining += ls;
        jac += (1.0 + (C-1.0-j)/2)*ls;
        cursor += 1;
      }
      L[i,i] = exp(log_remaining/2);
    }
    target += normal_lpdf(sd | 0,sd_scale) + C*log(2) + sum(segment(q,cov_start[k],C));
    target += lkj_corr_lpdf(multiply_lower_tri_self_transpose(L) | lkj_eta) + jac;
    factors[k] = diag_pre_multiply(sd,L);
    if (k<K) {
      matrix[J[k],C] z = to_matrix(segment(q,latent_start[k],J[k]*C),J[k],C);
      matrix[J[k],C] effects = z * factors[k]';
      target += std_normal_lpdf(to_vector(z));
      for (n in 1:N) mu[n] += effects[index[n,k]];
    }
  }
  for (n in 1:N) target += multi_normal_cholesky_lpdf(y[n]' | mu[n]',factors[K]);
}
