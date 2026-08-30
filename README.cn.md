# x-cmd-action/checkout

> 纯 shell 实现的 [`actions/checkout`](https://github.com/actions/checkout) 替代 —— **input 1:1 兼容，行为对齐，不依赖 Node.js**。再加三个 x-cmd 独家增强。

[English](./README.md)

## 这是什么

`actions/checkout` 是 TypeScript 写的，依赖 `@actions/core`、`@actions/github` 等一票 npm 包。每次 CI 跑都要：

- 下载 ~1MB 的 JS bundle
- 启动 Node.js
- 解析并执行 bundle

—— 而真正做的事只是 `git clone`。完全是大炮打蚊子。

这个 action 用 **~250 行 bash** 加 `git` / `ssh` / 标准 unix 工具做同样的事。零 npm 依赖，零嵌套 `uses:`。整个 action 就是 `action.yml` + `lib/checkout.sh`。

## 零依赖

这个 action **不依赖 x-cmd 安装**。只用：

- `git`（clone / fetch / checkout 本体）
- `ssh`（SSH 认证 —— 不启动 `ssh-agent`，直接用 `GIT_SSH_COMMAND`）
- `curl`（仅在用 `known-hosts-url` 时）
- 标准 POSIX shell

## 与 `actions/checkout` 的 input 兼容

`actions/checkout@v4` 的每一个 input 都有同名同语义对应。在它之上叠了三个 **x-cmd 增强**：

| Input | 来源 |
| --- | --- |
| `known-hosts-url` | **x-cmd 增强** —— `curl` 拉 known_hosts |
| `fetch-additional` | **x-cmd 增强** —— 额外 refspec 一起 fetch |
| `gitconfig` | **x-cmd 增强** —— repo-scoped `[include] path` 到指定 `.gitconfig` |

用过 `actions/checkout`，就会用这个。

## 用法

```yaml
- uses: x-cmd-action/checkout@v1
```

最常见情况就这样 —— 当前 repo + ref + token 的浅 clone，行为同 `actions/checkout`。`with:` 块可选。

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

**一次 fetch 多个 ref** —— x-cmd 增强，跟默认 ref 一起拉额外分支：

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    fetch-additional: refs/heads/main refs/heads/release
```

**Sparse checkout** —— 只拉部分路径（monorepo 省时间）：

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    sparse-checkout: |
      docs/
      src/**/*.go
```

**Repo-scoped git config** —— x-cmd 增强，给这个 checkout 自己的 `.gitconfig`：

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
```

> 需要对**整个 job 的所有 repo** 都生效的 config（不只这一个 checkout）？用 [`x-cmd-action/gitconfig`](https://github.com/x-cmd-action/gitconfig) —— 它写 `~/.gitconfig`（job 全局），不是 repo 的 `.git/config`（仅本 repo）。

### 组合使用

各 input 相互独立，自由组合：

```yaml
- uses: x-cmd-action/checkout@v1
  with:
    submodules: recursive
    lfs: true
    fetch-depth: 0
    ssh-key: ${{ secrets.SSH_PRIVATE_KEY }}
    fetch-additional: refs/heads/main refs/heads/release
```

## SSH 路径

照搬 `actions/checkout` 的做法 —— **不启动 ssh-agent**，**不污染 `~/.ssh/`**：

1. 私钥写到 temp 文件（600）
2. 合并后的 `known_hosts` 写到 temp 文件，按顺序：
   - 用户已有的 `~/.ssh/known_hosts`（如果有）
   - `ssh-known-hosts` input（字面写入）
   - `known-hosts-url` input（`curl` 拉，**x-cmd 增强**）
   - 硬编码的 `github.com` 公钥（pinned，离线也能防 MITM）
3. `GIT_SSH_COMMAND` 拼成 `-i <keypath> -o UserKnownHostsFile=<known_hosts> [-o StrictHostKeyChecking=yes]`
4. 当 `persist-credentials: true` 时写进 repo 的 `core.sshCommand` —— 后续 git 命令直接复用

Temp 文件在 `$RUNNER_TEMP` 下，runner 回收时清理。

## Inputs

下表所有 input 与 `actions/checkout@v4` 同名同语义，除非特别标注。

### 仓库身份与目标

| Input | 默认 | 说明 |
| --- | --- | --- |
| `repository` | `${{ github.repository }}` | 要 clone 的 `<owner>/<repo>` |
| `ref` | `${{ github.ref_name }}` | branch、tag 或 SHA |
| `path` | `${{ github.workspace }}` | clone 到的目录 |
| `clean` | `true` | clone 前是否清空目标目录 |
| `github-server-url` | `${{ github.server_url }}` | Enterprise 场景下覆盖 |
| `allow-unsafe-pr-checkout` | `false` | fork PR 用 `pull_request_target` / `workflow_run` 触发时必填 |

### 认证

| Input | 默认 | 说明 |
| --- | --- | --- |
| `token` | `${{ github.token }}` | HTTPS 模式 token，用于私有 repo |
| `ssh-key` | — | SSH 私钥（设了就优先用 SSH，覆盖 token） |
| `ssh-known-hosts` | — | 自定义 known_hosts 内容（字面写入） |
| **`known-hosts-url`** | — | **x-cmd 增强。** known_hosts 文件的 URL（运行时 `curl` 拉）。host key 集中管理时用。 |
| `ssh-strict` | `true` | 是否强制严格 host key 检查 |
| `ssh-user` | `git` | SSH 登录用户名 |
| `persist-credentials` | `true` | clone 完认证信息是否留在 repo config 里供后续 git 命令用 |

### Fetch 行为

| Input | 默认 | 说明 |
| --- | --- | --- |
| `fetch-depth` | `1` | 取多少历史；`0` = 全量 |
| `fetch-tags` | `false` | 是否 fetch tags |
| **`fetch-additional`** | — | **x-cmd 增强。** 同一 fetch 里额外的 ref 列表（空格分隔）。 |

### Submodule / LFS / Sparse / Filter

| Input | 默认 | 说明 |
| --- | --- | --- |
| `submodules` | `false` | `false` / `true` / `recursive` |
| `lfs` | `false` | checkout 后跑 `git lfs pull` |
| `sparse-checkout` | — | sparse 模式（每行一条 pattern） |
| `sparse-checkout-cone-mode` | `true` | 是否用 cone 模式 |
| `filter` | — | 部分 clone 过滤器（`blob:none`、`tree:0` 等）；设了就覆盖 `sparse-checkout` |

### 其他

| Input | 默认 | 说明 |
| --- | --- | --- |
| **`gitconfig`** | — | **x-cmd 增强。** `.gitconfig` 文件路径。设了之后会往 cloned repo 的 `.git/config` 里加 `[include] path = <file>` —— git 在该 repo 内查 config 时会读这个文件，**不会动 runner 的全局 `~/.gitconfig`**。 |
| `show-progress` | `true` | fetch / checkout 时是否显示进度 |
| `set-safe-directory` | `true` | 自动加 `safe.directory '*'`（container 环境需要） |

## 与 `actions/checkout` 的对比

| 维度 | `actions/checkout@v4` | `x-cmd-action/checkout` |
| --- | --- | --- |
| Runtime | bash + Node.js | 纯 bash |
| Tarball 大小 | 几 MB JS bundle | ~3 KB shell |
| 启动开销 | ~2–3s（Node + bundle） | ~0s |
| Inputs 数 | 22 | 22（同名）+ 3 x-cmd 增强 |
| LFS / submodules / sparse / filter | ✅ | ✅ |
| 私有 repo（token / ssh-key / ssh-user） | ✅ | ✅ |
| 从 URL 拉 known_hosts | ❌ | ✅（`known-hosts-url`） |
| 一次 fetch 多个 refspec | ❌ | ✅（`fetch-additional`） |
| Repo-scoped `[include]` gitconfig | ❌ | ✅（`gitconfig`） |
| Windows runner | ✅（Node 路径） | ✅（Git Bash） |
| 默认 identity | `github-actions[bot]` | `github-actions[bot]` |

**workflow 里把 `actions/checkout@v4` 换成 `x-cmd-action/checkout@v1`，所有 input 都不用改** —— `actions/checkout@v4` 的每个 input 都有同名支持。

## 已知差异（相对 `actions/checkout`）

- **没有 JS 端的中间计算缓存**。所有 input 在 bash 里读取 —— 外部可观察行为一致。
- **Sparse checkout**：直接写 `.git/info/sparse-checkout` 文件（`git sparse-checkout set` 内部也就是写这个文件）—— 终态相同。
- **Submodules + fetch-depth**：透传 `--depth` 给 `git submodule update`。新版 `actions/checkout` 同样行为。
- **LFS 检测**：如果 `git-lfs` 没装，**打印 warning 后继续**，而不是报错。
- **`allow-unsafe-pr-checkout`**：input 接受并保留，但这个 action 当前不会主动拒绝跑 fork PR。实际效果一致 —— 控制 checkout 行为的 input（token / ssh-key）仍然需要显式赋值。

## 许可证

Apache 2.0 —— 见 [`LICENSE`](LICENSE)。

## 相关链接

- [actions/checkout](https://github.com/actions/checkout) —— 本 action 作为纯 shell 替代的原版。
- [x-cmd-action/gitconfig](https://github.com/x-cmd-action/gitconfig) —— 全局 `~/.gitconfig` 设置（job 内所有 repo 生效，不是单 repo）。
- [x-cmd-action/gitmirror](https://github.com/x-cmd-action/gitmirror) —— 跨平台 repo 镜像 action。
- [x-cmd-action/.github](https://github.com/x-cmd-action/.github) —— org 主页 + 路线图。
