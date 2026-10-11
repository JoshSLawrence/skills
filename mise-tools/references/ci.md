<!-- markdownlint-disable MD013 -->
<!-- Wide tables and code samples are unwrappable. -->

# mise in CI

Read this when adding or reviewing a workflow that installs tools with mise.
The action inputs were checked against `action.yml` at tag v5 and the releases
API; the rest is from the docs, not run. Sources:
<https://mise.jdx.dev/continuous-integration.html>,
<https://github.com/jdx/mise-action>.

## Contents

- GitHub Actions
- Tokens
- Caching
- Trust in CI
- Other CI systems

## GitHub Actions

```yaml
name: ci

on:
  pull_request:

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

- **Pin to a full commit SHA** with the version in a comment. Tags can move;
  an action runs with your job's token, so treat it like a dependency. The SHA
  above is the commit for tag `v5.1.1` (the latest v5 release when this was
  written, published 2026-10-04), looked up with
  `gh api repos/jdx/mise-action/releases/latest` and
  `gh api repos/jdx/mise-action/git/ref/tags/v5.1.1` (a lightweight tag, so
  the object is the commit). Re-check for a newer release when you add the
  action to a repo.
- **Least privilege:** `permissions: contents: read` at the top, widened per
  job only when a step needs it.
- The action installs mise and the tools from `mise.toml`, caches installs,
  puts shims on PATH, and exports project `[env]`. When a `mise.lock` exists it
  installs with `--locked`, so a tool missing from the lock (or a platform the
  lock lacks) fails the job instead of resolving fresh. Re-run
  `mise lock --platform ...` locally to cover every runner OS and commit it.
- Useful inputs: `version` (pin the mise version itself), `install`,
  `install_args`, `cache`, `cache_save`, `cache_key_prefix`,
  `working_directory`, `github_token`, `persist_github_token`,
  `experimental`, `add_shims_to_path`, `env`. Pin `version` if you need the
  mise version to be reproducible too.
- Have CI call one task (`mise run ci`) that contributors can also run
  locally; see the `mise-tasks` skill. Warm caches for task-only tools with
  `mise install --include-task-tools` (docs).
- Add an update path: a scheduled job or a bot running `mise upgrade --bump`
  and opening a PR, so pins do not rot. Set `MISE_SAFE=1` for any such job
  that reads untrusted branches (docs).

## Tokens

- The action authenticates its own install with the workflow token but does
  not export it to later steps by default: mise-action v5.1.1's `action.yml`
  has a `persist_github_token` input, default `"false"`, and its release notes
  say the token stays inside the action. Setting `persist_github_token: true`
  exports it for the rest of the job. The narrower option is to give only the
  step that needs it a step-level `env:`. A later step that installs tools
  (`mise use`, `mise install`, `mise upgrade`) needs one of the two:

  ```yaml
  - run: mise install
    env:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  ```

  Otherwise that step falls back to the tiny anonymous API quota and may fail
  with a 403 or rate-limit message. mise reads `MISE_GITHUB_TOKEN`,
  `GITHUB_API_TOKEN`, then `GITHUB_TOKEN`, but not `GH_TOKEN`.
- Use a PAT or app token as `MISE_GITHUB_TOKEN` only when a tool lives in a
  private repo the workflow token cannot read. Keep it in encrypted secrets;
  never in `mise.toml` or a workflow literal.
- Expose a token only to the steps that need it (step-level `env:`), not the
  whole job.

## Caching

The action's default cache stores the tool install directory. A restored
`installs/` tree is trusted as is: the lockfile checks downloads, not
already-installed files (docs). For stricter integrity, cache the download
store keyed on the lockfile and let mise re-extract and verify:

```yaml
- uses: actions/cache@<full-sha> # vX.Y.Z
  with:
    path: ~/.cache/mise/downloads-cas
    key: mise-${{ runner.os }}-${{ hashFiles('mise.lock') }}
- uses: jdx/mise-action@2d8d4cafcbd33be2ea37d2b6f5ad595363d1f1ca # v5.1.1
  with:
    cache: false
```

That path is Linux's cache directory. On macOS runners mise's cache is
`~/Library/Caches/mise` (verified with `mise cache path`), so either use a
per-OS `path` or set `MISE_CACHE_DIR` in the job's `env:` so the path is the
same everywhere.

Keying on `hashFiles('mise.lock')` means any lock change (a bump) busts the
cache and nothing stale survives. Look up and pin the `actions/cache` SHA the
same way as the mise action. This pattern is from the docs and was not run
here.

## Trust in CI

With the `CI` environment variable set, mise treats every config as trusted
without recording it (verified locally with `CI=1`). That is convenient for
your own repo and a risk for workflows that check out untrusted pull request
code with secrets available: the PR's `mise.toml` can run code. Avoid
`pull_request_target` with a checkout of PR code, and use `MISE_SAFE=1` for
bots that only resolve versions.

## Other CI systems

- `mise generate install-script --localize --write` writes a committed
  `bin/mise` wrapper that pins the mise version, keeps its state in `.mise/`,
  trusts the project, and ignores the user's global config (docs).
- An official image exists at `ghcr.io/jdx/mise:<version>-debian` (docs); pin a
  version or digest rather than a floating tag.
- `mise generate github-action --write --task=ci` scaffolds a workflow
  (docs). Review it against the pinning rules above before committing.
- Anywhere else: install mise, then `mise install --locked`, then
  `mise run <task>` or `mise x -- <cmd>`. Set `MISE_GITHUB_TOKEN` from the
  CI system's secret store.
