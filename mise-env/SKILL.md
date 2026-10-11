---
name: mise-env
description: Set project environment variables with mise, even when the user never says "mise" - [env] in mise.toml, .env and dotenv files, extra PATH entries, per-environment config (mise.staging.toml, MISE_ENV), secrets kept out of the repo (sops or age encryption, redaction in logs) and Python venvs that activate automatically. Use this skill as soon as a user wants to add or change an env var, load a .env file, stop committing secrets or API keys, give DATABASE_URL or an API URL different values for dev, staging, prod and CI, activate the venv automatically, replace direnv or an .envrc, or debug why a variable is missing or wrong, and whenever a mise.toml has an [env] section or per-environment mise.*.toml files. Offer it as an option in repos that use direnv or a plain .env, and prefer it over ad hoc export lines in repos that already use mise. Don't use it for installing or pinning tools, shims, shell activation or `mise x` (that's the mise-tools skill) or for writing tasks and scripts (that's the mise-tasks skill).
---

<!-- markdownlint-disable MD013 -->
<!-- Wide tables, code, and the frontmatter description are unwrappable. -->

# Project environment variables with mise

mise sets a project's environment from the same `mise.toml` that pins its
tools. `[env]` holds plain values; directives load `.env` files, add `PATH`
entries, and activate a Python virtualenv; `mise.<env>.toml` files switch
values per target (staging, prod, CI); encrypted files keep shared secrets in
the repo without exposing them. `mise x`, `mise run`, shims, and activated
shells all see the same result. Your job is to put each value in the file
where it belongs (committed, personal, per environment, or per task), keep
secrets out of plaintext and out of logs, and confirm the value that actually
reached the command.

Behavior in this skill was verified against mise 2026.10.7 unless marked as
coming from the docs. Docs: <https://mise.jdx.dev/environments/>. Details
live in `references/`; read the one you need rather than all of them:

- `references/directives.md` - `_.file` formats and parsing rules, `_.path`,
  `_.source`, the `env_file` setting, deprecated syntax
- `references/templates.md` - `{{ }}` values, `exec()`, shell-style `$VAR`,
  ordering rules, `tools = true`, `[vars]`
- `references/secrets.md` - choosing a secrets approach, sops + age end to
  end, age values, redaction, CI masking, keeping a missing key from breaking
  everything
- `references/config-environments.md` - `mise.<env>.toml`, `-E`/`MISE_ENV`,
  precedence, several environments, `.miserc.toml`
- `references/python-venvs.md` - `_.python.venv`, uv projects,
  `python.uv_venv_auto`, `UV_PYTHON`
- `references/hooks-and-direnv.md` - enter/leave hooks, migrating from
  direnv, when to keep direnv or a plain `.env`

Out of scope here: installing and pinning tools, shims, shell activation,
`mise x` itself, and trust in general (use the `mise-tools` skill); writing
tasks (use the `mise-tasks` skill). A task's own `env` is mentioned below
only as a place a value can live.

## When to use mise `[env]` (and when not)

| Situation                                               | Use                                                  |
| ------------------------------------------------------- | ---------------------------------------------------- |
| Repo already uses mise; a dev/CI value is needed        | `[env]` in the right mise file                       |
| App, framework, or docker compose already reads `.env`  | Keep `.env`; load it into mise with `_.file`         |
| Repo uses direnv and not mise                           | Respect it; offer to migrate (`hooks-and-direnv.md`) |
| `.envrc` does what mise cannot (`use flake`, `use nix`) | Keep direnv for that repo                            |
| Production runtime config                               | The platform's secret store or config, not mise      |
| A value only one task needs                             | That task's `env` (see the `mise-tasks` skill)       |

mise environments are for developer machines and CI. A `mise.production.toml`
is for running commands *against* production (a migration, a deploy) from a
laptop or a pipeline; it is not how a production service gets its config.

Do not silently replace direnv or a dotenv loader: teammates' shells and the
app itself may depend on them. Respect the existing setup, say what you
found, and offer mise `[env]` as an option, the way the `mise-tools` skill
treats asdf and nvm.

## Reach for it without being asked

The user will rarely say "mise" or "`[env]`". In a repo that uses mise:

- **"Add an env var", "set FOO for this project"** -> `[env]` in `mise.toml`,
  or `mise.local.toml` if it is personal.
- **A `.env` the app already reads** -> `_.file = ".env"` instead of copying
  values into `mise.toml`, so there is one source of truth.
- **A secret pasted into config, "don't commit the API key"** -> move it to
  `mise.local.toml` (gitignored) or an encrypted file, and mark it
  `redact = true`.
- **"DATABASE_URL per environment", "staging vs prod config"** ->
  `mise.staging.toml` / `mise.production.toml`, selected with `-E`.
- **"Activate the venv automatically", "I keep forgetting to source
  .venv/bin/activate"** -> `_.python.venv` or `python.uv_venv_auto`.
- **Project scripts or `node_modules/.bin` wanted on PATH** -> `_.path`.
- **An `.envrc` in a repo that uses mise** -> offer to migrate it; running
  both on the same directory is unsupported (docs).

Why each one:

- **One place.** `[env]` reaches `mise x`, `mise run`, shims, and activated
  shells. Verified: a value in `[env]` reached a program run through its shim
  (`~/.local/share/mise/shims/jq -nr env.FOO` printed it) and through
  `mise x`.
- **Personal values stay personal.** `mise.local.toml` wins over `mise.toml`
  (verified) and is meant to be gitignored, so a developer's own
  `DATABASE_URL` never lands in a commit.
- **Environment files layer.** `mise -E staging` loads `mise.staging.toml` on
  top of `mise.toml` (verified), so the shared defaults are written once.
- **Secrets need more than a gitignore.** Redaction masks values in task
  output (verified), and sops-encrypted files can be committed and decrypted by
  mise itself with no `sops` binary at runtime (verified).
- **Venvs** that mise activates are active for `mise x`, tasks, and activated
  shells (verified for `mise x` and `mise env`), so nobody has to remember
  `source .venv/bin/activate`.

The boundaries still hold: introducing mise to a repo only for env vars is a
proposal, not a default; respect existing direnv and dotenv setups.

## Workflow

1. **Look first.** Check `mise.toml`, `mise.local.toml`, `mise.*.toml`,
   `.config/mise*`, `.env*`, `.envrc`, `.sops.yaml`, `.miserc.toml`, and
   `.gitignore`. Run `mise config ls` (which files load) and
   `mise set` (each variable, its source file, secrets shown as
   `[redacted]`; verified). In a repo you did not write, read the config
   before running `mise x`/`mise run`: they trust it implicitly and then run
   its `_.source` scripts and `exec()` templates (verified; see Trust below).
2. **Decide where each value belongs** (table below).
3. **Write it.** Edit the file, or use `mise set` (targets below). Keep
   secret values off the command line (`--prompt`, `--stdin`).
4. **Ignore personal files.** Add `mise.local.toml`, `mise.*.local.toml`,
   `.env`, and any key file to `.gitignore`; nothing does it for you (docs).
   Commit a `.env.example` with placeholder values if the project uses `.env`.
5. **Verify without printing secrets.** `mise env --json` for non-secret
   values, `mise x -- printenv NAME` for one value, and for secrets only
   presence: `mise x -- sh -c 'test -n "$API_TOKEN" && echo set'`. Check
   `mise config ls` when an environment file is involved.

## Where a value belongs

| Value                                                    | Put it in                                                    |
| -------------------------------------------------------- | ------------------------------------------------------------ |
| Non-secret, same for everyone (`LOG_LEVEL`, `APP_ENV`)   | `[env]` in `mise.toml` (committed)                           |
| Personal or machine-specific; a dev secret only you hold | `mise.local.toml` (gitignored)                               |
| Differs per target (staging, prod, CI)                   | `mise.<env>.toml`, selected with `-E <env>`                  |
| Personal override for one target                         | `mise.<env>.local.toml` (gitignored)                         |
| Needed by one task only                                  | The task's `env` (the `mise-tasks` skill)                    |
| Secret the whole team needs                              | sops-encrypted `.env.json`/`.yaml`, scoped to a task or env  |
| Secret held in 1Password, AWS Secrets Manager, ...       | fnox (experimental) or a task that fetches it (`secrets.md`) |
| A file the app or compose already reads                  | Keep `.env`; `_.file = ".env"`                               |

Precedence, highest first (verified): `mise.<env>.local.toml`,
`mise.local.toml`, `mise.<env>.toml`, `mise.toml`; a child directory's config
wins over its parent's; any project config wins over the global config. Note
the second row: **`mise.local.toml` beats `mise.staging.toml`** (verified), so
a personal override silently wins even under `-E staging`.

## `[env]` essentials

```toml
[env]
LOG_LEVEL = "debug"
PORT = 3000                      # numbers and booleans become strings
NODE_ENV = { default = "development" }
DATABASE_URL = { required = "Set DATABASE_URL in mise.local.toml" }
AWS_PROFILE = false              # unset it, even if the shell set it
API_TOKEN = { value = "...", redact = true }
```

Verified behavior:

- A plain value **replaces** what the shell had. `default` keeps a non-empty
  value from the shell or a lower-precedence file (`DEF2=fromshell` stayed
  `fromshell`; an empty one got the default). `false` unsets a variable the
  shell set.
- `PATH = "..."` in `[env]` is ignored; use `_.path` (verified: the value
  never appeared in `PATH`).
- Values must be defined before they are referenced, in file order (see
  Templates).
- **`required` at the top level blocks everything.** With it unset,
  `mise env`, `mise x`, `mise run` (any task, even one that does not use the
  variable), and also `mise ls` and `mise install` fail with
  `Required environment variable 'DATABASE_URL' is not defined` plus the help
  text; an activated shell only warns. An empty string from the shell
  satisfies it. Prefer task-level `required` for anything not every command
  needs:

  ```toml
  [tasks.migrate]
  env = { DATABASE_URL = { required = "Set DATABASE_URL to the target database" } }
  run = "./scripts/migrate.sh"
  ```

  Verified: with that, `mise run lint` and `mise ls` work without the
  variable and only `migrate` fails.

`mise set` and `mise unset` edit `[env]`. Verified write targets:

| Command                                        | Writes                                                |
| ---------------------------------------------- | ----------------------------------------------------- |
| `mise set KEY=v`                               | `mise.toml` (even when `mise.local.toml` exists)      |
| `mise set --env local KEY=v`                   | `mise.local.toml`                                     |
| `mise set --env staging KEY=v` (or `-E`)       | `mise.staging.toml` (created if missing)              |
| `mise -E staging set KEY=v`                    | `mise.toml`: a global `-E` only selects files         |
| `mise set --file <path> KEY=v`                 | That file                                             |
| `printf %s "$v" \| mise set --stdin KEY`       | Same targets; value kept off the command line         |
| `mise set` / `mise set KEY` / `mise unset KEY` | List (redacted) / print one (**unredacted**) / remove |

`mise set` writes the file and trusts it (docs, and mise-tools). Never pass a
real secret as `KEY=value` on the command line: it lands in shell history and,
by default, in the committed `mise.toml`.

## Directives at a glance

Directives live under `_` in `[env]` and run in the order written
(`_.python.venv` always last). Relative paths resolve against the project
root, even for `.config/mise.toml` (verified).

| Directive       | Does                                | Key facts (verified unless noted)                                                                                                                                  |
| --------------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `_.file`        | Load variables from files           | `.json`/`.yaml`/`.toml` are structured; **everything else, `.yml` included, is dotenv**; missing files are skipped silently; globs work; values override the shell |
| `_.path`        | Prepend directories to `PATH`       | Goes **ahead of tool bin dirs**, so `bin/jq` shadows the pinned jq                                                                                                 |
| `_.source`      | Run a bash script, keep its exports | Runs on **every** mise invocation; needs trust; never runs under `MISE_SAFE=1`                                                                                     |
| `_.python.venv` | Create/activate a virtualenv        | See `references/python-venvs.md`                                                                                                                                   |

```toml
[env]
_.path = ["bin", "node_modules/.bin"]
_.file = [".env", { path = ".env.secrets.json", redact = true }]
```

Details, dotenv parsing rules, and the traps (nested JSON is an error, a
`.yml` file fails as dotenv) are in `references/directives.md`.

## Templates in brief

Values are Tera templates plus shell-style `$VAR` expansion:

```toml
[env]
PROJECT_LIB = "{{ config_root }}/lib"
LD_LIBRARY_PATH = "$PROJECT_LIB:${LD_LIBRARY_PATH:-}"
GIT_SHA = "{{ exec(command='git rev-parse --short HEAD', cache_key='sha', cache_duration='1h') }}"
NODE_VERSION = { value = "{{ tools.node.version }}", tools = true }
```

- `{{ config_root }}` is the project root; `{{ cwd }}` is wherever mise was
  run, so prefer `config_root` for paths (verified).
- Referencing a variable defined *later* is a hard error
  (`Field 'LATER' is not defined`), not an empty string. Order entries, or
  use `{{ env.X | default(value='') }}` (verified).
- `exec()` runs on every mise invocation (verified: three `mise x` runs, three
  executions). Cache it with `cache_key`/`cache_duration` (verified: one
  execution across three runs), and use it only for side-effect-free
  commands.
- `[env]` resolves **before** tools load. Anything that needs a tool's
  version, path, or binary needs `tools = true` (verified: without it,
  `tools` is undefined, and `exec(command='command -v jq')` found
  `/usr/bin/jq` instead of the pinned jq).

More in `references/templates.md`.

## Secrets in brief

- Plaintext secrets never go in a committed file. In order of preference:
  personal dev secrets in `mise.local.toml` or an untracked `.env`; shared
  secrets in a sops-encrypted `.env.json` or `.env.yaml`; age-encrypted values
  and fnox only when the user accepts experimental features.
- **Redaction is masking, not protection.** `redact = true` or a top-level
  `redactions = ["*_TOKEN"]` replaces values with `[redacted]` in `mise run`
  output and in `mise set` listings (verified). `mise x` output,
  `mise env` (even `--redacted`), and `mise set KEY` print real values
  (verified). As an agent, do not run those in a project with secrets unless
  the user asks; check presence with `test -n` instead.
- **A key nobody has breaks every command.** A committed encrypted file loaded
  from `mise.toml` makes `mise ls`, `mise install`, and every task fail for
  anyone without the key, CI included (verified). Load it from the task that
  needs it or from `mise.<env>.toml` instead (verified to contain the failure);
  `secrets.md` has the patterns.

## Config environments in brief

```sh
mise -E staging run deploy          # or MISE_ENV=staging
mise -E staging config ls           # which files actually loaded
```

- `-E` and `MISE_ENV` are equivalent (verified). Several are comma-separated;
  later wins among files of the same kind, but any `.local` file beats any
  shared one (verified).
- **A typo selects nothing, silently**: `-E prodution` loaded only
  `mise.toml` with no warning (verified). Check `mise -E <env> config ls`
  before acting on production.
- `MISE_ENV` set inside `[env]` does **not** select files; it is just exported
  (verified), which can mislead a task into thinking an environment is active.
  Select with `-E`, `MISE_ENV` in the calling shell, or `.miserc.toml`.

Details in `references/config-environments.md`.

## Running with the env as an agent

Agent shells are usually not activated, so `[env]` is **not** in a bare
command's environment (verified: `printenv FOO` was empty in a project setting
`FOO`). Therefore:

- Run commands through mise: `mise x -- <cmd>` or `mise run <task>`.
- For several commands in one call, `eval "$(mise env -s bash)"` exports the
  environment once for the current directory (verified); it does not follow
  later `cd`s, and it puts secrets into that shell, so prefer `mise x` there.
- Enter/leave hooks never fire in an agent shell; do not rely on them for
  anything CI or agents need (`references/hooks-and-direnv.md`).
- Check what a command received with `mise x -- printenv NAME` for non-secret
  values and `test -n` for secrets. `mise env --json-extended` shows each
  value's source file (verified).

How activation, shims, and `mise x` work in general is in the `mise-tools`
skill.

## Trust and safety

Trust is covered in depth by the `mise-tools` skill
(`references/config-and-trust.md` there); what matters for `[env]`:

- **Any `[env]` needs trust**, even `FOO = "bar"` (verified). Untrusted, a
  read-only command fails with `Config files in <path> are not trusted` in a
  non-interactive shell, and an activated shell skips the file with a warning
  (verified).
- **`[env]` can run code.** `_.source` scripts and `exec()`/`read_file()`
  templates execute whenever mise computes the environment. Dotenv, JSON, and
  YAML files are data: `$(...)` and backticks in a `.env` stayed literal
  (verified).
- **`mise x` and `mise run` trust implicitly.** Verified: in an untrusted
  directory, `mise x` ran the `_.source` script and the `exec()` template and
  recorded the directory as trusted. In a repo you did not write, read the
  config first; if it has `_.source`, `exec()`, hooks, or unusual paths, show
  the user and ask before running anything through mise.
- **`MISE_SAFE=1` ignores project `[env]` entirely**, directives included: no
  error, no `_.source`, no `exec()`, no venv, and the directory stays
  untrusted (verified). Use it to resolve tools in an untrusted repo, not to
  run the project's commands, which need their env.
- Never run `mise trust` on the user's behalf without asking.
- Never write plaintext secrets, tokens, or connection strings with
  credentials into a committed file, commit message, or PR text.

## Checklist before you finish

- [ ] Each value is in the right file (committed, local, per env, per task)
- [ ] No plaintext secret in a committed file; secrets marked `redact = true`
      or covered by `redactions`
- [ ] `mise.local.toml`, `mise.*.local.toml`, `.env`, and key files are in
      `.gitignore`; a `.env.example` exists if the project uses `.env`
- [ ] Encrypted files are scoped so a missing key does not break `mise ls`,
      `mise install`, or unrelated tasks; `sops filestatus` shows
      `{"encrypted":true}` before commit
- [ ] `required` is on the task that needs the value, not top-level, unless
      every command needs it
- [ ] Entries are ordered so each template only references earlier values;
      tool-derived values use `tools = true`
- [ ] Verified with `mise x -- printenv NAME` (or `test -n` for secrets) and,
      for environments, `mise -E <env> config ls`
- [ ] No secret printed into the transcript (`mise env`, `mise set KEY`)
- [ ] No `mise trust`, global config change, or shell rc edit without the
      user's say-so
- [ ] README/CONTRIBUTING say where contributors put their local values
