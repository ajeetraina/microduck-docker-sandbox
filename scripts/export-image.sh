#!/usr/bin/env bash
# Pull the Microduck image on the host and save it to a tarball in this repo, so it can be
# carried into an air-gapped sandbox and loaded with `docker load` (no runtime network).
#
#   ./scripts/export-image.sh
#
# Env overrides: IMAGE, TARBALL
set -euo pipefail

IMAGE="${IMAGE:-ajeetraina777/microduck-docker:latest}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARBALL="${TARBALL:-$REPO_ROOT/microduck.tar}"

command -v docker >/dev/null || { echo "docker not found on host" >&2; exit 1; }

echo "Pulling $IMAGE ..."
docker pull "$IMAGE"

echo "Saving to $TARBALL ..."
docker save "$IMAGE" -o "$TARBALL"

size=$(du -h "$TARBALL" | cut -f1)
echo "Done: $TARBALL ($size)"
echo "Next: ./scripts/sbx-run.sh   (it will load this tar inside the sandbox)"
