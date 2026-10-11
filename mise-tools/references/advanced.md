<!-- markdownlint-disable MD013 -->
<!-- Wide tables and code samples are unwrappable. -->

# Less common topics

Read this for aliases, tool stubs, self-updating tools, system installs, OCI
images, install layout, and lazy tools. Behavior verified against mise
2026.10.7 unless marked "docs". Sources: <https://mise.jdx.dev/dev-tools/>
pages for each topic.

## Contents

- Tool aliases
- Tool stubs
- Self-updating tools
- System and shared installs
- OCI images (experimental)
- Install layout
- Lazy tools, wrappers, and deps

## Tool aliases

`[tool_alias]` renames a backend or defines version aliases:

```toml
[tool_alias]
jq = "github:jqlang/jq"

[tool_alias.node.versions]
project-lts = "24"
```

- Verified: `mise tool jq --backend` then prints `github:jqlang/jq`, and
  `mise ls --current` shows the alias name next to the version.
- The old `[alias]` table is deprecated (verified warning: use
  `[tool_alias]`).
- Pitfall (verified): switching a short name's backend through an alias reuses
  the existing install directory from the old backend and reports "already
  installed"; run `mise install --force <tool>` afterwards.
- One alias per binary when several tools come from one GitHub repo, each with
  `matching` or `matching_regex`; two entries for the same repo with
  different `matching` collapse into one (docs).
- `mise tool-alias ls node` lists node's aliases. `mise tool-alias set` and
  `unset` edit **global** config, so avoid them for project work.
- Registry aliases (`rg` -> `ripgrep`) and `[shell_alias]` are unrelated.
- `[tool_alias]` needs trust.

## Tool stubs

A stub is an executable TOML file that installs a tool on first run, handy for
`bin/` scripts in repos:

```toml
#!/usr/bin/env -S mise tool-stub
tool = "jq"
version = "1.7.1"
```

- Verified: running `./bin/jq --version` installed jq 1.7.1 and printed it.
  `mise install` ignores stubs.
- The stub needs `mise` on PATH (verified: without it the shebang fails with
  `env: mise: No such file or directory`). `mise generate tool-stub ... --bootstrap`
  produces a script that installs mise itself (docs).
- Generate stubs with URLs and checksums:
  `mise generate tool-stub ./bin/shellcheck --platform-url <url>` produced
  `[platforms.macos-arm64]` with `url`, `checksum = "blake3:..."`, `size`
  (verified). Repeat `--platform-url` per platform; `--checksum-algorithm
  sha256` changes the hash; `--lock` writes into the project `mise.lock`
  (docs).
- Running a stub records it so `mise prune` keeps its version (docs). If you
  only need one command with a specific version, `exec mise exec node@24 --
  node "$@"` in a wrapper script is simpler (docs), and `lazy = true` in
  `[tools]` covers "install on first use" for a set of tools.

## Self-updating tools

Some tools (coding agents among them) update themselves. When one is installed
by mise, do not write into its install directory. Use `mise outdated --global
<tool> --json` to check and `mise upgrade --global <tool>` to update, then
re-exec through `mise x -- <tool>` (docs). A mise install is recognizable by a
`.mise.backend.toml` in the install's parent directory (verified for the
default layout). For agents: if a mise-installed CLI offers to self-update,
prefer `mise upgrade <tool>`; it respects `minimum_release_age` and the lock.

`auto_update` (global config only) makes tools update on launch via shim or
exec, never in CI, offline, or with `locked = true` (docs). It conflicts with
exact pins, so do not enable it for project tools.

## System and shared installs

`mise install --system <tool>` installs to `/usr/local/share/mise/installs`
(docs, not run: it needs sudo). Run it as a normal user; mise elevates only
for the move, so avoid `sudo mise ...`. Elevated installs support
aqua/github/gitlab/forgejo/http/s3 tools without `postinstall`. The version
still comes from config (for example `/etc/mise/config.toml`). Related:
`mise reshim --system`, `--shared <DIR>` with `shared_install_dirs`, and
`system_packages.sudo = false` to forbid sudo. Changing a machine's system
config is the user's decision, so ask first.

## OCI images (experimental)

`mise oci build|run|push` packs the `mise.toml` tools into a container image,
one layer per tool. It needs `experimental = true`, a Linux host of the image
architecture (it copies host installs; macOS builds produce `Exec format
error`), and tools installed first; Docker or Podman is needed only for `run`.
The `[oci]` table sets `from`, `tag`, `workdir`, and more, and global config is
excluded unless `--include-global` (docs). Not verified here (macOS host), so
test before recommending it, and treat the feature as unstable.

## Install layout

Default (legacy) layout, verified:

```text
installs/jq/.mise.backend.toml
installs/jq/1.8.2/
installs/jq/1 -> ./1.8.2
installs/jq/latest -> ./1.8.2
installs/github-burnt-sushi-ripgrep/14.1.1
installs/npm-prettier/3/node_modules/.bin/prettier
```

- Registry short names get `installs/<short>/`; explicit backends get a
  slugged directory. PATH may go through request-named links such as
  `jq/1` or `latest`.
- Experimental `install_layout = "identity"` (needs `experimental = true`)
  keys installs by label and hash with `.mise-install.toml` receipts, so
  variants coexist and a short name shares installs with its explicit id
  (docs, not run).
- Default directories (override with `MISE_DATA_DIR`, `MISE_CONFIG_DIR`,
  `MISE_CACHE_DIR`, `MISE_STATE_DIR`): data `~/.local/share/mise`, config
  `~/.config/mise`, cache `~/.cache/mise`, state `~/.local/state/mise`.
  Overrides are honored (verified); that is how to test mise without touching
  a real setup.

## Lazy tools, wrappers, and deps

All docs only:

- `lazy = true` (plus `lazy_bins` for non-registry tools) installs on first
  command use; `mise install` skips lazy tools unless `--include-lazy`.
- `[wrappers]` define command wrappers (`terraform = "tofu"`) and need
  `mise reshim`.
- `mise deps` / `[deps]` is experimental and runs project package installs
  (npm ci, uv sync) when lockfiles change. That is dependency management,
  distinct from `[tools]`; keep it out of scope unless the user asks.
