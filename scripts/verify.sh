#!/usr/bin/env bash
# Verify a signed-release artifact: sha256, cosign keyless blob, gh attestation.
# Does not perform signing. Network is only needed for cosign/gh checks.
set -euo pipefail

readonly DEFAULT_REPO="dhivagar29/signed-release"
readonly DEFAULT_ISSUER="https://token.actions.githubusercontent.com"
# Certificate identity URI written by GitHub Actions keyless signing.
readonly DEFAULT_IDENTITY_REGEXP='^https://github\.com/dhivagar29/signed-release/\.github/workflows/release\.yml@refs/tags/v.+$'

usage() {
  cat <<'USAGE'
Usage: verify.sh --artifact PATH --checksums PATH --bundle PATH [--repo OWNER/REPO]

Checks (in order):
  1. sha256 of the artifact against SHA256SUMS.txt
  2. cosign verify-blob (keyless) with identity regexp + OIDC issuer
  3. gh attestation verify against the repository

Environment overrides:
  SIGNED_RELEASE_IDENTITY_REGEXP  cosign --certificate-identity-regexp
  SIGNED_RELEASE_OIDC_ISSUER      cosign --certificate-oidc-issuer
USAGE
}

ARTIFACT=""
CHECKSUMS=""
BUNDLE=""
REPO="${DEFAULT_REPO}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact)
      [[ $# -ge 2 ]] || { echo "error: --artifact needs a value" >&2; exit 2; }
      ARTIFACT="$2"
      shift 2
      ;;
    --checksums)
      [[ $# -ge 2 ]] || { echo "error: --checksums needs a value" >&2; exit 2; }
      CHECKSUMS="$2"
      shift 2
      ;;
    --bundle)
      [[ $# -ge 2 ]] || { echo "error: --bundle needs a value" >&2; exit 2; }
      BUNDLE="$2"
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 ]] || { echo "error: --repo needs a value" >&2; exit 2; }
      REPO="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${ARTIFACT}" || -z "${CHECKSUMS}" || -z "${BUNDLE}" ]]; then
  echo "error: --artifact, --checksums and --bundle are required" >&2
  usage >&2
  exit 2
fi

if [[ ! -f "${ARTIFACT}" ]]; then
  echo "error: artifact not found: ${ARTIFACT}" >&2
  exit 1
fi
if [[ ! -f "${CHECKSUMS}" ]]; then
  echo "error: checksums file not found: ${CHECKSUMS}" >&2
  exit 1
fi
if [[ ! -f "${BUNDLE}" ]]; then
  echo "error: cosign bundle not found: ${BUNDLE}" >&2
  exit 1
fi

IDENTITY_REGEXP="${SIGNED_RELEASE_IDENTITY_REGEXP:-${DEFAULT_IDENTITY_REGEXP}}"
OIDC_ISSUER="${SIGNED_RELEASE_OIDC_ISSUER:-${DEFAULT_ISSUER}}"

ARTIFACT_BASENAME="$(basename "${ARTIFACT}")"
ARTIFACT_DIR="$(cd "$(dirname "${ARTIFACT}")" && pwd)"

echo "==> 1/3 sha256"
# Resolve checksum for this basename and verify against the real file path.
EXPECTED_LINE="$(grep -E "[[:space:]]${ARTIFACT_BASENAME}\$" "${CHECKSUMS}" || true)"
if [[ -z "${EXPECTED_LINE}" ]]; then
  echo "error: no checksum entry for ${ARTIFACT_BASENAME} in ${CHECKSUMS}" >&2
  exit 1
fi
EXPECTED_HASH="${EXPECTED_LINE%% *}"
ACTUAL_HASH="$(sha256sum "${ARTIFACT}" | awk '{print $1}')"
if [[ "${EXPECTED_HASH}" != "${ACTUAL_HASH}" ]]; then
  echo "error: sha256 mismatch for ${ARTIFACT_BASENAME}" >&2
  echo "  expected: ${EXPECTED_HASH}" >&2
  echo "  actual:   ${ACTUAL_HASH}" >&2
  exit 1
fi
printf 'OK  %s  %s\n' "${ACTUAL_HASH}" "${ARTIFACT_BASENAME}"

echo "==> 2/3 cosign verify-blob (keyless)"
if ! command -v cosign >/dev/null 2>&1; then
  echo "error: cosign not found on PATH" >&2
  exit 1
fi
cosign verify-blob \
  --bundle "${BUNDLE}" \
  --certificate-identity-regexp "${IDENTITY_REGEXP}" \
  --certificate-oidc-issuer "${OIDC_ISSUER}" \
  "${ARTIFACT}"
echo "OK  cosign verify-blob"

echo "==> 3/3 gh attestation verify"
if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh not found on PATH" >&2
  exit 1
fi
gh attestation verify "${ARTIFACT}" --repo "${REPO}" \
  --signer-workflow "${REPO}/.github/workflows/release.yml"
echo "OK  gh attestation verify"

echo
echo "All checks passed for ${ARTIFACT_DIR}/${ARTIFACT_BASENAME}"
