"""POSIX polling guard for trusted research commands; not OS resource containment.

Requires psutil in the Python tool environment. Unavailable observation prevents
launch. No shell execution, automatic retries, or package/environment installation.
"""
import argparse
import json
import math
import os
from pathlib import Path
import signal
import stat
import subprocess
import time
import traceback

try:
    import psutil
except ImportError:
    psutil = None


class ObservationUnavailable(RuntimeError):
    pass


class GuardInterrupted(Exception):
    pass


def _probe():
    if os.name != "posix" or psutil is None:
        raise ObservationUnavailable("POSIX and psutil are required")
    try:
        own = psutil.Process(os.getpid())
        own.memory_info()
        own.children(recursive=True)
    except (OSError, psutil.Error) as error:
        raise ObservationUnavailable(str(error)) from error


def _live(process):
    try:
        return process.is_running() and process.status() != psutil.STATUS_ZOMBIE
    except psutil.NoSuchProcess:
        return False


def _snapshot(parent, known, allow_descendant_groups=False):
    try:
        for process in list(known.values()):
            try:
                if _live(process):
                    for child in process.children(recursive=True):
                        known.setdefault(child.pid, child)
            except psutil.NoSuchProcess:
                continue
        rss = 0
        for process in list(known.values()):
            try:
                if not _live(process):
                    continue
                if not allow_descendant_groups and os.getpgid(process.pid) != parent.pid:
                    raise ObservationUnavailable("an observed descendant left the owned process group")
                rss += process.memory_info().rss
            except (psutil.NoSuchProcess, ProcessLookupError):
                continue
        return rss
    except (OSError, psutil.Error) as error:
        raise ObservationUnavailable(str(error)) from error


def _tree_bytes(root, receipt_path):
    size = 0
    def walk_error(error):
        raise error
    try:
        for folder, directories, files in os.walk(root, onerror=walk_error):
            for name in directories + files:
                path = Path(folder) / name
                if path == receipt_path:
                    continue
                try:
                    info = path.stat(follow_symlinks=False)
                except FileNotFoundError:
                    continue  # a normal concurrent rename/removal; checked next poll
                if stat.S_ISLNK(info.st_mode) or not (stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode)):
                    raise ObservationUnavailable("output tree contains a symlink or special file")
                if stat.S_ISREG(info.st_mode):
                    size += info.st_size
    except OSError as error:
        raise ObservationUnavailable(str(error)) from error
    return size


def _group_exists(group):
    try:
        os.killpg(group, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        # Darwin can return EPERM for a group containing only unreaped zombies.
        # Never treat EPERM alone as absence: inspect group membership/liveness.
        for pid in psutil.pids():
            try:
                if os.getpgid(pid) == group and _live(psutil.Process(pid)):
                    return True
            except (psutil.NoSuchProcess, ProcessLookupError):
                continue
        return False


def _stop(parent, known, grace):
    def send(sig):
        try:
            os.killpg(parent.pid, sig)
        except ProcessLookupError:
            pass
        except PermissionError:
            if _group_exists(parent.pid):
                raise
        # Also clean an observed descendant that changed its process group.
        for process in known.values():
            try:
                if _live(process) and os.getpgid(process.pid) != parent.pid:
                    process.send_signal(sig)  # psutil checks identity against PID reuse
            except (psutil.NoSuchProcess, ProcessLookupError):
                pass

    send(signal.SIGTERM)
    end = time.monotonic() + grace
    while time.monotonic() < end:
        parent.poll()
        if not _group_exists(parent.pid) and not any(_live(p) for p in known.values()):
            break
        time.sleep(0.02)
    kill_sent = _group_exists(parent.pid) or any(_live(p) for p in known.values())
    if kill_sent:
        send(signal.SIGKILL)
    parent.wait(timeout=3)
    end = time.monotonic() + 1
    while any(_live(p) for p in known.values()) and time.monotonic() < end:
        time.sleep(0.02)
    return dict(term_sent=True, kill_sent=kill_sent,
                observed_live_survivors=[p.pid for p in known.values() if _live(p)])


def run_guarded(command, directory, *, wall_seconds, rss_bytes, output_bytes,
                poll_seconds=0.1, grace_seconds=0.5, cwd=None, output_root=None,
                batch_deadline=None, allow_descendant_groups=False):
    if not isinstance(command, (list, tuple)) or not command or not all(isinstance(x, str) and x for x in command):
        raise ValueError("command must be an argument vector")
    for name, value in (("wall_seconds", wall_seconds), ("poll_seconds", poll_seconds), ("grace_seconds", grace_seconds)):
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0:
            raise ValueError(f"{name} must be finite and positive")
    if poll_seconds > 1 or grace_seconds > 5:
        raise ValueError("poll <= 1 second and termination grace <= 5 seconds are required")
    for name, value in (("rss_bytes", rss_bytes), ("output_bytes", output_bytes)):
        if isinstance(value, bool) or not isinstance(value, int) or value < 1:
            raise ValueError(f"{name} must be a positive integer")
    if batch_deadline is not None and (isinstance(batch_deadline, bool) or not math.isfinite(batch_deadline)):
        raise ValueError("batch_deadline must be an absolute monotonic deadline")
    if not isinstance(allow_descendant_groups, bool):
        raise ValueError("allow_descendant_groups must be boolean")
    directory = Path(directory).resolve()
    root = Path(output_root).resolve() if output_root is not None else directory
    if not directory.is_relative_to(root):
        raise ValueError("the output root must contain the job directory")
    directory.mkdir(parents=True, exist_ok=False)
    receipt_path = directory / "guard-receipt.json"
    start = time.monotonic()
    deadline = min(start + wall_seconds, batch_deadline) if batch_deadline is not None else start + wall_seconds
    receipt = dict(schema="bayesianmgmfrm.paired_rating_resource_guard.v1", command=list(command),
        status="not_started", launched=False, process_id=None, output_root=str(root),
        limits=dict(wall_seconds=wall_seconds, rss_bytes=rss_bytes, output_bytes=output_bytes,
                    poll_seconds=poll_seconds, grace_seconds=grace_seconds, batch_deadline=batch_deadline,
                    allow_descendant_groups=allow_descendant_groups),
        peak_observed_rss_bytes=0, peak_observed_output_bytes=0, observations=0,
        measurement="Sum of observed live owned-descendant RSS; shared pages may be counted repeatedly. Logical output file bytes include logs, excluding this controller receipt.",
        limitation="Polling can miss transient peaks or descendants that detach and lose ancestry between observations. Trusted commands only; not a security sandbox or hard allocation/storage containment. Separate descendant groups require explicit opt-in and remain identity-tracked.",
        psutil_version=None if psutil is None else psutil.__version__)
    parent = None
    known = {}
    handlers = {}
    log = None
    try:
        _probe()
        if time.monotonic() >= deadline:
            receipt["status"] = "wall_limit_before_launch"
            return receipt
        receipt["peak_observed_output_bytes"] = _tree_bytes(root, receipt_path)
        if receipt["peak_observed_output_bytes"] > output_bytes:
            receipt["status"] = "output_limit_before_launch"
            return receipt

        def interrupted(signum, frame):
            raise GuardInterrupted(signum)

        for sig in (signal.SIGINT, signal.SIGTERM):
            handlers[sig] = signal.signal(sig, interrupted)
        log = (directory / "command.log").open("xb")
        parent = subprocess.Popen(command, cwd=directory if cwd is None else cwd,
            stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, start_new_session=True)
        receipt.update(launched=True, process_id=parent.pid)
        try:
            known[parent.pid] = psutil.Process(parent.pid)
        except psutil.NoSuchProcess:
            pass  # A command may exit before its first observation.
        while True:
            rss = _snapshot(parent, known, True) if allow_descendant_groups else _snapshot(parent, known)
            size = _tree_bytes(root, receipt_path)
            receipt["observations"] += 1
            receipt["peak_observed_rss_bytes"] = max(receipt["peak_observed_rss_bytes"], rss)
            receipt["peak_observed_output_bytes"] = max(receipt["peak_observed_output_bytes"], size)
            if time.monotonic() >= deadline:
                receipt["status"] = "wall_limit"
                break
            if rss > rss_bytes:
                receipt["status"] = "rss_limit"
                break
            if size > output_bytes:
                receipt["status"] = "output_limit"
                break
            code = parent.poll()
            if code is not None:
                unjoined = _group_exists(parent.pid) or any(_live(p) for p in known.values())
                receipt["status"] = "unjoined_descendants" if unjoined else "completed" if code == 0 else "command_failed"
                break
            time.sleep(min(poll_seconds, max(0, deadline - time.monotonic())))
    except ObservationUnavailable as error:
        receipt.update(status="observation_unavailable", error=str(error))
    except (GuardInterrupted, KeyboardInterrupt) as error:
        receipt.update(status="interrupted", error=str(error))
    except Exception as error:
        receipt.update(status="controller_error", error=f"{type(error).__name__}: {error}")
    finally:
        for sig in handlers:
            signal.signal(sig, signal.SIG_IGN)
        try:
            if parent is not None:
                if parent.poll() is None or _group_exists(parent.pid) or any(_live(p) for p in known.values()):
                    receipt["cleanup"] = _stop(parent, known, grace_seconds)
                    if receipt["cleanup"]["observed_live_survivors"]:
                        receipt["status"] = "cleanup_incomplete"
                receipt["exit_code"] = parent.poll()
        except Exception as error:
            receipt.update(status="cleanup_failed", cleanup_error=str(error), cleanup_traceback=traceback.format_exc())
        finally:
            if log is not None:
                log.close()
            if receipt["launched"]:
                try:
                    final_size = _tree_bytes(root, receipt_path)
                    receipt["final_output_bytes"] = final_size
                    receipt["peak_observed_output_bytes"] = max(receipt["peak_observed_output_bytes"], final_size)
                    if final_size > output_bytes and receipt["status"] in ("completed", "command_failed"):
                        receipt["status"] = "output_limit"
                except ObservationUnavailable as error:
                    receipt["final_observation_error"] = str(error)
                    if receipt["status"] in ("completed", "command_failed"):
                        receipt.update(status="observation_unavailable", error=str(error))
            for sig, handler in handlers.items():
                signal.signal(sig, handler)
            receipt["seconds"] = time.monotonic() - start
            receipt["observed_pids"] = sorted(known)
            receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", required=True)
    parser.add_argument("--wall-seconds", required=True, type=float)
    parser.add_argument("--rss-bytes", required=True, type=int)
    parser.add_argument("--output-bytes", required=True, type=int)
    parser.add_argument("--cwd")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    result = run_guarded(command, args.directory, wall_seconds=args.wall_seconds,
        rss_bytes=args.rss_bytes, output_bytes=args.output_bytes, cwd=args.cwd)
    print(json.dumps(result))
    raise SystemExit(0 if result["status"] == "completed" else 1)
