# Contributing

Changes land through pull requests only. `main` is protected: no direct
pushes, no force pushes, no deletions.

## Workflow

1. Branch from an up-to-date `main`. Name it `<type>/<short-description>`,
   for example `feat/mise-tasks-retry-helper`.
2. Commit using [Conventional Commits](https://www.conventionalcommits.org/)
   (see below).
3. Open a pull request. Its **title** must itself be a Conventional Commit.
4. Wait for the `pr-title` and `shellcheck` checks to pass.
5. **Squash and merge** - it is the only merge method enabled. The PR title
   becomes the single commit on `main`, and the branch is deleted
   automatically.

## Commit and PR title format

```text
<type>(<scope>)!: <subject>
```

- **type** - one of `feat`, `fix`, `docs`, `refactor`, `perf`, `test`,
  `build`, `ci`, `chore`, `style`, `revert`.
- **scope** - optional; use the skill's directory name (`mise-tasks`) for
  changes inside one skill. Omit it for repo-wide changes.
- **`!`** - marks a breaking change (for example renaming a skill or
  changing an asset's interface).
- **subject** - imperative, lowercase start, no trailing period, at most 72
  characters.

Examples:

```text
feat(mise-tasks): add retry helper to common.sh
fix(mise-tasks): quote variadic usage args in example-task
docs: document skills CLI install options
ci: pin actions/checkout to a commit SHA
feat!: rename mise-tasks skill to mise
```

Use `feat` for new or expanded skill capability, `fix` for incorrect guidance
or broken assets, and `docs`/`chore` for repo upkeep.

## Developing locally

Link a working copy so edits apply immediately, without reinstalling:

```sh
git clone git@github.com:JoshSLawrence/skills.git ~/source/github/skills
cd ~/source/github/skills
npx skills add . --skill mise-tasks -g -a claude-code
```

Or link by hand:

```sh
ln -sfn ~/source/github/skills/mise-tasks ~/.claude/skills/mise-tasks
```

Restart Claude Code (or start a new session) to pick up changes.

## Adding or changing a skill

1. Create `<skill-name>/SKILL.md` with `name` and `description` frontmatter.
   The directory name must match `name`.
2. Add the skill to the inventory in [README.md](README.md) in the same PR.
3. Follow the skill-authoring conventions in [CLAUDE.md](CLAUDE.md).
4. Run any shipped scripts for real in a scratch copy and lint them. CI runs
   `shellcheck` on everything under `assets/`. Do not add lint suppressions
   without maintainer approval; fix the underlying issue.

## Repository settings (for maintainers)

These are enforced in GitHub, not just by convention:

- Ruleset on the default branch: pull request required, squash-only merge,
  required checks `pr-title` and `shellcheck`, linear history, no force
  pushes or deletions. No bypass actors.
- Squash commit title is the PR title; merged branches are deleted.
