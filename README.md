# x-cmd-action/checkout

> Pure-shell git checkout for GitHub Actions. Drop-in alternative to `actions/checkout` — same input names where possible, same features, but **no Node.js runtime** and **no nested action dependencies**.

[中文文档](./README.cn.md)

## Why

`actions/checkout` is implemented in TypeScript and bundled with `@actions/core`,`, `@actions/github`, and friends. Every CI run pays the cost of downloading ~1MB of JS, starting Node.js, and parsing the bundle — even when the actual work is "just a `git clone`".

This action does the same thing in **~200 lines of bash** with `git`, `ssh`, and standard unix tools. No npm dependencies. No nested `uses:`. The whole action is `action.yml` + `lib/checkout.sh`.

## Zero dependencies

This action does **not** depend on x-cmd being installed. It uses only:

- `git` (for the actual clone / fetch / checkout)
- `ssh-agent`, `ssh-keyscan` (for SSH auth)
- `curl` (only when fetching `known_hosts`)
- Standard POSIX shell

If you don't want x-cmd in your CI at all, this action works fine standalone. It is the only action in the `x-cmd-action` org with **no x-cmd requirement**.

## Usage

```yaml
- uses: x-cmd-action/checkout@v1
```

That's it for the common case — shallow clone of the current repo, ref, and token, defaulting to `actions/checkout`'s behavior. The `with:` block is optional.

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

**Custom path** — clone into a subdirectory instead of overwriting workspace root:

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    path: src
```

**Specific ref / tag / SHA**:

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    ref: v1.2.3
```

**Sparse checkout** — only certain paths (saves time on monorepos):

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    sparse-checkout: |
      docs/
      src/**/*.go
```

### Composing multiple

All inputs are independent — combine them freely:

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    submodules: recursive
    lfs: true
    fetch-depth: 0
    ssh-key: ${{ secrets.SSH_PRIVATE_KEY }}
```

## Inputs

20 inputs, mirroring `actions/checkout@v4`:

### Identity & target

| Input | Default | Description |
| --- | --- | --- |
| `repository` | `${{ github.repository }}` | `<owner>/<repo>` to check out |
| `ref` | `${{ github.ref_name }}` | branch, tag, or SHA |
| `path` | `${{ github.workspace }}` | destination directory |
| `clean` | `true` | wipe path before cloning |

### Authentication

| Input | Default | Description |
| --- | --- | --- |
| `token` | `${{ github.token }}` | HTTPS token for private repos |
| `ssh-key` | — | SSH private key (takes priority over token) |
| `ssh-known-hosts` | — | Custom known_hosts content (verbatim) |
| `ssh-strict` | `true` | strict host key checking |
| `require-ssh-key` | `false` | fail if ssh-key is empty (no token fallback) |
| `github-server-url` | `${{ github.server_url }}` | override for Enterprise |

### Fetch behavior

| Input | Default | Description |
| --- | --- | --- |
| `fetch-depth` | `1` | commits to fetch; `0` = full history |
| `fetch-tags` | `false` | fetch tags |
| `fetch-additional` | — | extra space-separated refs |

### Submodules, LFS, sparse

| Input | Default | Description |
| --- | --- | --- |
| `submodules` | `false` | `false` / `true` / `recursive` |
| `lfs` | `false` | `git lfs pull` after checkout |
| `sparse-checkout` | — | sparse patterns (one per line) |
| `sparse-checkout-cone-mode` | `true` | cone mode |

### Misc

| Input | Default | Description |
| --- | --- | --- |
| `persist-credentials` | `true` | keep token in `.git/config` after clone |
| `gitconfig` | — | Path to a `.gitconfig` file. An `[include] path = <file>` is added to the checked-out repo's `.git/config` — the file is read for git config lookups in this repo only, never globally. |
| `show-progress` | `true` | show git progress in logs |
| `set-safe-directory` | `true` | auto-add `safe.directory '*'` (container safety) |

## How it works

```
┌────────────────────────────────────────┐
│  x-cmd-action/checkout                 │
│  ─ reads inputs                         │
│  ─ safe.directory (if requested)       │
│  ─ auth: SSH | token | public          │
│  ─ git init / fetch / checkout         │
│  ─ sparse, submodules, LFS             │
│  ─ strip token (if !persist)           │
│  ─ set github-actions bot identity     │
└────────────────────────────────────────┘
         │
         └─ uses only: git, ssh-keyscan, ssh-agent, standard POSIX
```

No Node.js. No nested `uses:`. No npm packages. The action tarball itself is just `action.yml` + `lib/checkout.sh`.

## Comparison with `actions/checkout`

| Dimension | `actions/checkout@v4` | `x-cmd-action/checkout` |
| --- | --- | --- |
| Runtime | bash + Node.js | bash only |
| Tarball size | ~few MB JS bundle | ~3 KB shell |
| Startup overhead | ~2–3s (Node + bundle) | ~0s |
| Inputs | 20 | 20 (same names) |
| LFS / submodules / sparse | ✅ | ✅ |
| Private repo (token / ssh-key) | ✅ | ✅ |
| Windows runner | ✅ (Node path) | ✅ (Git Bash) |
| Default identity | `github-actions[bot]` | `github-actions[bot]` |

You can swap one for the other without changing your workflow inputs.

## Known differences from `actions/checkout`

- **No JS-side caching of computed values.** All inputs are evaluated at action runtime via shell. Same observable behavior.
- **Sparse-checkout**: written to `.git/info/sparse-checkout` (which is what `git` reads). `actions/checkout` uses `git sparse-checkout set` which is a thin wrapper around the same file — same end state.
- **Submodules with `fetch-depth`**: pass `--depth` to `git submodule update`. `actions/checkout` does the same in newer versions.
- **LFS detection**: if `git-lfs` isn't installed, prints a warning and continues instead of failing.

## License

Apache 2.0 — see [`LICENSE`](LICENSE).

## Related

- [x-cmd-action/gitmirror](https://github.com/x-cmd-action/gitmirror) — cross-platform repo mirror action.
- [actions/checkout](https://github.com/actions/checkout) — the TypeScript action this one replaces.