#!/usr/bin/env bats
# remove.bats — test modules remove task

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

@test "remove deletes clone and manifest entry" {
  modules add "$REMOTE" --name my-repo
  git -C "$PARENT" commit -m "add module"

  local hash
  hash="$(hash_name "my-repo")"

  run modules remove my-repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed"* ]]

  # Clone should be gone
  [ ! -d "$PARENT/submodules/$hash" ]

  # Manifest should be empty
  run jq 'length' "$PARENT/submodules/.manifest"
  [ "$output" = "0" ]
}

@test "remove unstages the gitlink" {
  modules add "$REMOTE" --name my-repo
  git -C "$PARENT" commit -m "add module"

  local hash
  hash="$(hash_name "my-repo")"

  modules remove my-repo

  # Gitlink should no longer be in the index
  run git -C "$PARENT" ls-files --stage "submodules/$hash"
  [ -z "$output" ]
}

@test "remove fails for unknown module" {
  run modules remove nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "remove one of multiple modules leaves others intact" {
  local remote2="$BATS_TEST_TMPDIR/remote2"
  create_remote_repo "$remote2"

  modules add "$REMOTE" --name first
  modules add "$remote2" --name second
  git -C "$PARENT" commit -m "add modules"

  modules remove first

  # Second should still exist
  local hash2
  hash2="$(hash_name "second")"
  [ -d "$PARENT/submodules/$hash2" ]
  run jq -r 'keys[0]' "$PARENT/submodules/.manifest"
  [ "$output" = "second" ]
}
