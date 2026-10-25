-- uxid_check_request, the one refusal point: every refusal, its SQLSTATE
-- and its name, and the order in which they apply.
\set SHOW_CONTEXT never

-- Runs a statement and answers the SQLSTATE and message of the error it
-- raises, read with GET STACKED DIAGNOSTICS, or "accepted".
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

-- A refusal raised to psql: SQLSTATE 22023 under VERBOSITY sqlstate, and
-- the message, which starts "uxid: " and the error's name, by default.
-- sabotage: ERRCODE = 'invalid_text_representation' in uxid__raise
-- -> "ERROR:  22023"
\set VERBOSITY sqlstate
SELECT uxid_check_request(rand_size => 11);
\set VERBOSITY default
SELECT uxid_check_request(rand_size => 11);

-- The conformance corpus's invalid generate cases, by case id: the
-- corpus's options, an absent one at its default.
-- sabotage: = 30 in place of = 31 in the compact guard
-- -> " invalid/generate-compact-time-at-guard | 22023 uxid:
-- compact_time_out_of_range: ..."
-- sabotage: rand_size > 11 in place of rand_size > 10
-- -> " invalid/generate-rand-size-11 | 22023 uxid: rand_size_too_large: ..."
SELECT
    c.case_id,
    pg_temp.refusal(c.statement) AS refusal
FROM
    (
        VALUES
        (
            'invalid/generate-compact-time-at-guard',
            $s$SELECT uxid_check_request(prefix => 'usr', size => 's',
            compact => TRUE, rand => '\x010203',
            time_ms => 2164663517184)$s$
        ),
        (
            'invalid/generate-compact-time-at-guard-previous-window',
            $s$SELECT uxid_check_request(prefix => 'usr', size => 's',
            compact => TRUE, rand => '\x010203',
            time_ms => 1065151889408)$s$
        ),
        (
            'invalid/generate-rand-too-wide',
            $s$SELECT uxid_check_request(prefix => 'usr', size => 's',
            rand => '\x010203', time_ms => 1700000000000)$s$
        ),
        (
            'invalid/generate-rand-too-narrow',
            $s$SELECT uxid_check_request(prefix => 'usr', size => 'xl',
            rand => '\x010203040506070809', time_ms => 1700000000000)$s$
        ),
        (
            'invalid/generate-rand-on-xs-standard',
            $s$SELECT uxid_check_request(prefix => 'usr', size => 'xs',
            rand => '\x01', time_ms => 1700000000000)$s$
        ),
        (
            'invalid/generate-rand-size-11',
            $s$SELECT uxid_check_request(prefix => 'usr', rand_size => 11,
            size => 'xl', time_ms => 1700000000000)$s$
        ),
        (
            'invalid/generate-from-with-monotonic',
            $s$SELECT uxid_check_request(from_key => 'alice@example.com',
            monotonic => TRUE, prefix => 'usr')$s$
        ),
        (
            'invalid/generate-rand-with-from',
            $s$SELECT uxid_check_request(from_key => 'alice@example.com',
            prefix => 'usr', rand => '\x00010203040506070809')$s$
        ),
        (
            'invalid/generate-rand-with-monotonic',
            $s$SELECT uxid_check_request(monotonic => TRUE, prefix => 'usr',
            rand => '\x0102', size => 's', time_ms => 1700000000000)$s$
        )
    ) AS c (case_id, statement);

-- invalid_argument, for an option the corpus does not name.
-- sabotage: WHEN FALSE in place of WHEN req.delimiter = ''
-- -> " empty delimiter | 22023 uxid: invalid_argument: delimiter must not
-- be empty"
-- sabotage: req.rand_size < -1 in place of req.rand_size < 0
-- -> " negative rand_size | 22023 uxid: invalid_argument: rand_size must
-- not be negative; got -1"
-- sabotage: 281474976710656 in place of 281474976710655 in the time range
-- check -> " time past 2^48 - 1 | 22023 uxid: invalid_argument: ..."
SELECT
    c.request,
    pg_temp.refusal(c.statement) AS refusal
FROM
    (
        VALUES
        (
            'unknown size',
            $s$SELECT uxid_check_request(size => 'huge')$s$
        ),
        (
            'size in upper case',
            $s$SELECT uxid_check_request(size => 'XL')$s$
        ),
        (
            'unknown letter_case',
            $s$SELECT uxid_check_request(letter_case => 'title')$s$
        ),
        (
            'empty delimiter',
            $s$SELECT uxid_check_request(delimiter => '')$s$
        ),
        (
            'negative rand_size',
            $s$SELECT uxid_check_request(rand_size => -1)$s$
        ),
        (
            'time before 0',
            $s$SELECT uxid_check_request(time_ms => -1)$s$
        ),
        (
            'time past 2^48 - 1',
            $s$SELECT uxid_check_request(time_ms => 281474976710656)$s$
        ),
        (
            'monotonic xs with explicit standard time',
            $s$SELECT uxid_check_request(size => 'xs', compact => FALSE,
            monotonic => TRUE)$s$
        ),
        (
            'monotonic with rand_size 0',
            $s$SELECT uxid_check_request(rand_size => 0,
            monotonic => TRUE)$s$
        )
    ) AS c (request, statement);

-- Requests it accepts: the defaults, every spelling, the ends of standard
-- time, the compact guard's last valid time, a monotonic xs with no time
-- form given (compact), and a deterministic request, which reads no time,
-- random width or time form.
-- sabotage: WHEN FALSE in place of WHEN req.from_key IS NOT NULL THEN NULL
-- -> " deterministic with a time out of range | accepted"
SELECT
    c.request,
    pg_temp.refusal(c.statement) AS refusal
FROM
    (
        VALUES
        ('defaults', $s$SELECT uxid_check_request()$s$),
        (
            'every option NULL',
            $s$SELECT uxid_check_request(NULL, NULL, NULL, NULL, NULL, NULL,
            NULL, NULL, NULL, NULL)$s$
        ),
        (
            'long spelling',
            $s$SELECT uxid_check_request(size => 'xsmall',
            letter_case => 'upper', delimiter => '-')$s$
        ),
        (
            'time 0',
            $s$SELECT uxid_check_request(time_ms => 0)$s$
        ),
        (
            'time 2^48 - 1',
            $s$SELECT uxid_check_request(time_ms => 281474976710655)$s$
        ),
        (
            'compact guard last valid',
            $s$SELECT uxid_check_request(size => 's', compact => TRUE,
            rand => '\x012345', time_ms => 1065151889407)$s$
        ),
        (
            'rand matching an explicit rand_size',
            $s$SELECT uxid_check_request(size => 's', rand_size => 4,
            rand => '\x01020304')$s$
        ),
        (
            'monotonic xs, time form not given',
            $s$SELECT uxid_check_request(size => 'xs', monotonic => TRUE)$s$
        ),
        (
            'deterministic with a time out of range',
            $s$SELECT uxid_check_request(from_key => 'alice@example.com',
            time_ms => -1)$s$
        ),
        (
            'deterministic with rand_size 11',
            $s$SELECT uxid_check_request(from_key => 'alice@example.com',
            rand_size => 11)$s$
        ),
        (
            'deterministic, compact at the guard',
            $s$SELECT uxid_check_request(from_key => 'alice@example.com',
            compact => TRUE, time_ms => 2164663517184)$s$
        )
    ) AS c (request, statement);

-- The order: a request that breaks several rules is refused for the
-- first. Each row breaks the rule it names first and every later rule it
-- lists.
-- sabotage: AND NOT req.monotonic added to the rand_with_from condition
-- -> " rand_with_from before from_with_monotonic | 22023 uxid:
-- rand_with_from: ..."
-- sabotage: AND octet_length(req.rand) = req.width added to the
-- rand_with_monotonic condition
-- -> " rand_with_monotonic before rand_width_mismatch | 22023 uxid:
-- rand_with_monotonic: ..."
SELECT
    c.request,
    pg_temp.refusal(c.statement) AS refusal
FROM
    (
        VALUES
        (
            'invalid_argument before rand_with_from',
            $s$SELECT uxid_check_request(size => 'huge',
            from_key => 'alice@example.com', rand => '\x00')$s$
        ),
        (
            'rand_with_from before from_with_monotonic',
            $s$SELECT uxid_check_request(from_key => 'alice@example.com',
            rand => '\x00', monotonic => TRUE)$s$
        ),
        (
            'time range before rand_size_too_large',
            $s$SELECT uxid_check_request(time_ms => -1, rand_size => 11)$s$
        ),
        (
            'rand_size_too_large before rand_with_monotonic',
            $s$SELECT uxid_check_request(rand_size => 11, rand => '\x00',
            monotonic => TRUE)$s$
        ),
        (
            'rand_with_monotonic before rand_width_mismatch',
            $s$SELECT uxid_check_request(size => 's', rand => '\x00',
            monotonic => TRUE)$s$
        ),
        (
            'rand_width_mismatch before compact_time_out_of_range',
            $s$SELECT uxid_check_request(size => 's', compact => TRUE,
            rand => '\x00', time_ms => 2164663517184)$s$
        ),
        (
            'no monotonic random field before compact_time_out_of_range',
            $s$SELECT uxid_check_request(size => 's', compact => TRUE,
            rand_size => 0, monotonic => TRUE, time_ms => 2164663517184)$s$
        )
    ) AS c (request, statement);

-- The check is immutable and parallel safe, and returns void.
SELECT
    p.provolatile,
    p.proparallel,
    pg_get_function_result(p.oid) AS result
FROM pg_proc AS p
WHERE p.proname = 'uxid_check_request';
