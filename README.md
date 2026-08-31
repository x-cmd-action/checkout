# x-cmd-action/checkout

> Pure-shell alternative to [`actions/checkout`](https://github.com/actions/checkout) — **compatible** with it, **no Node.js**. Same input names; observable behavior matches in the common cases. Three x-cmd enhancements are layered on top.

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

## Compatibility with `actions/checkout`

**Same input names** as `actions/checkout@v4` — you can swap one for the other and your workflow inputs keep working. Three x-cmd enhancements sit on top:

| Input | Source |
| --- | --- |
| `known-hosts-url` | **x-cmd enhancement** — `curl`-fetched known_hosts at runtime (e.g., from a central repo of host keys) |
| `fetch-additional` | **x-cmd enhancement** — extra refspecs in the same fetch operation |
| `gitconfig` | **x-cmd enhancement** — repo-scoped `[include] path` to a `.gitconfig` file (signing keys, custom identity, hooks) |

If you've used `actions/checkout`, you already know how to use this one — the three enhancements are opt-in.

### Where the implementations differ

`actions/checkout` is a single TypeScript module with carefully tuned git plumbing (extraheader credentials, `includeIf` scoping, `core.quotepath`, `gc.auto=0`, `url.<origin>/.insteadOf`, isolated `HOME` under `RUNNER_TEMP`, post-step cleanup of temp files). This action is a single bash script that covers the **observable surface** — the same inputs, the same end state on disk.

If you depend on subtle internal behaviors of `actions/checkout` (for example, running git commands inside a Docker container action that reuses the action's credentials), the two may differ. For typical CI workflows — clone, set identity, run tests, push back via persisted credentials — this action is a drop-in. For exotic setups, `actions/checkout` may behave differently in edge cases.

The intentional differences:

| Behavior | `actions/checkout` | This action |
| --- | --- | --- |
| Runtime | bash + Node.js bundle | bash only |
| `actions/checkout` quirks (extraheader + `includeIf`, `gc.auto=0`, `core.quotepath`, isolated `HOME`, `url.<origin>/.insteadOf`, post-step temp cleanup) | yes | **no** — observable end state matches but the internal plumbing is simpler |
| Hardcoded `github.com` public key in known_hosts | yes (offline-safe MITM defense) | yes |
| `persist-credentials: true` keeps token reusable for follow-up git commands | yes (via `core.sshCommand` for SSH, `extraheader` + `includeIf` for HTTPS) | yes (via `core.sshCommand` for SSH, URL-embedded token for HTTPS) |
| `set-safe-directory` input | adds `<repo>` path | adds `'*'` (broader) |

If any of the "no" rows above matters for your workflow, prefer `actions/checkout` for that step.

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
| Tarball size (unpacked) | ~1.85 MB JS bundle | **~16 KB** shell (**~114x smaller**) — only `action.yml` + `lib/checkout.sh` ship in the tarball (CI workflows / READMEs / LICENSE excluded via `.gitattributes` `export-ignore`) |
| Wall-clock step duration (warm, depth: 1) | ~565–714 ms | ~326–546 ms (~1.7x faster; measured by [`benchmark-vs-actions-checkout`](.github/workflows/benchmark.yml)) |
| Cold-start (job init + tarball download + 1st step) | see [`benchmark-vs-actions-checkout`](.github/workflows/benchmark.yml) | see benchmark |
| Inputs | 22 | 22 (same names) + 3 x-cmd enhancements |
| LFS / submodules / sparse / filter | ✅ | ✅ |
| Private repo (token / ssh-key / ssh-user) | ✅ | ✅ |
| known_hosts from URL | ❌ | ✅ (`known-hosts-url`) |
| Multiple refspecs per fetch | ❌ | ✅ (`fetch-additional`) |
| Repo-scoped `[include]` gitconfig | ❌ | ✅ (`gitconfig`) |
| Windows runner | ✅ (Node path) | ✅ (Git Bash) |
| Default identity | `github-actions[bot]` | `github-actions[bot]` |

You can swap `actions/checkout@v4` for `x-cmd-action/checkout@v1` and your **inputs** keep working. Whether the **observable end state** matches in your specific workflow depends on the implementation differences below — most jobs work, but some don't.

## Known implementation differences from `actions/checkout`

`actions/checkout` is a single TypeScript module with carefully tuned git plumbing. This action is a single bash script that hits the same observable end state via simpler plumbing. The differences, in order of how often they matter:

### Likely to matter

- **HTTPS credential plumbing.** `actions/checkout` writes the token to a separate credentials file and uses `http.<origin>/.extraheader` + `includeIf.gitdir:` so that credentials are scoped to the cloned repo and not exposed via the remote URL. This action embeds the token directly into the HTTPS URL (`https://x-access-token:***@host/repo.git`) and strips it back out via `git remote set-url` after fetch. For follow-up git commands in the same repo, both approaches work — but tools that introspect the remote URL (some credential helpers, some IDE integrations) may see different things.
- **`url.<origin>/.insteadOf`.** `actions/checkout` sets this so that an SSH-style URL like `git@github.com:foo/bar` in subsequent commands is automatically rewritten to HTTPS using the action's stored credentials. This action does not. If your workflow uses SSH-style URLs in downstream `git` commands, `actions/checkout` is more forgiving.
- **HOME isolation.** `actions/checkout` writes its `core.sshCommand` and other global config to a **temporary HOME under `RUNNER_TEMP`** so the user's real `~/.gitconfig` is untouched. This action writes to the real `~/.gitconfig`. If your runner has important state in `~/.gitconfig`, prefer `actions/checkout` for that step.

### Unlikely to matter

- **`set-safe-directory` defaults to `*`.** `actions/checkout` adds the specific repo path; this action adds `*`. `*` is broader but covers the same use cases.
- **No `core.quotepath = false` / `gc.auto = 0` / `protocol.version = 2` tweaks.** `actions/checkout` sets these for performance and clean output on big repos. This action relies on git defaults.
- **Sparse-checkout is written directly to `.git/info/sparse-checkout`.** `actions/checkout` uses `git sparse-checkout set`, which writes the same file. End state is identical.
- **Submodule update with `--depth`.** This action passes `--depth` to `git submodule update`; `actions/checkout` does the same.
- **LFS detection.** This action prints a warning and continues if `git-lfs` is missing; `actions/checkout` fails.
- **`allow-unsafe-pr-checkout`.** This action accepts the input and respects it but does not actively refuse to run on fork PRs without it. Same observable effect because the inputs that drive checkout (token, ssh-key) still need to be set explicitly.
- **No `post:` step.** `actions/checkout` runs a `post:` step to clean up temp files and unset state. This action relies on `RUNNER_TEMP` being wiped on runner teardown. Observable behavior on the runner matches; only matters if you `source` the action's env into your own state.

### Bottom line

For the common case — clone, set identity, run tests, push back via persisted credentials — this action is a drop-in. For Docker-container actions that reuse the checkout's credentials, or workflows that rely on the action's `includeIf.gitdir:` scoping, `actions/checkout` is the safer pick.

## License

Apache 2.0 — see [`LICENSE`](LICENSE).

## Related

- [actions/checkout](https://github.com/actions/checkout) — the TypeScript action this is a pure-shell alternative to.
- [x-cmd-action/gitconfig](https://github.com/x-cmd-action/gitconfig) — global `~/.gitconfig` setup (when you want config to apply to every repo in the job, not just this checkout).
- [x-cmd-action/gitmirror](https://github.com/x-cmd-action/gitmirror) — cross-platform repo mirror action.
- [x-cmd-action/.github](https://github.com/x-cmd-action/.github) — org profile + roadmap.
