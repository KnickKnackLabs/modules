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
#
# Resolution order for the test key:
#   1. Pre-set TEST_GPG_FINGERPRINT (explicit override).
#   2. The secret key matching $GIT_AUTHOR_EMAIL (via testicles) — this is
#      the identity-scoped key, not some random first-in-the-keyring.
#   3. Skip if none of the above resolves.
skip_unless_gpg_key() {
  if [ -n "${TEST_GPG_FINGERPRINT:-}" ]; then
    return 0
  fi

  if ! command -v testicles &>/dev/null; then
    skip "testicles not installed (needed to resolve GPG identity key)"
  fi

  local email="${GIT_AUTHOR_EMAIL:-}"
  if [ -z "$email" ]; then
    skip "GIT_AUTHOR_EMAIL not set — cannot resolve identity key"
  fi

  local fpr
  fpr="$(testicles inspect "$email" --first --json 2>/dev/null | jq -r '.fingerprint // empty')" || true
  if [ -z "$fpr" ]; then
    skip "no secret key matches $email"
  fi

  export TEST_GPG_FINGERPRINT="$fpr"
}

# Import module_path from common.sh — single source of truth.
# Note: common.sh requires CALLER_PWD; tests using module_path must set it first.
# shellcheck source=../lib/common.sh
# Source in a subshell-safe way: common.sh uses set -euo pipefail but we want the
# functions available in the current shell.
CALLER_PWD="${CALLER_PWD:-/tmp}" source "$REPO_DIR/lib/common.sh"
export -f module_path
