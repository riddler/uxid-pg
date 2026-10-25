-- The extension installs and reports its version.
CREATE EXTENSION uxid;

-- sabotage: return '1.0.1' from uxid_version() -> " 1.0.0" under uxid_version
SELECT uxid_version();

-- The installed extension's version and the script's answer agree.
-- sabotage: return '1.0.1' from uxid_version() -> " t" under matches
SELECT e.extversion = uxid_version() AS matches
FROM pg_extension AS e
WHERE e.extname = 'uxid';

-- The function is immutable and parallel safe.
-- sabotage: VOLATILE PARALLEL UNSAFE in place of IMMUTABLE PARALLEL SAFE
-- -> " i           | s" under provolatile and proparallel
SELECT
    p.provolatile,
    p.proparallel
FROM pg_proc AS p
WHERE p.oid = 'uxid_version()'::regprocedure;
