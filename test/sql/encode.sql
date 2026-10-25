-- uxid_encode, the pure encoder: a fixed time and fixed random bytes give
-- the id the wire format defines.

-- A hand-picked subset of the conformance corpus's encode cases, named by
-- case id (until the corpus runner runs them all): every size in both
-- time forms and both cases, a random field of all ones at each short last
-- group, the ends of standard time, the compact guard's last valid time,
-- no prefix and the empty prefix, and a prefix holding the delimiter.
-- sabotage: the lower-case alphabet in place of the upper-case one in
-- uxid_encode's translate -> " encode/xs-standard-upper | usr_01HF7YAT00 |
-- t" and every upper row
-- sabotage: CASE WHEN compact THEN 9 in place of THEN 8 in
-- uxid__base32_time -> " encode/xs-compact-lower | usr_hf7yat0001 | t"
-- sabotage: 5 in place of least(5, 8 * field.bytes - 5 * g.i) in
-- uxid__base32_bytes -> " encode/s-standard-rand-all-ones |
-- cus_01hf7yat00zzz1 | t"
SELECT
    c.case_id,
    uxid_encode(
        c.prefix, c.size, c.time_ms, decode(c.rand, 'hex'), c.compact,
        c.letter_case
    ) AS id,
    uxid_encode(
        c.prefix, c.size, c.time_ms, decode(c.rand, 'hex'), c.compact,
        c.letter_case
    ) = c.expected AS matches
FROM
    (
        VALUES
        (
            'encode/xs-standard-lower', 'usr', 'xs', 1700000000000, '',
            FALSE, 'lower', 'usr_01hf7yat00'
        ),
        (
            'encode/xs-standard-upper', 'usr', 'xs', 1700000000000, '',
            FALSE, 'upper', 'usr_01HF7YAT00'
        ),
        (
            'encode/xs-compact-lower', 'usr', 'xs', 1700000000000, '01',
            TRUE, 'lower', 'usr_hf7yat0001'
        ),
        (
            'encode/xs-compact-upper', 'usr', 'xs', 1700000000000, '01',
            TRUE, 'upper', 'usr_HF7YAT0001'
        ),
        (
            'encode/s-standard-lower', 'usr', 's', 1700000000000, '0123',
            FALSE, 'lower', 'usr_01hf7yat0004h1'
        ),
        (
            'encode/s-standard-upper', 'usr', 's', 1700000000000, '0123',
            FALSE, 'upper', 'usr_01HF7YAT0004H1'
        ),
        (
            'encode/s-compact-lower', 'usr', 's', 1700000000000, '012345',
            TRUE, 'lower', 'usr_hf7yat0004hm5'
        ),
        (
            'encode/s-compact-upper', 'usr', 's', 1700000000000, '012345',
            TRUE, 'upper', 'usr_HF7YAT0004HM5'
        ),
        (
            'encode/m-standard-lower', 'usr', 'm', 1700000000000,
            '0123456789', FALSE, 'lower', 'usr_01hf7yat0004hmasw9'
        ),
        (
            'encode/m-standard-upper', 'usr', 'm', 1700000000000,
            '0123456789', FALSE, 'upper', 'usr_01HF7YAT0004HMASW9'
        ),
        (
            'encode/m-compact-lower', 'usr', 'm', 1700000000000,
            '0123456789ab', TRUE, 'lower', 'usr_hf7yat0004hmasw9n3'
        ),
        (
            'encode/m-compact-upper', 'usr', 'm', 1700000000000,
            '0123456789ab', TRUE, 'upper', 'usr_HF7YAT0004HMASW9N3'
        ),
        (
            'encode/l-standard-lower', 'usr', 'l', 1700000000000,
            '0123456789abcd', FALSE, 'lower', 'usr_01hf7yat0004hmasw9nf61'
        ),
        (
            'encode/l-standard-upper', 'usr', 'l', 1700000000000,
            '0123456789abcd', FALSE, 'upper', 'usr_01HF7YAT0004HMASW9NF61'
        ),
        (
            'encode/l-compact-lower', 'usr', 'l', 1700000000000,
            '0123456789abcdef', TRUE, 'lower', 'usr_hf7yat0004hmasw9nf6yf'
        ),
        (
            'encode/l-compact-upper', 'usr', 'l', 1700000000000,
            '0123456789abcdef', TRUE, 'upper', 'usr_HF7YAT0004HMASW9NF6YF'
        ),
        (
            'encode/xl-standard-lower', 'usr', 'xl', 1700000000000,
            '0123456789abcdef0123', FALSE, 'lower',
            'usr_01hf7yat0004hmasw9nf6yy093'
        ),
        (
            'encode/xl-standard-upper', 'usr', 'xl', 1700000000000,
            '0123456789abcdef0123', FALSE, 'upper',
            'usr_01HF7YAT0004HMASW9NF6YY093'
        ),
        (
            'encode/xl-compact-lower', 'usr', 'xl', 1700000000000,
            '0123456789abcdef0123', TRUE, 'lower',
            'usr_hf7yat0004hmasw9nf6yy093'
        ),
        (
            'encode/xl-compact-upper', 'usr', 'xl', 1700000000000,
            '0123456789abcdef0123', TRUE, 'upper',
            'usr_HF7YAT0004HMASW9NF6YY093'
        ),
        (
            'encode/xs-compact-rand-all-ones', 'cus', 'xs', 1700000000000,
            'ff', TRUE, 'lower', 'cus_hf7yat00z7'
        ),
        (
            'encode/s-standard-rand-all-ones', 'cus', 's', 1700000000000,
            'ffff', FALSE, 'lower', 'cus_01hf7yat00zzz1'
        ),
        (
            'encode/s-compact-rand-all-ones', 'cus', 's', 1700000000000,
            'ffffff', TRUE, 'lower', 'cus_hf7yat00zzzzf'
        ),
        (
            'encode/m-compact-rand-all-ones', 'cus', 'm', 1700000000000,
            'ffffffffffff', TRUE, 'lower', 'cus_hf7yat00zzzzzzzzz7'
        ),
        (
            'encode/l-standard-rand-all-ones', 'cus', 'l', 1700000000000,
            'ffffffffffffff', FALSE, 'lower', 'cus_01hf7yat00zzzzzzzzzzz1'
        ),
        (
            'encode/xs-standard-time-zero', NULL, 'xs', 0, '', FALSE,
            'lower', '0000000000'
        ),
        (
            'encode/xs-standard-time-max', NULL, 'xs', 281474976710655, '',
            FALSE, 'lower', '7zzzzzzzzz'
        ),
        (
            'encode/s-compact-guard-last-valid', 'usr', 's', 1065151889407,
            '012345', TRUE, 'lower', 'usr_yzzzzzzz04hm5'
        ),
        (
            'encode/xl-standard-no-prefix', NULL, 'xl', 1700000000000,
            '0123456789abcdef0123', FALSE, 'lower',
            '01hf7yat0004hmasw9nf6yy093'
        ),
        (
            'encode/xl-standard-empty-prefix', '', 'xl', 1700000000000,
            '0123456789abcdef0123', FALSE, 'lower',
            '01hf7yat0004hmasw9nf6yy093'
        ),
        (
            'encode/s-standard-prefix-with-delimiter', 'a_b', 's',
            1700000000000, '0123', FALSE, 'lower', 'a_b_01hf7yat0004h1'
        )
    ) AS c (
        case_id, prefix, size, time_ms, rand, compact, letter_case, expected
    );

-- The defaults: standard time, lower case, delimiter _; the long size
-- spellings name the same sizes.
SELECT
    uxid_encode('usr', 'xl', 1700000000000, '\x0123456789abcdef0123')
        AS xl_defaults,
    uxid_encode('usr', 'xlarge', 1700000000000, '\x0123456789abcdef0123')
        AS xlarge,
    uxid_encode('usr', 'small', 1700000000000, '\x0123') AS small,
    uxid_encode('usr', 'xsmall', 1700000000000, '') AS xsmall,
    uxid_encode('usr', 'medium', 1700000000000, '\x0123456789') AS medium,
    uxid_encode('usr', 'large', 1700000000000, '\x0123456789abcd')
        AS large_size;

-- A custom delimiter separates the prefix; case never applies to the
-- prefix, only to the body.
-- sabotage: upper(id.head) in place of id.head for an upper-case id in
-- uxid_encode -> " usr-01hf7yat0004h1 | usr::01hf7yat0004h1 |
-- Usr-01HF7YAT0004H1", and " encode/xs-standard-upper | usr_01HF7YAT00 |
-- t" above
SELECT
    uxid_encode(
        'usr', 's', 1700000000000, '\x0123', delimiter => '-'
    ) AS dash,
    uxid_encode(
        'usr', 's', 1700000000000, '\x0123', delimiter => '::'
    ) AS two_characters,
    uxid_encode(
        'Usr', 's', 1700000000000, '\x0123',
        letter_case => 'upper', delimiter => '-'
    ) AS upper_body;

-- An explicit rand_size sets the random field's width: 3 bytes at size s
-- standard is 5 random characters, and 0 bytes at xl leaves the time
-- alone.
SELECT
    uxid_encode(
        'usr', 's', 1700000000000, '\x012345', rand_size => 3
    ) AS s_three_bytes,
    uxid_encode('usr', 'xl', 1700000000000, '', rand_size => 0) AS xl_none;

-- A NULL size, letter_case or delimiter takes the default; a NULL compact
-- is standard time.
SELECT
    uxid_encode(
        'usr', NULL, 1700000000000, '\x0123456789abcdef0123', NULL, NULL,
        NULL
    ) AS null_options;

-- The encoder is immutable and parallel safe.
SELECT
    p.provolatile,
    p.proparallel
FROM pg_proc AS p
WHERE
    p.oid
    = 'uxid_encode(text, text, bigint, bytea, boolean, text, text, integer)'
    ::regprocedure;
