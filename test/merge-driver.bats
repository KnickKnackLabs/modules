#!/usr/bin/env bats
# merge-driver.bats — regression tests for the manifest merge driver.
#
# Simulates concurrent edits (the notes#48 bug class that motivated the
# redesign review) and asserts that the driver produces the right merge
# without corrupting the manifest.

bats_require_minimum_version 1.5.0

setup() {
  load test_helper

  PARENT="$BATS_TEST_TMPDIR/parent"
  REMOTE_A="$BATS_TEST_TMPDIR/remote_a"
  REMOTE_B="$BATS_TEST_TMPDIR/remote_b"

  create_remote_repo "$REMOTE_A"
  create_remote_repo "$REMOTE_B"
  create_parent_repo "$PARENT"
  export CALLER_PWD="$PARENT"

  modules setup
  git -C "$PARENT" commit -m "init modules"
}

# ── Union merge (no conflicts) ─────────────────────────────────

@test "merge: two concurrent adds → both entries present (no conflict)" {
  # Set up a "main" with no modules. Branch off two feature branches,
  # each adding a different module, then merge them back.

  git -C "$PARENT" checkout -q -b branch-a
  modules add "$REMOTE_A" --name alpha
  git -C "$PARENT" commit -q -m "add alpha"

  git -C "$PARENT" checkout -q main
  git -C "$PARENT" checkout -q -b branch-b
  modules add "$REMOTE_B" --name beta
  git -C "$PARENT" commit -q -m "add beta"

  # Merge branch-a into branch-b. The manifest should union to both entries.
  git -C "$PARENT" merge --no-edit branch-a
  run git -C "$PARENT" status --porcelain
  # No unmerged markers expected
  [[ "$output" != *"UU"* ]]
  [[ "$output" != *"AA"* ]]

  # Both modules in manifest
  manifest_has_name "$PARENT/.modules/manifest" "alpha"
  manifest_has_name "$PARENT/.modules/manifest" "beta"
  run manifest_count_of "$PARENT/.modules/manifest"
  [ "$output" = "2" ]
}

@test "merge: concurrent pin bumps on different modules → both updated" {
  # Seed with two modules on main.
  modules add "$REMOTE_A" --name alpha
  modules add "$REMOTE_B" --name beta
  git -C "$PARENT" commit -q -m "seed modules"

  # Push new commits upstream on both remotes so 'modules update' has work to do.
  echo "a1" > "$REMOTE_A/a.md" && git -C "$REMOTE_A" add a.md && git -C "$REMOTE_A" commit -qm "a bump"
  echo "b1" > "$REMOTE_B/b.md" && git -C "$REMOTE_B" add b.md && git -C "$REMOTE_B" commit -qm "b bump"

  # Branch A bumps alpha, branch B bumps beta.
  git -C "$PARENT" checkout -q -b branch-a
  modules update alpha
  git -C "$PARENT" commit -q -m "bump alpha"

  git -C "$PARENT" checkout -q main
  git -C "$PARENT" checkout -q -b branch-b
  modules update beta
  git -C "$PARENT" commit -q -m "bump beta"

  # Merge.
  git -C "$PARENT" merge --no-edit branch-a

  # Both should have the bumped pins.
  local alpha_pin beta_pin alpha_expected beta_expected
  alpha_pin="$(manifest_pin_of "$PARENT/.modules/manifest" "alpha")"
  beta_pin="$(manifest_pin_of "$PARENT/.modules/manifest" "beta")"
  alpha_expected="$(git -C "$REMOTE_A" rev-parse HEAD)"
  beta_expected="$(git -C "$REMOTE_B" rev-parse HEAD)"
  [ "$alpha_pin" = "$alpha_expected" ]
  [ "$beta_pin" = "$beta_expected" ]

  # No leftover conflict markers
  run grep -c "<<<<<<<" "$PARENT/.modules/manifest"
  [ "$output" = "0" ]
}

@test "merge: delete on one side + unchanged on other → deletion accepted" {
  modules add "$REMOTE_A" --name alpha
  modules add "$REMOTE_B" --name beta
  git -C "$PARENT" commit -q -m "seed"

  git -C "$PARENT" checkout -q -b branch-a
  modules remove beta
  git -C "$PARENT" commit -q -m "drop beta"

  git -C "$PARENT" checkout -q main
  git -C "$PARENT" checkout -q -b branch-b
  echo "unrelated" > "$PARENT/unrelated.txt"
  git -C "$PARENT" add unrelated.txt
  git -C "$PARENT" commit -q -m "unrelated change"

  git -C "$PARENT" merge --no-edit branch-a

  # beta should be gone; alpha still present.
  manifest_has_name "$PARENT/.modules/manifest" "alpha"
  run manifest_has_name "$PARENT/.modules/manifest" "beta"
  [ "$status" -ne 0 ]
}

# ── Conflicts ──────────────────────────────────────────────────

# Helper: set a specific pin for a module via a direct manifest edit.
# Simulates the outcome of 'modules update' without having to choreograph
# upstream repos — the merge driver doesn't care how the pin got there.
set_pin() {
  local name="$1" pin="$2"
  awk -F'\t' -v n="$name" -v p="$pin" \
    'BEGIN { OFS="\t" } $1 == n { $3 = p } 1' \
    "$PARENT/.modules/manifest" > "$PARENT/.modules/manifest.tmp"
  mv "$PARENT/.modules/manifest.tmp" "$PARENT/.modules/manifest"
}

@test "merge: concurrent bumps of the same module → true conflict" {
  modules add "$REMOTE_A" --name alpha
  git -C "$PARENT" add .modules/manifest
  git -C "$PARENT" commit -q -m "seed"

  # Fake two different pins — don't need them to correspond to real commits;
  # the merge driver operates on the manifest text, not the submodule state.
  local v1="1111111111111111111111111111111111111111"
  local v2="2222222222222222222222222222222222222222"

  git -C "$PARENT" checkout -q -b branch-a
  set_pin alpha "$v1"
  git -C "$PARENT" add .modules/manifest
  git -C "$PARENT" commit -q -m "pin alpha to v1"

  git -C "$PARENT" checkout -q main
  git -C "$PARENT" checkout -q -b branch-b
  set_pin alpha "$v2"
  git -C "$PARENT" add .modules/manifest
  git -C "$PARENT" commit -q -m "pin alpha to v2"

  # Merge — should conflict.
  run git -C "$PARENT" merge --no-edit branch-a
  [ "$status" -ne 0 ]

  # Conflict markers should be in the manifest.
  run grep -c "<<<<<<< ours" "$PARENT/.modules/manifest"
  [ "$output" = "1" ]
  run grep -c ">>>>>>> theirs" "$PARENT/.modules/manifest"
  [ "$output" = "1" ]
}

@test "merge: both sides add same name with different urls → conflict" {
  # Two branches off of an empty manifest each add 'shared' pointing to
  # different repos. That's a real conflict.
  git -C "$PARENT" checkout -q -b branch-a
  modules add "$REMOTE_A" --name shared
  git -C "$PARENT" commit -q -m "add shared=A"

  git -C "$PARENT" checkout -q main
  git -C "$PARENT" checkout -q -b branch-b
  # modules/ is gitignored — branch-a's clone is still on disk. Remove it
  # before re-adding on this branch.
  rm -rf "$PARENT/modules/shared"
  modules add "$REMOTE_B" --name shared
  git -C "$PARENT" commit -q -m "add shared=B"

  run git -C "$PARENT" merge --no-edit branch-a
  [ "$status" -ne 0 ]

  run grep -c "<<<<<<<" "$PARENT/.modules/manifest"
  [ "$output" = "1" ]
}

# ── Integrity: the driver never produces corrupt JSON-style output ───

@test "merge: result is always valid TSV (sorted, 3 columns per line)" {
  modules add "$REMOTE_A" --name alpha
  modules add "$REMOTE_B" --name beta
  git -C "$PARENT" commit -q -m "seed"

  git -C "$PARENT" checkout -q -b branch-a
  # Remove one, add another
  modules remove beta
  local REMOTE_C="$BATS_TEST_TMPDIR/remote_c"
  create_remote_repo "$REMOTE_C"
  modules add "$REMOTE_C" --name gamma
  git -C "$PARENT" commit -q -m "drop beta, add gamma"

  git -C "$PARENT" checkout -q main
  git -C "$PARENT" checkout -q -b branch-b
  echo "noop" > "$PARENT/noop.txt" && git -C "$PARENT" add noop.txt
  git -C "$PARENT" commit -q -m "noop"

  git -C "$PARENT" merge --no-edit branch-a

  # All lines should have exactly 3 tab-separated fields
  local bad
  bad="$(awk -F'\t' 'NF != 3' "$PARENT/.modules/manifest" || true)"
  [ -z "$bad" ]

  # Sorted by column 1
  local sorted
  sorted="$(sort -t$'\t' -k1,1 "$PARENT/.modules/manifest" | diff - "$PARENT/.modules/manifest" || true)"
  [ -z "$sorted" ]
}

# ── install-hooks task ─────────────────────────────────────────

@test "install-hooks registers merge driver in git config" {
  modules install-hooks

  run git -C "$PARENT" config --get merge.modules-manifest.driver
  [ "$status" -eq 0 ]
  [[ "$output" == *"manifest-merge-driver.sh"* ]]
}

@test "install-hooks adds merge attr to .gitattributes" {
  modules install-hooks

  run grep -F ".modules/manifest merge=modules-manifest" "$PARENT/.gitattributes"
  [ "$status" -eq 0 ]
}

@test "install-hooks is idempotent" {
  modules install-hooks
  modules install-hooks

  # Only one merge= entry in .gitattributes
  run grep -cF "merge=modules-manifest" "$PARENT/.gitattributes"
  [ "$output" = "1" ]
}

@test "setup installs merge driver by default" {
  # setup ran in the setup() function; driver should already be installed.
  run git -C "$PARENT" config --get merge.modules-manifest.driver
  [ "$status" -eq 0 ]
  [[ "$output" == *"manifest-merge-driver.sh"* ]]
}
