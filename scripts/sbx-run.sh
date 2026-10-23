#!/usr/bin/env bash
# Boot a Docker Sandboxes (sbx) microVM, run the Microduck simulator as a nested container
# inside it, and forward the viewer + lab ports out to the host.
#
#   ./scripts/sbx-run.sh            # air-gapped if ./microduck.tar exists, else pulls
#
# Env overrides: IMAGE, NAME, MEM, VIEWER_PORT, LAB_PORT, TARBALL
#
# This mirrors docs/sandbox-setup.md step for step. If a step errors on your sbx version,
# run the documented commands by hand — the flags move between releases.
set -euo pipefail

IMAGE="${IMAGE:-ajeetraina777/microduck-docker:latest}"
NAME="${NAME:-microduck}"
MEM="${MEM:-4GB}"
VIEWER_PORT="${VIEWER_PORT:-63317}"
LAB_PORT="${LAB_PORT:-8788}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARBALL="${TARBALL:-$REPO_ROOT/microduck.tar}"

command -v sbx >/dev/null || { echo "sbx not found — brew install docker/tap/sbx" >&2; exit 1; }

sbx_exec() { sbx exec "$NAME" "$@"; }

# 1. create the sandbox (mount this repo so an air-gapped tar is visible inside)
if sbx ls --json 2>/dev/null | grep -q "\"$NAME\""; then
  echo "Sandbox '$NAME' already exists — reusing it."
else
  echo "Creating sandbox '$NAME' (mem=$MEM) ..."
  sbx create shell "$REPO_ROOT" --name "$NAME" -m "$MEM"
fi

# 2. verify a Docker daemon is present inside the VM
if ! sbx_exec docker info >/dev/null 2>&1; then
  echo "No Docker daemon inside '$NAME'. Your 'shell' template lacks one —" >&2
  echo "recreate with a -docker template variant (see docs/sandbox-setup.md)." >&2
  exit 1
fi

# 3. get the image into the sandbox: load the tar if present, else pull
if [ -f "$TARBALL" ]; then
  echo "Loading $TARBALL inside the sandbox (air-gapped) ..."
  sbx_exec docker load -i "$TARBALL"
else
  echo "No $TARBALL found — pulling $IMAGE inside the sandbox."
  echo "  (needs: sbx policy allow network \"registry-1.docker.io,auth.docker.io,*.docker.com\")"
  sbx_exec docker pull "$IMAGE"
fi

# 4. run the simulator, detached, inside the sandbox
echo "Starting the simulator ..."
sbx exec -d "$NAME" docker run --rm \
  -p "${VIEWER_PORT}:63317" -p "${LAB_PORT}:8788" "$IMAGE"

# 5. forward both ports out of the VM to the host
echo "Forwarding ports to the host ..."
sbx ports "$NAME" --publish "${VIEWER_PORT}:${VIEWER_PORT}"
sbx ports "$NAME" --publish "${LAB_PORT}:${LAB_PORT}"

cat <<EOF

🦆  Microduck is starting inside sandbox '$NAME'.
    Open  http://localhost:${VIEWER_PORT}

    Logs:   sbx exec $NAME docker logs -f \$(sbx exec $NAME docker ps -q)
    Stop:   sbx stop $NAME   (re-run this script's port step after restart)
    Remove: sbx rm $NAME
EOF
