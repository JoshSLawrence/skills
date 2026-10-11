<!-- markdownlint-disable MD013 -->
<!-- Wide tables and code samples are unwrappable. -->

# Hooks, direnv, and plain `.env` files

Read this when something should happen on entering a project, when a repo has
an `.envrc`, or when choosing between mise, direnv, and a plain `.env`.
Behavior verified against mise 2026.10.7 unless marked "docs". Sources:
<https://mise.jdx.dev/hooks.html>, <https://mise.jdx.dev/direnv.html>.

## Contents

- Hooks vs `[env]`
- Directory hooks
- Exporting from a hook
- Migrating from direnv
- When to keep direnv or a plain `.env`

## Hooks vs `[env]`

Use `[env]` for variables: mise sets them on entry and removes them on leave
(verified: `PROJ_VAR` was gone after `cd` out of the project). Use hooks for
side effects such as printing a notice or loading shell completions. A hook
that exports a variable has to clean it up itself.

| Event                       | Runs when                          | Needs `mise activate` |
| --------------------------- | ---------------------------------- | --------------------- |
| `enter`                     | The shell moves into the project   | Yes                   |
| `leave`                     | The shell moves out                | Yes                   |
| `cd`                        | Any directory change inside it     | Yes                   |
| `preinstall`, `postinstall` | mise installs tools                | No                    |
| `[[watch_files]]`           | A watched file changed (at prompt) | Yes                   |

Agent shells, CI, and `mise x` are not activated, so directory hooks never
run there (verified: `mise x` in the project did not see the variable an
`enter` hook exports). Never put setup that CI or an agent needs in a hook;
make it a task.

## Directory hooks

```toml
[hooks]
enter = "echo 'run mise run setup on a fresh clone' >&2"
cd = "echo changed dir >&2"
leave = "echo bye >&2"
```

Verified in a non-interactive bash with `eval "$(mise activate bash)"`:

- Entering ran `cd` then `enter`; moving within the project ran only `cd`;
  leaving ran `leave`.
- A spawned hook sees the project's `[env]` (`PROJ_VAR=set-by-env` was
  printed by the `enter` hook).
- Output goes to stderr; a failing hook only warns (docs).
- Hooks need trust and are skipped under `--no-hooks`, `MISE_NO_HOOKS=1`, and
  `MISE_SAFE=1` (docs; see the `mise-tools` skill for trust).
- Global-config directory hooks run on every directory change (docs).

## Exporting from a hook

A `run` hook is a child process, so its `export` cannot reach the shell
(docs). To change the current shell, use `script` with `shell`:

```toml
[hooks]
enter = { shell = "bash", script = "export FROM_HOOK=hooked" }
leave = { shell = "bash", scripts = ["unset FROM_HOOK"] }
```

Verified: `FROM_HOOK=hooked` was set after entering and unset after leaving.
The script only runs in the named shell (a zsh user gets nothing from
`shell = "bash"`; docs), and mise does not undo it, hence the `leave`. If the
value is a plain variable, `[env]` does all of this for you.

## Migrating from direnv

direnv and mise on the same directory is unsupported (docs): both rewrite the
environment on `cd` and disagree about `PATH`. Map each `.envrc` line:

| `.envrc`                                 | mise                                                    |
| ---------------------------------------- | ------------------------------------------------------- |
| `export NODE_ENV=development`            | `NODE_ENV = "development"` under `[env]`                |
| `dotenv` / `dotenv_if_exists`            | `_.file = ".env"` (missing files are skipped; verified) |
| `PATH_add bin`                           | `_.path = "bin"`                                        |
| `source script.sh`                       | `_.source = "script.sh"`                                |
| `source_env_if_exists .envrc.local`      | `mise.local.toml`, gitignored                           |
| `source_up`                              | Nothing; parent configs already merge (verified)        |
| `layout python`                          | `_.python.venv` (`python-venvs.md`)                     |
| `layout node`                            | `_.path = "node_modules/.bin"`                          |
| `use nix`, `use flake`, custom functions | No equivalent; keep direnv for that repo                |

Steps:

1. Write the mise config, then compare `mise env --json` (non-secret values)
   with what direnv exported.
2. Delete the moved lines or the whole `.envrc` in the same change, and update
   README/CONTRIBUTING setup steps.
3. Ask before touching the user's shell rc: removing `eval "$(direnv hook
   zsh)"` and adding `mise activate` are their files to change. If they still
   use direnv in other repos, leave the hook.
4. `use mise` in `.envrc` (the `mise direnv` integration) is deprecated:
   verified, `mise direnv` warns `deprecated [cli.direnv] ... This will be
   removed in mise 2027.10.4.` Replace it with `mise activate`.

A newly written `mise.toml` with `[env]` needs trust before an activated shell
applies it (verified: the shell warned `... is not trusted, run 'mise trust'`
and skipped it). Tell the user to review and trust it; do not run
`mise trust` for them.

## When to keep direnv or a plain `.env`

- **Keep direnv** when the repo does not use mise and the user has not asked
  to adopt it, when `.envrc` relies on nix or custom shell functions, or when
  teammates depend on it and the migration has not been agreed.
- **Keep a plain `.env`** when the app, a framework, docker compose
  (`env_file:`), or an IDE run configuration reads it directly. mise then
  loads the same file with `_.file`; do not duplicate the values in
  `mise.toml`.
- **Use mise `[env]`** when the repo already uses mise for tools or tasks,
  when values should come with the right tools, or when you need per-environment
  files, templates, encrypted secrets, or venv activation.
