#!/usr/bin/env bash
# Prints the versions the extension built from this tree reports. It builds
# the gate image (docker/Dockerfile), runs a container from it that copies
# the tree, runs `make install`, starts a throwaway cluster, runs
# `CREATE EXTENSION uxid` and prints one line, `<uxid_version()>
# <extversion>`: what the function returns, then the version CREATE
# EXTENSION installed (default_version in uxid.control). The release
# workflow compares both with the tag. The container is removed when it
# exits (`--rm`), and nothing is written to the working tree, which is
# mounted read-only.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="uxid-pg-gate:local"

docker build --quiet --tag "$image" "$root/docker" >/dev/null

# The image's entrypoint passes a command other than `postgres` straight
# through, so the cluster the script starts is the only server that runs.
docker run --rm --interactive --volume "$root:/src:ro" "$image" bash -s <<'SCRIPT'
set -euo pipefail
mkdir /build
tar -C /src --exclude=./.git --exclude=./.beads -cf - . | tar -C /build -xf -
make -C /build install >/dev/null
gosu postgres initdb --auth=trust --pgdata=/tmp/pgdata >/dev/null
gosu postgres pg_ctl --pgdata=/tmp/pgdata --options="-c listen_addresses=" --wait start >/dev/null
gosu postgres psql --no-psqlrc --quiet --tuples-only --no-align \
  --set=ON_ERROR_STOP=1 --dbname=postgres <<'SQL'
CREATE EXTENSION uxid;
SELECT uxid_version() || ' ' || e.extversion
FROM pg_extension AS e
WHERE e.extname = 'uxid';
SQL
SCRIPT
