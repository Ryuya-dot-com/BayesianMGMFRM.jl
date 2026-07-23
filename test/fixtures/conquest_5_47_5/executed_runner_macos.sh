#!/bin/sh
set -u
set -f
umask 077

fail() {
  /usr/bin/printf '%s\n' "$1" >&2
  exit "$2"
}

SCRIPT_DIR=$(CDPATH= /usr/bin/dirname -- "$0") || fail "could not resolve runner directory" 2
CDPATH= cd -P "$SCRIPT_DIR" || fail "could not enter bridge directory" 2
ROOT=$(/bin/pwd -P) || fail "could not resolve bridge directory" 2

/bin/sh "$ROOT/verify_bundle_macos.sh" || fail "Bridge input verification failed." 3

case ${CONQUEST_EXE-} in
  /*) ;;
  *) fail "Set CONQUEST_EXE to the absolute path of the licensed ConQuest console executable." 2 ;;
esac
[ -f "$CONQUEST_EXE" ] || fail "CONQUEST_EXE does not point to a regular file." 2
[ ! -L "$CONQUEST_EXE" ] || fail "CONQUEST_EXE must not be a symbolic link." 2
[ -x "$CONQUEST_EXE" ] || fail "CONQUEST_EXE is not executable." 2

unset DYLD_INSERT_LIBRARIES DYLD_LIBRARY_PATH DYLD_FRAMEWORK_PATH

LOCK="$ROOT/.bridge_execution.lock"
/bin/mkdir "$LOCK" 2>/dev/null || fail "Another bridge execution is active or a stale execution lock exists." 4

"$CONQUEST_EXE" "conquest_control.cqc" > "results/conquest_console.log" 2>&1
BRIDGE_STATUS=$?
if ! /usr/bin/printf '%s\n' "$BRIDGE_STATUS" > "results/external_exit_code.txt"; then
  fail "Could not record the ConQuest exit code; execution lock retained." 5
fi
if ! /bin/rmdir "$LOCK"; then
  fail "Could not remove the bridge execution lock." 6
fi
exit "$BRIDGE_STATUS"
