-- The functions are bound when they are created (BEGIN ATOMIC bodies),
-- so they work with the extension's schema off the search_path, under
-- the empty search_path a dump restore uses, and after the extension
-- moves to another schema.
\set SHOW_CONTEXT never

-- The extension's schema is not on the search_path: pg_catalog alone.
-- sabotage: write uxid__compact with a string body (AS $c$ ... $c$)
-- -> " usr_01hf7yat0004h1" under uxid_encode
SET search_path = pg_catalog;
SELECT public.uxid_encode('usr', 's', 1700000000000, '\x0123'::bytea);
SELECT public.uxid_generate('usr', 'xs', TRUE) ~ '^usr_[0-9a-hjkmnp-tv-z]{10}$'
    AS generated_shape;
SELECT public.uxid_from('usr', 'alice@example.com', 's');
SELECT public.uxid_check_request(size => 'xs', monotonic => TRUE);
SELECT public.uxid_check_request(rand_size => 11);
SELECT public.uxid_version();
SELECT
    d.prefix,
    d.size,
    d.compact,
    d.deterministic,
    d.time_ms
FROM public.uxid_decode_at('usr_hf7yat0004hm5', 1700000000000) AS d;
SELECT
    d.prefix,
    d.size,
    d.compact,
    d.deterministic,
    d.time_ms
FROM public.uxid_decode('usr_01hf7yat0004h1') AS d;
SELECT public.uxid_decode_error('usr_01hf7yat00u');
SELECT
    public.uxid_is_valid('usr_01hf7yat0004h1', '_', 'usr') AS id_valid,
    public.uxid_is_deterministic('usr_z5rtsrkhx2h4dr') AS id_deterministic;
SELECT d.prefix FROM public.uxid_decode('usr_') AS d;

-- The empty search_path, as a dump restore sets it.
SET search_path = '';
SELECT public.uxid_encode('usr', 's', 1700000000000, '\x0123'::bytea);
SELECT public.uxid_from('usr', 'alice@example.com', 's');
SELECT length(public.uxid_generate()) AS generated_length;
SELECT public.uxid_check_request(delimiter => '');
SELECT
    d.prefix,
    d.size,
    d.compact,
    d.deterministic,
    d.time_ms
FROM public.uxid_decode_at('usr_hf7yat0004hm5', 1700000000000) AS d;
SELECT public.uxid_is_valid('usr_01hf7yat0004h1', '_', 'usr') AS id_valid;
SELECT public.uxid_decode_error('usr_') AS decode_reason;
RESET search_path;

-- After ALTER EXTENSION uxid SET SCHEMA, the functions live in the new
-- schema and still work with only pg_catalog on the search_path.
CREATE SCHEMA uxid_moved;
ALTER EXTENSION uxid SET SCHEMA uxid_moved;
SET search_path = pg_catalog;
SELECT
    uxid_moved.uxid_encode(
        'usr', 's', 1700000000000, '\x0123'::bytea, letter_case => 'upper'
    );
SELECT length(uxid_moved.uxid_generate('usr', 'm')) AS generated_length;
SELECT uxid_moved.uxid_from('usr', 'alice@example.com', 's');
SELECT uxid_moved.uxid_check_request(size => 'huge');
SELECT
    d.prefix,
    d.size,
    d.compact,
    d.deterministic,
    d.time_ms
FROM uxid_moved.uxid_decode('usr_hf7yat0004hm5', 1700000000000) AS d;
SELECT
    uxid_moved.uxid_is_valid('usr_01hf7yat0004h1', '_', 'usr') AS id_valid,
    uxid_moved.uxid_is_deterministic('usr_z5rtsrkhx2h4dr') AS id_deterministic,
    uxid_moved.uxid_decode_error('usr_01hf7yat000') AS decode_reason;
SELECT n.nspname
FROM pg_extension AS e
INNER JOIN pg_namespace AS n ON e.extnamespace = n.oid
WHERE e.extname = 'uxid';
RESET search_path;
ALTER EXTENSION uxid SET SCHEMA public;
DROP SCHEMA uxid_moved;
