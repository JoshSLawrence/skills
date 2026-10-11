<!-- markdownlint-disable MD013 -->
<!-- Wide tables and code samples are unwrappable. -->

# Troubleshooting and migration

Read this when a tool is missing, the wrong version ran, or an install or lock
command failed; also when moving a repo from asdf, nvm, pyenv, or tfenv.
Behavior verified against mise 2026.10.7 unless marked "docs". Sources:
<https://mise.jdx.dev/troubleshooting.html>,
<https://mise.jdx.dev/dev-tools/comparison-to-asdf.html>.

## Contents

- Diagnose in this order
- Symptom table
- Settings that change behavior
- Migrating from other managers

## Diagnose in this order

```sh
mise ls --current        # selected versions, source file, (missing) marker
mise config ls           # config files that apply, lowest precedence first
mise which <bin>         # the binary mise resolves; errors if not active here
mise tool <tool>         # backend and security features
mise doctor              # activation, shims, dirs, config, problems
```

Then, for install problems, rerun with `MISE_DEBUG=1 mise install <tool>` (or
`-v`). Strip credentials from any output before sharing it.

## Symptom table

| Symptom                                                           | Likely cause and fix                                                                                                                                                         |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `command not found` for a project tool                            | Shell not activated (agent shells usually are not). Run `mise x -- <cmd>`, or `mise install` if the tool shows `(missing)`                                                   |
| Bare `node`/`terraform` prints the wrong version                  | Global or system binary ran. Use `mise x --`; check `mise which`                                                                                                             |
| `jq --version` shows an Apple or distro version                   | Silent fallback to a system binary; the tool is not configured in this directory                                                                                             |
| `Config files in <path> are not trusted`                          | Read the config, ask the user, then `mise trust`; see `config-and-trust.md`                                                                                                  |
| `<tool> not found in mise tool registry`                          | Use an explicit backend id (`github:owner/repo`, `aqua:...`); `mise search`                                                                                                  |
| `<tool>@<req> is not in the lockfile` (with `--locked`)           | Run `mise lock` (add `--platform`) and commit; do not use `mise lock tool@X.Y.Z`                                                                                             |
| `No lockfile URL found for <tool> on platform <p>`                | The lock lacks that platform: `mise lock --platform <p>`                                                                                                                     |
| 403 or `GitHub rate limit exceeded`                               | Anonymous quota (60 per hour per IP, shared) used up. Set `MISE_GITHUB_TOKEN` or `GITHUB_TOKEN` (`backends.md`)                                                              |
| Lock written but a tool has no `platforms.<p>` entries            | A rate-limited `mise lock` exits 0 with an incomplete lock. Look for "skipped" in its summary; fix the token (`gh auth login` or `MISE_GITHUB_TOKEN`) and re-run `mise lock` |
| `Checksum mismatch`                                               | Never delete the checksum. Investigate the asset; then `mise lock <tool>` and review `git diff mise.lock`                                                                    |
| Newest release not offered                                        | `minimum_release_age` hides releases under 24 hours old; or the remote version list cache (1 hour): `mise cache clear <tool>`                                                |
| `mise install` says "already installed" but version is old        | A prefix matched an installed version. Pin exactly, then `mise install`                                                                                                      |
| After switching a backend, old behavior persists                  | The old install directory is reused: `mise install --force <tool>`                                                                                                           |
| `exec: node: not found` from an `npm:` tool                       | Declare `node` in `[tools]`                                                                                                                                                  |
| `missing: <tool>@<ver>` warning                                   | Declared but not installed: `mise install`                                                                                                                                   |
| `No version is set for shim` / `Tool not installed for shim`      | The cwd does not configure the tool, or it is not installed: `mise ls --current`, `mise install` (docs)                                                                      |
| Untrusted-config error from `mise ls`/`mise env` in a fresh clone | Plain `[tools]` loads without trust; option tables, `[env]`, `[settings]` do not                                                                                             |

Never fix a failure by deleting `mise.lock`, loosening a pin to `latest`, or
disabling checks (`--no-verify`-style settings) without telling the user what
changed and why.

## Settings that change behavior

Defaults, verified with `mise settings get`: `lockfile` unset, `locked`
false, `pin` false, `experimental` false, `paranoid` false, `auto_install`
true, `exec_auto_install` true, `not_found_auto_install` true,
`not_found_system_fallback` true, `idiomatic_version_file_enable_tools` empty,
`fetch_remote_versions_cache` 1h, `upgrade.prune_after` 24h,
`use_versions_host` true, `registry_floating` false. `minimum_release_age` is
unset but a 24-hour default applies.

- `minimum_release_age` accepts durations or dates, per tool, via
  `--minimum-release-age`, or `minimum_release_age_excludes = ["trivy"]`; `0s`
  disables it. It does not apply to exact versions, locked entries, or
  installed matches (docs).
- Settings live in global config (`mise settings set ...` edits **global**
  config; use an isolated `MISE_GLOBAL_CONFIG_FILE` when experimenting) or a
  `[settings]` table in a project file (which then needs trust).

## Migrating from other managers

Offer, do not impose. Say what you found, what would change, and that other
contributors and CI need updating too.

### asdf

- `mise` reads `.tool-versions` and accepts asdf names (`nodejs`, `golang`).
  Convert with `mise generate config --tool-versions .tool-versions
  --dry-run`, then without `--dry-run`. Verified output:

  ```toml
  [tools]
  jq = "1.7.1"
  node = "22.1.0"
  ```

- Run `mise lock`, commit `mise.toml` and `mise.lock`, and remove
  `.tool-versions` once nobody needs it (tools only in `.tool-versions` are
  never locked).
- mise does not reuse asdf installs. After migrating, ask the user to remove
  asdf shims and activation from their shell rc (their file). A leftover
  `~/.asdf/shims` on PATH can still shadow tools (observed).
- Command map (docs): `asdf install` -> `mise install`; `asdf set`/`local` ->
  `mise use`; `asdf set -u`/`global` -> `mise use -g`; `asdf list all` ->
  `mise ls-remote`; `asdf current` -> `mise ls --current`; `asdf exec` ->
  `mise exec --`; `asdf plugin add` is usually unnecessary. `mise set` sets
  env vars, not versions (see the `mise-env` skill).
- A shared `.tool-versions` that mise reads must hold exact versions (no
  `prefix:`, `sub-`, or backend ids).

### nvm, pyenv, tfenv, and similar

- Move the version from `.nvmrc` / `.python-version` / `.terraform-version`
  into `mise.toml` with `mise use --pin node@<version>`. Leave the old file in
  place if Docker, CI, or editors still read it, and keep both in sync (or
  enable that idiomatic file in mise, accepting that it cannot be locked).
- Remove the old manager's shell hooks only with the user's consent. Both
  managers editing PATH produces confusing results; check with
  `mise which <bin>`.
- Update README and CONTRIBUTING setup steps to `mise install` in the same
  change so docs do not drift.

### devbox, nix, brew-only setups

Not covered by a migration command. Compare what each tool provides, keep
system libraries where they are, and move only dev tools and runtimes that
mise's registry covers.
