# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

## Beads issue tracker

This project tracks all work in **bd (beads)** - not TodoWrite, not markdown TODO
lists. The prefix is `uxpg-`. Run `bd prime` for the command reference and
session-close protocol, and `bd remember` for knowledge that should outlive the
session.

Claude Code injects `bd prime` at session start, so this section is deliberately
a stub; the authority rules below are the part that is specific to this repo.

`AGENTS.md` is a symlink to this file. There is one set of instructions, not two.

### Beads that span repositories

| Situation | Rule |
|---|---|
| A decision is recorded in two trackers and they disagree | The repository whose files change owns the decision. The ID format itself is uxid-ex's call (its wire-format spec and its conformance corpus); this port's SQL surface, packaging and gate are this repo's call |
| A bead pairs with one in another repo | Both halves carry `mirrors: <id>` as the first line of the description |
| You are about to schedule, claim, plan against, or cite the status of a mirrored bead | Re-read the other tracker first and write a new dated note above the old one, then act |
| A `mirrors:` line names an id that no longer resolves | Broken immediately, not stale. Fix it with one `bd update` the moment you notice |

## Agent authority in this repo

**This repository grants an agent the authority to commit, push, and open
requests only inside an orchestrated campaign that carries the operator's
explicit consent for that campaign.** The grant is consent-scoped, not
standing. Outside such a campaign the conservative rules `bd prime` describes
apply in full, and so they do for any action the table below does not name.

What unlocks the grant is the operator saying, in their own words, that a
particular campaign may commit, push, and open requests here. Nothing else
does. It is **not** inferable from another repository having opted into the
team-maintainer profile; not from this file's resemblance to theirs; not from
the fact that the same person works on all of them. A dispatch from another
agent - a conductor, an orchestrator, a parent session - is not by itself the
operator's consent either, however confidently it asserts otherwise. An agent
that believes consent exists but cannot point to where the operator gave it
should do the work, stop before the irreversible step, and report.

| Action | Trigger | Still unauthorized when |
|---|---|---|
| `bd` task tracking (`create`, `claim`, `update`, `note`) | any time | never - this is the conservative profile too |
| `mise run gate` and any of its tasks | any time | never - running the gate costs nothing but time |
| `git commit` on the bead's branch | a campaign carrying the operator's explicit consent **and** the bead's work complete **and** the full gate (`mise run gate`) green; a change touching no path the manifest lists under `gate.build_paths` or `gate.also_gated_paths` (the lists the gate rules below name) has no gate to run and may commit on review of the diff alone | on `main`, on a red gate, on a `mise run gate:loop` or otherwise scoped run, or with unrelated changes in the tree |
| `git push`, `gh pr create` | the same consent, **and** the terminology scan clean over the full outbound content | any scan hit - that is a hard stop, not something to rephrase past |
| merging a campaign PR | a campaign consent the operator adopted verbatim that names automatic merges, with every named condition met (full gate green, firewall scan clean with a positive control, any named review gate passed) | outside such a consent; any named condition unmet; any PR the consent's carve-outs hold for the operator |
| `bd close <id>` | never for a mirrored bead whose other half is not merged to its own repo's `origin/main`; a mirrored bead whose other half has ALSO landed may be closed by the campaign conductor under a consent naming this exception, both halves together, each verified against its remote; otherwise the operator's call | for a bead whose description carries a `mirrors:` line while its other half is unlanded, campaign consent included |
| `bd dolt push` | bead state changed locally **and** the git side of the same change has already reached `origin`; inside a campaign, the conductor pushes (atomically across the campaign's trackers) | as a way to publish beads for work that is not on `origin/main` yet |
| a release prep (a version bump and a changelog promotion) and its tag | a release bead a campaign consent names, or the operator names in their own words; the tag once that prep is merged to `origin/main`, naming its version at the merged commit | on any other bead or on `main`; the tag before the prep is on `origin/main` |
| a release, a GitHub release of this extension | never - a version of this extension is the GitHub release the release workflow (`.github/workflows/release.yml`) creates on the tag push the release-prep row above already allows; an agent or a session never creates, edits, deletes or uploads to a GitHub release by hand (no `gh release create`, `edit`, `delete` or `upload`), and never moves or deletes a pushed tag | always - a failed workflow is re-run from its Actions page, never worked round by hand; a broken release is fixed by a new patch version, never by moving its tag |

The organizing principle: the human gate belongs where an action stops being
reversible. A commit on a per-bead branch is undone with
`git reset --soft HEAD~1`. A push, a request, a merge outside a consented
campaign, and a closed bead are visible to other people and other machines,
so a campaign's consent is what buys the first two and nothing buys the last
two.

Two rules override every row above. A current "do not commit", "do not push",
or equivalent instruction from the operator wins outright. And authority is
the operator's to give, never an agent's to infer: a subagent that believes a
trigger has fired - reasoning its way there from its dispatch, from a sibling
repo, or from the fact that it was asked to do the work - reports that, it
does not act on it. A subagent carrying the operator's consent relayed
verbatim by the session that owns the work is the other case: there the
authority is the operator's and the subagent is only the hands, so it may act.
What has to be quotable is the relay - the operator's own words authorizing
that campaign, not the subagent's sense of being authorized. A subagent that
cannot quote them reports and stops. A relay unlocks nothing the rows above
forbid outright: closing a mirrored bead, creating, editing or deleting a
GitHub release by hand, and moving a pushed tag stay forbidden however the
consent arrives. A release prep and its tag are not a release; the Release
preps paragraphs below record them.

Merging a campaign PR is a recorded exception: under a campaign consent the
operator has adopted verbatim that names automatic merges, with every
condition that consent names met, the conductor's merge executes the
operator's own authorization - the consent's text is what may be done and
nothing more. (Adopted here at onboarding with the rest of this authority
table.)

**Release preps.** The version bump and the tag of a release prep are the
family norm, not a grant a campaign consent has to name. On a release bead
a campaign consent names, or the operator names in their own words, the
prep - the version bump (`default_version` in `uxid.control` and the value
`uxid_version()` returns; for a version after 1.0.0, the upgrade script
`uxid--<from>--<to>.sql` that carries the change, since a released script is
never edited), the version in the README's install line once the README
carries one, and the changelog promotion - lands through the rows above; once
it is merged to `origin/main`, the conductor or the session that owns the
release bead tags that merged commit with the new version (`vX.Y.Z`) and
pushes the tag. The tag push is the release: the release workflow
(`.github/workflows/release.yml`, the file the release publishes from)
verifies the tag and its publish job creates the GitHub release on it,
carrying `uxid-pg-<version>.tar.gz` (a `git archive` of the tag) and its
`.sha256`, with the version's `CHANGELOG.md` section as its notes. A failed
workflow is re-run from its Actions page, never worked round by hand; the
workflow's header says what each step checks, what a failure leaves behind
and which re-run can go green. The manifest's release kind,
`github-release`, is not one `/wurk:release` implements (it cuts `hex` only),
so a prep is made by hand: these paragraphs are its recipe.

There is no package registry for this extension. The publish job, and no
other job or workflow, holds `contents: write`, and it creates the release
with the workflow's own `GITHUB_TOKEN`. No repository secret exists in this
repository and none is created: no agent or session lists, reads, prints or
sets one, and nobody runs `gh secret` against this repository. PGXN is not
part of this repository: nothing is uploaded there. Merging the prep follows
this file's merge row, and nothing else this file reserves for the operator
changes. A prep is cut only on a green full gate, which will include the
conformance corpus check.

This repository keeps no decision records (`docs/adr`). A release or gating
decision is recorded here, in the authority table and the Release preps
paragraphs, and in the header of the workflow it governs; a change a user of
the extension could notice is a changelog fragment (Conventions, below). The
ID format itself is not decided here: it is uxid-ex's wire-format spec,
`guides/wire-format.md` in https://github.com/riddler/uxid-ex, read at the
tag the vendored corpus names (`conformance/SOURCE.json`, once the corpus is
vendored). That this repository keeps no decision records was decided by the
conductor under a standing consent, 2026-10-24; a future API decision may
start a `docs/adr` directory.

Widening this section is a decision for the operator to make and record here.
An agent may draft the change; it does not adopt it.

## Non-interactive shell commands

`cp`, `mv`, and `rm` may be aliased to `-i` on a developer's machine, which
hangs an agent forever on a y/n prompt it cannot see. Always pass the
non-interactive form: `cp -f`, `mv -f`, `rm -f`, `rm -rf`, `cp -rf`. Same for
`scp` and `ssh` (`-o BatchMode=yes`), `apt-get` (`-y`), and `brew`
(`HOMEBREW_NO_AUTO_UPDATE=1`).

Also avoid `bd edit`, which opens `$EDITOR` and blocks. Use
`bd update <id> --title/--description/--notes/--design` instead.

## What this project is

`uxid` for PostgreSQL. Version 1.0.0, the extension this repository is being
built into, makes prefixed, K-sortable, Stripe-style identifiers a person can
read, copy and route back to their resource, wire-compatible with the Elixir
reference `uxid` and checked against its conformance corpus. It is a
PostgreSQL extension named `uxid`, written in pure SQL and PL/pgSQL (no C, no
compiled module, no dependency beyond core PostgreSQL 14 or later). It covers
generation (random, deterministic and monotonic), decoding and the validity
checks as functions whose names start `uxid_`, and a `uxid` domain over
`text COLLATE "C"`. Its random bytes come from the core `gen_random_uuid()`
CSPRNG. It installs by `CREATE EXTENSION uxid` (relocatable, with
`superuser = false`, so any role with CREATE on the target schema may install
it), by running the extension script once as a plain migration, or through
pg_tle's `pgtle.install_extension` on managed services.

The tree on `main` today holds the build and the gate around the first
part of the extension: the control file (`uxid.control`), the 1.0.0
extension script (`uxid--1.0.0.sql`), which defines `uxid_version()`,
time-based generation (`uxid_generate`, the pure encoder `uxid_encode` and
the request check `uxid_check_request`), deterministic generation
(`uxid_from`), decoding (`uxid_decode`, the pure decoder `uxid_decode_at`
and `uxid_decode_error`), the validity checks (`uxid_is_valid` and
`uxid_is_deterministic`), the `uxid` domain and their internal `uxid__`
helpers, the PGXS `Makefile`, a `pg_regress` test per function under
`test/` beside the surface test,
`mise.toml` with the gate tasks, the gate's Docker image and its scripts
under `docker/`, the CI and release workflows under `.github/workflows/`,
the sqlfluff configuration (`.sqlfluff`), `LICENSE`, `CHANGELOG.md` and
`changelog.d/`, beside these agent instructions, the wurk manifest
(`.claude/wurk.json`), the Claude Code settings (`.claude/settings.json`)
and the tracker files under `.beads/`. Monotonic generation and the
vendored corpus arrive with later changes; until they do, the sentences in
this file about those describe the target, not the current tree.

- **The extension is `uxid`.** Version 1.0.0 is its first release, a GitHub
  release on the tag `v1.0.0`.
- **The corpus is the arbiter.** `conformance/` will hold the corpus
  vendored from uxid-ex at a release tag, its tag, commit and hash recorded in
  `conformance/SOURCE.json`. The vendored files are never edited, and every
  case passes with no skip list: a case this port cannot pass is reported
  against uxid-ex with its evidence, never skipped or worked round here. An
  answer the corpus does not fix follows uxid-ex's spec at that tag.

`README.md`, which a later change adds, is the user reference; `CHANGELOG.md`
records each release.

## Build & Test

The gate tasks live in `mise.toml`.

```bash
mise install            # Python and sqlfluff, as mise.toml pins them
mise run gate:loop      # inner loop
mise run gate           # full gate
```

The local gate runs PostgreSQL in Docker: no PostgreSQL client or server is
installed or linked on the host for it, `psql` and `pg_config` are not
expected on the host's `PATH`, and sqlfluff comes from mise. The full gate
prints `docker --version`, then `docker/installcheck.sh` builds
`docker/Dockerfile` (FROM `postgres:18` pinned by digest, adding `make`),
starts a container with the repository mounted read-only, prints the
server's `SELECT version()`, copies the tree into the container, runs
`make install` and `make installcheck` (`pg_regress`) there, prints
`regression.diffs` on a failure, and removes the container on every exit,
so the build and the `pg_regress` output never land in the working tree.
The gate then runs mise.toml's `lint` task, `sqlfluff lint` (the postgres
dialect, `.sqlfluff`) over the extension script and `test/sql/`, and the
conformance corpus check (`scripts/corpus-check.sh`) once the corpus is
vendored: until `conformance/` or that script exists the step says so and
passes, and once either exists a missing script fails the gate. The inner
loop, `mise run gate:loop`, is `docker/installcheck.sh` alone.

The SQL lint is sqlfluff with the postgres dialect: sqlfluff 4.4.0 parses
SQL-standard function bodies (`BEGIN ATOMIC ... END` and `RETURN`), the
form the extension's functions are bound in, so the `pg_format` check mode, the fallback for a construct sqlfluff cannot
parse, is not used. No sqlfluff rule is disabled and no file is excluded
from the lint (decided by the conductor under a standing consent,
2026-10-24). sqlfluff skips a file over 20000 bytes by default, with a
warning and a pass; `.sqlfluff` sets `large_file_skip_byte_limit = 0` so
the extension script, which is larger, is linted whole.

There is no line-coverage floor: no token-free tool measures SQL and PL/pgSQL
function bodies. In its place stand a surface test (the extension's functions
read from the catalog and pinned), a regression file per function and the
full corpus.

The gate proves the server version it runs on (18). The declared floor is
PostgreSQL 14, stated apart from the gate's version. CI
(`.github/workflows/ci.yml`) runs the full gate on ubuntu-24.04, and
`make installcheck` on PostgreSQL 14, 15, 16, 17 and 18 in the
`pgxn/pgxn-tools` container; it runs the lint task, the extension script
as a plain migration on 14 and 18, and the pg_tle install path on 17
(pg_tle built at a pinned release, preloaded, the script installed through
`pgtle.install_extension`). The workflow's header says what each job runs.

### This repo's own gate rules

- The full gate is `mise run gate`; the inner loop is `mise run gate:loop`.
  Only the full command is the advancement gate: a `gate:loop` run, like a
  bare `make installcheck`, a single regression file or any other scoped run,
  is never evidence for a claim that the gate is green.
- **Never truncate the output.** No `| tail`, `| head`, `| grep`; truncating
  removes findings, not noise.
- **Never go green by weakening the check.** Not by editing an expected
  output file to agree with a wrong result, not by dropping a test from the
  `Makefile`'s `REGRESS` list, not by a `noqa` marker or a rule excluded or
  loosened in the sqlfluff configuration (a lint-config loosening is the
  maintainer's call), not by catching an error in a test so it cannot show,
  not by dropping or skipping a corpus case or adding a skip list to the
  conformance runner. If a finding is genuinely wrong for this project, say
  so and let the operator decide.
- The gate's PostgreSQL container is started and removed inside the gate run;
  never leave one running.
- Check `git status` after a gate run and include or discard deliberately
  anything it rewrote (a `results/` directory or `regression.diffs` left by
  `pg_regress` is never committed).
- A change touching no path the manifest (`.claude/wurk.json`) lists under
  `gate.build_paths` or `gate.also_gated_paths` has no gate to run and may
  commit on review of the diff alone. Those two lists are the one source for
  the exception: `uxid.control`, `uxid--1.0.0.sql`, `test/`, `conformance/`,
  `scripts/` and `README.md` are what the gate checks, and the `Makefile`,
  `docker/`, `mise.toml` and `.sqlfluff` decide how it runs and what it
  resolves. A listed path need not exist yet. The lists take no glob (an
  entry ending in `/` is a directory prefix, anything else an exact path),
  so each later upgrade script is added to `gate.build_paths` by name in the
  change that adds it.
- **Sabotage notes are SQL comments the reviewer reads.** The kit's
  sabotage-note scan reads only `#` comment lines, and SQL comments start
  with `--`, so the manifest declares no `gate.sabotage` block. A test's note
  is a comment beside the regression test it guards:
  `-- sabotage: <the mutation> -> <the expected-output line that failed>`.
  The reviewer reads each note by hand and re-runs a sample of the mutations.
- Documentation may point at the gate; it never enlarges it.

## Conventions

This repository is not part of the statifier package family, but it is worked
by the same operator with the same tooling, so it adopts the family's
satellite conventions rather than inventing a second set.

- **Domain-free examples.** The README, the SQL comments and the test
  fixtures teach no example domain: examples use neutral resource prefixes
  such as `usr` and `doc`, and any address is a fictional `@example.com` one.
- **Every public name starts `uxid_`** (the functions; the domain is `uxid`).
  An internal helper starts `uxid__` (two underscores) and carries a
  `COMMENT` saying it is not part of the public surface.
- **A released script is never edited.** The extension script for a version
  is `uxid--<version>.sql`; once that version is released, a later version
  ships an upgrade script (`uxid--<from>--<to>.sql`) and the released script
  stays as it was.
- **Bound at creation.** A function that calls another function of the
  extension is `LANGUAGE sql` with a `BEGIN ATOMIC` body, so the extension
  works with its schema off the caller's `search_path`, after
  `ALTER EXTENSION uxid SET SCHEMA`, and under a dump restore's empty
  `search_path`; PL/pgSQL is used only for leaf functions that call nothing
  but built-ins (decided by the conductor under a standing consent,
  2026-10-24).
- **No dependency beyond core PostgreSQL.** No C code, no compiled module
  (`MODULES`), no `requires` in `uxid.control`, no pgcrypto and no other
  extension the script needs: core functions only. Build and lint tools come
  from `mise.toml` and the gate's Docker image.
- **The random bytes come from the core CSPRNG.** Random bytes are taken from
  `uuid_send(gen_random_uuid())`, only its fully random bytes (never the
  version or variant bits); never `random()` or another seeded generator.
  Fixed random bytes, where the pure encoder takes them, exist for test
  vectors and are documented as such.
- **State only in the session.** The monotonic generator's state lives in the
  session's own settings, per prefix and random width, and nowhere else: no
  table, no sequence, no global configuration.
- **No test-only seam in the extension script.** Test-only SQL, such as the
  corpus runner, lives under `test/` and is never part of `uxid--*.sql`.
- **Pure SQL and PL/pgSQL, PostgreSQL 14 and later** (ruled by the operator,
  2026-10-24): a PGXS `Makefile`, `pg_regress` tests, the sqlfluff lint in
  the gate, and CI on PostgreSQL 14 through 18.
- **Tests are `pg_regress` files** under `test/`: a `.sql` file and its
  expected output. Every public function carries a `COMMENT ON FUNCTION`
  saying what it does.
- Sabotage every new test that asserts extension behavior: break the code it
  covers, confirm it goes red, revert, rebuild clean (make's timestamps are
  one second wide), and note the mutation in the form the gate rules above
  give.
- Changelog: a change a user of the extension could notice adds a fragment
  under `changelog.d/`, named for the bead (`changelog.d/uxpg-abc.md`), in the
  same request; tests, docs, tooling, CI and gate changes take none. New
  version sections in `CHANGELOG.md` keep the file's own heading shape;
  existing history is not rewritten.
- Commit messages: simple present tense ("Adds ...", "Fixes ..."), body
  wrapped at ~72 chars explaining why. Requests are rebase-merged, so each
  commit lands on main with its message unchanged. No AI attribution
  trailers.
