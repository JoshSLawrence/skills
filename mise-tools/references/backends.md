<!-- markdownlint-disable MD013 -->
<!-- Wide tables and code samples are unwrappable. -->

# Registry, backends, and tokens

Read this when adding a tool that is not a plain registry short name, picking
between backends, or migrating off `ubi:`/`asdf:`. Behavior verified against
mise 2026.10.7 unless marked "docs". Sources:
<https://mise.jdx.dev/registry.html>,
<https://mise.jdx.dev/dev-tools/backends/>.

## Contents

- Finding a tool
- Order of preference
- Backend notes
- Go toolchain bypass
- Declaring runtimes for package backends
- Migrating `ubi:` to `github:`
- Tool options
- GitHub tokens

## Finding a tool

```sh
mise registry jq        # aqua:jqlang/jq asdf:mise-plugins/asdf-jq
mise search jq          # fuzzy search of registry names and descriptions
mise tool jq            # backend, security features (checksum, attestations)
mise ls-remote jq       # versions available
```

- The registry maps a short name to an ordered backend list, bundled with each
  mise release. The first backend enabled on this platform wins.
- A short name can carry options (for example `aws-cli` sets
  `symlink_bins = true`); writing the raw identifier drops them (docs). Prefer
  the short name when one exists.
- An unknown name fails cleanly (`notarealtool123 not found in mise tool
  registry`) and writes nothing. Then use an explicit backend id.
- A tool's backend can also come from `[tool_alias]`, the lockfile, or the
  `MISE_BACKENDS_<TOOL>` environment variable; `mise tool <t> --backend` shows
  the result.

## Order of preference

1. **Registry short name.** It already picked a backend and its options.
2. **`aqua:owner/repo`** (checksums, attestations, and signature checks done
   natively; no aqua CLI needed) or **`github:owner/repo`** (release assets,
   autodetected by OS and architecture; digest or checksum file and GitHub
   attestations on github.com). `gitlab:` and `forgejo:` share the
   implementation.
3. **`http:` / `s3:`** for self-hosted artifacts.
4. **Language package backends** (`npm:`, `pypi:`, `cargo:`, `go:`, `gem:`,
   `dotnet:`, `spm:`, `conda:`) when the tool ships only as a package or you
   need extras. Declare the runtime too.
5. **Plugins** (`vfox:`, `asdf:`) only for custom install logic. They run
   plugin code. `asdf:` is legacy and never works on Windows; do not add new
   `asdf:` entries.

Why this order: the closer to a prebuilt, checksummed release asset, the
faster the install, the less code executes at install time, and the more the
lockfile can record (URL, checksum, provenance per platform).

## Backend notes

| Backend          | Notes                                                                                                                                                                                               |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| core             | Built in: node, python, go, ruby, java, rust, bun, deno, and others. `core:node` forces the built-in.                                                                                               |
| aqua             | Registry recipes. Options like `symlink_bins`, `vars`, `libc`, `prerelease`.                                                                                                                        |
| github           | Lists only releases that have assets; a repo with tags only has no versions. A repo-name tag prefix (`jq-`) is stripped automatically. Verified: `mise ls-remote github:jqlang/jq` ends at `1.8.2`. |
| http             | Needs `url`; `version_list_url` is required for `latest` and `ls-remote`. A fixed URL makes the version a label only.                                                                               |
| npm              | Installs without node (embedded installer) but most CLIs need `node` at run time. Reads the user's `~/.npmrc`, not the project's.                                                                   |
| pypi             | Uses uv (pipx fallback). `pipx:` is an alias, but a different tool to mise.                                                                                                                         |
| cargo            | Needs `rust`; uses cargo-binstall if present, otherwise compiles. Git sources use `@tag:`/`@branch:`/`@rev:`.                                                                                       |
| go               | `go install`; module path including `/cmd/x` or `/v4`; needs `go` in config.                                                                                                                        |
| gem, dotnet, spm | Need ruby, the .NET SDK, Swift respectively. conda needs nothing.                                                                                                                                   |
| ubi              | Deprecated; removed in 2027.1.0.                                                                                                                                                                    |
| asdf             | Legacy shell plugins; avoid.                                                                                                                                                                        |

Backend statuses beyond these (`packslip:` signed manifests, `spinel:`
experimental Ruby AOT) are documented but not exercised here; check the docs
before using them.

Verified runs: `mise use github:BurntSushi/ripgrep@14` writes
`"github:BurntSushi/ripgrep" = "14"` and installs the right platform asset;
`mise use uv pypi:cowsay` works with no Python declared (uv supplies one).

## Go toolchain bypass

Docs-based, not run here (installing Go was too heavy to test): with
`go` pinned in mise, a `go` or `toolchain` line in `go.mod` newer than the pin
makes Go itself download that toolchain (its default `GOTOOLCHAIN=auto`
behavior), bypassing mise. Keep the `go.mod` line at or below the pinned
version. `GOTOOLCHAIN=local` forces the local toolchain, but setting it in
mise needs `[env]`, which makes `mise.toml` require trust; weigh that
trade-off, or export it in CI and docs instead.

## Declaring runtimes for package backends

mise never adds a runtime for you (apart from uv supplying Python for
`pypi:`). Put it beside the tool so contributors and CI get both:

```toml
[tools]
node = "X.Y.Z"
"npm:some-cli" = "X.Y.Z"
uv = "X.Y.Z"
"pypi:some-tool" = "X.Y.Z"
```

`X.Y.Z` stands for real exact versions, resolved with `mise latest <tool>`.
Use a package backend only for a tool the registry and `aqua:`/`github:` do
not cover. A registry short name can itself resolve to a package backend:
verified, `mise registry prettier` shows `npm:prettier`. If `mise registry
<tool>` lists `npm:`, `pypi:`, `cargo:`, or `go:`, declare the runtime too.

Verified failure mode: `npm:prettier` with no node installs fine and then
`mise exec -- prettier` fails with `exec: node: not found`. Pin the runtime to
an exact version too, since the package's behavior depends on it.

For `pypi:`, the lock records the dependency graph only with uv >= 0.12.10
(docs). For npm and pypi, commit the `.mise/locks/` sidecars.

## Migrating `ubi:` to `github:`

Verified: `mise use ubi:koalaman/shellcheck` prints `deprecated [ubi]: ... will
be removed in mise 2027.1.0`. For each existing entry:

- Replace the key with `github:owner/repo`, keep the version.
- Drop `exe` (use `rename_exe` or `bin` if the binary name needs control), and
  note `extract_all` is gone and `tag_regex` has no direct equivalent (docs).
- Switching backends reuses the old install directory, so run
  `mise install --force <tool>` and then `mise lock`, and check
  `git diff mise.lock` (the entry's `backend` changes).
- Prefer the registry short name if the tool has one (`mise registry <t>`).

Other renames: `pipx:` entries can stay as they are; new entries use `pypi:`.
`[alias]` is deprecated in favor of `[tool_alias]`.

## Tool options

Inline tables apply per tool; they need trust (see `config-and-trust.md`):

```toml
[tools]
shellcheck = { version = "0.11.0", os = ["linux", "macos"] }
"github:jqlang/jq" = { version = "1.8.2", version_prefix = "jq-" }
```

- Universal: `version`, `os`, `depends`, `install_env`, `postinstall`, `lazy`,
  `minimum_release_age`, `prerelease`, `version_order`.
- `os = ["linux"]` skips the tool elsewhere with no error (verified on macOS);
  accepted values include `linux`, `macos`, `windows`, `unix`, and
  `macos/arm64` style pairs.
- `postinstall` runs after install with the tool on PATH and `MISE_TOOL_NAME`,
  `MISE_TOOL_VERSION`, `MISE_TOOL_INSTALL_PATH` set; failure fails the install
  (verified). It is code execution at install time, so review it in
  unfamiliar repos and keep it out of shared config unless needed.
- `depends = ["node"]` only orders installs.
- github options: `asset_pattern`, `matching`, `version_prefix`,
  `rename_exe`, `bin_path`, per-platform `platforms.<os>-<arch>` sections, and
  more (docs). Use the double-brace templates (`{{ version }}`, `{{ os() }}`,
  `{{ arch() }}`); the single-brace `{version}` form is deprecated and is
  removed in 2027.3.0.
- From the CLI, quote the bracket syntax:
  `mise use 'github:jqlang/jq[version_prefix=jq-]@1.8.2'`.

## GitHub tokens

Public release metadata is mostly served by a mise-run mirror
(`use_versions_host`, on by default), but some paths still use the GitHub API:
in testing, locking `github:` tools did, while aqua tools locked with no
quota. The anonymous limit is 60 requests per hour per IP and is shared with
everything else on that network; during testing it was observed exhausted
(59 of 60 used), cause not isolated. Set a token for locking and CI. A
rate-limited `mise lock` exits 0 with an incomplete lock; see
`versions-and-lockfile.md` for the check.

When `gh` is signed in, a one-off token is
`MISE_GITHUB_TOKEN="$(gh auth token)" mise lock` (it fails if `gh` is missing
or logged out, so test `command -v gh` and `gh auth token` first, as shown
there).

- Environment priority: `MISE_GITHUB_ENTERPRISE_TOKEN` (non-github.com hosts),
  `MISE_GITHUB_TOKEN`, `GITHUB_API_TOKEN`, `GITHUB_TOKEN`, then a configured
  `github.credential_command`, native OAuth, `github_tokens.toml`, `gh`'s
  `hosts.yml`, and `git credential fill` (docs). mise does **not** read
  `GH_TOKEN`. A bad higher-priority token hides a good lower one.
- `gh` on macOS stores tokens in the Keychain, so mise sees none even when
  `gh auth status` is fine. Fix in **global** config, never in a project:

  ```toml
  [settings.github]
  credential_command = 'gh auth token --hostname "$MISE_CREDENTIAL_HOST"'
  ```

  `credential_command` is global-only (docs).
- A classic PAT with no scopes suffices for public repos; a fine-grained token
  needs Contents: read for private release assets (docs).
- `mise token github` shows which source mise picked. Never use `--unmask` or
  `--raw` where output is logged.
- GitLab and Forgejo are analogous (`MISE_GITLAB_TOKEN`,
  `MISE_FORGEJO_TOKEN`). GitHub Enterprise Server tools set
  `api_url = "https://github.example.com/api/v3"` per tool, and attestation
  checks are skipped there (docs).
- Never put a token in `mise.toml` or commit one anywhere; an exposed token
  must be revoked.
