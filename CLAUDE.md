All code, documentation, commits, and PRs must be written in English.

When making a release, bump the version in both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.

All shell scripts must work on standard macOS and Windows (Git Bash) environments without requiring additional tool installations. Avoid using tools like `perl`, `python3`, or other interpreters that may not be available by default — prefer pure bash/POSIX sh constructs instead.
