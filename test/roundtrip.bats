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

# Helper: init rudi in the parent repo, then run modules setup
setup_with_encryption() {
  cd "$MISE_CONFIG_ROOT" && CALLER_PWD="$PARENT" mise run -q rudi:init --user "$TEST_GPG_FINGERPRINT" --no-user 2>/dev/null || \
    CALLER_PWD="$PARENT" rudi init --user "$TEST_GPG_FINGERPRINT" 2>/dev/null || true
  # If rudi isn't available as a mise task, use git-crypt directly
  if [ ! -d "$PARENT/.git/git-crypt" ]; then
    cd "$PARENT" && git-crypt init
    git-crypt add-gpg-user --trusted "$TEST_GPG_FINGERPRINT"
  fi
  export CALLER_PWD="$PARENT"
  modules setup
}

@test "roundtrip: setup auto-detects encryption and assigns manifest" {
  # Init encryption first via rudi/git-crypt
  cd "$PARENT" && git-crypt init
  git-crypt add-gpg-user --trusted "$TEST_GPG_FINGERPRINT"

  export CALLER_PWD="$PARENT"
  run modules setup
  [ "$status" -eq 0 ]

  # .manifest should be assigned for encryption
  run git -C "$PARENT" check-attr filter submodules/.manifest
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

  run file "$PARENT/submodules/.manifest"
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

  local hash pin
  hash="$(hash_name "my-repo")"
  pin="$(jq -r '.["my-repo"].pin' "$PARENT/submodules/.manifest")"

  local clone="$BATS_TEST_TMPDIR/clone"
  git clone "$PARENT" "$clone"

  [ ! -d "$clone/submodules/$hash/.git" ]

  cd "$clone" && git-crypt unlock

  export CALLER_PWD="$clone"
  modules init

  [ -d "$clone/submodules/$hash/.git" ]
  local actual
  actual="$(repo_head "$clone/submodules/$hash")"
  [ "$actual" = "$pin" ]
}
