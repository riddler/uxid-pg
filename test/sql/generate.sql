-- uxid_generate: random bytes from gen_random_uuid(), and the time from
-- time_ms or, when it is NULL, from clock_timestamp().
\set SHOW_CONTEXT never

-- The shape of each size in both time forms and both cases: the prefix,
-- the delimiter and a body of the wire format's length in the alphabet of
-- the case asked for. The time part is the given time's.
-- sabotage: THEN 2 ELSE 3 in place of THEN 3 ELSE 2 for s in
-- uxid__rand_width -> " s    | f       | lower       |        18 | t     |
-- t"
WITH
requests AS (
    SELECT
        s.size,
        c.compact,
        l.letter_case
    FROM (VALUES ('xs'), ('s'), ('m'), ('l'), ('xl')) AS s (size)
    CROSS JOIN (VALUES (FALSE), (TRUE)) AS c (compact)
    CROSS JOIN (VALUES ('lower'), ('upper')) AS l (letter_case)
),

generated AS (
    SELECT
        r.size,
        r.compact,
        r.letter_case,
        uxid_generate(
            'usr', r.size, r.compact, NULL, r.letter_case, '_', 1700000000000
        ) AS id
    FROM requests AS r
)

SELECT
    g.size,
    g.compact,
    g.letter_case,
    length(g.id) AS id_length,
    g.id ~ CASE
        WHEN g.letter_case = 'upper' THEN '^usr_[0-9A-HJKMNP-TV-Z]+$'
        ELSE '^usr_[0-9a-hjkmnp-tv-z]+$'
    END AS shape,
    lower(left(g.id, CASE WHEN g.compact THEN 12 ELSE 14 END))
    = CASE WHEN g.compact THEN 'usr_hf7yat00' ELSE 'usr_01hf7yat00' END
        AS time_part
FROM generated AS g
ORDER BY g.compact, length(g.id), g.letter_case;

-- The defaults: size xl, standard time, lower case, no prefix (NULL and
-- the empty string both give the bare body).
SELECT
    length(uxid_generate()) AS default_length,
    uxid_generate() ~ '^[0-7][0-9a-hjkmnp-tv-z]{25}$' AS default_shape,
    uxid_generate('') ~ '^[0-7][0-9a-hjkmnp-tv-z]{25}$' AS empty_prefix,
    uxid_generate('doc', delimiter => '-') ~ '^doc-[0-9a-hjkmnp-tv-z]{26}$'
        AS custom_delimiter,
    length(uxid_generate('usr', 'xs', rand_size => 4)) AS xs_four_bytes;

-- Two ids at one time differ in their random field.
-- sabotage: a zero-filled field (substring of ten zero bytes) in place of
-- uxid__random_bytes(...) in uxid_generate -> "            2" under
-- distinct_ids
SELECT count(DISTINCT uxid_generate(time_ms => 1700000000000)) AS distinct_ids
FROM generate_series(1, 2);

-- With no time_ms the time is the clock's: an xs id (a time and nothing
-- else) falls between the ids encoded at times read just before and just
-- after it.
-- sabotage: coalesce(time_ms, 0) in place of the clock read in
-- uxid_generate -> " t" under within_reads
CREATE TEMPORARY TABLE clock_check (step integer, ms bigint, id text);
INSERT INTO clock_check (step, ms)
VALUES (1, floor(extract(EPOCH FROM clock_timestamp()) * 1000)::bigint);
INSERT INTO clock_check (step, id)
VALUES (2, uxid_generate(NULL, 'xs'));
INSERT INTO clock_check (step, ms)
VALUES (3, floor(extract(EPOCH FROM clock_timestamp()) * 1000)::bigint);
SELECT
    during.id
    BETWEEN uxid_encode(NULL, 'xs', first_read.ms, '')
    AND uxid_encode(NULL, 'xs', last_read.ms, '') AS within_reads
FROM clock_check AS first_read
CROSS JOIN clock_check AS during
CROSS JOIN clock_check AS last_read
WHERE first_read.step = 1 AND during.step = 2 AND last_read.step = 3;

-- A generate request is refused as uxid_check_request refuses it.
-- sabotage: pass NULL in place of req.rand_size to uxid_encode
-- -> " rand_size 11       | 22023 uxid: rand_size_too_large: ..."
CREATE FUNCTION pg_temp.refusal(statement text)
RETURNS text
LANGUAGE plpgsql
AS $refusal$
DECLARE
    state text;
    message text;
BEGIN
    EXECUTE statement;
    RETURN 'accepted';
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        state = RETURNED_SQLSTATE,
        message = MESSAGE_TEXT;
    RETURN state || ' ' || message;
END;
$refusal$;

SELECT
    c.request,
    pg_temp.refusal(c.statement) AS refusal
FROM
    (
        VALUES
        (
            'unknown size',
            $s$SELECT uxid_generate('usr', 'huge')$s$
        ),
        (
            'rand_size 11',
            $s$SELECT uxid_generate('usr', rand_size => 11)$s$
        ),
        (
            'negative rand_size',
            $s$SELECT uxid_generate('usr', rand_size => -1)$s$
        ),
        (
            'compact time at the guard',
            $s$SELECT uxid_generate('usr', 's', TRUE,
            time_ms => 2164663517184)$s$
        ),
        (
            'time past 2^48 - 1',
            $s$SELECT uxid_generate('usr', time_ms => 281474976710656)$s$
        ),
        (
            'empty delimiter',
            $s$SELECT uxid_generate('usr', delimiter => '')$s$
        )
    ) AS c (request, statement);

-- uxid_encode's own refusals: it needs a time and the random bytes, and
-- rand of the wrong width is refused with the corpus name.
SELECT
    c.request,
    pg_temp.refusal(c.statement) AS refusal
FROM
    (
        VALUES
        (
            'encode with no time',
            $s$SELECT uxid_encode('usr', 's', NULL, '\x0123')$s$
        ),
        (
            'encode with no rand',
            $s$SELECT uxid_encode('usr', 's', 1700000000000, NULL)$s$
        ),
        (
            'encode with rand too wide',
            $s$SELECT uxid_encode('usr', 's', 1700000000000, '\x012345')$s$
        )
    ) AS c (request, statement);

-- The generator is volatile and parallel safe.
SELECT
    p.provolatile,
    p.proparallel
FROM pg_proc AS p
WHERE p.proname = 'uxid_generate';
