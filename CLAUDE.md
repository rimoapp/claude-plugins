All code, documentation, commits, and PRs must be written in English.

This repository is the `rimo-tools` plugin marketplace. Each plugin lives in its own directory under `plugins/<name>/` with its own `.claude-plugin/plugin.json`; the marketplace catalog is `.claude-plugin/marketplace.json` at the repo root.

Each plugin's `version` lives in exactly one place: its own `plugins/<name>/.claude-plugin/plugin.json`. Do not duplicate it in the `.claude-plugin/marketplace.json` entry — Claude Code resolves a local plugin's version from `plugin.json` first, so the marketplace entry would only risk drifting out of sync. To release a plugin, bump the `version` in its `plugin.json` and merge to `main`; the release workflow reads that file and tags each plugin as `<name>--v<version>`, creating a GitHub release if the tag does not already exist.

Externally-sourced plugins whose `plugin.json` lives in another repository (e.g. `rimo`, sourced from `rimo/cli`) carry no `version` either. With no `version` and no pinned `ref`/`sha` on the source, Claude Code resolves the version from the source repository's commit SHA, so the plugin always tracks the latest default-branch commit. To pin such a plugin to a stable release instead, add a `ref` or `sha` to its `source`.

Note: the marketplace `owner` object supports only `name` and `email` (no `url`). A plugin's `author` object additionally supports `url`, and plugins may also set `homepage` and `repository`.

All shell scripts must work on standard macOS and Windows (Git Bash) environments without requiring additional tool installations. Avoid using tools like `perl`, `python3`, or other interpreters that may not be available by default — prefer pure bash/POSIX sh constructs instead.
