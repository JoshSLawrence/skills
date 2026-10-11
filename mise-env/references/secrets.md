<!-- markdownlint-disable MD013 -->
<!-- Wide tables and code samples are unwrappable. -->

# Secrets

Read this whenever a value is a secret: tokens, passwords, API keys, private
keys, connection strings with credentials. Behavior verified against mise
2026.10.7 with sops 3.13.3 and age 1.3.2 unless marked "docs". Sources:
<https://mise.jdx.dev/environments/secrets/>,
<https://mise.jdx.dev/environments/secrets/sops.html>,
<https://mise.jdx.dev/environments/secrets/age.html>.

## Contents

- Choosing an approach
- Untracked local files
- sops-encrypted files (end to end)
- Keeping a missing key from breaking everything
- age-encrypted values (experimental)
- fnox (experimental)
- Redaction
- CI masking

## Choosing an approach

| Approach                        | You commit                           | Who gets plaintext           | Status       |
| ------------------------------- | ------------------------------------ | ---------------------------- | ------------ |
| `mise.local.toml` or `.env`     | Nothing (gitignored)                 | Everything loading `[env]`   | Stable       |
| sops file (`.env.json`/`.yaml`) | Ciphertext                           | Everything loading that file | Stable       |
| age values in `mise.toml`       | Ciphertext inline                    | Everything loading `[env]`   | Experimental |
| fnox                            | `fnox.toml` references or ciphertext | Only tasks that list the key | Experimental |

Default to an untracked local file for one developer's secrets and a sops
file for secrets the team shares. Offer age values or fnox only if the user
is fine with experimental features; both need `experimental = true` for
everyone who loads the config, CI included.

Whatever the approach, decrypted values are ordinary environment variables:
every child process can read them, and `mise env` prints them.

## Untracked local files

```toml
# mise.local.toml (gitignored)
[env]
STRIPE_KEY = "sk_test_..."
```

Put `redactions = ["*_KEY", "*_TOKEN"]` in the committed `mise.toml` so
personal values are masked too (verified).

Or keep `.env` untracked and load it from the committed config with
`_.file = ".env"`; a missing file is skipped (verified). Pair either with a
committed placeholder (`.env.example`, or a README line) and, for a task that
cannot work without it, task-level `required` (SKILL.md, `[env]` essentials).
Write values with `mise set --env local --stdin KEY` (agents) or
`--prompt` (users; typed input is visible and masked only with
`--age-encrypt`) so they stay out of shell history.

## sops-encrypted files (end to end)

Flow, with nothing installed globally:

```sh
mise --no-env x age@1.3.2 -- age-keygen -o ~/.config/mise/age.txt
tmp=$(mktemp -d)
# write $tmp/plain.json with the secrets, outside the repo
mise --no-env x sops@3.13.3 -- sops encrypt --age "age1..." --filename-override .env.production.json --output .env.production.json "$tmp/plain.json"
rm -rf "$tmp"
```

If `~/.config/mise/age.txt` already exists, reuse it (`age-keygen -y
~/.config/mise/age.txt` prints its public key); otherwise `mkdir -p
~/.config/mise` first. Verified: `-o` fails on an existing file and on a
missing directory.

Never write plaintext at the committed path and encrypt in place: if the
encrypt step fails, a plaintext secret file is left there to be committed.
Encrypting from a temp directory outside the repo into the final path leaves
nothing behind on failure (`--filename-override` and `--output` verified with
sops 3.13.3).

Load the encrypted file from a scoped place, never from `mise.toml` (see
"Keeping a missing key from breaking everything"):

```toml
# mise.production.toml (or a task's env); never mise.toml, see below
[env]
_.file = { path = ".env.production.json", redact = true }
```

Verified in a scratch directory with the key written to a scratch file and
passed as `MISE_SOPS_AGE_KEY_FILE`; that mise also finds
`~/.config/mise/age.txt` on its own is from the docs (it was not written
here, to leave the user's config alone). Writing that file is a change to the
user's home directory, so say so before doing it.

- mise decrypts age-encrypted sops files itself; **no `sops` binary is needed
  at runtime** (verified with neither sops nor a mise shim on `PATH`).
- Values came through (`{"API_TOKEN":"tok-plaintext-123", ...}`) and the
  `sops` metadata block did not become a variable.
- Only `.json`, `.yaml`, `.toml` are decrypted. **A sops-encrypted dotenv
  file is loaded as ciphertext**: verified, `DOT_SECRET` arrived as
  `ENC[AES256_GCM,...]` plus junk variables such as
  `sops_age__list_0__map_enc`. Use `.env.json` or `.env.yaml`.
- Before committing, confirm the file is encrypted:
  `mise --no-env x sops@3.13.3 -- sops filestatus .env.production.json`
  prints `{"encrypted":true}` (verified; it exits 0 either way, so read the
  output). Without `--no-env`, filestatus fails with "failed to decrypt sops
  file" when no key is present (verified).
- Edit later with
  `SOPS_AGE_KEY_FILE=<key> mise --no-env x sops@3.13.3 -- sops
  .env.production.json`
  (interactive: it opens `$EDITOR`, so agents cannot use it); decrypt to
  stdout with `sops decrypt` (verified). The `sops` CLI reads
  `SOPS_AGE_KEY_FILE`, not the `MISE_` variables (docs).
- To add a key non-interactively (verified):
  `printf '"%s"' "$v" | SOPS_AGE_KEY_FILE=<key> mise --no-env x sops@3.13.3 --
  sops set --value-stdin .env.production.json '["NEW_KEY"]'`.
  `sops set --help` says this avoids leaking secrets in process listings.
- **Run sops with `mise --no-env x ...` inside a project whose `[env]`
  already loads an encrypted file.** Verified trap: without a key, mise
  failed to decrypt the existing file before running sops, so
  `sops encrypt -i` never ran and the new file **stayed plaintext**.
  `mise --no-env x sops@3.13.3 -- sops encrypt -i ...` worked. `--no-env` is
  not a safety mode: in an untrusted directory it ran no project code but
  still recorded the directory as trusted (verified).
- Pin sops and age in `[tools]` if the team edits secrets often (the
  `mise-tools` skill covers exact pins); otherwise `mise x` one-offs are
  enough.
- Team access: encrypt to every member's public key
  (`--age "age1...,age1..."`) or commit a `.sops.yaml` with
  `creation_rules` (docs).
- KMS, Vault, or PGP keys need the `sops` CLI and `sops.rops = false`; the
  `sops` CLI cannot read TOML, so use JSON or YAML there (docs).

Where mise looks for the age key, first match wins (docs; items 2-4 and the
`[env]` form verified):

1. `MISE_SOPS_AGE_KEY` / setting `sops.age_key` (the key itself)
2. `MISE_SOPS_AGE_KEY_FILE` / setting `sops.age_key_file`
3. `SOPS_AGE_KEY_FILE`
4. `SOPS_AGE_KEY`
5. `~/.config/mise/age.txt`

`MISE_SOPS_AGE_KEY_FILE` may also be set in `[env]` above the `_.file` entry
(verified with `"{{ config_root }}/key.txt"`). Keep key files out of the repo.

## Keeping a missing key from breaking everything

Decryption is strict by default (`sops.strict = true`, verified default). With
an encrypted file in `mise.toml`'s `[env]` and no key, **every** command
failed: `mise ls --current`, `mise install`, and an unrelated `mise run lint`
all stopped with `failed to decrypt sops file` (verified). That hits new
contributors and any CI job without the key.

Scope the file to where it is needed. Both verified to keep `mise ls` and
`mise run lint` working without a key:

```toml
# Only the deploy task decrypts.
[tasks.deploy]
env = { _.file = { path = ".env.deploy.json", redact = true } }
run = "./scripts/deploy.sh"
```

```toml
# mise.production.toml: only `mise -E production ...` decrypts.
[env]
_.file = { path = ".env.production.json", redact = true }
```

`sops.strict = false` in `[settings]` instead skips files it cannot decrypt
(verified: `mise run lint` worked, the variables were simply absent). That
trades a loud failure for silently missing values, so combine it with
task-level `required` if you use it, and remember `[settings]` is ignored in
safe mode.

## age-encrypted values (experimental)

```sh
printf %s "$value" | MISE_EXPERIMENTAL=1 mise set --age-encrypt --age-recipient age1... --stdin DB_PASSWORD
```

writes `DB_PASSWORD = { age = "<base64>" }` to `mise.toml` (verified).

- Without experimental enabled, writing fails
  (`age encryption is experimental. Enable it with 'mise settings
  experimental=true'`), and so does **reading**: every command that loads the
  file failed with `Failed to decrypt DB_PASSWORD` (verified). Each developer
  and CI must enable experimental, so this is a team decision; do not run
  `mise settings experimental=true` for the user, since it edits global
  config.
- With no matching identity: `Failed to decrypt: No matching keys found`
  (verified). Decryption is strict by default (`age.strict = false` relaxes
  it; docs).
- Decryption identities, in order: `MISE_AGE_KEY` (verified), then
  `age.identity_files`, `age.key_file`, `~/.config/mise/age.txt`, and SSH keys
  `~/.ssh/id_ed25519`/`id_rsa` (docs).
- Without recipient flags, `mise set --age-encrypt` encrypts to those
  identities, including the user's SSH keys (docs). Pass `--age-recipient` /
  `--age-ssh-recipient` explicitly so the recipient list is deliberate.
- Values are redacted by default (verified: `[redacted]` in `mise set`).

## fnox (experimental)

fnox fetches secrets from providers (1Password, AWS Secrets Manager, KMS) and
gives them only to tasks that list them in `secrets = [...]`; shells, hooks,
and `mise env` never see them (docs). It needs `experimental = true`,
`min_version = "2026.10.4"`, fnox 1.39.0 or newer, and trust; safe mode
refuses it (docs). Not exercised here; read
<https://mise.jdx.dev/environments/secrets/fnox.html> before recommending it.

## Redaction

Mark values with `redact = true` on a variable or a directive, or list name
patterns in a top-level `redactions` array:

```toml
redactions = ["*_TOKEN", "*_SECRET", "PASSWORD"]

[env]
SECRET = { value = "...", redact = true }
TEST_TOKEN = { value = "not-sensitive", redact = false }  # opt out of a pattern
_.file = { path = ".env.json", redact = true }
```

Verified with all four forms:

| Where                    | Result                                                                    |
| ------------------------ | ------------------------------------------------------------------------- |
| `mise run` task output   | `secret=[redacted] token=[redacted] ...`; `redact = false` stayed visible |
| `mise set` (list)        | `[redacted]` in the value column                                          |
| `mise set KEY`           | Real value                                                                |
| `mise x -- <cmd>` output | Real value (mise hands the process over)                                  |
| `mise env`, `--json`     | Real values                                                               |
| `mise env --redacted`    | Only the sensitive variables, **with real values**                        |

Not redacted either (docs): tasks with `raw = true` or `interactive = true`,
and lines that the `replacing`/`timed` output modes drop. Redaction matches
values, so a marked value is masked wherever it appears in captured output.

## CI masking

`jdx/mise-action` registers GitHub Actions masks for values marked
`redact = true` or matching `redactions` (docs). Outside that action, mask
before anything can print them (docs):

```sh
set -o pipefail
mise env --redacted --json | jq -r '
  .[] | select(length > 0) |
  "::add-mask::" + (gsub("%"; "%25") | gsub("\r"; "%0D") | gsub("\n"; "%0A"))
'
```

`mise env --redacted --json` output shape verified
(`{"API_TOKEN": "...", ...}`); the masking step itself was not run here.
Give CI its decryption key through the CI secret store, scoped to the job or
step that needs it.
