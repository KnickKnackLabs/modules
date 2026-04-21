#!/usr/bin/env bash
# manifest-merge-driver.sh — custom git merge driver for .modules/manifest
#
# Git calls this with: %O %A %B (ancestor, ours, theirs).
# Writes the merged result to %A. Exit 0 on success, non-zero on conflict.
#
# Manifest format: <name>\t<url>\t<pin>, one per line, sorted by name.
#
# Strategy: union merge keyed on name.
# - Same name, same url+pin on both sides → take it.
# - Same name, one side unchanged from ancestor, other side updated → take the update.
# - Same name, both sides changed values differently → CONFLICT.
# - Name present in ancestor but deleted on one side and unchanged on the
#   other → accept the deletion.
# - Name present in ancestor, deleted on one side, modified on the other →
#   CONFLICT (hard to know intent).
# - Name new on one side only → include it.
# - Name new on both sides with same value → include it.
# - Name new on both sides with different values → CONFLICT.
#
# Adapted from KnickKnackLabs/notes' manifest-merge-driver.sh. Schema
# differs (3 cols vs 2), key is col 1 (name) not col 2 (name).
#
# Bash 3.2 compatible.
set -eo pipefail

ANCESTOR="$1"  # %O — common ancestor
OURS="$2"      # %A — current branch (merge result goes here)
THEIRS="$3"    # %B — branch being merged

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Git invokes merge drivers with index content. For git-crypt-tracked files,
# that content is the encrypted ciphertext (starts with "\0GITCRYPT\0"). We
# need plaintext to merge. If the file is encrypted, decrypt via git-crypt's
# smudge filter. If smudge fails (repo locked, git-crypt missing), abort —
# producing a corrupt merged manifest silently would be much worse than
# leaving git to raise a conflict.
decrypt_if_needed() {
  local src="$1" dst="$2"
  if [ ! -s "$src" ]; then
    : > "$dst"
    return 0
  fi
  # git-crypt files begin with \0 G I T C R Y P T \0 (10 bytes).
  # Bash strings can't carry a leading \0 — read bytes 2-9 and check for "GITCRYPT".
  local header
  header=$(dd if="$src" bs=1 skip=1 count=8 2>/dev/null)
  if [ "$header" = "GITCRYPT" ]; then
    if ! git-crypt smudge < "$src" > "$dst" 2>/dev/null; then
      echo "modules manifest-merge-driver: git-crypt smudge failed on $src — is the repo unlocked?" >&2
      echo "modules manifest-merge-driver: aborting merge to avoid producing a corrupt manifest." >&2
      return 1
    fi
  else
    cp "$src" "$dst"
  fi
}

# Normalize: decrypt if encrypted, strip blank lines, sort by name.
normalize() {
  local src="$1" plaintext
  plaintext=$(mktemp "$WORK/plain.XXXXXX")
  decrypt_if_needed "$src" "$plaintext" || return 1
  awk 'NF' "$plaintext" | sort -t$'\t' -k1,1 || true
}

normalize "$ANCESTOR" > "$WORK/anc"
normalize "$OURS"     > "$WORK/ours"
normalize "$THEIRS"   > "$WORK/theirs"

# Look up the entry line for a name in a file. Prints "<url>\t<pin>" (cols 2-3)
# or nothing. Uses read-loop instead of grep for filename-safety.
value_for_name() {
  local file="$1" name="$2"
  [ ! -f "$file" ] && return 0
  local line n rest
  while IFS= read -r line; do
    n="${line%%$'\t'*}"
    if [ "$n" = "$name" ]; then
      # Everything after the first tab
      rest="${line#*$'\t'}"
      printf '%s' "$rest"
      return
    fi
  done < "$file"
}

name_exists_in() {
  local file="$1" name="$2"
  [ ! -f "$file" ] && return 1
  local line n
  while IFS= read -r line; do
    n="${line%%$'\t'*}"
    if [ "$n" = "$name" ]; then
      return 0
    fi
  done < "$file"
  return 1
}

# Collect all unique names from all three files.
{
  cut -f1 "$WORK/anc"    2>/dev/null
  cut -f1 "$WORK/ours"   2>/dev/null
  cut -f1 "$WORK/theirs" 2>/dev/null
} | sort -u > "$WORK/all_names"

has_conflict=false
: > "$WORK/merged"
: > "$WORK/conflicts"

while IFS= read -r name; do
  [ -z "$name" ] && continue

  a_val=""; o_val=""; t_val=""
  if name_exists_in "$WORK/anc"    "$name"; then a_val="$(value_for_name "$WORK/anc"    "$name")"; a_set=1; else a_set=0; fi
  if name_exists_in "$WORK/ours"   "$name"; then o_val="$(value_for_name "$WORK/ours"   "$name")"; o_set=1; else o_set=0; fi
  if name_exists_in "$WORK/theirs" "$name"; then t_val="$(value_for_name "$WORK/theirs" "$name")"; t_set=1; else t_set=0; fi

  if [ "$o_set" = 1 ] && [ "$t_set" = 1 ]; then
    # Present in both. Decide which value to take.
    if [ "$o_val" = "$t_val" ]; then
      printf '%s\t%s\n' "$name" "$o_val" >> "$WORK/merged"
    elif [ "$a_set" = 0 ]; then
      # Both added independently with different values — true conflict.
      has_conflict=true
      {
        echo "<<<<<<< ours"
        printf '%s\t%s\n' "$name" "$o_val"
        echo "======="
        printf '%s\t%s\n' "$name" "$t_val"
        echo ">>>>>>> theirs"
      } >> "$WORK/conflicts"
    elif [ "$o_val" = "$a_val" ]; then
      # Ours unchanged, theirs updated — take theirs.
      printf '%s\t%s\n' "$name" "$t_val" >> "$WORK/merged"
    elif [ "$t_val" = "$a_val" ]; then
      # Theirs unchanged, ours updated — take ours.
      printf '%s\t%s\n' "$name" "$o_val" >> "$WORK/merged"
    else
      # Both changed from ancestor in different ways — conflict.
      has_conflict=true
      {
        echo "<<<<<<< ours"
        printf '%s\t%s\n' "$name" "$o_val"
        echo "======="
        printf '%s\t%s\n' "$name" "$t_val"
        echo ">>>>>>> theirs"
      } >> "$WORK/conflicts"
    fi
  elif [ "$o_set" = 1 ] && [ "$t_set" = 0 ]; then
    if [ "$a_set" = 1 ]; then
      # Theirs deleted it. If ours also still matches ancestor → accept deletion.
      # If ours diverged from ancestor → conflict (modify vs delete).
      if [ "$o_val" = "$a_val" ]; then
        : # accept deletion
      else
        has_conflict=true
        {
          echo "<<<<<<< ours (modified)"
          printf '%s\t%s\n' "$name" "$o_val"
          echo "======="
          echo "(deleted in theirs)"
          echo ">>>>>>> theirs"
        } >> "$WORK/conflicts"
      fi
    else
      # Only in ours, new — keep it.
      printf '%s\t%s\n' "$name" "$o_val" >> "$WORK/merged"
    fi
  elif [ "$o_set" = 0 ] && [ "$t_set" = 1 ]; then
    if [ "$a_set" = 1 ]; then
      if [ "$t_val" = "$a_val" ]; then
        : # accept deletion by ours
      else
        has_conflict=true
        {
          echo "<<<<<<< ours"
          echo "(deleted in ours)"
          echo "======="
          printf '%s\t%s\n' "$name" "$t_val"
          echo ">>>>>>> theirs (modified)"
        } >> "$WORK/conflicts"
      fi
    else
      # Only in theirs, new — keep it.
      printf '%s\t%s\n' "$name" "$t_val" >> "$WORK/merged"
    fi
  fi
  # If neither set: nothing to do (shouldn't happen since name came from union).
done < "$WORK/all_names"

# Write sorted merged result to OURS
sort -t$'\t' -k1,1 "$WORK/merged" > "$OURS"

if [ "$has_conflict" = true ]; then
  cat "$WORK/conflicts" >> "$OURS"
  exit 1
fi
exit 0
