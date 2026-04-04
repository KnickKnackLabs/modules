#!/usr/bin/env bats
# init.bats — test modules init task

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

@test "init with no modules prints message" {
  run modules init
  [ "$status" -eq 0 ]
  [[ "$output" == *"No modules"* ]]
}

@test "init clones modules from manifest into correct paths" {
  modules add "$REMOTE" --name my-repo
  git -C "$PARENT" commit -m "add module"

  local hash
  hash="$(hash_name "my-repo")"

  # Simulate fresh clone: remove the clone but keep the manifest and gitlink
  rm -rf "$PARENT/submodules/$hash"

  run modules init
  [ "$status" -eq 0 ]
  [[ "$output" == *"my-repo"* ]]

  # Clone should be restored
  [ -d "$PARENT/submodules/$hash/.git" ]
  [ -f "$PARENT/submodules/$hash/README.md" ]
}

@test "init checks out the pinned SHA" {
  modules add "$REMOTE" --name my-repo
  git -C "$PARENT" commit -m "add module"

  local hash pin
  hash="$(hash_name "my-repo")"
  pin="$(jq -r '.["my-repo"].pin' "$PARENT/submodules/.manifest")"

  # Remove clone
  rm -rf "$PARENT/submodules/$hash"

  modules init

  # Should be at pinned commit
  local actual
  actual="$(repo_head "$PARENT/submodules/$hash")"
  [ "$actual" = "$pin" ]
}

@test "init skips already-cloned modules" {
  modules add "$REMOTE" --name my-repo

  run modules init
  [ "$status" -eq 0 ]
  [[ "$output" == *"already cloned"* ]]
}

@test "init reports failure when clone fails" {
  # Add a module with a bogus URL directly in the manifest
  local hash
  hash="$(hash_name "bad-repo")"
  local manifest
  manifest="$(cat "$PARENT/submodules/.manifest")"
  echo "$manifest" | jq --arg h "submodules/$hash" \
    '. + {"bad-repo": {"url": "file:///nonexistent/repo.git", "path": $h, "pin": "0000000000000000000000000000000000000000"}}' \
    > "$PARENT/submodules/.manifest"

  run modules init
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed"* ]]
}

@test "init handles multiple modules" {
  local remote2="$BATS_TEST_TMPDIR/remote2"
  create_remote_repo "$remote2"

  modules add "$REMOTE" --name first
  modules add "$remote2" --name second
  git -C "$PARENT" commit -m "add modules"

  local hash1 hash2
  hash1="$(hash_name "first")"
  hash2="$(hash_name "second")"

  # Remove both clones
  rm -rf "$PARENT/submodules/$hash1" "$PARENT/submodules/$hash2"

  run modules init
  [ "$status" -eq 0 ]
  [ -d "$PARENT/submodules/$hash1/.git" ]
  [ -d "$PARENT/submodules/$hash2/.git" ]
}
