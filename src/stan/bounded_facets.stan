data {
  int<lower=1> N;
  int<lower=1> R;
  int<lower=1> T;
  int<lower=0> V;
  int<lower=1> D;
  vector<lower=0,upper=1>[N] y;
  real<lower=0> width;
  matrix[N,R] A;
  matrix[N,T] X;
  vector<lower=0>[R] residual_scale;
  array[R] int<lower=0,upper=V> hyper_index;
  vector[V] logmean;
  vector<lower=0>[V] logsd;
  vector[T] coefficient_mean;
  vector<lower=0>[T] coefficient_sd;
  int<lower=0> B;
  int<lower=0> C_sl;
  int<lower=0> S;
  matrix[N,S] Z;
  array[B] int<lower=2> block_dim;
  array[B] int<lower=2> block_m;
  array[B] int<lower=0,upper=D> block_corr_start;
  array[B] int<lower=0> block_corr_len;
  vector<lower=0>[B] block_eta;
  array[C_sl] int<lower=1,upper=max(1,B)> slope_col_block;
  array[C_sl] int<lower=1> slope_col_k;
  vector<lower=0>[C_sl] slope_scale;
  array[C_sl] int<lower=0,upper=D> slope_hyper;
  vector[C_sl] slope_logmean;
  vector<lower=0>[C_sl] slope_logsd;
  array[S] int<lower=1,upper=D> slope_intercept_raw;
  array[S] int<lower=1,upper=D> slope_raw;
  array[S] int<lower=1,upper=max(1,C_sl)> slope_vec_col;
  vector[3] observation_mean;
  vector<lower=0>[3] observation_sd;
  int<lower=0> U;
  int<lower=1> observation_offset;
  matrix[N,U] UX;
  array[U] int<lower=1,upper=D> u_raw;
  array[U] int<lower=1,upper=3> u_block;
  vector[U] u_mean;
  vector<lower=0>[U] u_sd;
  array[U] int<lower=0,upper=D> u_hyper;
  vector[U] u_logmean;
  vector<lower=0>[U] u_logsd;
}
transformed data {
  int extra = 0;
  for (c in 1:C_sl) extra += (slope_hyper[c] > 0);
  for (b in 1:B) extra += block_corr_len[b];
  if (observation_offset != R+T+V+S+extra || D < observation_offset+3) reject("dimension mismatch");
}
parameters { vector[D] q; }
model {
  vector[R] effect;
  vector[T] beta=coefficient_mean+coefficient_sd .* segment(q,R+1,T);
  vector[3] pars=observation_mean+observation_sd .* segment(q,observation_offset+1,3);
  matrix[N,3] op=rep_matrix(pars',N);
  vector[N] eta;
  vector[S] slope_effect;
  int s_offset = 0;
  int col_offset = 0;
  for (j in 1:R) {
    real s=residual_scale[j];
    if (hyper_index[j]>0)
      s=exp(logmean[hyper_index[j]]+logsd[hyper_index[j]]*q[R+T+hyper_index[j]]);
    effect[j]=s*q[j];
  }
  eta=A*effect+X*beta;
  target+=std_normal_lpdf(q);
  for (b in 1:B) {
    int d = block_dim[b];
    int m = block_m[b];
    matrix[d, d] L = diag_matrix(rep_vector(1.0, d));
    if (block_corr_len[b] > 0) {
      real log_jac_L = 0;
      int c_pos = 0;
      for (i in 2:d) {
        real log_rem = 0;
        for (j in 1:(i - 1)) {
          c_pos += 1;
          real a = q[block_corr_start[b] + c_pos - 1];
          real u = tanh(a);
          real ls = log1m(square(u));
          L[i, j] = u * exp(0.5 * log_rem);
          log_jac_L += ls + 0.5 * log_rem;
          log_rem += ls;
          target += -std_normal_lpdf(a);
        }
        L[i, i] = exp(0.5 * log_rem);
      }
      target += lkj_corr_cholesky_lpdf(L | block_eta[b]) + log_jac_L;
    }
    for (k in 1:(d - 1)) {
      int cid = col_offset + k;
      real sd_k = slope_scale[cid];
      int i = k + 1;
      if (slope_hyper[cid] > 0)
        sd_k = exp(slope_logmean[cid] + slope_logsd[cid] * q[slope_hyper[cid]]);
      for (p in 1:m) {
        int s_me = s_offset + (k - 1) * m + p;
        real w = L[i, 1] * q[slope_intercept_raw[s_me]];
        for (j in 2:i) {
          int s_prev = s_offset + (j - 2) * m + p;
          w += L[i, j] * q[slope_raw[s_prev]];
        }
        slope_effect[s_me] = sd_k * w;
      }
    }
    s_offset += (d - 1) * m;
    col_offset += (d - 1);
  }
  if (S > 0) eta += Z * slope_effect;
  for (j in 1:U) {
    real s=u_sd[j];
    if (u_hyper[j]>0) s=exp(u_logmean[j]+u_logsd[j]*q[u_hyper[j]]);
    op[,u_block[j]]+=UX[,j]*(u_mean[j]+s*q[u_raw[j]]);
  }
  for (n in 1:N) {
    real phi=exp(op[n,1]);
    if (y[n]==0) target+=bernoulli_logit_lpmf(1 | op[n,2])+bernoulli_logit_lpmf(0 | op[n,3]);
    else if (y[n]==1) target+=bernoulli_logit_lpmf(1 | op[n,2])+bernoulli_logit_lpmf(1 | op[n,3]);
    else target+=bernoulli_logit_lpmf(0 | op[n,2])
      +beta_lpdf(y[n] | phi*inv_logit(eta[n]),phi*inv_logit(-eta[n]))-log(width);
  }
}
