#!/usr/bin/env bats
# setup.bats — test modules setup task

bats_require_minimum_version 1.5.0

setup() {
  load test_helper

  PARENT="$BATS_TEST_TMPDIR/parent"
  create_parent_repo "$PARENT"
  export CALLER_PWD="$PARENT"
}

@test "setup creates manifest" {
  run modules setup
  [ "$status" -eq 0 ]
  [ -f "$PARENT/submodules/.manifest" ]
  run cat "$PARENT/submodules/.manifest"
  [ "$output" = "{}" ]
}

@test "setup stages the manifest" {
  modules setup
  run git -C "$PARENT" diff --cached --name-only
  [[ "$output" == *"submodules/.manifest"* ]]
}

@test "setup is re-entrant" {
  modules setup
  run modules setup
  [ "$status" -eq 0 ]
  # Manifest should still exist and be valid
  [ -f "$PARENT/submodules/.manifest" ]
  # Hooks should still be installed
  [ -x "$PARENT/.git/hooks/pre-commit" ]
}

@test "setup fails outside a git repo" {
  export CALLER_PWD="$BATS_TEST_TMPDIR/not-a-repo"
  mkdir -p "$CALLER_PWD"
  run modules setup
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a git repository"* ]]
}
