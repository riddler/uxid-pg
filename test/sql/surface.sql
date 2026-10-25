-- The extension's functions, read from the catalog: the public surface
-- with its full signatures, then the internal helpers, apart.

-- The public functions: arguments with their defaults, the result, the
-- volatility (i immutable, v volatile), parallel safety (s safe) and the
-- language.
-- sabotage: DEFAULT 'l' in place of DEFAULT 'xl' on uxid_generate's size
-- -> " uxid_generate      | v           | s           | sql     | text   |
-- prefix text DEFAULT NULL::text, size text DEFAULT 'xl'::text, ..."
-- sabotage: VOLATILE in place of IMMUTABLE on uxid_encode
-- -> " uxid_encode        | i           | s           | sql     | text   |
-- ..."
SELECT
    p.proname,
    p.provolatile,
    p.proparallel,
    l.lanname,
    pg_get_function_result(p.oid) AS result,
    pg_get_function_arguments(p.oid) AS arguments
FROM pg_proc AS p
INNER JOIN pg_depend AS d
    ON
        d.classid = 'pg_proc'::regclass
        AND p.oid = d.objid
        AND d.deptype = 'e'
INNER JOIN pg_extension AS e
    ON d.refobjid = e.oid
INNER JOIN pg_language AS l
    ON p.prolang = l.oid
WHERE
    e.extname = 'uxid'
    AND p.proname NOT LIKE 'uxid\_\_%'
ORDER BY p.proname;

-- The internal helpers, which start uxid__. The raise helper is VOLATILE
-- so the planner never evaluates it ahead of time out of a CASE branch
-- that is not taken: an IMMUTABLE one with constant arguments would raise
-- on every call of uxid_check_request.
-- sabotage: IMMUTABLE in place of VOLATILE on uxid__raise
-- -> " uxid__raise        | v           | s           | plpgsql | void    |
-- error_name text, detail text", and every accepted request in the
-- later files refused
SELECT
    p.proname,
    p.provolatile,
    p.proparallel,
    l.lanname,
    pg_get_function_result(p.oid) AS result,
    pg_get_function_arguments(p.oid) AS arguments
FROM pg_proc AS p
INNER JOIN pg_depend AS d
    ON
        d.classid = 'pg_proc'::regclass
        AND p.oid = d.objid
        AND d.deptype = 'e'
INNER JOIN pg_extension AS e
    ON d.refobjid = e.oid
INNER JOIN pg_language AS l
    ON p.prolang = l.oid
WHERE
    e.extname = 'uxid'
    AND p.proname LIKE 'uxid\_\_%'
ORDER BY p.proname;

-- Every function carries a comment, and an internal helper's says it is
-- not part of the public surface.
-- sabotage: drop the COMMENT ON FUNCTION for uxid__size
-- -> " uxid__size         | f" under commented
SELECT
    p.proname,
    coalesce(
        obj_description(p.oid, 'pg_proc') LIKE CASE
            WHEN p.proname LIKE 'uxid\_\_%'
                THEN
                    'Internal helper of the uxid extension, not part of '
                    || 'its public surface: %'
            ELSE '%'
        END,
        FALSE
    ) AS commented
FROM pg_proc AS p
INNER JOIN pg_depend AS d
    ON
        d.classid = 'pg_proc'::regclass
        AND p.oid = d.objid
        AND d.deptype = 'e'
INNER JOIN pg_extension AS e
    ON d.refobjid = e.oid
WHERE e.extname = 'uxid'
ORDER BY p.proname;

-- Every function except the raise helper is LANGUAGE sql with a BEGIN
-- ATOMIC body (prosqlbody set), so its callees are bound when it is
-- created.
-- sabotage: write uxid__compact with a string body (AS $c$ ... $c$)
-- -> " uxid__compact      | f" under bound
SELECT
    p.proname,
    p.prosqlbody IS NOT NULL AS bound
FROM pg_proc AS p
INNER JOIN pg_depend AS d
    ON
        d.classid = 'pg_proc'::regclass
        AND p.oid = d.objid
        AND d.deptype = 'e'
INNER JOIN pg_extension AS e
    ON d.refobjid = e.oid
WHERE e.extname = 'uxid'
ORDER BY p.proname;

-- No function of the extension calls random() or setseed(); the random
-- bytes come from gen_random_uuid().
-- sabotage: substring(md5(random()::text)::bytea FROM 1 FOR n) as the
-- second statement of uxid__random_bytes -> " f            | t" under
-- calls_random and calls_gen_random_uuid
SELECT
    bool_or(pg_get_functiondef(p.oid) ~ '(^|[^a-z_])(random|setseed)\(')
        AS calls_random,
    bool_or(pg_get_functiondef(p.oid) ~ 'gen_random_uuid\(')
        AS calls_gen_random_uuid
FROM pg_proc AS p
INNER JOIN pg_depend AS d
    ON
        d.classid = 'pg_proc'::regclass
        AND p.oid = d.objid
        AND d.deptype = 'e'
INNER JOIN pg_extension AS e
    ON d.refobjid = e.oid
WHERE e.extname = 'uxid';
