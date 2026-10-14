---
name: markdown-style
description: Write markdown that reads well raw and renders correctly where it is published - alerts by default (plain bold notes for Azure DevOps), 80-column wrapping with scoped markdownlint exceptions, aligned tables, sorted directory trees, and copy-paste-friendly code blocks. Use this skill whenever you write or edit any markdown file (README, docs, CHANGELOG, CONTRIBUTING, ADRs, SKILL.md, CLAUDE.md or AGENTS.md), realign a markdown table, or fix markdownlint findings, even for a small doc change.
---

# Markdown style

Markdown gets read in two places: rendered on a forge or in an editor, and
raw in diffs and terminals. Write it so both are pleasant, and so it renders
correctly on the platform the repo is actually published to.

## Workflow

1. **Look first.** Check for a markdownlint config
   (`.markdownlint-cli2.jsonc`, `.markdownlint.json`, `.markdownlint.yaml`)
   and the repo's remote (`git remote -v`). The config wins over the
   defaults below; the remote decides which syntax renders.
2. **Write**, following the rules below.
3. **Lint** with the repo's task or `markdownlint-cli2 <files>`. Fix the
   finding; add a disable comment only for content that genuinely can't
   comply (see line length).

## Platform features

- **Use alerts by default**: `> [!NOTE]`, `> [!TIP]`, `> [!IMPORTANT]`,
  `> [!WARNING]`, `> [!CAUTION]`. GitHub, GitLab and Obsidian render them
  as callouts. Azure DevOps doesn't, so when the remote is Azure DevOps
  (`dev.azure.com`, `*.visualstudio.com`) write `> **Note:** ...` instead.
- **Avoid `<details>`/`<summary>`** unless you know every place the file is
  read renders it; elsewhere the content shows up as raw HTML.
- **Separate paragraphs with blank lines**, never trailing whitespace or
  backslashes for line breaks. Trailing spaces are invisible and editors
  strip them.

## Line length

Wrap prose at 80 columns, so raw files read well in terminals, side-by-side
diffs and review tools. Break at clause or sentence boundaries where you can,
so later edits produce small diffs.

For content that can't wrap (tables, long URLs, frontmatter), disable the
rule only around it, and re-enable it after:

```markdown
<!-- markdownlint-disable MD013 -->
| Wide | table |
| ---- | ----- |
<!-- markdownlint-enable MD013 -->
```

Agent instruction files (`CLAUDE.md`, `AGENTS.md`) never get disable
comments: many agents read the raw file, so the comments are noise in
every session. Exclude those files in the linter config instead.

## Tables

- **Readable raw**: pad cells with spaces so the pipes line up, and never
  wrap a row across lines. Align with spaces, not tabs.
- **Keep them narrow.** If a table gets too wide to read raw, a list of
  `**term** - description` items usually reads better.
- **Realigning with a script? Skip fenced code blocks.** A line starting
  with `|` inside a fence (KQL, shell pipes) is not a table row. Diff the
  code blocks before and after realigning: markdownlint won't notice a query
  mangled into a table.

## Code blocks

- **Always tag the language** (`bash`, `yaml`, `text`), which gives syntax
  highlighting and satisfies MD040.
- **Keep them copy-paste friendly.** Put explanations in the prose around
  the block, not as inline comments that end up in someone's terminal. Leave
  out prompts (`$`) and output unless the block is explicitly a transcript.

## Directory trees

Use a `text` code block. Sort entries **lexically**: dotfiles first (sorted
among themselves, ignoring the dot), then everything else alphabetically,
case-insensitive.

```text
.github/
.gitignore
docs/
README.md
src/
```

## Checklist before you finish

- [ ] Alerts used, unless the remote is Azure DevOps
- [ ] Prose wrapped at 80 columns; disable comments only around
      unwrappable content, and none in `CLAUDE.md`/`AGENTS.md`
- [ ] Tables aligned with spaces, one line per row; code blocks unchanged
      by any realignment
- [ ] Every code block has a language and no inline explanations
- [ ] markdownlint passes
