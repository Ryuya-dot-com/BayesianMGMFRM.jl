data {
  int<lower=1> D;
  int<lower=1> E;
  int<lower=1> M;
  int<lower=1> O;
  int<lower=1> T;
  array[O] int<lower=1> owner_L;
  array[O] int<lower=1> owner_D;
  vector[O] owner_sign;
  array[E, O] int<lower=1> owner_index;

  int<lower=1> N_slices;
  array[N_slices] int<lower=1, upper=O> slice_owner;
  array[N_slices] int<lower=1> slice_dim;
  array[N_slices] int<lower=1, upper=D> slice_raw_start;
  array[N_slices] int<lower=1> slice_L;
  array[N_slices] int<lower=0, upper=D> slice_hyp;
  vector<lower=0>[N_slices] slice_sd_fixed;
  vector[N_slices] slice_logmean;
  vector<lower=0>[N_slices] slice_logsd;

  int<lower=0> N_corr;
  array[N_corr] int<lower=1, upper=O> corr_owner;
  array[N_corr] int<lower=2> corr_D;
  array[N_corr] int<lower=1, upper=D> corr_start;
  array[N_corr] int<lower=1> corr_len;
  vector<lower=0>[N_corr] corr_eta;

  int<lower=1> N_load;
  array[N_load] int<lower=1, upper=O> load_owner;
  array[N_load] int<lower=1, upper=M> load_out;
  array[N_load] int<lower=1> load_dim;
  array[N_load] int<lower=0, upper=2> load_kind;
  vector[N_load] load_val;
  vector[N_load] load_mean;
  vector[N_load] load_sd;
  array[N_load] int<lower=0, upper=D> load_raw;

  array[M] int<lower=1, upper=4> out_fam;
  vector[M] out_dir;
  array[M] int<lower=2> out_K;
  vector<lower=0>[M] out_step_scale;
  array[M] int<lower=0, upper=D> out_step_start;
  int<lower=0> N_Hstep;
  vector[N_Hstep] Hstep_flat;
  array[M] int<lower=0> Hstep_offset;
  array[M] int<lower=0> Hstep_rows;
  array[M] int<lower=0> Hstep_cols;

  vector[M] out_log_width;
  vector[M] out_prec_lm;
  vector<lower=0>[M] out_prec_ls;
  array[M] int<lower=0, upper=D> out_prec_raw;
  vector[M] out_ep_m;
  vector<lower=0>[M] out_ep_s;
  array[M] int<lower=0, upper=D> out_ep_raw;
  vector[M] out_up_m;
  vector<lower=0>[M] out_up_s;
  array[M] int<lower=0, upper=D> out_up_raw;

  array[E, M] int<lower=0, upper=1> obs_mask;
  array[E, M] int<lower=1> y_ord;
  matrix<lower=0, upper=1>[E, M] y_zoib;
  array[E, M] int<lower=0> y_cnt;
  array[E, M] int<lower=1> trials;

  array[T] int<lower=1, upper=M> term_out;
  array[T] int<lower=1, upper=D> term_raw;
  vector[T] term_mean;
  vector<lower=0>[T] term_sd;
  matrix[E, T] X_terms;
}
parameters {
  vector[D] q;
}
model {
  int max_L = max(owner_L);
  int max_D = max(owner_D);
  array[O] matrix[max_D, max_D] L_owner;
  array[O] matrix[max_L, max_D] Z_owner;
  array[O] vector[max_D] sds_owner;
  array[O] matrix[M, max_D] Lam_owner;
  array[O] matrix[max_L, M] proj_owner;
  matrix[E, M] eta = rep_matrix(0.0, E, M);

  target += std_normal_lpdf(q);

  for (o in 1:O) {
    L_owner[o] = diag_matrix(rep_vector(1.0, max_D));
    Z_owner[o] = rep_matrix(0.0, max_L, max_D);
    sds_owner[o] = rep_vector(1.0, max_D);
    Lam_owner[o] = rep_matrix(0.0, M, max_D);
    proj_owner[o] = rep_matrix(0.0, max_L, M);
  }

  for (ic in 1:N_corr) {
    int o = corr_owner[ic];
    int d = corr_D[ic];
    matrix[d, d] Lc = diag_matrix(rep_vector(1.0, d));
    real log_jac_L = 0.0;
    int c_pos = 0;
    for (i in 2:d) {
      real log_rem = 0.0;
      for (j in 1:(i - 1)) {
        c_pos += 1;
        real a = q[corr_start[ic] + c_pos - 1];
        real u = tanh(a);
        real ls = log1m(square(u));
        Lc[i, j] = u * exp(0.5 * log_rem);
        log_jac_L += ls + 0.5 * log_rem;
        log_rem += ls;
        target += -std_normal_lpdf(a);
      }
      Lc[i, i] = exp(0.5 * log_rem);
    }
    target += lkj_corr_cholesky_lpdf(Lc | corr_eta[ic]) + log_jac_L;
    L_owner[o][1:d, 1:d] = Lc;
  }

  for (is in 1:N_slices) {
    int o = slice_owner[is];
    int d = slice_dim[is];
    int L_o = slice_L[is];
    real sd_val = slice_sd_fixed[is];
    if (slice_hyp[is] > 0) {
      sd_val = exp(slice_logmean[is] + slice_logsd[is] * q[slice_hyp[is]]);
    }
    sds_owner[o][d] = sd_val;
    Z_owner[o][1:L_o, d] = segment(q, slice_raw_start[is], L_o);
  }

  for (il in 1:N_load) {
    int o = load_owner[il];
    int c = load_out[il];
    int d = load_dim[il];
    if (load_kind[il] == 0) {
      Lam_owner[o][c, d] = load_val[il];
    } else if (load_kind[il] == 1) {
      Lam_owner[o][c, d] = load_mean[il] + load_sd[il] * q[load_raw[il]];
    } else {
      Lam_owner[o][c, d] = exp(load_mean[il] + load_sd[il] * q[load_raw[il]]);
    }
  }

  for (o in 1:O) {
    int L_o = owner_L[o];
    int d_o = owner_D[o];
    matrix[L_o, d_o] w = Z_owner[o][1:L_o, 1:d_o] * (L_owner[o][1:d_o, 1:d_o]');
    matrix[L_o, d_o] b;
    for (d in 1:d_o) {
      b[, d] = sds_owner[o][d] * w[, d];
    }
    proj_owner[o][1:L_o, 1:M] = owner_sign[o] * (b * (Lam_owner[o][1:M, 1:d_o]'));
    for (e in 1:E) {
      int j = owner_index[e, o];
      eta[e, ] += proj_owner[o][j, ];
    }
  }

  for (ti in 1:T) {
    int c = term_out[ti];
    real bval = term_mean[ti] + term_sd[ti] * q[term_raw[ti]];
    eta[, c] += bval * X_terms[, ti];
  }

  for (c in 1:M) {
    real dsgn = out_dir[c];
    if (out_fam[c] == 1) {
      int K = out_K[c];
      int H = K - 1;
      vector[H] tau = rep_vector(0.0, H);
      if (H > 1) {
        int hr = Hstep_rows[c];
        int hc = Hstep_cols[c];
        matrix[hr, hc] Hmat = to_matrix(segment(Hstep_flat, Hstep_offset[c] + 1, hr * hc), hr, hc);
        tau = Hmat * segment(q, out_step_start[c], hc);
      }
      for (e in 1:E) {
        if (obs_mask[e, c] == 1) {
          vector[K] logits;
          logits[1] = 0.0;
          for (h in 1:H) {
            logits[h + 1] = logits[h] + dsgn * eta[e, c] - tau[h];
          }
          target += categorical_logit_lpmf(y_ord[e, c] | logits);
        }
      }
    } else if (out_fam[c] == 2) {
      real phi = exp(out_prec_lm[c] + out_prec_ls[c] * q[out_prec_raw[c]]);
      real ep = out_ep_m[c] + out_ep_s[c] * q[out_ep_raw[c]];
      real up = out_up_m[c] + out_up_s[c] * q[out_up_raw[c]];
      for (e in 1:E) {
        if (obs_mask[e, c] == 1) {
          real yv = y_zoib[e, c];
          real ec = dsgn * eta[e, c];
          if (yv == 0.0) {
            target += bernoulli_logit_lpmf(1 | ep) + bernoulli_logit_lpmf(0 | up);
          } else if (yv == 1.0) {
            target += bernoulli_logit_lpmf(1 | ep) + bernoulli_logit_lpmf(1 | up);
          } else {
            target += bernoulli_logit_lpmf(0 | ep)
              + beta_lpdf(yv | phi * inv_logit(ec), phi * inv_logit(-ec))
              - out_log_width[c];
          }
        }
      }
    } else if (out_fam[c] == 3) {
      for (e in 1:E) {
        if (obs_mask[e, c] == 1) {
          target += binomial_logit_lpmf(y_cnt[e, c] | trials[e, c], dsgn * eta[e, c]);
        }
      }
    } else {
      real phi = exp(out_prec_lm[c] + out_prec_ls[c] * q[out_prec_raw[c]]);
      for (e in 1:E) {
        if (obs_mask[e, c] == 1) {
          real ec = dsgn * eta[e, c];
          target += beta_binomial_lpmf(y_cnt[e, c] | trials[e, c], phi * inv_logit(ec), phi * inv_logit(-ec));
        }
      }
    }
  }
}
