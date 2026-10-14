---
name: bash
description: Write bash scripts that fail fast, log a story a reader can follow, handle expected errors deliberately, and pass shellcheck and shfmt. Use this skill whenever you write, edit, refactor, or review a bash or sh script - a *.sh file, an extensionless file with a bash shebang, a git hook, an install or setup script, the body of a mise file task, or a multi-line `run:` block in CI - even for a quick one-off, and whenever shellcheck or shfmt findings come up.
---

<!-- markdownlint-disable MD013 -->
<!-- Wide tables and code are unwrappable. -->

# Writing bash scripts

A good script fails loudly at the first unexpected error, tells whoever runs
it what it is doing and what to do when something breaks, and lints clean.
These conventions get there without much ceremony.

If the script is repository automation, the `mise-tasks` skill covers where
it lives and how it is invoked; this skill covers what goes inside it.

## Workflow

1. **Look first.** Check for existing scripts, a shared helper library
   (`scripts/lib/`, `mise-tasks/.lib/`), `.shellcheckrc`, and
   `.editorconfig`. Match what exists instead of adding a second style.
2. **Scaffold from `assets/`** when there is nothing yet: copy
   `assets/scripts/lib/common.sh`, `assets/.shellcheckrc`, and
   `assets/.editorconfig`, and start from `assets/scripts/example.sh`.
3. **Write the script**, then run it for real: the happy path, `--help`, a
   bad argument, and `--dry-run` if it has one.
4. **Lint**: `shellcheck -x <files>` and `shfmt -d <files>` (or the repo's
   lint task). Fix findings at the source. Never add `# shellcheck
   disable=` or another suppression without the user's explicit approval
   after explaining the finding.
5. **Make it executable**: `chmod +x`, and if git already tracks the file,
   `git update-index --chmod=+x <file>` so the bit is committed.

## Conventions and why

- **`#!/usr/bin/env bash`**, so the bash on `PATH` runs it (Homebrew's
  bash 5 on macOS, not `/bin/bash` 3.2). Write `#!/bin/sh` only when the
  script must be POSIX, and then avoid bash-isms.
- **`set -euo pipefail`** right after the shebang. Failing fast beats a
  script that carries on after a broken step. Never drop strict mode to get
  past one failure; handle that failure explicitly (below).
- **Handle expected failures deliberately.** When a command may fail and
  you know what that means, pause errexit just around it, check the status,
  then restore it. The lib's `try rc cmd...` does this and keeps the `ERR`
  trap quiet:

  ```bash
  rc=0
  try rc grep -q pattern file
  if [[ $rc -ne 0 ]]; then log_warn "pattern missing; using defaults"; fi
  ```

  `if cmd; then` and `cmd || fallback` also work, but only for a single
  command (see the gotchas below for why not a function).
- **Log every significant step.** The output should tell a story someone can
  follow without reading the source: a `log_step` per phase, `log_info`
  before an operation, `log_warn` for non-fatal problems, `log_error`/`die`
  before failing.
- **Make errors actionable.** Say what went wrong *and* what to do:
  `die "kubectl not found: install it with 'mise use kubectl'"`, not
  `die "missing dependency"`.
- **Logs to stderr, data to stdout**, so `$(script)` and pipes capture only
  the result.
- **Quote every expansion** (`"$var"`, `"${arr[@]}"`) and use `[[ ]]` over
  `[ ]`. Read lines with `while IFS= read -r line`. Iterate files with globs
  or `find`, never by parsing `ls`.
- **Use arrays for commands and argument lists** instead of building a
  string and relying on word splitting.
- **Dry-run anything destructive or outward-facing.** The lib's `run`
  echoes each command and honors `DRY_RUN=1`.
- **Clean up temp files** with `make_tmpdir`/`track_cleanup` plus
  `install_traps`, so they go away even on failure.
- **Idempotent where practical**: a second run should be safe and quick.
- **Target bash 3.2** when the script must run on stock macOS without
  Homebrew bash: no associative arrays, `mapfile`, or `${var,,}`.
- **Parse arguments with a `while`/`case` loop** and give the script a
  `--help` (see `assets/scripts/example.sh`). Inside a mise file task,
  declare them with `#USAGE` instead (the `mise-tasks` skill).

## The shared library (`assets/scripts/lib/common.sh`)

Source it near the top, after `set -euo pipefail`. From a script in
`scripts/` with the lib in `scripts/lib/`:

```bash
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
install_traps
```

The `.shellcheckrc` (`source-path=SCRIPTDIR`, `external-sources=true`) lets
shellcheck follow that directive into the lib. Keep the lib non-executable
and free of side effects at source time.

| Helper                                   | Purpose                                                 |
| ---------------------------------------- | ------------------------------------------------------- |
| `log_info/ok/warn/error/step/debug`      | Color-coded, stderr; `debug` needs `VERBOSE=1`          |
| `die MSG [CODE]`                         | Log error and exit                                      |
| `require_cmd NAME [HINT]`, `require_env` | Precondition checks with actionable errors              |
| `run CMD...`                             | Echo (shell-quoted) then run; honors `DRY_RUN=1`        |
| `try RC_VAR CMD...`                      | Run with errexit paused; exit status into var           |
| `make_tmpdir VAR`, `track_cleanup PATH`  | Temp paths removed on exit                              |
| `install_traps`                          | Cleanup on exit; report the failing command             |
| `project_root`                           | `$MISE_PROJECT_ROOT`, else the git work tree, else dies |

`try` and `make_tmpdir` assign by variable name, which shellcheck can't see,
so pre-declare the variable (`rc=0`, `work=""`) to avoid SC2154.

Colors honor `NO_COLOR`, `FORCE_COLOR`, and `TERM=dumb`. Inside `mise run`
stderr is a pipe even in a terminal, so the lib also treats a mise-launched
task as color-capable; don't replace that with a plain `[ -t 2 ]` check.

Extend the lib when logic repeats across two or more scripts (retry with
backoff, confirmation prompts, git helpers).

## Strict-mode gotchas

Verified with bash 3.2.57 (macOS `/bin/bash`) and 5.3.20:

- **errexit is off inside a function called from `if`, `&&`, `||`, or
  `!`.** `if deploy; then` runs all of `deploy` with `-e` disabled, so a
  failing line in the middle doesn't stop it. Use `try` around the call
  instead, or have the function return explicit statuses.
- **`local x=$(cmd)` hides `cmd`'s failure**: the status is `local`'s.
  Declare first, then assign: `local x; x=$(cmd)` (shellcheck SC2155).
- **A failure inside `$(...)` doesn't stop the substitution.**
  `x=$(false; echo after)` sets `x` to `after`. Keep substitutions to one
  command, or `shopt -s inherit_errexit` (bash 4.4+).
- **`((i++))` returns 1 when the old value is 0**, which kills the script
  under `set -e` on bash 5.3 but not on 3.2. Write `i=$((i + 1))`.
- **`pipefail` fails `producer | head -n1`**: `head` exits early, the
  producer gets SIGPIPE, and the pipeline returns 141. Avoid the early exit
  (`awk 'NR==1'`, `sed -n 1p`) or handle the status with `try`.
- **Empty arrays under `set -u` on bash 3.2**: `"${arr[@]}"` aborts with
  "unbound variable". Use `"${arr[@]+"${arr[@]}"}"` when the array may be
  empty and the script must run on 3.2. `"$@"` with no arguments is fine.

## Scripts and tests that create git repos

Scripts and tests that create throwaway git repos must first
`unset $(git rev-parse --local-env-vars)`. Run from a git hook, they inherit
`GIT_DIR`/`GIT_INDEX_FILE`, and `git -C <tmp> ...` then writes to the real
repository (this has set `core.bare = true` and a fake identity in a real
`.git/config`). Before any `git config` or commit, check that
`git rev-parse --absolute-git-dir` in the temp repo is inside the temp
directory, and pass test identities with `git -c user.name=... -c
user.email=...` rather than writing config.

## Checklist before you finish

- [ ] `#!/usr/bin/env bash`, `set -euo pipefail`, executable bit committed
- [ ] Lib sourced and `install_traps` called if the script makes temp files
- [ ] A step line per phase; every error says what to do next
- [ ] Expected failures handled with `try` or a single-command `if`
- [ ] `--help`, input validation, and `--dry-run` for destructive actions
- [ ] Ran it: success path, `--help`, invalid input
- [ ] `shellcheck -x` and `shfmt -d` clean, with no new suppressions
