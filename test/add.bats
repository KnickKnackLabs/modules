#!/usr/bin/env bats
# add.bats — test modules add task

bats_require_minimum_version 1.5.0

setup() {
  load test_helper

  REMOTE="$BATS_TEST_TMPDIR/remote"
  PARENT="$BATS_TEST_TMPDIR/parent"

  create_remote_repo "$REMOTE"
  create_parent_repo "$PARENT"
  export CALLER_PWD="$PARENT"

  # Initialize modules
  modules setup
  git -C "$PARENT" commit -m "init modules"
}

@test "add clones repo into hashed path" {
  run modules add "$REMOTE"
  [ "$status" -eq 0 ]

  # Should mention the module name (derived from dir name: "remote")
  [[ "$output" == *"Added module 'remote'"* ]]

  # Hashed directory should exist with repo contents
  local hash
  hash="$(hash_name "remote")"
  [ -d "$PARENT/submodules/$hash/.git" ]
  [ -f "$PARENT/submodules/$hash/README.md" ]
}

@test "add records entry in manifest" {
  modules add "$REMOTE"

  local manifest
  manifest="$(cat "$PARENT/submodules/.manifest")"

  # Should have a "remote" key with url, path, pin
  echo "$manifest" | jq -e '.remote.url' >/dev/null
  echo "$manifest" | jq -e '.remote.path' >/dev/null
  echo "$manifest" | jq -e '.remote.pin' >/dev/null

  # URL should match
  local url
  url="$(echo "$manifest" | jq -r '.remote.url')"
  [ "$url" = "$REMOTE" ]

  # Pin should match remote HEAD
  local pin expected
  pin="$(echo "$manifest" | jq -r '.remote.pin')"
  expected="$(repo_head "$REMOTE")"
  [ "$pin" = "$expected" ]
}

@test "add stages gitlink and manifest" {
  modules add "$REMOTE"

  local hash
  hash="$(hash_name "remote")"

  # Gitlink should be staged
  run gitlink_info "$PARENT" "submodules/$hash"
  [ "$status" -eq 0 ]
  [[ "$output" == 160000\ * ]]

  # Manifest should be staged
  run git -C "$PARENT" diff --cached --name-only
  [[ "$output" == *"submodules/.manifest"* ]]
}

@test "add with --name uses custom name" {
  run modules add "$REMOTE" --name my-dep
  [ "$status" -eq 0 ]
  [[ "$output" == *"Added module 'my-dep'"* ]]

  # Hashed under custom name
  local hash
  hash="$(hash_name "my-dep")"
  [ -d "$PARENT/submodules/$hash" ]

  # Manifest uses custom name
  run jq -r 'keys[0]' "$PARENT/submodules/.manifest"
  [ "$output" = "my-dep" ]
}

@test "add with --ref pins to specific commit" {
  # Get the first commit (not HEAD)
  local first_sha
  first_sha="$(git -C "$REMOTE" rev-list --max-parents=0 HEAD)"

  modules add "$REMOTE" --ref "$first_sha"

  local pin
  pin="$(jq -r '.remote.pin' "$PARENT/submodules/.manifest")"
  [ "$pin" = "$first_sha" ]

  # The clone should be at that commit
  local hash
  hash="$(hash_name "remote")"
  local head
  head="$(repo_head "$PARENT/submodules/$hash")"
  [ "$head" = "$first_sha" ]
}

@test "add fails if module name already exists" {
  modules add "$REMOTE"
  run modules add "$REMOTE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "add fails with invalid URL" {
  run modules add "file:///nonexistent/repo.git" --name bad-repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"clone"* || "$output" == *"fail"* || "$output" == *"fatal"* ]]
}

@test "add fails if not initialized" {
  local bare="$BATS_TEST_TMPDIR/bare"
  create_parent_repo "$bare"
  export CALLER_PWD="$bare"

  run modules add "$REMOTE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not initialized"* ]]
}

@test "add with dots in name" {
  run modules add "$REMOTE" --name "org.repo.git"
  [ "$status" -eq 0 ]

  run jq -r '.["org.repo.git"].url' "$PARENT/submodules/.manifest"
  [ "$output" = "$REMOTE" ]
}

@test "add multiple modules" {
  local remote2="$BATS_TEST_TMPDIR/remote2"
  create_remote_repo "$remote2"

  modules add "$REMOTE" --name first
  modules add "$remote2" --name second

  # Both in manifest
  run jq -r 'keys | length' "$PARENT/submodules/.manifest"
  [ "$output" = "2" ]

  # Both directories exist
  local hash1 hash2
  hash1="$(hash_name "first")"
  hash2="$(hash_name "second")"
  [ -d "$PARENT/submodules/$hash1" ]
  [ -d "$PARENT/submodules/$hash2" ]
}
