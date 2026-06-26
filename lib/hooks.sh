#!/usr/bin/env bash
# hooks.sh — git hook / merge driver installation helpers.
# Sourced by setup + install-hooks tasks.

git_common_dir_abs() {
  local common_dir
  common_dir="$(git -C "$TARGET_DIR" rev-parse --git-common-dir)"
  case "$common_dir" in
    /*) echo "$common_dir" ;;
    *) echo "$TARGET_DIR/$common_dir" ;;
  esac
}

install_pre_commit_hooks() {
  local hooks_src hooks_dst hook lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  hooks_src="$(cd "$lib_dir/../hooks" && pwd)"
  hooks_dst="$(git_common_dir_abs)/hooks"

  if [ ! -x "$hooks_dst/pre-commit" ]; then
    mkdir -p "$hooks_dst"
    cp "$hooks_src/dispatcher" "$hooks_dst/pre-commit"
    chmod +x "$hooks_dst/pre-commit"
  elif ! grep -q 'pre-commit\.d' "$hooks_dst/pre-commit" 2>/dev/null; then
    echo "Warning: existing pre-commit hook at $hooks_dst/pre-commit" >&2
    echo "         does not dispatch pre-commit.d/. The modules guards were" >&2
    echo "         installed but may not run until this hook invokes them." >&2
    echo "  To use the default dispatcher: rm $hooks_dst/pre-commit && mise run install-hooks" >&2
    echo "  To keep your hook: update it to iterate files in ${hooks_dst}/pre-commit.d/" >&2
  fi

  mkdir -p "$hooks_dst/pre-commit.d"
  for hook in gitmodules-guard manifest-encryption; do
    cp "$hooks_src/$hook" "$hooks_dst/pre-commit.d/$hook"
    chmod +x "$hooks_dst/pre-commit.d/$hook"
  done

  rm -f "$hooks_dst/pre-commit.d/path-obfuscation"
}

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
