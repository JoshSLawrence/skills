<!-- markdownlint-disable MD013 -->

# Task options and running tasks

Source: <https://mise.jdx.dev/tasks/task-configuration.html>,
<https://mise.jdx.dev/tasks/toml-tasks.html>,
<https://mise.jdx.dev/tasks/running-tasks.html>. Options marked
(experimental) require `experimental = true` under `[settings]`.

## Contents

- Core properties
- Behavior and I/O properties
- Dependencies and ordering
- `run` forms
- Environment variables mise provides
- Running tasks: flags, output, parallelism
- Settings worth knowing

## Core properties

Valid in `[tasks.<name>]` and, for file tasks, as `#MISE key=value`.

| Option         | Meaning                                                    |
| -------------- | ---------------------------------------------------------- |
| `description`  | Shown in help, completion, `mise tasks`                    |
| `run`          | String, array (series), or step array                      |
| `run_windows`  | Windows variant of `run`                                   |
| `file`         | External script (path, URL, or `git::` source)             |
| `alias`        | Alternate name(s); a real task of that name wins           |
| `depends`      | Prerequisites (parallel, unordered)                        |
| `depends_post` | Run after the task, even if it failed                      |
| `wait_for`     | Order after these only if already scheduled                |
| `env`          | Env vars for this task only (not passed to dependencies)   |
| `vars`         | Template values (`{{ vars.x }}`), not exported as env      |
| `tools`        | Tools installed/activated for this task only               |
| `dir`          | Working dir (default `{{ config_root }}`)                  |
| `shell`        | Shell for TOML tasks, e.g. `bash -c`                       |
| `usage`        | Argument spec (see arguments.md)                           |
| `hide`         | Hide from listings                                         |
| `timeout`      | e.g. `30s`, `5m`; kills runaway tasks                      |

## Behavior and I/O properties

| Option         | Meaning                                                    |
| -------------- | ---------------------------------------------------------- |
| `confirm`      | Prompt before the task's own `run` (deps run first). Prefer this over hand-rolled prompts for destructive tasks |
| `raw`          | Connect directly to stdin/stdout/stderr (per command)      |
| `interactive`  | Exclusive terminal; blocks other tasks                     |
| `raw_args`     | Pass all args through untouched, including `--help`        |
| `quiet`        | Hide mise's own output (the echoed command)                |
| `silent`       | Hide all task output (or `"stdout"` / `"stderr"`)          |
| `output`       | `prefix`, `interleave`, `keep-order`, `replacing`, `timed`, `silent` |
| `sources` / `outputs` | Freshness skipping; `!` excludes; `outputs = { auto = true }` tracks without files |
| `cache`        | (experimental) content-addressed result cache              |
| `secrets`      | (experimental) secret keys passed to the task, redacted    |
| `watch`        | Options for `mise watch`                                   |
| `daemons`      | (experimental) services that must be up first              |
| `deny_*` / `allow_*` | Sandboxing; see advanced.md                          |

Stdin is not connected by default. A task that prompts needs
`interactive = true` or `raw = true`.

## Dependencies and ordering

- `depends`: must succeed first; a failure blocks dependents. Shared
  dependencies run once. **No ordering among siblings.**
- `depends_post`: cleanup/notify; runs if the parent started, success or not.
- `wait_for`: soft ordering only; never schedules the target. Does not break
  cycles.
- Wildcards work in dependencies: `depends = ["lint:*"]`.
- Forward arguments with `depends = ["build {{ usage.env }}"]`.
- Inspect: `mise tasks deps [task]`, `mise tasks deps --dot`.
- A script that itself calls `mise run` starts a separate run that is not
  part of the graph; prefer `depends` / `run` steps.

## `run` forms

```toml
[tasks.a]
run = "cargo build"                 # string

[tasks.b]
run = ["cargo fmt --check", "cargo test"]   # series; stops at first failure

[tasks.c]
run = [                             # ordered steps, mixing tasks
  { task = "build" },
  { tasks = ["lint", "test"] },     # these two run in parallel
]

[tasks.d]
run = '''
#!/usr/bin/env bash
set -euo pipefail
echo multi-line script
'''

[tasks.e]
file = "scripts/release.sh"         # external script
```

- Without a `usage` spec, args go only to the last entry of an array.
- Without a shebang, TOML `run` uses `sh -c` (Unix) / `cmd /c` (Windows), so
  bash-isms fail. Add a shebang or `shell = "bash -c"`.
- `set -e` is applied for sh/bash/zsh in TOML scripts.

## Environment variables mise provides

| Variable            | Meaning                                              |
| ------------------- | ---------------------------------------------------- |
| `MISE_PROJECT_ROOT` | Root of the project defining the task (stable in monorepos) |
| `MISE_CONFIG_ROOT`  | Directory holding the defining `mise.toml`           |
| `MISE_ORIGINAL_CWD` | Where the user invoked mise                          |
| `MISE_TASK_NAME`    | Running task's name                                  |
| `MISE_TASK_DIR`     | Directory containing the task script                 |
| `MISE_TASK_FILE`    | Full path to the task script                         |
| `MISE_TASK_COLOR`   | ANSI prefix color (empty if disabled)                |
| `MISE_MONOREPO_ROOT`| Monorepo root, only inside a monorepo                |

## Running tasks: flags, output, parallelism

```bash
mise run build                    # also: mise r build, mise build
mise run build --release          # args after the name go to the task
mise run -j 1 build               # mise flags BEFORE the name
mise run build arg1 ::: test arg2 # several tasks, each with args
mise run 'test:*'                 # wildcard (quote it)
mise run --dry-run build          # show what would run
mise run --force build            # ignore sources/outputs freshness
mise run --verbose build
mise tasks ls [--hidden]          # list
mise tasks info build             # final definition after inheritance
mise watch build                  # rerun on source changes (needs watchexec)
```

- Prefer `mise run <task>` over `mise <task>` in scripts and CI: the short
  form can be shadowed by future mise commands.
- Default parallelism is 8 jobs (`--jobs`, `MISE_JOBS`, `jobs` setting);
  `-j 1` also switches to interleaved output.
- `mise run` with no name runs the `default` task if defined, otherwise opens
  a selector (interactive only).
- Output style: `--output`, `MISE_TASK_OUTPUT`, or `task.output`.

## Settings worth knowing

Under `[settings]`: `task.timeout` (global cap), `task.timings` (elapsed
time per task), `task.show_full_cmd`, `task.skip` / `task.skip_depends`,
`task.run_auto_install` (default true: missing tools install before a task
runs), `task.output`, `task.quiet`.
