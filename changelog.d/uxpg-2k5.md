### Added

- The extension `uxid` installs with `CREATE EXTENSION uxid`: relocatable, with `superuser = false` and no required extension. Its script carries no psql guard line, so the same file also runs once as a plain migration.
- `uxid_version()` returns the version of the extension script installed, `1.0.0`; it is immutable and parallel safe.
