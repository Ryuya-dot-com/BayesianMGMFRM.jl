  // Rotated bivariate-normal quadratic avoids subtracting rho rounded to +/-1.
  real scaled_square(real x, real log_scale) {
    real half_scale;
    if (x == 0) return 0;
    half_scale = exp(log_scale / 2);
    // Scaling before squaring preserves a finite first derivative even when
    // the squared value underflows. Log-space evaluation covers extreme scales.
    if (is_inf(half_scale) || half_scale == 0)
      return exp(2 * log(abs(x)) + log_scale);
    return square(x * half_scale);
  }
  real person_2d_logpdf(real x, real y, real sd, real z) {
    real log_plus = log(2.0) - log1p_exp(-2 * z);
    real log_minus = log(2.0) - log1p_exp(2 * z);
    return -log(2 * pi()) - 2 * log(sd) - (log_plus + log_minus) / 2
      - scaled_square(x / sd + y / sd, -log_plus - log(4.0))
      - scaled_square(x / sd - y / sd, -log_minus - log(4.0));
  }
