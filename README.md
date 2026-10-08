# Skills

A collection of [Claude Code](https://code.claude.com) agent skills. Each
skill is a top-level directory containing a `SKILL.md`, plus optional
`references/` and `assets/`.

## Inventory

- [`mise-tasks`](mise-tasks/SKILL.md) - Author repo scripts and automation as
  [mise](https://mise.jdx.dev/tasks/) tasks, with a shared shell library,
  color-coded logging, argument handling, and shellcheck/shfmt linting.

## Installing

Skills install with the [`skills` CLI](https://github.com/vercel-labs/skills)
(requires Node.js). It works with Claude Code and many other agents.

List what's available:

```sh
npx skills add JoshSLawrence/skills --list
```

Install one skill globally (`~/.claude/skills/`) for Claude Code:

```sh
npx skills add JoshSLawrence/skills --skill mise-tasks -g -a claude-code
```

Install every skill, or scope to the current project (`.claude/skills/`) by
dropping `-g`:

```sh
npx skills add JoshSLawrence/skills --all -g -a claude-code
```

Manage installed skills:

```sh
npx skills list -g
npx skills update -g
npx skills remove -g mise-tasks
```

By default the CLI keeps one canonical copy and symlinks each agent to it;
pass `--copy` for independent copies. Restart Claude Code (or start a new
session) to pick up new skills. The CLI sends anonymous telemetry unless
`DISABLE_TELEMETRY=1` is set.

## Contributing

Changes go through pull requests with Conventional Commit titles and
squash-only merges. See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow,
local development setup, and how to add a skill.
