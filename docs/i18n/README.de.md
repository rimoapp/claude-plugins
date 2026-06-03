# claude-plugin-auto-worktree

[English](../../README.md) | [日本語](README.ja.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [中文](README.zh-cn.md) | [Русский](README.ru.md) | [Português](README.pt.md) | [한국어](README.ko.md)

Ein Claude-Code-Plugin, das Claude automatisch in einen Git-Worktree umleitet, bevor Dateien geändert werden. So ist sicheres paralleles Arbeiten ohne Git-Konflikte möglich.

## Problem

Wenn mehrere Claude-Code-Sitzungen gleichzeitig am selben Repository arbeiten, können Dateiänderungen zu Konflikten führen. Nicht-Entwickler, die mit Git-Branching nicht vertraut sind, können Arbeit verlieren oder auf verwirrende Merge-Konflikte stoßen.

## Designprinzip

**Im Normalbetrieb finden Codeänderungen in Worktree-Branches statt.** Dies ist ein Leitprinzip, keine strikte Erzwingung für jeden Befehl.

Das Plugin ist so konzipiert, dass es minimal invasiv ist:

- **`Write`/`Edit` auf verfolgte Dateien** im Haupt-Repository werden blockiert — Claude wird aufgefordert, zuerst einen Worktree zu erstellen
- **`Bash`-Befehle** sind fast vollständig erlaubt — nur Ausgabeumleitungen (`>`, `>>`) auf verfolgte Dateien im Repository werden blockiert
- **Git-Befehle** (`checkout`, `reset`, `merge`, `rebase`, `stash` usw.) sind immer erlaubt — es wird nicht davon ausgegangen, dass der aktuelle Hauptbranch korrekt ist, und Benutzer müssen ihn möglicherweise reparieren oder verwalten
- **Paketmanager, Systembefehle, Datei-Utilities** sind alle erlaubt
- **Schreibvorgänge in `/tmp`, gitignorierte Pfade oder Dateien außerhalb des Repositorys** sind immer erlaubt (Plan-Modus, Speicher, temporäre Dateien funktionieren alle)

## Lösung

Dieses Plugin fängt `Write`-, `Edit`- und `Bash`-Tool-Aufrufe über einen `PreToolUse`-Hook ab. Wenn Claude versucht, eine verfolgte Datei im Haupt-Repository zu schreiben oder zu bearbeiten, wird:

1. Die Änderung blockiert (Exit-Code 2)
2. Claude angewiesen, das eingebaute `EnterWorktree`-Tool aufzurufen
3. Claude erstellt einen isolierten Worktree und wiederholt die Aktion dort

Jede Claude-Sitzung erhält ihren eigenen isolierten Worktree und Branch, sodass parallele Sitzungen niemals in Konflikt geraten.

## Installation

### Von GitHub (empfohlen)

In Claude Code ausführen:

```
/plugin marketplace add rimoapp/claude-plugin-auto-worktree
/plugin install auto-worktree@rimo
```

Nach der Installation bleibt das Plugin über Sitzungen hinweg bestehen. Sie können es jederzeit aktivieren/deaktivieren:

```
/plugin disable auto-worktree@rimo
/plugin enable auto-worktree@rimo
```

### Aus einem lokalen Verzeichnis

Für Entwicklung oder Tests:

```bash
claude --plugin-dir /path/to/claude-plugin-auto-worktree
```

## Funktionsweise

```
Benutzer startet Claude im Haupt-Repository
         │
         ▼
SessionStart-Hook wird ausgelöst ─── Auf Default-Branch? → Weist Claude proaktiv an, EnterWorktree zu verwenden
         │
         ▼
Claude ruft EnterWorktree auf → erstellt .claude/worktrees/<name>/
         │
         ▼
Alle Dateiänderungen erfolgen sicher im Worktree
         │
         ▼
Sitzung endet → Stop-Hook gibt Zusammenfassung aus (Branch, nicht committete Änderungen)
```

Falls Claude die proaktive Anweisung überspringt, dient der **PreToolUse-Hook** als Sicherheitsnetz:

```
Claude versucht, eine Datei auf dem Default-Branch zu schreiben/bearbeiten
         │
         ▼
PreToolUse-Hook fängt ab ──────── Bereits in einem Worktree? → Erlauben
         │
         ▼
Blockiert Aktion (Exit 2) + weist Claude an, EnterWorktree aufzurufen
```

### Worktree-Speicherort

Worktrees werden durch das eingebaute `EnterWorktree`-Tool von Claude Code innerhalb des Repositorys erstellt:

```
my-project/
├── .claude/
│   └── worktrees/
│       ├── humble-prancing-conway/    # Sitzung 1
│       └── brave-dancing-turing/      # Sitzung 2
├── src/
└── ...
```

Jeder Worktree erhält einen Branch namens `worktree-<session-name>`.

### Bash-Befehlsfilterung

Das Plugin blockiert nur Bash-Befehle, die Ausgabeumleitungen (`>`, `>>`) verwenden, um in verfolgte Dateien innerhalb des Repositorys zu schreiben. Alles andere ist erlaubt:

- **Erlaubt**: Alle Befehle ohne Umleitungen (`git checkout`, `npm install`, `rm`, `touch`, `mv` usw.), Umleitungen nach `/tmp`, `/dev/null`, gitignorierte Dateien oder Pfade außerhalb des Repositorys
- **Blockiert**: `echo "data" > tracked-file.txt`, `cat input >> src/main.py` usw. (Umleitungen in verfolgte Repository-Dateien)

## Konfiguration

Das Plugin unterstützt benutzerkonfigurierbare Optionen über den `userConfig`-Mechanismus von Claude Code. Nach der Installation des Plugins können Sie diese Optionen in Ihrer `~/.claude/settings.json` unter `pluginConfigs` festlegen:

| Option | Beschreibung | Standard |
|--------|-------------|---------|
| `skip_directories` | Kommagetrennte Liste von Git-Repository-Wurzelpfaden, in denen auto-worktree nicht aktiviert werden soll | (leer) |
| `pull_default_branch` | Den neuesten Default-Branch von Origin beim Sitzungsstart pullen. Verwendet ausschließlich Fast-Forward — lokale Änderungen werden niemals überschrieben. Bei Fehler wird stillschweigend fortgefahren. | `true` |
| `sync_gitignored_writes` | Automatisch gitignorierte Dateien, die in einem Worktree geschrieben wurden, zurück ins Haupt-Repository kopieren. Deckt Write/Edit-Tool-Aufrufe und Bash-Ausgabeumleitungen ab. | `true` |
| `auto_return_to_default` | Wechselt beim Sitzungsstart automatisch zum Default-Branch zurück, wenn man sich auf einem Nicht-Default-Branch ohne uncommittete Änderungen befindet. | `true` |

### Beispiel settings.json

```json
{
  "pluginConfigs": {
    "auto-worktree@rimo": {
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

Repositorys, deren Wurzelpfad einem Eintrag hier entspricht, werden vom Plugin vollständig ignoriert — keine Worktree-Erzwingung, keine Sitzungsstart-Anweisungen. Der Abgleich basiert auf dem Git-Repository-Wurzelpfad, sodass die Angabe von `/Users/me/notes` das gesamte Repository überspringt, unabhängig davon, in welchem Unterverzeichnis Claude arbeitet. Nützlich für persönliche Repositorys, Notizen oder Scratch-Verzeichnisse, in denen Sie direkt auf dem Default-Branch bearbeiten möchten.

### pull_default_branch

Wenn aktiviert (Standardeinstellung), führt das Plugin beim Sitzungsstart `git pull --ff-only` aus (mit einem Timeout von 8 Sekunden), um sicherzustellen, dass der lokale Default-Branch aktuell ist, bevor ein Worktree erstellt wird. Wenn der Pull fehlschlägt (z. B. offline, Timeout, divergierte Historie), fährt das Plugin mit dem lokalen Stand fort und gibt eine Warnung aus. Setzen Sie den Wert auf `false`, um dies vollständig zu überspringen.

### auto_return_to_default

Diese Option steuert ausschließlich, **ob der Arbeits-Branch automatisch auf den Default-Branch zurückgewechselt wird**. Das Aktualisieren der lokalen Default-Ref ist eine separate Aufgabe, die von `pull_default_branch` erledigt wird und auch dann läuft, wenn diese Option deaktiviert ist.

Wenn aktiviert (Standardeinstellung), prüft das Plugin beim Sitzungsstart, ob sich Claude im Haupt-Repository auf einem Nicht-Default-Branch befindet. Falls ja:

- **Keine uncommitteten Änderungen** — Das Plugin führt automatisch `git checkout <default-branch>` aus und setzt den normalen Pull- + EnterWorktree-Ablauf fort. Eine kurze Meldung wird ausgegeben, damit Claude den Benutzer informieren kann.
- **Uncommittete Änderungen vorhanden** — Das Plugin gibt eine Warnung aus, mit der Bitte, vor dem Wechsel zu committen und zu pushen, und beendet sich, ohne den aktuellen Branch zu ändern.

Auf `false` setzen, um den automatischen Wechsel vollständig zu deaktivieren. Nicht-Default-Branches werden weder gewechselt noch wird eine Warnung ausgegeben.

Unabhängig von dieser Option führt das Plugin bei aktiviertem `pull_default_branch` und einem Nicht-Default-Branch im Hintergrund `git fetch origin <default-branch>:<default-branch>` aus, was die lokale Default-Ref per Fast-Forward voranbringt, ohne den Working Tree zu stören (Non-Fast-Forward-Updates werden abgelehnt, und der Default-Branch ist in diesem Pfad nicht ausgecheckt). Eine kurze Meldung wird nur ausgegeben, wenn die lokale Default-Ref tatsächlich vorangerückt ist.

Untracked-Dateien gelten bei der Dirty-Prüfung nicht als „Änderungen" — sie werden bei einem Branch-Wechsel sicher übernommen.

### sync_gitignored_writes

Wenn aktiviert (Standardeinstellung), werden Dateien, die in gitignorierte Pfade innerhalb eines Worktrees geschrieben werden, automatisch zurück ins Haupt-Repository kopiert. Dies stellt sicher, dass Build-Artefakte in Verzeichnissen wie `dist/` oder `build/` nicht verloren gehen, wenn der Worktree entfernt wird.

**Was synchronisiert wird:**
- Dateien, die über Write/Edit-Tools in gitignorierte Pfade innerhalb des Repositorys geschrieben werden
- Bash-Ausgabeumleitungen (`>`, `>>`) in gitignorierte Pfade innerhalb des Repositorys

**Was NICHT synchronisiert wird:**
- Dateien, die indirekt durch Befehle erstellt werden (z. B. `npm install` erstellt `node_modules/`)
- Dateien außerhalb des Repositorys (z. B. `/tmp/...`)
- Dateien auf verfolgten (nicht-gitignorierten) Pfaden

Setzen Sie den Wert auf `false`, um dieses Verhalten vollständig zu deaktivieren.

## Sitzungsumgehung

Wenn das Plugin fälschlicherweise eine Aktion blockiert, können Sie Claude bitten, die Worktree-Erzwingung für die aktuelle Sitzung in natürlicher Sprache zu überspringen — jede Formulierung funktioniert:

- "worktree作らなくていい" / "auto-worktree 無視して"
- "don't need a worktree" / "skip worktree" / "no worktree please"
- Oder jede andere Art, dieselbe Absicht auszudrücken

Claude führt `touch <bypass-flag-file>` aus, um die Erzwingung für den Rest der Sitzung zu deaktivieren. Das Flag wird im temporären Systemverzeichnis (`$TMPDIR` / `$TMP` / `$TEMP` / `/tmp`) gespeichert und beeinflusst **keine** anderen Sitzungen.

## Bereinigung

Die Worktree-Bereinigung wird durch das eingebaute `ExitWorktree`-Tool von Claude Code durchgeführt. Wenn eine Sitzung in einem Worktree endet, wird der Benutzer gefragt, ob er ihn behalten oder entfernen möchte.

Für manuelle Bereinigung:

```bash
git worktree list          # Alle Worktrees anzeigen
git worktree remove <path> # Einen bestimmten Worktree entfernen
git worktree prune         # Veraltete Referenzen bereinigen
```

## Dateistruktur

```
claude-plugin-auto-worktree/
├── .claude-plugin/
│   ├── marketplace.json     # Marketplace-Definition
│   └── plugin.json          # Plugin-Manifest
├── hooks/
│   ├── hooks.json           # Hook-Definitionen
│   ├── session-start.sh     # Proaktive Anweisung beim Sitzungsstart
│   ├── pre-tool-use.sh      # Sicherheitsnetz: Blockieren und zu EnterWorktree umleiten
│   ├── post-tool-use.sh     # Gitignorierte Schreibvorgänge ins Haupt-Repository synchronisieren
│   └── stop.sh              # Zusammenfassung am Sitzungsende
├── lib/
│   ├── json.sh              # Gemeinsame JSON-Parsing-Hilfsfunktionen
│   ├── worktree.sh          # Git-Worktree-Erkennungshilfen
│   ├── bash-filter.sh       # Heuristik zur Mutationserkennung
│   ├── bypass.sh            # Hilfsfunktionen für Sitzungsumgehungs-Flag
│   └── config.sh            # Hilfsfunktionen für Benutzerkonfiguration
├── tests/
│   ├── run-tests.sh         # Testrunner
│   ├── test-bash-filter.sh  # Tests zur Mutationserkennung
│   ├── test-bypass.sh       # Tests zur Sitzungsumgehung
│   ├── test-config.sh       # Konfigurations-Unit-Tests
│   ├── test-config-integration.sh # Konfigurations-Integrationstests
│   ├── test-json.sh         # JSON-Parsing-Tests
│   ├── test-post-tool-use.sh # PostToolUse-Integrationstests
│   ├── test-worktree.sh     # Worktree-Erkennungstests
│   ├── test-pre-tool-use.sh # PreToolUse-Integrationstests
│   ├── test-session-start.sh # SessionStart-Hook-Tests
│   └── test-stop.sh         # Stop-Hook-Tests
├── docs/
│   └── i18n/                # Übersetzte READMEs
├── LICENSE
└── README.md
```

## Tests ausführen

```bash
bash tests/run-tests.sh
```

## Voraussetzungen

- `git` 2.5+ (Worktree-Unterstützung)
- `jq` (bevorzugt) oder `python3` (Fallback) für JSON-Parsing
- `bash` 4+

## Lizenz

MIT
