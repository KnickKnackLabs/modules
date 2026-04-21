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

  run modules remove my-repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed"* ]]

  # Clone should be gone
  [ ! -d "$PARENT/modules/my-repo" ]

  # Manifest should be empty
  run manifest_count_of "$PARENT/.modules/manifest"
  [ "$output" = "0" ]
}

@test "remove touches only the manifest (no gitlink cleanup needed)" {
  modules add "$REMOTE" --name my-repo
  git -C "$PARENT" commit -m "add module"

  modules remove my-repo

  # Nothing under modules/ is ever tracked — confirm no orphan index entries
  run git -C "$PARENT" ls-files modules/
  [ -z "$output" ]

  # Manifest change should be staged
  run git -C "$PARENT" diff --cached --name-only
  [[ "$output" == *".modules/manifest"* ]]
}

@test "remove fails for unknown module" {
  run modules remove nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "remove works when module was never cloned" {
  modules add "$REMOTE" --name my-repo
  git -C "$PARENT" commit -m "add module"

  # Simulate fresh clone: remove the clone but keep the manifest entry
  rm -rf "$PARENT/modules/my-repo"

  run modules remove my-repo
  [ "$status" -eq 0 ]

  # Manifest should be empty
  run manifest_count_of "$PARENT/.modules/manifest"
  [ "$output" = "0" ]
}

@test "remove one of multiple modules leaves others intact" {
  local remote2="$BATS_TEST_TMPDIR/remote2"
  create_remote_repo "$remote2"

  modules add "$REMOTE" --name first
  modules add "$remote2" --name second
  git -C "$PARENT" commit -m "add modules"

  modules remove first

  # Second should still exist
  [ -d "$PARENT/modules/second" ]
  manifest_has_name "$PARENT/.modules/manifest" "second"
  run manifest_count_of "$PARENT/.modules/manifest"
  [ "$output" = "1" ]
}
