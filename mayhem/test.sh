#!/usr/bin/env bash
#
# mayhem/test.sh — RUN astroterm's own Unity unit tests (built by mayhem/build.sh into build_coverage/)
# and report CTRF counts. Counts come from each binary's Unity summary line ("N Tests F Failures I
# Ignored"), not from exit codes, so a neutered binary that prints nothing fails loudly.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"
# drawing_test renders Unicode (smooth/braille) glyphs and calls setlocale(LC_ALL, ""); the image has no locale set.
export LC_ALL=C.UTF-8

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

TESTS="coord_test astro_test city_test bit_test core_test stopwatch_test drawing_test misc_test"
# Number of test cases upstream's suite defines (RUN_TEST calls); a run that reports fewer is a failure.
EXPECTED=43

passed=0 failed=0 skipped=0
cd build_coverage || { echo "build_coverage/ missing: mayhem/build.sh did not run" >&2; emit_ctrf "unity" 0 1 0; exit 1; }

for t in $TESTS; do
  if [ ! -x "./$t" ]; then
    echo "missing test binary build_coverage/$t" >&2
    failed=$((failed + 1))
    continue
  fi
  out=$("./$t" 2>&1)
  rc=$?
  echo "$out"
  summary=$(printf '%s\n' "$out" | grep -E '^[0-9]+ Tests [0-9]+ Failures [0-9]+ Ignored' | tail -n1)
  if [ -z "$summary" ]; then
    echo "no Unity summary from $t (exit $rc)" >&2
    failed=$((failed + 1))
    continue
  fi
  read -r n _ f _ i _ <<<"$summary"
  failed=$((failed + f))
  skipped=$((skipped + i))
  passed=$((passed + n - f - i))
  [ "$rc" -eq 0 ] || [ "$f" -gt 0 ] || failed=$((failed + 1))
done

if [ $((passed + failed + skipped)) -lt "$EXPECTED" ]; then
  echo "expected at least $EXPECTED test cases, saw $((passed + failed + skipped))" >&2
  failed=$((failed + 1))
fi

emit_ctrf "unity" "$passed" "$failed" "$skipped"
