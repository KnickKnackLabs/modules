#!/usr/bin/env bats
# setup.bats — test modules setup task

bats_require_minimum_version 1.5.0

setup() {
  load test_helper

  PARENT="$BATS_TEST_TMPDIR/parent"
  create_parent_repo "$PARENT"
  export CALLER_PWD="$PARENT"
}

@test "setup creates manifest at .modules/manifest" {
  run modules setup
  [ "$status" -eq 0 ]
  [ -f "$PARENT/.modules/manifest" ]
  # Empty manifest = empty file (TSV format, no entries)
  [ ! -s "$PARENT/.modules/manifest" ]
}

@test "setup stages the manifest and gitignore" {
  modules setup
  run git -C "$PARENT" diff --cached --name-only
  [[ "$output" == *".modules/manifest"* ]]
  [[ "$output" == *".gitignore"* ]]
}

@test "setup adds modules/ to .gitignore" {
  modules setup
  run grep -xF 'modules/' "$PARENT/.gitignore"
  [ "$status" -eq 0 ]
}

@test "setup is idempotent on .gitignore" {
  # Pre-existing .gitignore with other content
  echo 'build/' > "$PARENT/.gitignore"
  modules setup
  modules setup
  # modules/ should appear exactly once
  run grep -cxF 'modules/' "$PARENT/.gitignore"
  [ "$output" = "1" ]
  # Pre-existing entry preserved
  run grep -xF 'build/' "$PARENT/.gitignore"
  [ "$status" -eq 0 ]
}

@test "setup is re-entrant" {
  modules setup
  run modules setup
  [ "$status" -eq 0 ]
  # Manifest should still exist and be valid
  [ -f "$PARENT/.modules/manifest" ]
  # Hooks should still be installed
  [ -x "$PARENT/.git/hooks/pre-commit" ]
}

@test "setup creates config with default path" {
  modules setup
  [ -f "$PARENT/.modules/config" ]
  run jq -r '.path' "$PARENT/.modules/config"
  [ "$output" = "modules" ]
}

@test "setup --path customizes the clone-root location" {
  modules setup --path deps
  run jq -r '.path' "$PARENT/.modules/config"
  [ "$output" = "deps" ]
  # .gitignore entry should track the custom path
  run grep -xF 'deps/' "$PARENT/.gitignore"
  [ "$status" -eq 0 ]
  # Default 'modules/' entry should NOT be present when --path is used
  run grep -xF 'modules/' "$PARENT/.gitignore"
  [ "$status" -ne 0 ]
}

@test "setup --path accepts nested paths" {
  modules setup --path third-party/vendored
  run jq -r '.path' "$PARENT/.modules/config"
  [ "$output" = "third-party/vendored" ]
  run grep -xF 'third-party/vendored/' "$PARENT/.gitignore"
  [ "$status" -eq 0 ]
}

@test "setup --path rejects absolute paths" {
  run modules setup --path /tmp/modules
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid --path"* ]]
}

@test "setup --path rejects parent-dir traversal" {
  run modules setup --path ../outside
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid --path"* ]]
}

@test "setup --path rejects dot-prefixed paths" {
  run modules setup --path .hidden
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid --path"* ]]
}

@test "setup fails if target path already exists and is non-empty" {
  mkdir -p "$PARENT/modules"
  echo "pre-existing" > "$PARENT/modules/unrelated.txt"
  run modules setup
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "setup succeeds if target path exists but is empty" {
  mkdir -p "$PARENT/modules"
  run modules setup
  [ "$status" -eq 0 ]
}

@test "add with custom --path places clone in the right location" {
  local REMOTE="$BATS_TEST_TMPDIR/remote"
  create_remote_repo "$REMOTE"

  modules setup --path deps
  git -C "$PARENT" commit -m "init"

  modules add "$REMOTE" --name my-repo
  [ -d "$PARENT/deps/my-repo/.git" ]
  [ ! -d "$PARENT/modules" ]  # default path never created
}

@test "setup fails outside a git repo" {
  export CALLER_PWD="$BATS_TEST_TMPDIR/not-a-repo"
  mkdir -p "$CALLER_PWD"
  run modules setup
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a git repository"* ]]
}
