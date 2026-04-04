#!/usr/bin/env bash
# test_helper.bash — shared fixtures for modules tests

if [ -z "${MISE_CONFIG_ROOT:-}" ]; then
  echo "MISE_CONFIG_ROOT not set — run tests via: mise run test" >&2
  exit 1
fi

REPO_DIR="$MISE_CONFIG_ROOT"

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

# Get the gitlink mode and SHA for a path in the parent's index.
# Usage: gitlink_info <parent> <path>
# Output: "mode sha" (e.g., "160000 abc123...")
gitlink_info() {
  git -C "$1" ls-files --stage "$2" | awk '{print $1, $2}'
}
