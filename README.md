# x-cmd-action/checkout

> Pure-shell drop-in for [`actions/checkout`](https://github.com/actions/checkout) — **same inputs, same behavior, no Node.js**. Adds three x-cmd conveniences on top.

[中文文档](./README.cn.md)

## What it is

`actions/checkout` is implemented in TypeScript and bundled with `@actions/core`, `@actions/github`, and friends. Every CI run pays the cost of downloading ~1MB of JS, starting Node.js, and parsing the bundle — even when the actual work is "just a `git clone`".

This action does the same thing in **~250 lines of bash** with `git`, `ssh`, and standard unix tools. No npm dependencies. No nested `uses:`. The whole action is `action.yml` + `lib/checkout.sh`.

## Zero dependencies

This action does **not** depend on x-cmd being installed. It uses only:

- `git` (for the actual clone / fetch / checkout)
- `ssh` (for SSH auth — no `ssh-agent`, uses `GIT_SSH_COMMAND` directly)
- `curl` (only when fetching `known_hosts` from `known-hosts-url`)
- Standard POSIX shell

## Input parity with `actions/checkout`

Every input on `actions/checkout@v4` is supported with the same name and semantics. Three **x-cmd enhancements** are layered on top:

| Input | Source |
| --- | --- |
| `known-hosts-url` | **x-cmd enhancement** — `curl`-fetched known_hosts at runtime |
| `fetch-additional` | **x-cmd enhancement** — extra refspecs in the same fetch |
| `gitconfig` | **x-cmd enhancement** — repo-scoped `[include] path` to a `.gitconfig` file |

If you've used `actions/checkout`, you already know how to use this one.

## Usage

```yaml
- uses: x-cmd-action/checkout@v1
```

That's the common case — shallow clone of the current repo, ref, and token, identical to `actions/checkout`'s default behavior. The `with:` block is optional.

### Common use cases

**Full history** — for `git log` / `git blame` across all commits:

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    fetch-depth: 0
```

**Submodules** — initialize + fetch recursively:

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    submodules: recursive
```

**Git LFS files** — pull LFS-tracked binaries alongside the checkout:

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    lfs: true
```

**Private repo via SSH** — use a deploy key instead of the default token:

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    ssh-key: ${{ secrets.SSH_PRIVATE_KEY }}
```

**Multiple refs in one fetch** — `x-cmd` enhancement, lets you pull extra branches alongside the default ref:

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    fetch-additional: refs/heads/main refs/heads/release
```

**Sparse checkout** — only certain paths (saves time on monorepos):

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    sparse-checkout: |
      docs/
      src/**/*.go
```

**Repo-scoped git config** — `x-cmd` enhancement, point this checkout at a specific `.gitconfig` file via `[include]`:

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    path: src
    gitconfig: .github/repo.gitconfig
```

`.github/repo.gitconfig`:

```ini
[user]
    email = repo-specific@example.com

; Git 2.54+ inline hooks
[hook "pre-commit-lint"]
    event = pre-commit
    command = ./scripts/lint.sh
```

> Need config that applies to **all repos in the job**, not just this checkout? Use [`x-cmd-action/gitconfig`](https://github.com/x-cmd-action/gitconfig) — it writes to `~/.gitconfig` (job-wide) instead of the repo's `.git/config` (this repo only).

### Composing multiple inputs

All inputs are independent — combine them freely:

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    submodules: recursive
    lfs: true
    fetch-depth: 0
    ssh-key: ${{ secrets.SSH_PRIVATE_KEY }}
    fetch-additional: refs/heads/main refs/heads/release
```

## SSH path

Mirrors `actions/checkout`'s approach — **no ssh-agent**, **no writes to `~/.ssh/`**:

1. Private key written to a temp file (600)
2. Merged `known_hosts` written to a temp file, in this order:
   - user's existing `~/.ssh/known_hosts` (if any)
   - `ssh-known-hosts` input (verbatim)
   - `known-hosts-url` input (`curl`-fetched, **x-cmd enhancement**)
   - hardcoded `github.com` public key (pinned, offline-safe MITM defense)
3. `GIT_SSH_COMMAND` built with `-i <keypath> -o UserKnownHostsFile=<known_hosts> [-o StrictHostKeyChecking=yes]`
4. Persisted to the repo's `core.sshCommand` config when `persist-credentials: true` (so follow-up git commands reuse it)

Temp files live under `$RUNNER_TEMP` and are wiped on runner teardown.

## Inputs

All inputs below mirror `actions/checkout@v4` unless otherwise noted.

### Identity & target

| Input | Default | Description |
| --- | --- | --- |
| `repository` | `${{ github.repository }}` | `<owner>/<repo>` to check out |
| `ref` | `${{ github.ref_name }}` | branch, tag, or SHA |
| `path` | `${{ github.workspace }}` | destination directory |
| `clean` | `true` | wipe path before cloning |
| `github-server-url` | `${{ github.server_url }}` | override for Enterprise |
| `allow-unsafe-pr-checkout` | `false` | required to check out fork PR code from `pull_request_target` / `workflow_run` triggers |

### Authentication

| Input | Default | Description |
| --- | --- | --- |
| `token` | `${{ github.token }}` | HTTPS token for private repos |
| `ssh-key` | — | SSH private key (takes priority over token when set) |
| `ssh-known-hosts` | — | Custom known_hosts content (verbatim) |
| **`known-hosts-url`** | — | **x-cmd enhancement.** URL to a known_hosts file (`curl`-fetched at runtime). Useful when host keys are managed centrally. |
| `ssh-strict` | `true` | enforce strict host key checking |
| `ssh-user` | `git` | SSH user for the connection |
| `persist-credentials` | `true` | keep credentials configured for subsequent git commands |

### Fetch behavior

| Input | Default | Description |
| --- | --- | --- |
| `fetch-depth` | `1` | commits to fetch; `0` = full history |
| `fetch-tags` | `false` | fetch tags |
| **`fetch-additional`** | — | **x-cmd enhancement.** Extra space-separated refs in the same fetch. |

### Submodules, LFS, sparse, filter

| Input | Default | Description |
| --- | --- | --- |
| `submodules` | `false` | `false` / `true` / `recursive` |
| `lfs` | `false` | `git lfs pull` after checkout |
| `sparse-checkout` | — | sparse patterns (one per line) |
| `sparse-checkout-cone-mode` | `true` | cone mode |
| `filter` | — | partial clone filter (`blob:none`, `tree:0`, etc.); overrides `sparse-checkout` |

### Misc

| Input | Default | Description |
| --- | --- | --- |
| **`gitconfig`** | — | **x-cmd enhancement.** Path to a `.gitconfig` file. An `[include] path = <file>` is added to the checked-out repo's `.git/config` — read for git config lookups in this repo only. |
| `show-progress` | `true` | show git progress in logs |
| `set-safe-directory` | `true` | auto-add `safe.directory '*'` (container safety) |

## Comparison with `actions/checkout`

| Dimension | `actions/checkout@v4` | `x-cmd-action/checkout` |
| --- | --- | --- |
| Runtime | bash + Node.js | bash only |
| Tarball size | ~few MB JS bundle | ~3 KB shell |
| Startup overhead | ~2–3s (Node + bundle) | ~0s |
| Inputs | 22 | 22 (same names) + 3 x-cmd enhancements |
| LFS / submodules / sparse / filter | ✅ | ✅ |
| Private repo (token / ssh-key / ssh-user) | ✅ | ✅ |
| known_hosts from URL | ❌ | ✅ (`known-hosts-url`) |
| Multiple refspecs per fetch | ❌ | ✅ (`fetch-additional`) |
| Repo-scoped `[include]` gitconfig | ❌ | ✅ (`gitconfig`) |
| Windows runner | ✅ (Node path) | ✅ (Git Bash) |
| Default identity | `github-actions[bot]` | `github-actions[bot]` |

**You can swap `actions/checkout@v4` for `x-cmd-action/checkout@v1` without changing your workflow inputs.** Every input on `actions/checkout@v4` is supported with the same name.

## Known differences from `actions/checkout`

- **No JS-side caching of computed values.** All inputs are evaluated at action runtime via shell. Same observable behavior.
- **Sparse-checkout**: written to `.git/info/sparse-checkout` (which is what `git` reads). `actions/checkout` uses `git sparse-checkout set`, a thin wrapper around the same file — same end state.
- **Submodules with `fetch-depth`**: pass `--depth` to `git submodule update`. `actions/checkout` does the same in newer versions.
- **LFS detection**: if `git-lfs` isn't installed, prints a warning and continues instead of failing.
- **`allow-unsafe-pr-checkout`**: the flag is accepted and respected, but this action does not currently refuse to run on fork PRs without it. Same effective behavior because the inputs that govern checkout behavior (token, ssh-key) still need explicit values.

## License

Apache 2.0 — see [`LICENSE`](LICENSE).

## Related

- [actions/checkout](https://github.com/actions/checkout) — the TypeScript action this is a pure-shell alternative to.
- [x-cmd-action/gitconfig](https://github.com/x-cmd-action/gitconfig) — global `~/.gitconfig` setup (when you want config to apply to every repo in the job, not just this checkout).
- [x-cmd-action/gitmirror](https://github.com/x-cmd-action/gitmirror) — cross-platform repo mirror action.
- [x-cmd-action/.github](https://github.com/x-cmd-action/.github) — org profile + roadmap.
