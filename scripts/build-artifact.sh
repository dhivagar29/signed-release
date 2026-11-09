#!/usr/bin/env bash
# Build the dummy release tarball under dist/. Offline. No network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-dev}"
OUT_DIR="${ROOT}/dist"
STAGE="${OUT_DIR}/stage"
NAME="signed-release-${VERSION}"
TARBALL="${OUT_DIR}/${NAME}.tar.gz"
CHECKSUMS="${OUT_DIR}/SHA256SUMS.txt"

rm -rf "${OUT_DIR}"
mkdir -p "${STAGE}/${NAME}"

cp "${ROOT}/src/hello.sh" "${STAGE}/${NAME}/hello.sh"
chmod 0755 "${STAGE}/${NAME}/hello.sh"
printf '%s\n' "${VERSION}" >"${STAGE}/${NAME}/VERSION"
printf '%s\n' "signed-release dummy artifact" >"${STAGE}/${NAME}/README.txt"

tar -C "${STAGE}" -czf "${TARBALL}" "${NAME}"
(
  cd "${OUT_DIR}"
  sha256sum "$(basename "${TARBALL}")" >"${CHECKSUMS}"
)

printf 'Built %s\n' "${TARBALL}"
printf 'Checksums %s\n' "${CHECKSUMS}"
cat "${CHECKSUMS}"
