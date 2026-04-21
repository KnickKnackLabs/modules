#!/usr/bin/env bats
# git-mechanics.bats — verify git behavior we rely on for modules
#
# With the opacity redesign, modules does NOT use gitlinks. Clones live under
# modules/ which is gitignored; only the encrypted manifest is tracked.
# These tests prove that underlying git mechanics make this work correctly.

bats_require_minimum_version 1.5.0

setup() {
  load test_helper

  REMOTE="$BATS_TEST_TMPDIR/remote"
  PARENT="$BATS_TEST_TMPDIR/parent"

  create_remote_repo "$REMOTE"
  create_parent_repo "$PARENT"
}

# ── Gitignored clones ─────────────────────────────────────────

@test "cloning into a gitignored modules/ dir does not touch the index" {
  echo 'modules/' > "$PARENT/.gitignore"
  git -C "$PARENT" add .gitignore
  git -C "$PARENT" commit -m "gitignore submodules"

  git clone "$REMOTE" "$PARENT/modules/myrepo"

  # Parent's index should NOT contain anything under modules/
  run git -C "$PARENT" ls-files modules/
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # No gitlinks anywhere
  run git -C "$PARENT" ls-files --stage
  [[ "$output" != *"160000"* ]]

  # git status clean
  run git -C "$PARENT" status --porcelain
  [ -z "$output" ]
}

@test "nested repo under gitignored dir operates normally" {
  echo 'modules/' > "$PARENT/.gitignore"
  git -C "$PARENT" add .gitignore
  git -C "$PARENT" commit -m "gitignore submodules"

  git clone "$REMOTE" "$PARENT/modules/myrepo"

  # The nested repo is fully functional
  run git -C "$PARENT/modules/myrepo" log --oneline
  [ "$status" -eq 0 ]
  [[ "$output" == *"add readme"* ]]

  # You can make commits in the nested repo without affecting the parent
  echo "new" > "$PARENT/modules/myrepo/new.md"
  git -C "$PARENT/modules/myrepo" add new.md
  git -C "$PARENT/modules/myrepo" commit -m "nested commit"

  run git -C "$PARENT" status --porcelain
  [ -z "$output" ]
}

# ── Fresh clone reproducibility ───────────────────────────────

@test "fresh clone has no modules/ content — init must populate" {
  echo 'modules/' > "$PARENT/.gitignore"
  git -C "$PARENT" add .gitignore
  git -C "$PARENT" commit -m "gitignore submodules"

  # Simulate a module being added locally
  git clone "$REMOTE" "$PARENT/modules/myrepo"

  # Fresh clone of the parent
  local fresh="$BATS_TEST_TMPDIR/fresh"
  git clone "$PARENT" "$fresh"

  # No modules/ in fresh clone (gitignored, not tracked)
  [ ! -d "$fresh/submodules" ]

  # No gitlinks in the tree
  run git -C "$fresh" ls-tree -r HEAD
  [[ "$output" != *"160000"* ]]
}

# ── No .gitmodules ────────────────────────────────────────────

@test "parent git status works without .gitmodules" {
  echo 'modules/' > "$PARENT/.gitignore"
  git -C "$PARENT" add .gitignore
  git -C "$PARENT" commit -m "gitignore submodules"

  git clone "$REMOTE" "$PARENT/modules/myrepo"

  # No .gitmodules exists
  [ ! -f "$PARENT/.gitmodules" ]

  run git -C "$PARENT" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to commit"* ]]
}
