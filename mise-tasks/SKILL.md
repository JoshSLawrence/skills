---
name: mise-tasks
description: Author repository scripts, automation, and developer tooling as mise tasks (mise.toml tasks and executable file tasks in mise-tasks/) - task layout, #MISE/#USAGE headers, argument parsing with the usage spec, dependencies and aggregates, and a lint task. Use this skill whenever the user wants to add, write, refactor, or organize a script, build/test/lint/deploy/release step, Makefile replacement, CI helper, or any repo automation - even if they never mention mise - and whenever a mise.toml, mise-tasks/ directory, or `mise run` is involved. Default to mise as the orchestrator for repo tasks.
---

<!-- markdownlint-disable MD013 -->
<!-- Wide tables, code, and the frontmatter description are unwrappable. -->

# Authoring mise tasks

mise is the front door for automation in a repository: contributors and CI
both run `mise run <task>`, and mise supplies the pinned tools, the
environment, dependency ordering, argument parsing, and `--help`. Your job is
to produce tasks that are small to invoke, safe to run, easy to read, and
lint-clean.

This skill covers the mise side: where tasks live, how they declare
arguments and dependencies, and how they're run. For the bash inside a task
(strict mode, logging, error handling, the helper library, strict-mode
gotchas), load the `bash` skill.

Docs: <https://mise.jdx.dev/tasks/>. Details live in `references/`; read the
one you need rather than all of them:

- `references/task-options.md` - every task property, dependency semantics,
  `run` steps, output/parallelism flags
- `references/arguments.md` - the `usage` spec (flags, args, choices, env)
  and how values reach the script
- `references/advanced.md` - caching, sandboxing, templates, monorepos,
  OpenTelemetry

## Workflow

1. **Look first.** Check for an existing `mise.toml`, a task directory
   (`mise-tasks/`, `.mise/tasks/`, `.config/mise/tasks/`), a shared lib, and
   lint config. Run `mise tasks ls`. Extend what exists and match its style
   instead of introducing a second layout.
2. **Choose the format** (see below).
3. **Scaffold from `assets/`** when the repo has no conventions yet: copy
   `assets/mise-tasks/.lib/common.sh`, `.shellcheckrc`, `.editorconfig`,
   the `lint` task, and the `check` entry from `assets/mise.toml`. Add the
   linters with `mise use --pin shellcheck@latest shfmt@latest` so they land
   as exact versions (see the `mise-tools` skill). Use
   `assets/mise-tasks/example-task` as the starting point for new tasks.
4. **Write the task** (the script body follows the `bash` skill), then run
   it for real: happy path, `--help`, a bad argument, and (if it has one)
   `--dry-run`.
5. **Lint**: `mise run lint`. Fix findings at the source. Do not add
   `# shellcheck disable=` or similar suppressions without the user's
   explicit approval.
6. **Wire it up**: add the task to an aggregate (`check`, `ci`) if it belongs
   there, and update README/CONTRIBUTING mentions so docs don't drift.

## Choosing a format

| Situation                                        | Use                    |
| ------------------------------------------------ | ---------------------- |
| One-liner, or only wires dependencies together   | TOML task in mise.toml |
| Logic, loops, error handling, args, > ~3 lines   | File task              |
| Not shell (Python, Node, ...)                    | File task + shebang    |
| Many near-identical tasks                        | Task template          |

File tasks are the default for anything real because editors, shellcheck, and
shfmt all understand a script file; they cannot see inside a TOML string.
Keep `mise.toml` as the readable index: descriptions, `depends`, aggregates.

## Repository layout

```text
.editorconfig
.shellcheckrc
mise-tasks/
├── .lib/
│   └── common.sh
├── deploy
├── lint
└── test/
    ├── _default
    └── integration
mise.toml
```

- `mise-tasks/test/integration` becomes task `test:integration`;
  `test/_default` becomes `test`.
- Put shared code in `mise-tasks/.lib/` and leave it **non-executable**.
  Verified behavior: mise registers every executable file outside
  dot-directories as a task (even `_common`), so a helper placed beside the
  tasks would show up in `mise tasks`. Dot-directories are never scanned.
- Tasks must be executable (`chmod +x`), and the bit must be committed:
  `git update-index --chmod=+x mise-tasks/<name>` if the file was added
  before `chmod`. An unexecutable file is silently not a task.

## Anatomy of a file task

```bash
#!/usr/bin/env bash
#MISE description="Deploy the app to an environment"
#USAGE arg "<env>" help="Target environment" {
#USAGE   choices "dev" "staging" "prod"
#USAGE }
#USAGE flag "-n --dry-run" help="Show what would happen"
set -euo pipefail

# shellcheck source=mise-tasks/.lib/common.sh
source "${MISE_PROJECT_ROOT:?run via 'mise run <task>'}/mise-tasks/.lib/common.sh"
install_traps

[[ "${usage_dry_run:-false}" == "true" ]] && export DRY_RUN=1
log_step "Deploying to ${usage_env?}"
run ./scripts/deploy.sh "${usage_env?}"
log_ok "Deployed"
```

Conventions and the reasons behind them:

- **The body is an ordinary bash script**: shebang, `set -euo pipefail`,
  step logging, `try` for expected failures, logs to stderr and data to
  stdout, as the `bash` skill describes.
- **`#MISE` / `#USAGE` have no space** after `#`. `# MISE` is silently
  ignored. If a formatter rewrites the comments, use `# [MISE]`.
- **Always set `description`.** It powers `mise tasks`, `--help`, completion.
- **Source the lib via `$MISE_PROJECT_ROOT`**, not `$0`-relative paths, so
  nesting depth (`test/integration`) doesn't matter. The `:?` guard turns
  "ran the script directly" into an actionable error. Pair the `# shellcheck
  source=` directive with `.shellcheckrc` so linting follows into the lib.
- **Tasks run in `$MISE_CONFIG_ROOT`** by default, not the caller's cwd. Use
  `$MISE_ORIGINAL_CWD` (or `dir="{{cwd}}"`) when you need the caller's
  location. Use `MISE_PROJECT_ROOT` for repo-relative paths (stable in
  monorepos).
- **Idempotent and re-runnable** where practical; use `sources`/`outputs`
  for build-like tasks so mise skips up-to-date work.
- **Plaintext secrets never live in `mise.toml` or scripts.** Read them from
  the environment and fail with a message telling the user where to set them
  (`require_env NAME "hint"`). Where values and secrets come from (local
  files, encrypted files, per-environment config) is the `mise-env` skill.

## The shared library (`.lib/common.sh`)

`assets/mise-tasks/.lib/common.sh` is the `bash` skill's helper library
(logging, `die`, `require_cmd`/`require_env`, `run` with `DRY_RUN`, `try`,
temp-dir cleanup, `install_traps`, `project_root`); CI keeps the two copies
identical. The `bash` skill documents each helper. The mise-specific parts:

- It lives in `mise-tasks/.lib/`, non-executable, so mise doesn't register
  it as a task (see the layout above).
- Tasks source it via `$MISE_PROJECT_ROOT`, and `project_root` returns that
  same directory.
- Inside `mise run`, stderr is a pipe even in a terminal; the lib treats a
  mise-launched task as color-capable so logs keep their colors.

Extend the lib when logic repeats across two or more tasks, and keep it
bash 3.2 compatible so tasks run on stock macOS.

## Arguments

Declare them with `#USAGE` (file tasks) or `usage = '''...'''` (TOML tasks);
never parse `$1`/`getopts` by hand, since the spec gives validation, `--help`,
completion, and typo errors for free. Read values from `usage_<name>`
variables (dashes become underscores). Behaviors verified against mise:

- Boolean flags are `"true"` when passed and **unset otherwise**: read with
  `${usage_flag:-false}` under `set -u`.
- Flags/args with a `default` are always set: `${usage_name?}` is safe.
- Variadic args (`var=#true`) arrive as a single shell-quoted string:
  `eval "items=(${usage_items-})"` rebuilds the array.
- mise flags go **before** the task name (`mise run -j1 build`); anything
  after the name belongs to the task. `--` separates explicitly.
- Do not use the `{{arg(...)}}`/`{{flag(...)}}` Tera functions; they are
  deprecated (removal planned for 2027.5.0).

See `references/arguments.md` for the full spec syntax.

## Orchestration

- `depends` runs prerequisites **in parallel, in no guaranteed order**. For
  ordered steps, use a `run` array of steps:
  `run = [{ task = "build" }, { tasks = ["lint", "test"] }]`.
- `depends_post` is for cleanup that must run even after failure;
  `wait_for` only orders against tasks already scheduled.
- Provide aggregates (`check`, `ci`) so CI calls exactly one command that
  contributors can also run locally. CI should install mise and run
  `mise run ci`, not duplicate the steps in workflow YAML.
- Group related tasks with `:` names (`test:unit`, `db:migrate`) and quote
  them in TOML: `[tasks."test:unit"]`.
- `mise run 'test:*'` runs wildcards; quote the pattern.
- Pin linters and tools in `[tools]` so every contributor and CI lint the
  same way. The `mise-tools` skill covers exact pins and `mise.lock`.

## Non-shell tasks

A shebang is all mise needs, so use the right language for the job, e.g.
`#!/usr/bin/env -S uv run --script` for Python or `#!/usr/bin/env node`. The
`#MISE`/`#USAGE` headers work with `//MISE` / `//USAGE` for JS-style comments.
Lint with the language's own tool (ruff, eslint) and add it as a task under
`lint`. Shared helpers for those languages belong in the same dot-directory.

## Checklist before you finish

- [ ] Executable bit set (and staged as executable in git)
- [ ] `description`, `#USAGE` for every input, sensible defaults
- [ ] Body meets the `bash` skill's checklist (strict mode, lib, logging,
      dry-run for anything destructive)
- [ ] `mise run lint` passes with no new suppressions
- [ ] Ran it: success path, `--help`, invalid input
- [ ] Added to an aggregate task and mentioned in docs if user-facing
