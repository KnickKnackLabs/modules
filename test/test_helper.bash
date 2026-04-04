#!/usr/bin/env bash
# test_helper.bash — shared fixtures for modules tests

if [ -z "${MISE_CONFIG_ROOT:-}" ]; then
  echo "MISE_CONFIG_ROOT not set — run tests via: mise run test" >&2
  exit 1
fi

REPO_DIR="$MISE_CONFIG_ROOT"

# Run a modules task through mise.
modules() {
  if [ -z "${CALLER_PWD:-}" ]; then
    echo "CALLER_PWD not set" >&2
    return 1
  fi
  cd "$MISE_CONFIG_ROOT" && CALLER_PWD="$CALLER_PWD" mise run -q "$@"
}
export -f modules

# Create a local "remote" repo with some commits.
# Usage: create_remote_repo <path>
# Returns: the path, with a repo containing 2 commits.
create_remote_repo() {
  local path="$1"
  mkdir -p "$path"
  git -C "$path" init -b main
  git -C "$path" commit --allow-empty -m "initial commit"
  echo "hello" > "$path/README.md"
  git -C "$path" add README.md
  git -C "$path" commit -m "add readme"
}

# Create a parent repo (the one that will contain submodules).
# Usage: create_parent_repo <path>
create_parent_repo() {
  local path="$1"
  mkdir -p "$path"
  git -C "$path" init -b main
  git -C "$path" commit --allow-empty -m "initial commit"
}

# Get the HEAD SHA of a repo.
# Usage: repo_head <path>
repo_head() {
  git -C "$1" rev-parse HEAD
}

# Skip a test if git-crypt is not available.
skip_unless_git_crypt() {
  if ! command -v git-crypt &>/dev/null; then
    skip "git-crypt not installed"
  fi
}

# Skip a test if no GPG key is available for testing.
# Uses the current user's first secret key.
skip_unless_gpg_key() {
  local fpr
  fpr="$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')"
  if [ -z "$fpr" ]; then
    skip "no GPG secret key available"
  fi
  export TEST_GPG_FINGERPRINT="$fpr"
}

# Import hash_name from common.sh — single source of truth.
# shellcheck source=../lib/common.sh
source "$REPO_DIR/lib/common.sh"
export -f hash_name

# Get the gitlink mode and SHA for a path in the parent's index.
# Usage: gitlink_info <parent> <path>
# Output: "mode sha" (e.g., "160000 abc123...")
gitlink_info() {
  git -C "$1" ls-files --stage "$2" | awk '{print $1, $2}'
}
