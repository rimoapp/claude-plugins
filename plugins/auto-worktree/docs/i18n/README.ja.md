# auto-worktree

[English](../../README.md) | [日本語](README.ja.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [中文](README.zh-cn.md) | [Русский](README.ru.md) | [Português](README.pt.md) | [한국어](README.ko.md)

Claude Code プラグイン。ファイル変更前に Claude を自動的に git worktree へ誘導し、git の競合なしに安全な並列作業を実現します。

## 課題

複数の Claude Code セッションが同じリポジトリで同時に作業すると、ファイルの変更が競合する可能性があります。git のブランチ操作に慣れていない非エンジニアの方は、作業内容を失ったり、分かりにくいマージコンフリクトに遭遇することがあります。

## 設計方針

**通常の使用では、コードの変更は worktree ブランチで行われます。** これは指針であり、すべてのコマンドに対する厳格な制約ではありません。

このプラグインは最小限の介入を目指して設計されています：

- **`Write`/`Edit`（追跡ファイルへの書き込み）** はメインリポジトリでブロックされます — Claude はまず worktree を作成するよう誘導されます
- **`Bash` コマンド** はほぼすべて許可されます — 追跡されたリポジトリファイルへの出力リダイレクト（`>`、`>>`）のみブロックされます
- **Git コマンド**（`checkout`、`reset`、`merge`、`rebase`、`stash` など）は常に許可されます — 現在のメインブランチが正しいとは限らず、ユーザーが修正・管理する必要がある場合があります
- **パッケージマネージャ、システムコマンド、ファイルユーティリティ** はすべて許可されます
- **`/tmp`、gitignore されたパス、リポジトリ外のファイルへの書き込み** は常に許可されます（Plan Mode、メモリ、一時ファイルはすべて動作します）

## 解決策

このプラグインは `PreToolUse` フックを通じて `Write`、`Edit`、`Bash` ツールの呼び出しをインターセプトします。Claude がメインリポジトリ内の追跡ファイルに書き込みまたは編集しようとすると、プラグインは以下を行います：

1. 変更をブロック（終了コード 2）
2. 組み込みの `EnterWorktree` ツールを呼び出すよう Claude に指示
3. Claude が隔離された worktree を作成し、そこでアクションを再試行

各 Claude セッションは独自の隔離された worktree とブランチを持つため、並列セッション間で競合が発生しません。

## インストール

### GitHub から（推奨）

Claude Code で以下を実行します：

```
/plugin marketplace add rimoapp/claude-plugins
/plugin install auto-worktree@rimo-tools
```

インストール後、プラグインはセッション間で保持されます。いつでも有効/無効を切り替えられます：

```
/plugin disable auto-worktree@rimo-tools
/plugin enable auto-worktree@rimo-tools
```

### ローカルディレクトリから

開発やテスト用：

```bash
claude --plugin-dir /path/to/claude-plugins/plugins/auto-worktree
```

## 仕組み

```
ユーザーがメインリポジトリで Claude を起動
         │
         ▼
SessionStart フックが発火 ─── デフォルトブランチ？ → Claude に EnterWorktree の使用を事前に指示
         │
         ▼
Claude が EnterWorktree を呼び出す → .claude/worktrees/<name>/ を作成
         │
         ▼
すべてのファイル変更が worktree 内で安全に行われる
         │
         ▼
セッション終了 → Stop フックがサマリーを表示（ブランチ、未コミットの変更）
```

Claude が事前の指示をスキップした場合、**PreToolUse フック**がセーフティネットとして機能します：

```
Claude がデフォルトブランチでファイルの Write/Edit を試行
         │
         ▼
PreToolUse フックがインターセプト ──────── すでに worktree 内？ → 許可
         │
         ▼
アクションをブロック（exit 2）+ Claude に EnterWorktree の呼び出しを指示
```

### Worktree の配置場所

Worktree は Claude Code の組み込み `EnterWorktree` ツールによってリポジトリ内に作成されます：

```
my-project/
├── .claude/
│   └── worktrees/
│       ├── humble-prancing-conway/    # セッション 1
│       └── brave-dancing-turing/      # セッション 2
├── src/
└── ...
```

各 worktree には `worktree-<session-name>` という名前のブランチが割り当てられます。

### Bash コマンドのフィルタリング

プラグインは、リポジトリ内の追跡ファイルに出力リダイレクト（`>`、`>>`）を使用する Bash コマンドのみをブロックします。それ以外はすべて許可されます：

- **許可**: リダイレクトなしのすべてのコマンド（`git checkout`、`npm install`、`rm`、`touch`、`mv` など）、`/tmp`、`/dev/null`、gitignore されたファイル、リポジトリ外のパスへのリダイレクト
- **ブロック**: `echo "data" > tracked-file.txt`、`cat input >> src/main.py` など（追跡されたリポジトリファイルへのリダイレクト）

## 設定

このプラグインは Claude Code の `userConfig` メカニズムを通じてユーザー設定可能なオプションをサポートしています。プラグインのインストール後、`~/.claude/settings.json` の `pluginConfigs` でこれらのオプションを設定できます：

| オプション | 説明 | デフォルト |
|--------|-------------|---------|
| `skip_directories` | auto-worktree を無効にする git リポジトリルートパスのカンマ区切りリスト | （空） |
| `pull_default_branch` | セッション開始時に origin からデフォルトブランチの最新を pull します。fast-forward のみ使用 — ローカルの変更は上書きされません。失敗時はサイレントに続行します。 | `true` |
| `sync_gitignored_writes` | worktree 内で書き込まれた gitignore 対象ファイルをメインリポジトリに自動的にコピーします。Write/Edit ツールの呼び出しと Bash の出力リダイレクトに対応します。 | `true` |
| `auto_return_to_default` | セッション開始時に非デフォルトブランチにいて、未コミットの変更がない場合、自動的にデフォルトブランチに切り替えます。 | `true` |

### settings.json の例

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

ここに一致するルートパスを持つリポジトリは、プラグインによって完全に無視されます — worktree の強制もセッション開始時の指示もありません。一致は git リポジトリのルートに基づくため、`/Users/me/notes` を指定すると、Claude がどのサブディレクトリで作業していてもリポジトリ全体がスキップされます。個人用リポジトリ、メモ、スクラッチディレクトリなど、デフォルトブランチで直接編集したい場合に便利です。

### pull_default_branch

有効な場合（デフォルト）、プラグインはセッション開始時に `git pull --ff-only`（8秒のタイムアウト付き）を実行し、worktree 作成前にローカルのデフォルトブランチを最新の状態にします。pull が失敗した場合（オフライン、タイムアウト、履歴の分岐など）、プラグインはローカルの状態で続行し、警告を表示します。これを完全にスキップするには `false` に設定してください。

### auto_return_to_default

このオプションが制御するのは **作業ブランチを自動でデフォルトブランチに戻すかどうか** だけです。ローカルのデフォルトブランチ ref を最新に保つ動作は `pull_default_branch` 側の責務で、このオプションを無効にしても動きます。

有効な場合（デフォルト）、プラグインはセッション開始時にメインリポジトリで Claude が非デフォルトブランチにいるかを確認します。該当する場合：

- **未コミットの変更がない** — プラグインは自動的に `git checkout <default-branch>` を実行し、通常の pull + EnterWorktree フローを続行します。Claude がユーザーに通知できるよう、簡単なメッセージを表示します。
- **未コミットの変更がある** — プラグインは現在のブランチで commit と push を済ませてから切り替えるよう警告し、作業中のブランチを変更せずに終了します。

`false` に設定すると自動切り替えを完全に無効化します。非デフォルトブランチでもブランチを切り替えず、警告も出しません。

このオプションとは独立に、`pull_default_branch=true` のときは Claude が非デフォルトブランチにいてもバックグラウンドで `git fetch origin <default-branch>:<default-branch>` を実行し、作業ツリーを乱さずにローカルのデフォルト ref を fast-forward で進めます（non-fast-forward は拒否され、デフォルトブランチは checkout されていないので安全）。短い通知が出るのは実際にローカル ref が進んだ場合のみです。

untracked ファイルは dirty 判定では「変更」とみなされません — ブランチ切り替え時にも安全に持ち越されます。

### sync_gitignored_writes

有効な場合（デフォルト）、worktree 内の gitignore 対象パスに書き込まれたファイルは、メインリポジトリに自動的にコピーされます。これにより、`dist/` や `build/` などのディレクトリにあるビルド成果物が worktree の削除時に失われることを防ぎます。

**同期されるもの：**
- Write/Edit ツールを通じてリポジトリ内の gitignore 対象パスに書き込まれたファイル
- Bash の出力リダイレクト（`>`、`>>`）によってリポジトリ内の gitignore 対象パスに書き込まれたファイル

**同期されないもの：**
- コマンドによって間接的に作成されたファイル（例：`npm install` で作成される `node_modules/`）
- リポジトリ外のファイル（例：`/tmp/...`）
- 追跡対象（gitignore されていない）パスのファイル

この動作を完全に無効にするには `false` に設定してください。

## セッションバイパス

プラグインが誤ってアクションをブロックした場合、自然言語で Claude に現在のセッションの worktree 強制をスキップするよう依頼できます — 表現は自由です：

- "worktree作らなくていい" / "auto-worktree 無視して"
- "don't need a worktree" / "skip worktree" / "no worktree please"
- その他、同じ意図を伝える任意の表現

Claude は `touch <bypass-flag-file>` を実行して、セッションの残りの時間に対して強制を無効にします。フラグはシステムの一時ディレクトリ（`$TMPDIR` / `$TMP` / `$TEMP` / `/tmp`）に保存され、他のセッションには影響**しません**。

## クリーンアップ

Worktree のクリーンアップは Claude Code の組み込み `ExitWorktree` ツールによって処理されます。worktree 内でセッションが終了すると、保持するか削除するかをユーザーに確認します。

手動でクリーンアップする場合：

```bash
git worktree list          # すべての worktree を表示
git worktree remove <path> # 特定の worktree を削除
git worktree prune         # 古い参照をクリーンアップ
```

## ファイル構成

```
auto-worktree/
├── .claude-plugin/
│   ├── marketplace.json     # マーケットプレイス定義
│   └── plugin.json          # プラグインマニフェスト
├── hooks/
│   ├── hooks.json           # フック定義
│   ├── session-start.sh     # セッション開始時の事前指示
│   ├── pre-tool-use.sh      # セーフティネット：ブロックして EnterWorktree へ誘導
│   ├── post-tool-use.sh     # gitignore 対象の書き込みをメインリポジトリに同期
│   └── stop.sh              # セッション終了時のサマリー
├── lib/
│   ├── json.sh              # 共有 JSON パースヘルパー
│   ├── worktree.sh          # Git worktree 検出ヘルパー
│   ├── bash-filter.sh       # 変更検出ヒューリスティック
│   ├── bypass.sh            # セッションバイパスフラグヘルパー
│   └── config.sh            # ユーザー設定ヘルパー
├── tests/
│   ├── run-tests.sh         # テストランナー
│   ├── test-bash-filter.sh  # 変更検出テスト
│   ├── test-bypass.sh       # セッションバイパステスト
│   ├── test-config.sh       # 設定ユニットテスト
│   ├── test-config-integration.sh # 設定統合テスト
│   ├── test-json.sh         # JSON パーステスト
│   ├── test-post-tool-use.sh # PostToolUse 統合テスト
│   ├── test-worktree.sh     # Worktree 検出テスト
│   ├── test-pre-tool-use.sh # PreToolUse 統合テスト
│   ├── test-session-start.sh # SessionStart フックテスト
│   └── test-stop.sh         # Stop フックテスト
├── docs/
│   └── i18n/                # 翻訳版 README
├── LICENSE
└── README.md
```

## テストの実行

```bash
bash tests/run-tests.sh
```

## 要件

- `git` 2.5+（worktree サポート）
- `jq`（推奨）または `python3`（フォールバック）（JSON パース用）
- `bash` 4+

## ライセンス

MIT
