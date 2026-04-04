#!/usr/bin/env bats
# status.bats — test modules status task

bats_require_minimum_version 1.5.0

setup() {
  load test_helper

  REMOTE="$BATS_TEST_TMPDIR/remote"
  PARENT="$BATS_TEST_TMPDIR/parent"

  create_remote_repo "$REMOTE"
  create_parent_repo "$PARENT"
  export CALLER_PWD="$PARENT"

  modules setup
  git -C "$PARENT" commit -m "init modules"
}

@test "status shows at pin for clean module" {
  modules add "$REMOTE" --name my-repo

  run modules status
  [ "$status" -eq 0 ]
  [[ "$output" == *"my-repo"* ]]
  [[ "$output" == *"at pin"* ]]
}

@test "status shows changed when module has new commits" {
  modules add "$REMOTE" --name my-repo

  local hash
  hash="$(hash_name "my-repo")"

  # Make a new commit in the clone
  echo "new" > "$PARENT/submodules/$hash/new.md"
  git -C "$PARENT/submodules/$hash" add new.md
  git -C "$PARENT/submodules/$hash" commit -m "new commit"

  run modules status
  [ "$status" -eq 0 ]
  [[ "$output" == *"changed"* ]]
}

@test "status shows missing when clone is absent" {
  modules add "$REMOTE" --name my-repo
  git -C "$PARENT" commit -m "add module"

  local hash
  hash="$(hash_name "my-repo")"
  rm -rf "$PARENT/submodules/$hash"

  run modules status
  [ "$status" -eq 0 ]
  [[ "$output" == *"missing"* ]]
}
