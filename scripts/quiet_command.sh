#!/bin/sh
# Usage: sh scripts/quiet_command.sh COMMAND [ARG ...]
# Display only; no retries, timeouts, or changes to the command's arguments.
if [ "$#" -eq 0 ]; then
    printf 'Usage: sh scripts/quiet_command.sh COMMAND [ARG ...]\n' >&2
    exit 2
fi
command_log=$(mktemp "${TMPDIR:-/tmp}/quiet-command.XXXXXX") || exit 125
"$@" >"$command_log" 2>&1
command_status=$?
if [ "$command_status" -eq 0 ]; then
    printf 'PASS: %s (log: %s)\n' "${1##*/}" "$command_log"
else
    printf 'FAIL: %s (exit %s; full log: %s)\n' "${1##*/}" "$command_status" "$command_log" >&2
    tail -n 80 "$command_log" >&2
fi
exit "$command_status"
