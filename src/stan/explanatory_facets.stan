// Independent dense-map reference to the white-coordinate explanatory PCM.
data {
  int<lower=1> N;
  int<lower=2> K;
  int<lower=1> G;
  int<lower=1> R;
  int<lower=0> T;
  int<lower=0> V;
  int<lower=1> D;
  array[N] int<lower=1,upper=K> y;
  array[N] int<lower=1,upper=G> group;
  matrix[N,R] A;
  matrix[N,T] X;
  vector<lower=0>[R] residual_scale;
  array[R] int<lower=0,upper=V> hyper_index;
  vector[V] logmean;
  vector<lower=0>[V] logsd;
  vector[T] coefficient_mean;
  vector<lower=0>[T] coefficient_sd;
  matrix[K-1,K-2] Hstep;
}
transformed data {
  if (D != R+G*(K-2)+T+V) reject("coordinate dimension mismatch");
}
parameters { vector[D] q; }
model {
  vector[R] effect;
  vector[T] beta = coefficient_mean + coefficient_sd .* segment(q,R+G*(K-2)+1,T);
  vector[N] eta;
  for (j in 1:R) {
    real scale = residual_scale[j];
    if (hyper_index[j] > 0)
      scale = exp(logmean[hyper_index[j]] + logsd[hyper_index[j]] * q[R+G*(K-2)+T+hyper_index[j]]);
    effect[j] = scale*q[j];
  }
  eta = A*effect + X*beta;
  target += std_normal_lpdf(q);
  for (n in 1:N) {
    vector[K] w;
    vector[K-1] tau = Hstep*segment(q,R+(group[n]-1)*(K-2)+1,K-2);
    w[1] = 0;
    for (k in 2:K) w[k] = w[k-1] + eta[n] - tau[k-1];
    target += categorical_logit_lpmf(y[n] | w);
  }
}
