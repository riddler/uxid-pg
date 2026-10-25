-- The decode refusals: uxid_decode and uxid_decode_at raise SQLSTATE
-- 22P02 (invalid_text_representation) with "uxid: <reason>", and
-- uxid_decode_error answers the same reason without raising. The reasons
-- are checked in the order the wire format's Refusals section states in
-- its sentence: empty, invalid_length, invalid_character.
SET client_encoding = 'UTF8';
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

-- A refusal raised to psql: SQLSTATE 22P02 under VERBOSITY sqlstate, and
-- the message "uxid: <reason>" by default.
-- sabotage: ERRCODE = 'invalid_parameter_value' in uxid__raise_decode
-- -> "ERROR:  22P02"
\set VERBOSITY sqlstate
SELECT d.prefix FROM uxid_decode('usr_') AS d;
\set VERBOSITY default
SELECT d.prefix FROM uxid_decode('usr_') AS d;
SELECT d.prefix FROM uxid_decode_at('usr_01hf7yat000', 0) AS d;

-- Every decode case of invalid.json in the conformance corpus at v2.10.0
-- (16 cases), by case id: the reason uxid_decode_error answers, and the
-- SQLSTATE and message uxid_decode and uxid_decode_at raise. The two
-- non-ASCII cases count the body's length in bytes (U+00E9, 2 bytes): a
-- 24-character body with it is 26 bytes, a table length, and refused for
-- the character; a 25-character one is 27 bytes and refused for the
-- length. decode/length-and-character fails two rules and is refused for
-- the length, which is checked first.
-- sabotage: the invalid_character WHEN placed before the invalid_length
-- WHEN in uxid__body_error -> " invalid/decode-length-and-character |
-- invalid_character | ..." and " invalid/decode-non-ascii-off-table-length
-- | invalid_character | ..."
-- sabotage: length(body) in place of octet_length(convert_to(body,
-- 'UTF8')) -> " invalid/decode-non-ascii-table-length | invalid_length |
-- ..." and " invalid/decode-non-ascii-off-table-length | invalid_character
-- | ..."
-- sabotage: 25 added to the length table in uxid__body_error
-- -> " invalid/decode-length-25 | | | accepted | f"
SELECT
    c.case_id,
    uxid_decode_error(c.input) AS reason,
    uxid_decode_error(c.input) = c.expected AS matches,
    pg_temp.refusal(
        format('SELECT d.prefix FROM uxid_decode(%L) AS d', c.input)
    ) AS decode_refusal,
    pg_temp.refusal(
        format(
            'SELECT d.prefix FROM uxid_decode_at(%L, 1700000000000) AS d',
            c.input
        )
    ) = '22P02 uxid: ' || c.expected AS decode_at_matches
FROM
    (
        VALUES
        ('invalid/decode-empty-string', '', 'empty'),
        ('invalid/decode-ends-in-delimiter', 'usr_', 'empty'),
        (
            'invalid/decode-prefix-with-delimiter-ends-in-delimiter',
            'a_b_', 'empty'
        ),
        ('invalid/decode-delimiter-only', '_', 'empty'),
        ('invalid/decode-length-11', 'usr_01hf7yat000', 'invalid_length'),
        (
            'invalid/decode-length-25',
            'usr_01hf7yat00000g40r40m30e20', 'invalid_length'
        ),
        (
            'invalid/decode-length-27',
            'usr_01hf7yat00000g40r40m30e2090', 'invalid_length'
        ),
        ('invalid/decode-no-delimiter-short', 'usr', 'invalid_length'),
        (
            'invalid/decode-character-in-time',
            'usr_01hu7yat00000g40r40m30e209', 'invalid_character'
        ),
        (
            'invalid/decode-character-in-random',
            'usr_01hf7yat00000g4lr40m30e209', 'invalid_character'
        ),
        (
            'invalid/decode-upper-o-in-random',
            'usr_01hf7yat00000g40r40mO0e209', 'invalid_character'
        ),
        (
            'invalid/decode-hyphen-in-body',
            'usr_01hf7yat00-00g40r40m30e209', 'invalid_character'
        ),
        (
            'invalid/decode-character-in-deterministic',
            'usr_zcvt7epac0t1ebcsjfyf7cwzi5', 'invalid_character'
        ),
        (
            'invalid/decode-non-ascii-table-length',
            '01hf7yat00000g40r40m30e2é', 'invalid_character'
        ),
        (
            'invalid/decode-non-ascii-off-table-length',
            '01hf7yat00000g40r40m30e20é', 'invalid_length'
        ),
        (
            'invalid/decode-length-and-character',
            'usr_01hf7yat00u', 'invalid_length'
        )
    ) AS c (case_id, input, expected)
ORDER BY convert_to(c.case_id, 'UTF8');

-- The order on bodies that fail more than one rule. An empty body has no
-- length to refuse; a body of a wrong length with a character outside
-- the alphabet is refused for the length; a table length with a bad
-- character for the character. Each body is refused the same way with
-- and without the marker.
-- sabotage: octet_length(body) = 0 moved after the invalid_length WHEN
-- -> " usr_                  | invalid_length"
SELECT
    c.input,
    uxid_decode_error(c.input) AS reason
FROM
    (
        VALUES
        ('usr_'),
        ('usr_u'),
        ('usr_01hf7yat0u'),
        ('usr_01hf7yat0uu'),
        ('usr_zu'),
        ('usr_z1yhw20vau'),
        ('usr_01hf7yat00')
    ) AS c (input)
ORDER BY convert_to(c.input, 'UTF8');

-- uxid_decode_error never raises: not for an empty delimiter (it answers
-- invalid_argument), not for a NULL id or delimiter, and not for a
-- compact body, since it reads no clock.
SELECT
    uxid_decode_error('usr_01hf7yat0004h1', '') AS empty_delimiter,
    uxid_decode_error(NULL) AS null_id,
    uxid_decode_error('usr_01hf7yat0004h1', NULL) AS null_delimiter,
    uxid_decode_error('usr_hf7yat0004hm5') AS compact_body,
    uxid_decode_error('doc--hf7yat0004hm5', '--') AS other_delimiter,
    uxid_decode_error('doc--hf7yat0004hm5') AS wrong_delimiter;
