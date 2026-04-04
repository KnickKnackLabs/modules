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

# Helper: run rudi in the parent repo context
rudi_in_parent() {
  cd "$MISE_CONFIG_ROOT" && CALLER_PWD="$PARENT" mise run -q "$@"
}

@test "roundtrip: setup with --gpg-key initializes encryption" {
  run modules setup --gpg-key "$TEST_GPG_FINGERPRINT"
  [ "$status" -eq 0 ]

  # git-crypt should be initialized
  [ -d "$PARENT/.git/git-crypt" ]

  # .manifest should be assigned for encryption
  run git -C "$PARENT" check-attr filter submodules/.manifest
  [[ "$output" == *"git-crypt"* ]]
}

@test "roundtrip: manifest is encrypted after lock" {
  modules setup --gpg-key "$TEST_GPG_FINGERPRINT"
  git -C "$PARENT" commit -m "init modules"

  modules add "$REMOTE" --name my-repo
  git -C "$PARENT" commit -m "add module"

  # Lock — rudi needs to run in the parent repo
  cd "$PARENT" && git-crypt lock

  # Manifest should be binary (encrypted)
  run file "$PARENT/submodules/.manifest"
  [[ "$output" != *"JSON"* ]]
  [[ "$output" != *"ASCII"* ]]
}

@test "roundtrip: fresh clone → unlock → init restores modules" {
  modules setup --gpg-key "$TEST_GPG_FINGERPRINT"
  git -C "$PARENT" commit -m "init modules"

  modules add "$REMOTE" --name my-repo
  git -C "$PARENT" commit -m "add module"

  local hash pin
  hash="$(hash_name "my-repo")"
  pin="$(jq -r '.["my-repo"].pin' "$PARENT/submodules/.manifest")"

  # Clone the parent (simulates fresh checkout)
  local clone="$BATS_TEST_TMPDIR/clone"
  git clone "$PARENT" "$clone"

  # Submodule dir should be empty after clone
  [ ! -d "$clone/submodules/$hash/.git" ]

  # Unlock
  cd "$clone" && git-crypt unlock

  # Init should restore the module
  export CALLER_PWD="$clone"
  modules init

  [ -d "$clone/submodules/$hash/.git" ]
  local actual
  actual="$(repo_head "$clone/submodules/$hash")"
  [ "$actual" = "$pin" ]
}
