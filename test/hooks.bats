#!/usr/bin/env bats
# hooks.bats — test pre-commit leak prevention hooks

bats_require_minimum_version 1.5.0

setup() {
  load test_helper

  PARENT="$BATS_TEST_TMPDIR/parent"
  REMOTE="$BATS_TEST_TMPDIR/remote"

  create_remote_repo "$REMOTE"
  create_parent_repo "$PARENT"
  export CALLER_PWD="$PARENT"

  modules setup
  git -C "$PARENT" commit -m "init modules"
}

# ── Dispatcher ─────────────────────────────────────────────────

@test "setup installs pre-commit dispatcher" {
  [ -x "$PARENT/.git/hooks/pre-commit" ]
}

@test "setup installs all three hooks" {
  [ -x "$PARENT/.git/hooks/pre-commit.d/manifest-encryption" ]
  [ -x "$PARENT/.git/hooks/pre-commit.d/path-obfuscation" ]
  [ -x "$PARENT/.git/hooks/pre-commit.d/gitmodules-guard" ]
}

@test "dispatcher runs hooks in pre-commit.d" {
  # Add a test hook that creates a marker file
  cat > "$PARENT/.git/hooks/pre-commit.d/test-hook" <<'EOF'
#!/usr/bin/env bash
touch "$GIT_DIR/../.hook-ran"
EOF
  chmod +x "$PARENT/.git/hooks/pre-commit.d/test-hook"

  echo "test" > "$PARENT/testfile"
  git -C "$PARENT" add testfile
  git -C "$PARENT" commit -m "test commit"

  [ -f "$PARENT/.hook-ran" ]
}

@test "dispatcher aborts commit on hook failure" {
  cat > "$PARENT/.git/hooks/pre-commit.d/always-fail" <<'EOF'
#!/usr/bin/env bash
echo "blocked" >&2
exit 1
EOF
  chmod +x "$PARENT/.git/hooks/pre-commit.d/always-fail"

  echo "test" > "$PARENT/testfile"
  git -C "$PARENT" add testfile
  run git -C "$PARENT" commit -m "should fail"
  [ "$status" -ne 0 ]
}

# ── gitmodules guard ───────────────────────────────────────────

@test "gitmodules guard rejects .gitmodules" {
  echo '[submodule "foo"]' > "$PARENT/.gitmodules"
  git -C "$PARENT" add .gitmodules

  run git -C "$PARENT" commit -m "add gitmodules"
  [ "$status" -ne 0 ]
  [[ "$output" == *".gitmodules"* ]]
}

@test "gitmodules guard allows normal commits" {
  echo "hello" > "$PARENT/normal-file.txt"
  git -C "$PARENT" add normal-file.txt

  run git -C "$PARENT" commit -m "normal commit"
  [ "$status" -eq 0 ]
}

# ── Path obfuscation guard ─────────────────────────────────────

@test "path obfuscation rejects non-hashed dirs under submodules/" {
  # Create a clearly-named submodule dir (not a 12-char hex hash)
  mkdir -p "$PARENT/submodules/my-secret-repo"
  echo "leaked" > "$PARENT/submodules/my-secret-repo/file.txt"
  git -C "$PARENT" add submodules/my-secret-repo/

  run git -C "$PARENT" commit -m "add leaky path"
  [ "$status" -ne 0 ]
  [[ "$output" == *"obfuscat"* ]]
}

@test "path obfuscation allows hashed dirs under submodules/" {
  modules add "$REMOTE" --name my-repo

  run git -C "$PARENT" commit -m "add module"
  [ "$status" -eq 0 ]
}

@test "path obfuscation allows .manifest" {
  # .manifest is always under submodules/ — should not be flagged
  # Just modify the manifest and commit
  echo '{}' > "$PARENT/submodules/.manifest"
  git -C "$PARENT" add submodules/.manifest

  run git -C "$PARENT" commit -m "update manifest"
  [ "$status" -eq 0 ]
}

# ── Manifest encryption guard ──────────────────────────────────

@test "manifest encryption hook warns without git-crypt" {
  # In test repos, git-crypt isn't initialized — hook should warn but pass
  echo '{"test": {}}' > "$PARENT/submodules/.manifest"
  git -C "$PARENT" add submodules/.manifest

  run git -C "$PARENT" commit -m "update manifest"
  [ "$status" -eq 0 ]
}
