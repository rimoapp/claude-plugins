# auto-worktree

[English](../../README.md) | [日本語](README.ja.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [中文](README.zh-cn.md) | [Русский](README.ru.md) | [Português](README.pt.md) | [한국어](README.ko.md)

Claude Code 플러그인으로, 파일을 수정하기 전에 자동으로 git worktree로 이동시켜 git 충돌 없이 안전하게 병렬 작업을 할 수 있게 해줍니다.

## 문제점

여러 Claude Code 세션이 동일한 저장소에서 동시에 작업할 때, 파일 수정이 충돌할 수 있습니다. git 브랜치에 익숙하지 않은 비개발자는 작업을 잃거나 혼란스러운 병합 충돌에 직면할 수 있습니다.

## 설계 방침

**일반적인 사용 시, 코드 변경은 worktree 브랜치에서 이루어집니다.** 이것은 모든 명령에 대한 엄격한 강제가 아닌 기본 원칙입니다.

이 플러그인은 최소한의 개입을 목표로 설계되었습니다:

- **추적 중인 파일에 대한 `Write`/`Edit`** 은 메인 저장소에서 차단됩니다 — Claude는 먼저 worktree를 생성하도록 안내받습니다
- **`Bash` 명령** 은 거의 전부 허용됩니다 — 추적 중인 저장소 파일로의 출력 리다이렉트(`>`, `>>`)만 차단됩니다
- **Git 명령** (`checkout`, `reset`, `merge`, `rebase`, `stash` 등)은 항상 허용됩니다 — 현재 메인 브랜치가 올바른 상태라고 가정하지 않으며, 사용자가 관리하거나 수정해야 할 수 있습니다
- **패키지 매니저, 시스템 명령, 파일 유틸리티** 는 모두 허용됩니다
- **`/tmp`, gitignore된 경로, 또는 저장소 외부 파일에 대한 쓰기** 는 항상 허용됩니다 (Plan Mode, 메모리, 임시 파일 모두 작동합니다)

## 해결 방법

이 플러그인은 `PreToolUse` 훅을 통해 `Write`, `Edit`, `Bash` 도구 호출을 가로챕니다. Claude가 메인 저장소의 추적 중인 파일을 쓰거나 편집하려 할 때, 플러그인은:

1. 수정을 차단합니다 (종료 코드 2)
2. Claude에게 내장된 `EnterWorktree` 도구를 호출하도록 지시합니다
3. Claude가 격리된 worktree를 생성하고 그곳에서 작업을 재시도합니다

각 Claude 세션은 자체 격리된 worktree와 브랜치를 가지므로, 병렬 세션이 절대 충돌하지 않습니다.

## 설치

### GitHub에서 설치 (권장)

Claude Code에서 다음을 실행하세요:

```
/plugin marketplace add rimoapp/claude-plugins
/plugin install auto-worktree@rimo-tools
```

설치 후, 플러그인은 세션 간에 유지됩니다. 언제든지 활성화/비활성화할 수 있습니다:

```
/plugin disable auto-worktree@rimo-tools
/plugin enable auto-worktree@rimo-tools
```

### 로컬 디렉토리에서 설치

개발 또는 테스트용:

```bash
claude --plugin-dir /path/to/claude-plugins/plugins/auto-worktree
```

## 작동 방식

```
사용자가 메인 저장소에서 Claude를 시작
         │
         ▼
SessionStart 훅 실행 ─── 기본 브랜치인가? → Claude에게 EnterWorktree 사용을 사전 안내
         │
         ▼
Claude가 EnterWorktree 호출 → .claude/worktrees/<name>/ 생성
         │
         ▼
모든 파일 수정이 worktree 안에서 안전하게 수행됨
         │
         ▼
세션 종료 → Stop 훅이 요약 출력 (브랜치, 커밋되지 않은 변경사항)
```

Claude가 사전 안내를 건너뛴 경우, **PreToolUse 훅** 이 안전망 역할을 합니다:

```
Claude가 기본 브랜치에서 파일 Write/Edit 시도
         │
         ▼
PreToolUse 훅이 가로챔 ──────── 이미 worktree 안인가? → 허용
         │
         ▼
작업 차단 (exit 2) + Claude에게 EnterWorktree 호출 지시
```

### Worktree 위치

Worktree는 Claude Code의 내장 `EnterWorktree` 도구에 의해 저장소 내부에 생성됩니다:

```
my-project/
├── .claude/
│   └── worktrees/
│       ├── humble-prancing-conway/    # 세션 1
│       └── brave-dancing-turing/      # 세션 2
├── src/
└── ...
```

각 worktree는 `worktree-<session-name>` 형식의 브랜치를 갖습니다.

### Bash 명령 필터링

플러그인은 추적 중인 저장소 파일에 출력 리다이렉트(`>`, `>>`)를 사용하는 Bash 명령만 차단합니다. 그 외에는 모두 허용됩니다:

- **허용**: 리다이렉트 없는 모든 명령 (`git checkout`, `npm install`, `rm`, `touch`, `mv` 등), `/tmp`, `/dev/null`, gitignore된 파일, 또는 저장소 외부 경로로의 리다이렉트
- **차단**: `echo "data" > tracked-file.txt`, `cat input >> src/main.py` 등 (추적 중인 저장소 파일로의 리다이렉트)

## 설정

플러그인은 Claude Code의 `userConfig` 메커니즘을 통해 사용자 설정 옵션을 지원합니다. 플러그인을 설치한 후, `~/.claude/settings.json`의 `pluginConfigs` 에서 이러한 옵션을 설정할 수 있습니다:

| 옵션 | 설명 | 기본값 |
|------|------|--------|
| `skip_directories` | auto-worktree가 활성화되지 않아야 할 git 저장소 루트 경로의 쉼표 구분 목록 | (없음) |
| `pull_default_branch` | 세션 시작 시 origin에서 최신 기본 브랜치를 pull합니다. fast-forward만 사용하며, 로컬 변경사항은 절대 덮어쓰지 않습니다. 실패 시 조용히 계속합니다. | `true` |
| `sync_gitignored_writes` | worktree에서 작성된 gitignore된 파일을 자동으로 메인 저장소에 복사합니다. Write/Edit 도구 호출과 Bash 출력 리다이렉트를 모두 처리합니다. | `true` |
| `auto_return_to_default` | 세션 시작 시 비기본 브랜치에 있고 커밋되지 않은 변경사항이 없으면 자동으로 기본 브랜치로 전환합니다. | `true` |

### settings.json 예시

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

여기에 해당하는 루트 경로를 가진 저장소는 플러그인에 의해 완전히 무시됩니다 — worktree 강제도, 세션 시작 안내도 없습니다. 매칭은 git 저장소 루트를 기준으로 하므로, `/Users/me/notes`를 지정하면 Claude가 작업 중인 하위 디렉토리에 관계없이 전체 저장소를 건너뜁니다. 기본 브랜치에서 직접 편집하고 싶은 개인 저장소, 메모, 또는 임시 디렉토리에 유용합니다.

### pull_default_branch

활성화된 경우 (기본값), 플러그인은 세션 시작 시 `git pull --ff-only`를 실행하여 (8초 타임아웃) worktree 생성 전에 로컬 기본 브랜치가 최신 상태인지 확인합니다. pull이 실패하면 (예: 오프라인, 타임아웃, 히스토리 분기), 플러그인은 로컬 상태로 계속 진행하고 경고를 출력합니다. 이를 완전히 건너뛰려면 `false`로 설정하세요.

### auto_return_to_default

이 옵션은 **작업 브랜치를 기본 브랜치로 자동 전환할지 여부**만 제어합니다. 로컬 기본 브랜치 ref를 최신으로 유지하는 동작은 `pull_default_branch`의 책임이며, 이 옵션이 비활성화되어 있어도 작동합니다.

활성화된 경우 (기본값), 플러그인은 세션 시작 시 메인 저장소에서 Claude가 비기본 브랜치에 있는지 확인합니다. 그렇다면:

- **커밋되지 않은 변경사항이 없음** — 플러그인은 자동으로 `git checkout <default-branch>`를 실행하고 일반적인 pull + EnterWorktree 흐름을 계속합니다. Claude가 사용자에게 알릴 수 있도록 간단한 메시지가 출력됩니다.
- **커밋되지 않은 변경사항이 있음** — 플러그인은 전환 전에 commit과 push를 하라는 경고를 출력하고, 작업 중인 브랜치를 변경하지 않은 채 종료합니다.

`false`로 설정하면 자동 전환을 완전히 비활성화합니다. 비기본 브랜치는 전환되지 않으며, 경고도 출력되지 않습니다.

이 옵션과 독립적으로, `pull_default_branch=true`이고 Claude가 비기본 브랜치에 있을 때 플러그인은 백그라운드에서 `git fetch origin <default-branch>:<default-branch>`를 실행하여 사용자의 작업 트리를 건드리지 않고 로컬 기본 ref를 fast-forward로 진행합니다 (non-fast-forward 업데이트는 거부되며, 이 경우 기본 브랜치는 체크아웃되어 있지 않으므로 안전합니다). 짧은 알림은 로컬 기본 ref가 실제로 이동했을 때만 출력됩니다.

untracked 파일은 dirty 검사에서 "변경"으로 간주되지 않으며, 브랜치 전환 시에도 안전하게 유지됩니다.

### sync_gitignored_writes

활성화된 경우 (기본값), worktree 내의 gitignore된 경로에 작성된 파일은 자동으로 메인 저장소에 복사됩니다. 이를 통해 `dist/`나 `build/` 같은 디렉토리의 빌드 산출물이 worktree 제거 시 손실되지 않도록 합니다.

**동기화되는 항목:**
- Write/Edit 도구를 통해 저장소 내 gitignore된 경로에 작성된 파일
- Bash 출력 리다이렉트(`>`, `>>`)를 통해 저장소 내 gitignore된 경로에 작성된 파일

**동기화되지 않는 항목:**
- 명령에 의해 간접적으로 생성된 파일 (예: `npm install`로 생성된 `node_modules/`)
- 저장소 외부 파일 (예: `/tmp/...`)
- 추적 중인 (gitignore되지 않은) 경로의 파일

이 동작을 완전히 비활성화하려면 `false`로 설정하세요.

## 세션 우회

플러그인이 작업을 잘못 차단하는 경우, 자연어로 Claude에게 현재 세션에서 worktree 강제를 건너뛰도록 요청할 수 있습니다 — 어떤 표현이든 가능합니다:

- "worktree作らなくていい" / "auto-worktree 無視して"
- "don't need a worktree" / "skip worktree" / "no worktree please"
- 또는 같은 의도를 표현하는 다른 어떤 방식이든

Claude가 `touch <bypass-flag-file>`을 실행하여 나머지 세션 동안 강제를 비활성화합니다. 플래그는 시스템 임시 디렉토리(`$TMPDIR` / `$TMP` / `$TEMP` / `/tmp`)에 저장되며, 다른 세션에는 영향을 주지 **않습니다**.

## 정리

Worktree 정리는 Claude Code의 내장 `ExitWorktree` 도구에 의해 처리됩니다. worktree 내에서 세션이 종료되면, 사용자에게 유지 또는 제거 여부를 묻습니다.

수동 정리의 경우:

```bash
git worktree list          # 모든 worktree 확인
git worktree remove <path> # 특정 worktree 제거
git worktree prune         # 오래된 참조 정리
```

## 파일 구조

```
auto-worktree/
├── .claude-plugin/
│   ├── marketplace.json     # Marketplace 정의
│   └── plugin.json          # 플러그인 매니페스트
├── hooks/
│   ├── hooks.json           # 훅 정의
│   ├── session-start.sh     # 세션 시작 시 사전 안내
│   ├── pre-tool-use.sh      # 안전망: 차단 후 EnterWorktree로 안내
│   ├── post-tool-use.sh     # gitignore된 쓰기를 메인 저장소에 동기화
│   └── stop.sh              # 세션 종료 요약
├── lib/
│   ├── json.sh              # 공유 JSON 파싱 헬퍼
│   ├── worktree.sh          # Git worktree 감지 헬퍼
│   ├── bash-filter.sh       # 변경 감지 휴리스틱
│   ├── bypass.sh            # 세션 우회 플래그 헬퍼
│   └── config.sh            # 사용자 설정 헬퍼
├── tests/
│   ├── run-tests.sh         # 테스트 실행기
│   ├── test-bash-filter.sh  # 변경 감지 테스트
│   ├── test-bypass.sh       # 세션 우회 테스트
│   ├── test-config.sh       # 설정 단위 테스트
│   ├── test-config-integration.sh # 설정 통합 테스트
│   ├── test-json.sh         # JSON 파싱 테스트
│   ├── test-post-tool-use.sh # PostToolUse 통합 테스트
│   ├── test-worktree.sh     # Worktree 감지 테스트
│   ├── test-pre-tool-use.sh # PreToolUse 통합 테스트
│   ├── test-session-start.sh # SessionStart 훅 테스트
│   └── test-stop.sh         # Stop 훅 테스트
├── docs/
│   └── i18n/                # 번역된 README
├── LICENSE
└── README.md
```

## 테스트 실행

```bash
bash tests/run-tests.sh
```

## 요구 사항

- `git` 2.5+ (worktree 지원)
- `jq` (권장) 또는 `python3` (대체) — JSON 파싱용
- `bash` 4+

## 라이선스

MIT
