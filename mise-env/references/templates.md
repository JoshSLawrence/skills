<!-- markdownlint-disable MD013 -->
<!-- Wide tables and code samples are unwrappable. -->

# Templates and derived values

Read this when a value comes from another value, a path, a command's output,
or a tool. Behavior verified against mise 2026.10.7 unless marked "docs".
Sources: <https://mise.jdx.dev/templates.html>,
<https://mise.jdx.dev/environments/#reference-other-values>.

## Contents

- Template context
- Ordering
- Shell-style expansion
- `exec()` and `read_file()`
- Values from tools (`tools = true`)
- `[vars]`
- Any template means trust

## Template context

| Variable                                  | Value                                                                   |
| ----------------------------------------- | ----------------------------------------------------------------------- |
| `config_root`                             | Project root, also for `.config/mise.toml` (verified)                   |
| `cwd`                                     | Where mise was run; from `sub/deep` it was `sub/deep` (verified)        |
| `env.NAME`                                | The starting environment plus `[env]` values resolved so far (verified) |
| `vars.NAME`                               | `[vars]` values (verified)                                              |
| `mise_env`                                | Selected config environments as a list; undefined when none (verified)  |
| `tools.<t>.version`, `tools.<t>.path`     | Only with `tools = true` (verified)                                     |
| `config_source`, `xdg_*_home`, `mise_bin` | See the docs page (docs)                                                |

Use `config_root` for paths. `cwd` changes with the caller's directory, so a
path built from it differs between `mise x` in the root and in a
subdirectory.

Tera functions and filters (`default`, `trim`, `basename`, `os()`, `arch()`,
`is dir`, ...) are listed in the docs. Two worth knowing:

```toml
[env]
PROJECT_NAME = "{{ config_root | basename }}"
REGION = "{{ env.AWS_REGION | default(value='eu-west-1') }}"
```

## Ordering

mise evaluates config files from lowest to highest precedence, and entries in
each file top to bottom (docs). A value can use only what is already set.

Verified: `FWD = "{{ env.LATER }}"` above `LATER = "later"` failed every
command with

```text
mise ERROR failed to parse template: '{{ env.LATER }}'
mise ERROR error: Field `LATER` is not defined. Available fields: ...
```

(The message lists the names, not values, of every variable in the
environment.) It is a hard error, not an empty string. Reorder the entries,
or make the reference optional with
`{{ env.LATER | default(value='') }}` (verified: rendered the default).

## Shell-style expansion

After template rendering, `$VAR`, `${VAR}`, `${VAR:-default}`, and
`${VAR:-}` expand (setting `env_shell_expand`, default `true`; verified).

- `SHELLX = "$LIB/three"` used the earlier `LIB` entry (verified).
- `${UNSET_THING:-fallback}` gave `fallback` (verified).
- An undefined `$UNSET_THING` is left as written and warns on every command:
  `env var 'UNSET_THING' is not defined and will be left unexpanded ... Use
  ${UNSET_THING:-} to default to an empty string` (verified). Use `${X:-}`
  for optional values, such as appending to `LD_LIBRARY_PATH`.

## `exec()` and `read_file()`

```toml
[env]
GIT_SHA = "{{ exec(command='git rev-parse --short HEAD') }}"
VERSION = "{{ read_file(path='VERSION') | trim }}"
AWS_ACCOUNT_ID = "{{ exec(command='aws sts get-caller-identity --query Account --output text', cache_key='aws-account', cache_duration='1d') }}"
```

- `exec()` runs in the directory of the config file, so in
  `.config/mise.toml` it ran in `.config/`, not the project root (verified);
  relative `read_file()` paths follow the same rule (docs).
- **It runs on every mise invocation** (verified: three `mise x` calls, three
  executions), and in an activated shell whenever the environment is
  recomputed (docs). It also runs under `--dry-run` (docs). Only use
  side-effect-free, fast commands.
- `cache_key` and/or `cache_duration` cache the output under the cache dir
  (verified: one execution across three calls). Change `cache_key` to force a
  rerun.
- In `[env]`, `exec()` sees earlier `[env]` values (docs).
- It needs trust. Under `MISE_SAFE=1` project `[env]` is ignored altogether
  (verified: no execution, no error); `exec()` in config that safe mode still
  reads fails with `... is disabled in safe mode` (docs).

## Values from tools (`tools = true`)

`[env]` resolves **before** tools load, so it can configure tool installs
(`CFLAGS` for a source build). To use what a tool provides, mark the entry:

```toml
[tools]
python = "3.14.7"

[env]
NODE_VERSION = { value = "{{ tools.node.version }}", tools = true }
UV_PYTHON = { value = "{{ tools.python.path }}", tools = true }
_.path = { path = "{{ env.GEM_HOME }}/bin", tools = true }
```

Verified with `jq = "1.8.2"`:

- Without `tools = true`: `Variable 'tools' is not defined. Available
  variables: config_root, config_source, cwd, env, ...`.
- With it: `tools.jq.version` gave `1.8.2` and `tools.jq.path` the install
  dir.
- `exec(command='command -v jq')` gave `/usr/bin/jq` without `tools = true`
  and the mise-installed jq with it. Any `exec()` that calls a project tool
  needs the flag.

`tools = true` works on variables and on `_.file`, `_.path`, `_.source`
(docs). `preinstall` hooks do not see these entries (docs).

## `[vars]`

`[vars]` holds values for templates that should not be exported:

```toml
[vars]
region = "eu-west-1"

[env]
AWS_REGION = "{{ vars.region }}"
```

Verified: `AWS_REGION` was exported and `region` was not.

## Any template means trust

Any `{{`, `{%`, or `{#` in a config file makes it need trust (docs), and
`[env]` already does. `exec()` and `read_file()` are code execution and file
reads on whoever loads the config, which is why a repo you did not write
deserves a read before its first `mise x` or `mise run` (see SKILL.md, Trust
and safety).
