#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/dist/ChirpOS.app/Contents/MacOS/Birding"
if [[ ! -x "$BIN" ]]; then
    printf 'Build the development app before running this verification.\n' >&2
    exit 1
fi
OUT="$(mktemp -d "$ROOT/.build/behavior-stress.XXXXXX")"
printf 'Evidence: %s\n' "$OUT"

# Run serially so competing benchmark processes do not inflate callback times.
# /usr/bin/time records process-wide peak RSS, not retained heap or renderer cost.
run_case() {
    local label="$1" seconds="$2" birds="$3" displays="$4" mode="${5:-scripted}"
    /usr/bin/time -l "$BIN" --stress-behavior "$OUT/$label.json" \
        --stress-seconds "$seconds" --stress-birds "$birds" \
        --stress-displays "$displays" --stress-seed 73 --stress-mode "$mode" \
        > "$OUT/$label.log" 2> "$OUT/$label-resources.txt"
    cat "$OUT/$label.log"
}
# Malformed options must fail normally before creating a desktop app or report.
reject_options() {
    local label="$1" status=0
    shift
    "$BIN" "$@" > "$OUT/invalid-$label.log" 2>&1 || status=$?
    if [[ "$status" -ne 1 ]]; then
        printf 'Invalid options returned unexpected exit %s: %s\n' "$status" "$label" >&2
        exit 1
    fi
}
for invalid in nan inf -1 0 3601; do
    reject_options "duration-$invalid" --stress-behavior "$OUT/invalid.json" --stress-seconds "$invalid"
done
reject_options missing-path --stress-behavior
reject_options duplicate --stress-behavior "$OUT/invalid.json" --stress-birds 2 --stress-birds 3
reject_options unknown --stress-behavior "$OUT/invalid.json" --stress-unknown 1
reject_options birds --stress-behavior "$OUT/invalid.json" --stress-birds 65
reject_options displays --stress-behavior "$OUT/invalid.json" --stress-displays 0
reject_options seed --stress-behavior "$OUT/invalid.json" --stress-seed -1
reject_options mode --stress-behavior "$OUT/invalid.json" --stress-mode unknown
if [[ -e "$OUT/invalid.json" ]]; then
    printf 'Invalid input unexpectedly wrote a report.\n' >&2
    exit 1
fi
run_case ordinary 600 24 2
run_case crowded 600 64 4
run_case long 3600 12 2 autonomous
printf 'Evidence: %s\n' "$OUT"
