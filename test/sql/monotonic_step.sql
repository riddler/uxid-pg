-- uxid_monotonic_step: the pure step of the monotonic generator, driven
-- with fixed draws, and the internal helpers it rests on.
\set SHOW_CONTEXT never

-- The corpus's monotonic cases (uxid 2.10.0, conformance/monotonic.json),
-- every one: a generator for the case's prefix, size and time form, lower
-- case, called once per time; the first call draws the initial seed, each
-- later call the next step, and the call whose step overflows the field
-- the overflow seed, which is drawn at most once. Each id is the step's
-- time and value through uxid_encode.
CREATE FUNCTION pg_temp.run_case(
    p_prefix text,
    p_size text,
    p_compact boolean,
    p_times bigint[],
    p_initial_seed numeric,
    p_steps bigint[],
    p_overflow_seed numeric
)
RETURNS TABLE (call integer, drew text, id text)
LANGUAGE plpgsql
AS $run$
DECLARE
    v_width integer := uxid__rand_width(p_size, p_compact, NULL, TRUE);
    v_time bigint;
    v_rand numeric;
    v_overflow numeric := p_overflow_seed;
    v_next record;
BEGIN
    FOR v_call IN 1 .. cardinality(p_times) LOOP
        SELECT s.time_ms, s.rand, s.drew INTO v_next
        FROM uxid_monotonic_step(
            v_time,
            v_rand,
            p_times[v_call],
            v_width,
            CASE WHEN v_call = 1 THEN p_initial_seed END,
            p_steps[v_call - 1],
            v_overflow
        ) AS s;
        IF v_next.drew = 'step_overflow' THEN
            v_overflow := NULL;
        END IF;
        v_time := v_next.time_ms;
        v_rand := v_next.rand;
        call := v_call;
        drew := v_next.drew;
        id := uxid_encode(
            p_prefix,
            p_size,
            v_time,
            uxid__numeric_bytes(v_rand, v_width),
            p_compact
        );
        RETURN NEXT;
    END LOOP;
END;
$run$;

-- sabotage: last_rand + step < in place of last_rand + step <= in
-- uxid__monotonic_rule -> " monotonic/xs-compact-overflow-clock-back
-- |    2 | step_overflow | usr_hf7yat0111                 | f"
WITH
cases AS (
    SELECT
        c.case_id,
        c.prefix,
        c.size,
        c.compact,
        c.times,
        c.initial_seed,
        c.steps,
        c.overflow_seed,
        c.expected
    FROM
        (
            VALUES
            (
                'monotonic/xl-same-millisecond',
                'usr',
                'xl',
                FALSE,
                ARRAY[
                    1700000000000,
                    1700000000000,
                    1700000000000,
                    1700000000000
                ]::bigint[],
                123456789::numeric,
                ARRAY[1, 1099511627776, 42]::bigint[],
                NULL::numeric,
                ARRAY[
                    'usr_01hf7yat0000000000003nqk8n',
                    'usr_01hf7yat0000000000003nqk8p',
                    'usr_01hf7yat0000000001003nqk8p',
                    'usr_01hf7yat0000000001003nqka0'
                ]
            ),
            (
                'monotonic/m-clock-moves-back',
                'usr',
                'm',
                FALSE,
                ARRAY[
                    1700000000000,
                    1699999999999,
                    1699999999990,
                    1700000000000
                ]::bigint[],
                1000::numeric,
                ARRAY[5, 1048576, 7]::bigint[],
                NULL::numeric,
                ARRAY[
                    'usr_01hf7yat00000000z8',
                    'usr_01hf7yat00000000zd',
                    'usr_01hf7yat00000100zd',
                    'usr_01hf7yat00000100zm'
                ]
            ),
            (
                'monotonic/s-overflow-bumps-time',
                'usr',
                's',
                FALSE,
                ARRAY[
                    1700000000000,
                    1700000000000,
                    1700000000000,
                    1700000000000,
                    1700000000000,
                    1700000000001
                ]::bigint[],
                65000::numeric,
                ARRAY[200, 250, 100, 7, 3]::bigint[],
                1234::numeric,
                ARRAY[
                    'usr_01hf7yat00zqm0',
                    'usr_01hf7yat00ztr0',
                    'usr_01hf7yat00zyn0',
                    'usr_01hf7yat010k90',
                    'usr_01hf7yat010kc1',
                    'usr_01hf7yat010ke0'
                ]
            ),
            (
                'monotonic/xs-compact-overflow-clock-back',
                'usr',
                'xs',
                TRUE,
                ARRAY[
                    1700000000000, 1700000000000, 1699999999999
                ]::bigint[],
                250::numeric,
                ARRAY[5, 16]::bigint[],
                9::numeric,
                ARRAY['usr_hf7yat00z2', 'usr_hf7yat00z7', 'usr_hf7yat0111']
            ),
            (
                'monotonic/l-compact-single',
                'usr',
                'l',
                TRUE,
                ARRAY[1700000000000]::bigint[],
                0::numeric,
                ARRAY[]::bigint[],
                NULL::numeric,
                ARRAY['usr_hf7yat000000000000000']
            ),
            (
                'monotonic/s-compact-no-prefix-largest-step',
                NULL,
                's',
                TRUE,
                ARRAY[1700000000000, 1700000000000]::bigint[],
                0::numeric,
                ARRAY[4096]::bigint[],
                NULL::numeric,
                ARRAY['hf7yat0000000', 'hf7yat0000800']
            )
        ) AS c (
            case_id,
            prefix,
            size,
            compact,
            times,
            initial_seed,
            steps,
            overflow_seed,
            expected
        )
)

SELECT
    c.case_id,
    r.call,
    r.drew,
    r.id,
    r.id = c.expected[r.call] AS matches
FROM cases AS c
CROSS JOIN
    LATERAL pg_temp.run_case(
        c.prefix,
        c.size,
        c.compact,
        c.times,
        c.initial_seed,
        c.steps,
        c.overflow_seed
    ) AS r
ORDER BY c.case_id, r.call;

-- The three rules one at a time, with the draws a rule does not take left
-- NULL: no state, a later clock, the same and an earlier clock, and an
-- overflow at the field's top.
-- sabotage: WHEN 'step' THEN a.clock in place of WHEN 'step' THEN
-- a.last_time in uxid_monotonic_step -> " clock moved back |
-- 1699999999000 |   105 | step"
-- sabotage: ELSE a.last_time in place of ELSE a.last_time + 1 in
-- uxid_monotonic_step -> " one past the top | 1700000000000 |     9 |
-- step_overflow"
SELECT
    c.label,
    s.time_ms,
    s.rand,
    s.drew
FROM
    (
        VALUES
        (
            1,
            'no state',
            NULL::bigint,
            NULL::numeric,
            1700000000000::bigint,
            100::numeric,
            NULL::bigint,
            NULL::numeric
        ),
        (2, 'a later clock', 1700000000000, 100, 1700000000001, 7, NULL, NULL),
        (3, 'the same clock', 1700000000000, 100, 1700000000000, NULL, 5, NULL),
        (
            4,
            'clock moved back',
            1700000000000,
            100,
            1699999999000,
            NULL,
            5,
            NULL
        ),
        (
            5,
            'the field''s top',
            1700000000000,
            65530,
            1700000000000,
            NULL,
            5,
            9
        ),
        (6, 'one past the top', 1700000000000, 65530, 1700000000000, NULL, 6, 9)
    )
        AS c (
            n, label, last_time_ms, last_rand, now_ms, seed, step, overflow_seed
        )
CROSS JOIN
    LATERAL uxid_monotonic_step(
        c.last_time_ms,
        c.last_rand,
        c.now_ms,
        2,
        c.seed,
        c.step,
        c.overflow_seed
    ) AS s
ORDER BY c.n;

-- An xl field is 80 bits: the step reaches 2^80 - 1 exactly and overflows
-- one past it, and the value converts to and from its 10 bytes with no
-- loss.
-- sabotage: * 1099511627775 in place of * 1099511627776 in
-- uxid__bytes_numeric -> " 1208925819613529663078400 | ..." under
-- top_from_bytes
SELECT
    uxid__bytes_numeric('\xffffffffffffffffffff') AS top_from_bytes,
    uxid__numeric_bytes(1208925819614629174706175, 10) AS top_to_bytes,
    uxid__numeric_bytes(
        uxid__bytes_numeric('\x0123456789abcdef0123'), 10
    ) AS round_trip,
    uxid__bytes_numeric('') AS empty_field,
    uxid__numeric_bytes(258, 2) AS two_bytes;
SELECT
    s.time_ms,
    s.rand,
    s.drew
FROM
    uxid_monotonic_step(
        1700000000000,
        1208925819614629174706174,
        1700000000000,
        10,
        NULL,
        1,
        NULL
    ) AS s;
SELECT
    s.time_ms,
    s.rand,
    s.drew
FROM
    uxid_monotonic_step(
        1700000000000,
        1208925819614629174706174,
        1700000000000,
        10,
        NULL,
        2,
        5
    ) AS s;

-- The draws of one call, cut from 25 random bytes: the seed from byte 1,
-- the step from the low 4w bits of ceil(w/2) bytes at byte 11, plus one
-- (so all ones gives 2^(4w), all zeros 1, and the bits above 4w are never
-- read), the overflow seed from byte 16.
-- sabotage: & ((1::bigint << (4 * width)) - 1) removed from the step in
-- uxid__monotonic_draws -> "     1 | all ones         |
-- 1 |           256 |                       2"
-- sabotage: FOR width / 2 in place of FOR (width + 1) / 2 in
-- uxid__monotonic_draws -> "     1 | all ones         |
-- 1 |             1 |                       2"
SELECT
    c.width,
    c.label,
    d.seed,
    d.step,
    d.overflow_seed
FROM
    (
        VALUES
        (
            1,
            'all ones',
            '\x01000000000000000000ff0000000002000000000000000000'::bytea
        ),
        (
            1,
            'high nibble only',
            '\x01000000000000000000f00000000002000000000000000000'::bytea
        ),
        (
            3,
            'all ones',
            '\x01020300000000000000ffff00000004050600000000000000'::bytea
        ),
        (
            3,
            'bit 12 only',
            '\x01020300000000000000100000000004050600000000000000'::bytea
        ),
        (
            10,
            'all ones',
            '\x0102030405060708090affffffffff0b0c0d0e0f1011121314'::bytea
        ),
        (
            10,
            'all zeros',
            '\x0102030405060708090a00000000000b0c0d0e0f1011121314'::bytea
        )
    ) AS c (width, label, draws)
CROSS JOIN LATERAL uxid__monotonic_draws(c.draws, c.width) AS d
ORDER BY c.width, c.label;

-- A step drawn this way feeds the step function: the largest step a
-- 1-byte field draws, 16, takes 239 to 255 and 240 over the top.
SELECT
    s.time_ms,
    s.rand,
    s.drew
FROM
    uxid__monotonic_draws(
        '\x01000000000000000000ff0000000002000000000000000000', 1
    ) AS d
CROSS JOIN
    LATERAL uxid_monotonic_step(
        1700000000000, 239, 1700000000000, 1, d.seed, d.step, d.overflow_seed
    ) AS s;
SELECT
    s.time_ms,
    s.rand,
    s.drew
FROM
    uxid__monotonic_draws(
        '\x01000000000000000000ff0000000002000000000000000000', 1
    ) AS d
CROSS JOIN
    LATERAL uxid_monotonic_step(
        1700000000000, 240, 1700000000000, 1, d.seed, d.step, d.overflow_seed
    ) AS s;

-- The step function's refusals: a width outside 1 to 10, no clock, a half
-- state, values outside the field, a step outside 1 to 2^(4w), and a NULL
-- draw the rule needs.
-- sabotage: a.step_value > a.step_max * 2 in place of a.step_value >
-- a.step_max -> " step past 2^(4w)                | accepted"
-- sabotage: WHEN FALSE in place of WHEN a.chosen = 'step_overflow' AND
-- a.overflow_value IS NULL -> " overflow with no overflow seed  |
-- accepted"
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
            1,
            'width 0',
            $s$SELECT * FROM uxid_monotonic_step(NULL, NULL, 1, 0, 1, NULL,
            NULL)$s$
        ),
        (
            2,
            'width 11',
            $s$SELECT * FROM uxid_monotonic_step(NULL, NULL, 1, 11, 1, NULL,
            NULL)$s$
        ),
        (
            3,
            'width NULL',
            $s$SELECT * FROM uxid_monotonic_step(NULL, NULL, 1, NULL, 1, NULL,
            NULL)$s$
        ),
        (
            4,
            'no clock',
            $s$SELECT * FROM uxid_monotonic_step(NULL, NULL, NULL, 2, 1, NULL,
            NULL)$s$
        ),
        (
            5,
            'a last time with no last value',
            $s$SELECT * FROM uxid_monotonic_step(5, NULL, 5, 2, 1, 1,
            NULL)$s$
        ),
        (
            6,
            'a last value past the field',
            $s$SELECT * FROM uxid_monotonic_step(5, 65536, 5, 2, NULL, 1,
            NULL)$s$
        ),
        (
            7,
            'a fractional last value',
            $s$SELECT * FROM uxid_monotonic_step(5, 1.5, 5, 2, NULL, 1,
            NULL)$s$
        ),
        (
            8,
            'a negative seed',
            $s$SELECT * FROM uxid_monotonic_step(NULL, NULL, 5, 2, -1, NULL,
            NULL)$s$
        ),
        (
            9,
            'a seed past the field',
            $s$SELECT * FROM uxid_monotonic_step(NULL, NULL, 5, 2, 65536,
            NULL, NULL)$s$
        ),
        (
            10,
            'step 0',
            $s$SELECT * FROM uxid_monotonic_step(5, 1, 5, 2, NULL, 0,
            NULL)$s$
        ),
        (
            11,
            'step past 2^(4w)',
            $s$SELECT * FROM uxid_monotonic_step(5, 1, 5, 2, NULL, 257,
            NULL)$s$
        ),
        (
            12,
            'an overflow seed past the field',
            $s$SELECT * FROM uxid_monotonic_step(5, 1, 5, 2, NULL, 1,
            65536)$s$
        ),
        (
            13,
            'no state and no seed',
            $s$SELECT * FROM uxid_monotonic_step(NULL, NULL, 5, 2, NULL, 1,
            1)$s$
        ),
        (
            14,
            'the same clock and no step',
            $s$SELECT * FROM uxid_monotonic_step(5, 1, 5, 2, 1, NULL,
            1)$s$
        ),
        (
            15,
            'overflow with no overflow seed',
            $s$SELECT * FROM uxid_monotonic_step(5, 65535, 5, 2, 1, 1,
            NULL)$s$
        ),
        (
            16,
            'the largest step accepted',
            $s$SELECT * FROM uxid_monotonic_step(5, 1, 5, 2, NULL, 256,
            NULL)$s$
        )
    ) AS c (n, request, statement)
ORDER BY c.n;

-- The step function is immutable and parallel safe.
SELECT
    p.provolatile,
    p.proparallel,
    pg_get_function_result(p.oid) AS result
FROM pg_proc AS p
WHERE p.proname = 'uxid_monotonic_step';
