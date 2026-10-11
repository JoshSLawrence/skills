<!-- markdownlint-disable MD013 -->
<!-- Wide tables and code samples are unwrappable. -->

# Versions, `mise use`, the lockfile, and upgrades

Read this when choosing a version syntax, creating or repairing `mise.lock`,
or bumping tools. Behavior verified against mise 2026.10.7 unless marked
"docs". Sources: <https://mise.jdx.dev/dev-tools/versions.html>,
<https://mise.jdx.dev/dev-tools/mise-lock.html>.

## Contents

- Version request syntax
- How a request resolves
- What `mise use` writes
- Creating and maintaining `mise.lock`
- Installing from the lock
- Upgrading and finding outdated tools
- Removing tools
- Lockfile hygiene

## Version request syntax

| Request                     | Example            | Meaning                                                                                  |
| --------------------------- | ------------------ | ---------------------------------------------------------------------------------------- |
| exact                       | `"24.11.1"`        | that release; use this in shared config                                                  |
| prefix                      | `"24"`, `"3.14"`   | newest match at a separator boundary (`1.2` matches `1.2.3`, not `1.20`)                 |
| `latest`                    | `"latest"`         | what the backend calls latest (a GitHub "Latest" release, not always the highest semver) |
| alias                       | `"lts"`            | backend alias (node `lts`) or your `[tool_alias]`                                        |
| `prefix:`                   | `"prefix:1.20"`    | newest 1.20.x even if a release is literally named `1.20`                                |
| `ref:` / `tag:` / `branch:` | `"ref:main"`       | build from VCS; backend dependent                                                        |
| `path:`                     | `"path:/opt/node"` | use an existing directory                                                                |
| `system`                    | `"system"`         | mise adds nothing to PATH                                                                |
| list                        | `["3.14", "3.13"]` | install all; the first provides the unversioned binaries                                 |

- npm-style ranges (`^24`, `>=20`) are not supported. Verified: mise warns
  `semver range "^24" is not supported` and asks for a concrete version or
  prefix.
- `mise latest <tool>[@prefix]` and `mise ls-remote <tool> [prefix]` show what
  a request would resolve to. `mise latest` ignores `prefix:` (verified), so
  test that form with `mise x tool@prefix:1.7 -- tool --version`.

## How a request resolves

Order: (1) the lockfile entry for that request, (2) alias expansion, (3) an
**installed** version matching the request, (4) the remote version list.

Consequences, all verified:

- A prefix gives different answers on different machines. `jq = "1.7"`
  selected `1.7.1` when 1.7.1 was installed, and the release literally named
  `1.7` after 1.7.1 was uninstalled. Exact pins avoid the whole class.
- A new upstream release changes nothing until `mise upgrade`. With
  `shellcheck = "0"` and 0.9.0 installed, `mise install` reported "already
  installed" while 0.11.0 existed.
- A locked entry wins over a newer installed match.
- Releases younger than 24 hours are hidden (`minimum_release_age`); mise
  warns "N newer release hidden by minimum_release_age".

## What `mise use` writes

| Command                    | Written to `mise.toml`                                                                              |
| -------------------------- | --------------------------------------------------------------------------------------------------- |
| `mise use jq`              | `jq = "latest"`                                                                                     |
| `mise use jq@1`            | `jq = "1"`                                                                                          |
| `mise use --pin jq@latest` | `jq = "1.8.2"` (newest)                                                                             |
| `mise use --pin jq@1`      | the **installed** match of `1` (`"1.7.1"` if that is installed, though `mise latest jq@1` is 1.8.2) |
| `mise use jq@1.8.1`        | `jq = "1.8.1"`                                                                                      |

`mise use` installs immediately and records the request. For shared config
write an exact version. `--pin` on a prefix resolves like any other request:
installed versions win over the remote list (verified: with jq 1.7.1
installed, `mise use --pin jq@1` wrote `"1.7.1"`). Only `@latest` checks the
remote. So:

- Newest release: `mise use --pin tool@latest`.
- Newest within a major: `mise use tool@"$(mise latest tool@24)"`.
- Convert an existing `latest` entry without changing what runs:
  `mise use tool@"$(mise current tool)"` (verified: `mise current jq` prints
  `1.8.2`).

`pin = true` in settings makes `--pin` the default (docs); for a team, spell
out the exact version or flag in instructions so it does not depend on
anyone's settings.

Where it writes: the lowest-precedence file in the nearest directory that has
mise config (so `mise.toml`, not `mise.local.toml`); from a subdirectory with
no config, the parent's file; a new `mise.toml` in the current directory if
there is none. In `$HOME` it writes global config. **Gotcha (verified):** if
`.tool-versions` is the only config in the directory, `mise use --pin
shfmt@3.10.0` appends to `.tool-versions`, where tools are never locked. Use
`mise use --path mise.toml ...` (verified: it creates `mise.toml` beside the
`.tool-versions`) or convert first with `mise generate config --tool-versions
.tool-versions`.

| Flag                | Effect                                          |
| ------------------- | ----------------------------------------------- |
| `-g`                | global config (`~/.config/mise/config.toml`)    |
| `-e local`          | `mise.local.toml` (`-e X` writes `mise.X.toml`) |
| `--path <file>`     | a specific file, e.g. `.tool-versions`          |
| `--remove <tool>`   | remove the entry                                |
| `--dry-run`         | show what would change                          |
| `--tool-option K=V` | set a tool option, written as an option table   |

Note `-e` on `mise use` selects the file written, while the global `-E` flag
only *loads* an environment file; they are easy to confuse.

An unknown short name fails with `not found in mise tool registry` and writes
nothing; see `backends.md`.

Option tables can be written from the CLI (quote the whole spec):
`mise use 'github:jqlang/jq[version_prefix=jq-]@1.8.2'`. Tables need trust;
see `config-and-trust.md`.

## Creating and maintaining `mise.lock`

The `lockfile` setting has three states:

| State                | Behavior                                        |
| -------------------- | ----------------------------------------------- |
| unset (default)      | maintain an existing lockfile, never create one |
| `true` (in a config) | create and maintain                             |
| `false`              | off; errors if `locked = true` is also set      |

Recommended flow: leave it unset, create the file once with `mise lock`, and
commit it. Reason: `lockfile = true` lives under `[settings]`, which makes
`mise.toml` require trust, while the file's existence achieves the same
maintenance. Verified: with the setting unset and a `mise.lock` present,
`mise install` and `mise use` add entries for new tools.

- `mise lock` resolves and writes entries; it installs nothing. Without
  `--platform` a new file covers `linux-arm64`, `linux-arm64-musl`,
  `linux-x64`, `linux-x64-musl`, `macos-arm64`, `macos-x64`, `windows-x64`.
  Prefer this default set. `--platform` restrictions cause churn: with a
  `linux-x64`-only lock, a plain `mise install` on macOS added `macos-arm64`
  entries (verified), so contributors' diffs keep changing the file. Use
  `--platform` only when a narrow set is genuinely wanted.
- Entries added by `mise use` cover the platforms already in the lockfile
  (verified: a lock created for `macos-arm64` alone got a `macos-arm64`-only
  entry for a new tool). When CI runs a platform the lock lacks, `--locked`
  installs fail, so re-run `mise lock` (or with `--platform`).
- One lockfile per config file: `mise.toml` -> `mise.lock`,
  `mise.<env>.toml` -> `mise.<env>.lock`, `mise.local.toml` ->
  `mise.local.lock` (add it to `.gitignore`). `mise lock --global` writes the
  global one.
- Format (`lockfile_version = 3`):

  ```toml
  [[tools.jq]]
  version = "1.8.2"
  backend = "aqua:jqlang/jq"
  specifiers = ["1.8.2"]

  [tools.jq."platforms.macos-arm64"]
  checksum = "sha256:..."
  url = "https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-macos-arm64"
  provenance = "github-attestations"
  ```

  `specifiers` records which request the entry satisfies, and resolution
  matches on it. Do not hand-edit entries; regenerate them.
- Commit `mise.lock` and, when it exists, `.mise/locks/` (npm and pypi
  dependency-graph sidecars; `mise lock --sidecars` lists them) (docs).
- **Rate limits produce a silently incomplete lock.** In testing only
  `github:` tools needed the GitHub API while locking; aqua tools locked fully
  with no quota. A rate-limited `mise lock` still exits 0: a reviewer saw WARN
  403 lines and then `Updated 14 platform entries (7 skipped)`, and the
  `github:` tool had no `platforms.*` tables. So:

  1. Check that `gh` is installed and signed in, and use its token for this
     one command:

     ```sh
     if command -v gh >/dev/null 2>&1 && gh auth token >/dev/null 2>&1; then
       MISE_GITHUB_TOKEN="$(gh auth token)" mise lock
     else
       mise lock
     fi
     ```

  2. Without `gh`, proceed but warn the user that the anonymous limit is 60
     requests per hour per IP, shared with everything on that network, and
     recommend `gh auth login` or setting `MISE_GITHUB_TOKEN`. Offer the
     permanent global `credential_command` (`backends.md`); it changes global
     config, so it is the user's call.
  3. Afterwards read the summary for "skipped" and confirm every tool has
     `platforms.<p>` tables for each platform you need, for example with
     `grep -c 'platforms\.' mise.lock` against the number of tools times
     platforms, or by reading `mise.lock`. Re-run once the token or quota is
     fixed if anything is missing.
- Only registry-style backends with downloadable assets record URLs and
  checksums (aqua, github, gitlab, forgejo, http, s3, and similar). Backends
  that build or run package managers (cargo, go, gem, dotnet, spm) record the
  version only (docs).

### The `mise lock tool@X.Y.Z` trap

The docs say `mise lock node@24.11.0` locks an exact version without changing
a prefix request. Verified in 2026.10.7: it rewrites the entry's `specifiers`
to the exact version, so the prefix request in `mise.toml` no longer matches
the lockfile:

```text
mise.toml: ripgrep = "14"
$ mise lock --platform macos-arm64 ripgrep@14.1.0
version = "14.1.0", specifiers = ["14.1.0"]
$ mise ls --current ripgrep      -> 14.1.1   (lock ignored)
$ mise lock                      -> 14.1.1 with specifiers ["14"] (pin lost)
```

Under `--locked` the tool is then "not in the lockfile", and `mise x --locked`
printed only a warning before running a system `/usr/bin/jq` instead. With
exact pins the lock stays consistent, but a reviewer verified that
`mise lock jq@1.7.1` over `jq = "1.8.2"` also rewrote `mise.toml` to `"1.7.1"`,
so it is not harmless. Avoid the form entirely: for a deliberate version
change use `mise use tool@X.Y.Z` (writes config and lock together), and to
refresh entries use plain `mise lock` or `mise lock <tool>` (no version).
`mise upgrade jq@1.8.1` does not downgrade a newer current version.

## Installing from the lock

- `mise install --locked` (or `MISE_LOCKED=1`) fails when a tool has no
  entry, or no URL for this platform, instead of resolving fresh. Use it in CI.
- Project policy without environment variables: `[tool_config] locked = true`
  (docs). That is a config table; weigh the trust cost as with `[settings]`.
- A lockfile verifies **downloads**, not an already-installed tree. A restored
  `installs/` cache is trusted as is (docs), so cache downloads, not installs,
  where integrity matters (`ci.md`).
- Provenance recorded in the lock is trusted on later installs unless
  `locked_verify_provenance` or paranoid mode is on (docs). Review lock diffs.

## Upgrading and finding outdated tools

```sh
mise outdated            # tools with a newer version in range of the request
mise outdated --bump     # also show newer versions outside the request
mise upgrade --dry-run   # what would change
mise upgrade             # within-range upgrade; lock changes, mise.toml not
mise upgrade --bump      # also rewrite mise.toml to the new version
mise upgrade --bump jq   # one tool
```

Verified behavior:

- Exact pins do not appear in plain `mise outdated`; use `--bump`
  (`ripgrep 14.0.0 -> 15.2.0`).
- `mise upgrade --bump` keeps the precision of the request: an exact pin
  becomes the newest exact version. With a committed lock, **both**
  `mise.toml` and `mise.lock` are rewritten (`jq = "1.7.1"` -> `"1.8.2"`
  in both).
- With prefix requests, plain `mise upgrade` updates only the lock, leaving
  `mise.toml` as `"1"`. That is one more reason to pin exactly: the file you
  review then shows the change.
- Replaced versions are scheduled for pruning after 24 hours
  (`upgrade.prune_after`); `--prune` removes them now, `--no-prune` keeps them.
- For bots and update checks use `mise outdated --bump --json` and
  `mise upgrade --bump`. `mise lock --bump --dry-run --json` prints `[]` under
  exact pins (it only moves within the request's range), so it cannot detect
  updates there. For jobs reading untrusted branches with secrets, set
  `MISE_SAFE=1` (docs).
- `mise upgrade --bump` on an exact pin jumps to the newest release and can
  cross majors (for node, onto a non-LTS line). To stay within a major, use
  `mise use tool@"$(mise latest tool@<major>)"` instead.
- Other flags: `-i` interactive picker, `--local`/`--global` scope,
  `-x tool` exclude.

Workflow for a dependency-bump PR: `mise upgrade --bump`, run the project's
checks via `mise x --`/`mise run`, commit `mise.toml` and `mise.lock`
together, and mention major bumps in the PR description.

## Removing tools

- `mise unuse tool@<request-as-written>` removes the config entry and prunes
  installs nothing else needs. `mise uninstall tool@ver` keeps config.
- `mise prune [--dry-run]` and `mise ls --prunable` list unreferenced
  installs; prune keeps versions that any tracked config requires.
- After removing a tool, check `git diff mise.lock` for a leftover entry;
  not verified whether every removal path cleans the lock.

## Lockfile hygiene

- Checksum mismatch: do not delete checksums to make it pass. Investigate the
  asset, then `mise lock <tool>` and review `git diff mise.lock` (docs).
- Merge conflicts: resolve `mise.toml` first, accept either side of the lock,
  then run `mise lock` to regenerate and re-commit (docs).
- After changing a tool's backend, run `mise install --force <tool>` and
  `mise lock`: the legacy install layout reuses the old install directory for
  the short name and reports "already installed" (verified).
- Keep personal tools out of the committed lock with `mise.local.toml`. Add
  it, `mise.local.lock`, and `.mise/locks/mise.local/` to `.gitignore`.
