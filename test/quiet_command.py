"""Run with python3 test/quiet_command.py; no Julia, fits, or dependencies."""

import os
from pathlib import Path
import subprocess
import tempfile


wrapper = Path(__file__).resolve().parents[1] / "scripts" / "quiet_command.sh"
with tempfile.TemporaryDirectory(prefix="quiet command ") as directory:
    def run(*args):
        return subprocess.run(["sh", str(wrapper), *args], capture_output=True,
                              text=True, env={**os.environ, "TMPDIR": directory})

    result = run("sh", "-c", 'printf "%s\\n" "$1"; printf "hidden error\\n" >&2; [ "$#" -eq 1 ]',
                 "check", "a b; $x")
    assert result.returncode == 0 and result.stdout.startswith("PASS: sh (log: "), result
    assert len(result.stdout.splitlines()) == 1 and not result.stderr, result
    logs = list(Path(directory).iterdir())
    assert len(logs) == 1 and logs[0].read_text() == "a b; $x\nhidden error\n"
    assert logs[0].stat().st_mode & 0o077 == 0  # Private output, not shared logs.

    result = run("sh", "-c", 'printf "failure output\\n"; printf "failure error\\n" >&2; exit 7')
    assert result.returncode == 7 and not result.stdout, result
    assert "exit 7; full log:" in result.stderr, result
    assert "failure output\nfailure error\n" in result.stderr, result
    result = run("sh", "-c", 'i=0; while [ "$i" -lt 100 ]; do echo "line $i"; i=$((i+1)); done; exit 9')
    assert result.returncode == 9 and len(result.stderr.splitlines()) == 81, result
    assert "line 0\n" not in result.stderr and "line 99\n" in result.stderr, result
    result = run(str(Path(directory) / "missing command"))
    assert result.returncode == 127 and "FAIL:" in result.stderr, result
    result = run("sh", "-c", 'kill -TERM "$$"')
    assert result.returncode == 143 and "FAIL:" in result.stderr, result
    result = run()
    assert result.returncode == 2 and result.stderr.startswith("Usage:"), result
print("quiet command: 6 cases passed")
