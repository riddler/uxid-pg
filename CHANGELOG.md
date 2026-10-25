# Changelog

## 1.0.0 - 2026-10-25

The first release of `uxid` for PostgreSQL: prefixed, K-sortable identifiers
a person can read, wire-compatible with the Elixir `uxid` package. It covers
time-based generation (`uxid_generate`, with the pure encoder `uxid_encode`
and the request check `uxid_check_request`), deterministic ids (`uxid_from`),
decoding (`uxid_decode`, the pure decoder `uxid_decode_at` and
`uxid_decode_error`), the validity checks (`uxid_is_valid` and
`uxid_is_deterministic`), the `uxid` domain over `text COLLATE "C"`, a
monotonic generator whose state lives in the session (`uxid_monotonic`, with
its pure step `uxid_monotonic_step`) and `uxid_version()`. It is an extension
written in SQL and PL/pgSQL, with no C code, no compiled module and no
dependency beyond core PostgreSQL; its random bytes come from the core
`gen_random_uuid()` generator, through `uuid_send(gen_random_uuid())`, and
never from `random()`. It supports PostgreSQL 14 and later; CI runs its tests
on PostgreSQL 14, 15, 16, 17 and 18. It installs three ways: `CREATE EXTENSION
uxid` from the release tarball, the extension script run once as a plain
migration, and pg_tle's `pgtle.install_extension`. A refused generation
request raises SQLSTATE 22023 and a malformed id SQLSTATE 22P02, each message
naming the refusal: the conformance corpus's names, and this extension's own
`invalid_argument` for an argument the corpus has no name for. It passes every
case of the uxid conformance corpus at uxid-ex's tag `v2.10.0`, vendored byte
for byte and run with no skip list.

### Added

- The extension `uxid` installs with `CREATE EXTENSION uxid`: relocatable, with `superuser = false` and no required extension. Its script carries no psql guard line, so the same file also runs once as a plain migration.
- `uxid_version()` returns the version of the extension script installed, `1.0.0`; it is immutable and parallel safe.
- `uxid_from(prefix, key, size, letter_case, delimiter)` builds the deterministic id of a key: the same prefix, key and size always give the same id, such as `usr_zcvt7epac0t1ebcsjfyf7cwz25` for `usr` and `alice@example.com` at the default size `xl`. The id is the marker `z` and the leading characters of a SHA-256 of the prefix and the key, hashed as UTF-8 bytes whatever the database encoding, so the same text gives the same id in every database. A deterministic id has no compact form, time or random field. A NULL key gives NULL, and NULL or the empty string is no prefix. It refuses a request as `uxid_check_request` does, an unknown size or letter case or an empty delimiter included, even for a NULL key. It is immutable and parallel safe.
- `uxid_monotonic(prefix, size, compact, rand_size, letter_case, delimiter, time_ms)` generates time-based ids that sort strictly after the last id the same session generated for that prefix and random width: a fresh random field when the time is later than the last id's, otherwise the last id's time and its random field plus a step drawn uniformly from 1 to 2^(4 x width), and the next millisecond with a fresh field when the step would overflow. It is volatile and parallel unsafe.
- The generator's state is a session setting per prefix and random width, `uxid.mono_<hex of the prefix's UTF-8 bytes>_<width>`, holding `<time_ms>:<value>`. The order holds within one session only, never across sessions, connections or the backends behind a pooler. A transaction that aborts, or a savepoint rolled back, restores the state it found, so ids returned inside it may repeat in the same session; `RESET ALL` and `DISCARD ALL` clear it. A refused call leaves the state as it was.
- A monotonic xs always uses compact time: `compact` NULL is the size's default, and an explicit `compact` false at xs is refused with SQLSTATE 22023 and `uxid: invalid_argument`, with or without a `rand_size`; `uxid_check_request` refuses the same monotonic request.
- `uxid_monotonic_step(last_time_ms, last_rand, now_ms, rand_width, seed, step, overflow_seed)` is the generator's pure step, returning the next `time_ms`, `rand` and which draw it took (`seed`, `step` or `step_overflow`); it is immutable and parallel safe, and refuses a missing draw the rule needs, or a value outside its range, with `invalid_argument`.
- `uxid_decode(id, clock_ms, delimiter)` decodes an id to one row of `prefix`, `size`, `compact`, `deterministic` and `time_ms` (NULL for a deterministic id). The body is everything after the last delimiter; the size and time form come from its length; a compact time takes its high bits from the clock, the transaction time (`now()`) when `clock_ms` is NULL, and steps back one 2^40 ms window when it would be more than a day ahead of it, with no clamp at zero. It is stable and parallel safe.
- `uxid_decode_at(id, clock_ms, delimiter)` is the same decoder against the clock it is given; it is immutable and parallel safe.
- A malformed id is refused with SQLSTATE 22P02 (`invalid_text_representation`) and the message `uxid: empty`, `uxid: invalid_length` or `uxid: invalid_character`, checked in that order, with the body's length counted in UTF-8 bytes whatever the database encoding. An empty delimiter, or a compact time with no clock or one outside 0 to 2^48 - 1, is refused with SQLSTATE 22023 and `uxid: invalid_argument`.
- `uxid_decode_error(id, delimiter)` returns the reason an id would be refused, or NULL for one that decodes, and never raises.
- `uxid_is_valid(id, delimiter, required_prefix)` and `uxid_is_deterministic(id, delimiter)` check an id without reading a clock; both ask for a body that fully decodes, which is stricter than the Elixir reference, and answer NULL for a NULL id. They are immutable and parallel safe.
- The domain `uxid` over `text COLLATE "C"` refuses any value `uxid_is_valid` refuses, so lower-case ids of one prefix and size sort by time. Every function still takes and returns `text`, so a `text` column works unchanged and `ALTER TABLE ... ALTER COLUMN id TYPE uxid` is the opt-in.
- `uxid_generate(prefix, size, compact, rand_size, letter_case, delimiter, time_ms)` generates a time-based id: size `xs`, `s`, `m`, `l` or `xl` (or `xsmall`, `small`, `medium`, `large` or `xlarge`; default `xl`), standard or compact time, lower or upper case, any non-empty delimiter (default `_`), and no prefix for NULL or the empty string. The time is `time_ms`, or `clock_timestamp()` when it is NULL; the random field comes from the fully random bytes of `uuid_send(gen_random_uuid())`. It is volatile and parallel safe.
- `uxid_encode(prefix, size, time_ms, rand, compact, letter_case, delimiter, rand_size)` builds the same id from a fixed time and fixed random bytes, for test vectors; it is immutable and parallel safe.
- `uxid_check_request(prefix, size, compact, rand_size, letter_case, delimiter, time_ms, rand, from_key, monotonic)` refuses a generation request the way generation does and returns nothing for one it accepts. A refusal raises SQLSTATE 22023 (`invalid_parameter_value`) with a message that starts `uxid: ` and the refusal's name: `compact_time_out_of_range`, `rand_width_mismatch`, `rand_size_too_large`, `from_with_monotonic`, `rand_with_from` or `rand_with_monotonic`, or `invalid_argument` for an unknown size or letter case, an empty delimiter, a negative `rand_size`, a time outside 0 to 2^48 - 1, or a monotonic request with no random field.
- The functions work with the extension's schema off the `search_path`, under an empty `search_path` and after `ALTER EXTENSION uxid SET SCHEMA`.
