#!/usr/bin/env bash
# Example script: greet one or more targets (copy me).
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
install_traps

usage() {
  cat <<EOF
Usage: ${0##*/} [options] [TARGET...]

Greet one or more targets (default: world).

Options:
  -g, --greeting GREETING  hello, hi or howdy (default: hello)
  -n, --dry-run            Print what would run without doing it
  -h, --help               Show this help
EOF
}

greeting="hello"
targets=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  -g | --greeting)
    [[ $# -ge 2 ]] || die "--greeting needs a value. See --help." 2
    greeting="$2"
    shift
    ;;
  -n | --dry-run) export DRY_RUN=1 ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    targets+=("$@")
    break
    ;;
  -*) die "Unknown option '$1'. See --help." 2 ;;
  *) targets+=("$1") ;;
  esac
  shift
done

case "$greeting" in
hello | hi | howdy) ;;
*) die "Unknown greeting '$greeting': use hello, hi or howdy." 2 ;;
esac
[[ ${#targets[@]} -gt 0 ]] || targets=("world")

log_step "Greeting ${#targets[@]} target(s)"
work="" # pre-declare: make_tmpdir assigns by name, which shellcheck cannot see
make_tmpdir work
log_debug "Scratch space: $work"

for target in "${targets[@]}"; do
  log_info "Preparing greeting for '${target}'"
  run printf '%s, %s!\n' "$greeting" "$target"
done

# Handling an expected failure without dying: errexit is paused inside try.
rc=0 # pre-declare so shellcheck sees the assignment
try rc grep -q "nothing-matches-this" /dev/null
if [[ "$rc" -ne 0 ]]; then
  log_warn "Optional check found nothing (exit ${rc}); continuing"
fi

log_ok "Done"
