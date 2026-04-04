#!/usr/bin/env bash
# common.sh — shared helpers for modules tasks

set -euo pipefail

# The target repo is always CALLER_PWD (set by shiv shim)
TARGET_DIR="${CALLER_PWD:-.}"

# Where modules live in the target repo
SUBMODULES_DIR="$TARGET_DIR/submodules"

# The manifest file (encrypted via git-crypt)
MANIFEST="$SUBMODULES_DIR/.manifest"

# ── Require checks ────────────────────────────────────────────

require_git() {
  if ! git -C "$TARGET_DIR" rev-parse --git-dir &>/dev/null; then
    echo "Error: not a git repository: $TARGET_DIR" >&2
    exit 1
  fi
}

require_initialized() {
  if [ ! -f "$MANIFEST" ]; then
    echo "Error: modules not initialized. Run: modules setup" >&2
    exit 1
  fi
}

require_jq() {
  if ! command -v jq &>/dev/null; then
    echo "Error: jq not found" >&2
    exit 1
  fi
}

# ── Hashing ───────────────────────────────────────────────────

# Generate an obfuscated directory name from a module name.
# Uses first 12 chars of SHA-1 hash.
hash_name() {
  printf '%s' "$1" | shasum | cut -c1-12
}

# ── Manifest operations ──────────────────────────────────────

# Read the full manifest. Outputs JSON to stdout.
manifest_read() {
  if [ ! -f "$MANIFEST" ]; then
    echo "{}"
    return
  fi
  cat "$MANIFEST"
}

# Write JSON from stdin to the manifest.
# Uses a temp file to avoid truncating before pipeline reads finish.
manifest_write() {
  local tmp="${MANIFEST}.tmp"
  jq '.' > "$tmp"
  mv "$tmp" "$MANIFEST"
}

# Get a module entry by name. Outputs JSON to stdout.
# Returns 1 if not found.
manifest_get() {
  local name="$1"
  local entry
  entry="$(manifest_read | jq -e --arg n "$name" '.[$n]')" || return 1
  echo "$entry"
}

# Set a module entry. Reads current manifest, merges, writes back.
# Usage: manifest_set <name> <url> <path> <pin>
manifest_set() {
  local name="$1" url="$2" path="$3" pin="$4"
  manifest_read | jq --arg n "$name" --arg u "$url" --arg p "$path" --arg s "$pin" \
    '.[$n] = {"url": $u, "path": $p, "pin": $s}' | manifest_write
}

# Remove a module entry by name.
manifest_remove() {
  local name="$1"
  manifest_read | jq --arg n "$name" 'del(.[$n])' | manifest_write
}

# List all module names. One per line.
manifest_names() {
  manifest_read | jq -r 'keys[]'
}
