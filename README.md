# Skills

A collection of [Claude Code](https://code.claude.com) agent skills. Each
skill is a top-level directory containing a `SKILL.md`, plus optional
`references/` and `assets/`.

## Inventory

- [`bash`](bash/SKILL.md) - Write bash scripts that fail fast, log a
  readable story, handle expected errors deliberately, and pass shellcheck
  and shfmt, with a shared helper library and the strict-mode gotchas.
- [`ci-pipelines`](ci-pipelines/SKILL.md) - Write GitHub Actions and Azure
  Pipelines that fail cleanly and deploy in order: job timeouts above tool
  timeouts, one approval environment per deployment, deploy concurrency,
  pinned actions, least-privilege tokens, and injection-safe `run:` steps.
- [`markdown-style`](markdown-style/SKILL.md) - Write markdown that reads
  well raw and renders where it's published: alerts by default (bold notes
  for Azure DevOps), 80-column wrapping, aligned tables, sorted directory
  trees, and copy-paste-friendly code blocks.
- [`mise-env`](mise-env/SKILL.md) - Set project environment variables with
  [mise](https://mise.jdx.dev/environments/): `[env]` in `mise.toml`, `.env`
  files, per-environment config with `MISE_ENV`, sops/age-encrypted secrets
  and redaction, and Python venvs that activate automatically.
- [`mise-tasks`](mise-tasks/SKILL.md) - Author repo scripts and automation as
  [mise](https://mise.jdx.dev/tasks/) tasks: layout, `#MISE`/`#USAGE`
  headers, argument parsing, dependencies and aggregates, and a lint task.
  Pairs with `bash` for the script bodies.
- [`mise-tools`](mise-tools/SKILL.md) - Install, pin, lock, and run dev tools
  and runtimes with [mise](https://mise.jdx.dev/dev-tools/): `[tools]` in
  `mise.toml`, a committed `mise.lock`, backend choice, CI setup, and running
  the right version from an agent shell.

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
npx skills add JoshSLawrence/skills --skill '*' -g -a claude-code -y
```

Avoid `--all` here: it is shorthand for `--skill '*' --agent '*' -y`, so it
overrides `-a` and installs into every agent the CLI supports (about 50
directories in your home folder), with errors for agents that have no global
skills directory (verified with `skills` 1.7.2).

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
