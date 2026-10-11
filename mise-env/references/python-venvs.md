<!-- markdownlint-disable MD013 -->
<!-- Wide tables and code samples are unwrappable. -->

# Python virtualenvs

Read this for any Python project that should have its virtualenv active
without `source .venv/bin/activate`. Behavior verified against mise 2026.10.7
with Python 3.14.7 and uv 0.12.19 unless marked "docs". Source:
<https://mise.jdx.dev/lang/python.html#automatic-virtualenv-activation>.

## Contents

- Which mechanism
- `_.python.venv`
- uv projects (`python.uv_venv_auto`)
- Making uv use mise's Python
- Checks and pitfalls
- Deprecated forms

## Which mechanism

| Project                                 | Use                                                       |
| --------------------------------------- | --------------------------------------------------------- |
| Managed by uv (has `uv.lock`)           | `[settings] python.uv_venv_auto = "source"`               |
| pip/requirements, or no project manager | `[env] _.python.venv = { path = ".venv", create = true }` |

Both set `VIRTUAL_ENV` and put the venv's `bin` first on `PATH` for `mise x`,
tasks, and activated shells. With shims alone the venv is not on `PATH`
(docs). Add `.venv/` to `.gitignore`.

Python itself is pinned in `[tools]` (the `mise-tools` skill).

## `_.python.venv`

```toml
[tools]
python = "3.14.7"

[env]
_.python.venv = { path = ".venv", create = true }
```

Verified:

- The first `mise x -- python ...` created `.venv` and ran inside it:
  `sys.prefix` was `<project>/.venv`.
- `PATH` order: `<project>/.venv/bin`, then the mise Python, then the rest.
- **How it is created** depends on whether uv is available:
  - uv on `PATH` or in the project's `[tools]` -> `mise creating venv with uv`,
    `pyvenv.cfg` has `uv = 0.12.19`, and there is **no pip** in the venv.
  - No uv anywhere -> `mise creating venv with stdlib`, pip included.
  mise does not fetch uv for this; it uses one that is already there.
  Seed pip into a uv venv with `uv_create_args = ["--seed"]`, or force the
  stdlib with the `python.venv_stdlib` setting (docs).
- The string form `_.python.venv = ".venv"` only activates; with no venv it
  warns on every command:
  `no venv found at: <project>/.venv ... python -m venv <project>/.venv`.
- Other options (docs): `python` (which version to create with),
  `python_create_args`, `uv_create_args`.
- `_.python.venv` always runs after tools and other directives, and does not
  take `tools = true` (docs).

## uv projects (`python.uv_venv_auto`)

```toml
[tools]
python = "3.14.7"
uv = "0.12.19"

[settings]
python.uv_venv_auto = "source"   # or "create|source"
```

Verified with a minimal `uv init --bare` project:

- Before `uv.lock` existed the setting did nothing (`VIRTUAL_ENV` unset).
- After `uv lock`, `"create|source"` created `.venv` with uv and activated it.
- `"source"` only activates what `uv sync` made; it warns when the venv is
  missing (docs). Prefer it when uv owns the environment, so mise never
  creates a venv uv did not expect.
- The venv is `.venv` next to `uv.lock`, or `UV_PROJECT_ENVIRONMENT` (docs).

This puts a `[settings]` table in `mise.toml`. Like `[env]`, that needs trust,
and safe mode ignores project settings (mise-tools).

## Making uv use mise's Python

uv may prefer a Python it downloaded. Point it at mise's:

```toml
[env]
UV_PYTHON = { value = "{{ tools.python.path }}", tools = true }
```

Verified: `UV_PYTHON` became the mise install dir
(`.../installs/python/3.14.7`), uv 0.12.19 accepted it, and `uv run python`
ran the project venv's interpreter. `tools = true` is required; without it
`tools` is undefined (`templates.md`).

## Checks and pitfalls

- Verify with
  `mise x -- python -c 'import sys; print(sys.prefix)'`; it should print the
  project's `.venv`.
- **Read-only commands create venvs too.** `mise env` printed uv's
  "Creating virtual environment" output and created `.venv` with
  `create|source` (verified). Expect that on the first command in a fresh
  clone, and keep the `.venv` path gitignored.
- `MISE_SAFE=1` ignores the venv (verified: `VIRTUAL_ENV` unset), like the
  rest of project `[env]`.
- Do not let direnv's `layout python` or pyenv-virtualenv manage the same
  venv; pick one (docs).
- In an agent shell, a bare `python` is not the venv's (the shell is not
  activated); use `mise x -- python` or `mise run`.

## Deprecated forms

From the docs:

- `python = { version = "3.14", virtualenv = ".venv" }` in `[tools]` warns
  since 2026.7.0 and is removed in 2027.7.0. Convert to `_.python.venv`.
- `python.uv_venv_auto = true` warns since 2026.7.0 and is removed in
  2027.7.0. Use `"source"` or `"create|source"`, plus the `UV_PYTHON` recipe
  if uv must use mise's Python.
