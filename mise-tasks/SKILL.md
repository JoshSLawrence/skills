---
name: mise-tasks
description: Author repository scripts, automation, and developer tooling as mise tasks (mise.toml tasks and executable file tasks in mise-tasks/) with shared shell libraries, color-coded logging, shellcheck/shfmt linting, and proper argument handling. Use this skill whenever the user wants to add, write, refactor, or organize a script, build/test/lint/deploy/release step, Makefile replacement, CI helper, or any repo automation - even if they never mention mise - and whenever a mise.toml, mise-tasks/ directory, or `mise run` is involved. Default to mise as the orchestrator for repo tasks.
---

<!-- markdownlint-disable MD013 -->
<!-- Wide tables, code, and the frontmatter description are unwrappable. -->

# Authoring mise tasks

mise is the front door for automation in a repository: contributors and CI
both run `mise run <task>`, and mise supplies the pinned tools, the
environment, dependency ordering, argument parsing, and `--help`. Your job is
to produce tasks that are small to invoke, safe to run, easy to read, and
lint-clean.

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
   the `lint` task, and the `[tools]`/`check` entries from `assets/mise.toml`.
   Use `assets/mise-tasks/example-task` as the starting point for new tasks.
4. **Write the task**, then run it for real: happy path, `--help`, a bad
   argument, and (if it has one) `--dry-run`.
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

- **`#!/usr/bin/env bash` + `set -euo pipefail`** at the top of every bash
  task. Failing fast beats half-finished automation. Handle an *expected*
  failure with `try` (errexit paused locally) instead of removing strict
  mode.
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
- **Logs go to stderr, data to stdout**, so `$(mise run thing)` captures only
  the result.
- **Idempotent and re-runnable** where practical; use `sources`/`outputs`
  for build-like tasks so mise skips up-to-date work.
- **Secrets never live in `mise.toml` or scripts.** Read them from the
  environment and fail with a message telling the user where to set them
  (`require_env NAME "hint"`).

## The shared library (`.lib/common.sh`)

`assets/mise-tasks/.lib/common.sh` is tested against mise and shellcheck. It
provides:

| Helper                                   | Purpose                                      |
| ---------------------------------------- | -------------------------------------------- |
| `log_info/ok/warn/error/step/debug`      | Color-coded, stderr; `debug` needs `VERBOSE=1` |
| `die MSG [CODE]`                         | Log error and exit                           |
| `require_cmd NAME [HINT]`, `require_env` | Precondition checks with actionable errors   |
| `run CMD...`                             | Echo (shell-quoted) then run; honors `DRY_RUN=1` |
| `try RC_VAR CMD...`                      | Run with errexit paused; exit status into var |
| `make_tmpdir VAR`, `track_cleanup PATH`  | Temp paths removed on exit                   |
| `install_traps`                          | Cleanup on exit; report the failing command  |
| `project_root`                           | `$MISE_PROJECT_ROOT` or an actionable error  |

Extend the lib when logic repeats across two or more tasks (git helpers,
retry/backoff, JSON parsing wrappers, confirmation prompts). Keep it
bash 3.2 compatible so tasks run on stock macOS. Keep it free of side
effects at source time.

Color note: inside `mise run`, stdout/stderr are pipes, so `[ -t 2 ]` is
false even in a terminal. The lib treats a mise-launched task as
color-capable and honors `NO_COLOR`, `FORCE_COLOR`, and `TERM=dumb`. Don't
reintroduce a plain TTY check.

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
  same way.

## Non-shell tasks

A shebang is all mise needs, so use the right language for the job, e.g.
`#!/usr/bin/env -S uv run --script` for Python or `#!/usr/bin/env node`. The
`#MISE`/`#USAGE` headers work with `//MISE` / `//USAGE` for JS-style comments.
Lint with the language's own tool (ruff, eslint) and add it as a task under
`lint`. Shared helpers for those languages belong in the same dot-directory.

## Checklist before you finish

- [ ] Executable bit set (and staged as executable in git)
- [ ] `description`, `#USAGE` for every input, sensible defaults
- [ ] `set -euo pipefail`, lib sourced, `install_traps` if it makes temp files
- [ ] Meaningful logging: a step line per phase, actionable error messages
- [ ] Dry-run support for anything destructive or outward-facing
- [ ] `mise run lint` passes with no new suppressions
- [ ] Ran it: success path, `--help`, invalid input
- [ ] Added to an aggregate task and mentioned in docs if user-facing
