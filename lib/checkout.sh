#!/usr/bin/env bash
# x-cmd-action/checkout — pure-shell implementation.
# 1:1 input parity with actions/checkout@v4 plus x-cmd enhancements:
#   - known-hosts-url (curl-fetch known_hosts)
#   - fetch-additional (additional refspecs)
#   - gitconfig (repo-scoped [include] for a .gitconfig file — repo-local
#     hooks, signing keys, identity overrides, etc.)
#
# SSH path mirrors actions/checkout's approach: temp files + GIT_SSH_COMMAND
# with explicit -i / UserKnownHostsFile / StrictHostKeyChecking flags. No
# ssh-agent, no writes to ~/.ssh/. The post-step cleanup that actions/checkout
# does in its `post:` entry is omitted here — /tmp is wiped on runner teardown.

set -eu

# ───────────────────── inputs ─────────────────────
REPOSITORY="${INPUT_REPOSITORY:-${GITHUB_REPOSITORY:-}}"
REF="${INPUT_REF:-${GITHUB_REF_NAME:-}}"
TOKEN="${INPUT_TOKEN:-${GITHUB_TOKEN:-}}"
SSH_KEY="${INPUT_SSH_KEY:-}"
SSH_KNOWN_HOSTS="${INPUT_SSH_KNOWN_HOSTS:-}"
KNOWN_HOSTS_URL="${INPUT_KNOWN_HOSTS_URL:-}"
SSH_STRICT="${INPUT_SSH_STRICT:-true}"
SSH_USER="${INPUT_SSH_USER:-git}"
PATH_DIR="${INPUT_PATH:-${GITHUB_WORKSPACE:-$(pwd)}}"
CLEAN="${INPUT_CLEAN:-true}"
FETCH_DEPTH="${INPUT_FETCH_DEPTH:-1}"
FETCH_TAGS="${INPUT_FETCH_TAGS:-false}"
FETCH_ADDITIONAL="${INPUT_FETCH_ADDITIONAL:-}"
LFS="${INPUT_LFS:-false}"
SUBMODULES="${INPUT_SUBMODULES:-false}"
SPARSE_CHECKOUT="${INPUT_SPARSE_CHECKOUT:-}"
SPARSE_CHECKOUT_CONE_MODE="${INPUT_SPARSE_CHECKOUT_CONE_MODE:-true}"
FILTER="${INPUT_FILTER:-}"
PERSIST_CREDENTIALS="${INPUT_PERSIST_CREDENTIALS:-true}"
SHOW_PROGRESS="${INPUT_SHOW_PROGRESS:-true}"
SET_SAFE_DIRECTORY="${INPUT_SET_SAFE_DIRECTORY:-true}"
GITHUB_SERVER_URL="${INPUT_GITHUB_SERVER_URL:-${GITHUB_SERVER_URL:-https://github.com}}"
ALLOW_UNSAFE_PR_CHECKOUT="${INPUT_ALLOW_UNSAFE_PR_CHECKOUT:-false}"
GITCONFIG="${INPUT_GITCONFIG:-}"

# Derived
HOST=$(echo "$GITHUB_SERVER_URL" | sed -E 's|^https?://||; s|/.*$||')
GIT_QUIET=""
[ "$SHOW_PROGRESS" != "true" ] && GIT_QUIET="--quiet"

# ───────────────────── safe.directory ─────────────────────
if [ "$SET_SAFE_DIRECTORY" = "true" ]; then
    git config --global --add safe.directory '*' >/dev/null 2>&1 || true
fi

# ───────────────────── auth mode ─────────────────────
URL=""
USING_TOKEN=false
USING_SSH=false

if [ -n "$SSH_KEY" ]; then
    USING_SSH=true

    # 1. Write private key to a temp file (600, never on disk in ~)
    SSH_KEY_PATH=$(mktemp "${RUNNER_TEMP:-/tmp}/checkout_ssh_key.XXXXXX")
    chmod 600 "$SSH_KEY_PATH"
    printf '%s\n' "$SSH_KEY" > "$SSH_KEY_PATH"

    # 2. Build merged known_hosts in a temp file. Order:
    #    a) user's existing ~/.ssh/known_hosts (if any)
    #    b) ssh-known-hosts input (verbatim)
    #    c) known-hosts-url input (curl, warn on failure — don't break checkout)
    #    d) hardcoded github.com public key (offline-safe MITM defense)
    KNOWN_HOSTS_PATH=$(mktemp "${RUNNER_TEMP:-/tmp}/checkout_known_hosts.XXXXXX")
    chmod 644 "$KNOWN_HOSTS_PATH"

    if [ -f "$HOME/.ssh/known_hosts" ]; then
        cat "$HOME/.ssh/known_hosts" >> "$KNOWN_HOSTS_PATH"
    fi

    if [ -n "$SSH_KNOWN_HOSTS" ]; then
        {
            echo "# Begin from ssh-known-hosts input"
            printf '%s\n' "$SSH_KNOWN_HOSTS"
            echo "# End from ssh-known-hosts input"
        } >> "$KNOWN_HOSTS_PATH"
    fi

    if [ -n "$KNOWN_HOSTS_URL" ]; then
        if curl -fsSL --connect-timeout 15 "$KNOWN_HOSTS_URL" >> "$KNOWN_HOSTS_PATH" 2>/dev/null; then
            echo "# fetched known_hosts from $KNOWN_HOSTS_URL" >> "$KNOWN_HOSTS_PATH"
        else
            echo "WARN: failed to fetch known_hosts from $KNOWN_HOSTS_URL, continuing" >&2
        fi
    fi

    # Hardcoded github.com public key — pinned regardless of network state.
    # (Equivalent to what actions/checkout embeds.)
    cat >> "$KNOWN_HOSTS_PATH" <<'KNOWN_HOSTS_GITHUB_COM'
# Begin implicitly added github.com
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
# End implicitly added github.com
KNOWN_HOSTS_GITHUB_COM

    # 3. Build GIT_SSH_COMMAND
    SSH_BIN="$(command -v ssh)"
    GIT_SSH_COMMAND="\"${SSH_BIN}\" -i \"${SSH_KEY_PATH}\" -o UserKnownHostsFile=\"${KNOWN_HOSTS_PATH}\""
    if [ "$SSH_STRICT" = "true" ]; then
        GIT_SSH_COMMAND="${GIT_SSH_COMMAND} -o StrictHostKeyChecking=yes -o CheckHostIP=no"
    else
        GIT_SSH_COMMAND="${GIT_SSH_COMMAND} -o StrictHostKeyChecking=no"
    fi
    GIT_SSH_COMMAND="${GIT_SSH_COMMAND} -l \"${SSH_USER}\""

    export GIT_SSH_COMMAND
    URL="${SSH_USER}@${HOST}:${REPOSITORY}.git"
elif [ -n "$TOKEN" ]; then
    USING_TOKEN=true
    URL="https://x-access-token:${TOKEN}@${HOST}/${REPOSITORY}.git"
else
    URL="${GITHUB_SERVER_URL}/${REPOSITORY}.git"
fi

# ───────────────────── prepare path ─────────────────────
# Two Windows fixes applied here:
#   (a) cd to a safe dir BEFORE removing PATH_DIR. The runner's cwd may
#       already be inside PATH_DIR (left over from a prior actions/checkout
#       step), and `rm -rf` of cwd fails with "Device or resource busy".
#   (b) convert PATH_DIR to POSIX form (D:\a\... -> /d/a/...) before
#       using it as a path argument. Bash on Windows interprets backslashes
#       as escape characters, so an unquoted/unconverted Windows path
#       silently mangles to nonsense ("D:a_actions..."). cygpath -u is
#       available in Git Bash; on Linux/macOS the input is already POSIX.
if command -v cygpath >/dev/null 2>&1; then
    PATH_DIR=$(cygpath -u "$PATH_DIR")
fi
if [ "$CLEAN" = "true" ] && [ -d "$PATH_DIR" ]; then
    # Force cwd out of PATH_DIR before rm. On Windows, even with cwd
    # outside PATH_DIR, rm can still fail with "Device or resource busy"
    # if any file inside PATH_DIR is held open by another process.
    # Best-effort cleanup: cd to parent first, then try git clean (if
    # it's a git repo), then fall back to rm.
    PARENT_DIR=$(dirname "$PATH_DIR")
    cd "$PARENT_DIR" 2>/dev/null || cd / 2>/dev/null || cd /tmp 2>/dev/null || true
    if [ -d "$PATH_DIR/.git" ]; then
        # It's a git repo — use git to release locks + clean tracked state.
        GIT_WORK_TREE="$PATH_DIR" GIT_DIR="$PATH_DIR/.git" \
            git remote remove origin 2>/dev/null || true
    fi
    rm -rf "$PATH_DIR" 2>/dev/null || {
        echo "WARN: rm -rf failed on $PATH_DIR — retrying after sleep" >&2
        sleep 1
        rm -rf "$PATH_DIR" 2>/dev/null || true
    }
fi
mkdir -p "$PATH_DIR"
cd "$PATH_DIR"

# ───────────────────── init / re-init ─────────────────────
if [ -d ".git" ]; then
    git remote set-url origin "$URL"
else
    git init -q
    git remote add origin "$URL"
fi

# ───────────────────── partial clone (filter) ─────────────────────
# filter= overrides sparse-checkout when both are set (actions/checkout parity).
if [ -n "$FILTER" ]; then
    git config --local remote.origin.promisor true
    git config --local remote.origin.partialclonefilter "$FILTER"
fi

# ───────────────────── sparse checkout ─────────────────────
if [ -n "$SPARSE_CHECKOUT" ] && [ -z "$FILTER" ]; then
    git config core.sparseCheckout true
    if [ "$SPARSE_CHECKOUT_CONE_MODE" = "true" ]; then
        git config core.sparseCheckoutCone true
    else
        git config core.sparseCheckoutCone false
    fi
    mkdir -p .git/info
    printf '%s\n' "$SPARSE_CHECKOUT" > .git/info/sparse-checkout
fi

# ───────────────────── persist ssh command for follow-up git ops ─────────────────────
if [ "$USING_SSH" = "true" ] && [ "$PERSIST_CREDENTIALS" = "true" ]; then
    git config --local core.sshCommand "$GIT_SSH_COMMAND"
fi

# ───────────────────── fetch ─────────────────────
FETCH_ARGS=()
if [ -z "$FILTER" ] && [ "$FETCH_DEPTH" != "0" ]; then
    FETCH_ARGS+=(--depth="$FETCH_DEPTH")
    # --depth implies --single-branch by default in many git versions
    FETCH_ARGS+=(--no-tags)
fi
[ "$FETCH_TAGS" = "true" ] && FETCH_ARGS+=(--tags)
[ -n "$FILTER" ] && FETCH_ARGS+=(--filter="$FILTER")

# Build additional refspec if provided
ADDITIONAL_REFS=()
if [ -n "$FETCH_ADDITIONAL" ]; then
    # shellcheck disable=SC2206
    ADDITIONAL_REFS=($FETCH_ADDITIONAL)
fi

# Allow-unsafe-pr-checkout: bypass any future safety gates (matches actions/checkout behavior).
# Currently this action always honors the fetch; the flag exists for forward-compat with
# actions/checkout's permission check semantics.
_unsafe_pr_marker=""
if [ "$ALLOW_UNSAFE_PR_CHECKOUT" = "true" ]; then
    _unsafe_pr_marker="allow-unsafe-pr-checkout=true"
fi

git fetch $GIT_QUIET "${FETCH_ARGS[@]}" origin "$REF" "${ADDITIONAL_REFS[@]:+${ADDITIONAL_REFS[@]}}" || {
    if [ "$ALLOW_UNSAFE_PR_CHECKOUT" != "true" ] && [ -n "$_unsafe_pr_marker" ]; then
        echo "ERROR: failed to fetch ref $REF. If this is a fork PR, set allow-unsafe-pr-checkout: 'true'" >&2
    fi
    exit 1
}

# ───────────────────── checkout ─────────────────────
git checkout $GIT_QUIET -f FETCH_HEAD

# ───────────────────── submodules ─────────────────────
case "$SUBMODULES" in
    true|recursive)
        git submodule sync --recursive
        if [ "$SUBMODULES" = "recursive" ]; then
            git submodule update --init --recursive --depth "$FETCH_DEPTH"
        else
            git submodule update --init --depth "$FETCH_DEPTH"
        fi
        ;;
esac

# ───────────────────── LFS ─────────────────────
if [ "$LFS" = "true" ]; then
    if command -v git-lfs >/dev/null 2>&1; then
        git lfs pull
    else
        echo "WARN: git-lfs not installed, skipping LFS pull" >&2
    fi
fi

# ───────────────────── strip credentials if not persisting ─────────────────────
if [ "$PERSIST_CREDENTIALS" = "false" ]; then
    if [ "$USING_TOKEN" = "true" ]; then
        git remote set-url origin "${GITHUB_SERVER_URL}/${REPOSITORY}.git"
    elif [ "$USING_SSH" = "true" ]; then
        git config --local --unset core.sshCommand
    fi
fi

# ───────────────────── git identity + repo-scoped config ─────────────────────
# Always set the bot identity (matches actions/checkout's behavior). If
# local-config is set, it overlays repo-specific values (signing keys,
# custom identity, etc.) via [include] — git's config precedence means
# the local file's values win for keys that overlap.
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

if [ -n "$GITCONFIG" ]; then
    if [ ! -f "$GITCONFIG" ]; then
        echo "ERROR: gitconfig file not found: $GITCONFIG" >&2
        exit 1
    fi
    INCLUDE_PATH=$(realpath "$GITCONFIG")
    git config --local include.path "$INCLUDE_PATH"
    echo "gitconfig: include.path=$INCLUDE_PATH (repo-scoped)"
fi
