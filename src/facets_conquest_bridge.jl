# facets_conquest_bridge.jl -- licensed-host interchange for minimal MFRM fits.

using Dates
using JSON3
using SHA

const _EXTERNAL_BRIDGE_SCHEMA =
    "bayesianmgmfrm.external_software_bridge_bundle.v1"
const _EXTERNAL_BRIDGE_RECEIPT_SCHEMA =
    "bayesianmgmfrm.external_software_bridge_result_receipt.v1"
const _EXTERNAL_BRIDGE_SHA256 = r"^[0-9a-f]{64}$"
const _EXTERNAL_BRIDGE_ID = r"^sha256:[0-9a-f]{64}$"
const _EXTERNAL_BRIDGE_ID_SENTINEL = string("sha256:", repeat("0", 64))
const _EXTERNAL_BRIDGE_UTC =
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
const _CONQUEST_RESPONSE_CODES = collect('A':'Z')
const _EXTERNAL_BRIDGE_STREAM_CHUNK_BYTES = 64 * 1024
const _EXTERNAL_BRIDGE_FATAL_SCAN_OVERLAP = 512
const _EXTERNAL_BRIDGE_EXIT_CODE_MAX_BYTES = 64
const _CONQUEST_PARAMETER_LINE_MAX_BYTES = 4096
const _CONQUEST_PARAMETER_PAIR_MAX = 1_000_000
const _CONQUEST_DESIGN_MATRIX_LINE_MAX_BYTES = 16 * 1024 * 1024
const _CONQUEST_DESIGN_MATRIX_ROW_MAX = 10_000_000
const _CONQUEST_SEMANTIC_ADAPTER_ID =
    :conquest_5_47_5_three_category_mfrm_rsm_pcm_v1
const _CONQUEST_SEMANTIC_SUPPORTED_VERSION = "5.47.5"
const _CONQUEST_SEMANTIC_SUPPORTED_VERSION_REPORTS = (
    "5.47.5",
    "ConQuest 5.47.5",
    "ConQuest 5.47.5 Demonstration Version",
)
const _CONQUEST_PARAMETER_ROW =
    r"^([0-9]+)[\t ]+([+-]?(?:(?:[0-9]+(?:\.[0-9]*)?)|(?:\.[0-9]+))(?:[eE][+-]?[0-9]+)?)(?:[\t ]+/\*((?:(?!/\*|\*/)[^\r\n])*)\*/)?$"

_external_bridge_spec(spec::FacetSpec) = spec
_external_bridge_spec(design::FacetDesign) = design.spec
_external_bridge_spec(fit::MFRMFit) = fit.design.spec

function _external_bridge_sha256(content::AbstractString)
    return bytes2hex(sha256(codeunits(content)))
end

function _external_bridge_sha256_bytes(bytes)
    return bytes2hex(sha256(bytes))
end

function _external_bridge_sha256_file(path::AbstractString)
    return open(path, "r") do io
        bytes2hex(sha256(io))
    end
end

function _external_bridge_require_single_link(path::AbstractString,
        description::AbstractString)
    stat(path).nlink == 1 ||
        throw(ArgumentError("$description must not be a hard link"))
    return nothing
end

function _external_bridge_relative_path(path::AbstractString)
    value = replace(String(path), '\\' => '/')
    isempty(value) && throw(ArgumentError("bridge file path must not be empty"))
    startswith(value, "/") &&
        throw(ArgumentError("bridge file path must be relative: $value"))
    occursin(r"^[A-Za-z]:", value) &&
        throw(ArgumentError("bridge file path must not contain a drive prefix: $value"))
    '\0' in value && throw(ArgumentError("bridge file path contains a null byte"))
    parts = split(value, '/'; keepempty = true)
    any(part -> isempty(part) || part in (".", ".."), parts) &&
        throw(ArgumentError("bridge file path must be normalized: $value"))
    portable_normpath = replace(normpath(value), '\\' => '/')
    portable_normpath == value ||
        throw(ArgumentError("bridge file path must be normalized: $value"))
    return value
end

function _external_bridge_title(title)
    title isa AbstractString ||
        throw(ArgumentError("bridge title must be a string"))
    value = String(title)
    isempty(value) && throw(ArgumentError("bridge title must not be empty"))
    ncodeunits(value) <= 96 ||
        throw(ArgumentError("bridge title must be at most 96 ASCII bytes"))
    all(isascii, value) ||
        throw(ArgumentError("bridge title must be ASCII for portable control files"))
    occursin(r"^[A-Za-z0-9][A-Za-z0-9 ._()/-]*$", value) ||
        throw(ArgumentError(
            "bridge title may contain only ASCII letters, digits, spaces, '.', '_', '-', '/', and parentheses"))
    return value
end

function _external_bridge_validate_spec(spec::FacetSpec, software::Symbol)
    software in (:facets, :conquest) ||
        throw(ArgumentError("software must be :facets or :conquest"))
    spec.family === :mfrm ||
        throw(ArgumentError("the external bridge supports only family = :mfrm"))
    spec.dimensions == 1 ||
        throw(ArgumentError("the external bridge supports only one dimension"))
    spec.discrimination === :none ||
        throw(ArgumentError("the external bridge does not compile discrimination terms"))
    isempty(spec.validation_bias_terms) ||
        throw(ArgumentError("the external bridge does not compile fitted bias or interaction terms"))
    isempty(spec.anchors) ||
        throw(ArgumentError(
            "version 1 exports an unanchored calibration only; construct anchors after the returned parameter identity has been checked"))
    spec.estimation_status === :fit_supported ||
        throw(ArgumentError("the external bridge requires a fit-supported minimal MFRM specification"))
    spec.validation.passed ||
        throw(ArgumentError("the external bridge requires a passing design validation report"))
    data = spec.data
    data.n > 0 || throw(ArgumentError("the external bridge requires at least one rating"))
    length(data.category_levels) >= 2 ||
        throw(ArgumentError("the external bridge requires at least two ordered categories"))
    length(data.category_levels) <= 256 ||
        throw(ArgumentError("the external bridge supports at most 256 categories"))
    return spec
end

function _external_bridge_code(prefix::Char, index::Int, nlevels::Int)
    width = max(6, ndigits(max(nlevels, 1)))
    width <= 10 ||
        throw(ArgumentError("bridge identifiers are limited to ten numeric digits"))
    return string(prefix, lpad(index, width, '0'))
end

function _external_bridge_codes(data::FacetData)
    persons = [_external_bridge_code('P', i, length(data.person_levels))
        for i in eachindex(data.person_levels)]
    raters = [_external_bridge_code('R', i, length(data.rater_levels))
        for i in eachindex(data.rater_levels)]
    items = [_external_bridge_code('I', i, length(data.item_levels))
        for i in eachindex(data.item_levels)]
    return (; persons, raters, items)
end

function _external_bridge_label_hash(value)
    return bytes2hex(sha256(codeunits(_cache_stable_string(value))))
end

function _external_bridge_id_map(data::FacetData, codes;
        include_original_labels::Bool)
    lines = String[
        "facet\telement_number\tbridge_id\tcanonical_label_sha256\toriginal_label_json",
    ]
    for (facet, levels, bridge_codes) in (
            (:person, data.person_levels, codes.persons),
            (:rater, data.rater_levels, codes.raters),
            (:item, data.item_levels, codes.items))
        for index in eachindex(levels)
            original = include_original_labels ?
                JSON3.write(_json_export_value(levels[index])) : ""
            push!(lines, join((
                String(facet),
                index,
                bridge_codes[index],
                _external_bridge_label_hash(levels[index]),
                original,
            ), '\t'))
        end
    end
    return string(join(lines, "\n"), "\n")
end

function _external_bridge_category_map(data::FacetData;
        response_codes = nothing)
    lines = String[
        "category_index\toriginal_score\texternal_score\tresponse_code",
    ]
    for index in eachindex(data.category_levels)
        response_code = response_codes === nothing ? "" : string(response_codes[index])
        push!(lines, join((
            index,
            data.category_levels[index],
            index - 1,
            response_code,
        ), '\t'))
    end
    return string(join(lines, "\n"), "\n")
end

function _external_bridge_row_order(data::FacetData)
    return sort(collect(1:data.n); by = row -> (data.person[row], row))
end

function _external_bridge_observation_map(data::FacetData, order, codes;
        response_codes = nothing)
    lines = String[
        "external_row\tsource_row\tperson_number\trater_number\titem_number\tbridge_person\tbridge_rater\tbridge_item\toriginal_score\texternal_score\tresponse_code",
    ]
    for (external_row, source_row) in pairs(order)
        category = data.category[source_row]
        response_code = response_codes === nothing ? "" : string(response_codes[category])
        push!(lines, join((
            external_row,
            source_row,
            data.person[source_row],
            data.rater[source_row],
            data.item[source_row],
            codes.persons[data.person[source_row]],
            codes.raters[data.rater[source_row]],
            codes.items[data.item[source_row]],
            data.score[source_row],
            category - 1,
            response_code,
        ), '\t'))
    end
    return string(join(lines, "\n"), "\n")
end

function _external_bridge_file(path::AbstractString, role::Symbol,
        content::AbstractString)
    checked_path = _external_bridge_relative_path(path)
    text = String(content)
    return (;
        path = checked_path,
        role,
        content = text,
        nbytes = sizeof(text),
        sha256 = _external_bridge_sha256(text),
    )
end

function _external_bridge_inventory(files)
    return Tuple((;
        path = file.path,
        role = file.role,
        nbytes = file.nbytes,
        sha256 = file.sha256,
    ) for file in files)
end

function _external_bridge_host_preflight(bundle_id::AbstractString, inventory)
    verifiers = filter(record -> record.role === :input_verifier, inventory)
    runners = filter(record -> record.role === :windows_runner, inventory)
    length(verifiers) == 1 ||
        throw(ArgumentError("bridge manifest must declare one Windows input verifier"))
    length(runners) == 1 ||
        throw(ArgumentError("bridge manifest must declare one Windows runner"))
    verifier = only(verifiers)
    runner = only(runners)
    common = (;
        bundle_id = String(bundle_id),
        verifier = (; path = verifier.path, sha256 = verifier.sha256),
        runner = (; path = runner.path, sha256 = runner.sha256),
        independent_operator_comparison_required = true,
        transfer_contained_launcher_is_trust_anchor = false,
        adversarial_transfer_protection_claimed = false,
    )
    macos_verifiers = filter(
        record -> record.role === :macos_input_verifier, inventory)
    macos_runners = filter(record -> record.role === :macos_runner, inventory)
    if isempty(macos_verifiers) && isempty(macos_runners)
        return common
    end
    length(macos_verifiers) == 1 ||
        throw(ArgumentError(
            "ConQuest bridge manifest must declare one macOS input verifier"))
    length(macos_runners) == 1 ||
        throw(ArgumentError("ConQuest bridge manifest must declare one macOS runner"))
    macos_verifier = only(macos_verifiers)
    macos_runner = only(macos_runners)
    return merge(common, (;
        macos_verifier = (;
            path = macos_verifier.path,
            sha256 = macos_verifier.sha256,
        ),
        macos_runner = (;
            path = macos_runner.path,
            sha256 = macos_runner.sha256,
        ),
    ))
end

function _external_bridge_bundle_id(manifest_json::AbstractString)
    text = String(manifest_json)
    pattern = r"\"bundle_id\":\"sha256:[0-9a-f]{64}\""
    matches = collect(eachmatch(pattern, text))
    length(matches) == 1 ||
        throw(ArgumentError(
            "bridge manifest must contain exactly one canonical bundle_id field"))
    sentinel_field = string("\"bundle_id\":\"",
        _EXTERNAL_BRIDGE_ID_SENTINEL, "\"")
    normalized = replace(text, matches[1].match => sentinel_field; count = 1)
    return string("sha256:", _external_bridge_sha256(normalized))
end

function _external_bridge_powershell()
    text = raw"""$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ManifestPath = Join-Path $Root "bridge_manifest.json"
$LedgerPath = Join-Path $Root "bridge_manifest.sha256"
$LockPath = Join-Path $Root ".bridge_execution.lock"

function Assert-NotReparsePoint {
    param([string]$Path, [string]$Description)
    $Item = Get-Item -LiteralPath $Path -Force
    if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Description must not be a reparse point"
    }
}

Assert-NotReparsePoint $Root "bridge directory"

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "bridge_manifest.json is missing"
}
if (-not (Test-Path -LiteralPath $LedgerPath -PathType Leaf)) {
    throw "bridge_manifest.sha256 is missing"
}
Assert-NotReparsePoint $ManifestPath "bridge manifest"
Assert-NotReparsePoint $LedgerPath "bridge manifest hash ledger"

$LedgerFields = (Get-Content -LiteralPath $LedgerPath -Raw).Trim() -split '\s+'
if ($LedgerFields.Count -ne 2 -or $LedgerFields[1] -ne 'bridge_manifest.json') {
    throw "bridge_manifest.sha256 has an invalid record"
}
$ExpectedManifestHash = [string]$LedgerFields[0]
if ($ExpectedManifestHash -notmatch '^[0-9a-f]{64}$') {
    throw "bridge manifest SHA-256 has an invalid format"
}
$ActualManifestHash = (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($ExpectedManifestHash.ToLowerInvariant() -ne $ActualManifestHash) {
    throw "bridge manifest SHA-256 mismatch"
}

$Utf8Strict = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false, $true)
$ManifestText = $Utf8Strict.GetString([IO.File]::ReadAllBytes($ManifestPath))
$Manifest = $ManifestText | ConvertFrom-Json
$ExpectedBundleId = [string]$env:BRIDGE_BUNDLE_ID
if ($ExpectedBundleId -notmatch '^sha256:[0-9a-f]{64}$') {
    throw "Set BRIDGE_BUNDLE_ID to the bundle_id retained on the originating machine"
}

$BundleIdPattern = '"bundle_id":"sha256:[0-9a-f]{64}"'
$BundleIdMatches = [regex]::Matches($ManifestText, $BundleIdPattern)
if ($BundleIdMatches.Count -ne 1) {
    throw "bridge manifest must contain exactly one canonical bundle_id field"
}
$SentinelField = '"bundle_id":"sha256:' + ('0' * 64) + '"'
$NormalizedManifest = [regex]::Replace(
    $ManifestText, $BundleIdPattern, $SentinelField)
$Hasher = [Security.Cryptography.SHA256]::Create()
try {
    $NormalizedBytes = [Text.Encoding]::UTF8.GetBytes($NormalizedManifest)
    $DigestBytes = $Hasher.ComputeHash($NormalizedBytes)
} finally {
    $Hasher.Dispose()
}
$RecomputedBundleId = 'sha256:' +
    ([BitConverter]::ToString($DigestBytes).Replace('-', '').ToLowerInvariant())
if ([string]$Manifest.bundle_id -ne $RecomputedBundleId) {
    throw "bridge bundle_id does not match the complete manifest contract"
}
if ([string]$Manifest.bundle_id -ne $ExpectedBundleId) {
    throw "bridge bundle_id does not match BRIDGE_BUNDLE_ID"
}

foreach ($Entry in $Manifest.input_files) {
    $Relative = [string]$Entry.path
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "unsafe manifest path: $Relative"
    }
    $Path = Join-Path $Root ($Relative -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "manifested input is missing: $Relative"
    }
    Assert-NotReparsePoint $Path "manifested input $Relative"
    $ActualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($ActualHash -ne ([string]$Entry.sha256).ToLowerInvariant()) {
        throw "input SHA-256 mismatch: $Relative"
    }
    $ActualLength = (Get-Item -LiteralPath $Path).Length
    if ($ActualLength -ne [int64]$Entry.nbytes) {
        throw "input byte length mismatch: $Relative"
    }
}

$ResultsPath = Join-Path $Root "results"
if (Test-Path -LiteralPath $LockPath) {
    throw "an external bridge execution lock already exists; use a fresh bundle copy"
}
if (Test-Path -LiteralPath $ResultsPath) {
    if (-not (Test-Path -LiteralPath $ResultsPath -PathType Container)) {
        throw "results exists and is not a directory"
    }
    Assert-NotReparsePoint $ResultsPath "results directory"
    $ResultEntryCount = (Get-ChildItem -LiteralPath $ResultsPath -Force |
        Measure-Object).Count
    if ($ResultEntryCount -ne 0) {
        throw "results must be empty before external execution"
    }
} else {
    New-Item -ItemType Directory -Path $ResultsPath | Out-Null
}

Write-Host "Bridge input verification passed."
exit 0
"""
    return replace(text, "\n" => "\r\n")
end

function _external_bridge_shell_single_quote(value::AbstractString)
    return string("'", replace(String(value), "'" => "'\\''"), "'")
end

function _external_bridge_macos_verifier(files)
    allowed_names = String[
        "bridge_manifest.json",
        "bridge_manifest.sha256",
        "verify_bundle_macos.sh",
        "results",
    ]
    append!(allowed_names, (file.path for file in files))
    any(name -> '/' in name, allowed_names) &&
        throw(ArgumentError(
            "macOS bridge verifier currently requires root-level input files"))
    allowed_pattern = join(allowed_names, '|')

    lines = String[
        "#!/bin/sh",
        "set -u",
        "set -f",
        "umask 077",
        "",
        "fail() {",
        "  /usr/bin/printf '%s\\n' \"\$1\" >&2",
        "  exit 1",
        "}",
        "",
        "hash_file() {",
        "  /usr/bin/shasum -a 256 \"\$1\" | /usr/bin/awk '{print \$1}'",
        "}",
        "",
        "check_regular_single_link() {",
        "  checked_path=\$1",
        "  checked_description=\$2",
        "  [ -f \"\$checked_path\" ] || fail \"\$checked_description is missing or not a regular file\"",
        "  [ ! -L \"\$checked_path\" ] || fail \"\$checked_description must not be a symbolic link\"",
        "  checked_links=\$(/usr/bin/stat -f '%l' \"\$checked_path\") || fail \"could not inspect \$checked_description\"",
        "  [ \"\$checked_links\" = 1 ] || fail \"\$checked_description must not be a hard link\"",
        "}",
        "",
        "check_file() {",
        "  relative=\$1",
        "  expected_hash=\$2",
        "  expected_bytes=\$3",
        "  candidate=\$ROOT/\$relative",
        "  check_regular_single_link \"\$candidate\" \"manifested input \$relative\"",
        "  actual_bytes=\$(/usr/bin/stat -f '%z' \"\$candidate\") || fail \"could not inspect input length: \$relative\"",
        "  [ \"\$actual_bytes\" = \"\$expected_bytes\" ] || fail \"input byte length mismatch: \$relative\"",
        "  actual_hash=\$(hash_file \"\$candidate\") || fail \"could not hash input: \$relative\"",
        "  [ \"\$actual_hash\" = \"\$expected_hash\" ] || fail \"input SHA-256 mismatch: \$relative\"",
        "}",
        "",
        "SCRIPT_DIR=\$(CDPATH= /usr/bin/dirname -- \"\$0\") || fail \"could not resolve verifier directory\"",
        "CDPATH= cd -P \"\$SCRIPT_DIR\" || fail \"could not enter bridge directory\"",
        "ROOT=\$(/bin/pwd -P) || fail \"could not resolve bridge directory\"",
        "MANIFEST=\$ROOT/bridge_manifest.json",
        "LEDGER=\$ROOT/bridge_manifest.sha256",
        "SELF=\$ROOT/verify_bundle_macos.sh",
        "LOCK=\$ROOT/.bridge_execution.lock",
        "RESULTS=\$ROOT/results",
        "",
        "[ ! -L \"\$0\" ] || fail \"macOS verifier must not be launched through a symbolic link\"",
        "check_regular_single_link \"\$SELF\" \"macOS verifier\"",
        "check_regular_single_link \"\$MANIFEST\" \"bridge manifest\"",
        "check_regular_single_link \"\$LEDGER\" \"bridge manifest hash ledger\"",
        "",
        "LEDGER_HASH=\$(/usr/bin/awk '{sub(/\\r\$/, \"\", \$2)} NR == 1 && NF == 2 && \$2 == \"bridge_manifest.json\" {print \$1; ok=1} END {if (NR != 1 || !ok) exit 1}' \"\$LEDGER\") || fail \"bridge_manifest.sha256 has an invalid record\"",
        "printf '%s\\n' \"\$LEDGER_HASH\" | /usr/bin/grep -Eq '^[0-9a-f]{64}\$' || fail \"bridge manifest SHA-256 has an invalid format\"",
        "ACTUAL_MANIFEST_HASH=\$(hash_file \"\$MANIFEST\") || fail \"could not hash bridge manifest\"",
        "[ \"\$ACTUAL_MANIFEST_HASH\" = \"\$LEDGER_HASH\" ] || fail \"bridge manifest SHA-256 mismatch\"",
        "",
        "printf '%s\\n' \"\${BRIDGE_BUNDLE_ID-}\" | /usr/bin/grep -Eq '^sha256:[0-9a-f]{64}\$' || fail \"Set BRIDGE_BUNDLE_ID to the separately retained bundle_id\"",
        "BUNDLE_MATCH_COUNT=\$(/usr/bin/grep -Eo '\"bundle_id\":\"sha256:[0-9a-f]{64}\"' \"\$MANIFEST\" | /usr/bin/wc -l | /usr/bin/tr -d '[:space:]')",
        "[ \"\$BUNDLE_MATCH_COUNT\" = 1 ] || fail \"bridge manifest must contain exactly one canonical bundle_id field\"",
        "MANIFEST_BUNDLE_ID=\$(/usr/bin/sed -nE 's/.*\"bundle_id\":\"(sha256:[0-9a-f]{64})\".*/\\1/p' \"\$MANIFEST\")",
        "ZERO_ID=sha256:0000000000000000000000000000000000000000000000000000000000000000",
        "RECOMPUTED_HASH=\$(/usr/bin/sed -E \"s/\\\"bundle_id\\\":\\\"sha256:[0-9a-f]{64}\\\"/\\\"bundle_id\\\":\\\"\$ZERO_ID\\\"/\" \"\$MANIFEST\" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print \$1}')",
        "RECOMPUTED_BUNDLE_ID=sha256:\$RECOMPUTED_HASH",
        "[ \"\$MANIFEST_BUNDLE_ID\" = \"\$RECOMPUTED_BUNDLE_ID\" ] || fail \"bridge bundle_id does not match the complete manifest contract\"",
        "[ \"\$MANIFEST_BUNDLE_ID\" = \"\$BRIDGE_BUNDLE_ID\" ] || fail \"bridge bundle_id does not match BRIDGE_BUNDLE_ID\"",
        "",
        "/usr/bin/grep -Fq '\"schema\":\"$(_EXTERNAL_BRIDGE_SCHEMA)\"' \"\$MANIFEST\" || fail \"bridge manifest schema is unsupported\"",
        "/usr/bin/grep -Fq '\"object\":\"external_software_bridge_bundle\"' \"\$MANIFEST\" || fail \"bridge manifest object is unsupported\"",
        "/usr/bin/grep -Fq '\"software\":\"conquest\"' \"\$MANIFEST\" || fail \"macOS verifier requires a ConQuest bundle\"",
        "",
    ]
    for file in files
        push!(lines, string(
            "check_file ", _external_bridge_shell_single_quote(file.path), " ",
            _external_bridge_shell_single_quote(file.sha256), " ", file.nbytes))
    end
    append!(lines, [
        "",
        "for ENTRY in \"\$ROOT\"/* \"\$ROOT\"/.[!.]* \"\$ROOT\"/..?*; do",
        "  [ -e \"\$ENTRY\" ] || [ -L \"\$ENTRY\" ] || continue",
        "  NAME=\${ENTRY##*/}",
        "  case \"\$NAME\" in",
        "    $allowed_pattern) ;;",
        "    *) fail \"bridge directory contains an undeclared entry: \$NAME\" ;;",
        "  esac",
        "done",
        "",
        "[ ! -e \"\$LOCK\" ] && [ ! -L \"\$LOCK\" ] || fail \"an external bridge execution lock already exists; use a fresh bundle copy\"",
        "if [ -e \"\$RESULTS\" ] || [ -L \"\$RESULTS\" ]; then",
        "  [ -d \"\$RESULTS\" ] || fail \"results exists and is not a directory\"",
        "  [ ! -L \"\$RESULTS\" ] || fail \"results directory must not be a symbolic link\"",
        "  FIRST_RESULT=\$(/usr/bin/find \"\$RESULTS\" -mindepth 1 -maxdepth 1 -print -quit) || fail \"could not inspect results directory\"",
        "  [ -z \"\$FIRST_RESULT\" ] || fail \"results must be empty before external execution\"",
        "else",
        "  /bin/mkdir \"\$RESULTS\" || fail \"could not create results directory\"",
        "fi",
        "",
        "/usr/bin/printf '%s\\n' 'Bridge input verification passed.'",
        "exit 0",
    ])
    return string(join(lines, "\n"), "\n")
end

function _conquest_macos_runner()
    return raw"""#!/bin/sh
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
"""
end

function _facets_runner()
    text = raw"""@echo off
setlocal
pushd "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "verify_bundle_windows.ps1"
if errorlevel 1 (
  echo Bridge input verification failed.
  popd
  exit /b 3
)

if not defined FACETS_EXE (
  echo Set FACETS_EXE to the licensed FACETS executable path.
  popd
  exit /b 2
)
if not exist "%FACETS_EXE%" (
  echo FACETS_EXE does not point to a file.
  popd
  exit /b 2
)
if not exist "results" mkdir "results"
mkdir ".bridge_execution.lock" 2>nul
if errorlevel 1 (
  echo Another bridge execution is active or a stale execution lock exists.
  popd
  exit /b 4
)

"%FACETS_EXE%" BATCH=YES "facets_control.txt" "results\facets_report.txt" > "results\facets_console.log" 2>&1
set "BRIDGE_STATUS=%ERRORLEVEL%"
> "results\external_exit_code.txt" echo %BRIDGE_STATUS%
rmdir ".bridge_execution.lock" 2>nul

popd
exit /b %BRIDGE_STATUS%
"""
    return replace(text, "\n" => "\r\n")
end

function _conquest_runner()
    text = raw"""@echo off
setlocal
pushd "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "verify_bundle_windows.ps1"
if errorlevel 1 (
  echo Bridge input verification failed.
  popd
  exit /b 3
)

if not defined CONQUEST_EXE (
  echo Set CONQUEST_EXE to the licensed ConQuest console executable path.
  popd
  exit /b 2
)
if not exist "%CONQUEST_EXE%" (
  echo CONQUEST_EXE does not point to a file.
  popd
  exit /b 2
)
if not exist "results" mkdir "results"
mkdir ".bridge_execution.lock" 2>nul
if errorlevel 1 (
  echo Another bridge execution is active or a stale execution lock exists.
  popd
  exit /b 4
)

"%CONQUEST_EXE%" "conquest_control.cqc" > "results\conquest_console.log" 2>&1
set "BRIDGE_STATUS=%ERRORLEVEL%"
> "results\external_exit_code.txt" echo %BRIDGE_STATUS%
rmdir ".bridge_execution.lock" 2>nul

popd
exit /b %BRIDGE_STATUS%
"""
    return replace(text, "\n" => "\r\n")
end

function _facets_data(spec::FacetSpec, order)
    data = spec.data
    lines = String[]
    for row in order
        push!(lines, join((
            data.person[row],
            data.rater[row],
            data.item[row],
            data.category[row] - 1,
        ), ','))
    end
    return string(join(lines, "\r\n"), "\r\n")
end

function _facets_labels(title::AbstractString, levels, prefix::Char)
    lines = String[title]
    nlevels = length(levels)
    for index in eachindex(levels)
        push!(lines, string(index, "=",
            _external_bridge_code(prefix, index, nlevels)))
    end
    push!(lines, "*")
    return lines
end

function _facets_control(spec::FacetSpec, title::AbstractString)
    data = spec.data
    max_category = length(data.category_levels) - 1
    model = spec.thresholds === :rating_scale ?
        string("?,?,?,R", max_category, "K") :
        string("?,?,#,R", max_category, "K")
    lines = String[
        string("Title=", title),
        "Facets=3",
        "Positive=1",
        "Noncenter=1",
        "Batch=Yes",
        string("Models=", model),
        "Labels=",
    ]
    append!(lines, _facets_labels("1,Persons", data.person_levels, 'P'))
    append!(lines, _facets_labels("2,Raters", data.rater_levels, 'R'))
    append!(lines, _facets_labels("3,Items", data.item_levels, 'I'))
    append!(lines, [
        "CSV=Tab",
        "Heading lines=Yes",
        "Anchorfile=results\\facets_anchors.txt",
        "Scorefile=results\\facets_scores",
        "Residualfile=results\\facets_residuals.txt",
        "Graphfile=results\\facets_graph.txt",
        "Data=facets_data.dat",
    ])
    return string(join(lines, "\r\n"), "\r\n")
end

function _external_bridge_has_full_extremes(categories, n_categories::Int)
    observed = Set(categories)
    return 1 in observed && n_categories in observed
end

function _facets_validate_categories(spec::FacetSpec)
    data = spec.data
    n_categories = length(data.category_levels)
    _external_bridge_has_full_extremes(data.category, n_categories) ||
        throw(ArgumentError(
            "FACETS bridge requires the lowest and highest declared categories to be observed"))
    if spec.thresholds === :partial_credit
        for item in eachindex(data.item_levels)
            rows = findall(==(item), data.item)
            _external_bridge_has_full_extremes(
                data.category[rows], n_categories) ||
                throw(ArgumentError(
                    "FACETS PCM bridge requires both declared category extremes for item index $item"))
        end
    end
    return nothing
end

function _conquest_validate_cells(spec::FacetSpec)
    data = spec.data
    seen = Dict{Tuple{Int,Int,Int},Int}()
    generalized_item_categories = Dict{Tuple{Int,Int},Set{Int}}()
    duplicates = Tuple{Int,Int,Int}[]
    for row in 1:data.n
        key = (data.person[row], data.item[row], data.rater[row])
        if haskey(seen, key)
            push!(duplicates, key)
        else
            seen[key] = row
        end
        generalized_item = (data.rater[row], data.item[row])
        push!(get!(generalized_item_categories, generalized_item, Set{Int}()),
            data.category[row])
    end
    isempty(duplicates) ||
        throw(ArgumentError(
            "ConQuest bridge found repeated person-item-rater cells; add an explicit occasion model before exporting repeated ratings"))

    n_categories = length(data.category_levels)
    for ((rater, item), categories) in generalized_item_categories
        _external_bridge_has_full_extremes(categories, n_categories) ||
            throw(ArgumentError(
                "ConQuest bridge requires the lowest and highest declared categories in every observed rater-item generalized item; coverage fails for rater index $rater and item index $item"))
    end

    if spec.thresholds === :partial_credit
        for item in eachindex(data.item_levels)
            observed = sort!(unique(data.category[findall(==(item), data.item)] .- 1))
            isempty(observed) && continue
            observed == collect(first(observed):last(observed)) ||
                throw(ArgumentError(
                    "ConQuest PCM bridge found an unobserved category between the minimum and maximum score for item $(data.item_levels[item])"))
        end
    end
    return nothing
end

function _conquest_data(spec::FacetSpec, order, codes, response_codes)
    data = spec.data
    lines = String["personid,itemid,raterid,response"]
    for row in order
        push!(lines, join((
            codes.persons[data.person[row]],
            codes.items[data.item[row]],
            codes.raters[data.rater[row]],
            response_codes[data.category[row]],
        ), ','))
    end
    return string(join(lines, "\r\n"), "\r\n")
end

function _conquest_control(spec::FacetSpec, title::AbstractString,
        codes, response_codes)
    pidwidth = maximum(ncodeunits, codes.persons)
    keepswidth = max(maximum(ncodeunits, codes.items),
        maximum(ncodeunits, codes.raters))
    code_list = join(response_codes, ',')
    score_list = join(0:(length(response_codes) - 1), ',')
    model = spec.thresholds === :rating_scale ?
        "raterid + itemid + step" :
        "raterid + itemid + itemid*step"
    lines = String[
        string("title ", title, ";"),
        "set lconstraints=items,seed=2,storecommands=yes,exit_on_error=yes,addextension=no;",
        "datafile conquest_ratings.csv",
        "  ! filetype=csv,",
        "    responses=response,",
        "    pid=personid,",
        "    keeps=itemid raterid,",
        "    width=1,",
        string("    pidwidth=", pidwidth, ","),
        string("    keepswidth=", keepswidth, ","),
        "    header=yes",
        "  >> results/conquest_input_snapshot.txt;",
        string("codes ", code_list, ";"),
        string("score (", code_list, ") (", score_list, ");"),
        string("model ", model, ";"),
        "export logfile >> results/conquest_estimation.log;",
        "estimate ! method=gauss,nodes=20,convergence=0.0001,stderr=empirical,fit=yes,pfit=yes;",
        "export parameters >> results/conquest_parameters.txt;",
        "export covariance >> results/conquest_population_covariance.txt;",
        "export designmatrix ! filetype=csv >> results/conquest_designmatrix.csv;",
        "export labels >> results/conquest_labels.txt;",
        "export history >> results/conquest_history.txt;",
        "export threshold ! filetype=csv >> results/conquest_thresholds.csv;",
        "show parameters ! tables=1:2:3:5:10,labelled=yes,estimates=wle >> results/conquest_show_parameters.txt;",
        "show cases ! estimates=wle,pfit=yes,filetype=csv >> results/conquest_cases_wle.csv;",
        "show residuals ! estimates=wle,filetype=csv >> results/conquest_residuals.csv;",
        "itanal ! estimates=wle,format=export >> results/conquest_itanal_export.txt;",
        "chistory >> results/conquest_commands.txt;",
        "quit;",
    ]
    return string(join(lines, "\r\n"), "\r\n")
end

function _external_bridge_manual_sources(software::Symbol)
    if software === :facets
        return (
            "https://www.winsteps.com/a/Facets64-Manual.pdf",
            "https://www.winsteps.com/facetman64/models.htm",
            "https://www.winsteps.com/facetman64/noncenter.htm",
            "https://www.winsteps.com/facetman64/labels.htm",
            "https://www.winsteps.com/facetman64/scoreoutput.htm",
            "https://www.winsteps.com/facetman64/graphoutputfile.htm",
            "https://www.winsteps.com/facetman64/residualsoutputfile.htm",
            "https://www.winsteps.com/facetman64/anchoroutputfile.htm",
            "https://www.winsteps.com/facetman/batchyes.htm",
        )
    end
    return (
        "https://conquestmanual.acer.org/index.html",
        "https://conquestmanual.acer.org/s2-00.html",
        "https://conquestmanual.acer.org/s3-00.html",
        "https://conquestmanual.acer.org/s4-00.html",
    )
end

function _external_bridge_expected_outputs(software::Symbol)
    if software === :facets
        return (
            (path = "results/external_exit_code.txt", role = :process_exit_code,
                required = true, allow_empty = false),
            (path = "results/facets_console.log", role = :console_log,
                required = true, allow_empty = true),
            (path = "results/facets_report.txt", role = :facets_report,
                required = true, allow_empty = false),
            (path = "results/facets_anchors.txt", role = :facets_anchor_output,
                required = true, allow_empty = false),
            (path = "results/facets_scores.1.txt", role = :person_score_file,
                required = true, allow_empty = false),
            (path = "results/facets_scores.2.txt", role = :rater_score_file,
                required = true, allow_empty = false),
            (path = "results/facets_scores.3.txt", role = :item_score_file,
                required = true, allow_empty = false),
            (path = "results/facets_residuals.txt", role = :residual_output,
                required = true, allow_empty = false),
            (path = "results/facets_graph.txt", role = :category_graph_output,
                required = true, allow_empty = false),
        )
    end
    return (
        (path = "results/external_exit_code.txt", role = :process_exit_code,
            required = true, allow_empty = false),
        (path = "results/conquest_console.log", role = :console_log,
            required = true, allow_empty = true),
        (path = "results/conquest_input_snapshot.txt", role = :parsed_input_snapshot,
            required = true, allow_empty = false),
        (path = "results/conquest_estimation.log", role = :estimation_log,
            required = true, allow_empty = false),
        (path = "results/conquest_parameters.txt", role = :parameter_pairs,
            required = true, allow_empty = false),
        (path = "results/conquest_population_covariance.txt",
            role = :population_covariance, required = true, allow_empty = false),
        (path = "results/conquest_designmatrix.csv", role = :design_matrix,
            required = true, allow_empty = false),
        (path = "results/conquest_labels.txt", role = :conquest_labels,
            required = true, allow_empty = true),
        (path = "results/conquest_history.txt", role = :estimation_history,
            required = true, allow_empty = false),
        (path = "results/conquest_thresholds.csv", role = :threshold_output,
            required = true, allow_empty = false),
        (path = "results/conquest_show_parameters.txt", role = :parameter_report,
            required = true, allow_empty = false),
        (path = "results/conquest_cases_wle.csv", role = :case_estimates,
            required = true, allow_empty = false),
        (path = "results/conquest_residuals.csv", role = :residual_output,
            required = true, allow_empty = false),
        (path = "results/conquest_itanal_export.txt", role = :item_analysis,
            required = true, allow_empty = false),
        (path = "results/conquest_commands.txt", role = :command_history,
            required = true, allow_empty = false),
    )
end

function _external_bridge_readme(software::Symbol, spec::FacetSpec,
        bundle_title::AbstractString; include_original_labels::Bool)
    software_name = software === :facets ? "FACETS" : "ACER ConQuest"
    executable_variable = software === :facets ? "FACETS_EXE" : "CONQUEST_EXE"
    host_runner_note = if software === :conquest
        "On Windows, run run_conquest_windows.cmd from Command Prompt. On macOS, run /bin/sh run_conquest_macos.sh from Terminal; the shell script intentionally does not change quarantine attributes, re-sign files, or disable Gatekeeper."
    else
        "Run run_facets_windows.cmd from a Windows command prompt."
    end
    estimator = software === :facets ?
        "FACETS JMLE/UCON estimation" :
        "ConQuest marginal maximum likelihood with Gauss-Hermite integration"
    raw_label_note = include_original_labels ?
        "id_map.tsv includes original labels as JSON values and unsalted deterministic SHA-256 hashes of their canonical representations. This bundle is not anonymized." :
        "id_map.tsv omits original labels and retains unsalted deterministic SHA-256 hashes of their canonical representations. This is pseudonymization, not anonymization: guessable labels can be dictionary matched and equal canonical labels can be linked across bundles."
    text = """
$bundle_title

Purpose
-------
This bundle was generated on a machine without executing $software_name. It
contains a manual-syntax control file, ASCII-safe identifiers, row-level rating
data, input hashes, host runner scripts, and a declared return-file contract.
The licensed executable and its licence are not included.

Model boundary
--------------
Target: one-dimensional additive MFRM with $(spec.thresholds === :rating_scale ? "shared rating-scale steps" : "item-specific partial-credit steps").
External estimator: $estimator.
Weights, fitted interactions, additional likelihood facets, and anchors are not
compiled by this version. The category map records the conversion from the
source scores to external scores 0:(K-1). FACETS PCM requires both declared
category endpoints within every item; FACETS RSM requires them in the data as a
whole. ConQuest requires both endpoints within every observed rater-item
generalized item and rejects item-level PCM category holes. These checks prevent
an observed category range from silently changing the likelihood denominator.
$raw_label_note

Run on the licensed host
------------------------
1. On the originating machine, retain bundle_id plus the verifier and runner
   SHA-256 values returned in host_preflight through a separate trusted channel.
2. Copy this directory without changing its files.
3. Before running anything from the bundle, independently compare the verifier
   and runner with those retained hashes using a trusted host-side hash tool.
4. Set $executable_variable to the full path of the licensed console executable.
5. Set BRIDGE_BUNDLE_ID to the bundle_id retained separately on the originating
   machine. Do not copy this value from a modified transfer manifest. It is an
   integrity reference, not a secret or a digital signature.
6. $host_runner_note The results directory must be absent or empty; use a fresh
   copy for every execution attempt.
7. Record the product-reported version, executable SHA-256, and UTC execution
   time outside this directory. Do not add notes under results.
8. Keep this directory and its results subdirectory together when returning it.
9. On the originating machine, call validate_external_bridge_bundle and then
   external_bridge_result_receipt with the original bundle_id.

After the independent runner/verifier hash comparison, the runner checks
bridge_manifest.json and every manifested input with SHA-256, recomputes the
full manifest identity, checks the separately supplied BRIDGE_BUNDLE_ID, and
requires an empty results directory before launching the external program. It
writes the process exit code and console output into results. Without the
independent comparison, a transfer-contained launcher is not a trust anchor and
protects against accidental corruption only, not hostile transfer.

On macOS, invoke the generated runner from a normal Terminal session. Sandboxed
IDE or automation hosts can prevent ConQuest from writing its per-user registry
state. Approve the exact ACER executable through macOS Privacy & Security only
after independently confirming its source; never disable Gatekeeper globally.

Interpretation boundary
-----------------------
A complete return receipt proves input continuity and binds the returned raw
file snapshot to hashes. It records operator-reported completion but does not
independently prove that the executable ran, or prove software authenticity,
convergence, correct parameter labels, equal estimators, or numerical agreement.
FACETS/ConQuest estimates must be aligned to the declared sign and gauge before comparison.
For ConQuest anchors, first return the unanchored parameter export, labelled
parameter table, design matrix, and labels; only then resolve semantic targets
to the parameter numbers used by that exact design.
"""
    return replace(strip(text), "\n" => "\r\n") * "\r\n"
end

function _external_bridge_model_target(spec::FacetSpec, software::Symbol)
    source_identification = software === :facets ? (;
        person = :noncentered,
        rater = :centered,
        item = :centered,
    ) : (;
        location_constraints = :items,
        latent_distribution = :marginal,
    )
    category_universe_contract = if software === :conquest
        :declared_extremes_observed_per_rater_item_generalized_item
    elseif spec.thresholds === :partial_credit
        :declared_extremes_observed_per_item
    else
        :declared_extremes_observed_globally
    end
    return (;
        family = :mfrm,
        dimensions = 1,
        threshold_regime = spec.thresholds,
        destination_identification = (;
            person = :free_with_proper_prior,
            rater = :reference_first,
            item = :reference_first,
            thresholds = :sum_to_zero,
        ),
        source_identification,
        sign = (;
            person = :ability_positive,
            rater = :severity_positive,
            item = :difficulty_positive,
        ),
        weighting = :unit,
        anchors = :none,
        category_mapping = :ordered_to_zero_based,
        category_universe_contract,
    )
end

function _external_bridge_build(spec_or_design, software::Symbol;
        title,
        include_original_labels::Bool)
    spec = _external_bridge_validate_spec(
        _external_bridge_spec(spec_or_design), software)
    checked_title = _external_bridge_title(title)
    data = spec.data
    codes = _external_bridge_codes(data)
    order = _external_bridge_row_order(data)
    response_codes = software === :conquest ? begin
        length(data.category_levels) <= length(_CONQUEST_RESPONSE_CODES) ||
            throw(ArgumentError(
                "ConQuest bridge version 1 supports at most $(length(_CONQUEST_RESPONSE_CODES)) categories"))
        _CONQUEST_RESPONSE_CODES[eachindex(data.category_levels)]
    end : nothing

    if software === :conquest
        _conquest_validate_cells(spec)
    else
        _facets_validate_categories(spec)
    end
    id_map = _external_bridge_id_map(data, codes;
        include_original_labels)
    category_map = _external_bridge_category_map(data; response_codes)
    observation_map = _external_bridge_observation_map(
        data, order, codes; response_codes)
    powershell = _external_bridge_powershell()
    readme = _external_bridge_readme(software, spec, checked_title;
        include_original_labels)

    files = if software === :facets
        (
            _external_bridge_file("README.txt", :instructions, readme),
            _external_bridge_file("facets_control.txt", :control_file,
                _facets_control(spec, checked_title)),
            _external_bridge_file("facets_data.dat", :rating_data,
                _facets_data(spec, order)),
            _external_bridge_file("id_map.tsv", :identifier_map, id_map),
            _external_bridge_file("category_map.tsv", :category_map, category_map),
            _external_bridge_file("observation_map.tsv", :observation_map,
                observation_map),
            _external_bridge_file("verify_bundle_windows.ps1", :input_verifier,
                powershell),
            _external_bridge_file("run_facets_windows.cmd", :windows_runner,
                _facets_runner()),
        )
    else
        base_files = (
            _external_bridge_file("README.txt", :instructions, readme),
            _external_bridge_file("conquest_control.cqc", :control_file,
                _conquest_control(spec, checked_title, codes, response_codes)),
            _external_bridge_file("conquest_ratings.csv", :rating_data,
                _conquest_data(spec, order, codes, response_codes)),
            _external_bridge_file("id_map.tsv", :identifier_map, id_map),
            _external_bridge_file("category_map.tsv", :category_map, category_map),
            _external_bridge_file("observation_map.tsv", :observation_map,
                observation_map),
            _external_bridge_file("verify_bundle_windows.ps1", :input_verifier,
                powershell),
            _external_bridge_file("run_conquest_windows.cmd", :windows_runner,
                _conquest_runner()),
            _external_bridge_file("run_conquest_macos.sh", :macos_runner,
                _conquest_macos_runner()),
        )
        (
            base_files...,
            _external_bridge_file("verify_bundle_macos.sh",
                :macos_input_verifier,
                _external_bridge_macos_verifier(base_files)),
        )
    end

    inventory = _external_bridge_inventory(files)
    model_target = _external_bridge_model_target(spec, software)
    expected_outputs = _external_bridge_expected_outputs(software)
    manifest_template = (;
        schema = _EXTERNAL_BRIDGE_SCHEMA,
        object = :external_software_bridge_bundle,
        bundle_id = _EXTERNAL_BRIDGE_ID_SENTINEL,
        software,
        title = checked_title,
        status = :ready_for_licensed_host_execution,
        model_target,
        data = (;
            n_ratings = data.n,
            n_persons = length(data.person_levels),
            n_raters = length(data.rater_levels),
            n_items = length(data.item_levels),
            n_categories = length(data.category_levels),
            row_order = :grouped_by_person_then_source_row,
            rows_added = 0,
            rows_removed = 0,
        ),
        privacy = (;
            row_level_ratings_included = true,
            original_labels_included = include_original_labels,
            canonical_label_hashes_included = true,
            label_hash_input = :canonical_label_representation_v1,
            label_hashes_are_unsalted = true,
            label_hashes_are_pseudonymous = true,
            anonymization_claimed = false,
            dictionary_resistance_claimed = false,
            generated_ascii_identifiers_used = true,
        ),
        execution = (;
            performed = false,
            executable_included = false,
            licence_included = false,
            target_host = :licensed_external_host,
            windows_runner_included = true,
            macos_runner_included = software === :conquest,
        ),
        evidence_boundary = (;
            manual_syntax_compiled = true,
            external_execution_completed = false,
            raw_return_integrity_verified = false,
            host_bootstrap_authentication_verified = false,
            adversarial_transfer_protection_claimed = false,
            windows_powershell_5_execution_validated = false,
            semantic_parameter_adapter_validated = false,
            numerical_comparison_allowed = false,
            software_equivalence_claimed = false,
        ),
        manual_sources = _external_bridge_manual_sources(software),
        input_files = inventory,
        expected_outputs,
    )
    template_json = string(JSON3.write(manifest_template), "\n")
    bundle_id = _external_bridge_bundle_id(template_json)
    manifest = merge(manifest_template, (; bundle_id))
    manifest_json = string(JSON3.write(manifest), "\n")
    manifest_hash = _external_bridge_sha256(manifest_json)
    all_files = (
        files...,
        _external_bridge_file("bridge_manifest.json", :bridge_manifest,
            manifest_json),
        _external_bridge_file("bridge_manifest.sha256", :manifest_hash_ledger,
            string(manifest_hash, "  bridge_manifest.json\r\n")),
    )
    host_preflight = _external_bridge_host_preflight(bundle_id, inventory)
    return (;
        schema = _EXTERNAL_BRIDGE_SCHEMA,
        object = :external_software_bridge_bundle,
        bundle_id,
        software,
        status = :ready_for_licensed_host_execution,
        external_execution_completed = false,
        host_preflight,
        manifest,
        files = all_files,
    )
end

"""
    facets_bridge_bundle(spec_or_design;
        title = "BayesianMGMFRM FACETS overlap bridge",
        include_original_labels = false)

Compile a portable, unanchored FACETS input bundle for the fit-supported
one-dimensional MFRM/RSM/PCM model. The bundle contains a manual-syntax control
file, rating data, generated ASCII identifiers, category and observation maps,
SHA-256 manifests, and a Windows runner. It never launches FACETS and never
includes an executable or licence. Retain the returned `host_preflight` bundle
ID and runner/verifier hashes through a separate trusted channel; transferred
scripts are not their own trust anchor.

Original labels are omitted by default; unsalted deterministic hashes of their
canonical representations remain in `id_map.tsv`. This is pseudonymization, not
anonymization: guessable labels can be dictionary matched and equal canonical
labels can be linked across bundles. Set
`include_original_labels = true` only when the transfer host is authorized to
receive those labels. Row-level ratings are always present and should be handled
as sensitive data. Both declared category endpoints must occur globally; PCM
items must also contain both endpoints so the external category universe cannot
silently narrow.
"""
function facets_bridge_bundle(spec_or_design;
        title = "BayesianMGMFRM FACETS overlap bridge",
        include_original_labels::Bool = false)
    return _external_bridge_build(spec_or_design, :facets;
        title, include_original_labels)
end

"""
    conquest_bridge_bundle(spec_or_design;
        title = "BayesianMGMFRM ConQuest overlap bridge",
        include_original_labels = false)

Compile a portable, unanchored ACER ConQuest input bundle for the fit-supported
one-dimensional MFRM/RSM/PCM model. Sparse ratings remain one row per observed
rating; ConQuest's documented `pid` mapping links rows belonging to the same
person. The generated command uses MML with Gauss-Hermite integration. The
bundle includes a Windows verifier/runner and a macOS verifier/runner; neither
path supplies ConQuest itself.

Repeated person-item-rater cells, rater-item generalized items without both
declared category endpoints, and PCM category holes are rejected because they
would need a more explicit external model contract. This function does not run
ConQuest and does not include an executable or licence. Canonical-label hashes
are unsalted pseudonyms, not an anonymization mechanism; row-level ratings
remain sensitive. Retain the bundle ID and platform-specific verifier/runner
hashes from `host_preflight` through a separate trusted channel before
transfer.
"""
function conquest_bridge_bundle(spec_or_design;
        title = "BayesianMGMFRM ConQuest overlap bridge",
        include_original_labels::Bool = false)
    return _external_bridge_build(spec_or_design, :conquest;
        title, include_original_labels)
end

function _external_bridge_bundle_fields(bundle)
    bundle isa NamedTuple ||
        throw(ArgumentError("bridge bundle must be returned by facets_bridge_bundle or conquest_bridge_bundle"))
    haskey(bundle, :schema) && bundle.schema == _EXTERNAL_BRIDGE_SCHEMA ||
        throw(ArgumentError("bridge bundle has an unsupported schema"))
    haskey(bundle, :object) && bundle.object === :external_software_bridge_bundle ||
        throw(ArgumentError("object is not an external software bridge bundle"))
    haskey(bundle, :bundle_id) &&
        occursin(_EXTERNAL_BRIDGE_ID, String(bundle.bundle_id)) ||
        throw(ArgumentError("bridge bundle_id is invalid"))
    haskey(bundle, :files) || throw(ArgumentError("bridge bundle has no files"))
    return bundle
end

function _external_bridge_check_file_record(file)
    file isa NamedTuple || throw(ArgumentError("bridge file record must be a named tuple"))
    path = _external_bridge_relative_path(file.path)
    content = String(file.content)
    sizeof(content) == file.nbytes ||
        throw(ArgumentError("bridge file byte length is inconsistent for $path"))
    actual = _external_bridge_sha256(content)
    actual == file.sha256 ||
        throw(ArgumentError("bridge file SHA-256 is inconsistent for $path"))
    return path
end

function _external_bridge_preflight_bundle(bundle, paths)
    files_by_path = Dict{String,Any}()
    for file in bundle.files
        path = _external_bridge_relative_path(file.path)
        files_by_path[path] = file
    end
    Set(keys(files_by_path)) == Set(paths) ||
        throw(ArgumentError("bridge bundle file paths are inconsistent"))
    for required in ("bridge_manifest.json", "bridge_manifest.sha256")
        haskey(files_by_path, required) ||
            throw(ArgumentError("bridge bundle is missing $required"))
    end

    manifest_file = files_by_path["bridge_manifest.json"]
    ledger_file = files_by_path["bridge_manifest.sha256"]
    manifest_file.role === :bridge_manifest ||
        throw(ArgumentError("bridge manifest file role is invalid"))
    ledger_file.role === :manifest_hash_ledger ||
        throw(ArgumentError("bridge manifest hash ledger role is invalid"))
    manifest_text = String(manifest_file.content)
    manifest = try
        JSON3.read(manifest_text, Dict{String,Any})
    catch err
        throw(ArgumentError(
            "could not parse in-memory bridge manifest: $(sprint(showerror, err))"))
    end
    get(manifest, "schema", nothing) == _EXTERNAL_BRIDGE_SCHEMA ||
        throw(ArgumentError("in-memory bridge manifest schema is unsupported"))
    get(manifest, "object", nothing) == "external_software_bridge_bundle" ||
        throw(ArgumentError("in-memory bridge manifest object is unsupported"))
    software = _external_bridge_software(get(manifest, "software", ""))
    _external_bridge_threshold_regime(manifest)
    inventory = _external_bridge_manifest_inventory(manifest)
    _external_bridge_manifest_expected_outputs(manifest)

    manifest_bundle_id = String(get(manifest, "bundle_id", ""))
    occursin(_EXTERNAL_BRIDGE_ID, manifest_bundle_id) ||
        throw(ArgumentError("in-memory bridge manifest bundle_id is invalid"))
    _external_bridge_bundle_id(manifest_text) == manifest_bundle_id ||
        throw(ArgumentError(
            "in-memory bridge bundle_id does not match the complete manifest contract"))
    String(bundle.bundle_id) == manifest_bundle_id ||
        throw(ArgumentError("bridge bundle_id does not match its serialized manifest"))
    haskey(bundle, :software) && bundle.software === software ||
        throw(ArgumentError("bridge software does not match its serialized manifest"))
    haskey(bundle, :manifest) ||
        throw(ArgumentError("bridge bundle has no in-memory manifest"))
    string(JSON3.write(bundle.manifest), "\n") == manifest_text ||
        throw(ArgumentError(
            "bridge in-memory manifest does not match bridge_manifest.json"))
    expected_host_preflight = _external_bridge_host_preflight(
        manifest_bundle_id, inventory)
    haskey(bundle, :host_preflight) &&
        bundle.host_preflight == expected_host_preflight ||
        throw(ArgumentError(
            "bridge host_preflight does not match its serialized inputs"))

    input_paths = Set(record.path for record in inventory)
    serialized_input_paths = Set(paths)
    delete!(serialized_input_paths, "bridge_manifest.json")
    delete!(serialized_input_paths, "bridge_manifest.sha256")
    input_paths == serialized_input_paths ||
        throw(ArgumentError(
            "bridge serialized files do not match the manifest input inventory"))
    for record in inventory
        file = files_by_path[record.path]
        file.role === record.role ||
            throw(ArgumentError("bridge input role mismatch: $(record.path)"))
        file.nbytes == record.nbytes ||
            throw(ArgumentError("bridge input byte length mismatch: $(record.path)"))
        file.sha256 == record.sha256 ||
            throw(ArgumentError("bridge input SHA-256 mismatch: $(record.path)"))
    end

    ledger_fields = split(strip(String(ledger_file.content)))
    length(ledger_fields) == 2 &&
        ledger_fields[2] == "bridge_manifest.json" ||
        throw(ArgumentError("in-memory bridge manifest hash ledger is invalid"))
    occursin(_EXTERNAL_BRIDGE_SHA256, ledger_fields[1]) ||
        throw(ArgumentError("in-memory bridge manifest SHA-256 is invalid"))
    ledger_fields[1] == _external_bridge_sha256(manifest_text) ||
        throw(ArgumentError("in-memory bridge manifest SHA-256 mismatch"))
    return nothing
end

function _external_bridge_validate_overwrite_root(root::AbstractString, paths)
    allowed_files = Set(paths)
    allowed_directories = Set{String}(["results"])
    for path in paths
        parts = split(replace(path, '\\' => '/'), '/')
        for last_index in 1:(length(parts) - 1)
            push!(allowed_directories, join(parts[1:last_index], '/'))
        end
    end

    results = joinpath(root, "results")
    if ispath(results)
        islink(results) &&
            throw(ArgumentError("bridge results entry must not be a symbolic link"))
        isdir(results) ||
            throw(ArgumentError("bridge results entry exists and is not a directory"))
        isempty(readdir(results)) ||
            throw(ArgumentError(
                "bridge directory contains external results; write a new bundle to a fresh directory"))
    end

    for (directory, subdirectories, names) in walkdir(root;
            follow_symlinks = false)
        for subdirectory in subdirectories
            candidate = joinpath(directory, subdirectory)
            islink(candidate) &&
                throw(ArgumentError("bridge overwrite source must not contain symbolic links"))
            relative = replace(relpath(candidate, root), '\\' => '/')
            relative in allowed_directories ||
                throw(ArgumentError(
                    "bridge overwrite source contains an undeclared directory: $relative"))
        end
        for name in names
            candidate = joinpath(directory, name)
            islink(candidate) &&
                throw(ArgumentError("bridge overwrite source must not contain symbolic links"))
            relative = replace(relpath(candidate, root), '\\' => '/')
            relative in allowed_files ||
                throw(ArgumentError(
                    "bridge overwrite source contains an undeclared file: $relative"))
            isfile(candidate) ||
                throw(ArgumentError(
                    "bridge overwrite source contains a non-regular file: $relative"))
            _external_bridge_require_single_link(
                candidate, "existing bridge file at $relative")
        end
    end
    return nothing
end

"""
    save_external_bridge_bundle(directory, bundle; overwrite = false)

Write a bundle returned by [`facets_bridge_bundle`](@ref) or
[`conquest_bridge_bundle`](@ref) to a transfer directory. Existing files are
protected unless `overwrite = true`. Overwrite accepts only an unexecuted
directory whose existing paths are declared by the new bundle; `results` must be
absent or empty. Every written input is verified before the function returns.
Writing to a fresh directory is preferred because overwrite is preflight-safe
but not an atomic recovery mechanism for an interrupted filesystem write.
"""
function save_external_bridge_bundle(directory::AbstractString, bundle;
        overwrite::Bool = false)
    checked = _external_bridge_bundle_fields(bundle)
    paths = String[]
    for file in checked.files
        path = _external_bridge_check_file_record(file)
        path in paths && throw(ArgumentError("duplicate bridge file path: $path"))
        push!(paths, path)
    end
    _external_bridge_preflight_bundle(checked, paths)

    root = abspath(normpath(String(directory)))
    islink(root) && throw(ArgumentError("bridge directory must not be a symbolic link"))
    if isdir(root)
        !overwrite && !isempty(readdir(root)) &&
            throw(ArgumentError(
                "bridge directory is not empty; pass overwrite = true only for an unexecuted bundle"))
        overwrite && _external_bridge_validate_overwrite_root(root, paths)
    elseif ispath(root)
        throw(ArgumentError("bridge destination exists and is not a directory"))
    end

    mkpath(root)
    for file in checked.files
        target = joinpath(root, split(file.path, '/')...)
        target_root = dirname(target)
        mkpath(target_root)
        islink(target) &&
            throw(ArgumentError("refusing to overwrite symbolic link at $(file.path)"))
        isfile(target) && _external_bridge_require_single_link(
            target, "existing bridge file at $(file.path)")
        isfile(target) && !overwrite &&
            throw(ArgumentError("bridge file already exists at $(file.path)"))
        open(target, "w") do io
            write(io, file.content)
        end
    end
    return validate_external_bridge_bundle(root;
        expected_bundle_id = checked.bundle_id)
end

function _external_bridge_json_dict(path::AbstractString)
    try
        return JSON3.read(read(path, String), Dict{String,Any})
    catch err
        throw(ArgumentError(
            "could not parse bridge manifest at $path: $(sprint(showerror, err))"))
    end
end

function _external_bridge_manifest_hash(directory::AbstractString)
    manifest_path = joinpath(directory, "bridge_manifest.json")
    ledger_path = joinpath(directory, "bridge_manifest.sha256")
    islink(manifest_path) &&
        throw(ArgumentError("bridge manifest must not be a symbolic link"))
    islink(ledger_path) &&
        throw(ArgumentError("bridge manifest hash ledger must not be a symbolic link"))
    isfile(manifest_path) || throw(ArgumentError("bridge_manifest.json is missing"))
    isfile(ledger_path) || throw(ArgumentError("bridge_manifest.sha256 is missing"))
    _external_bridge_require_single_link(manifest_path, "bridge manifest")
    _external_bridge_require_single_link(ledger_path, "bridge manifest hash ledger")
    ledger = strip(read(ledger_path, String))
    fields = split(ledger)
    length(fields) == 2 && fields[2] == "bridge_manifest.json" ||
        throw(ArgumentError("bridge_manifest.sha256 has an invalid record"))
    occursin(_EXTERNAL_BRIDGE_SHA256, fields[1]) ||
        throw(ArgumentError("bridge manifest SHA-256 has an invalid format"))
    actual = _external_bridge_sha256_bytes(read(manifest_path))
    actual == fields[1] ||
        throw(ArgumentError("bridge manifest SHA-256 mismatch"))
    return (; manifest_path, sha256 = actual)
end

function _external_bridge_manifest_inventory(manifest)
    haskey(manifest, "input_files") ||
        throw(ArgumentError("bridge manifest has no input_files inventory"))
    records = manifest["input_files"]
    records isa AbstractVector ||
        throw(ArgumentError("bridge input_files inventory must be an array"))
    out = NamedTuple[]
    seen = Set{String}()
    for record in records
        record isa AbstractDict ||
            throw(ArgumentError("bridge input file record must be an object"))
        for field in ("path", "role", "nbytes", "sha256")
            haskey(record, field) ||
                throw(ArgumentError("bridge input file record is missing $field"))
        end
        path = _external_bridge_relative_path(String(record["path"]))
        startswith(path, "results/") &&
            throw(ArgumentError("bridge inputs must not be placed inside results/: $path"))
        path in ("bridge_manifest.json", "bridge_manifest.sha256") &&
            throw(ArgumentError("bridge input inventory uses a reserved path: $path"))
        path in seen && throw(ArgumentError("duplicate bridge input path: $path"))
        push!(seen, path)
        role = Symbol(String(record["role"]))
        nbytes = record["nbytes"]
        nbytes isa Integer && nbytes >= 0 ||
            throw(ArgumentError("bridge input nbytes is invalid for $path"))
        hash = String(record["sha256"])
        occursin(_EXTERNAL_BRIDGE_SHA256, hash) ||
            throw(ArgumentError("bridge input SHA-256 is invalid for $path"))
        push!(out, (; path, role, nbytes = Int(nbytes), sha256 = hash))
    end
    isempty(out) && throw(ArgumentError("bridge input inventory is empty"))
    return Tuple(out)
end

function _external_bridge_manifest_expected_outputs(manifest)
    haskey(manifest, "expected_outputs") ||
        throw(ArgumentError("bridge manifest has no expected_outputs contract"))
    records = manifest["expected_outputs"]
    records isa AbstractVector ||
        throw(ArgumentError("bridge expected_outputs must be an array"))
    out = NamedTuple[]
    seen = Set{String}()
    for record in records
        record isa AbstractDict ||
            throw(ArgumentError("bridge expected output record must be an object"))
        for field in ("path", "role", "required")
            haskey(record, field) ||
                throw(ArgumentError(
                    "bridge expected output record is missing $field"))
        end
        path = _external_bridge_relative_path(String(record["path"]))
        startswith(path, "results/") ||
            throw(ArgumentError("bridge output must be inside results/: $path"))
        path in seen && throw(ArgumentError("duplicate bridge output path: $path"))
        push!(seen, path)
        role = Symbol(String(record["role"]))
        required = record["required"]
        required isa Bool ||
            throw(ArgumentError("bridge expected output required flag is invalid for $path"))
        allow_empty = if haskey(record, "allow_empty")
            value = record["allow_empty"]
            value isa Bool ||
                throw(ArgumentError(
                    "bridge expected output allow_empty flag is invalid for $path"))
            value
        else
            # Bundles created before the explicit flag allowed only an empty
            # console log. New ConQuest bundles explicitly opt the labels
            # export into the zero-byte allowance, so an old manifest cannot
            # gain a broader output contract during validation.
            role === :console_log
        end
        push!(out, (;
            path,
            role,
            required,
            allow_empty,
        ))
    end
    return Tuple(out)
end

function _external_bridge_software(value)
    software = Symbol(String(value))
    software in (:facets, :conquest) ||
        throw(ArgumentError("bridge manifest software is unsupported"))
    return software
end

function _external_bridge_threshold_regime(manifest)
    target = get(manifest, "model_target", nothing)
    target isa AbstractDict ||
        throw(ArgumentError("bridge manifest has no model_target object"))
    regime = Symbol(String(get(target, "threshold_regime", "")))
    regime in (:rating_scale, :partial_credit) ||
        throw(ArgumentError("bridge threshold regime is unsupported"))
    return regime
end

function _external_bridge_validate_saved_entries(root::AbstractString, inventory)
    allowed_files = Set(record.path for record in inventory)
    push!(allowed_files, "bridge_manifest.json", "bridge_manifest.sha256")
    allowed_directories = Set{String}(["results"])
    for path in allowed_files
        parts = split(path, '/')
        for last_index in 1:(length(parts) - 1)
            push!(allowed_directories, join(parts[1:last_index], '/'))
        end
    end

    for (directory, subdirectories, names) in walkdir(root;
            topdown = true, follow_symlinks = false)
        for subdirectory in subdirectories
            candidate = joinpath(directory, subdirectory)
            islink(candidate) &&
                throw(ArgumentError("bridge directories must not be symbolic links"))
            relative = replace(relpath(candidate, root), '\\' => '/')
            relative in allowed_directories ||
                throw(ArgumentError("bridge directory contains an undeclared directory: $relative"))
        end
        for name in names
            candidate = joinpath(directory, name)
            islink(candidate) &&
                throw(ArgumentError("bridge files must not be symbolic links"))
            relative = replace(relpath(candidate, root), '\\' => '/')
            relative in allowed_files ||
                throw(ArgumentError("bridge directory contains an undeclared file: $relative"))
            isfile(candidate) ||
                throw(ArgumentError("bridge entry is not a regular file: $relative"))
            _external_bridge_require_single_link(candidate, "bridge file $relative")
        end
        if directory == root
            filter!(subdirectory -> subdirectory != "results", subdirectories)
        end
    end
    return nothing
end

"""
    validate_external_bridge_bundle(directory; expected_bundle_id = nothing)

Verify the manifest hash, full manifest-contract identity, normalized relative
paths, and SHA-256/byte length of every input in a saved external-software
bundle. Undeclared entries outside `results/` are rejected. Pass the `bundle_id`
retained on the originating machine as
`expected_bundle_id` when validating a directory returned from another host.
The returned `host_preflight` contains runner/verifier hashes for an independent
comparison before any transferred script is executed.

This checks transfer integrity only. It does not execute FACETS or ConQuest and
does not validate returned estimates.
"""
function validate_external_bridge_bundle(directory::AbstractString;
        expected_bundle_id = nothing)
    root = abspath(normpath(String(directory)))
    isdir(root) || throw(ArgumentError("bridge directory does not exist"))
    islink(root) && throw(ArgumentError("bridge directory must not be a symbolic link"))
    manifest_hash = _external_bridge_manifest_hash(root)
    manifest = _external_bridge_json_dict(manifest_hash.manifest_path)
    get(manifest, "schema", nothing) == _EXTERNAL_BRIDGE_SCHEMA ||
        throw(ArgumentError("bridge manifest schema is unsupported"))
    get(manifest, "object", nothing) == "external_software_bridge_bundle" ||
        throw(ArgumentError("bridge manifest object is unsupported"))
    software = _external_bridge_software(get(manifest, "software", ""))
    threshold_regime = _external_bridge_threshold_regime(manifest)
    inventory = _external_bridge_manifest_inventory(manifest)
    bundle_id = String(get(manifest, "bundle_id", ""))
    occursin(_EXTERNAL_BRIDGE_ID, bundle_id) ||
        throw(ArgumentError("bridge manifest bundle_id is invalid"))
    recomputed = _external_bridge_bundle_id(read(manifest_hash.manifest_path, String))
    recomputed == bundle_id ||
        throw(ArgumentError(
            "bridge bundle_id does not match the complete manifest contract"))
    if expected_bundle_id !== nothing
        expected = String(expected_bundle_id)
        occursin(_EXTERNAL_BRIDGE_ID, expected) ||
            throw(ArgumentError("expected_bundle_id has an invalid format"))
        bundle_id == expected ||
            throw(ArgumentError("returned bridge bundle_id does not match the retained bundle_id"))
    end

    _external_bridge_validate_saved_entries(root, inventory)

    for record in inventory
        path = joinpath(root, split(record.path, '/')...)
        islink(path) &&
            throw(ArgumentError("manifested input must not be a symbolic link: $(record.path)"))
        isfile(path) ||
            throw(ArgumentError("manifested input is missing: $(record.path)"))
        _external_bridge_require_single_link(
            path, "manifested input $(record.path)")
        stat(path).size == record.nbytes ||
            throw(ArgumentError("manifested input byte length mismatch: $(record.path)"))
        actual = _external_bridge_sha256_file(path)
        actual == record.sha256 ||
            throw(ArgumentError("manifested input SHA-256 mismatch: $(record.path)"))
    end
    expected_outputs = _external_bridge_manifest_expected_outputs(manifest)
    host_preflight = _external_bridge_host_preflight(bundle_id, inventory)
    return (;
        schema = "bayesianmgmfrm.external_software_bridge_validation.v1",
        object = :external_software_bridge_validation,
        status = :input_bundle_valid,
        valid = true,
        bundle_id,
        software,
        threshold_regime,
        manifest_sha256 = manifest_hash.sha256,
        n_input_files = length(inventory),
        host_preflight,
        expected_outputs,
        external_execution_completed = false,
        numerical_comparison_allowed = false,
    )
end

function _external_bridge_printable_metadata(value, field::AbstractString;
        max_bytes::Int = 256)
    value isa AbstractString || throw(ArgumentError("$field must be a string"))
    text = String(value)
    isempty(text) && throw(ArgumentError("$field must not be empty"))
    strip(text) == text ||
        throw(ArgumentError("$field must not have leading or trailing whitespace"))
    ncodeunits(text) <= max_bytes ||
        throw(ArgumentError("$field exceeds $max_bytes bytes"))
    all(isprint, text) || throw(ArgumentError("$field must be printable"))
    occursin('\n', text) && throw(ArgumentError("$field must be one line"))
    occursin('\r', text) && throw(ArgumentError("$field must be one line"))
    return text
end

function _external_bridge_execution_time(value)
    text = _external_bridge_printable_metadata(value, "executed_at_utc";
        max_bytes = 20)
    occursin(_EXTERNAL_BRIDGE_UTC, text) ||
        throw(ArgumentError("executed_at_utc must use YYYY-MM-DDTHH:MM:SSZ"))
    try
        DateTime(text[1:(end - 1)])
    catch err
        throw(ArgumentError(
            "executed_at_utc is not a valid UTC date-time: $(sprint(showerror, err))"))
    end
    return text
end

function _external_bridge_fatal_patterns(software::Symbol, role::Symbol)
    inspected = software === :facets ?
        role in (:console_log, :facets_report) :
        role in (:console_log, :estimation_log, :parameter_report)
    inspected || return ()
    return software === :facets ? (
        r"execution halted",
        r"fatal error",
        r"error 0 in line",
    ) : (
        r"fatal error",
        r"syntax error",
        r"unknown command",
        r"(?:cannot|could not|unable to) open",
    )
end

function _external_bridge_normalize_ascii_chunk(bytes,
        previous_whitespace::Bool, previous_digit::Bool)
    normalized = UInt8[]
    sizehint!(normalized, length(bytes))
    in_whitespace = previous_whitespace
    in_digit = previous_digit
    for byte in bytes
        if byte in (0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x20)
            if !in_whitespace
                push!(normalized, 0x20)
            end
            in_whitespace = true
            in_digit = false
        elseif 0x30 <= byte <= 0x39
            if !in_digit
                push!(normalized, 0x30)
            end
            in_whitespace = false
            in_digit = true
        else
            in_whitespace = false
            in_digit = false
            if 0x41 <= byte <= 0x5a
                push!(normalized, byte + 0x20)
            elseif 0x20 <= byte <= 0x7e
                push!(normalized, byte)
            else
                push!(normalized, UInt8('?'))
            end
        end
    end
    return String(normalized), in_whitespace, in_digit
end

function _external_bridge_stream_result_file(path::AbstractString,
        relative::AbstractString, software::Symbol, role::Symbol)
    context = SHA.SHA2_256_CTX()
    nbytes = 0
    content = role === :process_exit_code ? UInt8[] : nothing
    patterns = _external_bridge_fatal_patterns(software, role)
    found_patterns = Set{Int}()
    markers = NamedTuple[]
    overlap = ""
    previous_whitespace = false
    previous_digit = false
    buffer = Vector{UInt8}(undef, _EXTERNAL_BRIDGE_STREAM_CHUNK_BYTES)
    open(path, "r") do io
        while !eof(io)
            count = readbytes!(io, buffer, length(buffer))
            count == 0 && break
            chunk = @view buffer[1:count]
            SHA.update!(context, chunk)
            nbytes = Base.checked_add(nbytes, count)
            if content !== nothing
                nbytes <= _EXTERNAL_BRIDGE_EXIT_CODE_MAX_BYTES ||
                    throw(ArgumentError(
                        "external_exit_code.txt exceeds the allowed byte length"))
                append!(content, chunk)
            end
            isempty(patterns) && continue
            normalized, previous_whitespace, previous_digit =
                _external_bridge_normalize_ascii_chunk(
                    chunk, previous_whitespace, previous_digit)
            scanned = string(overlap, normalized)
            for (index, pattern) in pairs(patterns)
                index in found_patterns && continue
                matched = match(pattern, scanned)
                matched === nothing && continue
                push!(found_patterns, index)
                push!(markers, (;
                    path = String(relative),
                    marker = String(matched.match),
                ))
            end
            overlap = if ncodeunits(scanned) <=
                    _EXTERNAL_BRIDGE_FATAL_SCAN_OVERLAP
                scanned
            else
                String(Vector{UInt8}(codeunits(scanned)[
                    (end - _EXTERNAL_BRIDGE_FATAL_SCAN_OVERLAP + 1):end]))
            end
        end
    end
    return (;
        nbytes,
        sha256 = bytes2hex(SHA.digest!(context)),
        content,
        fatal_markers = Tuple(markers),
        parameter_export = nothing,
    )
end

function _external_bridge_result_snapshots(root::AbstractString,
        expected_outputs, software::Symbol)
    results_root = joinpath(root, "results")
    isdir(results_root) || throw(ArgumentError("external results directory is missing"))
    islink(results_root) &&
        throw(ArgumentError("external results directory must not be a symbolic link"))
    allowed_directories = Set{String}(["results"])
    for output in expected_outputs
        parts = split(output.path, '/')
        for last_index in 1:(length(parts) - 1)
            push!(allowed_directories, join(parts[1:last_index], '/'))
        end
    end
    role_by_path = Dict(output.path => output.role for output in expected_outputs)
    snapshots = NamedTuple[]
    for (directory, subdirectories, names) in walkdir(results_root;
            follow_symlinks = false)
        for subdirectory in subdirectories
            path = joinpath(directory, subdirectory)
            islink(path) &&
                throw(ArgumentError("external result directories must not be symbolic links"))
            relative = replace(relpath(path, root), '\\' => '/')
            relative in allowed_directories ||
                throw(ArgumentError(
                    "external results contain an undeclared directory: $relative"))
        end
        for name in names
            path = joinpath(directory, name)
            islink(path) &&
                throw(ArgumentError("external result files must not be symbolic links"))
            isfile(path) ||
                throw(ArgumentError("external result entry is not a regular file"))
            _external_bridge_require_single_link(
                path, "external result file $(name)")
            relative = replace(relpath(path, root), '\\' => '/')
            checked_relative = _external_bridge_relative_path(relative)
            haskey(role_by_path, checked_relative) ||
                throw(ArgumentError(
                    "external results contain an undeclared file: $checked_relative"))
            role = role_by_path[checked_relative]
            streamed = if role === :parameter_pairs
                parsed = _external_bridge_stream_conquest_parameter_export(
                    path; collect_rows = false)
                (;
                    parsed.nbytes,
                    parsed.sha256,
                    content = nothing,
                    fatal_markers = (),
                    parameter_export = (;
                        parsed = true,
                        n_parameter_pairs = parsed.n_parameter_pairs,
                        semantic_parameter_identity_resolved = false,
                        source_sha256 = parsed.sha256,
                    ),
                )
            else
                _external_bridge_stream_result_file(
                    path, checked_relative, software, role)
            end
            push!(snapshots, (;
                path = checked_relative,
                role,
                streamed.nbytes,
                streamed.sha256,
                streamed.content,
                streamed.fatal_markers,
                streamed.parameter_export,
            ))
        end
    end
    sort!(snapshots; by = snapshot -> snapshot.path)
    return Tuple(snapshots)
end

function _external_bridge_utf8(bytes, description::AbstractString)
    try
        text = String(copy(bytes))
        isvalid(text) || throw(ArgumentError("invalid UTF-8 byte sequence"))
        return text
    catch err
        throw(ArgumentError(
            "$description is not valid UTF-8: $(sprint(showerror, err))"))
    end
end

function _external_bridge_exit_code(bytes)
    text = strip(_external_bridge_utf8(bytes, "external_exit_code.txt"))
    occursin(r"^-?[0-9]+$", text) ||
        throw(ArgumentError("external_exit_code.txt does not contain one integer"))
    value = try
        parse(Int, text)
    catch err
        throw(ArgumentError(
            "external exit code is not representable: $(sprint(showerror, err))"))
    end
    value == 0 || throw(ArgumentError("external process returned exit code $value"))
    return value
end

function _external_bridge_fatal_markers(snapshots)
    return Tuple(marker
        for snapshot in snapshots
        for marker in snapshot.fatal_markers)
end

function _external_bridge_conquest_parameter_row(line::AbstractString,
        line_number::Int)
    (occursin('\n', line) || occursin('\r', line)) &&
        throw(ArgumentError(
            "ConQuest parameter export line $line_number must be one logical line"))
    stripped = strip(line)
    isempty(stripped) && return nothing
    matched = match(_CONQUEST_PARAMETER_ROW, stripped)
    matched === nothing &&
        throw(ArgumentError(
            "ConQuest parameter export line $line_number must contain parameter_number and value, optionally followed by one well-formed /* ... */ comment"))
    parameter_number = try
        parse(Int, matched.captures[1])
    catch
        throw(ArgumentError(
            "ConQuest parameter export line $line_number has an invalid parameter number"))
    end
    parameter_number > 0 ||
        throw(ArgumentError(
            "ConQuest parameter number must be positive at line $line_number"))
    value = try
        parse(Float64, matched.captures[2])
    catch
        throw(ArgumentError(
            "ConQuest parameter export line $line_number has an invalid value"))
    end
    isfinite(value) ||
        throw(ArgumentError(
            "ConQuest parameter export line $line_number has a nonfinite value"))
    source_comment = matched.captures[3]
    if source_comment !== nothing
        source_comment = String(strip(source_comment))
        all(isprint, source_comment) ||
            throw(ArgumentError(
                "ConQuest parameter export line $line_number has a nonprintable source comment"))
    end
    return (;
        schema = "bayesianmgmfrm.conquest_parameter_export_row.v1",
        parameter_number,
        value,
        semantic_parameter_identity_resolved = false,
        source_comment,
    )
end

function _external_bridge_parse_conquest_parameter_export(text::AbstractString)
    rows = NamedTuple[]
    seen = Set{Int}()
    for (line_number, line) in enumerate(eachline(IOBuffer(String(text))))
        row = _external_bridge_conquest_parameter_row(line, line_number)
        row === nothing && continue
        row.parameter_number in seen &&
            throw(ArgumentError(
                "ConQuest parameter number $(row.parameter_number) is duplicated"))
        length(rows) < _CONQUEST_PARAMETER_PAIR_MAX ||
            throw(ArgumentError(
                "ConQuest parameter export exceeds the supported pair limit of $(_CONQUEST_PARAMETER_PAIR_MAX)"))
        push!(seen, row.parameter_number)
        push!(rows, row)
    end
    isempty(rows) && throw(ArgumentError("ConQuest parameter export is empty"))
    sort!(rows; by = row -> row.parameter_number)
    return rows
end

function _external_bridge_stream_conquest_parameter_export(
        path::AbstractString; collect_rows::Bool)
    context = SHA.SHA2_256_CTX()
    nbytes = 0
    line_number = 0
    line_buffer = UInt8[]
    seen = Set{Int}()
    rows = NamedTuple[]
    n_parameter_pairs = 0

    function consume_line!()
        line_number += 1
        text = _external_bridge_utf8(
            line_buffer, "ConQuest parameter export line $line_number")
        row = _external_bridge_conquest_parameter_row(text, line_number)
        empty!(line_buffer)
        row === nothing && return
        row.parameter_number in seen &&
            throw(ArgumentError(
                "ConQuest parameter number $(row.parameter_number) is duplicated"))
        n_parameter_pairs < _CONQUEST_PARAMETER_PAIR_MAX ||
            throw(ArgumentError(
                "ConQuest parameter export exceeds the supported pair limit of $(_CONQUEST_PARAMETER_PAIR_MAX)"))
        push!(seen, row.parameter_number)
        n_parameter_pairs += 1
        collect_rows && push!(rows, row)
        return
    end

    buffer = Vector{UInt8}(undef, _EXTERNAL_BRIDGE_STREAM_CHUNK_BYTES)
    open(path, "r") do io
        while !eof(io)
            count = readbytes!(io, buffer, length(buffer))
            count == 0 && break
            chunk = @view buffer[1:count]
            SHA.update!(context, chunk)
            nbytes = Base.checked_add(nbytes, count)
            segment_start = 1
            for index in eachindex(chunk)
                chunk[index] == 0x0a || continue
                if index > segment_start
                    append!(line_buffer, @view chunk[segment_start:(index - 1)])
                end
                !isempty(line_buffer) && last(line_buffer) == 0x0d &&
                    pop!(line_buffer)
                length(line_buffer) <= _CONQUEST_PARAMETER_LINE_MAX_BYTES ||
                    throw(ArgumentError(
                        "ConQuest parameter export line $(line_number + 1) exceeds the byte limit"))
                consume_line!()
                segment_start = index + 1
            end
            if segment_start <= length(chunk)
                append!(line_buffer, @view chunk[segment_start:end])
                pending_cr = !isempty(line_buffer) && last(line_buffer) == 0x0d
                logical_length = length(line_buffer) - (pending_cr ? 1 : 0)
                logical_length <= _CONQUEST_PARAMETER_LINE_MAX_BYTES ||
                    throw(ArgumentError(
                        "ConQuest parameter export line $(line_number + 1) exceeds the byte limit"))
            end
        end
    end
    !isempty(line_buffer) && last(line_buffer) == 0x0d && pop!(line_buffer)
    length(line_buffer) <= _CONQUEST_PARAMETER_LINE_MAX_BYTES ||
        throw(ArgumentError(
            "ConQuest parameter export line $(line_number + 1) exceeds the byte limit"))
    isempty(line_buffer) || consume_line!()
    n_parameter_pairs > 0 ||
        throw(ArgumentError("ConQuest parameter export is empty"))
    collect_rows && sort!(rows; by = row -> row.parameter_number)
    return (;
        nbytes,
        sha256 = bytes2hex(SHA.digest!(context)),
        n_parameter_pairs,
        rows,
    )
end

"""
    load_conquest_parameter_export(path; expected_sha256 = nothing)

Read ConQuest's documented text `export parameters` format as unique positive
parameter-number/value pairs. A pair may be followed by one well-formed,
single-line `/* ... */` source comment; its trimmed content is returned as
`source_comment`, without treating it as a resolved parameter identity. The
parser rejects headers, malformed rows, duplicate parameter numbers, nonfinite
values, lines longer than 4096 bytes, and exports above 1,000,000 pairs. It
streams the source bytes while hashing and parsing, but the returned row
collection is necessarily proportional to the number of parameter pairs. It
does not infer semantic item, rater, or step labels from positional parameter
numbers.

Pass the SHA-256 recorded by [`external_bridge_result_receipt`](@ref) as
`expected_sha256` when reading a transferred file later.
"""
function load_conquest_parameter_export(path::AbstractString;
        expected_sha256 = nothing)
    source = abspath(normpath(String(path)))
    islink(source) &&
        throw(ArgumentError("ConQuest parameter export must not be a symbolic link"))
    isfile(source) || throw(ArgumentError("ConQuest parameter export does not exist"))
    _external_bridge_require_single_link(source, "ConQuest parameter export")
    parsed = _external_bridge_stream_conquest_parameter_export(
        source; collect_rows = true)
    if expected_sha256 !== nothing
        expected = String(expected_sha256)
        occursin(_EXTERNAL_BRIDGE_SHA256, expected) ||
            throw(ArgumentError("expected_sha256 has an invalid format"))
        parsed.sha256 == expected ||
            throw(ArgumentError("ConQuest parameter export SHA-256 mismatch"))
    end
    return parsed.rows
end

"""
    external_bridge_result_receipt(directory;
        expected_bundle_id,
        software_version,
        executable_sha256,
        executed_at_utc)

Verify a bundle returned from a licensed execution host. The function first
rechecks the retained `bundle_id` and every input, then requires all declared
outputs, no undeclared result files or directories, a zero process exit code,
regular non-symlink files, no execution lock, and no recognized fatal marker.
Every returned file is streamed once and bound to its byte length and SHA-256
digest. Fatal-marker inspection and ConQuest parameter-row validation run in
that same streaming pass. Raw output content is not retained except for the
strictly bounded process-exit record.

The software version, executable digest, and execution time are operator-
supplied metadata; this function cannot authenticate the executable. A valid
receipt records reported completion but does not independently verify that the
external executable ran. It also does not validate convergence, semantic
parameter identities, gauge alignment, numerical agreement, or product
equivalence. Those comparison claims remain disabled until version-specific
output samples and adapters are checked.
"""
function external_bridge_result_receipt(directory::AbstractString;
        expected_bundle_id,
        software_version,
        executable_sha256,
        executed_at_utc)
    root = abspath(normpath(String(directory)))
    validation = validate_external_bridge_bundle(root;
        expected_bundle_id)
    version = _external_bridge_printable_metadata(
        software_version, "software_version")
    executable_hash = String(executable_sha256)
    occursin(_EXTERNAL_BRIDGE_SHA256, executable_hash) ||
        throw(ArgumentError("executable_sha256 must be a lowercase SHA-256 digest"))
    execution_time = _external_bridge_execution_time(executed_at_utc)

    lock_path = joinpath(root, ".bridge_execution.lock")
    ispath(lock_path) &&
        throw(ArgumentError("external bridge execution lock is still present"))
    snapshots = _external_bridge_result_snapshots(
        root, validation.expected_outputs, validation.software)
    snapshot_by_path = Dict(snapshot.path => snapshot for snapshot in snapshots)
    result_set = Set(keys(snapshot_by_path))
    declared_result_set = Set(row.path for row in validation.expected_outputs)
    unexpected_results = sort!(collect(setdiff(result_set, declared_result_set)))
    isempty(unexpected_results) ||
        throw(ArgumentError(
            "external results contain undeclared files: $(join(unexpected_results, ", "))"))
    for expected in validation.expected_outputs
        expected.required || continue
        expected.path in result_set ||
            throw(ArgumentError("required external output is missing: $(expected.path)"))
        if !expected.allow_empty
            snapshot_by_path[expected.path].nbytes > 0 ||
                throw(ArgumentError("required external output is empty: $(expected.path)"))
        end
    end
    exit_snapshot = snapshot_by_path["results/external_exit_code.txt"]
    exit_snapshot.content === nothing &&
        throw(ArgumentError("external exit-code output was not retained"))
    exit_code = _external_bridge_exit_code(exit_snapshot.content)
    fatal_markers = _external_bridge_fatal_markers(snapshots)
    isempty(fatal_markers) ||
        throw(ArgumentError(
            "external output contains a recognized fatal marker: $(first(fatal_markers))"))

    outputs = Tuple((;
        path = snapshot.path,
        role = begin
            matched = findfirst(row -> row.path == snapshot.path,
                validation.expected_outputs)
            matched === nothing ? :additional_output :
                validation.expected_outputs[matched].role
        end,
        nbytes = snapshot.nbytes,
        sha256 = snapshot.sha256,
    ) for snapshot in snapshots)

    parameter_export = if validation.software === :conquest
        parameter_snapshot = snapshot_by_path["results/conquest_parameters.txt"]
        parameter_snapshot.parameter_export === nothing &&
            throw(ArgumentError("ConQuest parameter export was not parsed"))
        parameter_snapshot.parameter_export
    else
        (;
            parsed = false,
            reason = :facets_output_format_not_yet_validated,
        )
    end
    ispath(lock_path) &&
        throw(ArgumentError("external bridge execution lock appeared while collecting results"))
    final_validation = validate_external_bridge_bundle(root;
        expected_bundle_id)
    final_validation.manifest_sha256 == validation.manifest_sha256 ||
        throw(ArgumentError("bridge manifest changed while collecting results"))

    payload = (;
        schema = _EXTERNAL_BRIDGE_RECEIPT_SCHEMA,
        object = :external_software_bridge_result_receipt,
        status = :raw_return_integrity_verified,
        bundle_id = validation.bundle_id,
        software = validation.software,
        software_version = version,
        executable_sha256 = executable_hash,
        executed_at_utc = execution_time,
        exit_code,
        input_manifest_sha256 = validation.manifest_sha256,
        raw_return_integrity_verified = true,
        external_execution_completed = false,
        external_execution_reported_completed = true,
        external_execution_independently_verified = false,
        external_execution_authenticity_verified = false,
        convergence_validated = false,
        semantic_parameter_adapter_validated = false,
        numerical_comparison_allowed = false,
        software_equivalence_claimed = false,
        parameter_export,
        output_files = outputs,
    )
    return merge(payload, (;
        content_hash = artifact_content_hash(payload),
    ))
end

function _conquest_semantic_version(value)
    text = _external_bridge_printable_metadata(
        value, "software_version"; max_bytes = 256)
    text in _CONQUEST_SEMANTIC_SUPPORTED_VERSION_REPORTS ||
        throw(ArgumentError(
            "ConQuest semantic adapter requires an exact supported 5.47.5 version report"))
    return (;
        reported = text,
        normalized = _CONQUEST_SEMANTIC_SUPPORTED_VERSION,
    )
end

function _conquest_semantic_manifest_integer(object, key::AbstractString)
    value = get(object, key, nothing)
    value isa Integer && !(value isa Bool) && value >= 0 ||
        throw(ArgumentError("bridge manifest $key must be a nonnegative integer"))
    return Int(value)
end

function _conquest_semantic_exact_input(root::AbstractString,
        relative::AbstractString, expected::AbstractString)
    path = joinpath(root, split(relative, '/')...)
    islink(path) &&
        throw(ArgumentError("semantic adapter input must not be a symbolic link: $relative"))
    isfile(path) ||
        throw(ArgumentError("semantic adapter input is missing: $relative"))
    _external_bridge_require_single_link(path, "semantic adapter input $relative")
    stat(path).size == sizeof(expected) ||
        throw(ArgumentError("semantic adapter input byte length mismatch: $relative"))
    _external_bridge_sha256_file(path) == _external_bridge_sha256(expected) ||
        throw(ArgumentError("semantic adapter input content mismatch: $relative"))
    return nothing
end

function _conquest_semantic_validate_source_bundle(root::AbstractString,
        spec::FacetSpec, expected_bundle_id)
    validation = validate_external_bridge_bundle(
        root; expected_bundle_id)
    validation.software === :conquest ||
        throw(ArgumentError("semantic adapter requires a ConQuest bundle"))
    validation.threshold_regime === spec.thresholds ||
        throw(ArgumentError(
            "ConQuest bundle threshold regime does not match the specification"))
    validation.expected_outputs == _external_bridge_expected_outputs(:conquest) ||
        throw(ArgumentError(
            "ConQuest bundle expected-output contract is not canonical"))

    manifest_path = joinpath(root, "bridge_manifest.json")
    islink(manifest_path) &&
        throw(ArgumentError("bridge manifest must not be a symbolic link"))
    _external_bridge_require_single_link(manifest_path, "bridge manifest")
    manifest_bytes = read(manifest_path)
    _external_bridge_sha256_bytes(manifest_bytes) ==
            validation.manifest_sha256 ||
        throw(ArgumentError(
            "bridge manifest changed after bundle validation"))
    manifest = try
        JSON3.read(String(manifest_bytes), Dict{String,Any})
    catch err
        throw(ArgumentError(
            "could not parse bridge manifest for semantic adaptation: $(sprint(showerror, err))"))
    end
    target = get(manifest, "model_target", nothing)
    target isa AbstractDict ||
        throw(ArgumentError("bridge manifest has no model_target object"))
    get(target, "family", nothing) == "mfrm" ||
        throw(ArgumentError("semantic adapter requires family = mfrm"))
    _conquest_semantic_manifest_integer(target, "dimensions") == 1 ||
        throw(ArgumentError("semantic adapter requires one dimension"))
    get(target, "weighting", nothing) == "unit" ||
        throw(ArgumentError("semantic adapter requires unit weighting"))
    get(target, "anchors", nothing) == "none" ||
        throw(ArgumentError("semantic adapter requires an unanchored source bundle"))
    get(target, "category_mapping", nothing) == "ordered_to_zero_based" ||
        throw(ArgumentError("semantic adapter requires ordered zero-based category mapping"))
    source_identification = get(target, "source_identification", nothing)
    source_identification isa AbstractDict &&
        get(source_identification, "location_constraints", nothing) == "items" ||
        throw(ArgumentError(
            "semantic adapter requires ConQuest lconstraints=items"))
    signs = get(target, "sign", nothing)
    signs isa AbstractDict &&
        get(signs, "person", nothing) == "ability_positive" &&
        get(signs, "rater", nothing) == "severity_positive" &&
        get(signs, "item", nothing) == "difficulty_positive" ||
        throw(ArgumentError("ConQuest bundle sign declaration is unsupported"))

    data_manifest = get(manifest, "data", nothing)
    data_manifest isa AbstractDict ||
        throw(ArgumentError("bridge manifest has no data object"))
    data = spec.data
    expected_counts = (
        "n_ratings" => data.n,
        "n_persons" => length(data.person_levels),
        "n_raters" => length(data.rater_levels),
        "n_items" => length(data.item_levels),
        "n_categories" => length(data.category_levels),
    )
    for (key, expected) in expected_counts
        _conquest_semantic_manifest_integer(data_manifest, key) == expected ||
            throw(ArgumentError(
                "ConQuest bundle $key does not match the specification"))
    end
    _conquest_semantic_manifest_integer(data_manifest, "rows_added") == 0 ||
        throw(ArgumentError("semantic adapter does not accept added rows"))
    _conquest_semantic_manifest_integer(data_manifest, "rows_removed") == 0 ||
        throw(ArgumentError("semantic adapter does not accept removed rows"))

    privacy = get(manifest, "privacy", nothing)
    privacy isa AbstractDict ||
        throw(ArgumentError("bridge manifest has no privacy object"))
    include_original_labels = get(privacy, "original_labels_included", nothing)
    include_original_labels isa Bool ||
        throw(ArgumentError(
            "bridge manifest original_labels_included flag is invalid"))
    title = _external_bridge_title(get(manifest, "title", nothing))
    codes = _external_bridge_codes(data)
    response_codes = _CONQUEST_RESPONSE_CODES[eachindex(data.category_levels)]
    order = _external_bridge_row_order(data)
    expected_inputs = (
        "conquest_control.cqc" =>
            _conquest_control(spec, title, codes, response_codes),
        "conquest_ratings.csv" =>
            _conquest_data(spec, order, codes, response_codes),
        "id_map.tsv" => _external_bridge_id_map(
            data, codes; include_original_labels),
        "category_map.tsv" => _external_bridge_category_map(
            data; response_codes),
        "observation_map.tsv" => _external_bridge_observation_map(
            data, order, codes; response_codes),
    )
    for (relative, expected) in expected_inputs
        _conquest_semantic_exact_input(root, relative, expected)
    end
    return (; validation, manifest, codes, response_codes)
end

function _conquest_semantic_free_descriptors(spec::FacetSpec, codes)
    data = spec.data
    rows = NamedTuple[]
    parameter_number = 0
    for index in 1:max(length(data.rater_levels) - 1, 0)
        parameter_number += 1
        comment = "raterid $(codes.raters[index])"
        push!(rows, (;
            parameter_number,
            block = :rater,
            level_index = index,
            item_index = missing,
            step = missing,
            bridge_label = codes.raters[index],
            source_comment = comment,
        ))
    end
    for index in 1:max(length(data.item_levels) - 1, 0)
        parameter_number += 1
        comment = "itemid $(codes.items[index])"
        push!(rows, (;
            parameter_number,
            block = :item,
            level_index = index,
            item_index = missing,
            step = missing,
            bridge_label = codes.items[index],
            source_comment = comment,
        ))
    end
    free_steps = max(length(data.category_levels) - 2, 0)
    if spec.thresholds === :rating_scale
        for step in 1:free_steps
            parameter_number += 1
            comment = "category $step"
            push!(rows, (;
                parameter_number,
                block = :thresholds,
                level_index = missing,
                item_index = missing,
                step,
                bridge_label = comment,
                source_comment = comment,
            ))
        end
    else
        for item_index in eachindex(data.item_levels), step in 1:free_steps
            parameter_number += 1
            comment = "itemid $(codes.items[item_index]) category $step"
            push!(rows, (;
                parameter_number,
                block = :thresholds,
                level_index = missing,
                item_index,
                step,
                bridge_label = comment,
                source_comment = comment,
            ))
        end
    end
    return Tuple(rows)
end

function _conquest_semantic_bind_free_rows(parameter_rows, descriptors)
    length(parameter_rows) == length(descriptors) ||
        throw(ArgumentError(
            "ConQuest parameter count does not match the version-specific model contract"))
    rows = NamedTuple[]
    for (index, (parameter, descriptor)) in enumerate(
            zip(parameter_rows, descriptors))
        parameter.parameter_number == index ||
            throw(ArgumentError(
                "ConQuest parameter numbers must be contiguous from 1"))
        parameter.parameter_number == descriptor.parameter_number ||
            throw(ArgumentError("ConQuest parameter order is inconsistent"))
        parameter.source_comment === descriptor.source_comment ||
            throw(ArgumentError(
                "ConQuest parameter comment does not match parameter $(index)"))
        push!(rows, merge(descriptor, (;
            value = parameter.value,
            semantic_parameter_identity_resolved = true,
        )))
    end
    return Tuple(rows)
end

function _conquest_semantic_derived_last(free_values)
    value = -sum(free_values)
    isfinite(value) ||
        throw(ArgumentError("ConQuest constraint reconstruction is nonfinite"))
    return iszero(value) ? 0.0 : value
end

function _conquest_semantic_source_values(spec::FacetSpec, free_rows)
    data = spec.data
    rater_free = [row.value for row in free_rows if row.block === :rater]
    item_free = [row.value for row in free_rows if row.block === :item]
    rater = vcat(rater_free, _conquest_semantic_derived_last(rater_free))
    item = vcat(item_free, _conquest_semantic_derived_last(item_free))
    free_steps = max(length(data.category_levels) - 2, 0)
    if spec.thresholds === :rating_scale
        step_free = [row.value for row in free_rows
            if row.block === :thresholds]
        steps = vcat(step_free, _conquest_semantic_derived_last(step_free))
        return (; rater, item, steps, item_steps = nothing)
    end
    item_steps = Vector{Vector{Float64}}()
    for item_index in eachindex(data.item_levels)
        step_free = [row.value for row in free_rows
            if row.block === :thresholds && row.item_index == item_index]
        length(step_free) == free_steps ||
            throw(ArgumentError(
                "ConQuest PCM step count is inconsistent for item $item_index"))
        push!(item_steps,
            vcat(step_free, _conquest_semantic_derived_last(step_free)))
    end
    return (; rater, item, steps = nothing, item_steps)
end

function _conquest_semantic_parse_matrix_integer(value::AbstractString,
        description::AbstractString)
    text = strip(value)
    occursin(r"^[+-]?[0-9]+$", text) ||
        throw(ArgumentError("$description must be an integer"))
    try
        return parse(Int, text)
    catch
        throw(ArgumentError("$description is outside the supported integer range"))
    end
end

function _conquest_semantic_contrast_level(values, nlevels::Int,
        block::AbstractString, gin::Int)
    nlevels == 1 && return 1
    length(values) == nlevels - 1 ||
        throw(ArgumentError("ConQuest $block contrast width is invalid"))
    all(==(1), values) && return nlevels
    negative = findall(==(-1), values)
    length(negative) == 1 &&
        all(index -> index == only(negative) || values[index] == 0,
            eachindex(values)) ||
        throw(ArgumentError(
            "ConQuest $block contrast is invalid for GIN $gin"))
    return only(negative)
end

function _conquest_semantic_expected_facet_coefficient(
        level::Int, free_index::Int, nlevels::Int, score::Int)
    level == nlevels && return score
    return level == free_index ? -score : 0
end

function _conquest_semantic_expected_step_coefficient(
        step::Int, category::Int, ncategories::Int)
    return category < ncategories && step < category ? -1 : 0
end

function _conquest_semantic_validate_design_matrix(path::AbstractString,
        expected_sha256::AbstractString, expected_nbytes::Integer,
        spec::FacetSpec, descriptors,
        free_rows, source_values)
    islink(path) &&
        throw(ArgumentError("ConQuest design matrix must not be a symbolic link"))
    isfile(path) || throw(ArgumentError("ConQuest design matrix does not exist"))
    _external_bridge_require_single_link(path, "ConQuest design matrix")
    occursin(_EXTERNAL_BRIDGE_SHA256, expected_sha256) ||
        throw(ArgumentError("ConQuest design-matrix SHA-256 has an invalid format"))
    expected_nbytes >= 0 ||
        throw(ArgumentError("ConQuest design-matrix byte length is invalid"))

    data = spec.data
    ncategories = length(data.category_levels)
    nrater_free = max(length(data.rater_levels) - 1, 0)
    nitem_free = max(length(data.item_levels) - 1, 0)
    nfree_steps = max(ncategories - 2, 0)
    rater_range = 1:nrater_free
    item_range = (nrater_free + 1):(nrater_free + nitem_free)
    step_start = nrater_free + nitem_free + 1
    expected_header = vcat(
        ["GIN", "Category"],
        [row.source_comment for row in descriptors],
    )
    free_values = [row.value for row in free_rows]
    observed_pairs = Set((data.rater[row], data.item[row]) for row in 1:data.n)
    seen_pairs = Set{Tuple{Int,Int}}()
    expected_gin = 1
    expected_category = 1
    current_rater = 0
    current_item = 0
    nrows = 0
    max_predictor_residual = 0.0
    header_seen = false
    context = SHA.SHA2_256_CTX()
    nbytes = 0

    open(path, "r") do io
        stat(io).nlink == 1 ||
            throw(ArgumentError("ConQuest design matrix must not be a hard link"))
        for raw_line in eachline(io; keep = true)
            SHA.update!(context, codeunits(raw_line))
            nbytes = Base.checked_add(nbytes, ncodeunits(raw_line))
            line = chomp(raw_line)
            isvalid(line) ||
                throw(ArgumentError("ConQuest design matrix is not valid UTF-8"))
            ncodeunits(line) <= _CONQUEST_DESIGN_MATRIX_LINE_MAX_BYTES ||
                throw(ArgumentError(
                    "ConQuest design-matrix line exceeds the byte limit"))
            fields = strip.(split(line, ','; keepempty = true))
            if !header_seen
                fields == expected_header ||
                    throw(ArgumentError(
                        "ConQuest design-matrix header does not exactly match parameter comments"))
                header_seen = true
                continue
            end
            nrows < _CONQUEST_DESIGN_MATRIX_ROW_MAX ||
                throw(ArgumentError(
                    "ConQuest design matrix exceeds the supported row limit"))
            length(fields) == length(expected_header) ||
                throw(ArgumentError("ConQuest design matrix has a ragged row"))
            nrows += 1
            gin = _conquest_semantic_parse_matrix_integer(
                fields[1], "ConQuest design-matrix GIN")
            category = _conquest_semantic_parse_matrix_integer(
                fields[2], "ConQuest design-matrix Category")
            gin == expected_gin && category == expected_category ||
                throw(ArgumentError(
                    "ConQuest design matrix must be ordered by contiguous GIN and Category"))
            coefficients = [_conquest_semantic_parse_matrix_integer(
                fields[index], "ConQuest design-matrix coefficient")
                for index in 3:length(fields)]
            score = category - 1
            if category == 1
                all(iszero, coefficients) ||
                    throw(ArgumentError(
                        "ConQuest base-category design row must be zero"))
            else
                if category == 2
                    current_rater = _conquest_semantic_contrast_level(
                        coefficients[rater_range],
                        length(data.rater_levels), "rater", gin)
                    current_item = _conquest_semantic_contrast_level(
                        coefficients[item_range],
                        length(data.item_levels), "item", gin)
                    pair = (current_rater, current_item)
                    pair in observed_pairs ||
                        throw(ArgumentError(
                            "ConQuest design matrix contains an unknown rater-item generalized item"))
                    pair in seen_pairs &&
                        throw(ArgumentError(
                            "ConQuest design matrix duplicates a rater-item generalized item"))
                    push!(seen_pairs, pair)
                end
                for free_index in 1:nrater_free
                    coefficients[free_index] ==
                        _conquest_semantic_expected_facet_coefficient(
                            current_rater, free_index,
                            length(data.rater_levels), score) ||
                        throw(ArgumentError(
                            "ConQuest rater design coefficient is inconsistent"))
                end
                for free_index in 1:nitem_free
                    coefficients[nrater_free + free_index] ==
                        _conquest_semantic_expected_facet_coefficient(
                            current_item, free_index,
                            length(data.item_levels), score) ||
                        throw(ArgumentError(
                            "ConQuest item design coefficient is inconsistent"))
                end
                if spec.thresholds === :rating_scale
                    for step in 1:nfree_steps
                        coefficients[step_start + step - 1] ==
                            _conquest_semantic_expected_step_coefficient(
                                step, category, ncategories) ||
                            throw(ArgumentError(
                                "ConQuest rating-scale step coefficient is inconsistent"))
                    end
                    threshold_sum = sum(source_values.steps[1:score])
                else
                    for item_index in eachindex(data.item_levels),
                            step in 1:nfree_steps
                        column = step_start +
                            (item_index - 1) * nfree_steps + step - 1
                        expected = item_index == current_item ?
                            _conquest_semantic_expected_step_coefficient(
                                step, category, ncategories) : 0
                        coefficients[column] == expected ||
                            throw(ArgumentError(
                                "ConQuest partial-credit step coefficient is inconsistent"))
                    end
                    threshold_sum = sum(
                        source_values.item_steps[current_item][1:score])
                end
                lhs = sum(coefficients .* free_values)
                rhs = -score * source_values.rater[current_rater] -
                    score * source_values.item[current_item] - threshold_sum
                residual = abs(lhs - rhs)
                max_predictor_residual = max(max_predictor_residual, residual)
                tolerance = 128eps(Float64) * max(1.0, abs(lhs), abs(rhs))
                residual <= tolerance ||
                    throw(ArgumentError(
                        "ConQuest design matrix and reconstructed semantic values have inconsistent orientation"))
            end
            if category == ncategories
                expected_gin += 1
                expected_category = 1
                current_rater = 0
                current_item = 0
            else
                expected_category += 1
            end
        end
    end
    header_seen || throw(ArgumentError("ConQuest design matrix is empty"))
    nrows > 0 || throw(ArgumentError("ConQuest design matrix has no data rows"))
    expected_category == 1 ||
        throw(ArgumentError("ConQuest design matrix ends within a GIN block"))
    seen_pairs == observed_pairs ||
        throw(ArgumentError(
            "ConQuest design matrix does not cover the specification's rater-item generalized items"))
    nbytes == expected_nbytes ||
        throw(ArgumentError("ConQuest design-matrix byte length mismatch"))
    bytes2hex(SHA.digest!(context)) == expected_sha256 ||
        throw(ArgumentError("ConQuest design-matrix SHA-256 mismatch"))
    return (;
        n_rows = nrows,
        n_generalized_items = expected_gin - 1,
        max_predictor_identity_residual = max_predictor_residual,
        exact_header_order_validated = true,
        category_grid_validated = true,
        structural_basis_validated = true,
        predictor_orientation_validated = true,
    )
end

function _conquest_semantic_output_record(receipt, path::AbstractString,
        role::Symbol)
    matches = [row for row in receipt.output_files
        if row.path == path && row.role === role]
    length(matches) == 1 ||
        throw(ArgumentError(
            "ConQuest receipt must contain exactly one $role record at $path"))
    return only(matches)
end

function _conquest_semantic_source_rows(spec::FacetSpec, codes,
        free_rows, source_values)
    data = spec.data
    by_parameter = Dict(row.parameter_number => row for row in free_rows)
    rater_parameters = [row.parameter_number for row in free_rows
        if row.block === :rater]
    item_parameters = [row.parameter_number for row in free_rows
        if row.block === :item]
    rows = NamedTuple[]
    for index in eachindex(data.rater_levels)
        exported = index < length(data.rater_levels)
        parameter = exported ? by_parameter[index] : nothing
        derivation = exported ? :exported :
            isempty(rater_parameters) ? :fixed_zero_constraint :
            :negative_sum_constraint
        push!(rows, (;
            block = :rater,
            level_index = index,
            level = data.rater_levels[index],
            item_index = missing,
            item = missing,
            step = missing,
            from_category = missing,
            to_category = missing,
            bridge_label = codes.raters[index],
            canonical_label_sha256 =
                _external_bridge_label_hash(data.rater_levels[index]),
            value = source_values.rater[index],
            orientation = :severity_positive,
            derivation,
            exported_parameter_number = exported ?
                parameter.parameter_number : missing,
            source_parameter_numbers = exported ?
                (parameter.parameter_number,) : Tuple(rater_parameters),
            source_comment = exported ? parameter.source_comment : missing,
            semantic_parameter_identity_resolved = true,
        ))
    end
    item_offset = length(rater_parameters)
    for index in eachindex(data.item_levels)
        exported = index < length(data.item_levels)
        parameter_number = item_offset + index
        parameter = exported ? by_parameter[parameter_number] : nothing
        derivation = exported ? :exported :
            isempty(item_parameters) ? :fixed_zero_constraint :
            :negative_sum_constraint
        push!(rows, (;
            block = :item,
            level_index = index,
            level = data.item_levels[index],
            item_index = missing,
            item = missing,
            step = missing,
            from_category = missing,
            to_category = missing,
            bridge_label = codes.items[index],
            canonical_label_sha256 =
                _external_bridge_label_hash(data.item_levels[index]),
            value = source_values.item[index],
            orientation = :difficulty_positive,
            derivation,
            exported_parameter_number = exported ?
                parameter.parameter_number : missing,
            source_parameter_numbers = exported ?
                (parameter.parameter_number,) : Tuple(item_parameters),
            source_comment = exported ? parameter.source_comment : missing,
            semantic_parameter_identity_resolved = true,
        ))
    end

    free_steps = max(length(data.category_levels) - 2, 0)
    if spec.thresholds === :rating_scale
        step_parameters = [row.parameter_number for row in free_rows
            if row.block === :thresholds]
        for step in 1:(length(data.category_levels) - 1)
            exported = step <= free_steps
            parameter = exported ? by_parameter[step_parameters[step]] : nothing
            derivation = exported ? :exported :
                isempty(step_parameters) ? :fixed_zero_constraint :
                :negative_sum_constraint
            push!(rows, (;
                block = :thresholds,
                level_index = missing,
                level = missing,
                item_index = missing,
                item = missing,
                step,
                from_category = data.category_levels[step],
                to_category = data.category_levels[step + 1],
                bridge_label = "category $step",
                canonical_label_sha256 = missing,
                value = source_values.steps[step],
                orientation = :subtractive_transition,
                derivation,
                exported_parameter_number = exported ?
                    parameter.parameter_number : missing,
                source_parameter_numbers = exported ?
                    (parameter.parameter_number,) : Tuple(step_parameters),
                source_comment = exported ? parameter.source_comment : missing,
                semantic_parameter_identity_resolved = true,
            ))
        end
    else
        for item_index in eachindex(data.item_levels)
            step_parameters = [row.parameter_number for row in free_rows
                if row.block === :thresholds && row.item_index == item_index]
            for step in 1:(length(data.category_levels) - 1)
                exported = step <= free_steps
                parameter = exported ? by_parameter[step_parameters[step]] : nothing
                derivation = exported ? :exported :
                    isempty(step_parameters) ? :fixed_zero_constraint :
                    :negative_sum_constraint
                push!(rows, (;
                    block = :thresholds,
                    level_index = missing,
                    level = missing,
                    item_index,
                    item = data.item_levels[item_index],
                    step,
                    from_category = data.category_levels[step],
                    to_category = data.category_levels[step + 1],
                    bridge_label =
                        "itemid $(codes.items[item_index]) category $step",
                    canonical_label_sha256 =
                        _external_bridge_label_hash(data.item_levels[item_index]),
                    value = source_values.item_steps[item_index][step],
                    orientation = :subtractive_transition,
                    derivation,
                    exported_parameter_number = exported ?
                        parameter.parameter_number : missing,
                    source_parameter_numbers = exported ?
                        (parameter.parameter_number,) : Tuple(step_parameters),
                    source_comment = exported ? parameter.source_comment : missing,
                    semantic_parameter_identity_resolved = true,
                ))
            end
        end
    end
    return Tuple(rows)
end

function _conquest_semantic_constraint_residual(source_values)
    residuals = Float64[
        abs(sum(source_values.rater)),
        abs(sum(source_values.item)),
    ]
    if source_values.steps !== nothing
        push!(residuals, abs(sum(source_values.steps)))
    else
        append!(residuals,
            abs(sum(steps)) for steps in source_values.item_steps)
    end
    return maximum(residuals; init = 0.0)
end

"""
    load_conquest_semantic_parameters(directory, spec_or_design;
        expected_bundle_id,
        software_version,
        executable_sha256,
        executed_at_utc)

Resolve the parameter identities in a returned ConQuest bridge bundle for the
version-specific, three-category, one-dimensional additive MFRM/RSM/PCM
contract. The function verifies the complete input bundle, constructs a
receipt from the current returned-file snapshot,
requires an exact match between the supplied specification and the hash-bound
control, rating, identifier-map, category-map, and observation-map inputs, and
then jointly checks the parameter comments and exported design matrix.

The returned rows are ConQuest source-gauge values. Under
`lconstraints=items`, the last rater and item values and the last shared or
item-specific step are reconstructed as the negative sum of the corresponding
free values. No global sign reversal is applied: raters use
`severity_positive`, items use `difficulty_positive`, and steps enter as
subtractive transitions. Empty `conquest_labels.txt` output is allowed because
semantic identity comes from the jointly verified bundle inputs, comments, and
design matrix.

This first adapter is deliberately restricted to ConQuest 5.47.5 and exactly
three ordered categories, the executed RSM/PCM fixture boundary currently
available in the package. It does not validate convergence, align values to the
package's first-reference gauge, construct a fit parameter vector or anchors,
permit a numerical-comparison claim, or claim estimator/software equivalence.
Use [`load_conquest_parameter_export`](@ref) when only the raw numbered values
are needed.
"""
function load_conquest_semantic_parameters(directory::AbstractString,
        spec_or_design;
        expected_bundle_id,
        software_version,
        executable_sha256,
        executed_at_utc)
    expected_bundle_id isa AbstractString ||
        throw(ArgumentError(
            "expected_bundle_id must be the out-of-band retained bundle ID"))
    retained_bundle_id = String(expected_bundle_id)
    occursin(_EXTERNAL_BRIDGE_ID, retained_bundle_id) ||
        throw(ArgumentError("expected_bundle_id has an invalid format"))
    spec = _external_bridge_validate_spec(
        _external_bridge_spec(spec_or_design), :conquest)
    _conquest_validate_cells(spec)
    length(spec.data.category_levels) == 3 ||
        throw(ArgumentError(
            "ConQuest semantic adapter currently requires exactly three categories"))
    version = _conquest_semantic_version(software_version)
    root = abspath(normpath(String(directory)))
    source_bundle = _conquest_semantic_validate_source_bundle(
        root, spec, retained_bundle_id)
    receipt = external_bridge_result_receipt(root;
        expected_bundle_id = retained_bundle_id,
        software_version = version.reported,
        executable_sha256,
        executed_at_utc,
    )
    receipt.bundle_id == source_bundle.validation.bundle_id ||
        throw(ArgumentError("ConQuest receipt bundle identity is inconsistent"))
    receipt.input_manifest_sha256 ==
            source_bundle.validation.manifest_sha256 ||
        throw(ArgumentError("ConQuest receipt manifest identity is inconsistent"))

    parameter_record = _conquest_semantic_output_record(
        receipt, "results/conquest_parameters.txt", :parameter_pairs)
    design_record = _conquest_semantic_output_record(
        receipt, "results/conquest_designmatrix.csv", :design_matrix)
    parameter_path = joinpath(root, "results", "conquest_parameters.txt")
    design_path = joinpath(root, "results", "conquest_designmatrix.csv")
    parameter_rows = load_conquest_parameter_export(
        parameter_path; expected_sha256 = parameter_record.sha256)
    descriptors = _conquest_semantic_free_descriptors(
        spec, source_bundle.codes)
    free_rows = _conquest_semantic_bind_free_rows(
        parameter_rows, descriptors)
    source_values = _conquest_semantic_source_values(spec, free_rows)
    all(isfinite, source_values.rater) && all(isfinite, source_values.item) ||
        throw(ArgumentError("ConQuest semantic facet values are nonfinite"))
    if source_values.steps !== nothing
        all(isfinite, source_values.steps) ||
            throw(ArgumentError("ConQuest semantic step values are nonfinite"))
    else
        all(steps -> all(isfinite, steps), source_values.item_steps) ||
            throw(ArgumentError("ConQuest semantic item-step values are nonfinite"))
    end
    constraint_residual = _conquest_semantic_constraint_residual(source_values)
    constraint_residual <= 128eps(Float64) * max(
        1.0,
        maximum(abs, source_values.rater; init = 0.0),
        maximum(abs, source_values.item; init = 0.0),
    ) || throw(ArgumentError(
        "ConQuest reconstructed source constraints are inconsistent"))
    design_validation = _conquest_semantic_validate_design_matrix(
        design_path,
        design_record.sha256,
        design_record.nbytes,
        spec,
        descriptors,
        free_rows,
        source_values,
    )
    rows = _conquest_semantic_source_rows(
        spec, source_bundle.codes, free_rows, source_values)
    payload = (;
        schema = "bayesianmgmfrm.conquest_semantic_parameters.v1",
        object = :conquest_semantic_parameters,
        status = :semantic_identity_resolved_source_gauge,
        adapter_id = _CONQUEST_SEMANTIC_ADAPTER_ID,
        software = :conquest,
        software_version = version.normalized,
        software_version_reported = version.reported,
        source_model = spec.thresholds === :rating_scale ?
            :mfrm_rsm : :mfrm_pcm,
        threshold_regime = spec.thresholds,
        source_scale = :logit,
        source_gauge = (;
            rater = :sum_to_zero_last_derived,
            item = :sum_to_zero_last_derived,
            thresholds = spec.thresholds === :rating_scale ?
                :shared_sum_to_zero_last_derived :
                :itemwise_sum_to_zero_last_derived,
        ),
        source_orientation = (;
            person = :ability_positive,
            rater = :severity_positive,
            item = :difficulty_positive,
            thresholds = :subtractive_transition,
        ),
        provenance = (;
            bundle_id = receipt.bundle_id,
            receipt_content_hash = receipt.content_hash,
            input_manifest_sha256 = receipt.input_manifest_sha256,
            parameter_export_sha256 = parameter_record.sha256,
            design_matrix_sha256 = design_record.sha256,
            executable_sha256 = receipt.executable_sha256,
            executed_at_utc = receipt.executed_at_utc,
            source_data_bound_to_specification = true,
            external_execution_reported_completed = true,
            external_execution_independently_verified = false,
            external_execution_authenticity_verified = false,
        ),
        identity_checks = (;
            complete_bundle_validated = true,
            receipt_snapshot_constructed = true,
            source_inputs_match_specification = true,
            reported_version_allowlisted = true,
            exact_parameter_numbering_validated = true,
            exact_parameter_comment_order_validated = true,
            design_matrix = design_validation,
            constraint_max_abs_residual = constraint_residual,
        ),
        n_free_parameters = length(free_rows),
        n_semantic_rows = length(rows),
        free_parameter_rows = free_rows,
        parameter_rows = rows,
        rater_values = Tuple(source_values.rater),
        item_values = Tuple(source_values.item),
        threshold_values = source_values.steps === nothing ?
            Tuple(Tuple(steps) for steps in source_values.item_steps) :
            Tuple(source_values.steps),
        semantic_parameter_identity_resolved = true,
        source_gauge_validated = true,
        destination_gauge_aligned = false,
        destination_parameter_vector_ready = false,
        anchor_candidate_ready = false,
        convergence_validated = false,
        numerical_comparison_allowed = false,
        software_equivalence_claimed = false,
        caveat = :semantic_source_values_not_convergence_or_equivalence_evidence,
        next_gate = :align_conquest_source_values_to_reference_first_gauge,
    )
    return merge(payload, (;
        content_hash = artifact_content_hash(payload),
    ))
end
