# The uxid extension, built and tested with PGXS. The extension is SQL
# only: there is no compiled module.
EXTENSION = uxid
DATA = uxid--1.0.0.sql

# One name per test/sql/<name>.sql, with its expected output in
# test/expected/<name>.out.
REGRESS = version surface base32 encode check_request generate from \
	from_encoding binding decode decode_refusals decode_encoding validity \
	domain
REGRESS_OPTS = --inputdir=test

PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
