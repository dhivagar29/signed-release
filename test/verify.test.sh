#!/usr/bin/env bash
# Offline tests for scripts/verify.sh: args + sha256 failure path.
# cosign/gh are stubbed so no network and no Sigstore contact.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY="${ROOT}/scripts/verify.sh"
PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then
    echo "PASS  ${label}"
    PASS=$((PASS + 1))
  else
    echo "FAIL  ${label}: expected=${expected} actual=${actual}" >&2
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    echo "PASS  ${label}"
    PASS=$((PASS + 1))
  else
    echo "FAIL  ${label}: missing '${needle}'" >&2
    echo "${haystack}" >&2
    FAIL=$((FAIL + 1))
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# Stub cosign/gh that succeed if invoked (sha256 tests should not reach them).
cat >"${TMP}/cosign" <<'STUB'
#!/usr/bin/env bash
echo "stub cosign: $*"
exit 0
STUB
cat >"${TMP}/gh" <<'STUB'
#!/usr/bin/env bash
echo "stub gh: $*"
exit 0
STUB
chmod +x "${TMP}/cosign" "${TMP}/gh"
export PATH="${TMP}:${PATH}"

# --- arg handling ---
set +e
OUT="$("${VERIFY}" 2>&1)"
RC=$?
set -e
assert_eq "missing args exit 2" "2" "${RC}"
assert_contains "missing args message" "required" "${OUT}"

set +e
OUT="$("${VERIFY}" --artifact /nope --checksums /nope --bundle /nope --bogus 2>&1)"
RC=$?
set -e
assert_eq "unknown arg exit 2" "2" "${RC}"
assert_contains "unknown arg message" "unknown argument" "${OUT}"

set +e
OUT="$("${VERIFY}" -h 2>&1)"
RC=$?
set -e
assert_eq "help exit 0" "0" "${RC}"
assert_contains "help usage" "Usage:" "${OUT}"

# --- sha256 failure path ---
"${ROOT}/scripts/build-artifact.sh" "test" >/dev/null
ARTIFACT="${ROOT}/dist/signed-release-test.tar.gz"
CHECKSUMS="${ROOT}/dist/SHA256SUMS.txt"
BUNDLE="${TMP}/fake.cosign.bundle"
printf 'fake-bundle\n' >"${BUNDLE}"

# Corrupt expected hash
BAD_SUMS="${TMP}/SHA256SUMS.bad.txt"
awk '{print "0000000000000000000000000000000000000000000000000000000000000000  " $2}' \
  "${CHECKSUMS}" >"${BAD_SUMS}"

set +e
OUT="$("${VERIFY}" --artifact "${ARTIFACT}" --checksums "${BAD_SUMS}" --bundle "${BUNDLE}" 2>&1)"
RC=$?
set -e
assert_eq "sha256 mismatch exit 1" "1" "${RC}"
assert_contains "sha256 mismatch message" "sha256 mismatch" "${OUT}"

# Missing basename in checksums
EMPTY_SUMS="${TMP}/SHA256SUMS.empty.txt"
printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  other.tar.gz\n' >"${EMPTY_SUMS}"
set +e
OUT="$("${VERIFY}" --artifact "${ARTIFACT}" --checksums "${EMPTY_SUMS}" --bundle "${BUNDLE}" 2>&1)"
RC=$?
set -e
assert_eq "missing checksum entry exit 1" "1" "${RC}"
assert_contains "missing checksum message" "no checksum entry" "${OUT}"

# Happy path through all three stubs
set +e
OUT="$("${VERIFY}" --artifact "${ARTIFACT}" --checksums "${CHECKSUMS}" --bundle "${BUNDLE}" 2>&1)"
RC=$?
set -e
assert_eq "happy path exit 0" "0" "${RC}"
assert_contains "happy path sha256" "1/3 sha256" "${OUT}"
assert_contains "happy path cosign" "2/3 cosign verify-blob" "${OUT}"
assert_contains "happy path gh" "3/3 gh attestation verify" "${OUT}"
assert_contains "happy path done" "All checks passed" "${OUT}"

# Missing files
set +e
OUT="$("${VERIFY}" --artifact "${TMP}/missing.tar.gz" --checksums "${CHECKSUMS}" --bundle "${BUNDLE}" 2>&1)"
RC=$?
set -e
assert_eq "missing artifact exit 1" "1" "${RC}"

echo
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "${FAIL}" -ne 0 ]]; then
  exit 1
fi
