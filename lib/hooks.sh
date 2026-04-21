#!/usr/bin/env bash
# hooks.sh — git hook / merge driver installation helpers.
# Sourced by setup + install-hooks tasks.

# Install the manifest merge driver.
# Registers a git config entry + adds .gitattributes merge= pattern.
install_manifest_merge_driver() {
  local driver_path="$MISE_CONFIG_ROOT/lib/manifest-merge-driver.sh"
  local gitattributes="$TARGET_DIR/.gitattributes"

  # Register the merge driver in repo-local git config.
  # Using an absolute path is fine: the driver lives inside the shiv package,
  # which is stable across sessions for the same version.
  git -C "$TARGET_DIR" config merge."modules-manifest".name \
    "Union merge driver for modules manifest"
  git -C "$TARGET_DIR" config merge."modules-manifest".driver \
    "bash \"$driver_path\" %O %A %B"

  # Add .gitattributes entry if not already present.
  local pattern=".modules/manifest merge=modules-manifest"
  touch "$gitattributes"
  if ! grep -qF "$pattern" "$gitattributes" 2>/dev/null; then
    if [ -n "$(tail -c1 "$gitattributes" 2>/dev/null)" ]; then
      printf '\n' >> "$gitattributes"
    fi
    echo "$pattern" >> "$gitattributes"
  fi
}
