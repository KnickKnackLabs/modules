#!/usr/bin/env bats
# update.bats — test modules update task

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

@test "update pulls new commits and updates pin" {
  modules add "$REMOTE" --name my-repo
  git -C "$PARENT" commit -m "add module"

  local old_pin
  old_pin="$(jq -r '.["my-repo"].pin' "$PARENT/submodules/.manifest")"

  # Push a new commit to the remote
  echo "upstream change" > "$REMOTE/upstream.md"
  git -C "$REMOTE" add upstream.md
  git -C "$REMOTE" commit -m "upstream update"

  run modules update my-repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"updated"* ]]

  local new_pin
  new_pin="$(jq -r '.["my-repo"].pin' "$PARENT/submodules/.manifest")"
  [ "$old_pin" != "$new_pin" ]
}

@test "update reports already up to date" {
  modules add "$REMOTE" --name my-repo

  run modules update my-repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]
}

@test "update all modules when no name given" {
  local remote2="$BATS_TEST_TMPDIR/remote2"
  create_remote_repo "$remote2"

  modules add "$REMOTE" --name first
  modules add "$remote2" --name second
  git -C "$PARENT" commit -m "add modules"

  # Push changes to both remotes
  echo "change1" > "$REMOTE/change.md"
  git -C "$REMOTE" add change.md
  git -C "$REMOTE" commit -m "change 1"

  echo "change2" > "$remote2/change.md"
  git -C "$remote2" add change.md
  git -C "$remote2" commit -m "change 2"

  run modules update
  [ "$status" -eq 0 ]
  [[ "$output" == *"first"*"updated"* ]]
  [[ "$output" == *"second"*"updated"* ]]
}

@test "update works after init (detached HEAD)" {
  modules add "$REMOTE" --name my-repo
  git -C "$PARENT" commit -m "add module"

  local hash
  hash="$(hash_name "my-repo")"

  # Simulate fresh clone: remove the clone, re-init (which detaches HEAD)
  rm -rf "$PARENT/submodules/$hash"
  modules init

  # Push a new commit to the remote
  echo "new stuff" > "$REMOTE/new.md"
  git -C "$REMOTE" add new.md
  git -C "$REMOTE" commit -m "new commit"

  # Update should succeed despite detached HEAD from init
  run modules update my-repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"updated"* ]]
}

@test "update all reports failure when a module fails" {
  local remote2="$BATS_TEST_TMPDIR/remote2"
  create_remote_repo "$remote2"

  modules add "$REMOTE" --name first
  modules add "$remote2" --name second
  git -C "$PARENT" commit -m "add modules"

  # Break the first module's clone so pull fails
  local hash
  hash="$(hash_name "first")"
  rm -rf "$PARENT/submodules/$hash/.git"
  mkdir -p "$PARENT/submodules/$hash/.git"  # broken .git dir

  run modules update
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to update"* ]]
}

@test "update fails for unknown module" {
  run modules update nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
