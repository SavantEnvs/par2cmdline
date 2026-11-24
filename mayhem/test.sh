#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Upstream's own suite, built by mayhem/build.sh in mayhem/build/tests: the unit
# tests (crc/md5/galois/reedsolomon/utf8/... known-answer tests) and the
# tests/testN integration scripts, which create/verify/repair real PAR1/PAR2
# sets with the par2 tool and check the repaired files byte-for-byte.
B="$SRC/mayhem/build/tests"
if [ ! -f "$B/CTestTestfile.cmake" ] || [ ! -x "$B/par2" ]; then
  echo "test suite not built: run mayhem/build.sh first" >&2
  emit_ctrf "cmake-ctest" 0 1 0
  exit 1
fi
log=$(mktemp)
(cd "$B" && ctest --output-on-failure -j"$MAYHEM_JOBS") 2>&1 | tee "$log"
total=$(sed -nE 's/.*tests passed, ([0-9]+) tests failed out of ([0-9]+).*/\2/p' "$log" | tail -1)
failed=$(sed -nE 's/.*tests passed, ([0-9]+) tests failed out of ([0-9]+).*/\1/p' "$log" | tail -1)
skipped=$(grep -cE '\*\*\*Skipped|Not Run' "$log" || true)
rm -f "$log"
if [ -z "$total" ]; then
  echo "could not parse ctest summary" >&2
  emit_ctrf "cmake-ctest" 0 1 0
  exit 1
fi
passed=$(( total - failed - skipped ))
emit_ctrf "cmake-ctest" "$passed" "$failed" "$skipped"
