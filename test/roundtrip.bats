#!/usr/bin/env bats
# roundtrip.bats — full integration: setup → add → lock → clone → unlock → init

bats_require_minimum_version 1.5.0

setup() {
  load test_helper
  skip_unless_git_crypt
  skip_unless_gpg_key

  REMOTE="$BATS_TEST_TMPDIR/remote"
  PARENT="$BATS_TEST_TMPDIR/parent"

  create_remote_repo "$REMOTE"
  create_parent_repo "$PARENT"
  export CALLER_PWD="$PARENT"
}

@test "roundtrip: setup auto-detects encryption and assigns manifest" {
  cd "$PARENT" && git-crypt init
  git-crypt add-gpg-user --trusted "$TEST_GPG_FINGERPRINT"

  export CALLER_PWD="$PARENT"
  run modules setup
  [ "$status" -eq 0 ]

  # .modules/manifest should be assigned for encryption
  run git -C "$PARENT" check-attr filter .modules/manifest
  [[ "$output" == *"git-crypt"* ]]
}

@test "roundtrip: manifest is encrypted after lock" {
  cd "$PARENT" && git-crypt init
  git-crypt add-gpg-user --trusted "$TEST_GPG_FINGERPRINT"

  export CALLER_PWD="$PARENT"
  modules setup
  git -C "$PARENT" commit -m "init modules"

  modules add "$REMOTE" --name my-repo
  git -C "$PARENT" commit -m "add module"

  cd "$PARENT" && git-crypt lock

  run file "$PARENT/.modules/manifest"
  [[ "$output" != *"JSON"* ]]
  [[ "$output" != *"ASCII"* ]]
}

@test "roundtrip: fresh clone → unlock → init restores modules" {
  cd "$PARENT" && git-crypt init
  git-crypt add-gpg-user --trusted "$TEST_GPG_FINGERPRINT"

  export CALLER_PWD="$PARENT"
  modules setup
  git -C "$PARENT" commit -m "init modules"

  modules add "$REMOTE" --name my-repo
  git -C "$PARENT" commit -m "add module"

  local pin
  pin="$(jq -r '.["my-repo"].pin' "$PARENT/.modules/manifest")"

  local clone="$BATS_TEST_TMPDIR/clone"
  git clone "$PARENT" "$clone"

  # Fresh clone has no modules/ dir — it's gitignored and not tracked
  [ ! -d "$clone/submodules" ] || [ -z "$(ls -A "$clone/submodules" 2>/dev/null)" ]

  cd "$clone" && git-crypt unlock

  export CALLER_PWD="$clone"
  modules init

  [ -d "$clone/modules/my-repo/.git" ]
  local actual
  actual="$(repo_head "$clone/modules/my-repo")"
  [ "$actual" = "$pin" ]
}

@test "roundtrip: locked clone reveals nothing about submodules" {
  cd "$PARENT" && git-crypt init
  git-crypt add-gpg-user --trusted "$TEST_GPG_FINGERPRINT"

  export CALLER_PWD="$PARENT"
  modules setup
  git -C "$PARENT" commit -m "init modules"

  modules add "$REMOTE" --name my-secret-dep
  git -C "$PARENT" commit -m "add module"

  # Lock the parent
  cd "$PARENT" && git-crypt lock

  # A locked observer sees nothing about what's in submodules
  run git -C "$PARENT" ls-tree -r HEAD
  [[ "$output" != *"160000"* ]]       # no gitlinks
  [[ "$output" != *"my-secret-dep"* ]] # name not in tree

  # The manifest is present but ciphertext
  run file "$PARENT/.modules/manifest"
  [[ "$output" != *"JSON"* ]]
}
