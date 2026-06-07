All code, documentation, commits, and PRs must be written in English.

This repository is the `rimo-tools` plugin marketplace. Each plugin lives in its own directory under `plugins/<name>/` with its own `.claude-plugin/plugin.json`; the marketplace catalog is `.claude-plugin/marketplace.json` at the repo root.

When releasing a plugin, bump its version in both `plugins/<name>/.claude-plugin/plugin.json` and the matching entry in `.claude-plugin/marketplace.json` (keep them equal). The release workflow tags each plugin as `<name>--v<version>`.

All shell scripts must work on standard macOS and Windows (Git Bash) environments without requiring additional tool installations. Avoid using tools like `perl`, `python3`, or other interpreters that may not be available by default — prefer pure bash/POSIX sh constructs instead.
