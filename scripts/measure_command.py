#!/usr/bin/env python3
"""Local POSIX diagnostic: elapsed time and an owned-process-group deadline.

Usage: python3 scripts/measure_command.py SECONDS -- COMMAND [ARG ...]
Run --self-test in the same permission context before an expensive command.
No external timer, resource counters, shell, retries, or cache management.
"""

import argparse
import math
import os
import signal
import subprocess
import sys
import time


def measure(seconds, argv):
    if os.name != "posix":
        raise ValueError("this diagnostic requires POSIX process groups")
    if not math.isfinite(seconds) or not 0 < seconds <= 1800 or not argv:
        raise ValueError("require a command and 0 < finite seconds <= 1800")

    cancelled = 0

    def cancel(signum, _frame):
        nonlocal cancelled
        cancelled = cancelled or signum

    previous = {}
    proc = None
    status, code = "observer_error", 125
    started = time.monotonic()
    try:
        # Recording, not raising, also permits cleanup if cancellation arrives
        # while Popen is starting the child. Never change the child's argv/env.
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            previous[sig] = signal.signal(sig, cancel)
        proc = subprocess.Popen(argv, start_new_session=True)
        while True:
            if cancelled:
                status, code = "interrupted", 128 + cancelled
                break
            remaining = seconds - (time.monotonic() - started)
            if remaining <= 0:
                status, code = "timeout", 124
                break
            try:
                child_code = proc.wait(timeout=min(remaining, 0.1))
            except subprocess.TimeoutExpired:
                continue
            status = "completed"
            code = child_code if child_code >= 0 else 128 - child_code
            break
    except OSError as error:
        status = "launch_error" if proc is None else "observer_error"
        code = (127 if isinstance(error, FileNotFoundError) else 126) if proc is None else 125
        print(f"MEASURE error={error}", file=sys.stderr, flush=True)
    finally:
        if proc is not None:
            try:
                # ponytail: owned POSIX group, not containment of descendants
                # that call setsid/setpgid. Use an OS job/container if needed.
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.wait(timeout=5)
            except (OSError, subprocess.TimeoutExpired) as error:
                status, code = "observer_error", 125
                print(f"MEASURE cleanup_error={error}", file=sys.stderr, flush=True)
        if cancelled and status != "observer_error":
            status, code = "interrupted", 128 + cancelled
        for sig, handler in previous.items():
            signal.signal(sig, handler)

    child_code = proc.returncode if proc is not None else None
    print(f"MEASURE elapsed={time.monotonic() - started:.6f} status={status} "
          f"child_exit={child_code} exit={code}", file=sys.stderr, flush=True)
    return code


def self_test():
    import contextlib
    import io
    import tempfile
    from pathlib import Path
    from unittest.mock import patch

    wrapper = [sys.executable, os.path.abspath(__file__)]
    checked = 0

    def verify(result, status, code, child_code):
        nonlocal checked
        assert result.returncode == code, result
        line = result.stderr.splitlines()[-1]
        fields = dict(part.split("=", 1) for part in line.split()[1:])
        assert line.startswith("MEASURE "), result.stderr
        assert fields["status"] == status and int(fields["exit"]) == code, fields
        assert fields["child_exit"] == str(child_code), fields
        assert math.isfinite(float(fields["elapsed"])) and float(fields["elapsed"]) >= 0, fields
        checked += 1

    def run(args):
        return subprocess.run(wrapper + args, capture_output=True, text=True, timeout=15)

    for code in (0, 7, 124, 125, 127):
        result = run(["10", "--", sys.executable, "-c", f"raise SystemExit({code})"])
        verify(result, "completed", code, code)
    result = run(["10", "--", sys.executable, "-c",
                  "import os,signal; os.kill(os.getpid(),signal.SIGTERM)"])
    verify(result, "completed", 128 + signal.SIGTERM, -signal.SIGTERM)
    result = run(["10", "--", sys.executable, "-c",
                  "import sys; assert sys.argv[1:] == ['space value', '; exit 7', '--flag']; "
                  "print('stdout kept'); print('stderr kept',file=sys.stderr)",
                  "space value", "; exit 7", "--flag"])
    verify(result, "completed", 0, 0)
    assert result.stdout == "stdout kept\n" and "stderr kept\n" in result.stderr
    for seconds in ("nan", "inf", "0", "-1", "1801"):
        result = run([seconds, "--", sys.executable, "-c", "print('MUST NOT RUN')"])
        assert result.returncode == 2 and not result.stdout, result
        checked += 1
    result = run(["10", "--"])
    assert result.returncode == 2, result
    checked += 1

    # Inject an observer failure after a short-lived child has already exited:
    # never relabel it as a test failure or successful cleanup.
    errors = io.StringIO()
    with patch("os.killpg", side_effect=PermissionError("injected cleanup failure")), contextlib.redirect_stderr(errors):
        code = measure(10, [sys.executable, "-c", "raise SystemExit(7)"])
    verify(subprocess.CompletedProcess([], code, "", errors.getvalue()), "observer_error", 125, 7)

    with tempfile.TemporaryDirectory(prefix="m0-observer-self-test-") as root:
        verify(run(["10", "--", str(Path(root) / "absent")]), "launch_error", 127, None)
        verify(run(["10", "--", root]), "launch_error", 126, None)
        worker = ("import os,signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); "
                  "print('OWNED',os.getpid(),os.getpgrp(),flush=True); time.sleep(30)")
        parent = ("import os,signal,subprocess,sys; "
                  "signal.signal(signal.SIGTERM,signal.SIG_IGN); "
                  "print('OWNED',os.getpid(),os.getpgrp(),flush=True); "
                  "p=subprocess.Popen([sys.executable,'-c',sys.argv[1]],stdout=subprocess.PIPE,text=True); "
                  "print(p.stdout.readline(),end='',flush=True); "
                  "print('READY',flush=True); "
                  "p.wait() if sys.argv[2]=='wait' else None")
        for mode in ("timeout", "normal", signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            log = Path(root) / str(mode)
            args = ["2" if mode == "timeout" else "10", "--", sys.executable, "-c",
                    parent, worker, "leave" if mode == "normal" else "wait"]
            with log.open("w+") as output:
                proc = subprocess.Popen(wrapper + args, stdout=output, stderr=subprocess.PIPE, text=True)
                try:
                    ready_by = time.monotonic() + 5
                    while "READY\n" not in log.read_text() and proc.poll() is None:
                        assert time.monotonic() < ready_by, "worker failed to become ready"
                        time.sleep(0.01)
                    assert "READY\n" in log.read_text(), log.read_text()
                    if isinstance(mode, int):
                        proc.send_signal(mode)
                    # Both controlled workers hold inherited stderr open until
                    # exit. EOF proves cleanup without sandbox-sensitive ps or
                    # treating an unreaped zombie as a running process.
                    _, stderr = proc.communicate(timeout=10)
                finally:
                    if proc.poll() is None:
                        proc.terminate()
                        proc.communicate(timeout=10)
            result = subprocess.CompletedProcess(proc.args, proc.returncode, log.read_text(), stderr)
            expected = 0 if mode == "normal" else 124 if mode == "timeout" else 128 + mode
            status = "completed" if mode == "normal" else "timeout" if mode == "timeout" else "interrupted"
            verify(result, status, expected, 0 if mode == "normal" else -signal.SIGKILL)
            owned = [tuple(map(int, line.split()[1:])) for line in result.stdout.splitlines()
                     if line.startswith("OWNED ")]
            assert len(owned) == 2 and owned[0][0] == owned[0][1] == owned[1][1], owned
            assert owned[0][1] != os.getpgrp(), owned
    print(f"Measurement self-test passed: {checked} cases; child status, argv/output, "
          "launch errors, deadline, cancellation, and owned-group cleanup.")


def main():
    if sys.argv[1:] == ["--self-test"]:
        self_test()
        return 0
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("seconds", type=float)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    try:
        return measure(args.seconds, command)
    except ValueError as error:
        parser.error(str(error))


if __name__ == "__main__":
    sys.exit(main())
