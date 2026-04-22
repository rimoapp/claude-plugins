# claude-plugin-auto-worktree

[English](../../README.md) | [日本語](README.ja.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [中文](README.zh-cn.md) | [Русский](README.ru.md) | [Português](README.pt.md) | [한국어](README.ko.md)

一个 Claude Code 插件，可在修改文件前自动将 Claude 重定向到 git worktree 中，从而实现安全的并行工作，避免 git 冲突。

## 问题背景

当多个 Claude Code 会话同时在同一个仓库中工作时，文件修改可能会产生冲突。不熟悉 git 分支操作的非工程师用户可能会丢失工作成果，或遇到令人困惑的合并冲突。

## 设计理念

**在正常使用过程中，代码变更发生在 worktree 分支中。** 这是一项指导原则，而非对每条命令的强制约束。

该插件的设计目标是尽可能少地干预正常操作：

- **对已跟踪文件的 `Write`/`Edit` 操作**在主仓库中会被阻止 — Claude 会被引导先创建一个 worktree
- **`Bash` 命令**几乎全部允许 — 仅阻止使用输出重定向（`>`、`>>`）写入已跟踪的仓库文件
- **Git 命令**（`checkout`、`reset`、`merge`、`rebase`、`stash` 等）始终允许 — 不假设当前主分支的状态是正确的，用户可能需要修复或管理它
- **包管理器、系统命令、文件工具**全部允许
- **写入 `/tmp`、被 gitignore 的路径或仓库外的文件**始终允许（Plan Mode、memory、临时文件均可正常使用）

## 解决方案

该插件通过 `PreToolUse` 钩子拦截 `Write`、`Edit` 和 `Bash` 工具调用。当 Claude 尝试在主仓库中写入或编辑已跟踪的文件时，插件会：

1. 阻止修改操作（退出码 2）
2. 指示 Claude 调用内置的 `EnterWorktree` 工具
3. Claude 创建一个隔离的 worktree 并在其中重试操作

每个 Claude 会话都有自己独立的 worktree 和分支，因此并行会话之间不会产生冲突。

## 安装

### 从 GitHub 安装（推荐）

在 Claude Code 中运行：

```
/plugin marketplace add rimoapp/claude-plugin-auto-worktree
/plugin install auto-worktree@rimoapp-plugins
```

安装后，插件会在各会话间持久保留。你可以随时启用或禁用它：

```
/plugin disable auto-worktree@rimoapp-plugins
/plugin enable auto-worktree@rimoapp-plugins
```

### 从本地目录安装

用于开发或测试：

```bash
claude --plugin-dir /path/to/claude-plugin-auto-worktree
```

## 工作原理

```
用户在主仓库中启动 Claude
         │
         ▼
SessionStart 钩子触发 ─── 在默认分支上？→ 主动指示 Claude 使用 EnterWorktree
         │
         ▼
Claude 调用 EnterWorktree → 创建 .claude/worktrees/<name>/
         │
         ▼
所有文件修改安全地在 worktree 中进行
         │
         ▼
会话结束 → Stop 钩子输出摘要（分支名、未提交的变更）
```

如果 Claude 跳过了主动指示，**PreToolUse 钩子**会作为安全网发挥作用：

```
Claude 尝试在默认分支上 Write/Edit 文件
         │
         ▼
PreToolUse 钩子拦截 ──────── 已在 worktree 中？→ 允许
         │
         ▼
阻止操作（exit 2）+ 指示 Claude 调用 EnterWorktree
```

### Worktree 位置

Worktree 由 Claude Code 的内置 `EnterWorktree` 工具在仓库内创建：

```
my-project/
├── .claude/
│   └── worktrees/
│       ├── humble-prancing-conway/    # 会话 1
│       └── brave-dancing-turing/      # 会话 2
├── src/
└── ...
```

每个 worktree 都有一个名为 `worktree-<session-name>` 的分支。

### Bash 命令过滤

该插件仅阻止使用输出重定向（`>`、`>>`）向仓库内已跟踪文件写入的 Bash 命令。其他所有命令均被允许：

- **允许**：所有不含重定向的命令（`git checkout`、`npm install`、`rm`、`touch`、`mv` 等），重定向到 `/tmp`、`/dev/null`、被 gitignore 的文件或仓库外的路径
- **阻止**：`echo "data" > tracked-file.txt`、`cat input >> src/main.py` 等（重定向到仓库内已跟踪的文件）

## 配置

该插件通过 Claude Code 的 `userConfig` 机制支持用户自定义配置选项。安装插件后，你可以在 `~/.claude/settings.json` 的 `pluginConfigs` 中设置以下选项：

| 选项 | 说明 | 默认值 |
|------|------|--------|
| `skip_directories` | 以逗号分隔的 git 仓库根路径列表，auto-worktree 不会在这些目录中激活 | （空） |
| `pull_default_branch` | 在会话启动时从 origin 拉取最新的默认分支。仅使用快进合并 — 本地变更不会被覆盖。失败时静默继续。 | `true` |
| `sync_gitignored_writes` | 自动将 worktree 中写入的被 gitignore 文件复制回主仓库。涵盖 Write/Edit 工具调用和 Bash 输出重定向。 | `true` |

### 配置示例 settings.json

```json
{
  "pluginConfigs": {
    "auto-worktree@rimoapp-plugins": {
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

仓库根路径匹配此处条目的仓库将被插件完全忽略 — 不会执行 worktree 强制，也不会有会话启动指示。匹配基于 git 仓库根目录，因此指定 `/Users/me/notes` 将跳过整个仓库，无论 Claude 在哪个子目录中工作。适用于个人仓库、笔记或临时目录等你希望直接在默认分支上编辑的场景。

### pull_default_branch

启用时（默认启用），插件会在会话启动时运行 `git pull --ff-only`（超时时间为 8 秒），以确保本地默认分支在创建 worktree 前是最新的。如果拉取失败（例如离线、超时、历史分歧），插件会继续使用本地状态并输出警告。设为 `false` 可完全跳过此步骤。

### sync_gitignored_writes

启用时（默认启用），在 worktree 中写入被 gitignore 路径的文件会自动复制回主仓库。这确保了 `dist/` 或 `build/` 等目录中的构建产物在 worktree 被移除时不会丢失。

**会同步的内容：**
- 通过 Write/Edit 工具写入仓库内被 gitignore 路径的文件
- 通过 Bash 输出重定向（`>`、`>>`）写入仓库内被 gitignore 路径的文件

**不会同步的内容：**
- 由命令间接创建的文件（例如 `npm install` 创建的 `node_modules/`）
- 仓库外的文件（例如 `/tmp/...`）
- 已跟踪（非 gitignore）路径上的文件

设为 `false` 可完全禁用此行为。

## 会话绕过

如果插件错误地阻止了某个操作，你可以使用自然语言要求 Claude 在当前会话中跳过 worktree 强制 — 任何表述方式均可：

- "worktree作らなくていい" / "auto-worktree 無視して"
- "don't need a worktree" / "skip worktree" / "no worktree please"
- 或任何其他表达相同意图的方式

Claude 会运行 `touch <bypass-flag-file>` 来禁用当前会话后续的强制检查。该标志文件存储在系统临时目录（`$TMPDIR` / `$TMP` / `$TEMP` / `/tmp`）中，**不会**影响其他会话。

## 清理

Worktree 的清理由 Claude Code 的内置 `ExitWorktree` 工具处理。当会话在 worktree 中结束时，用户会被提示选择保留或移除它。

手动清理：

```bash
git worktree list          # 查看所有 worktree
git worktree remove <path> # 移除指定的 worktree
git worktree prune         # 清理过时的引用
```

## 文件结构

```
claude-plugin-auto-worktree/
├── .claude-plugin/
│   ├── marketplace.json     # Marketplace 定义
│   └── plugin.json          # 插件清单
├── hooks/
│   ├── hooks.json           # 钩子定义
│   ├── session-start.sh     # 会话启动时的主动指示
│   ├── pre-tool-use.sh      # 安全网：阻止并重定向到 EnterWorktree
│   ├── post-tool-use.sh     # 将被 gitignore 的写入同步到主仓库
│   └── stop.sh              # 会话结束摘要
├── lib/
│   ├── json.sh              # 共享 JSON 解析辅助函数
│   ├── worktree.sh          # Git worktree 检测辅助函数
│   ├── bash-filter.sh       # 变更检测启发式方法
│   ├── bypass.sh            # 会话绕过标志辅助函数
│   └── config.sh            # 用户配置辅助函数
├── tests/
│   ├── run-tests.sh         # 测试运行器
│   ├── test-bash-filter.sh  # 变更检测测试
│   ├── test-bypass.sh       # 会话绕过测试
│   ├── test-config.sh       # 配置单元测试
│   ├── test-config-integration.sh # 配置集成测试
│   ├── test-json.sh         # JSON 解析测试
│   ├── test-post-tool-use.sh # PostToolUse 集成测试
│   ├── test-worktree.sh     # Worktree 检测测试
│   ├── test-pre-tool-use.sh # PreToolUse 集成测试
│   ├── test-session-start.sh # SessionStart 钩子测试
│   └── test-stop.sh         # Stop 钩子测试
├── docs/
│   └── i18n/                # 翻译版 README
├── LICENSE
└── README.md
```

## 运行测试

```bash
bash tests/run-tests.sh
```

## 系统要求

- `git` 2.5+（worktree 支持）
- `jq`（首选）或 `python3`（备选）用于 JSON 解析
- `bash` 4+

## 许可证

MIT
