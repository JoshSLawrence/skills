<!-- markdownlint-disable MD013 -->
<!-- Wide tables and code samples are unwrappable. -->

# Env directives: `_.file`, `_.path`, `_.source`

Read this when loading variables from a file, adding directories to `PATH`,
or sourcing a script. Behavior verified against mise 2026.10.7 unless marked
"docs". Source: <https://mise.jdx.dev/environments/>.

## Contents

- Shared rules
- `_.file`
- `_.path`
- `_.source`
- The `env_file` setting
- Deprecated syntax

## Shared rules

- Each directive takes a path, a table with `path` and options, or an array of
  either. They run in the order written, so a later one can use what an
  earlier one set; `_.python.venv` always runs last (docs).
- Relative paths resolve against the project root, also when the config is
  `.config/mise.toml` (verified: `_.path = "bin"` and `_.file = ".env"` in
  `.config/mise.toml` resolved to `<project>/bin` and `<project>/.env`).
  Templates, `$VAR`, and `~` work in paths (verified for `~` and
  `{{ config_root }}`).
- Options:

  | Option   | `_.file` | `_.source` | `_.path` | Effect                                    |
  | -------- | -------- | ---------- | -------- | ----------------------------------------- |
  | `path`   | yes      | yes        | yes      | One path or a list                        |
  | `tools`  | yes      | yes        | yes      | Resolve after tools load (`templates.md`) |
  | `redact` | yes      | yes        | no       | Mark every loaded value sensitive         |
  | `expand` | yes      | no         | no       | Let the file reference earlier values     |

## `_.file`

```toml
[env]
_.file = [
  ".env",
  { path = ".env.secrets.json", redact = true },
]
```

Verified behavior:

- **Format comes from the extension.** `.json`, `.yaml`, `.toml` are parsed
  as structured files; their top-level keys become variables. **Every other
  name is dotenv, `.yml` included**: a YAML file named `.env.yml` failed with
  `dotenv syntax error ... expected '=' after the environment variable name`.
  Name YAML files `.yaml`.
- Structured values must be scalars. Numbers and booleans become strings
  (`5`, `true`). A nested object is a hard error:
  `unsupported json value: Object {"x": Number(1)}`.
- **A missing file is skipped without a message**, so `_.file = ".env"` is
  safe for an optional, untracked file. The flip side: a typo in the path is
  silent too. Check with `mise set` that the variables arrived.
- Globs work: `.env.g*` loaded both `.env.g1` and `.env.g2`.
- **File values replace the shell's.** With `DOT_A=shell` exported and
  `DOT_A=plain` in `.env`, the command saw `plain`. If a developer must be
  able to override from the shell, use `[env]` with `default` instead.
- Dotenv parsing: `#` comments, `export KEY=v`, double quotes, and single
  quotes (literal: `'single $NOT'` stayed as written) all worked. `${KEY}`
  referenced an earlier key in the same file, and `$HOME` expanded from the
  environment. `$(...)` and backticks were **not** executed; they stayed
  literal text.
- JSON/YAML/TOML values are literal (`"$BASE"` stayed `$BASE`) unless the
  entry sets `expand = true`, which expanded it from an earlier `[env]` value.
- sops-encrypted `.json`, `.yaml`, and `.toml` files are decrypted on load;
  a sops-encrypted dotenv file is **not** (see `secrets.md`).

When the app or docker compose already reads `.env`, keep `.env` as the
source of truth and point `_.file` at it rather than copying values into
`mise.toml`. Commit a `.env.example`, ignore `.env`.

## `_.path`

```toml
[env]
_.path = ["bin", "{{ config_root }}/node_modules/.bin", "~/.local/share/mytool/bin"]
```

Verified, running `mise x -- printenv PATH` from a subdirectory:

```text
<project>/bin
<project>/tools/bin
/Users/<you>/fake-home-bin
<project>/rel
~/.local/share/mise/installs/jq/1.8.2
~/.local/share/mise/shims
...
```

- Entries keep their written order and go **ahead of the tools' bin dirs**.
  A project `bin/jq` ran instead of the pinned jq 1.8.2. Use `_.path` for
  project scripts, and do not give them names that shadow tools.
- Relative entries resolve from the project root, not the cwd.
- A `PATH` key in `[env]` is ignored (verified with `mise x` and `mise env`).
  Use `_.path`, or a `_.source` script that prepends.
- `node_modules/.bin` on `PATH` is the direnv `layout node` equivalent (docs).

## `_.source`

```toml
[env]
_.source = "scripts/env.sh"
```

- mise runs the script with bash, ignoring its shebang (docs), and keeps the
  variables it exports. Verified: `export FROM_SOURCE=sourced` arrived, and
  `export PATH="/prepended/by/source:$PATH"` put that directory first. mise
  ignores other `PATH` edits such as appending or reordering (docs).
- **It runs every time mise computes the environment**: three `mise x` calls
  ran it three times (verified). Keep it fast, idempotent, and free of side
  effects; anything slow belongs in a task.
- It is code: it needs trust, `mise x`/`mise run` will run it after trusting
  implicitly (verified), and `MISE_SAFE=1` never runs it, even from global
  config (verified for project config; global is docs).
- Globs and missing-file skipping work as for `_.file` (docs).
- Windows needs a POSIX bash such as Git for Windows (docs).

Prefer plain `[env]` values or `_.file` when the values are static. Reach for
`_.source` only when a script must compute them, for example a vendor's
`env.sh` you cannot change.

## The `env_file` setting

`MISE_ENV_FILE=.env` (setting `env_file`) loads a dotenv file from the current
directory and every parent, closer files winning, without any `mise.toml`
(docs). Verified: from a subdirectory with no mise config,
`MISE_ENV_FILE=.env mise x -- printenv DOT` printed the parent `.env` value,
and nothing became trusted. It is a per-user setting, so it suits a personal
habit, not a project convention; projects should use `_.file`.

## Deprecated syntax

From the docs; do not write these, and offer to convert them when you see
them:

| Deprecated                                                   | Use instead  | Removed in |
| ------------------------------------------------------------ | ------------ | ---------- |
| `env.mise.*`                                                 | `env._.*`    | 2026.12.0  |
| `value`/`values` in a `_.file`, `_.path` or `_.source` table | `path`       | 2026.12.0  |
| Top-level `env_file` or `dotenv`                             | `env._.file` | 2027.4.0   |
| Top-level `env_path`                                         | `env._.path` | 2027.4.0   |

`value` in an ordinary variable table (`SECRET = { value = "...", redact =
true }`) is not deprecated.
