#!/usr/bin/env bash
# x-cmd-action/checkout — pure-shell implementation.
# Replaces every input of actions/checkout@v4 in a single bash step.

set -euo errexit
echo "::debug::checkout.sh start; cwd=$(pwd); INPUT_PATH=${INPUT_PATH:-<unset>}"

# ───────────────────── inputs ─────────────────────
REPOSITORY="${INPUT_REPOSITORY:-${GITHUB_REPOSITORY:-}}"
REF="${INPUT_REF:-${GITHUB_REF_NAME:-}}"
TOKEN="${INPUT_TOKEN:-${GITHUB_TOKEN:-}}"
SSH_KEY="${INPUT_SSH_KEY:-}"
SSH_KNOWN_HOSTS="${INPUT_SSH_KNOWN_HOSTS:-}"
SSH_STRICT="${INPUT_SSH_STRICT:-true}"
PATH_DIR="${INPUT_PATH:-${GITHUB_WORKSPACE:-$(pwd)}}"
CLEAN="${INPUT_CLEAN:-true}"
FETCH_DEPTH="${INPUT_FETCH_DEPTH:-1}"
FETCH_TAGS="${INPUT_FETCH_TAGS:-false}"
FETCH_ADDITIONAL="${INPUT_FETCH_ADDITIONAL:-}"
LFS="${INPUT_LFS:-false}"
SUBMODULES="${INPUT_SUBMODULES:-false}"
SPARSE_CHECKOUT="${INPUT_SPARSE_CHECKOUT:-}"
SPARSE_CHECKOUT_CONE_MODE="${INPUT_SPARSE_CHECKOUT_CONE_MODE:-true}"
PERSIST_CREDENTIALS="${INPUT_PERSIST_CREDENTIALS:-true}"
SHOW_PROGRESS="${INPUT_SHOW_PROGRESS:-true}"
SET_SAFE_DIRECTORY="${INPUT_SET_SAFE_DIRECTORY:-true}"
GITHUB_SERVER_URL="${INPUT_GITHUB_SERVER_URL:-${GITHUB_SERVER_URL:-https://github.com}}"
REQUIRE_SSH_KEY="${INPUT_REQUIRE_SSH_KEY:-false}"

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

if [ -n "$SSH_KEY" ] || [ "$REQUIRE_SSH_KEY" = "true" ]; then
    if [ -z "$SSH_KEY" ]; then
        echo "ERROR: ssh-key is required when require-ssh-key is true" >&2
        exit 1
    fi
    eval "$(ssh-agent -s)" >/dev/null
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    touch ~/.ssh/known_hosts
    chmod 600 ~/.ssh/known_hosts
    # User-supplied known_hosts first (verbatim), then auto-scan
    if [ -n "$SSH_KNOWN_HOSTS" ]; then
        printf '%s\n' "$SSH_KNOWN_HOSTS" >> ~/.ssh/known_hosts
    fi
    # ssh-keyscan may fail on offline runners; don't error out
    ssh-keyscan -H "$HOST" 2>/dev/null >> ~/.ssh/known_hosts || true
    if [ "$SSH_STRICT" != "true" ]; then
        cat > ~/.ssh/config <<EOF
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
EOF
    fi
    printf '%s\n' "$SSH_KEY" > ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa
    ssh-add ~/.ssh/id_rsa >/dev/null
    URL="git@${HOST}:${REPOSITORY}.git"
elif [ -n "$TOKEN" ]; then
    USING_TOKEN=true
    URL="https://x-access-token:${TOKEN}@${HOST}/${REPOSITORY}.git"
else
    URL="${GITHUB_SERVER_URL}/${REPOSITORY}.git"
fi

# ───────────────────── prepare path ─────────────────────
if [ "$CLEAN" = "true" ] && [ -d "$PATH_DIR" ]; then
    rm -rf "$PATH_DIR"
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

# ───────────────────── sparse checkout ─────────────────────
if [ -n "$SPARSE_CHECKOUT" ]; then
    git config core.sparseCheckout true
    if [ "$SPARSE_CHECKOUT_CONE_MODE" = "true" ]; then
        git config core.sparseCheckoutCone true
    else
        git config core.sparseCheckoutCone false
    fi
    mkdir -p .git/info
    printf '%s\n' "$SPARSE_CHECKOUT" > .git/info/sparse-checkout
fi

# ───────────────────── fetch ─────────────────────
FETCH_ARGS=()
if [ "$FETCH_DEPTH" != "0" ]; then
    FETCH_ARGS+=(--depth="$FETCH_DEPTH")
    # --depth implies --single-branch by default in many git versions
    FETCH_ARGS+=(--no-tags)
fi
[ "$FETCH_TAGS" = "true" ] && FETCH_ARGS+=(--tags)

# Build additional refspec if provided
ADDITIONAL_REFS=()
if [ -n "$FETCH_ADDITIONAL" ]; then
    # shellcheck disable=SC2206
    ADDITIONAL_REFS=($FETCH_ADDITIONAL)
fi

git fetch $GIT_QUIET "${FETCH_ARGS[@]}" origin "$REF" "${ADDITIONAL_REFS[@]:+${ADDITIONAL_REFS[@]}}"

# ───────────────────── checkout ─────────────────────
# FETCH_HEAD contains the commit hash we just fetched
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
if [ "$PERSIST_CREDENTIALS" = "false" ] && [ "$USING_TOKEN" = "true" ]; then
    git remote set-url origin "${GITHUB_SERVER_URL}/${REPOSITORY}.git"
fi

# ───────────────────── github-actions bot identity ─────────────────────
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"