#!/usr/bin/env bash
# Builds the gate image, starts PostgreSQL in a container, installs the
# extension and runs `make installcheck` against that server. The
# container is removed on every exit, a failed step included.
#
# The repository is mounted read-only and copied to /build inside the
# container, so the build and pg_regress's results/ and regression.diffs
# stay in the container and nothing is written to the working tree.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="uxid-pg-gate:local"
name="uxid-pg-gate-$$-$(date +%s)"

cleanup() { docker rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT

printf '\n==> %s\n' "build the gate image (${image})"
docker build --quiet --tag "$image" "$root/docker"

printf '\n==> %s\n' "start the server (${name})"
docker run --detach --name "$name" \
  --env POSTGRES_HOST_AUTH_METHOD=trust \
  --volume "$root:/src:ro" \
  "$image" >/dev/null

# The image's entrypoint first runs a socket-only server to initialise
# the cluster, then restarts it listening on TCP; waiting on TCP waits
# for the final server.
ready=0
for _ in $(seq 1 60); do
  if docker exec "$name" pg_isready --quiet --host 127.0.0.1 --username postgres; then
    ready=1
    break
  fi
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  echo "the server did not accept connections within 60 seconds" >&2
  docker logs "$name" >&2
  exit 1
fi

printf '\n==> %s\n' "server version"
docker exec "$name" psql --no-psqlrc --tuples-only --no-align \
  --host 127.0.0.1 --username postgres --command 'SELECT version()'

printf '\n==> %s\n' "copy the tree and make install"
docker exec "$name" bash -c '
  set -euo pipefail
  mkdir /build
  tar -C /src --exclude=./.git --exclude=./.beads -cf - . | tar -C /build -xf -
  chown -R postgres:postgres /build
  make -C /build install
'

printf '\n==> %s\n' "make installcheck"
if ! docker exec --user postgres --workdir /build \
  --env PGHOST=127.0.0.1 --env PGUSER=postgres \
  "$name" make installcheck; then
  printf '\n==> %s\n' "regression.diffs"
  docker exec "$name" cat /build/regression.diffs || true
  exit 1
fi
