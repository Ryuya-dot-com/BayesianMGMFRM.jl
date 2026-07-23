#!/bin/sh
set -u
set -f
umask 077

fail() {
  /usr/bin/printf '%s\n' "$1" >&2
  exit 1
}

hash_file() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

check_regular_single_link() {
  checked_path=$1
  checked_description=$2
  [ -f "$checked_path" ] || fail "$checked_description is missing or not a regular file"
  [ ! -L "$checked_path" ] || fail "$checked_description must not be a symbolic link"
  checked_links=$(/usr/bin/stat -f '%l' "$checked_path") || fail "could not inspect $checked_description"
  [ "$checked_links" = 1 ] || fail "$checked_description must not be a hard link"
}

check_file() {
  relative=$1
  expected_hash=$2
  expected_bytes=$3
  candidate=$ROOT/$relative
  check_regular_single_link "$candidate" "manifested input $relative"
  actual_bytes=$(/usr/bin/stat -f '%z' "$candidate") || fail "could not inspect input length: $relative"
  [ "$actual_bytes" = "$expected_bytes" ] || fail "input byte length mismatch: $relative"
  actual_hash=$(hash_file "$candidate") || fail "could not hash input: $relative"
  [ "$actual_hash" = "$expected_hash" ] || fail "input SHA-256 mismatch: $relative"
}

SCRIPT_DIR=$(CDPATH= /usr/bin/dirname -- "$0") || fail "could not resolve verifier directory"
CDPATH= cd -P "$SCRIPT_DIR" || fail "could not enter bridge directory"
ROOT=$(/bin/pwd -P) || fail "could not resolve bridge directory"
MANIFEST=$ROOT/bridge_manifest.json
LEDGER=$ROOT/bridge_manifest.sha256
SELF=$ROOT/verify_bundle_macos.sh
LOCK=$ROOT/.bridge_execution.lock
RESULTS=$ROOT/results

[ ! -L "$0" ] || fail "macOS verifier must not be launched through a symbolic link"
check_regular_single_link "$SELF" "macOS verifier"
check_regular_single_link "$MANIFEST" "bridge manifest"
check_regular_single_link "$LEDGER" "bridge manifest hash ledger"

LEDGER_HASH=$(/usr/bin/awk '{sub(/\r$/, "", $2)} NR == 1 && NF == 2 && $2 == "bridge_manifest.json" {print $1; ok=1} END {if (NR != 1 || !ok) exit 1}' "$LEDGER") || fail "bridge_manifest.sha256 has an invalid record"
printf '%s\n' "$LEDGER_HASH" | /usr/bin/grep -Eq '^[0-9a-f]{64}$' || fail "bridge manifest SHA-256 has an invalid format"
ACTUAL_MANIFEST_HASH=$(hash_file "$MANIFEST") || fail "could not hash bridge manifest"
[ "$ACTUAL_MANIFEST_HASH" = "$LEDGER_HASH" ] || fail "bridge manifest SHA-256 mismatch"

printf '%s\n' "${BRIDGE_BUNDLE_ID-}" | /usr/bin/grep -Eq '^sha256:[0-9a-f]{64}$' || fail "Set BRIDGE_BUNDLE_ID to the separately retained bundle_id"
BUNDLE_MATCH_COUNT=$(/usr/bin/grep -Eo '"bundle_id":"sha256:[0-9a-f]{64}"' "$MANIFEST" | /usr/bin/wc -l | /usr/bin/tr -d '[:space:]')
[ "$BUNDLE_MATCH_COUNT" = 1 ] || fail "bridge manifest must contain exactly one canonical bundle_id field"
MANIFEST_BUNDLE_ID=$(/usr/bin/sed -nE 's/.*"bundle_id":"(sha256:[0-9a-f]{64})".*/\1/p' "$MANIFEST")
ZERO_ID=sha256:0000000000000000000000000000000000000000000000000000000000000000
RECOMPUTED_HASH=$(/usr/bin/sed -E "s/\"bundle_id\":\"sha256:[0-9a-f]{64}\"/\"bundle_id\":\"$ZERO_ID\"/" "$MANIFEST" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')
RECOMPUTED_BUNDLE_ID=sha256:$RECOMPUTED_HASH
[ "$MANIFEST_BUNDLE_ID" = "$RECOMPUTED_BUNDLE_ID" ] || fail "bridge bundle_id does not match the complete manifest contract"
[ "$MANIFEST_BUNDLE_ID" = "$BRIDGE_BUNDLE_ID" ] || fail "bridge bundle_id does not match BRIDGE_BUNDLE_ID"

/usr/bin/grep -Fq '"schema":"bayesianmgmfrm.external_software_bridge_bundle.v1"' "$MANIFEST" || fail "bridge manifest schema is unsupported"
/usr/bin/grep -Fq '"object":"external_software_bridge_bundle"' "$MANIFEST" || fail "bridge manifest object is unsupported"
/usr/bin/grep -Fq '"software":"conquest"' "$MANIFEST" || fail "macOS verifier requires a ConQuest bundle"

check_file 'README.txt' '964be412953f0a501d06a77ed5338e2de2c949f1eba8ea790110f8bb4399849c' 4311
check_file 'conquest_control.cqc' '24be10d062a0b02235561a80e8d46785e2996a7d3412f64a29884f671b3312a0' 1325
check_file 'conquest_ratings.csv' '9bb698796ecc38c7b5cd7b30c5e74cc0dcee5f3609cd2aceced382d3e6ab9280' 38914
check_file 'id_map.tsv' '74f700fcd4d19e60d559f31cdff851d4e40ddc68a433b5d38be5f2ec1aff262a' 10736
check_file 'category_map.tsv' 'aba70bae99977f5315528a4672f5d8da1ca2449c3e57e1f0356f2960af6f8795' 83
check_file 'observation_map.tsv' 'aa4eb02589eae5a75c7893fb7a4ddd433fbf031883ed78dc1cc9d72a16425a23' 65756
check_file 'verify_bundle_windows.ps1' 'f64351b4899d256202b838fb13f101a2a3acfebe89709e3a720793b0b8b1efc7' 4672
check_file 'run_conquest_windows.cmd' 'fff3a9e2e3da950451cd164223b80690cb595387dc8a97e3002ee5859ef77764' 881
check_file 'run_conquest_macos.sh' 'd490c42465270dc2ae1528e3ad0c8fc3e1ee7657f3259b7392856a680916ccfb' 1368

for ENTRY in "$ROOT"/* "$ROOT"/.[!.]* "$ROOT"/..?*; do
  [ -e "$ENTRY" ] || [ -L "$ENTRY" ] || continue
  NAME=${ENTRY##*/}
  case "$NAME" in
    bridge_manifest.json|bridge_manifest.sha256|verify_bundle_macos.sh|results|README.txt|conquest_control.cqc|conquest_ratings.csv|id_map.tsv|category_map.tsv|observation_map.tsv|verify_bundle_windows.ps1|run_conquest_windows.cmd|run_conquest_macos.sh) ;;
    *) fail "bridge directory contains an undeclared entry: $NAME" ;;
  esac
done

[ ! -e "$LOCK" ] && [ ! -L "$LOCK" ] || fail "an external bridge execution lock already exists; use a fresh bundle copy"
if [ -e "$RESULTS" ] || [ -L "$RESULTS" ]; then
  [ -d "$RESULTS" ] || fail "results exists and is not a directory"
  [ ! -L "$RESULTS" ] || fail "results directory must not be a symbolic link"
  FIRST_RESULT=$(/usr/bin/find "$RESULTS" -mindepth 1 -maxdepth 1 -print -quit) || fail "could not inspect results directory"
  [ -z "$FIRST_RESULT" ] || fail "results must be empty before external execution"
else
  /bin/mkdir "$RESULTS" || fail "could not create results directory"
fi

/usr/bin/printf '%s\n' 'Bridge input verification passed.'
exit 0
