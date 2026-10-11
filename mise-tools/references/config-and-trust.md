<!-- markdownlint-disable MD013 -->
<!-- Wide tables and code samples are unwrappable. -->

# Config files, trust, and getting tools on PATH

Read this when deciding where a tool declaration belongs, handling a "not
trusted" error, or choosing between activate, shims, and `mise x`. Behavior
verified against mise 2026.10.7 unless marked "docs". Sources:
<https://mise.jdx.dev/configuration.html>,
<https://mise.jdx.dev/security.html>,
<https://mise.jdx.dev/shell-setup.html>.

## Contents

- Config files and precedence
- `.tool-versions` and idiomatic version files
- Environment overrides
- Trust
- PATH methods: activate, shims, exec, env
- Silent fallback to system binaries

## Config files and precedence

Per directory, highest precedence first (docs): `mise.local.toml`,
`mise.toml`, `mise/config.toml`, `mise/conf.d/*.toml`, `.mise/config.toml`,
`.config/mise.toml`, `.config/mise/config.toml`, and finally `.tool-versions`.
Dotfile variants (`.mise.toml`) override the non-dot names.

Load order: system `/etc/mise`, then global `~/.config/mise/config.toml`, then
every directory from `/` down to the working directory (deeper wins). Setting
`MISE_GLOBAL_CONFIG_FILE` replaces the global files with one file, which is
how to isolate experiments.

- `[tools]` merges **per tool**: the nearest file's entry replaces that tool's
  whole entry, including options; other tools are inherited (docs).
- `mise config ls` lists the files that apply. `mise ls --current` shows the
  selected version and the file that chose it. Use both when a version is
  not what you expect.
- Where each kind of tool belongs:

  | Tool                                    | File                        |
  | --------------------------------------- | --------------------------- |
  | Needed to build, test, or lint the repo | `mise.toml` (committed)     |
  | Personal preference in one repo         | `mise.local.toml` (ignored) |
  | Wanted everywhere, not tied to a repo   | `mise use -g`               |
  | Only for CI or a special environment    | `mise.<env>.toml`           |

- Gitignore `mise.local.toml`, `mise.local.lock`, and `.mise/locks/mise.local/`
  (docs).
- `min_version = "2026.1.0"` at the top of `mise.toml` fails fast on an old
  mise (docs). It loads without trust.
- Editors can validate with the schema at
  <https://mise.jdx.dev/schema/mise.json> (docs).

`mise use` write targets are in `versions-and-lockfile.md`.

## `.tool-versions` and idiomatic version files

- `.tool-versions` is read like `mise.toml`, parents and `~/.tool-versions`
  included. `mise.toml` wins within a directory. **Tools declared only there
  are never locked** (verified: `mise lock` -> "No tools configured to
  lock"). Keep an existing one if asdf users still need it, but prefer
  `mise.toml` and do not maintain both with different versions.
- `mise generate config --tool-versions .tool-versions [--dry-run]` converts
  one to `mise.toml` (verified; it maps `nodejs` to `node`).
- Idiomatic files (`.nvmrc`, `.python-version`, `.go-version`,
  `.terraform-version`, `rust-toolchain.toml`, ...) are **off by default**.
  Verified: with `22` in `.nvmrc`, `mise ls --current` listed no node until
  `MISE_IDIOMATIC_VERSION_FILE_ENABLE_TOOLS=node` was set. Persist it per user
  with `mise settings add idiomatic_version_file_enable_tools node`, or in
  config under `[settings]`. Enable it only when the project's other tooling
  reads the same file (a Docker build reading `.nvmrc`, say), because these
  files cannot be locked the way `mise.toml` entries can.
- Reading `go X.Y` from `go.mod` and `cmake_minimum_required` as version
  sources is deprecated and stops in 2026.11.0 (docs).

## Environment overrides

`MISE_<TOOL>_VERSION=1.7.1 mise x -- jq --version` runs with that version for
one command regardless of config (verified: ran 1.7.1 while `mise.toml` said
1.8.1). Use it to test a version before editing files.

## Trust

Trust exists because a mise config can run code (templates, hooks, env
scripts, `postinstall`).

Verified rules:

- Loads **without** trust: `min_version` and `[tools]` whose values are plain
  version strings or arrays. `.nvmrc` and other idiomatic files never need
  trust.
- Needs trust: tool option tables (`{ version = ..., os = [...] }`),
  `[env]`, `[settings]`, `[tool_alias]`, `[hooks]`, `include`, and templating.
- An untrusted file that needs trust makes read-only commands fail in a
  non-interactive shell: `mise ERROR Config files in .../mise.toml are not
  trusted. Trust them with 'mise trust'.` (An interactive terminal gets a
  prompt.)
- **Implicit trust:** `mise install`, `mise exec`, `mise run`, and `mise watch`
  record trust for every non-global config they load; `mise use` and
  `mise set` trust the file they write. After `mise exec` ran in an untrusted
  directory, `mise trust --show` reported it trusted.
- `CI` set: every config is treated as trusted but nothing is recorded.
  `MISE_YES=1`: answers yes and records trust.
- `MISE_PARANOID=1` (global-only `paranoid = true`): every non-global config
  needs explicit, content-hashed trust, even tools-only; implicit trust and
  `CI` no longer apply.
- `MISE_SAFE=1` refuses tasks, `exec()` templates, and plugin installs and
  skips hooks, intended for bots resolving versions from untrusted branches
  (docs).

What to do as an agent:

1. In an unfamiliar repo, read `mise.toml`/`mise.local.toml` and
   `.config/mise` before running `mise install`, `exec`, or `run`: look for
   `postinstall`, `[hooks]`, `[env]` with `exec()`/templates, `include`, and
   tool options pointing at odd URLs.
2. If a read-only command fails with "not trusted", show the user what is in
   the file and ask whether to run `mise trust`. Do not trust to make the
   error go away.
3. Trust is per config root; symlinked configs need the real path trusted
   (docs). `mise trust --show` reports status; `--untrust` reverses it.
4. Users can pre-trust a workspace they own with `trusted_config_paths` in
   global config (docs). Do not edit their global config to do it unprompted.

## PATH methods: activate, shims, exec, env

| Method                                 | Use for                                                       |
| -------------------------------------- | ------------------------------------------------------------- |
| `mise activate <shell>`                | An interactive shell, or one scripted Bash call; follows `cd` |
| Shims dir on PATH (`activate --shims`) | IDEs, cron, anything that never runs `activate`               |
| `mise exec` / `mise x -- <cmd>`        | One command and its children; works with no setup             |
| `mise run <task>`                      | Tasks (see the `mise-tasks` skill)                            |
| `eval "$(mise env -s bash)"`           | Export PATH (and env) once for the current directory          |

Verified details:

- `mise x -- jq --version` honors the cwd's config and auto-installs missing
  tools. `mise x jq@1.8.2 -- jq --version` forces a version for that command;
  `mise x -c 'cmd args'` runs a shell string.
- `eval "$(mise activate bash)"` and `eval "$(mise activate zsh)"` both work in
  non-interactive shells (`bash -c`, `zsh -fc`): the tool resolves to
  `.../installs/jq/<ver>/jq` immediately, and a `cd` to another project
  switches versions in the same script. `builtin cd` bypasses the hook;
  `eval "$(mise hook-env -s bash)"` refreshes manually.
- Shims resolve per call from the cwd, so `cd a && jq` and `cd ../b && jq` can
  differ. They do not export `[env]` into the shell. mise creates shims
  automatically on install; run `mise reshim` only after another tool adds
  binaries (for example `npm i -g`).
- `mise which <bin>` prints the real path. `mise where <tool>` prints the
  install directory. `mise bin-paths` lists the dirs mise would put on PATH.
- Shims re-resolve config on every call, so wrap loops in one
  `mise exec -- bash script.sh` rather than calling a shim thousands of times
  (docs).
- `mise doctor` says whether activation is in place and recommends shims for
  non-interactive setups.

For users, activation belongs in their shell rc (`eval "$(mise activate zsh)"`
in `~/.zshrc`); that is their file, so suggest it rather than editing it.

## Silent fallback to system binaries

Verified: a shim for a tool the current directory does not configure runs the
next binary on PATH. Outside any project, the jq shim ran macOS's
`/usr/bin/jq` (`jq-1.7.1-apple`), and in a directory without ripgrep the rg
shim ran Homebrew's. `mise x -- jq` in a directory with no jq configured did
the same. `mise x --locked` with an unlocked request also fell back, after
only a warning.

- `mise which jq` in that directory fails loudly (`jq is a mise bin however it
  is not currently active`), which makes it the right check.
- To make shims fail instead, a user can set `not_found_system_fallback =
  false` and `not_found_auto_install = false` (global settings).
- `shims.exclude = ["python3", ...]` keeps OS-shadowing names out of shims
  (docs).
