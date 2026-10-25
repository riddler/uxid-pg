# uxid

[![MIT License][badge_license_url]](LICENSE)
[![CI][badge_ci_url]](https://github.com/riddler/uxid-pg/actions/workflows/ci.yml)

User eXperience focused IDentifiers for PostgreSQL: prefixed, K-sortable,
Stripe-style ids a person can read, copy and route back to their resource. An
id looks like `usr_01hf7yat0004h1`: the prefix names the resource, and the
body carries a time and randomness in lower-case Crockford Base32. The ids
follow the wire format of the Elixir reference implementation,
[uxid-ex](https://github.com/riddler/uxid-ex), and the extension is checked
against that implementation's conformance corpus, every case, with no skip
list.

It is a PostgreSQL extension named `uxid`, written in SQL and PL/pgSQL. It
generates ids (random, deterministic and monotonic), decodes them, checks them,
and provides a `uxid` domain for columns. Every function name starts `uxid_`.

## Why UXID

An auto-increment key leaks how many rows a table holds and invites
enumeration; a random UUID fixes both but is long, unordered and anonymous, so
in a log line, a URL or a support thread nobody can tell what it points at, and
a double-click selects only part of it. A UXID names its resource in its
prefix, selects whole on a double-click, reads aloud without ambiguity, sorts
by creation time so it indexes well, and is generated with no coordination
between nodes. Its size is tunable for low-cardinality resources, a monotonic
generator keeps a burst within one millisecond unique and in order, and a
deterministic mode maps the same input to the same id.

Because the format is shared, an id this extension makes is read by the other
implementations of the format, and the other way round.

## Install

Version 1.0.0 is a GitHub release. The
[releases page](https://github.com/riddler/uxid-pg/releases) carries
`uxid-pg-1.0.0.tar.gz` and its `uxid-pg-1.0.0.tar.gz.sha256`. Pick one of
three paths.

### CREATE EXTENSION, from the release tarball

You need the server's development files, `make`, and `pg_config` on your
`PATH` for the server you install into.

```bash
curl -fsSLO https://github.com/riddler/uxid-pg/releases/download/v1.0.0/uxid-pg-1.0.0.tar.gz
curl -fsSLO https://github.com/riddler/uxid-pg/releases/download/v1.0.0/uxid-pg-1.0.0.tar.gz.sha256
sha256sum --check uxid-pg-1.0.0.tar.gz.sha256   # on macOS: shasum -a 256 -c
tar -xzf uxid-pg-1.0.0.tar.gz
cd uxid-pg-1.0.0
make install
```

`make install` copies `uxid.control` and `uxid--1.0.0.sql` into the server's
extension directory, so run it as a user who may write there. There is no
compiled module. Then, in each database that wants it:

```sql
CREATE EXTENSION uxid;
```

The control file sets `superuser = false`, so any role with CREATE on the
schema the extension installs into may run `CREATE EXTENSION uxid`; the
extension needs no other privilege and is relocatable (`CREATE EXTENSION uxid
SCHEMA ids`). A role without CREATE on that schema is refused with `permission
denied for schema`.

### The script as a plain migration

When you cannot put files on the server, run the extension script once, in the
database, from the release tarball (or a checkout):

```bash
psql -v ON_ERROR_STOP=1 -d mydb -f uxid--1.0.0.sql
```

This creates the same functions and the `uxid` domain, but no extension owns
them. What that gives up:

- `DROP EXTENSION`, `ALTER EXTENSION ... UPDATE` and `ALTER EXTENSION ... SET
  SCHEMA` do not apply; the objects are dropped, moved and changed by hand.
- A later `CREATE EXTENSION uxid` in the same schema fails, because the
  functions already exist. Pick one path per database.
- The script runs once. An upgrade is a later upgrade script that you run by
  hand in the same way; running the 1.0.0 script a second time is an error.

### pg_tle, for managed services that load no custom files

On a managed service that provides
[pg_tle](https://github.com/aws/pg_tle), install the script through
`pgtle.install_extension`, which stores it in the database. With `psql`, in the
directory of the release tarball:

```bash
psql -v ON_ERROR_STOP=1 -d mydb \
  -v version=1.0.0 \
  -v comment='Prefixed, K-sortable, human-readable identifiers (UXID)' \
  -v file=uxid--1.0.0.sql <<'SQL'
\set script `cat :'file'`
CREATE EXTENSION IF NOT EXISTS pg_tle;
SELECT pgtle.install_extension('uxid', :'version', :'comment', :'script');
CREATE EXTENSION uxid;
SQL
```

`CREATE EXTENSION pg_tle` may need a role the service reserves for it, and the
service decides who may call `pgtle.install_extension`. CI proves this path on
PostgreSQL 17 with pg_tle v1.5.3.

## Basic usage

```sql
-- A prefix names the resource; the body is a time and randomness.
SELECT uxid_generate('usr');                  -- usr_01m5t0nf900v4jbj9kj746cran

-- A column default; the domain checks every value stored.
CREATE TABLE doc (
    id    uxid PRIMARY KEY DEFAULT uxid_generate('doc'),
    title text NOT NULL
);

-- Shrink the random part for low-cardinality resources: xs s m l xl.
SELECT uxid_generate('usr', 's');             -- usr_01m5t0nf91s021

-- Deterministic: the same prefix and key give the same id, every time.
SELECT uxid_from('usr', 'alice@example.com'); -- usr_zcvt7epac0t1ebcsjfyf7cwz25

-- Read an id back. The result is one row.
SELECT * FROM uxid_decode('doc_01hf7yat0004h1');
--  prefix | size | compact | deterministic |    time_ms
-- --------+------+---------+---------------+---------------
--  doc    | s    | f       | f             | 1700000000000

SELECT uxid_is_valid('doc_01hf7yat0004h1', required_prefix => 'doc');  -- t
SELECT uxid_decode_error('doc_');             -- empty
SELECT uxid_is_deterministic('usr_zcvt7epac0t1ebcsjfyf7cwz25');        -- t

-- Monotonic: ids from one session increase strictly, also within one
-- millisecond.
SELECT uxid_monotonic('usr') < uxid_monotonic('usr');                  -- t
```

The values on random lines differ on every call. Every function takes and
returns plain `text`. `uxid_decode` returns the time of a compact id against
the transaction time; give it a `clock_ms` to decode against another clock.

`uxid_check_request`, `uxid_encode`, `uxid_from`, `uxid_decode_at`,
`uxid_decode_error`, `uxid_is_valid`, `uxid_is_deterministic`,
`uxid_monotonic_step` and `uxid_version` are `IMMUTABLE`, as PostgreSQL asks of
a function that depends only on its arguments. The usual caveat follows: when
every argument is a constant, the planner may evaluate the call early, even
inside a `CASE` branch that no row reaches, and a refusal then raises at plan
time. Keep the arguments of such a call out of a `CASE` that guards against
them being invalid, or validate them first.

### The functions

`\df+ uxid_*` lists them (and the internal helpers) with their comments, and each function's
`COMMENT ON FUNCTION` states what it accepts, answers and refuses; the comment
is the reference.

| Function | What it does |
|---|---|
| `uxid_generate(prefix, size, compact, rand_size, letter_case, delimiter, time_ms)` | A time-based id with random bytes from `gen_random_uuid()`. Volatile. |
| `uxid_from(prefix, key, size, letter_case, delimiter)` | The deterministic id of a key: SHA-256 of the prefix and key. |
| `uxid_monotonic(prefix, size, compact, rand_size, letter_case, delimiter, time_ms)` | An id that sorts after the last one this session made for the prefix and width. Volatile, parallel unsafe. |
| `uxid_decode(id, clock_ms, delimiter)` | One row: prefix, size, compact flag, deterministic flag, time in ms. Raises on a malformed id. |
| `uxid_decode_at(id, clock_ms, delimiter)` | The pure decoder against a clock you pass. |
| `uxid_decode_error(id, delimiter)` | Why `uxid_decode` would refuse the id, or `NULL`. Never raises. |
| `uxid_is_valid(id, delimiter, required_prefix)` | Whether the id decodes, with an optional required prefix. |
| `uxid_is_deterministic(id, delimiter)` | Whether the id is a well-formed deterministic id. |
| `uxid_encode(prefix, size, time_ms, rand, ...)` | The pure encoder for a fixed time and fixed random bytes: test vectors, never a source of random ids. |
| `uxid_monotonic_step(...)` | The monotonic generator's pure step. |
| `uxid_check_request(...)` | Refuses a generation request the format forbids. |
| `uxid_version()` | The installed script's version. |

Names that start `uxid__` (two underscores) are internal helpers and not part
of the public surface.

## The uxid domain and why it uses COLLATE "C"

```sql
CREATE DOMAIN uxid AS text COLLATE "C"
    CHECK (uxid_is_valid(VALUE));
```

The extension script defines it. The check uses the
default delimiter `_` only, and a `NULL` passes it, as a column's `NOT NULL`
decides that. The functions above take and return plain `text`, so a `text`
column works unchanged; `ALTER TABLE doc ALTER COLUMN id TYPE uxid` is the
opt-in to the domain.

`COLLATE "C"` makes comparison bytewise, and bytewise order is time order: for
ids of one prefix, one size and one letter case the time comes first in the
body, and the Base32 alphabet is in ASCII order (digits before letters). A
locale-aware collation may order by something else - fold case, or ignore the
delimiter and other punctuation - and the order of ids by time would be lost
in an index. A plain `text` column uses the database's default collation, so
give an index or an `ORDER BY` on such a column `COLLATE "C"`, or use the
domain.

## Defaults

| Argument | Default |
|---|---|
| `size` | `xl` (`xs`, `s`, `m`, `l` and `xl`, or `xsmall` to `xlarge`) |
| `compact` | `false`, standard time; `NULL` is the size's default, which is compact only for a monotonic `xs` |
| `letter_case` | `lower` (`upper` changes the body only) |
| `delimiter` | `_` |
| `prefix` | none; `NULL` and the empty string are both no prefix |
| `time_ms` | the current time, from `clock_timestamp()` |

A `NULL` prefix, size, letter case or delimiter takes its default.

### Refusals

A generation request the format refuses raises SQLSTATE `22023`
(`invalid_parameter_value`) with the message `uxid: <name>: <detail>`. The
names are the six the conformance corpus uses - `compact_time_out_of_range`,
`rand_width_mismatch`, `rand_size_too_large`, `from_with_monotonic`,
`rand_with_from` and `rand_with_monotonic` - and `invalid_argument` for an
argument the corpus has no name for: an unknown size or letter case, an empty
delimiter, a negative `rand_size`, a `time_ms` outside 0 to 2^48 - 1, or a
monotonic `xs` with `compact` false. A refused call changes nothing.

Decoding a malformed id raises SQLSTATE `22P02`
(`invalid_text_representation`) with the message `uxid: <reason>`, where the
reason is `empty`, `invalid_length` or `invalid_character`, checked in that
order. `uxid_decode_error` answers those reasons, or `invalid_argument` for an
empty delimiter, or `NULL` for a well-formed body (and for a `NULL` id), and
never raises. `uxid_decode` and `uxid_decode_at` raise `22023` with
`invalid_argument` for an empty delimiter and, for a compact time, for a
`clock_ms` that is `NULL` or outside 0 to 2^48 - 1.

## The monotonic rule

`uxid_monotonic` keeps its state in a session setting per prefix and random
width, named `uxid.mono_<hex of the prefix's UTF-8 bytes>_<width>`. So the
order holds **within one session only**: never across sessions, connections or
the backends behind a connection pooler.

- A rollback undoes the state. A transaction that aborts, or a savepoint
  rolled back, restores what it found, so ids returned inside it may repeat in
  the same session. `RESET ALL` and `DISCARD ALL` clear the state.
- A refused call raises and writes nothing.
- An `xs` id is always compact: `compact` `NULL` is compact at `xs`, and an
  explicit `false` is refused with `invalid_argument`.
- `uxid_monotonic` is volatile and parallel unsafe.

If you need an order across sessions, sort by the id (the time leads) and
accept that two ids in one millisecond from different sessions carry no order.

## Compatibility

- **PostgreSQL 14 and later.** CI runs `make installcheck` on 14, 15, 16, 17
  and 18, the plain migration on 14 and 18, and the pg_tle install on 17. The
  functions are bound when they are created (`BEGIN ATOMIC` bodies, which
  PostgreSQL 14 introduced), so the extension works with its schema off your
  `search_path`.
- **No C code, no extension dependency.** The extension is SQL and PL/pgSQL
  over core PostgreSQL: no compiled module, no `requires` in the control file,
  and no pgcrypto. SHA-256 is core `sha256(bytea)`.
- **The random source.** Random bytes come from
  `uuid_send(gen_random_uuid())`, PostgreSQL's core cryptographically secure
  generator (core since version 13). Only the 14 fully random bytes of the UUID
  are used, never its version or variant bits. `random()` and other seeded
  generators are never used. `uxid_encode` takes fixed bytes for test vectors;
  an id built from them is exactly as guessable as those bytes.
- **The wire format.** The extension follows uxid-ex at the tag its vendored
  corpus names. Where the corpus does not fix an answer, this README states the
  choice: `uxid_is_valid` and `uxid_is_deterministic` accept only a body whose
  length the format defines, which is stricter than the reference.
- **Compact times.** A compact body carries the low 40 bits of its time and
  the decoder supplies the rest from its clock. The corpus's compact cases hold
  for a clock from 1699913600000 ms inclusive to 2164577117183 ms exclusive.

## Documentation

- Look up
  - `\df+ uxid_*` and `\dD+ uxid` in `psql`: the comment on every function and
    on the domain is the API reference.
  - [The changelog](CHANGELOG.md): what changed in each version.
  - [The conformance corpus](conformance): the cases every implementation of
    the wire format passes, vendored here from uxid-ex.
- Understand
  - [The wire format](docs/wire-format.md): where the normative layout of an
    id lives, and which version of it this extension follows.
  - [The reference spec, at v2.10.0][guide_wire_format_url]: alphabet, bit
    packing, sizes, prefix grammar, deterministic and monotonic bodies, and
    decoding.
  - [Why a UXID has a prefix, a time and randomness][guide_why_url]: what each
    part of an id is for, and what you trade when you tune it.
  - [Why monotonic mode exists and what it costs][guide_monotonic_url]:
    same-millisecond uniqueness and ordering, and the security tradeoff.

## Development

After checking out the repository, run `mise install` for the tools
`mise.toml` pins. `mise run gate:loop` builds a PostgreSQL 18 container and
runs `make installcheck` in it, and `mise run gate` runs the full quality
gate: that, the sqlfluff lint and the conformance corpus check. Docker is the
only PostgreSQL you need on the host.

A release is published by CI, never from a checkout: pushing a tag `vX.Y.Z`
that names the version in `uxid.control` runs `.github/workflows/release.yml`,
which creates the GitHub release.

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/riddler/uxid-pg.

## License

The extension is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).

<!-- LINKS -->
[guide_wire_format_url]: https://github.com/riddler/uxid-ex/blob/v2.10.0/guides/wire-format.md
[guide_why_url]: https://github.com/riddler/uxid-ex/blob/v2.10.0/guides/why-prefix-time-randomness.md
[guide_monotonic_url]: https://github.com/riddler/uxid-ex/blob/v2.10.0/guides/monotonic.md

<!-- BADGES -->
[badge_license_url]: https://img.shields.io/badge/license-MIT-brightgreen.svg
[badge_ci_url]: https://github.com/riddler/uxid-pg/actions/workflows/ci.yml/badge.svg
