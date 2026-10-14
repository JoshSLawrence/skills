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
(requires Node.js). The commands below put one copy in the shared
`.agents/skills/` directory, which Codex, Cline, Pi, Warp, Zed and other
agents read, and symlink Claude Code to it (`-a universal claude-code`).

List what's available:

```sh
npx skills add JoshSLawrence/skills --list
```

Install one skill globally (`~/.agents/skills/`, linked from
`~/.claude/skills/`):

```sh
npx skills add JoshSLawrence/skills --skill bash -g -a universal claude-code
```

Install every skill, or drop `-g` to install into the current project
(`.agents/skills/`, linked from `.claude/skills/`):

```sh
npx skills add JoshSLawrence/skills --skill '*' -g -a universal claude-code -y
```

Always name the agents. `-a claude-code` on its own copies into
`~/.claude/skills/` only, so no other agent sees the skill. `--all` (shorthand
for `--skill '*' --agent '*' -y`) or `-a '*'` writes a directory for every
supported agent, about 50 in your home folder. The CLI's agent table lists
`~/.config/agents/skills/` for `universal`, but it installs to
`~/.agents/skills/` (verified with `skills` 1.7.2).

Manage installed skills (`remove` cleans up both directories):

```sh
npx skills list -g
npx skills update -g
npx skills remove -g bash
```

Restart Claude Code (or start a new session) to pick up new skills. The CLI
sends anonymous telemetry unless `DISABLE_TELEMETRY=1` is set.

## Contributing

Changes go through pull requests with Conventional Commit titles and
squash-only merges. See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow,
local development setup, and how to add a skill.
