#!/usr/bin/env bash
# Shared helpers for mise file tasks. Source it; do not execute it.
#
# Lives in a dot-directory and is intentionally NOT executable: mise only
# registers executable files outside dot-directories as tasks, so this stays
# out of `mise tasks`.
#
# Usage from a task:
#   set -euo pipefail
#   # shellcheck source=mise-tasks/.lib/common.sh
#   source "${MISE_PROJECT_ROOT:?run via 'mise run <task>'}/mise-tasks/.lib/common.sh"
#
# Targets bash 3.2+ (macOS system bash) -- no associative arrays, mapfile, or
# ${var,,}.

# Guard against double-sourcing (tasks that source helpers that source us).
[[ -n "${_MISE_COMMON_LOADED:-}" ]] && return 0
_MISE_COMMON_LOADED=1

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
# Inside `mise run`, stdout/stderr are pipes, so `[ -t 2 ]` is false even in an
# interactive terminal. Treat a mise-launched task as color-capable unless the
# user opted out.
_use_color() {
  [[ -n "${NO_COLOR:-}" ]] && return 1
  [[ "${TERM:-}" == "dumb" ]] && return 1
  [[ -n "${FORCE_COLOR:-}${CLICOLOR_FORCE:-}" ]] && return 0
  [[ -t 2 ]] && return 0
  [[ -n "${MISE_TASK_NAME:-}" ]] && return 0
  return 1
}

if _use_color; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_CYAN=$'\033[36m'
else
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN=''
fi

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
# Everything goes to stderr so stdout stays clean for data that callers may
# pipe or capture ($(mise run ...)).

log_info() { printf '%s[INFO]%s  %s\n' "$C_BLUE" "$C_RESET" "$*" >&2; }
log_ok() { printf '%s[ OK ]%s  %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
log_warn() { printf '%s[WARN]%s  %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error() { printf '%s[ERR ]%s  %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
log_step() { printf '\n%s==> %s%s\n' "$C_BOLD$C_CYAN" "$*" "$C_RESET" >&2; }

# Only prints when VERBOSE=1 (or DEBUG=1), so tasks can be chatty on demand.
log_debug() {
  [[ "${VERBOSE:-${DEBUG:-0}}" == "1" ]] || return 0
  printf '%s[DBG ]%s  %s\n' "$C_DIM" "$C_RESET" "$*" >&2
}

# die MESSAGE [EXIT_CODE]
# Messages should say what went wrong AND what to do about it.
die() {
  log_error "$1"
  exit "${2:-1}"
}

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

# require_cmd NAME [HINT]
require_cmd() {
  command -v "$1" >/dev/null 2>&1 ||
    die "Required command '$1' not found.${2:+ $2}"
}

# require_env NAME [HINT]
require_env() {
  [[ -n "${!1:-}" ]] || die "Required environment variable '$1' is not set.${2:+ $2}"
}

# ---------------------------------------------------------------------------
# Running commands
# ---------------------------------------------------------------------------

# run CMD [ARGS...]
# Logs the command before running it. Honors DRY_RUN=1 so a task can expose
# a --dry-run flag by exporting DRY_RUN from its #USAGE flag.
run() {
  # %q shows the command as the shell will see it, so quoting bugs are visible.
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s[DRY ]%s  %s\n' "$C_YELLOW" "$C_RESET" "$(printf '%q ' "$@")" >&2
    return 0
  fi
  printf '%s$ %s%s\n' "$C_DIM" "$(printf '%q ' "$@")" "$C_RESET" >&2
  "$@"
}

# try RC_VAR CMD [ARGS...]
# Runs CMD with errexit temporarily disabled, assigns its exit status to the
# variable named RC_VAR, and always returns 0. The caller decides what a
# failure means:
#   rc=0   # pre-declare: shellcheck cannot see assignments made by name
#   try rc grep -q pattern file
#   if [[ $rc -ne 0 ]]; then log_warn "no match"; fi
try() {
  local _rc_var="$1" _status errexit_was_set=0 err_trap
  shift
  [[ $- == *e* ]] && errexit_was_set=1
  # bash fires ERR traps even with errexit off; suspend ours so an expected
  # failure is not reported as an unexpected one.
  err_trap="$(trap -p ERR)"
  trap - ERR
  set +e
  "$@"
  _status=$?
  [[ $errexit_was_set -eq 1 ]] && set -e
  [[ -n "$err_trap" ]] && eval "$err_trap"
  printf -v "$_rc_var" '%s' "$_status"
  return 0
}

# ---------------------------------------------------------------------------
# Cleanup & error reporting
# ---------------------------------------------------------------------------

_CLEANUP_PATHS=()

_cleanup() {
  local p
  for p in "${_CLEANUP_PATHS[@]+"${_CLEANUP_PATHS[@]}"}"; do
    rm -rf -- "$p"
  done
}

_on_err() {
  # Args captured by the trap: exit status, line number, failing command.
  log_error "Command failed (exit $1) at line $2: $3"
  log_error "Re-run with VERBOSE=1 for more detail, or run the command by hand to reproduce."
}

# track_cleanup PATH... -> remove these paths when the task exits.
track_cleanup() {
  _CLEANUP_PATHS+=("$@")
}

# make_tmpdir VARNAME -> creates a temp dir, assigns its path to VARNAME, and
# removes it on exit. Takes a variable name instead of printing the path
# because $(...) runs in a subshell, where cleanup tracking would be lost.
#   make_tmpdir work
#   cp input "$work/"
make_tmpdir() {
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/mise-task.XXXXXX")"
  track_cleanup "$dir"
  printf -v "$1" '%s' "$dir"
}

# install_traps -> run cleanup on exit and report which command failed when
# errexit kills the task. Call once near the top of a task, after sourcing.
# `set -E` makes the ERR trap fire inside functions too.
install_traps() {
  set -E
  trap '_cleanup' EXIT
  trap '_on_err "$?" "$LINENO" "$BASH_COMMAND"' ERR
}

# ---------------------------------------------------------------------------
# Project paths
# ---------------------------------------------------------------------------

# Resolved lazily so sourcing never fails outside mise; fails loudly on use.
project_root() {
  printf '%s\n' "${MISE_PROJECT_ROOT:?run via 'mise run <task>' so MISE_PROJECT_ROOT is set}"
}
