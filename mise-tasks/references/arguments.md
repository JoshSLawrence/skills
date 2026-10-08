<!-- markdownlint-disable MD013 -->

# Task arguments (`usage` spec)

Source: <https://mise.jdx.dev/tasks/task-arguments.html>. Behavior notes
marked "verified" were tested against mise 2026.10.3.

The `usage` spec gives validation, `--help` (`mise run <task> --help`),
completion, and docs (`mise generate task-docs`). Without a spec, extra CLI
args are simply forwarded to the command.

## Where it goes

File task:

```bash
#!/usr/bin/env bash
#USAGE arg "<environment>" help="Target environment" {
#USAGE   choices "dev" "staging" "prod"
#USAGE }
#USAGE flag "--region <region>" help="AWS region" default="us-east-1" env="AWS_REGION"
```

TOML task:

```toml
[tasks.deploy]
usage = '''
arg "<environment>" help="Target environment" {
  choices "dev" "staging" "prod"
}
flag "-v --verbose" help="Enable verbose output"
flag "--region <region>" help="AWS region" default="us-east-1" env="AWS_REGION"
'''
run = 'echo "deploy ${usage_environment?} to ${usage_region?}"'
```

File-task `#USAGE` lines are not Tera-rendered, so use `$MISE_CONFIG_ROOT`,
not `{{ config_root }}`, inside them.

## Positional args

```kdl
arg "<name>"                          // required
arg "[name]"                          // optional
arg "<file>" default="config.toml"
arg "[files]" var=#true               // variadic, 0+
arg "<files>" var=#true var_min=2 var_max=5
arg "<token>" env="API_TOKEN"
arg "<level>" { choices "debug" "info" "warn" "error" }
arg "<x>" long_help="Extended help" hide=#true
```

Precedence: CLI value, then `env`, then `default`.

## Flags

```kdl
flag "-f --force"
flag "-o --output <file>" help="Output file"
flag "--color <when>" { choices "auto" "always" "never" }
flag "--force" default=#true
flag "-v --verbose" count=#true            // -vvv
flag "--color" negate="--no-color" default=#true
flag "--debug" hide=#true
```

## Completion

```kdl
arg "<plugin>"
complete "plugin" run="mise plugins ls"
```

## Reading values in the script

Each arg/flag becomes `usage_<name>` (dashes to underscores:
`--dry-run` -> `usage_dry_run`). Inherited `usage_*` from a parent
invocation are cleared, so pass values deliberately via `env=`.

| Case                       | Pattern                                    |
| -------------------------- | ------------------------------------------ |
| Has a `default`            | `"${usage_name?}"` (always set; verified)  |
| Required, must be non-empty| `"${usage_name:?}"`                        |
| Boolean flag, no default   | `[ "${usage_x:-false}" = "true" ]` (unset unless passed; verified) |
| Optional string            | `"${usage_x:-}"`                           |
| Variadic                   | `eval "items=(${usage_items-})"` (value is a shell-quoted string, e.g. `a 'b c'`; verified) |

## Shared flag sets

Put reusable flags in a `.usage.kdl`:

```kdl
flagset "common" {
  flag "--env <env>" help="Target environment"
  flag "--dry-run" help="Print what would happen"
}
```

```bash
#USAGE include file="$MISE_CONFIG_ROOT/shared.usage.kdl"
#USAGE use "common"
```

TOML equivalent: `include file="{{ config_root }}/shared.usage.kdl"`.

## Templating alternative (TOML tasks)

`usage` values are also available to Tera as a map:
`{{ usage.environment }}`, `{% if usage.verbose %}...{% endif %}`. This also
works inside `depends` to forward args to dependencies. Do not mix with the
deprecated functions below.

## Deprecated: `arg()` / `option()` / `flag()` template functions

`run = 'cargo test {{arg(name="file")}}'` is deprecated (removal planned for
mise 2027.5.0). Migrate to `usage` + `${usage_file?}`. To opt out now:
`task.disable_spec_from_run_scripts = true`.
