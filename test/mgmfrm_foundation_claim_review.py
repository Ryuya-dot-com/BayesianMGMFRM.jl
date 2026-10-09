from pathlib import Path
import sys
import unittest
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/"scripts"))
from mgmfrm_foundation_claim_review import ability_errors


class AbilityErrors(unittest.TestCase):
    def test_location_error_is_not_relative_error_or_relative_uncertainty(self):
        truth = np.array([[-1., -2.], [1., 2.]])
        # Perfect relative ability, but shifted and uncertain panel location.
        draws = truth[None, :, :] + np.array([2., 4.])[:, None, None]
        for row in ability_errors(draws, truth, 1.):
            self.assertAlmostEqual(row["absolute_rmse"], 3.)
            self.assertAlmostEqual(row["centered_rmse"], 0.)
            self.assertAlmostEqual(row["panel_mean_error"], 3.)
            self.assertAlmostEqual(row["mean_posterior_centered_sd"], 0.)
            self.assertAlmostEqual(row["posterior_panel_mean_sd"], np.sqrt(2.))
            self.assertAlmostEqual(row["prior_panel_mean_sd"], 1/np.sqrt(2.))
            self.assertAlmostEqual(row["prior_centered_marginal_sd"], 1/np.sqrt(2.))
        imperfect = draws.copy()
        imperfect[:, 0, :] += 1.
        rows = ability_errors(imperfect, truth, 1.)
        shifted = ability_errors(imperfect+7, truth+7, 1.)
        for a, b in zip(rows, shifted):
            self.assertAlmostEqual(a["centered_rmse"], .5)
            self.assertAlmostEqual(a["mse_decomposition_error"], 0.)
            self.assertAlmostEqual(a["absolute_rmse"], b["absolute_rmse"])
            self.assertAlmostEqual(a["centered_rmse"], b["centered_rmse"])
        for bad in (draws[:1], draws[:, :1], np.full_like(draws, np.nan)):
            with self.assertRaises(ValueError):
                ability_errors(bad, truth, 1.)


if __name__ == "__main__":
    unittest.main()
