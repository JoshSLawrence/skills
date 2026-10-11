---
name: mise-tools
description: Install, pin, lock, upgrade, and run developer tools, CLIs, and language runtimes (terraform, jq, node, python, shellcheck, uv, go, ...) with mise - per project in mise.toml [tools] plus a committed mise.lock, or globally with mise use -g. Use this skill whenever the user needs or wants to install a dev tool, CLI, or runtime; hits "command not found" or the wrong version of one; sets up a repo's toolchain; edits, reviews, or upgrades [tools], .tool-versions, or mise.lock; chooses a backend (aqua, github, npm, pypi); sets up mise in CI; migrates from asdf, nvm, pyenv, or tfenv; or hits mise trust or untrusted-config errors - even if they never say "mise". Not for task authoring (mise-tasks skill) or project dependencies (packages a project imports, such as npm install lodash).
---

<!-- markdownlint-disable MD013 -->
<!-- Wide tables, code, and the frontmatter description are unwrappable. -->

# Managing dev tools with mise

mise is the default way to get developer tools, runtimes, and CLIs onto a
machine and into CI: one `mise.toml` says which versions a project uses, a
committed `mise.lock` makes that reproducible (checksums, URLs, provenance),
and `mise x --` or `mise run` guarantees the right binary runs. Your job is to
declare tools in a way that is pinned, reviewable, and the same for every
contributor and runner, and to make sure the tool that actually ran is the one
you intended.

Behavior in this skill was verified against mise 2026.10.7 unless marked as
coming from the docs. Docs:
<https://mise.jdx.dev/dev-tools/>. Details live in `references/`; read the one
you need rather than all of them:

- `references/versions-and-lockfile.md` - version syntax, what `mise use`
  writes, how `mise.lock` is created and kept current, upgrade and outdated
  flows, the `mise lock tool@X.Y.Z` trap
- `references/backends.md` - registry, backend order of preference, options
  per backend, `ubi:` migration, runtimes for package backends, tokens
- `references/config-and-trust.md` - config file hierarchy, `.tool-versions`
  and idiomatic files, trust rules and their effect on tools, PATH methods
- `references/ci.md` - GitHub Actions with `jdx/mise-action`, tokens,
  caching, other CI systems
- `references/troubleshooting.md` - diagnosing "command not found", wrong
  versions, lock errors, rate limits; asdf/nvm/pyenv migration
- `references/advanced.md` - `[tool_alias]`, tool stubs, self-updating tools,
  system installs, OCI, install layout, lazy tools

Out of scope here: writing tasks (use the `mise-tasks` skill) and `[env]`
configuration (a separate topic that this skill does not cover).

## When to use mise (and when not to)

| Need                                                  | Use                          |
| ----------------------------------------------------- | ---------------------------- |
| Dev tool, CLI, or runtime (terraform, jq, node, uv)   | mise                         |
| Project dependencies (package.json, pyproject, Cargo) | npm / uv / cargo             |
| GUI apps, system libraries (openssl, libpq)           | brew / apt / OS installer    |
| Repo already uses asdf, nvm, pyenv, tfenv, devbox     | Respect it; offer to migrate |

Do not silently replace another version manager: other contributors and CI
depend on it. Say what you found and offer a migration (see
`references/troubleshooting.md`). Personal tools the user wants everywhere go
in global config (`mise use -g`); tools a repo needs go in the repo's
`mise.toml`.

## Workflow

1. **Look first.** Check for `mise.toml`, `mise.local.toml`, `.tool-versions`,
   `mise.lock`, and idiomatic files (`.nvmrc`, `.python-version`). Run
   `mise ls --current` (what is selected, from which file) and
   `mise config ls`. If `.tool-versions` is the only config in the directory,
   `mise use` would append to it, and tools there are never locked: see
   "Config hierarchy" below. In a repo you did not write, read the config
   before the first `mise install`/`exec`/`run` (see Trust below).
2. **Choose the backend.** Registry short name first (`mise registry <tool>`,
   `mise search <word>`), then `aqua:` or `github:`, then a language package
   backend with its runtime declared. Details: `references/backends.md`.
3. **Pin and lock.** `mise use --pin tool@X.Y.Z` writes an exact version and
   installs it; if the repo has a `mise.lock`, mise updates it. First-time
   lock: `mise lock`, then commit `mise.toml` and `mise.lock` together. If the
   lock summary mentions skipped entries, see "The lockfile in practice".
4. **Run through mise** (`mise x -- <cmd>`, or `mise run`). See "Running tools
   as an agent" below.
5. **Verify.** `mise ls --current` shows the selected version and `mise which
   <bin>` the binary mise resolves. Check that `mise.lock` has a
   `platforms.<p>` table for every tool on every platform the team and CI use.
   `mise install --locked` passes locally whenever the tools are already
   installed, so the real proof is CI on a fresh runner.

## Pinning policy

Project `mise.toml` holds **exact versions** and the repo commits a
**`mise.lock`**. The two cover different risks:

- An exact version makes the intent obvious in review and keeps results the
  same across machines. A prefix such as `"1.7"` resolves against whatever is
  *installed* first, so two machines can get different binaries from the same
  request. `"latest"` drifts on its own schedule.
- The lockfile adds per-platform checksums, download URLs, and provenance, so
  a tampered or replaced release asset fails instead of installing.

```toml
[tools]
jq = "1.8.2"
node = "24.11.1"
shellcheck = "0.11.0"
```

Rules of thumb:

- `mise use tool` writes `"latest"` by default. In shared config, write an
  exact version instead. Bare prefixes and `latest` do not belong there.
  - Newest release: `mise use --pin tool@latest`.
  - Newest within a major: `mise use tool@"$(mise latest tool@24)"`.
  - Trap: `mise use --pin tool@24` writes the *installed* match of `24`, not
    the newest. Verified: with jq 1.7.1 installed, `mise use --pin jq@1`
    wrote `"1.7.1"` while `mise latest jq@1` said 1.8.2. Only `@latest`
    consults the remote list.
  - Convert an existing `latest` entry without changing what runs:
    `mise use tool@"$(mise current tool)"`.
- Bump on purpose: `mise outdated --bump` to see candidates,
  `mise upgrade --bump [tool]` to apply. With exact pins, `--bump` rewrites
  both `mise.toml` and `mise.lock`. Review and commit the diff as one change.
  `--bump` on an exact pin jumps to the newest release, crossing majors (node
  to a non-LTS line, say). To stay in a major, use the within-major recipe
  above instead.
- Global or personal config (`mise use -g`, `mise.local.toml`) can be looser;
  `latest` or a major version is fine for tools nobody else depends on.
- Brand-new releases are invisible for 24 hours by default (a supply-chain
  cooldown, `minimum_release_age`). Leave it alone; if the user needs a
  release that is hours old, ask first and use `--minimum-release-age 0s` for
  that one command.

## The lockfile in practice

Behavior verified: with the `lockfile` setting unset (the default), mise
**maintains an existing `mise.lock` but never creates one**. Create it once,
deliberately:

```sh
mise lock
git add mise.toml mise.lock
```

This resolves every tool for the default platform set and installs nothing.
Prefer the default set over `--platform` restrictions: verified, with a lock
holding only `linux-x64`, a plain `mise install` on macOS added `macos-arm64`
entries, so a restricted lock churns in diffs. Use `--platform` only when a
narrow set is genuinely wanted.

Locking calls the GitHub API for `github:` tools. A rate-limited `mise lock`
**exits 0** with WARN lines and an incomplete lock (a reviewer saw a `github:`
tool with no `platforms.*` tables). Run it with a token when `gh` is signed
in, and always inspect the result:

```sh
if command -v gh >/dev/null 2>&1 && gh auth token >/dev/null 2>&1; then
  MISE_GITHUB_TOKEN="$(gh auth token)" mise lock
else
  mise lock
fi
```

Without `gh`, proceed but warn the user that the anonymous limit is 60
requests per hour per IP, shared with everything on that network, and
recommend `gh auth login` or setting `MISE_GITHUB_TOKEN`. Then check that the
summary shows no "skipped" entries and that every tool has `platforms.<p>`
tables. See `references/backends.md` for the permanent `credential_command`
option, which changes global config and is the user's call.

Why not `[settings] lockfile = true` in `mise.toml`? Any `[settings]` table
makes the file require trust, and an untrusted config makes read-only commands
(`mise ls`, `mise env`) hard-fail in non-interactive shells. A plain `[tools]`
table needs no trust, so keeping `mise.toml` to `[tools]` keeps it friction
free for newcomers and agents.

Verified with exact pins in a project that already has a `mise.lock`:

- `mise use --pin shfmt@3.10.0` adds the tool to `mise.toml` **and** adds its
  entry to `mise.lock`, for the platforms already present in the lockfile.
- `mise upgrade --bump jq` rewrites `jq = "1.7.1"` to `"1.8.2"` in
  `mise.toml` and the `version` and `specifiers` in `mise.lock`.

Two traps:

- Tools declared **only** in `.tool-versions` are never locked
  (`mise lock` reports "No tools configured to lock"). Use `mise.toml`.
- **Do not run `mise lock tool@X.Y.Z`.** The docs say it locks an exact
  version without touching the request. In 2026.10.7 against a prefix request
  it rewrites the entry's `specifiers`, the prefix no longer matches, and the
  pin is silently ignored. Against an exact pin, a reviewer verified that
  `mise lock jq@1.7.1` over `jq = "1.8.2"` rewrote `mise.toml` to `"1.7.1"`
  too. For a deliberate version change use `mise use tool@X.Y.Z`; to refresh
  entries use plain `mise lock [tool]`.

Install from the lock with `mise install --locked` (CI should): it fails
when a tool has no entry instead of resolving fresh. More in
`references/versions-and-lockfile.md`.

## Backends in one table

| Situation                                      | Use                              |
| ---------------------------------------------- | -------------------------------- |
| Tool has a registry short name                 | `mise use --pin jq@1.8.2`        |
| Not in registry, GitHub releases ship binaries | `github:owner/repo`              |
| Not in registry, aqua registry has a recipe    | `aqua:owner/repo`                |
| Only distributed as a package                  | `npm:`, `pypi:`, `cargo:`, `go:` |
| Existing `ubi:` entry                          | Migrate to `github:`             |
| Existing or proposed `asdf:` plugin            | Avoid; look for another backend  |

- Check what a short name resolves to: `mise registry jq` (ordered backend
  list) and `mise tool jq` (backend, security features). Some short names
  resolve to a package backend (verified: `mise registry prettier` shows
  `npm:prettier`), so if the result is `npm:`, `pypi:`, `cargo:`, or `go:`,
  declare the runtime too.
- A package backend needs its runtime declared in the same `[tools]` table:
  `npm:` needs `node`, `cargo:` needs `rust`, `go:` needs `go`, `pypi:` needs
  `uv` (or `python`). Verified: `npm:prettier` installs without node but
  fails at run time with `node: not found`.
- Do not add new `ubi:` entries: the backend is deprecated and is removed in
  mise 2027.1.0. Use `github:`.
- Prefer `pypi:` over `pipx:` for new entries. `pipx:` is an alias, but mise
  treats `pipx:cowsay` and `pypi:cowsay` as different tools (separate installs
  and lock entries), so do not rename existing entries casually.

## Running tools as an agent

Agent shells are usually non-interactive and have no prompt or `cd` hooks, so
mise's activation never fires. Verified in Claude Code's Bash tool: it
inherits a PATH snapshot from the user's interactive shell, so
`cd project && node` runs whatever version was first on that snapshot (often
the user's global one), not the project's pin. Worse, the fallback is silent:
shims and `mise x` run a system binary of the same name (for example macOS's
`/usr/bin/jq`) when the tool is not configured.

Therefore:

- **Run project tools through mise**: `mise x -- terraform plan`,
  `mise x -- node script.js`, or `mise run <task>` for tasks. It needs no
  setup, honors the config in the current directory, and installs missing
  tools.
- **For several commands at once**, `mise x -c 'cmd1 && cmd2'` runs a shell
  string under one resolved environment and does not depend on which shell
  the harness uses (verified: `mise x -c 'jq --version && shfmt --version'`
  ran both from the project pins).
- **Alternatively activate once** at the top of the same call:

  ```sh
  eval "$(mise activate bash)"
  terraform fmt -check && terraform validate
  ```

  Pass the shell actually in use (`bash` or `zsh`; check `echo "$SHELL"`).
  Verified: `activate` works in non-interactive `bash -c` and `zsh -fc`, and
  its `cd` wrapper switches tools mid-script. Whether the activation survives
  into the next command depends on the harness; where each call is a fresh
  shell (as in Claude Code), repeat it per call.
  `eval "$(mise env -s bash)"` is the one-shot variant: it exports PATH for
  the current directory only and does not follow later `cd`s.
- **Check what actually ran.** `mise which <bin>` prints the resolved path and
  errors loudly when the tool is not configured here; `mise ls --current`
  shows versions and the file that chose them. Distrust bare `--version`
  output that disagrees with `mise.toml`.
- **Do not edit the user's shell rc** to add activation unless they ask.
- Installing a missing tool on the user's behalf is fine in a project whose
  config you have checked (see Trust). Changing global config
  (`mise use -g`) changes their machine, so say so first.

## Trust and safety

- Never run `mise trust` on the user's behalf without asking. It tells mise
  to execute that config's hooks, templates, and env logic.
- `mise install`, `mise exec`, and `mise run` **trust implicitly** every
  non-global config they load, so the first one is effectively `mise trust`.
  In a repo the user did not author, read its mise config first. If it holds
  anything beyond plain version strings (`postinstall`, `[hooks]`, `[env]`
  with `exec()` or templates, `include`, unusual URLs or backends), ask the
  user before running any of those commands.
- Plain `[tools]` entries (version strings only) load without trust. Option
  tables, `[env]`, and `[settings]` need it (verified), as do `[tool_alias]`
  and `[hooks]` (docs). An
  untrusted config fails read-only commands such as `mise ls` with "Config
  files in ... are not trusted" in non-interactive shells. Show the user what
  the file contains, then ask.
- Never put tokens in `mise.toml`. Use environment variables or a credential
  command in global config (`references/backends.md`).
- Supply chain: prefer backends with checksums and attestations (`aqua:`,
  `github:`), keep the lockfile committed, and review `mise.lock` diffs the
  way you review dependency bumps.

## Config hierarchy at a glance

Highest precedence first, per directory: `mise.local.toml` (personal; add it
to `.gitignore`), `mise.toml`, `.config/mise/...` variants, then
`.tool-versions`.
Directories closer to the working directory win over parents, and the global
`~/.config/mise/config.toml` is the base. Per tool, the nearest entry replaces
the whole entry, options included.

- `mise use` writes the lowest-precedence file in the nearest directory that
  has mise config, creating `mise.toml` in the current directory if none
  exists. That is usually `mise.toml`, but if `.tool-versions` is the only
  config there, `mise use` appends to it (verified), and tools in
  `.tool-versions` are never locked. Pass `--path mise.toml` (verified: it
  creates `mise.toml` and writes there), or run `mise generate config
  --tool-versions .tool-versions` first to convert. Use `-e local` for
  `mise.local.toml` and `-g` for global.
- Idiomatic files (`.nvmrc`, `.python-version`, `.terraform-version`) are
  **off by default**. Prefer `mise.toml`, which can be locked; enable an
  idiomatic file only when the project already depends on it
  (`references/config-and-trust.md`).
- `MISE_<TOOL>_VERSION=1.2.3` overrides config for one command, handy for
  trying a version without editing files.

Env configuration is outside this skill, with two tool-adjacent exceptions
worth knowing exist: `_.path` (add directories to PATH) and
`_.python.venv` (auto-activate a Python virtualenv; docs only). Both live in
the `[env]` table, which requires trust like any non-`[tools]` content.

## CI in brief

Install tools in CI from the same `mise.toml` and `mise.lock`:

```yaml
on: pull_request

permissions:
  contents: read

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: jdx/mise-action@2d8d4cafcbd33be2ea37d2b6f5ad595363d1f1ca # v5.1.1
      - run: mise run ci
```

Pin the action to a full commit SHA with a version comment, as above. With a
`mise.lock` present the action installs with `--locked`. See
`references/ci.md` for tokens, cache keys, and non-GitHub CI.

## Checklist before you finish

- [ ] Tool belongs in mise (not a project dependency, GUI app, or system lib)
- [ ] Repo's existing tool manager respected, or migration offered
- [ ] Backend chosen registry-first; package backends have their runtime
- [ ] Exact versions in project `mise.toml`; no `latest` or bare prefixes
- [ ] `mise.lock` created or updated and committed with `mise.toml`
- [ ] Lock summary shows no skipped entries; each tool has `platforms.<p>`
      tables for every runner
- [ ] `mise ls --current` shows the pins; CI (fresh runner) installs with
      `--locked`
- [ ] Ran the tool through `mise x --` (or `mise run`) and confirmed with
      `mise which` that the mise-managed binary ran
- [ ] No `mise trust`, global config change, or token in files without the
      user's say-so
- [ ] README/CONTRIBUTING setup instructions mention `mise install`
