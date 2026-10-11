<!-- markdownlint-disable MD013 -->
<!-- Wide tables and code samples are unwrappable. -->

# Config environments (`mise.<env>.toml`)

Read this when values differ between dev, staging, prod, or CI. Behavior
verified against mise 2026.10.7 unless marked "docs". Source:
<https://mise.jdx.dev/configuration/environments.html>.

## Contents

- How it works
- Precedence (verified)
- Selecting environments
- Writing to an environment file
- Tasks and templates
- Pitfalls
- Platform environments

## How it works

`mise -E staging ...` (or `MISE_ENV=staging`) loads `mise.staging.toml` on
top of `mise.toml`; the base file always loads. Selecting an environment does
not set any variable for the app; define those in the environment file:

```toml
# mise.toml
[env]
APP_ENV = "development"
API_URL = "http://localhost:8080"
```

```toml
# mise.staging.toml
[env]
APP_ENV = "staging"
API_URL = "https://staging.example.com"
```

```sh
mise x -- printenv API_URL                 # http://localhost:8080
mise -E staging x -- printenv API_URL      # https://staging.example.com
mise -E staging config ls                  # files that loaded
```

The same works for `[tools]` (an env file can pin a tool for CI) and each env
file gets its own lockfile, `mise.<env>.lock` (see the `mise-tools` skill).

## Precedence (verified)

Six files in one directory, each setting some of `A`-`F`:

| Selection    | Result                                                                                                         |
| ------------ | -------------------------------------------------------------------------------------------------------------- |
| none         | `mise.local.toml` > `mise.toml`                                                                                |
| `staging`    | `mise.staging.local.toml` > `mise.local.toml` > `mise.staging.toml` > `mise.toml`                              |
| `staging,ci` | `C` from `mise.ci.toml` (later env wins among shared files); `F` from `mise.ci.local.toml` over `mise.ci.toml` |
| `ci,staging` | `C` from `mise.staging.toml`                                                                                   |

So, highest first: `mise.<env>.local.toml`, `mise.local.toml`,
`mise.<env>.toml`, `mise.toml`. **A personal `mise.local.toml` beats a
committed `mise.staging.toml`** (verified: `D` came from `mise.local.toml`
under `-E staging`). To override only for one environment, use
`mise.staging.local.toml`. Gitignore `mise.local.toml` and
`mise.*.local.toml`.

Other locations take environment suffixes the same way
(`.config/mise.<env>.toml`, `mise/config.<env>.toml`), and the global config
dir uses `config.<env>.toml` (docs).

## Selecting environments

Highest precedence first:

| Method               | Example                            |
| -------------------- | ---------------------------------- |
| Global flag          | `mise -E staging run deploy`       |
| Environment variable | `MISE_ENV=staging mise run deploy` |
| `.miserc.toml`       | `env = ["development"]`            |

Verified: `-E` and `MISE_ENV` gave identical results. A committed
`.miserc.toml` with `env = ["production"]` made a plain `mise env` load
`mise.production.toml`; `-E dev` and an empty `MISE_ENV=` both overrode it.
`.miserc.local.toml` (gitignored) holds a personal default (docs).

Be careful with a committed `.miserc.toml` default other than a harmless
`development`: everyone then runs against that environment without passing a
flag.

## Writing to an environment file

| Command                          | Writes                                                   |
| -------------------------------- | -------------------------------------------------------- |
| `mise set --env staging KEY=v`   | `mise.staging.toml` (verified)                           |
| `mise set -E staging KEY=v`      | Same: `-E` *after* `set` is its own flag (verified)      |
| `mise -E staging set KEY=v`      | `mise.toml`: `-E` *before* `set` only selects (verified) |
| `mise use --env staging node@24` | `mise.staging.toml` (docs)                               |

## Tasks and templates

- Tasks receive the selection as `MISE_ENV` (verified:
  `MISE_ENV=production` with `-E production`, unset without it).
- Templates read it as `mise_env`, a list that is **undefined** when nothing
  is selected. `{{ mise_env | default(value=['none']) | first }}` gave
  `production` and `none` (verified). A bare `{{ mise_env }}` fails when
  undefined (docs).
- A deploy task can refuse to run without an environment:

  ```toml
  [tasks.deploy]
  run = """
  {% if mise_env is not defined %}echo "select an environment with -E" >&2; exit 1{% endif %}
  ./scripts/deploy.sh {{ mise_env | first }}
  """
  ```

  (docs pattern; task authoring is the `mise-tasks` skill.)

## Pitfalls

- **Typos select nothing, silently.** `mise -E prodution env` loaded only
  `mise.toml`, with no warning (verified). Before acting on a real
  environment, run `mise -E <env> config ls` and look for the env file.
- **`MISE_ENV` in `[env]` does not select anything.** It was exported as
  `MISE_ENV=production` while `mise.production.toml` stayed unloaded
  (verified), so a task reading `$MISE_ENV` would be misled. You cannot select
  an environment from `mise.toml` (docs).
- **Encrypted files in an env file** decrypt only when that env is selected,
  which is the recommended way to keep a missing key from breaking dev
  commands (`secrets.md`).
- The selection is per command. In an agent shell, pass `-E` on each `mise`
  call or set `MISE_ENV` in that same call.

## Platform environments

With the `auto_env` setting, mise also loads `mise.unix.toml`,
`mise.<os>.toml`, and `mise.<os>-<arch>.toml` (for example
`mise.macos-arm64.toml`) automatically, below selected environments. It is
off by default; mise warns from 2026.12.0 about files it would load and turns
it on in 2027.6.0 (docs). Set `auto_env` in `.miserc.toml`, not `mise.toml`.
If a repo has files with those names for other reasons, rename them before
then.
