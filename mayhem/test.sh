#!/usr/bin/env bash
#
# amqp091-go/mayhem/test.sh — RUN amqp091-go's OWN Go unit test suite and emit a CTRF summary.
# exit 0 iff no test failed.
#
# PATCH-grade oracle: upstream's unit suite (allocator_test.go, auth_test.go, channel_test.go,
# client_test.go, confirms_test.go, connection_unit_test.go, consumers_test.go, delivery_test.go,
# read_test.go, tls_test.go, types_test.go, uri_test.go, write_test.go, …) is a REAL
# known-answer suite — cases assert exact parsed URIs, frame (de)serialization bytes, confirm
# resequencing order and delivery semantics against golden expectations, so a no-op/exit(0)
# patch FAILS it. The integration-tagged tests (connection_test.go, integration_test.go,
# recovery_test.go — 91 test funcs) require a live RabbitMQ broker and are NOT run here.
#
# This script does NOT compile: mayhem/build.sh pre-built the runner (normal flags) at
# $SRC/mayhem-build/amqp091-go.test with -linkmode=external, so the binary is dynamically
# linked and the §6.3 LD_PRELOAD sabotage check can neuter it (a neutered runner emits no
# "--- PASS" lines -> 0 tests parsed -> this oracle FAILS -> not reward-hackable). A second
# behavioral probe runs the (also dynamically linked) fuzz target single-shot on a seed frame.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
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

RUNNER="$SRC/mayhem-build/amqp091-go.test"
if [ ! -x "$RUNNER" ]; then
  echo "test runner $RUNNER missing — mayhem/build.sh must pre-build it (do not compile here)" >&2
  emit_ctrf "go-test" 0 1 0; exit 2
fi

OUT="/tmp/amqp091-go-test.out"
echo "=== running: $RUNNER -test.v (upstream unit suite, pre-built by build.sh) ==="
"$RUNNER" -test.v > "$OUT" 2>&1; rc=$?
tail -15 "$OUT"

# Count test-level results (subtests included — they are real asserted cases).
PASSED=$(grep -c -- '--- PASS: ' "$OUT" || true)
FAILED=$(grep -c -- '--- FAIL: ' "$OUT" || true)
SKIPPED=$(grep -c -- '--- SKIP: ' "$OUT" || true)
: "${PASSED:=0}" "${FAILED:=0}" "${SKIPPED:=0}"

# A neutered/silent runner (or a crash before any test ran) parses as 0 events — fail honestly.
if [ "$(( PASSED + FAILED + SKIPPED ))" -eq 0 ]; then
  echo "no test results parsed from the runner output (exit $rc) — treating as failure" >&2
  emit_ctrf "go-test" 0 1 0; exit 1
fi
# Trust parsed failures; if the runner exited non-zero with 0 parsed failures, force one.
if [ "$rc" -ne 0 ] && [ "$FAILED" -eq 0 ]; then FAILED=1; fi

# ── Behavioral probe (§6.3): run the dynamically-linked fuzz target single-shot on a minimal
# AMQP heartbeat frame and assert libFuzzer's "Executed" marker — proves the fuzz target
# actually drives reader.ReadFrame (and is neutered under the sabotage LD_PRELOAD -> probe fails).
if [ -x /mayhem/fuzz-amqp091-go ]; then
  echo "=== behavioral probe: fuzz-amqp091-go single-shot on a heartbeat frame ==="
  printf '\x08\x00\x00\x00\x00\x00\x00\xce' > /tmp/amqp-probe.bin
  PROBE_OUT=$(/mayhem/fuzz-amqp091-go -runs=1 /tmp/amqp-probe.bin 2>&1 || true)
  if echo "$PROBE_OUT" | grep -q "Executed"; then
    echo "PROBE PASS: fuzz-amqp091-go executed the seed"
    PASSED=$(( PASSED + 1 ))
  else
    echo "PROBE FAIL: fuzz-amqp091-go produced no 'Executed' output"; echo "$PROBE_OUT" | tail -5
    FAILED=$(( FAILED + 1 ))
  fi
fi

emit_ctrf "go-test" "$PASSED" "$FAILED" "$SKIPPED"
