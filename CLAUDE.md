# Skills Repository

Personal collection of Claude Code skills. See [README.md](README.md) for the
inventory and install steps and [CONTRIBUTING.md](CONTRIBUTING.md) for the
git/PR workflow.

## Layout

```text
<skill-name>/
├── assets/        files used in output (templates, configs)
├── references/    docs loaded on demand
└── SKILL.md       required; name + description frontmatter
README.md
```

## Conventions

- One skill per top-level directory; the directory name matches the `name`
  in its frontmatter.
- Keep `SKILL.md` under ~500 lines; push detail into `references/` and say
  when to read each file.
- The `description` is the trigger. Say what the skill does *and* when to
  use it, and err on the pushy side so it doesn't undertrigger.
- Explain the *why* behind instructions rather than shouting MUSTs.
- Verify claims against the real tool before writing them into a skill, and
  mark behavior you tested as verified (with the tool version).
- Any script shipped in `assets/` must pass its own linter (e.g. shellcheck,
  shfmt) and actually run. Never add lint suppressions without approval.
- Keep the README inventory in sync whenever a skill is added, renamed, or
  removed.
- Markdown stays within 80 columns (tables and URLs excepted; use
  `<!-- markdownlint-disable MD013 -->`).

## Git workflow

- Never commit or push to `main`. Work on a branch and open a PR.
- Commit messages and PR titles are Conventional Commits, scoped to the skill
  name (`feat(mise-tasks): ...`). Squash-only merge makes the PR title the
  commit on `main`.
- Confirm with the user before pushing, opening PRs, or changing GitHub
  settings.

## Testing

Skills here are mostly judgment and style rather than checkable output, so
formal eval suites are optional. Test shipped scripts in a scratch copy
(not in this repo) and iterate by reviewing real outputs.
