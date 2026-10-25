-- uxid_decode_at, the pure decoder, and uxid_decode, which takes its
-- clock from the transaction time: the prefix, size, time form,
-- deterministic flag and time an id carries.
\set SHOW_CONTEXT never

-- Every decode case of the conformance corpus at v2.10.0 (18 cases), by
-- case id, with their expected answers. The compact cases hold for a
-- decoder clock from 1699913600000 ms inclusive to 2164577117183 ms
-- exclusive (the corpus README, "Compact times and the decoder's
-- clock"): 1700000000000 - 86400000 = 1699913600000 is the earliest
-- clock no more than a day behind the cases at 1700000000000, and
-- 2^40 + 1065151889407 - 86400000 = 1099511627776 + 1065151889407
-- - 86400000 = 2164577117183 is the first clock at which the guard's last
-- valid millisecond is no longer more than a day ahead, so it is no
-- longer stepped back. The cases run at both ends of that window.
CREATE TEMPORARY TABLE decode_case (
    case_id text,
    case_input text,
    expected_prefix text,
    expected_size text,
    expected_compact boolean,
    expected_deterministic boolean,
    expected_time_ms bigint
);
INSERT INTO decode_case VALUES
(
    'decode/xl-standard', 'usr_01hf7yat0004hmasw9nf6yy093',
    'usr', 'xl', FALSE, FALSE, 1700000000000
),
(
    'decode/xl-compact', 'usr_hf7yat0004hmasw9nf6yy093',
    'usr', 'xl', TRUE, FALSE, 1700000000000
),
(
    'decode/l-standard', 'usr_01hf7yat0004hmasw9nf61',
    'usr', 'l', FALSE, FALSE, 1700000000000
),
(
    'decode/l-compact', 'usr_hf7yat0004hmasw9nf6yf',
    'usr', 'l', TRUE, FALSE, 1700000000000
),
(
    'decode/m-standard', 'usr_01hf7yat0004hmasw9',
    'usr', 'm', FALSE, FALSE, 1700000000000
),
(
    'decode/m-compact-reads-as-standard', 'usr_hf7yat0004hmasw9n3',
    'usr', 'm', FALSE, FALSE, 51950139736068
),
(
    'decode/s-standard', 'usr_01hf7yat0004h1',
    'usr', 's', FALSE, FALSE, 1700000000000
),
(
    'decode/s-compact', 'usr_hf7yat0004hm5',
    'usr', 's', TRUE, FALSE, 1700000000000
),
(
    'decode/xs-standard', 'usr_01hf7yat00',
    'usr', 'xs', FALSE, FALSE, 1700000000000
),
(
    'decode/xs-compact-reads-as-standard', 'usr_hf7yat0001',
    'usr', 'xs', FALSE, FALSE, 51950139736065
),
(
    'decode/xl-standard-upper', 'usr_01HF7YAT0004HMASW9NF6YY093',
    'usr', 'xl', FALSE, FALSE, 1700000000000
),
(
    'decode/xl-standard-no-prefix', '01hf7yat0004hmasw9nf6yy093',
    NULL, 'xl', FALSE, FALSE, 1700000000000
),
(
    'decode/s-standard-prefix-with-delimiter', 'a_b_01hf7yat000001',
    'a_b', 's', FALSE, FALSE, 1700000000000
),
(
    'decode/s-compact-guard-last-valid', 'usr_yzzzzzzz04hm5',
    'usr', 's', TRUE, FALSE, 1065151889407
),
(
    'decode/deterministic-usr-xl', 'usr_zcvt7epac0t1ebcsjfyf7cwz25',
    'usr', 'xl', FALSE, TRUE, NULL
),
(
    'decode/deterministic-cus-s', 'cus_zt9vnyfd85bff0',
    'cus', 's', FALSE, TRUE, NULL
),
(
    'decode/deterministic-no-prefix-m', 'zqz4cwzgyw8ks97869',
    NULL, 'm', FALSE, TRUE, NULL
),
(
    'decode/deterministic-upper-marker', 'usr_ZCVT7EPAC0T1EBCSJFYF7CWZ25',
    'usr', 'xl', FALSE, TRUE, NULL
);

-- At the window's first clock, 1699913600000 ms.
-- sabotage: & 7 dropped, the standard time read as all 50 bits
-- (uxid__base32_value(left(d.body, 10)) alone)
-- -> " decode/m-compact-reads-as-standard | ... | 614900093157380 | t"
-- sabotage: the marker dropped from WHEN d.body IS NULL OR d.marker THEN
-- NULL (the marker body read as a standard time)
-- -> " decode/deterministic-cus-s | ... | 275216872224005 | t"
-- sabotage: ascii(b.body) IN (122) in place of IN (90, 122) in
-- uxid_decode_at -> " decode/deterministic-upper-marker | ... | f |
-- 260440624671104 | t"
-- sabotage: the upper-case translate dropped from uxid__base32_value
-- -> " decode/xl-standard-upper | ... | 281474976709632 | t"
SELECT
    c.case_id,
    d.prefix,
    d.size,
    d.compact,
    d.deterministic,
    d.time_ms,
    (d.prefix IS DISTINCT FROM c.expected_prefix)
    OR (d.size IS DISTINCT FROM c.expected_size)
    OR (d.compact IS DISTINCT FROM c.expected_compact)
    OR (d.deterministic IS DISTINCT FROM c.expected_deterministic)
    OR (d.time_ms IS DISTINCT FROM c.expected_time_ms) AS differs
FROM decode_case AS c
CROSS JOIN LATERAL uxid_decode_at(c.case_input, 1699913600000) AS d
ORDER BY convert_to(c.case_id, 'UTF8');

-- At the window's last clock, 2164577117182 ms.
-- sabotage: - 1099511627775 in place of - 1099511627776 in
-- uxid__compact_time -> " decode/s-compact-guard-last-valid | t"
-- sabotage: > 86400001 in place of > 86400000 in uxid__compact_time
-- -> " decode/s-compact-guard-last-valid | t"
SELECT
    c.case_id,
    (d.prefix IS DISTINCT FROM c.expected_prefix)
    OR (d.size IS DISTINCT FROM c.expected_size)
    OR (d.compact IS DISTINCT FROM c.expected_compact)
    OR (d.deterministic IS DISTINCT FROM c.expected_deterministic)
    OR (d.time_ms IS DISTINCT FROM c.expected_time_ms) AS differs
FROM decode_case AS c
CROSS JOIN LATERAL uxid_decode_at(c.case_input, 2164577117182) AS d
ORDER BY convert_to(c.case_id, 'UTF8');

-- Just outside the window the corpus's compact cases no longer hold:
-- one millisecond before its start, the cases at 1700000000000 are more
-- than a day ahead and step back a window (1700000000000 - 2^40 =
-- 600488372224); at its end, the guard's last valid millisecond is no
-- longer more than a day ahead and is not stepped back (2^40 +
-- 1065151889407 = 2164663517183).
-- sabotage: >= 86400000 in place of > 86400000 in uxid__compact_time
-- -> " xl-compact at the window start | 1700000000000" read as
-- 600488372224
SELECT
    'xl-compact at the window start' AS clock,
    d.time_ms
FROM uxid_decode_at('usr_hf7yat0004hmasw9nf6yy093', 1699913600000) AS d
UNION ALL
SELECT
    'xl-compact one ms before the window' AS clock,
    d.time_ms
FROM uxid_decode_at('usr_hf7yat0004hmasw9nf6yy093', 1699913599999) AS d
UNION ALL
SELECT
    'guard-last-valid at the window''s last ms' AS clock,
    d.time_ms
FROM uxid_decode_at('usr_yzzzzzzz04hm5', 2164577117182) AS d
UNION ALL
SELECT
    'guard-last-valid at the window end' AS clock,
    d.time_ms
FROM uxid_decode_at('usr_yzzzzzzz04hm5', 2164577117183) AS d;

-- A clock inside the first 2^40 ms window steps a compact time more than
-- a day ahead of it back one window, to a negative time: there is no
-- clamp at zero. hf7yat00 is the low 40 bits of 1700000000000,
-- 600488372224; against the clock 0 that is 600488372224 - 2^40 =
-- -499023255552. Against the clock 600401972223 (more than a day behind
-- it) the same, and against 600401972224 (a day behind) it is kept.
-- sabotage: greatest(0, ...) round the stepped-back time in
-- uxid__compact_time -> " 0             | -499023255552" read as 0
SELECT
    c.clock_ms,
    d.time_ms
FROM
    (VALUES (0::bigint), (600401972223), (600401972224)) AS c (clock_ms)
CROSS JOIN
    LATERAL uxid_decode_at('usr_hf7yat0004hmasw9nf6yy093', c.clock_ms) AS d
ORDER BY c.clock_ms;

-- The clock's bits above bit 40 are the time's: a compact time decoded
-- against a clock in a later window carries that window's high bits.
-- 3 x 2^40 + 600488372224 = 3899023255552.
SELECT d.time_ms
FROM uxid_decode_at('usr_hf7yat0004hmasw9nf6yy093', 3898936855552) AS d;

-- uxid_decode takes its clock from the transaction time, now(), in ms,
-- when clock_ms is NULL, and from clock_ms when it is given.
SELECT
    d.time_ms = (
        SELECT n.time_ms
        FROM
            uxid_decode_at(
                'usr_hf7yat0004hmasw9nf6yy093',
                floor(extract(EPOCH FROM now()) * 1000)::bigint
            ) AS n
    ) AS same_as_now
FROM uxid_decode('usr_hf7yat0004hmasw9nf6yy093') AS d;
SELECT d.time_ms
FROM uxid_decode('usr_hf7yat0004hmasw9nf6yy093', 0) AS d;

-- The clock is the transaction's start, not the wall clock: inside one
-- transaction, a compact time 86400020 ms after now() (20 ms more than a
-- day ahead of it) steps back a window however long the transaction has
-- run, while 50 ms later a wall clock would be less than a day behind it
-- and keep it. The id is built from the time's low 40 bits; from mid-2038
-- to 2039 such a time starts with the marker and this check cannot be
-- built, as the wire format's compact guard says.
-- sabotage: clock_timestamp() in place of now() in uxid_decode
-- -> " f" under stepped_back
BEGIN;
SELECT pg_sleep(0.05);
SELECT d.time_ms = c.ahead_ms - 1099511627776 AS stepped_back
FROM
    (
        SELECT
            floor(extract(EPOCH FROM now()) * 1000)::bigint
            + 86400020 AS ahead_ms
    ) AS c
CROSS JOIN
    LATERAL uxid_decode(
        'usr_' || uxid__base32_time(c.ahead_ms, TRUE) || 'g0000'
    ) AS d;
COMMIT;
SELECT
    d.prefix,
    d.size,
    d.compact,
    d.deterministic,
    d.time_ms
FROM uxid_decode('usr_01hf7yat0004hmasw9nf6yy093') AS d;

-- The body is everything after the last delimiter; the prefix is what is
-- before it (the empty string for an id that starts with the delimiter,
-- as the reference reports it), NULL when there is no delimiter. A
-- longer delimiter splits left to right, its matches not overlapping:
-- under __, a___01hf7yat0004h1 is the prefix a and the body
-- _01hf7yat0004h1, which is 15 bytes long.
SELECT
    c.id_shape,
    d.prefix,
    d.size,
    d.compact,
    d.deterministic,
    d.time_ms,
    d.prefix IS NULL AS null_prefix
FROM
    (
        VALUES
        (1, 'leading delimiter', '_01hf7yat0004h1', '_'),
        (2, 'prefix holding the delimiter', 'a_b_c_01hf7yat0004h1', '_'),
        (3, 'no delimiter', '01hf7yat0004h1', '_'),
        (4, 'delimiter --', 'doc--01hf7yat0004h1', '--'),
        (
            5, 'delimiter -- with _ in the prefix', 'doc_v1--01hf7yat0004h1',
            '--'
        ),
        (6, 'NULL delimiter is _', 'usr_01hf7yat0004h1', NULL),
        (7, 'NULL id', NULL, '_')
    ) AS c (n, id_shape, id, delimiter)
CROSS JOIN LATERAL uxid_decode_at(c.id, 0, c.delimiter) AS d
ORDER BY c.n;
SELECT uxid_decode_error('a___01hf7yat0004h1', '__') AS overlapping_delimiter;

-- A standard time is the low 48 bits of its first 10 characters: the
-- first character's low 3 bits, as the reference reads it, so a first
-- character 8 (0b01000) reads as 0 and this is 1700000000000.
SELECT d.time_ms
FROM uxid_decode_at('usr_81hf7yat0004h1', 0) AS d;

-- A body that starts with the marker is deterministic at every length of
-- the table; at a compact length the compact flag is the length table's,
-- as the reference reports it, and no clock is needed.
SELECT
    d.prefix,
    d.size,
    d.compact,
    d.deterministic,
    d.time_ms
FROM uxid_decode_at('usr_zt9vnyfd85bff', NULL) AS d;

-- A standard body needs no clock; a compact time body does, from 0 to
-- 2^48 - 1, and is refused with invalid_argument (22023) without one.
-- sabotage: the clock refusal statement dropped from uxid_decode_at
-- -> "ERROR:  uxid: invalid_argument: a compact time needs a clock_ms ...
-- got NULL" (a row with a NULL time instead)
SELECT d.time_ms
FROM uxid_decode_at('usr_01hf7yat0004h1', NULL) AS d;
SELECT d.time_ms
FROM uxid_decode_at('usr_hf7yat0004hm5', NULL) AS d;
SELECT d.time_ms
FROM uxid_decode_at('usr_hf7yat0004hm5', -1) AS d;
SELECT d.time_ms
FROM uxid_decode_at('usr_hf7yat0004hm5', 281474976710656) AS d;
SELECT d.time_ms
FROM uxid_decode_at('usr_hf7yat0004hm5', 281474976710655) AS d;

-- An empty delimiter is refused with invalid_argument (22023), before the
-- id is read.
\set VERBOSITY sqlstate
SELECT d.prefix FROM uxid_decode_at('', 0, '') AS d;
\set VERBOSITY default
SELECT d.prefix FROM uxid_decode_at('', 0, '') AS d;
