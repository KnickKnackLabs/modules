#!/usr/bin/env bats
# git-mechanics.bats — verify git behavior we rely on for modules
#
# Modules manages nested git repos WITHOUT .gitmodules. These tests prove
# the underlying git mechanics work: gitlinks, pin tracking, fresh clones,
# and obfuscated paths.

bats_require_minimum_version 1.5.0

setup() {
  load test_helper

  REMOTE="$BATS_TEST_TMPDIR/remote"
  PARENT="$BATS_TEST_TMPDIR/parent"

  create_remote_repo "$REMOTE"
  create_parent_repo "$PARENT"
}

# ── Gitlink creation ──────────────────────────────────────────

@test "git clone inside a repo creates a mode 160000 gitlink" {
  git clone "$REMOTE" "$PARENT/submodules/myrepo"
  git -C "$PARENT" add submodules/myrepo

  run gitlink_info "$PARENT" submodules/myrepo
  [ "$status" -eq 0 ]
  [[ "$output" == 160000\ * ]]
}

@test "git add on nested repo does not track inner files" {
  git clone "$REMOTE" "$PARENT/submodules/myrepo"
  git -C "$PARENT" add submodules/myrepo

  # Parent should have exactly one index entry for the path — the gitlink.
  # It should NOT have entries like submodules/myrepo/README.md.
  run git -C "$PARENT" ls-files --stage submodules/
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l)" -eq 1 ]
  [[ "$output" == *"submodules/myrepo"* ]]
}

# ── No .gitmodules required ──────────────────────────────────

@test "parent git status works without .gitmodules" {
  git clone "$REMOTE" "$PARENT/submodules/myrepo"
  git -C "$PARENT" add submodules/myrepo
  git -C "$PARENT" commit -m "add nested repo"

  # No .gitmodules exists
  [ ! -f "$PARENT/.gitmodules" ]

  # git status should work fine
  run git -C "$PARENT" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to commit"* ]]
}

@test "parent git log works without .gitmodules" {
  git clone "$REMOTE" "$PARENT/submodules/myrepo"
  git -C "$PARENT" add submodules/myrepo
  git -C "$PARENT" commit -m "add nested repo"

  run git -C "$PARENT" log --oneline
  [ "$status" -eq 0 ]
  [[ "$output" == *"add nested repo"* ]]
}

# ── SHA pinning ───────────────────────────────────────────────

@test "gitlink captures the cloned repo's HEAD SHA" {
  local remote_sha
  remote_sha="$(repo_head "$REMOTE")"

  git clone "$REMOTE" "$PARENT/submodules/myrepo"
  git -C "$PARENT" add submodules/myrepo

  run gitlink_info "$PARENT" submodules/myrepo
  [ "$status" -eq 0 ]
  [[ "$output" == *"$remote_sha"* ]]
}

@test "git add after new commits updates the pinned SHA" {
  git clone "$REMOTE" "$PARENT/submodules/myrepo"
  git -C "$PARENT" add submodules/myrepo
  git -C "$PARENT" commit -m "add nested repo"

  local old_sha
  old_sha="$(repo_head "$PARENT/submodules/myrepo")"

  # Make a new commit in the nested clone
  echo "new content" > "$PARENT/submodules/myrepo/new.md"
  git -C "$PARENT/submodules/myrepo" add new.md
  git -C "$PARENT/submodules/myrepo" commit -m "add new file"

  local new_sha
  new_sha="$(repo_head "$PARENT/submodules/myrepo")"
  [ "$old_sha" != "$new_sha" ]

  # Parent should detect the change
  run git -C "$PARENT" status --porcelain
  [[ "$output" == *"submodules/myrepo"* ]]

  # Re-add to update the pin
  git -C "$PARENT" add submodules/myrepo
  run gitlink_info "$PARENT" submodules/myrepo
  [[ "$output" == *"$new_sha"* ]]
}

@test "pulling upstream changes into nested repo updates pin" {
  git clone "$REMOTE" "$PARENT/submodules/myrepo"
  git -C "$PARENT" add submodules/myrepo
  git -C "$PARENT" commit -m "add nested repo"

  local old_sha
  old_sha="$(repo_head "$PARENT/submodules/myrepo")"

  # Push a new commit to the "remote"
  echo "upstream change" > "$REMOTE/upstream.md"
  git -C "$REMOTE" add upstream.md
  git -C "$REMOTE" commit -m "upstream update"

  # Pull in the nested clone
  git -C "$PARENT/submodules/myrepo" pull origin main

  local new_sha
  new_sha="$(repo_head "$PARENT/submodules/myrepo")"
  [ "$old_sha" != "$new_sha" ]

  # Parent sees the updated pin
  git -C "$PARENT" add submodules/myrepo
  run gitlink_info "$PARENT" submodules/myrepo
  [[ "$output" == *"$new_sha"* ]]
}

# ── Fresh clone behavior ─────────────────────────────────────

@test "fresh clone of parent has empty gitlink paths" {
  git clone "$REMOTE" "$PARENT/submodules/myrepo"
  git -C "$PARENT" add submodules/myrepo
  git -C "$PARENT" commit -m "add nested repo"

  # Clone the parent to a new location
  local fresh="$BATS_TEST_TMPDIR/fresh"
  git clone "$PARENT" "$fresh"

  # The gitlink entry exists in the tree
  run git -C "$fresh" ls-tree HEAD submodules/
  [ "$status" -eq 0 ]
  [[ "$output" == *"160000"* ]]

  # But the directory is empty — git can't populate it without .gitmodules
  [ ! -d "$fresh/submodules/myrepo/.git" ]
  # The directory might not even exist
  if [ -d "$fresh/submodules/myrepo" ]; then
    run ls "$fresh/submodules/myrepo/"
    [ -z "$output" ]
  fi
}

@test "git submodule commands fail gracefully without .gitmodules" {
  git clone "$REMOTE" "$PARENT/submodules/myrepo"
  git -C "$PARENT" add submodules/myrepo
  git -C "$PARENT" commit -m "add nested repo"

  local fresh="$BATS_TEST_TMPDIR/fresh"
  git clone "$PARENT" "$fresh"

  # git submodule init should fail (no .gitmodules to read)
  run git -C "$fresh" submodule init
  [ "$status" -ne 0 ] || [ -z "$output" ]
}

@test "manually cloning into empty gitlink path restores it" {
  git clone "$REMOTE" "$PARENT/submodules/myrepo"
  git -C "$PARENT" add submodules/myrepo
  git -C "$PARENT" commit -m "add nested repo"

  local pinned_sha
  pinned_sha="$(gitlink_info "$PARENT" submodules/myrepo | awk '{print $2}')"

  # Clone parent fresh
  local fresh="$BATS_TEST_TMPDIR/fresh"
  git clone "$PARENT" "$fresh"

  # Manually clone the remote into the expected path
  git clone "$REMOTE" "$fresh/submodules/myrepo"

  # Check out the pinned SHA
  git -C "$fresh/submodules/myrepo" checkout "$pinned_sha"

  # Parent should see a clean state (nested repo at the pinned commit)
  run git -C "$fresh" status --porcelain
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── Obfuscated paths ─────────────────────────────────────────

@test "obfuscated directory names work identically to plain names" {
  local hash
  hash="$(hash_name "rudi")"

  git clone "$REMOTE" "$PARENT/submodules/$hash"
  git -C "$PARENT" add "submodules/$hash"

  run gitlink_info "$PARENT" "submodules/$hash"
  [ "$status" -eq 0 ]
  [[ "$output" == 160000\ * ]]

  # The nested repo is fully functional
  run git -C "$PARENT/submodules/$hash" log --oneline -1
  [ "$status" -eq 0 ]
  [[ "$output" == *"add readme"* ]]
}

@test "multiple obfuscated submodules coexist" {
  # Create a second remote
  local remote2="$BATS_TEST_TMPDIR/remote2"
  create_remote_repo "$remote2"
  echo "second repo" > "$remote2/SECOND.md"
  git -C "$remote2" add SECOND.md
  git -C "$remote2" commit -m "second repo marker"

  local hash1 hash2
  hash1="$(hash_name "repo-one")"
  hash2="$(hash_name "repo-two")"

  git clone "$REMOTE" "$PARENT/submodules/$hash1"
  git clone "$remote2" "$PARENT/submodules/$hash2"
  git -C "$PARENT" add "submodules/$hash1" "submodules/$hash2"
  git -C "$PARENT" commit -m "add two modules"

  # Both gitlinks exist
  run git -C "$PARENT" ls-tree HEAD submodules/
  [ "$(echo "$output" | wc -l)" -eq 2 ]

  # Each points to the correct repo
  [ -f "$PARENT/submodules/$hash1/README.md" ]
  [ -f "$PARENT/submodules/$hash2/SECOND.md" ]
}

# ── Encrypted manifest coexistence ────────────────────────────

@test "a regular file alongside gitlinks is tracked normally" {
  git clone "$REMOTE" "$PARENT/submodules/myrepo"
  git -C "$PARENT" add submodules/myrepo

  # Create a manifest file in the same directory
  echo '{"myrepo": {"url": "https://example.com/repo.git"}}' > "$PARENT/submodules/.manifest"
  git -C "$PARENT" add submodules/.manifest
  git -C "$PARENT" commit -m "add module and manifest"

  # Tree should have both: a gitlink and a regular file
  run git -C "$PARENT" ls-tree HEAD submodules/
  [ "$status" -eq 0 ]
  [[ "$output" == *"160000"*"submodules/myrepo"* ]]
  [[ "$output" == *"100644"*"submodules/.manifest"* ]]
}

@test "manifest can be encrypted while gitlinks remain functional" {
  skip_unless_git_crypt

  git clone "$REMOTE" "$PARENT/submodules/myrepo"
  git -C "$PARENT" add submodules/myrepo

  # Set up git-crypt and encrypt only the manifest
  git -C "$PARENT" crypt init
  echo "submodules/.manifest filter=git-crypt diff=git-crypt" > "$PARENT/.gitattributes"
  git -C "$PARENT" add .gitattributes

  echo '{"myrepo": {"url": "https://example.com/repo.git"}}' > "$PARENT/submodules/.manifest"
  git -C "$PARENT" add submodules/.manifest
  git -C "$PARENT" commit -m "add encrypted manifest and module"

  # Export key for lock/unlock
  local key="$BATS_TEST_TMPDIR/gckey"
  git -C "$PARENT" crypt export-key "$key"

  # Lock — manifest should be encrypted, gitlink should still work
  git -C "$PARENT" crypt lock

  run git -C "$PARENT" status
  [ "$status" -eq 0 ]

  run file "$PARENT/submodules/.manifest"
  [[ "$output" == *"data"* ]]  # encrypted = binary data

  # Nested repo still works
  run git -C "$PARENT/submodules/myrepo" log --oneline -1
  [ "$status" -eq 0 ]

  # Unlock restores the manifest
  git -C "$PARENT" crypt unlock "$key"
  run cat "$PARENT/submodules/.manifest"
  [[ "$output" == *"example.com"* ]]
}
