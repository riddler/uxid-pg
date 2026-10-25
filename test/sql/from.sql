-- uxid_from, the deterministic id of a key: SHA-256 of the prefix and the
-- key, behind the marker z.
SET client_encoding = 'UTF8';
\set SHOW_CONTEXT never

-- Every deterministic case of the conformance corpus at v2.10.0 (12
-- cases), named by case id (conformance.sql runs them all again). The
-- non-ASCII case hashes the key's UTF-8 bytes, U+00E9 precomposed.
-- sabotage: the set_byte count byte left out of the hash input
-- -> " deterministic/golden-usr-xl | usr_zaemdwqphe2sw084gxbs7czw33 | f"
-- and every other row
-- sabotage: 'y' in place of 'z' as the marker
-- -> " deterministic/golden-usr-xl | usr_ycvt7epac0t1ebcsjfyf7cwz25 | f"
-- sabotage: left(..., req.chars + 1) in place of left(..., req.chars)
-- -> " deterministic/golden-usr-xl | usr_zcvt7epac0t1ebcsjfyf7cwz25d | f"
-- sabotage: the upper-case translate dropped (the body left as it is)
-- -> " deterministic/usr-xl-upper | usr_zcvt7epac0t1ebcsjfyf7cwz25 | f"
SELECT
    c.case_id,
    uxid_from(c.prefix, c.key, c.size, c.letter_case) AS id,
    uxid_from(c.prefix, c.key, c.size, c.letter_case) = c.expected AS matches
FROM
    (
        VALUES
        (
            'deterministic/golden-usr-xl', 'usr', 'alice@example.com',
            'xl', 'lower',
            'usr_zcvt7epac0t1ebcsjfyf7cwz25'
        ),
        (
            'deterministic/golden-cus-s', 'cus', 'acme-corp',
            's', 'lower',
            'cus_zt9vnyfd85bff0'
        ),
        (
            'deterministic/golden-no-prefix-m', NULL, 'alice@example.com',
            'm', 'lower',
            'zqz4cwzgyw8ks97869'
        ),
        (
            'deterministic/usr-xs', 'usr', 'alice@example.com',
            'xs', 'lower',
            'usr_z1yhw20vag'
        ),
        (
            'deterministic/usr-s', 'usr', 'alice@example.com',
            's', 'lower',
            'usr_z5rtsrkhx2h4dr'
        ),
        (
            'deterministic/usr-m', 'usr', 'alice@example.com',
            'm', 'lower',
            'usr_zt8naccefxhwnrmscd'
        ),
        (
            'deterministic/usr-l', 'usr', 'alice@example.com',
            'l', 'lower',
            'usr_zwbz6myvgz7ehe3nceap5n'
        ),
        (
            'deterministic/usr-xl', 'usr', 'alice@example.com',
            'xl', 'lower',
            'usr_zcvt7epac0t1ebcsjfyf7cwz25'
        ),
        (
            'deterministic/empty-prefix-xl', '', 'alice@example.com',
            'xl', 'lower',
            'z4krgegf6drn563pvqhya4tsx9'
        ),
        (
            'deterministic/no-prefix-xl', NULL, 'alice@example.com',
            'xl', 'lower',
            'z4krgegf6drn563pvqhya4tsx9'
        ),
        (
            'deterministic/usr-xl-upper', 'usr', 'alice@example.com',
            'xl', 'upper',
            'usr_ZCVT7EPAC0T1EBCSJFYF7CWZ25'
        ),
        (
            'deterministic/non-ascii-from-m', 'cus', 'café',
            'm', 'lower',
            'cus_zfsx9se75671f9kdjv'
        )
    ) AS c (case_id, prefix, key, size, letter_case, expected);

-- The long size spellings give the same id as the short ones, and a NULL
-- size, letter_case or delimiter takes its default.
-- sabotage: delimiter in place of coalesce(delimiter, '_') in the head
-- -> " t            | t          | t           | t          | t            |
-- f" under null_options_are_defaults
SELECT
    uxid_from('usr', 'alice@example.com', 'xsmall')
    = uxid_from('usr', 'alice@example.com', 'xs') AS xsmall_is_xs,
    uxid_from('usr', 'alice@example.com', 'small')
    = uxid_from('usr', 'alice@example.com', 's') AS small_is_s,
    uxid_from('usr', 'alice@example.com', 'medium')
    = uxid_from('usr', 'alice@example.com', 'm') AS medium_is_m,
    uxid_from('usr', 'alice@example.com', 'large')
    = uxid_from('usr', 'alice@example.com', 'l') AS large_is_l,
    uxid_from('usr', 'alice@example.com', 'xlarge')
    = uxid_from('usr', 'alice@example.com', 'xl') AS xlarge_is_xl,
    uxid_from('usr', 'alice@example.com', NULL, NULL, NULL)
    = 'usr_zcvt7epac0t1ebcsjfyf7cwz25' AS null_options_are_defaults;

-- A custom delimiter appears only in the head: the body is the same.
SELECT
    uxid_from('usr', 'alice@example.com', delimiter => '-') AS dash,
    uxid_from('usr', 'alice@example.com', delimiter => '::') AS colons;

-- The prefix keeps its case in an upper-case id; only the body changes.
SELECT uxid_from('Usr', 'alice@example.com', letter_case => 'upper') AS id;

-- A NULL key gives NULL, with a prefix or without. An empty key is a valid
-- key: it gives a 26-character xl id.
-- sabotage: WHEN FALSE THEN NULL in place of WHEN id.no_key THEN NULL
-- -> " f        | f" under null_key and null_key_no_prefix
SELECT
    uxid_from('usr', NULL) IS NULL AS null_key,
    uxid_from(NULL, NULL) IS NULL AS null_key_no_prefix;
SELECT
    uxid_from(NULL, '') AS empty_key,
    length(uxid_from(NULL, '')) AS empty_key_length;

-- Two prefixes, or two sizes, for one key give unrelated bodies: each is
-- hashed from a different input.
SELECT
    uxid_from('usr', 'alice@example.com', 'm') AS usr_m,
    uxid_from('doc', 'alice@example.com', 'm') AS doc_m,
    uxid_from('usr', 'alice@example.com', 's') AS usr_s;

-- A request is refused as uxid_check_request refuses it, before the key is
-- read: an unknown size or letter_case or an empty delimiter is
-- invalid_argument even when the key is NULL.
SELECT uxid_from('usr', 'alice@example.com', 'huge');
SELECT uxid_from('usr', 'alice@example.com', letter_case => 'title');
SELECT uxid_from('usr', 'alice@example.com', delimiter => '');
SELECT uxid_from('usr', NULL, 'huge');
SELECT uxid_from('usr', NULL, letter_case => 'title');
SELECT uxid_from('usr', NULL, delimiter => '');

-- A fixed random field with a key is refused as rand_with_from, by the
-- request check (the corpus case invalid/generate-rand-with-from).
SELECT
    uxid_check_request(
        prefix => 'usr', from_key => 'alice@example.com',
        rand => '\x00010203040506070809'
    );

-- The function is immutable and parallel safe.
SELECT
    p.provolatile,
    p.proparallel
FROM pg_proc AS p
WHERE p.oid = 'uxid_from(text, text, text, text, text)'::regprocedure;
