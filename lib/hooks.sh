#!/usr/bin/env bash
# hooks.sh — git hook / merge driver installation helpers.
# Sourced by setup + install-hooks tasks.

# Install the manifest merge driver.
# Registers a git config entry + adds .gitattributes merge= pattern.
install_manifest_merge_driver() {
  local gitattributes="$TARGET_DIR/.gitattributes"

  # Register the merge driver in repo-local git config.
  #
  # Resolve the driver at merge time via the `modules` shim on PATH, not by
  # writing an absolute path. A path like $MISE_CONFIG_ROOT/lib/... pins the
  # driver to the version of modules installed at setup time; on upgrade
  # (shiv installs each version to a new directory), that path goes stale,
  # git silently falls back to the default recursive merge, and encrypted
  # manifests get corrupted on any concurrent pin bump — exactly the failure
  # mode this driver exists to prevent.
  git -C "$TARGET_DIR" config merge."modules-manifest".name \
    "Union merge driver for modules manifest"
  git -C "$TARGET_DIR" config merge."modules-manifest".driver \
    "modules merge-driver %O %A %B"

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
