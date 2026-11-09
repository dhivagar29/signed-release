#!/usr/bin/env bash
# Dummy portfolio payload. Contains nothing private.
set -euo pipefail
echo "hello from signed-release"
echo "version=${SIGNED_RELEASE_VERSION:-dev}"
