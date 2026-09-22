"""Run with python3 test/cmdstan_cancellation.py (POSIX, Julia, no package load).

Exercise unchanged package command-helper bodies with real processes/signals.
Only owned temporary commands run; no CmdStan build, sampler, or posterior fit.
"""
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

if os.name != "posix":
    print("CmdStan cancellation: skipped (POSIX signal probe)")
    raise SystemExit(0)

root = Path(__file__).resolve().parents[1]
runner_source = r'''
module CommandProbe
include(joinpath(ARGS[1], "src", "cmdstan_backend.jl"))
const selected = Symbol[]
const wanted = (:_cmdstan_failure_reason, :_cmdstan_error_detail, :_cmdstan_short_detail,
    :_cmdstan_stop, :_cmdstan_exit_cleanup, :_cmdstan_wait, :_cmdstan_run)
const constants = (:_CMDSTAN_ACTIVE_COMMANDS, :_CMDSTAN_PROCESS_LOCK, :_CMDSTAN_EXIT_HOOK)
Base.include(@__MODULE__, joinpath(ARGS[1], "src", "cmdstan_fit.jl")) do expression
    if expression isa Expr && expression.head === :const
        assignment = expression.args[1]
        assignment isa Expr && assignment.head === :(=) && assignment.args[1] in constants && return expression
    end
    signature = expression isa Expr && expression.head === :function ? expression.args[1] : nothing
    name = signature isa Expr && signature.head === :call ? signature.args[1] : nothing
    name in wanted || return nothing
    push!(selected, name)
    expression
end
@assert Tuple(selected) == wanted
Base.exit_on_sigint(false)
result = try
    _cmdstan_run(Cmd([ARGS[2], ARGS[3], ARGS[6]]), :sampling; show_output = ARGS[5] == "true")
    "ok"
catch err
    string(nameof(typeof(err)), ": ", sprint(showerror, err))
end
@assert isempty(_CMDSTAN_ACTIVE_COMMANDS)
write(ARGS[4], result)
# Keep Julia alive briefly so the parent can check that its child was reaped.
sleep(0.5)
end
'''

with tempfile.TemporaryDirectory(prefix="mgmfrm cancellation ") as temporary:
    temporary = Path(temporary)
    runner = temporary / "runner.jl"
    runner.write_text(runner_source)
    command = temporary / "command.sh"
    command.write_text('''#!/bin/sh
printf '%s' "$$" > "$1"
if [ "$2" = wait ]; then
    trap '' INT TERM
    exec /bin/sleep 30
fi
IFS= read -r input
printf 'OUT:%s\\n' "$input"
printf 'ERR:fixture\\n' >&2
exit "$2"
''')
    command.chmod(0o700)
    cases = 0
    for show_output in ("false", "true"):
        for mode in ("wait", "0", "7"):
            stem = f"{show_output}-{mode}"
            pidfile, result = temporary / f"{stem}.pid", temporary / f"{stem}.result"
            logfile = temporary / f"{stem}.log"
            child_pid = None
            with logfile.open("w") as log:
                parent = subprocess.Popen([
                    "julia", "--startup-file=no", "--history-file=no", str(runner),
                    str(root), str(command), str(pidfile), str(result), show_output, mode,
                ], stdin=subprocess.PIPE, stdout=log, stderr=log, start_new_session=True)
                try:
                    parent.stdin.write(b"fixture input\n")
                    parent.stdin.close()
                    deadline = time.monotonic() + 20
                    while (not pidfile.exists() or pidfile.stat().st_size == 0) and parent.poll() is None and time.monotonic() < deadline:
                        time.sleep(0.02)
                    assert pidfile.exists(), (parent.poll(), logfile.read_text())
                    child_pid = int(pidfile.read_text())
                    if mode == "wait":
                        os.kill(parent.pid, signal.SIGINT)  # Julia only; child ignores INT/TERM.
                    while (not result.exists() or result.stat().st_size == 0) and parent.poll() is None and time.monotonic() < deadline:
                        time.sleep(0.02)
                    assert result.exists(), (parent.poll(), logfile.read_text())
                    outcome = result.read_text()
                    try:
                        os.kill(child_pid, 0)
                        alive = True
                    except ProcessLookupError:
                        alive = False
                    assert not alive, f"direct child {child_pid} was not reaped: {outcome}"
                    child_pid = None
                    if mode == "wait":
                        assert outcome.startswith("InterruptException:"), outcome
                    elif mode == "0":
                        assert outcome == "ok", outcome
                    else:
                        assert outcome.startswith("CmdStanError: CmdStan sampling failed (command_failed)"), outcome
                        if show_output == "false":
                            assert "OUT:fixture input" in outcome and "ERR:fixture" in outcome, outcome
                    parent.wait(timeout=3)
                    assert parent.returncode == 0, logfile.read_text()
                    output = logfile.read_text()
                    if show_output == "true" and mode != "wait":
                        assert "OUT:fixture input" in output and "ERR:fixture" in output, output
                    else:
                        assert output == "", output
                    cases += 1
                finally:
                    # Reap/kill only this probe's known processes even if a regression fails a check.
                    if child_pid:
                        try:
                            os.kill(child_pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                    try:
                        parent.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        parent.kill()
                        parent.wait()
    print(f"CmdStan command lifecycle: {cases} cases passed (direct children, POSIX only)")

# Descendants keep an owned FIFO open: EOF proves exit without confusing zombies
# with running workers or consulting a sandbox-sensitive process listing.
import json
import select
import sys

with tempfile.TemporaryDirectory(prefix="mgmfrm process groups ") as temporary:
    temporary = Path(temporary)
    runner = temporary / "runner.jl"
    tree_runner = runner_source.replace('Base.exit_on_sigint(false)', '''
ARGS[7] in ("captured", "captured_group") && Base.exit_on_sigint(false)
if ARGS[7] in ("exit", "two")
    @async begin
        while !isfile(ARGS[4] * ".exit")
            sleep(0.01)
        end
        exit(23)
    end
end
''')
    tree_runner = tree_runner.replace('Cmd([ARGS[2], ARGS[3], ARGS[6]])',
        'Cmd([ARGS[2], ARGS[8], ARGS[3], ARGS[6]])')
    invocation = '_cmdstan_run(Cmd([ARGS[2], ARGS[8], ARGS[3], ARGS[6]]), :sampling; show_output = ARGS[5] == "true")'
    tree_runner = tree_runner.replace(invocation, '''if ARGS[7] == "two"
    @sync for suffix in ("a", "b")
        @async _cmdstan_run(Cmd([ARGS[2], ARGS[8], ARGS[3] * suffix, ARGS[6]]),
            :sampling; show_output = ARGS[5] == "true")
    end
else
    ''' + invocation + "\nend")
    runner.write_text(tree_runner)
    worker = temporary / "tree.py"
    worker.write_text('''import json, os, signal, subprocess, sys, time
from pathlib import Path
stem, mode = sys.argv[1:]
signal.signal(signal.SIGINT, signal.SIG_IGN)
signal.signal(signal.SIGTERM, signal.SIG_IGN)
fd = os.open(stem + ".fifo", os.O_WRONLY)
role = "worker" if mode == "worker" else "leader"
Path(stem + "." + role).write_text(json.dumps([os.getpid(), os.getpgrp()]))
os.write(fd, b"W" if role == "worker" else b"L")
if role == "worker":
    Path(stem + ".ready").touch()
    time.sleep(30)
else:
    child = subprocess.Popen([sys.executable, __file__, stem, "worker"])
    if mode in ("leave0", "leave7"):
        while not Path(stem + ".ready").exists():
            time.sleep(.01)
        raise SystemExit(0 if mode == "leave0" else 7)
    child.wait()
''')
    checked = 0
    cases = [
        (show, policy, mode)
        for show in ("false", "true")
        for policy, mode in (("captured", "wait"), ("captured_group", "wait"), ("default", "wait"),
                             ("default", "leave0"), ("default", "leave7"))
    ] + [("false", "exit", "wait"), ("false", "two", "wait")]
    for index, (show, policy, mode) in enumerate(cases):
        stem = temporary / str(index)
        fifo = str(stem) + ".fifo"
        os.mkfifo(fifo, 0o600)
        reader = os.open(fifo, os.O_RDONLY | os.O_NONBLOCK)
        if policy == "two":
            os.link(fifo, str(stem) + "a.fifo")
            os.link(fifo, str(stem) + "b.fifo")
        result = Path(str(stem) + ".result")
        logfile = Path(str(stem) + ".log")
        # A separate group must survive all command cleanup, even under SIGINT.
        sentinel = subprocess.Popen(["/bin/sleep", "30"], start_new_session=True)
        owned_groups = []
        with logfile.open("w") as log:
            parent = subprocess.Popen([
                "julia", "--startup-file=no", "--history-file=no", str(runner),
                str(root), sys.executable, str(stem), str(result), show, mode,
                policy, str(worker),
            ], stdout=log, stderr=log, start_new_session=True)
            try:
                deadline = time.monotonic() + 20
                received = b""
                while len(received) < (4 if policy == "two" else 2) and time.monotonic() < deadline:
                    select.select([reader], [], [], 0.05)
                    try:
                        received += os.read(reader, 16)
                    except BlockingIOError:
                        pass
                assert sorted(received) == sorted(b"LLWW" if policy == "two" else b"LW"), (received, logfile.read_text())
                for suffix in (("a", "b") if policy == "two" else ("",)):
                    leader = json.loads(Path(str(stem) + suffix + ".leader").read_text())
                    descendant = json.loads(Path(str(stem) + suffix + ".worker").read_text())
                    owned_group = leader[1]
                    owned_groups.append(owned_group)
                    assert leader[0] == owned_group == descendant[1], (leader, descendant)
                    assert owned_group not in (os.getpgrp(), parent.pid, sentinel.pid), owned_group
                if mode == "wait":
                    if policy in ("exit", "two"):
                        Path(str(result) + ".exit").touch()
                    elif policy == "captured_group":
                        os.killpg(parent.pid, signal.SIGINT)
                    else:
                        os.kill(parent.pid, signal.SIGINT)
                # Both the leader and descendant must close the FIFO, including
                # when the leader returned normally before its worker finished.
                while True:
                    assert time.monotonic() < deadline, (policy, mode, "worker survived", logfile.read_text())
                    readable, _, _ = select.select([reader], [], [], 0.05)
                    if readable and os.read(reader, 16) == b"":
                        break
                parent.wait(timeout=3)
                assert sentinel.poll() is None, "cleanup signalled an unrelated process group"
                if policy in ("exit", "two"):
                    assert parent.returncode == 23 and not result.exists(), (parent.returncode, logfile.read_text())
                elif mode == "wait" and policy == "default":
                    assert parent.returncode in (-signal.SIGINT, 128 + signal.SIGINT) and not result.exists(), (parent.returncode, logfile.read_text())
                else:
                    outcome = result.read_text()
                    assert parent.returncode == 0, logfile.read_text()
                    if mode == "wait":
                        assert outcome.startswith("InterruptException:"), outcome
                    elif mode == "leave0":
                        assert outcome == "ok", outcome
                    else:
                        assert "sampling failed (command_failed)" in outcome, outcome
                checked += 1
            finally:
                # Each group was created by this probe; never target its own group.
                for group in (*owned_groups, parent.pid):
                    if group is not None:
                        assert group > 1 and group != os.getpgrp()
                        try:
                            os.killpg(group, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                parent.wait(timeout=3)
                sentinel.kill()
                sentinel.wait(timeout=3)
                os.close(reader)
    print(f"CmdStan owned process groups: {checked} cases passed (descendants, script exits, unrelated group preserved)")

# Invalid PGIDs must fail before any signal is sent, including Julia's own group.
with tempfile.TemporaryDirectory(prefix="mgmfrm group guard ") as temporary:
    guard = Path(temporary) / "guard.jl"
    guard.write_text(runner_source[:runner_source.index('Base.exit_on_sigint(false)')] + r'''
process = run(`/bin/sleep 10`; wait = false)
try
    for group in (0, -1, 1, Int(ccall(:getpgrp, Cint, ())))
        failure = try
            _cmdstan_stop(process, group)
            nothing
        catch err
            err
        end
        @assert failure isa ArgumentError
        @assert process_running(process)
    end
finally
    kill(process, Base.SIGKILL)
    wait(process)
end
@assert isempty(_CMDSTAN_ACTIVE_COMMANDS)
both = CompositeException([ErrorException("original command failure"),
    ErrorException("cleanup failure")])
detail = _cmdstan_error_detail(both)
@assert occursin("original command failure", detail) && occursin("cleanup failure", detail)
@assert _cmdstan_error_detail(ErrorException("ordinary failure")) == "ordinary failure"
println("CmdStan group guard and combined-error diagnostics passed")
end
''')
    subprocess.run(["julia", "--startup-file=no", "--history-file=no", str(guard), str(root)],
                   check=True, timeout=20)
