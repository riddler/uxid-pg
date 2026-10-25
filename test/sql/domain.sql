-- The uxid domain: text with COLLATE "C" whose check is uxid_is_valid.
\set SHOW_CONTEXT never

-- The domain over text, its collation and its check, read from the
-- catalog.
-- sabotage: CREATE DOMAIN uxid AS text CHECK (...) with no COLLATE "C"
-- -> " uxid    | default  | text      | CHECK (uxid_is_valid(VALUE))"
SELECT
    t.typname,
    c.collname,
    format_type(t.typbasetype, t.typtypmod) AS base_type,
    pg_get_constraintdef(k.oid) AS check_constraint
FROM pg_type AS t
INNER JOIN pg_collation AS c ON t.typcollation = c.oid
INNER JOIN pg_constraint AS k ON t.oid = k.contypid
WHERE t.typname = 'uxid';

-- A uxid column takes a well-formed id and NULL, and refuses anything
-- uxid_is_valid refuses.
-- sabotage: WHEN uxid__body_error(...) IS NOT NULL THEN FALSE dropped from
-- uxid_is_valid -> "ERROR:  value for domain uxid violates check
-- constraint "uxid_check"" missing for usr_01hf7yat000
CREATE TABLE uxid_domain_row (id uxid);
INSERT INTO uxid_domain_row VALUES ('usr_01hf7yat0004h1'), (NULL);
INSERT INTO uxid_domain_row VALUES ('usr_01hf7yat000');
INSERT INTO uxid_domain_row VALUES ('usr_01hu7yat0004h1');
INSERT INTO uxid_domain_row VALUES ('');
SELECT 'usr_01hf7yat0004h1'::uxid AS cast_ok;
SELECT 'usr_'::uxid AS cast_refused;
SELECT id
FROM uxid_domain_row
ORDER BY id NULLS LAST;

-- ORDER BY on a uxid column follows time for lower-case ids of one
-- prefix and size: COLLATE "C" compares bytes, and the alphabet is in
-- ASCII order. Each id's random field runs against its time (the
-- earliest time has the highest random field), and the rows go in out
-- of order, so only the time can order them.
-- All these ids are lower case, so a linguistic collation sorts them
-- the same way; the mixed-case test below is the one whose order
-- depends on COLLATE "C".
CREATE TABLE uxid_ordered (time_ms bigint, id uxid);
INSERT INTO uxid_ordered
SELECT
    t.time_ms,
    uxid_encode('doc', 'm', t.time_ms, t.rand) AS id
FROM
    (
        VALUES
        (1700000000001::bigint, '\x0000000000'::bytea),
        (0, '\xffffffffff'),
        (281474976710655, '\x0000000000'),
        (1700000000000, '\xfffffffffe'),
        (35184372088832, '\x0102030405'),
        (1700000086400, '\x8000000000'),
        (31, '\x0000000001'),
        (32, '\x0000000000')
    ) AS t (time_ms, rand);
SELECT
    id,
    time_ms,
    lag(time_ms) OVER (ORDER BY id) < time_ms AS later_than_previous
FROM uxid_ordered
ORDER BY id;
SELECT
    array_agg(time_ms ORDER BY id)
    = array_agg(time_ms ORDER BY time_ms) AS id_order_is_time_order
FROM uxid_ordered;

-- Mixed case: COLLATE "C" compares bytes, and A to Z come before a to z,
-- so the upper-case ids of one prefix and size sort before the
-- lower-case ones, each group in time order. A linguistic collation
-- folds case first and interleaves the two groups by time: the text
-- column below, collated by ICU's root locale (a collation this test
-- creates, as und-x-icu is), shows that order. The two orders are
-- pinned row by row, and the uxid column's order is checked against the
-- ids' bytes, so the result is the same whatever the server's default
-- collation. On a server whose default is linguistic, such as the local
-- gate's en_US.utf8, dropping
-- COLLATE "C" from the domain makes the uxid column sort like the ICU
-- column; on a server whose default is C the order cannot show it,
-- and the collation row at the top of this file guards it there.
-- sabotage: CREATE DOMAIN uxid AS text CHECK (...) with no COLLATE "C",
-- run on the en_US.utf8 gate server -> " f" under
-- uxid_order_is_bytewise, and the uxid rows in the ICU order
CREATE TABLE uxid_mixed_case (time_ms bigint, id uxid);
INSERT INTO uxid_mixed_case
SELECT
    t.time_ms,
    uxid_encode(
        'doc', 'm', t.time_ms, '\x0000000000'::bytea,
        letter_case => t.letter_case
    ) AS id
FROM
    (
        VALUES
        (1700000000002::bigint, 'lower'),
        (1700000000001, 'upper'),
        (1700000000003, 'upper'),
        (1700000000000, 'lower')
    ) AS t (time_ms, letter_case);
CREATE COLLATION uxid_icu_root (PROVIDER = ICU, LOCALE = 'und');
CREATE TABLE uxid_mixed_case_icu (
    time_ms bigint,
    id text COLLATE uxid_icu_root
);
INSERT INTO uxid_mixed_case_icu SELECT
    time_ms,
    id
FROM uxid_mixed_case;
SELECT
    id,
    time_ms
FROM uxid_mixed_case
ORDER BY id;
SELECT
    id,
    time_ms
FROM uxid_mixed_case_icu
ORDER BY id;
SELECT
    (SELECT array_agg(m.id ORDER BY m.id) FROM uxid_mixed_case AS m)::text
    = (
        SELECT array_agg(m.id ORDER BY convert_to(m.id, 'UTF8'))
        FROM uxid_mixed_case AS m
    )::text AS uxid_order_is_bytewise,
    (
        SELECT array_agg(i.time_ms ORDER BY i.id)
        FROM uxid_mixed_case_icu AS i
    )
    = (
        SELECT array_agg(i.time_ms ORDER BY i.time_ms)
        FROM uxid_mixed_case_icu AS i
    ) AS icu_order_is_time_order;

-- Every function takes and returns plain text, so a text column holding
-- the same values works unchanged with each of them, and a uxid value
-- passes to a function that takes text.
CREATE TABLE uxid_text_row (id text);
INSERT INTO uxid_text_row SELECT id FROM uxid_ordered;
SELECT
    bool_and(uxid_is_valid(t.id, '_', 'doc')) AS text_valid,
    bool_and(uxid_is_valid(o.id, '_', 'doc')) AS domain_valid,
    bool_and(uxid_decode_error(t.id) IS NULL) AS text_no_error,
    bool_and(
        (SELECT d.time_ms FROM uxid_decode(t.id) AS d) = o.time_ms
    ) AS text_decodes,
    bool_and(
        (SELECT d.time_ms FROM uxid_decode(o.id) AS d) = o.time_ms
    ) AS domain_decodes,
    bool_and(NOT uxid_is_deterministic(o.id)) AS not_deterministic
FROM uxid_text_row AS t
INNER JOIN uxid_ordered AS o ON t.id = o.id;
SELECT pg_typeof(uxid_from('doc', 'alice@example.com', 's')) AS from_type;
ALTER TABLE uxid_text_row ALTER COLUMN id TYPE uxid;
SELECT count(*) AS converted FROM uxid_text_row;

-- The check holds under the empty search_path a dump restore sets: the
-- domain's check calls uxid_is_valid by its bound reference, and
-- uxid_is_valid's callees are bound when it is created.
-- sabotage: uxid_is_valid written with a string body (AS $v$ ... $v$)
-- -> "ERROR:  function uxid__body(text, text) does not exist" in place of
-- the accepted INSERT under the empty search_path
SET search_path = '';
INSERT INTO public.uxid_domain_row VALUES ('usr_01hf7yat0004h2');
INSERT INTO public.uxid_domain_row VALUES ('usr_01hf7yat0004');
CREATE TABLE public.uxid_restored (id public.uxid);
INSERT INTO public.uxid_restored VALUES ('doc_zt9vnyfd85bff0');
INSERT INTO public.uxid_restored VALUES ('doc_zt9vnyfd85bf');
RESET search_path;

-- After ALTER EXTENSION uxid SET SCHEMA the domain moves with the
-- functions, and the check still holds with only pg_catalog on the
-- search_path.
CREATE SCHEMA uxid_moved;
ALTER EXTENSION uxid SET SCHEMA uxid_moved;
SET search_path = pg_catalog;
SELECT n.nspname
FROM pg_catalog.pg_type AS t
INNER JOIN pg_catalog.pg_namespace AS n ON t.typnamespace = n.oid
WHERE t.typname = 'uxid';
INSERT INTO public.uxid_domain_row VALUES ('usr_01hf7yat0004h3');
INSERT INTO public.uxid_domain_row VALUES ('usr_01hf7yat0004');
SELECT 'usr_01hf7yat0004h4'::uxid_moved.uxid AS moved_cast;
SET search_path = '';
INSERT INTO public.uxid_restored VALUES ('doc_01hf7yat0004h1');
INSERT INTO public.uxid_restored VALUES ('doc_01hf7yat0004');
RESET search_path;
ALTER EXTENSION uxid SET SCHEMA public;
DROP SCHEMA uxid_moved;
SELECT count(*) AS rows_kept FROM uxid_domain_row;

DROP TABLE uxid_domain_row;
DROP TABLE uxid_ordered;
DROP TABLE uxid_mixed_case;
DROP TABLE uxid_mixed_case_icu;
DROP COLLATION uxid_icu_root;
DROP TABLE uxid_text_row;
DROP TABLE uxid_restored;
