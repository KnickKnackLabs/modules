#!/usr/bin/env bash
# common.sh — shared helpers for modules tasks

set -euo pipefail

# The target repo is always CALLER_PWD (set by shiv shim)
TARGET_DIR="${CALLER_PWD:-.}"

# Where modules metadata lives (tracked; manifest encrypted, config plaintext).
MODULES_DIR="$TARGET_DIR/.modules"
MANIFEST="$MODULES_DIR/manifest"
CONFIG="$MODULES_DIR/config"

# Paths tracked in git-relative form (for hooks / diff matching).
MANIFEST_REL=".modules/manifest"
CONFIG_REL=".modules/config"

# Default clone-root path (relative to repo root) if no config is set.
DEFAULT_CLONES_PATH="modules"

# Resolve the relative path (from repo root) where module clones live.
# Reads .modules/config; falls back to DEFAULT_CLONES_PATH.
clones_path_rel() {
  if [ -f "$CONFIG" ] && command -v jq &>/dev/null; then
    local configured
    configured="$(jq -r '.path // empty' "$CONFIG" 2>/dev/null || true)"
    if [ -n "$configured" ]; then
      echo "$configured"
      return
    fi
  fi
  echo "$DEFAULT_CLONES_PATH"
}

# Absolute path to the clone root.
clones_dir() {
  echo "$TARGET_DIR/$(clones_path_rel)"
}

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

require_rudi() {
  if ! command -v rudi &>/dev/null; then
    echo "Error: rudi not found. Install it: shiv install rudi" >&2
    exit 1
  fi
}

# ── Path helpers ──────────────────────────────────────────────

# Given a module name, return its clone path (absolute).
# With the opacity redesign, the path is <clones_dir>/<name>/ —
# no hashing, no manifest lookup. Names are the directory names.
module_path() {
  local name="$1"
  echo "$(clones_dir)/$name"
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
# Usage: manifest_set <name> <url> <pin>
manifest_set() {
  local name="$1" url="$2" pin="$3"
  manifest_read | jq --arg n "$name" --arg u "$url" --arg s "$pin" \
    '.[$n] = {"url": $u, "pin": $s}' | manifest_write
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
