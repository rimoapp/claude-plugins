# auto-worktree

[English](README.md) | [日本語](docs/i18n/README.ja.md) | [Español](docs/i18n/README.es.md) | [Deutsch](docs/i18n/README.de.md) | [中文](docs/i18n/README.zh-cn.md) | [Русский](docs/i18n/README.ru.md) | [Português](docs/i18n/README.pt.md) | [한국어](docs/i18n/README.ko.md)

A Claude Code plugin that automatically redirects Claude into a git worktree before modifying files, enabling safe parallel work without git conflicts.

## Problem

When multiple Claude Code sessions work on the same repository simultaneously, file modifications can conflict. Non-engineers who aren't familiar with git branching may lose work or encounter confusing merge conflicts.

## Design Policy

**During normal use, code changes happen in worktree branches.** This is a guiding principle, not a hard enforcement on every command.

The plugin is designed to be minimally invasive:

- **`Write`/`Edit` to tracked files** in the main repo are blocked — Claude is redirected to create a worktree first
- **`Bash` commands** are almost entirely allowed — only output redirects (`>`, `>>`) to tracked repo files are blocked
- **Git commands** (`checkout`, `reset`, `merge`, `rebase`, `stash`, etc.) are always allowed — the current main branch is not assumed to be correct, and users may need to fix or manage it
- **Package managers, system commands, file utilities** are all allowed
- **Writes to `/tmp`, gitignored paths, or files outside the repo** are always allowed (Plan Mode, memory, temp files all work)

## Solution

This plugin intercepts `Write`, `Edit`, and `Bash` tool calls via a `PreToolUse` hook. When Claude tries to write or edit a tracked file in the main repository, the plugin:

1. Blocks the modification (exit code 2)
2. Instructs Claude to call the built-in `EnterWorktree` tool
3. Claude creates an isolated worktree and retries the action there

Each Claude session gets its own isolated worktree and branch, so parallel sessions never conflict.

## Installation

### From GitHub (recommended)

In Claude Code, run:

```
/plugin marketplace add rimoapp/claude-plugins
/plugin install auto-worktree@rimo-tools
```

Once installed, the plugin persists across sessions. You can enable/disable it anytime:

```
/plugin disable auto-worktree@rimo-tools
/plugin enable auto-worktree@rimo-tools
```

### From local directory

For development or testing:

```bash
claude --plugin-dir /path/to/claude-plugins/plugins/auto-worktree
```

## How It Works

```
User starts Claude in main repo
         │
         ▼
SessionStart hook fires ─── On default branch? → Proactively tells Claude to use EnterWorktree
         │
         ▼
Claude calls EnterWorktree → creates .claude/worktrees/<name>/
         │
         ▼
All file modifications happen safely in the worktree
         │
         ▼
Session ends → Stop hook prints summary (branch, uncommitted changes)
```

If Claude skips the proactive instruction, the **PreToolUse hook** acts as a safety net:

```
Claude tries to Write/Edit a file on default branch
         │
         ▼
PreToolUse hook intercepts ──────── Already in a worktree? → Allow
         │
         ▼
Blocks action (exit 2) + tells Claude to call EnterWorktree
```

### Worktree Location

Worktrees are created by Claude Code's built-in `EnterWorktree` tool inside the repository:

```
my-project/
├── .claude/
│   └── worktrees/
│       ├── humble-prancing-conway/    # Session 1
│       └── brave-dancing-turing/      # Session 2
├── src/
└── ...
```

Each worktree gets a branch named `worktree-<session-name>`.

### Bash Command Filtering

The plugin only blocks Bash commands that use output redirects (`>`, `>>`) to write to tracked files inside the repository. Everything else is allowed:

- **Allowed**: all commands without redirects (`git checkout`, `npm install`, `rm`, `touch`, `mv`, etc.), redirects to `/tmp`, `/dev/null`, gitignored files, or paths outside the repo
- **Blocked**: `echo "data" > tracked-file.txt`, `cat input >> src/main.py`, etc. (redirects to tracked repo files)

## Configuration

The plugin supports user-configurable options via Claude Code's `userConfig` mechanism. After installing the plugin, you can set these options in your `~/.claude/settings.json` under `pluginConfigs`:

| Option | Description | Default |
|--------|-------------|---------|
| `skip_directories` | Comma-separated list of git repository root paths where auto-worktree should not activate | (empty) |
| `pull_default_branch` | Pull the latest default branch from origin on session start. Uses fast-forward only — local changes are never overwritten. Silently continues on failure. | `true` |
| `sync_gitignored_writes` | Automatically copy gitignored files written in a worktree back to the main repository. Covers Write/Edit tool calls and Bash output redirects. | `true` |
| `auto_return_to_default` | Automatically switch back to the default branch at session start if on a non-default branch with no uncommitted changes. | `true` |

### Example settings.json

```json
{
  "pluginConfigs": {
    "auto-worktree@rimo-tools": {
      "options": {
        "skip_directories": "/Users/me/notes,/Users/me/scratch",
        "pull_default_branch": "false",
        "sync_gitignored_writes": "true"
      }
    }
  }
}
```

### skip_directories

Repositories whose root path matches an entry here will be completely ignored by the plugin — no worktree enforcement, no session-start instructions. The match is based on the git repository root, so specifying `/Users/me/notes` will skip the entire repository regardless of which subdirectory Claude is working in. Useful for personal repos, notes, or scratch directories where you want to edit directly on the default branch.

### pull_default_branch

When enabled (the default), the plugin runs `git pull --ff-only` at session start (with an 8-second timeout) to ensure the local default branch is up to date before creating a worktree. If the pull fails (e.g. offline, timeout, diverged history), the plugin continues with the local state and prints a warning. Set to `false` to skip this entirely.

### auto_return_to_default

This option only governs **whether the working branch is automatically switched back to the default branch**. Keeping the local default branch ref fresh is handled separately by `pull_default_branch` and runs even when this option is disabled.

When enabled (the default), the plugin checks at session start whether Claude is on a non-default branch in the main repository. If so:

- **No uncommitted changes** — the plugin automatically runs `git checkout <default-branch>` and continues with the normal pull + EnterWorktree flow. A brief notice is printed so Claude can inform the user.
- **Uncommitted changes exist** — the plugin prints a warning asking the user to commit and push before switching, then exits without modifying the working branch.

Set to `false` to disable the auto-switch entirely. Non-default branches are not switched, and no warning is printed.

Independently of this option, when `pull_default_branch=true` and Claude is on a non-default branch, the plugin runs `git fetch origin <default-branch>:<default-branch>` in the background to fast-forward the local default ref without disturbing the user's working tree (non-fast-forward updates are rejected, and the default branch is not checked out in this path). A short notice is printed only when the local default ref actually moved.

Untracked files are not considered "changes" for the dirty-state check; they carry over safely across branch switches.

### sync_gitignored_writes

When enabled (the default), files written to gitignored paths inside a worktree are automatically copied back to the main repository. This ensures that build artifacts in directories like `dist/` or `build/` are not lost when the worktree is removed.

**What is synced:**
- Files written via Write/Edit tools to gitignored paths inside the repo
- Bash output redirects (`>`, `>>`) to gitignored paths inside the repo

**What is NOT synced:**
- Files created indirectly by commands (e.g. `npm install` creating `node_modules/`)
- Files outside the repository (e.g. `/tmp/...`)
- Files on tracked (non-gitignored) paths

Set to `false` to disable this behavior entirely.

## Session Bypass

If the plugin incorrectly blocks an action, you can ask Claude to skip worktree enforcement for the current session using natural language — any phrasing works:

- "worktree作らなくていい" / "auto-worktree 無視して"
- "don't need a worktree" / "skip worktree" / "no worktree please"
- Or any other way of expressing the same intent

Claude will run `touch <bypass-flag-file>` to disable enforcement for the rest of the session. The flag is stored in the system temp directory (`$TMPDIR` / `$TMP` / `$TEMP` / `/tmp`) and does **not** affect other sessions.

## Cleanup

Worktree cleanup is handled by Claude Code's built-in `ExitWorktree` tool. When a session ends while in a worktree, the user is prompted to keep or remove it.

For manual cleanup:

```bash
git worktree list          # See all worktrees
git worktree remove <path> # Remove a specific worktree
git worktree prune         # Clean up stale references
```

## File Structure

```
auto-worktree/
├── .claude-plugin/
│   ├── marketplace.json     # Marketplace definition
│   └── plugin.json          # Plugin manifest
├── hooks/
│   ├── hooks.json           # Hook definitions
│   ├── session-start.sh     # Proactive instruction at session start
│   ├── pre-tool-use.sh      # Safety net: block and redirect to EnterWorktree
│   ├── post-tool-use.sh     # Sync gitignored writes to main repo
│   └── stop.sh              # Session end summary
├── lib/
│   ├── json.sh              # Shared JSON parsing helpers
│   ├── worktree.sh          # Git worktree detection helpers
│   ├── bash-filter.sh       # Mutation detection heuristic
│   ├── bypass.sh            # Session bypass flag helpers
│   └── config.sh            # User configuration helpers
├── tests/
│   ├── run-tests.sh         # Test runner
│   ├── test-bash-filter.sh  # Mutation detection tests
│   ├── test-bypass.sh       # Session bypass tests
│   ├── test-config.sh       # Configuration unit tests
│   ├── test-config-integration.sh # Configuration integration tests
│   ├── test-json.sh         # JSON parsing tests
│   ├── test-post-tool-use.sh # PostToolUse integration tests
│   ├── test-worktree.sh     # Worktree detection tests
│   ├── test-pre-tool-use.sh # PreToolUse integration tests
│   ├── test-session-start.sh # SessionStart hook tests
│   └── test-stop.sh         # Stop hook tests
├── docs/
│   └── i18n/                # Translated READMEs
├── LICENSE
└── README.md
```

## Running Tests

```bash
bash tests/run-tests.sh
```

## Requirements

- `git` 2.5+ (worktree support)
- `jq` (preferred) or `python3` (fallback) for JSON parsing
- `bash` 4+

## License

MIT
