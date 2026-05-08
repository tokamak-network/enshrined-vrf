#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-tokamaknetwork/vrf-enclave}"
IMAGE_TAG="${IMAGE_TAG:-dev}"
IMAGE="${IMAGE_REPOSITORY}:${IMAGE_TAG}"
PLATFORM="${PLATFORM:-linux/amd64}"
PUSH="${PUSH:-0}"

command -v docker >/dev/null 2>&1 || {
  echo "missing required command: docker" >&2
  exit 1
}

args=(
  build
  --platform "$PLATFORM"
  -f "$ROOT/vrf-enclave/Dockerfile"
  -t "$IMAGE"
  "$ROOT"
)

echo "[image] building $IMAGE for $PLATFORM"
docker "${args[@]}"

if [ "$PUSH" = "1" ]; then
  echo "[image] pushing $IMAGE"
  docker push "$IMAGE"
else
  echo "[image] built $IMAGE"
  echo "Set PUSH=1 to push this tag."
fi
