# Changelog

## Unreleased

The PostgreSQL port of uxid: prefixed, K-sortable identifiers a person can
read, wire-compatible with the Elixir `uxid` package. No version has been
released yet. The build is in place: the extension `uxid` (its control file
and a 1.0.0 script that holds only `uxid_version()`), a PGXS `Makefile` with
no compiled module, `pg_regress` tests and the local gate. Generation,
decoding, the validity checks, the `uxid` domain and the monotonic generator
arrive in later changes.
