-- The internal helpers under the encoder: the random bytes taken from a
-- UUID, the random-bytes draw, the size table and the base32 fields.
\set SHOW_CONTEXT never

-- The fully random bytes of a UUID are bytes 0 to 5, 7 and 9 to 15; the
-- fixed UUID below holds its own byte offsets, so the answer names them.
-- Byte 6 (the version nibble) and byte 8 (the variant bits) never come
-- back.
-- sabotage: substring(uuid_bytes FROM 7 FOR 1) in place of FROM 8 FOR 1
-- -> " 00010203040507090a0b0c0d0e0f | 14" under taken and bytes
SELECT
    encode(
        uxid__uuid_bytes('\x000102030405060708090a0b0c0d0e0f'::bytea), 'hex'
    ) AS taken,
    octet_length(
        uxid__uuid_bytes('\x000102030405060708090a0b0c0d0e0f'::bytea)
    ) AS bytes;

-- A version 4 UUID from gen_random_uuid() with every random bit set
-- would read ff..ff except for its version and variant bytes; those
-- bytes are exactly the ones left out.
SELECT
    encode(
        uxid__uuid_bytes(
            '\xffffffffffff4fffbfffffffffffffff'::bytea
        ),
        'hex'
    ) AS taken;

-- A draw of n bytes is n bytes long: one UUID covers up to 14 bytes, two
-- cover up to 28.
-- sabotage: WHEN n > 28 in place of WHEN n > 14 in uxid__random_bytes
-- -> " 15 |    15" under n and bytes (14 comes back)
SELECT
    n.n,
    octet_length(uxid__random_bytes(n.n)) AS bytes
FROM (VALUES (0), (1), (10), (14), (15), (25), (28)) AS n (n)
ORDER BY n.n;

-- Two draws of 10 bytes differ (a repeat has probability 2^-80).
SELECT count(DISTINCT uxid__random_bytes(10)) AS distinct_draws
FROM generate_series(1, 2);

-- A draw outside 0 to 28 bytes is refused.
SELECT uxid__random_bytes(29);
SELECT uxid__random_bytes(-1);

-- Each size's short and long spelling, NULL (the default, xl) and an
-- unknown size (NULL).
SELECT
    s.size,
    uxid__size(s.size) AS short_size
FROM
    (
        VALUES
        ('xs'), ('xsmall'), ('s'), ('small'), ('m'), ('medium'),
        ('l'), ('large'), ('xl'), ('xlarge'), (NULL), ('XL'), ('huge')
    ) AS s (size);

-- The random field's width for each size and time form, as the wire
-- format's size table gives it, and an explicit width over it.
-- sabotage: THEN 2 ELSE 3 in place of THEN 3 ELSE 2 for s in
-- uxid__rand_width -> " s    | f       |     2 |              4"
SELECT
    s.size,
    c.compact,
    uxid__rand_width(s.size, c.compact, NULL, FALSE) AS width,
    uxid__rand_width(s.size, c.compact, 4, FALSE) AS explicit_width
FROM (VALUES ('xs'), ('s'), ('m'), ('l'), ('xl')) AS s (size)
CROSS JOIN (VALUES (FALSE), (TRUE)) AS c (compact)
ORDER BY c.compact, uxid__rand_width(s.size, c.compact, NULL, FALSE);

-- With no compact given (NULL), a monotonic xs is compact and every other
-- request is standard.
SELECT
    uxid__compact('xs', NULL, TRUE) AS monotonic_xs,
    uxid__compact('s', NULL, TRUE) AS monotonic_s,
    uxid__compact('xs', NULL, FALSE) AS plain_xs,
    uxid__compact('xs', FALSE, TRUE) AS explicit_standard_xs;

-- The time field: 1700000000000 ms is 01hf7yat00 standard and hf7yat00
-- compact (the wire format's example); 0 and 2^48 - 1 are the ends of
-- standard time; compact keeps the low 40 bits only.
-- sabotage: CASE WHEN compact THEN 9 in place of THEN 8 in
-- uxid__base32_time -> " 1700000000000 | 01hf7yat00 | hf7yat00" under
-- the first row
SELECT
    t.ms,
    uxid__base32_time(t.ms, FALSE) AS standard,
    uxid__base32_time(t.ms, TRUE) AS compact
FROM
    (
        VALUES
        (1700000000000::bigint),
        (0::bigint),
        (281474976710655::bigint),
        (1099511627775::bigint),
        (1099511627776::bigint)
    ) AS t (ms);

-- The random field: ceil(8 x bytes / 5) characters, most significant bit
-- first, and a short last group written as its raw value (0xffff is zzz1,
-- never zzzg).
-- sabotage: 5 in place of least(5, 8 * field.bytes - 5 * g.i) in
-- uxid__base32_bytes -> " ffff                 | zzz1             |     4"
SELECT
    encode(b.rand, 'hex') AS hex,
    uxid__base32_bytes(b.rand) AS field,
    length(uxid__base32_bytes(b.rand)) AS chars
FROM
    (
        VALUES
        (''::bytea),
        ('\x01'::bytea),
        ('\xff'::bytea),
        ('\xffff'::bytea),
        ('\x0123'::bytea),
        ('\xffffff'::bytea),
        ('\x0123456789'::bytea),
        ('\xffffffffffffff'::bytea),
        ('\x0123456789abcdef0123'::bytea)
    ) AS b (rand)
ORDER BY octet_length(b.rand), b.rand;
