-- uxid 1.0.0: prefixed, K-sortable, human-readable identifiers.
--
-- This script carries no psql guard line, so the same file serves
-- CREATE EXTENSION uxid and a plain migration run once with psql -f.
--
-- Every function that calls another function of this extension is
-- LANGUAGE sql with a BEGIN ATOMIC body, which binds its callees when it
-- is created, so the extension works with its schema off the caller's
-- search_path, after ALTER EXTENSION uxid SET SCHEMA, and under the empty
-- search_path a dump restore uses. The one PL/pgSQL function,
-- uxid__raise, calls nothing. A function is created after every function
-- it calls.
--
-- Functions whose names start uxid__ (two underscores) are internal
-- helpers, not part of the public surface.

CREATE FUNCTION uxid_version()
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT '1.0.0';
END;

COMMENT ON FUNCTION uxid_version() IS
'The version of the uxid extension script installed, such as 1.0.0.';

-- Raises a refusal: SQLSTATE 22023 (invalid_parameter_value) with the
-- message "uxid: <error_name>: <detail>". It is VOLATILE so the planner
-- never evaluates it ahead of time out of a CASE branch that is not taken.
CREATE FUNCTION uxid__raise(error_name text, detail text)
RETURNS void
LANGUAGE plpgsql
VOLATILE PARALLEL SAFE
AS $raise$
BEGIN
    RAISE EXCEPTION USING
        ERRCODE = 'invalid_parameter_value',
        MESSAGE = 'uxid: ' || error_name || ': ' || detail;
END;
$raise$;

COMMENT ON FUNCTION uxid__raise(text, text) IS
'Internal helper of the uxid extension, not part of its public surface: '
'raises SQLSTATE 22023 with the message "uxid: <error_name>: <detail>".';

-- The 14 fully random bytes of a version 4 UUID's 16: bytes 0 to 5, 7 and
-- 9 to 15 (counting from 0). Byte 6 holds the version nibble and byte 8
-- the variant bits, so neither is taken.
CREATE FUNCTION uxid__uuid_bytes(uuid_bytes bytea)
RETURNS bytea
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        substring(uuid_bytes FROM 1 FOR 6)
        || substring(uuid_bytes FROM 8 FOR 1)
        || substring(uuid_bytes FROM 10 FOR 7);
END;

COMMENT ON FUNCTION uxid__uuid_bytes(bytea) IS
'Internal helper of the uxid extension, not part of its public surface: '
'the 14 fully random bytes (0 to 5, 7 and 9 to 15) of a UUID''s 16 bytes, '
'leaving out the version and variant bits.';

-- n random bytes, 0 to 28, from the core CSPRNG: the fully random bytes of
-- one gen_random_uuid() for up to 14, of two for up to 28.
CREATE FUNCTION uxid__random_bytes(n integer)
RETURNS bytea
LANGUAGE sql
VOLATILE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        CASE
            WHEN n < 0 OR n > 28
                THEN
                    uxid__raise(
                        'invalid_argument',
                        format(
                            'random bytes are drawn 0 to 28 at a time; got %s',
                            n
                        )
                    )
        END;
    SELECT
        substring(
            uxid__uuid_bytes(uuid_send(gen_random_uuid()))
            || CASE
                WHEN n > 14
                    THEN uxid__uuid_bytes(uuid_send(gen_random_uuid()))
                ELSE ''::bytea
            END
            FROM 1 FOR n
        );
END;

COMMENT ON FUNCTION uxid__random_bytes(integer) IS
'Internal helper of the uxid extension, not part of its public surface: '
'n random bytes (0 to 28) taken from the fully random bytes of '
'uuid_send(gen_random_uuid()), one UUID for up to 14 bytes, two for more.';

-- The short name of a size (xs, s, m, l or xl) for either spelling, xl for
-- NULL, and NULL for anything else.
CREATE FUNCTION uxid__size(size text)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        CASE coalesce(size, 'xl')
            WHEN 'xs' THEN 'xs'
            WHEN 'xsmall' THEN 'xs'
            WHEN 's' THEN 's'
            WHEN 'small' THEN 's'
            WHEN 'm' THEN 'm'
            WHEN 'medium' THEN 'm'
            WHEN 'l' THEN 'l'
            WHEN 'large' THEN 'l'
            WHEN 'xl' THEN 'xl'
            WHEN 'xlarge' THEN 'xl'
        END;
END;

COMMENT ON FUNCTION uxid__size(text) IS
'Internal helper of the uxid extension, not part of its public surface: '
'the short name of a size (xs, s, m, l or xl) for its short or long '
'spelling, xl for NULL, and NULL for an unknown size.';

-- Whether a request uses compact time: the caller's choice, or when it
-- gives none (NULL), compact for a monotonic xs and standard otherwise.
CREATE FUNCTION uxid__compact(size text, compact boolean, monotonic boolean)
RETURNS boolean
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        coalesce(
            compact,
            coalesce(monotonic, FALSE) AND uxid__size(size) = 'xs'
        );
END;

COMMENT ON FUNCTION uxid__compact(text, boolean, boolean) IS
'Internal helper of the uxid extension, not part of its public surface: '
'whether a request uses compact time; NULL means the size''s default, '
'which is compact for a monotonic xs and standard otherwise.';

-- The random field's width in bytes for a request: an explicit rand_size,
-- or the size's width for its time form (the wire format's size table).
CREATE FUNCTION uxid__rand_width(
    size text, compact boolean, rand_size integer, monotonic boolean
)
RETURNS integer
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        coalesce(
            form.explicit_width,
            CASE form.short_size
                WHEN 'xs' THEN CASE WHEN form.is_compact THEN 1 ELSE 0 END
                WHEN 's' THEN CASE WHEN form.is_compact THEN 3 ELSE 2 END
                WHEN 'm' THEN CASE WHEN form.is_compact THEN 6 ELSE 5 END
                WHEN 'l' THEN CASE WHEN form.is_compact THEN 8 ELSE 7 END
                WHEN 'xl' THEN 10
            END
        )
    FROM
        (
            SELECT
                rand_size AS explicit_width,
                uxid__size(size) AS short_size,
                uxid__compact(size, compact, monotonic) AS is_compact
        ) AS form;
END;

COMMENT ON FUNCTION uxid__rand_width(text, boolean, integer, boolean) IS
'Internal helper of the uxid extension, not part of its public surface: '
'the random field''s width in bytes, rand_size when given, otherwise the '
'size''s width for its time form.';

-- The time field in lower case: standard time is the 48-bit time as 10
-- characters (a 3-bit group, then nine 5-bit groups); compact time is its
-- low 40 bits as 8 characters. Most significant bits first.
CREATE FUNCTION uxid__base32_time(time_ms bigint, compact boolean)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        string_agg(
            substr(
                '0123456789abcdefghjkmnpqrstvwxyz',
                (
                    (
                        (form.ms & form.mask)
                        >> (5 * (form.width - 1 - g.i))
                    )
                    & 31
                )::integer + 1,
                1
            ),
            ''
            ORDER BY g.i
        )
    FROM
        (
            SELECT
                time_ms AS ms,
                CASE WHEN compact THEN 8 ELSE 10 END AS width,
                CASE
                    WHEN compact THEN 1099511627775::bigint
                    ELSE 281474976710655::bigint
                END AS mask
        ) AS form
    CROSS JOIN LATERAL generate_series(0, form.width - 1) AS g (i);
END;

COMMENT ON FUNCTION uxid__base32_time(bigint, boolean) IS
'Internal helper of the uxid extension, not part of its public surface: '
'the time field in lower-case Crockford base32, 10 characters of the '
'48-bit time or, compact, 8 characters of its low 40 bits.';

-- The random field in lower case: the bytes most significant bit first,
-- cut into 5-bit groups, ceil(8 x bytes / 5) characters. A last group of
-- fewer than 5 bits is written as its raw value, never padded.
CREATE FUNCTION uxid__base32_bytes(rand bytea)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        coalesce(
            string_agg(
                substr(
                    '0123456789abcdefghjkmnpqrstvwxyz',
                    (
                        (
                            (
                                (get_byte(grp.field, grp.first_bit / 8) << 8)
                                | CASE
                                    WHEN grp.first_bit / 8 + 1 < grp.bytes
                                        THEN
                                            get_byte(
                                                grp.field,
                                                grp.first_bit / 8 + 1
                                            )
                                    ELSE 0
                                END
                            )
                            >> (16 - grp.first_bit % 8 - grp.bits)
                        )
                        & ((1 << grp.bits) - 1)
                    ) + 1,
                    1
                ),
                ''
                ORDER BY grp.first_bit
            ),
            ''
        )
    FROM
        (
            SELECT
                field.field,
                field.bytes,
                5 * g.i AS first_bit,
                least(5, 8 * field.bytes - 5 * g.i) AS bits
            FROM
                (
                    SELECT
                        rand AS field,
                        octet_length(rand) AS bytes
                ) AS field
            CROSS JOIN
                LATERAL generate_series(
                    0, (8 * field.bytes + 4) / 5 - 1
                ) AS g (i)
        ) AS grp;
END;

COMMENT ON FUNCTION uxid__base32_bytes(bytea) IS
'Internal helper of the uxid extension, not part of its public surface: '
'bytes in lower-case Crockford base32, most significant bit first, a '
'short last group written as its raw value.';

-- The one refusal point. The order is the reference's (uxid 2.10.0's
-- UXID.new/1 and UXID.Encoder): a fixed random field with a deterministic
-- body, then a deterministic body with monotonic generation (a
-- deterministic request reads no time, random width or time form); then,
-- for a time-based body, an explicit random width above 10 bytes, a fixed
-- random field with monotonic generation, a fixed random field of the
-- wrong width, a monotonic request with no random field, and a compact
-- time whose first character would be the deterministic marker. The
-- invalid_argument checks on an option's own value come first, and the
-- time range check comes before the random width checks.
CREATE FUNCTION uxid_check_request(
    prefix text DEFAULT NULL,
    size text DEFAULT 'xl',
    compact boolean DEFAULT NULL,
    rand_size integer DEFAULT NULL,
    letter_case text DEFAULT 'lower',
    delimiter text DEFAULT '_',
    time_ms bigint DEFAULT NULL,
    rand bytea DEFAULT NULL,
    from_key text DEFAULT NULL,
    monotonic boolean DEFAULT FALSE
)
RETURNS void
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        CASE
            WHEN req.short_size IS NULL
                THEN
                    uxid__raise(
                        'invalid_argument',
                        format(
                            'size must be xs, s, m, l or xl (or xsmall, small, '
                            'medium, large or xlarge); got %s',
                            quote_literal(req.size)
                        )
                    )
            WHEN req.letter_case NOT IN ('lower', 'upper')
                THEN
                    uxid__raise(
                        'invalid_argument',
                        format(
                            'letter_case must be lower or upper; got %s',
                            quote_literal(req.letter_case)
                        )
                    )
            WHEN req.delimiter = ''
                THEN
                    uxid__raise(
                        'invalid_argument', 'delimiter must not be empty'
                    )
            WHEN req.rand_size < 0
                THEN
                    uxid__raise(
                        'invalid_argument',
                        format(
                            'rand_size must not be negative; got %s',
                            req.rand_size
                        )
                    )
            WHEN req.from_key IS NOT NULL AND req.rand IS NOT NULL
                THEN
                    uxid__raise(
                        'rand_with_from',
                        'a deterministic id has no random field to fix'
                    )
            WHEN req.from_key IS NOT NULL AND req.monotonic
                THEN
                    uxid__raise(
                        'from_with_monotonic',
                        'a deterministic id is not generated monotonically'
                    )
            WHEN req.from_key IS NOT NULL THEN NULL
            WHEN req.time_ms < 0 OR req.time_ms > 281474976710655
                THEN
                    uxid__raise(
                        'invalid_argument',
                        format(
                            'time_ms must be from 0 to 281474976710655; got %s',
                            req.time_ms
                        )
                    )
            WHEN req.rand_size > 10
                THEN
                    uxid__raise(
                        'rand_size_too_large',
                        format(
                            'rand_size must be at most 10; got %s',
                            req.rand_size
                        )
                    )
            WHEN req.rand IS NOT NULL AND req.monotonic
                THEN
                    uxid__raise(
                        'rand_with_monotonic',
                        'monotonic generation fills the random field itself'
                    )
            WHEN req.rand IS NOT NULL AND octet_length(req.rand) <> req.width
                THEN
                    uxid__raise(
                        'rand_width_mismatch',
                        format(
                            'rand must be %s bytes for this request; got %s',
                            req.width,
                            octet_length(req.rand)
                        )
                    )
            WHEN req.monotonic AND req.width = 0
                THEN
                    uxid__raise(
                        'invalid_argument',
                        'monotonic generation needs a random field; an xs '
                        'with standard time or a rand_size of 0 has none'
                    )
            WHEN
                req.is_compact
                AND ((req.time_ms & 1099511627775::bigint) >> 35) = 31
                THEN
                    uxid__raise(
                        'compact_time_out_of_range',
                        format(
                            'the compact time of %s would start with the '
                            'deterministic marker',
                            req.time_ms
                        )
                    )
        END
    FROM
        (
            SELECT
                size,
                rand_size,
                delimiter,
                time_ms,
                rand,
                from_key,
                uxid__size(size) AS short_size,
                coalesce(letter_case, 'lower') AS letter_case,
                coalesce(monotonic, FALSE) AS monotonic,
                uxid__compact(size, compact, monotonic) AS is_compact,
                uxid__rand_width(size, compact, rand_size, monotonic) AS width
        ) AS req;
END;

COMMENT ON FUNCTION uxid_check_request(
    text, text, boolean, integer, text, text, bigint, bytea, text, boolean
) IS
'Refuses a generation request, raising SQLSTATE 22023 with the message '
'"uxid: <name>: <detail>" for the first refusal that applies: '
'invalid_argument for an unknown size or letter_case, an empty delimiter, '
'a negative rand_size, a time_ms outside 0 to 2^48 - 1 or a monotonic '
'request with no random field; rand_with_from, from_with_monotonic, '
'rand_size_too_large, rand_with_monotonic, rand_width_mismatch and '
'compact_time_out_of_range as the wire format names them. Returns nothing '
'for a request it accepts. A NULL prefix, size, letter_case, delimiter or '
'monotonic takes the default; a NULL compact is the size''s default.';

CREATE FUNCTION uxid_encode(
    prefix text,
    size text,
    time_ms bigint,
    rand bytea,
    compact boolean DEFAULT FALSE,
    letter_case text DEFAULT 'lower',
    delimiter text DEFAULT '_',
    rand_size integer DEFAULT NULL
)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        uxid_check_request(
            prefix => prefix,
            size => size,
            compact => compact,
            rand_size => rand_size,
            letter_case => letter_case,
            delimiter => delimiter,
            time_ms => time_ms,
            rand => rand
        );
    SELECT
        CASE
            WHEN time_ms IS NULL
                THEN
                    uxid__raise(
                        'invalid_argument', 'uxid_encode needs a time_ms'
                    )
            WHEN rand IS NULL
                THEN
                    uxid__raise(
                        'invalid_argument',
                        'uxid_encode needs the random field''s bytes in rand'
                    )
        END;
    SELECT
        id.head
        || CASE
            WHEN id.letter_case = 'upper'
                THEN
                    translate(
                        id.body,
                        'abcdefghjkmnpqrstvwxyz',
                        'ABCDEFGHJKMNPQRSTVWXYZ'
                    )
            ELSE id.body
        END
    FROM
        (
            SELECT
                letter_case,
                coalesce(
                    nullif(prefix, '') || coalesce(delimiter, '_'), ''
                ) AS head,
                uxid__base32_time(time_ms, coalesce(compact, FALSE))
                || uxid__base32_bytes(rand) AS body
        ) AS id;
END;

COMMENT ON FUNCTION uxid_encode(
    text, text, bigint, bytea, boolean, text, text, integer
) IS
'Builds the time-based id the wire format defines from a fixed time_ms and '
'fixed random bytes: the pure encoder, for test vectors such as the '
'conformance corpus, never a source of random ids. rand must be the '
'random field''s width for the request. Refuses as uxid_check_request '
'does, and with invalid_argument for a NULL time_ms or rand.';

CREATE FUNCTION uxid_generate(
    prefix text DEFAULT NULL,
    size text DEFAULT 'xl',
    compact boolean DEFAULT FALSE,
    rand_size integer DEFAULT NULL,
    letter_case text DEFAULT 'lower',
    delimiter text DEFAULT '_',
    time_ms bigint DEFAULT NULL
)
RETURNS text
LANGUAGE sql
VOLATILE PARALLEL SAFE
BEGIN ATOMIC
    -- The width drawn is held to 0 to 10 bytes; a request whose width
    -- falls outside that is refused by uxid_encode's check, and the bytes
    -- drawn for it are never used.
    SELECT
        uxid_encode(
            req.prefix,
            req.size,
            req.ms,
            uxid__random_bytes(least(greatest(req.width, 0), 10)),
            req.compact,
            req.letter_case,
            req.delimiter,
            req.rand_size
        )
    FROM
        (
            SELECT
                prefix,
                size,
                compact,
                rand_size,
                letter_case,
                delimiter,
                coalesce(
                    time_ms,
                    floor(extract(EPOCH FROM clock_timestamp()) * 1000)::bigint
                ) AS ms,
                coalesce(
                    uxid__rand_width(size, compact, rand_size, FALSE), 0
                ) AS width
        ) AS req;
END;

COMMENT ON FUNCTION uxid_generate(
    text, text, boolean, integer, text, text, bigint
) IS
'Generates a time-based id: time_ms, or the current time from '
'clock_timestamp() when it is NULL, and a random field drawn from the '
'fully random bytes of uuid_send(gen_random_uuid()). Defaults: size xl, '
'standard time, lower case, delimiter _, no prefix (NULL and the empty '
'string are both no prefix). Refuses as uxid_check_request does.';
