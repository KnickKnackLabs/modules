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

@test "setup initializes rudi and assigns manifest encryption" {
  skip_unless_git_crypt

  modules setup

  [ -d "$PARENT/.git/git-crypt" ]
  run git -C "$PARENT" check-attr filter .modules/manifest
  [ "$status" -eq 0 ]
  [[ "$output" == *"git-crypt"* ]]
}

@test "setup --gpg-key adds collaborator" {
  skip_unless_git_crypt
  skip_unless_gpg_key

  modules setup --gpg-key "$TEST_GPG_FINGERPRINT"

  [ -f "$PARENT/.git-crypt/keys/default/0/$TEST_GPG_FINGERPRINT.gpg" ]
}

@test "setup handles repeated --gpg-key values separately" {
  skip_unless_git_crypt

  run modules setup --gpg-key NOPE1 --gpg-key NOPE2
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOPE1"* ]]
  [[ "$output" == *"NOPE2"* ]]
  [[ "$output" != *"NOPE1 NOPE2"* ]]
}

@test "setup warns when initializing without collaborators" {
  skip_unless_git_crypt

  run modules setup
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING: initialized git-crypt without any GPG collaborators"* ]]
  [[ "$output" == *"fresh clones cannot unlock"* ]]
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

# ── Layout version gate (RC-4 from peer review) ──

@test "setup writes layout version into .modules/config" {
  modules setup
  run jq -r '.version' "$PARENT/.modules/config"
  [ "$status" -eq 0 ]
  [ "$output" = "0.9.0" ]
}

@test "require_initialized detects pre-v0.9.0 layout" {
  # Simulate an old-layout repo: no .modules/, but submodules/.manifest
  # present. Any operation that requires initialization should point at
  # the migration guide rather than say 'not initialized'.
  mkdir -p "$PARENT/submodules"
  echo '{"some":"json"}' > "$PARENT/submodules/.manifest"

  run modules list
  [ "$status" -ne 0 ]
  [[ "$output" == *"pre-v0.9.0 modules layout"* ]]
  [[ "$output" == *"Migration guide"* ]]
}

@test "require_initialized rejects unknown layout version" {
  modules setup
  # Tamper with the version to simulate a future (or older) layout.
  local tmp
  tmp=$(mktemp)
  jq '.version = "99.0.0"' "$PARENT/.modules/config" > "$tmp"
  mv "$tmp" "$PARENT/.modules/config"

  run modules list
  [ "$status" -ne 0 ]
  [[ "$output" == *"layout version '99.0.0'"* ]]
  [[ "$output" == *"client supports '0.9.0'"* ]]
}
