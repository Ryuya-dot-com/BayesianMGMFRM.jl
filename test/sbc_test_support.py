"""Synthetic orchestration settings, never a scientific execution manifest."""
import run_mgmfrm_core_sbc as R
from unittest.mock import patch


def prepare_fixture(root, ids):
    # Exercise real profile/source validation without local workflow artifacts.
    # Dummy quantity names and this limited source list are only test inputs.
    source = 'scripts/mgmfrm_core_sbc_plan.py'
    plan = R.S.proposal([f'test_quantity_{i}' for i in range(150)],
                        {source: R.S.digest(R.REPO/source)})
    setting = root.parent/'synthetic-setting.json'
    R.write(setting, plan)
    # These orchestration fixtures do not contain a Julia package. The real
    # saved-runtime import is exercised separately by mgmfrm_core_sbc_runtime.py.
    with patch.object(R, 'preflight'):
        return R.prepare(setting, root, ids)
