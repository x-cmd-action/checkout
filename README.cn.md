# x-cmd-action/checkout

> 纯 shell 实现的 GitHub Actions checkout action。`actions/checkout` 的直接替代 —— **input 名称尽量保持一致**、**功能完整覆盖**，但 **不依赖 Node.js runtime**，**不嵌套任何 action**。

[English](./README.md)

## 为什么需要这个

`actions/checkout` 是用 TypeScript 写的，依赖 `@actions/core`、`@actions/github` 等一票 npm 包。每次 CI 跑都要：

- 下载 ~1MB 的 JS bundle
- 启动 Node.js
- 解析并执行 bundle

—— 而真正做的事只是 `git clone`。完全是大炮打蚊子。

这个 action 用 **~200 行 bash** 加 `git` / `ssh` / 标准 unix 工具做同样的事。零 npm 依赖，零嵌套 `uses:`。整个 action 就是 `action.yml` + `lib/checkout.sh`。

## 零依赖

这个 action **不依赖 x-cmd 安装**。只用：

- `git`（clone / fetch / checkout 本体）
- `ssh-agent`、`ssh-keyscan`（SSH 认证）
- `curl`（仅在拉 `known_hosts` 时）
- 标准 POSIX shell

如果你完全不想要 x-cmd 出现在 CI 里，这个 action 单独跑就行。它是 `x-cmd-action` org 里**唯一不依赖 x-cmd**的 action。

## 用法

```yaml
- uses: x-cmd-action/checkout@v1
```

最常见情况就这样 —— 当前 repo + ref + token 的浅 clone，行为同 `actions/checkout`。`with:` 块可选。

### 带 repo-scoped git config（比如这个 checkout 自己的 hooks）

`gitconfig` input 给 **cloned repo 自己**加 `.git/config`（用 `[include] path = <file>`），**不动** `~/.gitconfig` —— job 里其他 repo 不受影响。给单 repo 的特定配置用：自定义 hooks、签名 key、alias 等。

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    path: src
    gitconfig: .github/repo.gitconfig
```

`.github/repo.gitconfig`：

```ini
[user]
    email = repo-specific@example.com

; Git 2.54+ 内联 hooks
[hook "pre-commit-lint"]
    event = pre-commit
    command = ./scripts/lint.sh

; 旧版 Git：要 script-based hooks 的话，手动设 core.hooksPath
```

文件内容通过 git 原生 `[include]` 合并进 repo 的 `.git/config`。repo 已有的其他 config 都保留。

> 需要对**整个 job 的所有 repo**都生效的 config（不只这一个 checkout）？用 [`x-cmd-action/gitconfig`](https://github.com/x-cmd-action/gitconfig) —— 它写 `~/.gitconfig`（job 全局），不是 repo 的 `.git/config`（仅本 repo）。

### 常见用例

**全量历史** —— 给 `git log` / `git blame` 用：

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    fetch-depth: 0
```

**Submodules** —— 递归初始化 + 拉取：

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    submodules: recursive
```

**Git LFS 文件** —— 顺手把 LFS 跟踪的大文件拉下来：

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    lfs: true
```

**私有 repo 用 SSH** —— 用 deploy key 替代默认 token：

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    ssh-key: ${{ secrets.SSH_PRIVATE_KEY }}
```

**自定义路径** —— 克隆到子目录，不覆盖 workspace 根：

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    path: src
```

**指定 ref / tag / SHA**：

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    ref: v1.2.3
```

**Sparse checkout** —— 只拉部分路径（monorepo 省时间）：

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    sparse-checkout: |
      docs/
      src/**/*.go
```

### 组合使用

各 input 相互独立，自由组合：

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    submodules: recursive
    lfs: true
    fetch-depth: 0
    ssh-key: ${{ secrets.SSH_PRIVATE_KEY }}
```

input 名称尽量和 `actions/checkout` 对齐。`repository` / `ref` 的默认值来自 `github.*` context，行为一致。

## Inputs

20 个 input，覆盖 `actions/checkout@v4` 的全部输入：

### 仓库身份与目标

| Input | 默认 | 说明 |
| --- | --- | --- |
| `repository` | `${{ github.repository }}` | 要 clone 的 `<owner>/<repo>` |
| `ref` | `${{ github.ref_name }}` | branch、tag 或 SHA |
| `path` | `${{ github.workspace }}` | clone 到的目录 |
| `clean` | `true` | clone 前是否清空目标目录 |

### 认证

| Input | 默认 | 说明 |
| --- | --- | --- |
| `token` | `${{ github.token }}` | HTTPS 模式 token，用于私有 repo |
| `ssh-key` | — | SSH 私钥（设了就优先用 SSH，覆盖 token） |
| `ssh-known-hosts` | — | 自定义 known_hosts 内容（字面写入） |
| `ssh-strict` | `true` | 是否强制严格 host key 检查 |
| `require-ssh-key` | `false` | 是否强制要求 ssh-key（不允许回退到 token） |
| `github-server-url` | `${{ github.server_url }}` | 覆盖用，Enterprise Server 场景 |

### Fetch 行为

| Input | 默认 | 说明 |
| --- | --- | --- |
| `fetch-depth` | `1` | 取多少历史；`0` = 全量 |
| `fetch-tags` | `false` | 是否 fetch tags |
| `fetch-additional` | — | 额外的 ref 列表（空格分隔） |

### Submodule / LFS / Sparse

| Input | 默认 | 说明 |
| --- | --- | --- |
| `submodules` | `false` | `false` / `true` / `recursive` |
| `lfs` | `false` | checkout 后跑 `git lfs pull` |
| `sparse-checkout` | — | sparse 模式（每行一条 pattern） |
| `sparse-checkout-cone-mode` | `true` | 是否用 cone 模式 |

### 其他

| Input | 默认 | 说明 |
| --- | --- | --- |
| `persist-credentials` | `true` | clone 完 token 是否留在 `.git/config` |
| `gitconfig` | — | `.gitconfig` 文件路径。设了之后会往 cloned repo 的 `.git/config` 里加 `[include] path = <file>` —— git 在该 repo 内查 config 时会读这个文件，**不会动 runner 的全局 `~/.gitconfig`**。 |
| `show-progress` | `true` | fetch / checkout 时是否显示进度 |
| `set-safe-directory` | `true` | 自动加 `safe.directory '*'`（container 环境需要） |

## 原理

```
┌────────────────────────────────────────┐
│  x-cmd-action/checkout                 │
│  ─ 读 input                            │
│  ─ safe.directory（按需）              │
│  ─ 认证：SSH / token / 公开           │
│  ─ git init / fetch / checkout        │
│  ─ sparse、submodules、LFS            │
│  ─ 按需 strip token                   │
│  ─ 配 github-actions[bot] identity    │
└────────────────────────────────────────┘
         │
         └─ 只依赖：git, ssh-keyscan, ssh-agent, 标准 POSIX 工具
```

没有 Node.js、没有嵌套 `uses:`、没有 npm 包。action tarball 本身只有 `action.yml` + `lib/checkout.sh`。

## 与 `actions/checkout` 的对比

| 维度 | `actions/checkout@v4` | `x-cmd-action/checkout` |
| --- | --- | --- |
| Runtime | bash + Node.js | 纯 bash |
| Tarball 大小 | 几 MB JS bundle | ~3 KB shell |
| 启动开销 | ~2–3s（Node + bundle） | ~0s |
| Inputs 数 | 20 | 20（同名） |
| LFS / submodules / sparse | ✅ | ✅ |
| 私有 repo（token / ssh-key） | ✅ | ✅ |
| Windows runner | ✅（Node 路径） | ✅（Git Bash） |
| 默认 identity | `github-actions[bot]` | `github-actions[bot]` |

两个 action 在 workflow 输入层完全兼容，可以无缝互换。

## 已知差异（相对 `actions/checkout`）

- **没有 JS 端的中间计算缓存**。所有 input 在 bash 里读取 —— 外部可观察行为一致。
- **Sparse checkout**：直接写 `.git/info/sparse-checkout` 文件（`git sparse-checkout set` 内部也就是写这个文件）—— 终态相同。
- **Submodules + fetch-depth**：透传 `--depth` 给 `git submodule update`。新版 `actions/checkout` 同样行为。
- **LFS 检测**：如果 `git-lfs` 没装，**打印 warning 后继续**，而不是报错。

## 许可证

Apache 2.0 —— 见 [`LICENSE`](LICENSE)。

## 相关链接

- [x-cmd-action/gitmirror](https://github.com/x-cmd-action/gitmirror) —— 跨平台 repo 镜像 action。
- [actions/checkout](https://github.com/actions/checkout) —— 本 action 替代的 TypeScript 原版。