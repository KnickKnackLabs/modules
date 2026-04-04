#!/usr/bin/env bats
# list.bats — test modules list task

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

@test "list shows empty message with no modules" {
  run modules list
  [ "$status" -eq 0 ]
  [[ "$output" == *"No modules"* ]]
}

@test "list shows module after add" {
  modules add "$REMOTE" --name my-repo
  run modules list
  [ "$status" -eq 0 ]
  [[ "$output" == *"my-repo"* ]]
  [[ "$output" == *"$REMOTE"* ]]
}

@test "list --json outputs valid JSON" {
  modules add "$REMOTE" --name my-repo
  run modules list --json
  [ "$status" -eq 0 ]

  # Should be parseable JSON with our module
  echo "$output" | jq -e '.["my-repo"].url' >/dev/null
}

@test "list shows multiple modules" {
  local remote2="$BATS_TEST_TMPDIR/remote2"
  create_remote_repo "$remote2"

  modules add "$REMOTE" --name first
  modules add "$remote2" --name second

  run modules list
  [ "$status" -eq 0 ]
  [[ "$output" == *"first"* ]]
  [[ "$output" == *"second"* ]]
}
