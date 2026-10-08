# Caching, sandboxing, templates, monorepos, telemetry

Read this when a task needs more than "run a script". Sources:
<https://mise.jdx.dev/tasks/caching.html>,
<https://mise.jdx.dev/sandboxing.html>,
<https://mise.jdx.dev/tasks/templates.html>,
<https://mise.jdx.dev/tasks/monorepo.html>,
<https://mise.jdx.dev/tasks/opentelemetry.html>,
<https://mise.jdx.dev/tasks/architecture.html>.

## Contents

- Skipping and caching work
- Sandboxing
- Task templates
- Monorepos
- OpenTelemetry
- Architecture notes

## Skipping and caching work

Two mechanisms; start with the first.

1. **Freshness (`sources` + `outputs`)** - stable, mtime based. If every
   output is newer than every source (and the task definition is unchanged),
   the task is skipped. Missing outputs force a rerun. `--force` bypasses.

   ```toml
   [tasks.build]
   run = "cargo build"
   sources = ["Cargo.toml", "src/**/*.rs"]
   outputs = ["target/debug/mycli"]
   ```

   In a file task: `#MISE sources=["src/**/*.rs"]` and
   `#MISE outputs=["dist"]`.

2. **Artifact cache** (experimental, `experimental = true`) - content hashed;
   restores outputs and replays logs on a hit. Needs `sources` and either
   explicit `outputs` or `outputs = []` (for pure checks like lint/test).

   ```toml
   cache = { enabled = true, env = ["NODE_ENV"],
             command_inputs = ["node --version"] }
   ```

   Enabling it is a correctness promise: same inputs must give same
   logs/outputs. Side effects (deploys, DB writes, notifications) are not
   replayed, so never cache them. List lockfiles in `sources`. Debug with
   `mise run --task-cache-explain <task>` and `cache.audit = true` (Linux,
   strace). Modes: `--task-cache read-only|write-only|off|local-only`.
   Remote cache setup: see the caching docs.

## Sandboxing

Restrict what a task can touch (least privilege). Flags work on
`mise run` and `mise exec`; per task use the same names as properties.

```toml
[tasks.lint]
run = "npm run lint"
deny_write = true

[tasks.build]
run = "npm run build"
deny_net = true
allow_write = ["./dist"]

[tasks.test]
run = "npm test"
deny_net = true
deny_write = true
allow_write = ["./coverage", "./node_modules/.cache"]
allow_env = ["NODE_*", "npm_*"]
```

Gotchas from the docs:

- Enforced via Landlock/seccomp on Linux (5.13+) and Seatbelt on macOS;
  **not enforced on Windows** (mise only warns), so a passing run proves
  nothing there.
- Linux rejects `--allow-net`; use `deny_net` or nothing.
- `allow_*` paths must already exist on Linux (missing ones are dropped).
- Allowing a parent directory allows everything inside it.
- Wildcard `allow_env` (`NODE_*`) can expose credentials with that prefix;
  prefer exact names.
- Only the child command is sandboxed, not config evaluation or tool install.
- Unix sockets remain usable under `deny_net`.

Good defaults to suggest: `deny_write` on lint/check tasks, `deny_net` on
build/test tasks that shouldn't phone home.

## Task templates

Share config across similar tasks with `[task_templates.<name>]` and
`extends`. Templates are not runnable themselves.

```toml
[task_templates."python:test"]
description = "Run pytest"
run = "uv run pytest"
tools = { python = "3.13" }

[tasks.test]
extends = "python:test"
run = "uv run pytest --cov"      # overrides the template run
```

File tasks use `#MISE extends="python:test"` (their script is the `run`).

Merge rules: `tools`/`env`/`vars` deep-merge; `depends*`, `sources`,
`outputs`, `cache` are replaced wholesale; `usage` is concatenated
(template first). An empty list (`depends = []`) inherits rather than
clears. Prefer templates defined in the repo over global ones so teammates
and CI resolve the same thing. Inspect the result with
`mise tasks info <task>`.

## Monorepos

```toml
# root mise.toml
monorepo_root = true

[monorepo]
config_roots = ["projects/frontend", "projects/backend"]
```

- Tasks are namespaced by path: `//projects/frontend:build`. `:build` means
  the nearest enclosing config root. Use `depends = [":lint"]` for relative
  references.
- Wildcards: `mise //...:test` (any depth), `'//projects/frontend:*'`. Quote
  them.
- Subprojects inherit `[tools]`, `[env]`, `[vars]`; task-level wins.
- List config roots explicitly; auto-discovery is deprecated.
- Use `MISE_PROJECT_ROOT` (subproject) vs `MISE_MONOREPO_ROOT` (top) for
  paths in scripts.
- `mise run --affected build` and `mise tasks graph` are experimental.

## OpenTelemetry

Experimental. `otel.enabled = true` (or `MISE_OTEL_ENABLED=1`) exports a
trace per `mise run` with per-task spans, plus `OTEL_EXPORTER_OTLP_ENDPOINT`.
Task args and argv are exported, so pass secrets through env vars, not
arguments. Log export is a separate opt-in and sends everything the task
prints.

## Architecture notes

- Discovery merges inline TOML tasks, includes, and file tasks across the
  config hierarchy; children override parents. A metadata-only TOML entry
  can add properties to a file task.
- Names resolve through aliases and partial matches; cycles are rejected
  before anything runs.
- A failed dependency prevents dependents; `depends_post` still runs if the
  parent started.
- Debug with `mise tasks deps`, `mise run --verbose`, `mise run --dry-run`,
  `mise tasks info`.
