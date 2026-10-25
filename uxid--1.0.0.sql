-- uxid 1.0.0: prefixed, K-sortable, human-readable identifiers.
--
-- This script carries no psql guard line, so the same file serves
-- CREATE EXTENSION uxid and a plain migration run once with psql -f.
--
-- Every function that calls another function of this extension is
-- LANGUAGE sql with a BEGIN ATOMIC body, which binds its callees when it
-- is created, so the extension works with its schema off the caller's
-- search_path, after ALTER EXTENSION uxid SET SCHEMA, and under the empty
-- search_path a dump restore uses. The two PL/pgSQL functions, the
-- raise helpers uxid__raise and uxid__raise_decode, call nothing. A
-- function is created after every function it calls.
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
-- wrong width, a monotonic xs with an explicit standard time, a
-- monotonic request with no random field, and a compact time whose first
-- character would be the deterministic marker. The
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
            WHEN req.monotonic AND req.short_size = 'xs' AND NOT req.compact
                THEN
                    uxid__raise(
                        'invalid_argument',
                        'a monotonic xs uses compact time, so its random '
                        'field has a byte to step; compact must be NULL or '
                        'true'
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
                compact,
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
'a negative rand_size, a time_ms outside 0 to 2^48 - 1, a monotonic xs '
'with compact false (a monotonic xs always uses compact time) or a '
'monotonic request with no random field; rand_with_from, '
'from_with_monotonic, '
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

-- The deterministic id of a key: the same prefix, key and size always give
-- the same id. The hash input is the prefix, a zero byte, the key, a zero
-- byte and one byte holding the number of hash characters (xs 9, s 13,
-- m 17, l 21, xl 25), all hashed with SHA-256; the body is the marker z
-- and the first that many characters of the digest's base32. A NULL
-- prefix and the empty string are both no prefix. The prefix and the key
-- reach sha256 as their UTF-8 bytes whatever the database encoding
-- (convert_to(..., 'UTF8')), so the same text gives the same id in every
-- database; in a SQL_ASCII database, which has no conversion to UTF-8,
-- the stored bytes are hashed as they are. A database's encoding never
-- changes, so the function is immutable. The request is checked first,
-- so a refusal does not depend on the key; then a NULL key gives NULL.
-- The letter case changes the body only, never the prefix.
CREATE FUNCTION uxid_from(
    prefix text,
    key text,
    size text DEFAULT 'xl',
    letter_case text DEFAULT 'lower',
    delimiter text DEFAULT '_'
)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        uxid_check_request(
            prefix => prefix,
            size => size,
            letter_case => letter_case,
            delimiter => delimiter,
            from_key => key
        );
    SELECT
        CASE
            WHEN id.no_key THEN NULL
            ELSE
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
        END
    FROM
        (
            SELECT
                req.letter_case,
                req.no_key,
                req.head,
                'z'
                || left(
                    uxid__base32_bytes(
                        sha256(
                            req.hashed_head
                            || set_byte('\x00'::bytea, 0, req.chars)
                        )
                    ),
                    req.chars
                ) AS body
            FROM
                (
                    SELECT
                        letter_case,
                        key IS NULL AS no_key,
                        coalesce(
                            nullif(prefix, '') || coalesce(delimiter, '_'),
                            ''
                        ) AS head,
                        convert_to(coalesce(prefix, ''), 'UTF8')
                        || '\x00'::bytea
                        || convert_to(key, 'UTF8')
                        || '\x00'::bytea AS hashed_head,
                        CASE uxid__size(size)
                            WHEN 'xs' THEN 9
                            WHEN 's' THEN 13
                            WHEN 'm' THEN 17
                            WHEN 'l' THEN 21
                            WHEN 'xl' THEN 25
                        END AS chars
                ) AS req
        ) AS id;
END;

COMMENT ON FUNCTION uxid_from(text, text, text, text, text) IS
'Builds the deterministic id of a key: SHA-256 of the prefix, a zero byte, '
'the key, a zero byte and one byte holding the hash character count, '
'behind the marker z (xs 9, s 13, m 17, l 21, xl 25 hash characters). The '
'prefix and the key are hashed as UTF-8 bytes whatever the database '
'encoding (in a SQL_ASCII database, which has no conversion to UTF-8, the '
'stored bytes are hashed as they are), so the id does not depend on it. '
'A deterministic id has no compact form, time or random field. A NULL '
'key gives NULL; a NULL prefix and the empty string are both no prefix; '
'lower case is the default and upper case changes the body only. Refuses '
'as uxid_check_request does, before the key is read. Defaults: size xl, '
'lower case, delimiter _.';

-- Raises a decode refusal: SQLSTATE 22P02 (invalid_text_representation)
-- with the message "uxid: <reason>", the reason empty, invalid_length or
-- invalid_character. VOLATILE for the reason uxid__raise is.
CREATE FUNCTION uxid__raise_decode(reason text)
RETURNS void
LANGUAGE plpgsql
VOLATILE PARALLEL SAFE
AS $raise_decode$
BEGIN
    RAISE EXCEPTION USING
        ERRCODE = 'invalid_text_representation',
        MESSAGE = 'uxid: ' || reason;
END;
$raise_decode$;

COMMENT ON FUNCTION uxid__raise_decode(text) IS
'Internal helper of the uxid extension, not part of its public surface: '
'raises SQLSTATE 22P02 with the message "uxid: <reason>".';

-- The splits below scan the id left to right for the delimiter, matches
-- not overlapping, as the reference's String.split does: the body is the
-- part after the last match, the prefix the parts before it joined by
-- the delimiter. A NULL delimiter is the default _. The text operations
-- that read a collation name COLLATE "C", so the result never depends on
-- the collation of the arguments (a uxid value carries "C", a literal
-- the database's); the marker is read by its code point (ascii), which
-- reads no collation.

-- The body of an id: everything after the last delimiter, the whole
-- string when it has none, and NULL for a NULL id.
CREATE FUNCTION uxid__body(id text, delimiter text)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        CASE
            WHEN part.parts IS NULL THEN NULL
            ELSE coalesce(part.parts[cardinality(part.parts)], '')
        END AS body
    FROM
        (
            SELECT
                string_to_array(
                    id COLLATE "C", coalesce(delimiter, '_') COLLATE "C"
                ) AS parts
        ) AS part;
END;

COMMENT ON FUNCTION uxid__body(text, text) IS
'Internal helper of the uxid extension, not part of its public surface: '
'the body of an id, everything after the last delimiter (the whole '
'string when there is none).';

-- The prefix of an id: everything before the last delimiter, the empty
-- string for an id that starts with it, and NULL for an id with no
-- delimiter or a NULL id.
CREATE FUNCTION uxid__prefix(id text, delimiter text)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        CASE
            WHEN cardinality(part.parts) > 1
                THEN
                    array_to_string(
                        part.parts[1:cardinality(part.parts) - 1],
                        part.joiner
                    )
        END AS prefix_part
    FROM
        (
            SELECT
                coalesce(delimiter, '_') AS joiner,
                string_to_array(
                    id COLLATE "C", coalesce(delimiter, '_') COLLATE "C"
                ) AS parts
        ) AS part;
END;

COMMENT ON FUNCTION uxid__prefix(text, text) IS
'Internal helper of the uxid extension, not part of its public surface: '
'the prefix of an id, everything before the last delimiter; NULL when '
'there is no delimiter.';

-- The first rule a body breaks, checked in the order the wire format's
-- Refusals section states (empty, invalid_length, invalid_character), or
-- NULL for a well-formed body and for NULL. The length is the body's
-- UTF-8 byte count whatever the database encoding (in a SQL_ASCII
-- database, the stored bytes), and the table is the wire format's
-- length table: 10, 13, 14, 18, 21, 22, 24 and 26.
CREATE FUNCTION uxid__body_error(body text)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        CASE
            WHEN octet_length(body) = 0 THEN 'empty'
            WHEN
                octet_length(convert_to(body, 'UTF8'))
                NOT IN (10, 13, 14, 18, 21, 22, 24, 26)
                THEN 'invalid_length'
            WHEN
                body COLLATE "C"
                !~ '^[0123456789ABCDEFGHJKMNPQRSTVWXYZabcdefghjkmnpqrstvwxyz]+$'
                THEN 'invalid_character'
        END;
END;

COMMENT ON FUNCTION uxid__body_error(text) IS
'Internal helper of the uxid extension, not part of its public surface: '
'the first rule a body breaks (empty, invalid_length, invalid_character, '
'in that order) or NULL for a well-formed body.';

-- The integer a run of base32 characters of either case spells, most
-- significant character first, 5 bits each. Read only from a checked
-- body, at most 10 characters (50 bits).
CREATE FUNCTION uxid__base32_value(chars text)
RETURNS bigint
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        coalesce(
            bit_or(
                (strpos(lc.alphabet, substr(lc.symbols, g.i, 1)) - 1)::bigint
                << (5 * (length(lc.symbols) - g.i))
            ),
            0
        ) AS symbol_value
    FROM
        (
            SELECT
                '0123456789abcdefghjkmnpqrstvwxyz' COLLATE "C" AS alphabet,
                translate(
                    chars,
                    'ABCDEFGHJKMNPQRSTVWXYZ',
                    'abcdefghjkmnpqrstvwxyz'
                ) COLLATE "C" AS symbols
        ) AS lc
    CROSS JOIN LATERAL generate_series(1, length(lc.symbols)) AS g (i);
END;

COMMENT ON FUNCTION uxid__base32_value(text) IS
'Internal helper of the uxid extension, not part of its public surface: '
'the integer a run of base32 characters of either case spells, most '
'significant first.';

-- The full time of a compact time field (its low 40 bits) against a
-- clock, as the wire format's "Decoding the time" states: the clock's
-- bits above bit 40 with the 40 decoded bits, less 2^40 when that is
-- more than one day (86400000 ms) ahead of the clock. There is no clamp
-- at zero: a clock in the first 2^40 ms window can give a negative time.
CREATE FUNCTION uxid__compact_time(low_ms bigint, clock_ms bigint)
RETURNS bigint
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        CASE
            WHEN t.full_ms - t.clock > 86400000
                THEN t.full_ms - 1099511627776
            ELSE t.full_ms
        END AS decoded_ms
    FROM
        (
            SELECT
                clock_ms AS clock,
                (clock_ms & ~1099511627775::bigint) | low_ms AS full_ms
        ) AS t;
END;

COMMENT ON FUNCTION uxid__compact_time(bigint, bigint) IS
'Internal helper of the uxid extension, not part of its public surface: '
'the full time of a compact time field against a clock, one 2^40 ms '
'window back when it would be more than a day ahead of the clock.';

-- The pure decoder. Refuses an empty delimiter with invalid_argument
-- (22023); then a malformed body with 22P02 and its reason, in the order
-- empty, invalid_length, invalid_character; then a compact time body
-- with a NULL clock or one outside 0 to 2^48 - 1, with invalid_argument.
-- The size and time form come from the body length alone (10 and 18 read
-- as standard, so a compact xs or m id decodes with a wrong time, as the
-- wire format says). A body starting with z or Z is deterministic and
-- has no time; its compact flag is the length table's, as the reference
-- reports it. A standard time is the first 10 characters' low 48 bits.
CREATE FUNCTION uxid_decode_at(
    id text,
    clock_ms bigint,
    delimiter text DEFAULT '_'
)
RETURNS TABLE (
    prefix text,
    size text,
    compact boolean,
    deterministic boolean,
    time_ms bigint
)
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        CASE
            WHEN octet_length(delimiter) = 0
                THEN
                    uxid__raise(
                        'invalid_argument', 'delimiter must not be empty'
                    )
        END;
    SELECT
        CASE
            WHEN chk.reason IS NOT NULL THEN uxid__raise_decode(chk.reason)
        END
    FROM
        (
            SELECT uxid__body_error(uxid__body(id, delimiter)) AS reason
        ) AS chk;
    SELECT
        CASE
            WHEN
                b.needs_clock
                AND (
                    b.clock IS NULL
                    OR b.clock < 0
                    OR b.clock > 281474976710655
                )
                THEN
                    uxid__raise(
                        'invalid_argument',
                        format(
                            'a compact time needs a clock_ms from 0 to '
                            '281474976710655; got %s',
                            coalesce(b.clock::text, 'NULL')
                        )
                    )
        END
    FROM
        (
            SELECT
                clock_ms AS clock,
                octet_length(uxid__body(id, delimiter)) IN (13, 21, 24)
                AND ascii(uxid__body(id, delimiter)) NOT IN (90, 122)
                    AS needs_clock
        ) AS b;
    SELECT
        r.id_prefix,
        r.id_size,
        r.is_compact,
        r.is_deterministic,
        r.id_time_ms
    FROM
        (
            SELECT
                d.is_compact,
                d.marker AS is_deterministic,
                CASE WHEN d.body IS NOT NULL THEN d.body_prefix END
                    AS id_prefix,
                CASE octet_length(d.body)
                    WHEN 10 THEN 'xs'
                    WHEN 13 THEN 's'
                    WHEN 14 THEN 's'
                    WHEN 18 THEN 'm'
                    WHEN 21 THEN 'l'
                    WHEN 22 THEN 'l'
                    WHEN 24 THEN 'xl'
                    WHEN 26 THEN 'xl'
                END AS id_size,
                CASE
                    WHEN d.body IS NULL OR d.marker THEN NULL
                    WHEN d.is_compact
                        THEN
                            uxid__compact_time(
                                uxid__base32_value(left(d.body, 8)), d.clock
                            )
                    ELSE
                        uxid__base32_value(left(d.body, 10))
                        & 281474976710655
                END AS id_time_ms
            FROM
                (
                    SELECT
                        b.body,
                        b.body_prefix,
                        b.clock,
                        octet_length(b.body) IN (13, 21, 24) AS is_compact,
                        ascii(b.body) IN (90, 122) AS marker
                    FROM
                        (
                            SELECT
                                clock_ms AS clock,
                                uxid__body(id, delimiter) AS body,
                                uxid__prefix(id, delimiter) AS body_prefix
                        ) AS b
                ) AS d
        ) AS r;
END;

COMMENT ON FUNCTION uxid_decode_at(text, bigint, text) IS
'Decodes an id against the clock clock_ms (ms since the Unix epoch), the '
'pure decoder: one row of the prefix (NULL for none, the empty string '
'for an id that starts with the delimiter), the size (xs, s, m, l or '
'xl), whether the time is compact, whether the body is deterministic, '
'and the time in ms (NULL for a deterministic body). The body is '
'everything after the last delimiter. A compact time takes its high bits '
'from the clock and steps back one 2^40 ms window when it would be more '
'than a day ahead of it, with no clamp at zero. A malformed body raises '
'SQLSTATE 22P02 with the message "uxid: empty", "uxid: invalid_length" '
'or "uxid: invalid_character", checked in that order; an empty '
'delimiter, or a compact time with a NULL clock or one outside 0 to '
'2^48 - 1, raises 22023 with invalid_argument. A NULL id gives one row '
'of NULLs; a NULL delimiter is _.';

CREATE FUNCTION uxid_decode(
    id text,
    clock_ms bigint DEFAULT NULL,
    delimiter text DEFAULT '_'
)
RETURNS TABLE (
    prefix text,
    size text,
    compact boolean,
    deterministic boolean,
    time_ms bigint
)
LANGUAGE sql
STABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        d.prefix,
        d.size,
        d.compact,
        d.deterministic,
        d.time_ms
    FROM
        (
            SELECT
                id AS given_id,
                delimiter AS given_delimiter,
                coalesce(
                    clock_ms,
                    floor(extract(EPOCH FROM now()) * 1000)::bigint
                ) AS clock
        ) AS a
    CROSS JOIN
        LATERAL uxid_decode_at(a.given_id, a.clock, a.given_delimiter) AS d;
END;

COMMENT ON FUNCTION uxid_decode(text, bigint, text) IS
'Decodes an id as uxid_decode_at does, against clock_ms or, when it is '
'NULL, the transaction time in ms (now()). Returns one row of the '
'prefix, size, compact flag, deterministic flag and time (NULL for a '
'deterministic body); raises SQLSTATE 22P02 with "uxid: empty", '
'"uxid: invalid_length" or "uxid: invalid_character" for a malformed '
'body. Defaults: delimiter _.';

CREATE FUNCTION uxid_decode_error(id text, delimiter text DEFAULT '_')
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        CASE
            WHEN id IS NULL THEN NULL
            WHEN octet_length(delimiter) = 0 THEN 'invalid_argument'
            ELSE uxid__body_error(uxid__body(id, delimiter))
        END;
END;

COMMENT ON FUNCTION uxid_decode_error(text, text) IS
'The reason uxid_decode refuses an id (empty, invalid_length or '
'invalid_character, the first that applies in that order), or NULL when '
'the body is well formed; invalid_argument for an empty delimiter. Never '
'raises and reads no clock. A NULL id gives NULL; a NULL delimiter is _.';

-- The validity checks read no clock: a well-formed body (the length
-- table and the alphabet) is all they ask, which is stricter than the
-- reference's valid?, whose body check takes any length from 10 up.
CREATE FUNCTION uxid_is_valid(
    id text,
    delimiter text DEFAULT '_',
    required_prefix text DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        CASE
            WHEN id IS NULL THEN NULL
            WHEN octet_length(delimiter) = 0 THEN FALSE
            WHEN uxid__body_error(uxid__body(id, delimiter)) IS NOT NULL
                THEN FALSE
            WHEN coalesce(octet_length(required_prefix), 0) = 0 THEN TRUE
            ELSE
                coalesce(
                    uxid__prefix(id, delimiter) COLLATE "C"
                    = required_prefix COLLATE "C",
                    FALSE
                )
        END;
END;

COMMENT ON FUNCTION uxid_is_valid(text, text, text) IS
'Whether an id decodes: its body (everything after the last delimiter) '
'is well formed, every character in the alphabet of either case and its '
'length in the wire format''s length table, which is stricter than the '
'reference''s check of any length from 10 up. With a required_prefix '
'(NULL or the empty string is none), the id''s prefix must also equal it. '
'Reads no clock. False for an empty delimiter; NULL for a NULL id, so a '
'NULL passes the uxid domain''s check. A NULL delimiter is _.';

CREATE FUNCTION uxid_is_deterministic(id text, delimiter text DEFAULT '_')
RETURNS boolean
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        CASE
            WHEN id IS NULL THEN NULL
            WHEN octet_length(delimiter) = 0 THEN FALSE
            WHEN uxid__body_error(uxid__body(id, delimiter)) IS NOT NULL
                THEN FALSE
            ELSE ascii(uxid__body(id, delimiter)) IN (90, 122)
        END;
END;

COMMENT ON FUNCTION uxid_is_deterministic(text, text) IS
'Whether an id is a well-formed deterministic id: its body decodes (as '
'uxid_is_valid asks) and starts with the marker z or Z. Stricter than '
'the reference''s check, which reads the first body character alone. '
'Reads no clock. False for an empty delimiter; NULL for a NULL id. A NULL '
'delimiter is _.';

-- The uxid type: text that must decode. COLLATE "C" compares bytes, and
-- the alphabet is in ASCII order, so lower-case (or upper-case) ids of
-- one prefix and size sort by time, then random field; a linguistic
-- collation may skip the delimiter or fold case and break that order.
-- The check calls a bound function, so it holds under a dump restore's
-- empty search_path and after ALTER EXTENSION uxid SET SCHEMA.
CREATE DOMAIN uxid AS text COLLATE "C" CHECK (uxid_is_valid(value));

COMMENT ON DOMAIN uxid IS
'A uxid id stored as text with COLLATE "C": a value must pass '
'uxid_is_valid with the default delimiter _, and ids of one prefix, size '
'and letter case sort by time. Every uxid function takes and returns '
'plain text, so a text column works unchanged.';

-- Monotonic generation (the wire format's "Monotonic generation"). The
-- random field of width w bytes is read as one big-endian unsigned
-- integer below 2^(8w), held as numeric because an xl field is 80 bits;
-- every conversion between it and the field's bytes is exact.

-- The unsigned big-endian integer of up to 10 bytes, as numeric: the
-- high 5 bytes times 2^40 plus the low 5 bytes. The empty field is 0.
CREATE FUNCTION uxid__bytes_numeric(field bytea)
RETURNS numeric
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        ('x' || substr(h.hex, 1, 10))::bit(40)::bigint::numeric
        * 1099511627776
        + ('x' || substr(h.hex, 11, 10))::bit(40)::bigint AS field_value
    FROM (SELECT lpad(encode(field, 'hex'), 20, '0') AS hex) AS h;
END;

COMMENT ON FUNCTION uxid__bytes_numeric(bytea) IS
'Internal helper of the uxid extension, not part of its public surface: '
'up to 10 bytes read as one big-endian unsigned integer, exactly.';

-- The width bytes, big-endian, of an integer from 0 to 2^(8 x width) - 1
-- (width 0 to 10): the inverse of uxid__bytes_numeric.
CREATE FUNCTION uxid__numeric_bytes(field_value numeric, width integer)
RETURNS bytea
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        decode(
            right(
                lpad(to_hex(div(field_value, 1099511627776)::bigint), 10, '0')
                || lpad(
                    to_hex(mod(field_value, 1099511627776)::bigint), 10, '0'
                ),
                2 * width
            ),
            'hex'
        );
END;

COMMENT ON FUNCTION uxid__numeric_bytes(numeric, integer) IS
'Internal helper of the uxid extension, not part of its public surface: '
'the width bytes, big-endian, of an integer below 2^(8 x width).';

-- The three draws of one monotonic call, cut from 25 random bytes for a
-- field of width bytes (1 to 10): the seed is bytes 1 to width, the step
-- is the low 4 x width bits of the ceil(width / 2) bytes from byte 11,
-- plus one, so it is uniform from 1 to 2^(4 x width) with no modulo bias,
-- and the overflow seed is width bytes from byte 16.
CREATE FUNCTION uxid__monotonic_draws(draws bytea, width integer)
RETURNS TABLE (seed numeric, step bigint, overflow_seed numeric)
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        uxid__bytes_numeric(substring(draws FROM 1 FOR width)) AS seed_value,
        (
            uxid__bytes_numeric(
                substring(draws FROM 11 FOR (width + 1) / 2)
            )::bigint
            & ((1::bigint << (4 * width)) - 1)
        ) + 1 AS step_value,
        uxid__bytes_numeric(substring(draws FROM 16 FOR width))
            AS overflow_value;
END;

COMMENT ON FUNCTION uxid__monotonic_draws(bytea, integer) IS
'Internal helper of the uxid extension, not part of its public surface: '
'the seed, step and overflow seed of one monotonic call cut from 25 '
'random bytes; the step is the low 4 x width bits of ceil(width / 2) '
'bytes plus one.';

-- Which of the wire format's three rules applies: seed (rule 1, no state
-- or a clock later than the last time), step (rule 2, the last value
-- plus the step fits the field) or step_overflow (rule 3, it does not).
-- A missing step reads as step, so the caller can refuse it by name.
CREATE FUNCTION uxid__monotonic_rule(
    last_time_ms bigint,
    last_rand numeric,
    now_ms bigint,
    rand_width integer,
    step bigint
)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        CASE
            WHEN last_time_ms IS NULL OR now_ms > last_time_ms THEN 'seed'
            WHEN step IS NULL THEN 'step'
            WHEN
                last_rand + step
                <= uxid__bytes_numeric(decode(repeat('ff', rand_width), 'hex'))
                THEN 'step'
            ELSE 'step_overflow'
        END;
END;

COMMENT ON FUNCTION uxid__monotonic_rule(
    bigint, numeric, bigint, integer, bigint
) IS
'Internal helper of the uxid extension, not part of its public surface: '
'which monotonic rule applies (seed, step or step_overflow).';

-- The pure step of the monotonic generator, the function the corpus
-- drives with its draws. Refuses with invalid_argument a width outside 1
-- to 10, a NULL now_ms, a last time without a last value (or the other
-- way round), a last value, seed or overflow seed that is not an integer
-- from 0 to 2^(8w) - 1, a step outside 1 to 2^(4w), and a NULL draw that
-- the rule taken needs. A draw the rule does not take may be NULL.
CREATE FUNCTION uxid_monotonic_step(
    last_time_ms bigint,
    last_rand numeric,
    now_ms bigint,
    rand_width integer,
    seed numeric,
    step bigint,
    overflow_seed numeric
)
RETURNS TABLE (time_ms bigint, rand numeric, drew text)
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT
        CASE
            WHEN a.width IS NULL OR a.width < 1 OR a.width > 10
                THEN
                    uxid__raise(
                        'invalid_argument',
                        format(
                            'rand_width must be from 1 to 10; got %s',
                            coalesce(a.width::text, 'NULL')
                        )
                    )
            WHEN a.clock IS NULL
                THEN
                    uxid__raise(
                        'invalid_argument', 'the monotonic step needs a now_ms'
                    )
            WHEN (a.last_time IS NULL) <> (a.last_value IS NULL)
                THEN
                    uxid__raise(
                        'invalid_argument',
                        'last_time_ms and last_rand are both given or both NULL'
                    )
            WHEN
                a.last_value < 0
                OR a.last_value > a.field_max
                OR a.last_value <> trunc(a.last_value)
                THEN
                    uxid__raise(
                        'invalid_argument',
                        format(
                            'last_rand must be an integer from 0 to %s; got %s',
                            a.field_max,
                            a.last_value
                        )
                    )
            WHEN
                a.seed_value < 0
                OR a.seed_value > a.field_max
                OR a.seed_value <> trunc(a.seed_value)
                THEN
                    uxid__raise(
                        'invalid_argument',
                        format(
                            'seed must be an integer from 0 to %s; got %s',
                            a.field_max,
                            a.seed_value
                        )
                    )
            WHEN a.step_value < 1 OR a.step_value > a.step_max
                THEN
                    uxid__raise(
                        'invalid_argument',
                        format(
                            'step must be from 1 to %s; got %s',
                            a.step_max,
                            a.step_value
                        )
                    )
            WHEN
                a.overflow_value < 0
                OR a.overflow_value > a.field_max
                OR a.overflow_value <> trunc(a.overflow_value)
                THEN
                    uxid__raise(
                        'invalid_argument',
                        format(
                            'overflow_seed must be an integer from 0 to %s; '
                            'got %s',
                            a.field_max,
                            a.overflow_value
                        )
                    )
        END
    FROM
        (
            SELECT
                rand_width AS width,
                now_ms AS clock,
                last_time_ms AS last_time,
                last_rand AS last_value,
                seed AS seed_value,
                step AS step_value,
                overflow_seed AS overflow_value,
                uxid__bytes_numeric(
                    decode(
                        repeat('ff', least(greatest(rand_width, 0), 10)), 'hex'
                    )
                ) AS field_max,
                1::bigint << (4 * least(greatest(rand_width, 0), 10))
                    AS step_max
        ) AS a;
    SELECT
        CASE
            WHEN a.chosen = 'seed' AND a.seed_value IS NULL
                THEN
                    uxid__raise(
                        'invalid_argument',
                        'a fresh value is drawn here, and seed is NULL'
                    )
            WHEN a.chosen = 'step' AND a.step_value IS NULL
                THEN
                    uxid__raise(
                        'invalid_argument',
                        'the last value is stepped here, and step is NULL'
                    )
            WHEN a.chosen = 'step_overflow' AND a.overflow_value IS NULL
                THEN
                    uxid__raise(
                        'invalid_argument',
                        'the step overflows the field here, and overflow_seed '
                        'is NULL'
                    )
        END
    FROM
        (
            SELECT
                seed AS seed_value,
                step AS step_value,
                overflow_seed AS overflow_value,
                uxid__monotonic_rule(
                    last_time_ms, last_rand, now_ms, rand_width, step
                ) AS chosen
        ) AS a;
    SELECT
        n.next_time_ms,
        n.next_rand,
        n.drew_rule
    FROM
        (
            SELECT
                a.chosen AS drew_rule,
                CASE a.chosen
                    WHEN 'seed' THEN a.clock
                    WHEN 'step' THEN a.last_time
                    ELSE a.last_time + 1
                END AS next_time_ms,
                CASE a.chosen
                    WHEN 'seed' THEN a.seed_value
                    WHEN 'step' THEN a.last_value + a.step_value
                    ELSE a.overflow_value
                END AS next_rand
            FROM
                (
                    SELECT
                        now_ms AS clock,
                        last_time_ms AS last_time,
                        last_rand AS last_value,
                        seed AS seed_value,
                        step AS step_value,
                        overflow_seed AS overflow_value,
                        uxid__monotonic_rule(
                            last_time_ms, last_rand, now_ms, rand_width, step
                        ) AS chosen
                ) AS a
        ) AS n;
END;

COMMENT ON FUNCTION uxid_monotonic_step(
    bigint, numeric, bigint, integer, numeric, bigint, numeric
) IS
'The pure step of the monotonic generator, by the wire format''s three '
'rules, for a random field of rand_width bytes (1 to 10) read as one '
'big-endian unsigned integer: with no state (last_time_ms and last_rand '
'NULL) or now_ms later than last_time_ms, now_ms and the fresh seed '
'(drew seed); otherwise last_time_ms and last_rand + step (drew step); '
'and when that reaches 2^(8 x rand_width), last_time_ms + 1 and the '
'fresh overflow_seed (drew step_overflow). Returns one row of time_ms, '
'rand and drew. A draw the rule does not take may be NULL; a NULL draw '
'it takes, or a value outside its range (a seed or last value from 0 '
'to 2^(8 x rand_width) - 1, a step from 1 to 2^(4 x rand_width)), is '
'refused with SQLSTATE 22023 and invalid_argument.';

-- The monotonic generator. Its state is one session setting per prefix
-- and random width, uxid.mono_<the prefix's UTF-8 bytes in hex>_<width>
-- (no prefix is the empty hex, so NULL and the empty string share it),
-- holding "<time_ms>:<rand>" in decimal, read with current_setting(name,
-- true) and written with set_config(name, value, false). The first
-- statement refuses the request before anything is read, drawn or
-- written; it checks the given time_ms against the time range only (an
-- in-range time is passed to the check as 0), because the id may carry
-- the last id's time rather than the clock's, and the compact guard
-- applies to the time the id carries. The second reads the state, draws
-- two UUIDs' worth of random bytes, takes the step, encodes the id
-- (uxid_encode checks the time the id carries, the compact guard
-- included) and writes the new state with a value computed from that
-- id, so the encoder has accepted the id before the state is written. A
-- setting written in a statement that fails is undone with it, so a
-- refused call leaves the state as it was.
CREATE FUNCTION uxid_monotonic(
    prefix text DEFAULT NULL,
    size text DEFAULT 'xl',
    compact boolean DEFAULT NULL,
    rand_size integer DEFAULT NULL,
    letter_case text DEFAULT 'lower',
    delimiter text DEFAULT '_',
    time_ms bigint DEFAULT NULL
)
RETURNS text
LANGUAGE sql
VOLATILE PARALLEL UNSAFE
BEGIN ATOMIC
    SELECT
        uxid_check_request(
            prefix => prefix,
            size => size,
            compact => compact,
            rand_size => rand_size,
            letter_case => letter_case,
            delimiter => delimiter,
            time_ms => CASE
                WHEN time_ms BETWEEN 0 AND 281474976710655 THEN 0
                ELSE time_ms
            END,
            monotonic => TRUE
        );
    SELECT
        CASE
            WHEN
                set_config(
                    emitted.setting_name,
                    CASE
                        WHEN emitted.id IS NOT NULL
                            THEN
                                emitted.next_time_ms::text
                                || ':'
                                || emitted.next_rand::text
                    END,
                    FALSE
                ) IS NOT NULL
                THEN emitted.id
        END
    FROM
        (
            SELECT
                req.setting_name,
                st.time_ms AS next_time_ms,
                st.rand AS next_rand,
                uxid_encode(
                    req.given_prefix,
                    req.given_size,
                    st.time_ms,
                    uxid__numeric_bytes(st.rand, req.width),
                    req.is_compact,
                    req.given_case,
                    req.given_delimiter,
                    req.given_rand_size
                ) AS id
            FROM
                (
                    SELECT
                        state.given_prefix,
                        state.given_size,
                        state.given_case,
                        state.given_delimiter,
                        state.given_rand_size,
                        state.width,
                        state.is_compact,
                        state.now_ms,
                        state.setting_name,
                        nullif(split_part(state.saved, ':', 1), '')::bigint
                            AS last_time_ms,
                        nullif(split_part(state.saved, ':', 2), '')::numeric
                            AS last_rand,
                        uxid__random_bytes(25) AS draws
                    FROM
                        (
                            SELECT
                                form.given_prefix,
                                form.given_size,
                                form.given_case,
                                form.given_delimiter,
                                form.given_rand_size,
                                form.width,
                                form.is_compact,
                                form.now_ms,
                                form.setting_name,
                                current_setting(form.setting_name, TRUE)
                                    AS saved
                            FROM
                                (
                                    SELECT
                                        prefix AS given_prefix,
                                        size AS given_size,
                                        letter_case AS given_case,
                                        delimiter AS given_delimiter,
                                        rand_size AS given_rand_size,
                                        uxid__rand_width(
                                            size, compact, rand_size, TRUE
                                        ) AS width,
                                        uxid__compact(size, compact, TRUE)
                                            AS is_compact,
                                        coalesce(
                                            time_ms,
                                            floor(
                                                extract(
                                                    EPOCH FROM clock_timestamp()
                                                ) * 1000
                                            )::bigint
                                        ) AS now_ms,
                                        'uxid.mono_'
                                        || encode(
                                            convert_to(
                                                coalesce(prefix, ''), 'UTF8'
                                            ),
                                            'hex'
                                        )
                                        || '_'
                                        || uxid__rand_width(
                                            size, compact, rand_size, TRUE
                                        ) AS setting_name
                                ) AS form
                        ) AS state
                ) AS req
            CROSS JOIN LATERAL uxid__monotonic_draws(req.draws, req.width) AS d
            CROSS JOIN
                LATERAL uxid_monotonic_step(
                    req.last_time_ms,
                    req.last_rand,
                    req.now_ms,
                    req.width,
                    d.seed,
                    d.step,
                    d.overflow_seed
                ) AS st
        ) AS emitted;
END;

COMMENT ON FUNCTION uxid_monotonic(
    text, text, boolean, integer, text, text, bigint
) IS
'Generates a time-based id that sorts after the last one this session '
'generated for the same prefix and random width, by the wire format''s '
'monotonic rules: a fresh random field when the time (time_ms, or the '
'clock_timestamp() time when it is NULL) is later than the last id''s, '
'otherwise the last id''s time and its random field plus a step drawn '
'uniformly from 1 to 2^(4 x width), and the next millisecond with a fresh '
'field when the step overflows. The random bytes come from two '
'uuid_send(gen_random_uuid()) calls. The state is a session setting, '
'uxid.mono_<hex of the prefix''s UTF-8 bytes>_<width>, so the order holds '
'within one session only, never across sessions, connections or the '
'backends behind a pooler; the setting is transactional, so a '
'transaction that aborts (or a savepoint rolled back) restores the state '
'it found and ids returned inside it may repeat in the same session; '
'RESET ALL and DISCARD ALL clear it. A refused call raises and leaves the '
'state as it was. An xs always uses compact time: compact NULL is the '
'size''s default (compact for xs, standard otherwise) and an explicit '
'compact false at xs is refused with invalid_argument. Refuses as '
'uxid_check_request does with monotonic true. Defaults: size xl, lower '
'case, delimiter _, no prefix (NULL and the empty string share one '
'state). Volatile and parallel unsafe.';
