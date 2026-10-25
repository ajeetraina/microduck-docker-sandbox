#!/usr/bin/env bash
# Boot a Docker Sandboxes (sbx) microVM, run the Microduck simulator as a nested container
# inside it, and forward the viewer + lab ports out to the host.
#
#   ./scripts/sbx-run.sh            # air-gapped if ./microduck.tar exists, else pulls
#
# Env overrides: IMAGE, NAME, MEM, VIEWER_PORT, LAB_PORT, TARBALL
#
# This mirrors docs/sandbox-setup.md step for step. If a step errors on your sbx version,
# run the documented commands by hand - the flags move between releases.
set -euo pipefail

IMAGE="${IMAGE:-ajeetraina777/microduck-docker:latest}"
NAME="${NAME:-microduck}"
MEM="${MEM:-4GB}"
VIEWER_PORT="${VIEWER_PORT:-63317}"
LAB_PORT="${LAB_PORT:-8788}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARBALL="${TARBALL:-$REPO_ROOT/microduck.tar}"

command -v sbx >/dev/null || { echo "sbx not found - brew install docker/tap/sbx" >&2; exit 1; }

sbx_exec() { sbx exec "$NAME" "$@"; }

# 1. create the sandbox (mount this repo so an air-gapped tar is visible inside)
if sbx ls --json 2>/dev/null | grep -q "\"$NAME\""; then
  echo "Sandbox '$NAME' already exists - reusing it."
else
  echo "Creating sandbox '$NAME' (mem=$MEM) ..."
  sbx create shell "$REPO_ROOT" --name "$NAME" -m "$MEM"
fi

# 2. verify a Docker daemon is present inside the VM
if ! sbx_exec docker info >/dev/null 2>&1; then
  echo "No Docker daemon inside '$NAME'. Your 'shell' template lacks one -" >&2
  echo "recreate with a -docker template variant (see docs/sandbox-setup.md)." >&2
  exit 1
fi

# 3. get the image into the sandbox: load the tar if present, else pull
if [ -f "$TARBALL" ]; then
  echo "Loading $TARBALL inside the sandbox (air-gapped) ..."
  sbx_exec docker load -i "$TARBALL"
else
  echo "No $TARBALL found - pulling $IMAGE inside the sandbox."
  echo "  (needs: sbx policy allow network \"registry-1.docker.io,auth.docker.io,*.docker.com\")"
  sbx_exec docker pull "$IMAGE"
fi

# 4. run the simulator inside the sandbox.
# Give the container a fixed name and replace any prior one, so re-running this
# script is idempotent instead of colliding on the published ports.
# sbx exec has no detached mode (-d is rejected), so detach the *container*
# with "docker run -d" instead - the exec returns as soon as Docker backgrounds it.
CONTAINER="${CONTAINER:-microduck-sim}"
# Remove any prior container for this image (by fixed name or a leftover random
# name from an earlier run) so the published ports are free.
OLD="$(sbx_exec docker ps -aq -f "ancestor=$IMAGE" | tr '\n' ' ')"
if [ -n "${OLD// /}" ]; then
  echo "Replacing existing Microduck container(s) ..."
  # shellcheck disable=SC2086
  sbx_exec docker rm -f $OLD >/dev/null
fi
echo "Starting the simulator ..."
sbx_exec docker run -d --rm --name "$CONTAINER" \
  -p "${VIEWER_PORT}:63317" -p "${LAB_PORT}:8788" "$IMAGE"

# 5. forward both ports out of the VM to the host.
# Host->VM forwards persist at the sandbox level across container restarts, so
# publish a port only if it is not already forwarded (re-publishing 409s).
echo "Forwarding ports to the host ..."
publish_port() {
  local port="$1"
  # "sbx ports" prints a table; HOST PORT is column 2. Skip if already forwarded.
  if sbx ports "$NAME" 2>/dev/null | awk -v p="$port" 'NR>1 && $2==p{f=1} END{exit !f}'; then
    echo "  port ${port} already forwarded - skipping."
  else
    sbx ports "$NAME" --publish "${port}:${port}"
  fi
}
publish_port "$VIEWER_PORT"
publish_port "$LAB_PORT"

cat <<EOF

🦆  Microduck is starting inside sandbox '$NAME'.
    Open  http://localhost:${VIEWER_PORT}

    Logs:   sbx exec $NAME docker logs -f $CONTAINER
    Stop:   sbx exec $NAME docker rm -f $CONTAINER   (or: sbx stop $NAME)
    Remove: sbx rm $NAME
EOF
