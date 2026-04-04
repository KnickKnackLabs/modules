<div align="center">

# modules

**Encrypted, obfuscated git submodules — without .gitmodules.**

Manage cross-repo references with hashed directory names and an encrypted manifest.
Outsiders see opaque gitlinks. Insiders see the full dependency graph.

![lang: bash](https://img.shields.io/badge/lang-bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
[![tests: 46 passing](https://img.shields.io/badge/tests-46%20passing-brightgreen?style=flat)](test/)
![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat)

</div>

<br />

## Why

Git submodules require `.gitmodules` — a plaintext file that exposes your dependency URLs and paths. Git-crypt can't encrypt it (git needs to parse it as INI config). So if your repo is public but your dependency graph is private, submodules leak information.

**modules** skips `.gitmodules` entirely. It uses plain `git clone` inside your repo (which git tracks as mode 160000 gitlinks — the same mechanism submodules use) and stores the URL/path/pin mapping in its own manifest, which _can_ be encrypted.

## Quick start

```bash
# Install
shiv install modules

# Initialize in your repo
modules setup

# Add a dependency
modules add https://github.com/org/repo.git --name my-dep

# See what you have
modules list
modules status

# On a fresh clone: populate everything from the manifest
modules init
```

## How it works

```
  your-repo/
  ├── submodules/
  │   ├── .manifest      ← encrypted (name → url, path, pin)
  │   ├── a8f3c12b/      ← hashed directory name
  │   │   └── (cloned repo contents)
  │   └── 7d2e9f01/
  │       └── (another repo)
  └── ...
```

- **No .gitmodules** — git tracks gitlinks (pinned commit SHAs) but has no URL metadata
- **Hashed paths** — directory names are SHA-1 hashes of the module name, not human-readable
- **Encrypted manifest** — the `.manifest` file maps names to URLs and can be encrypted via git-crypt
- **Standard git** — uses regular `git clone` and `git add` under the hood, nothing exotic

<br />

## Commands

| Command                              | Description                                      |
| ------------------------------------ | ------------------------------------------------ |
| `modules add <url> [--name] [--ref]` | Add a submodule                                  |
| `modules init`                       | Clone and checkout all modules from the manifest |
| `modules list [--json]`              | List modules                                     |
| `modules remove <name>`              | Remove a module                                  |
| `modules setup`                      | Initialize modules in the current repo           |
| `modules status`                     | Show status of all modules                       |
| `modules update [name]`              | Pull latest and update pin for module(s)         |

<br />

## Testing

```bash
git clone https://github.com/KnickKnackLabs/modules.git
cd modules && mise trust && mise install
mise run test
```

**46 tests** across 8 suites, using [BATS](https://github.com/bats-core/bats-core). All tests use local git repos in temp directories — no network, no external dependencies.

The `git-mechanics` suite independently verifies every git assumption the tool relies on: gitlinks without .gitmodules, SHA pinning, fresh clone behavior, obfuscated paths, and encrypted manifest coexistence.

## Architecture

```
modules/
├── .mise/tasks/
│   ├── setup       # Initialize submodules dir + manifest
│   ├── add         # Clone into hashed path, record in manifest
│   ├── list        # Show modules (table or --json)
│   ├── init        # Populate all modules on fresh checkout
│   ├── update      # Pull latest, update pinned SHA
│   ├── status      # Show at-pin / changed / missing
│   ├── remove      # Clean removal of clone + manifest entry
│   └── test        # Run BATS test suite
├── lib/
│   └── common.sh   # Shared helpers (manifest ops, hashing, require checks)
├── test/
│   ├── test_helper.bash
│   ├── git-mechanics.bats   # Git behavior verification
│   ├── setup.bats
│   ├── add.bats
│   ├── list.bats
│   ├── init.bats
│   ├── update.bats
│   ├── status.bats
│   └── remove.bats
└── mise.toml
```

<br />

<div align="center">

---

<sub>
Your dependencies, visible only to those who should see them.<br />
<br />
This README was generated from <a href="https://github.com/KnickKnackLabs/readme">README.tsx</a>.
</sub></div>
