# The local gate's server: the official PostgreSQL 18 image, pinned by its
# multi-arch index digest. The image already ships PGXS and pg_regress; it
# lacks make, which PGXS needs, so make is the one package added.
FROM postgres:18@sha256:edb0c08dc33befd0262ab3b5cf1c4f3f8cfd8b09e88c05b45adee29d6761ddb6

RUN apt-get update \
    && apt-get install -y --no-install-recommends make \
    && rm -rf /var/lib/apt/lists/*
