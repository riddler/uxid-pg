-- uxid 1.0.0: prefixed, K-sortable, human-readable identifiers.
--
-- This script carries no psql guard line, so the same file serves
-- CREATE EXTENSION uxid and a plain migration run once with psql -f.

CREATE FUNCTION uxid_version()
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
BEGIN ATOMIC
    SELECT '1.0.0';
END;

COMMENT ON FUNCTION uxid_version() IS
'The version of the uxid extension script installed, such as 1.0.0.';
