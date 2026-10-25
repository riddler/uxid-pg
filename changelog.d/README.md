# Changelog fragments

Changelog entries for unreleased work live here, one file per issue, not as
edits to `CHANGELOG.md`. At release the fragments are assembled into one
version section of `CHANGELOG.md` and deleted.

## Why fragments

Work happens in one worktree per issue, so several branches are usually open
at once. If each appended to the top of `CHANGELOG.md`, every branch would
touch the same lines of the same file and nearly every pull request would
conflict with every other. A fragment is named for its issue, so no two
branches write the same file.

## When a change needs a fragment

The changelog serves people who use the extension. Write a fragment for a
change a user of the extension could notice:

- a public function or the `uxid` domain added, changed or removed, or a
  change to a function's arguments, defaults, return type, volatility or
  parallel safety
- a change in observable behavior, including what an id looks like and what
  generation, decoding or the validity checks accept or refuse, and the
  SQLSTATE or message of a refusal
- a change in how the extension is installed: the control file's settings,
  the install paths (`CREATE EXTENSION`, the plain migration, pg_tle), an
  upgrade script, or the supported PostgreSQL versions
- a bug fix a user could have noticed
- anything breaking

Write none for tests, documentation, tooling, CI, the release workflow or
gate changes. If you are unsure, ask whether someone who only installs the
extension and calls its functions could tell the difference; if not, skip it.

## Format

One file per issue, named for its beads issue id, in the same pull request as
the change:

    changelog.d/uxpg-abc.md

The file holds a Keep a Changelog kind heading and one bullet per change; an
illustration of the shape, not a change this extension has made:

```markdown
### Fixed

- The validity check answers false for a `usr` id when the caller requires the `doc` prefix.
```

- The kind headings are `### Added`, `### Changed`, `### Deprecated`,
  `### Removed`, `### Fixed` and `### Security`. A file may carry more than
  one when the issue genuinely spans them.
- Bullets are `- `, one per change, in the present tense, saying what the
  change means to a user. No nested bullets: detail belongs in the pull
  request and the commit body.
- A breaking change opens its bullet with `Breaking:` and says what a caller
  does about it, not only what broke.
- A change in the vendored conformance corpus that changes an id this
  extension produces or accepts is visible to every consumer that stores ids:
  say what changes on the consumer's side.
- Examples stay domain-free: neutral resource prefixes such as `usr` or
  `doc`, and fictional `@example.com` addresses.

## At release

The release prep assembles the fragments into a new version section at the
top of `CHANGELOG.md`, below its title, at the `##` level:
`## X.Y.Z - YYYY-MM-DD`. The entries are grouped under the kind headings,
`### Added` and the rest, in the order Added, Changed, Deprecated, Removed,
Fixed, Security; within one kind, fragments go in file-name order and each
fragment's bullets keep their order and their `- ` marker. A `Breaking:`
bullet keeps that word. The sections already released in `CHANGELOG.md` are
not rewritten. The fragments are deleted in the same commit.

The prep's version bump and its tag follow CLAUDE.md, "Release preps".
Because the prep consumes every fragment, it merges last: a branch still
holding an unmerged fragment when the prep lands waits for the next release.
