# auto-worktree

[English](../../README.md) | [日本語](README.ja.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [中文](README.zh-cn.md) | [Русский](README.ru.md) | [Português](README.pt.md) | [한국어](README.ko.md)

Um plugin para o Claude Code que redireciona automaticamente o Claude para um git worktree antes de modificar arquivos, permitindo trabalho paralelo seguro sem conflitos no git.

## Problema

Quando múltiplas sessões do Claude Code trabalham no mesmo repositório simultaneamente, as modificações de arquivos podem gerar conflitos. Pessoas que não são engenheiras e não estão familiarizadas com branches do git podem perder trabalho ou encontrar conflitos de merge confusos.

## Política de Design

**Durante o uso normal, as alterações de código acontecem em branches de worktree.** Este é um princípio orientador, não uma imposição rígida em cada comando.

O plugin foi projetado para ser minimamente invasivo:

- **`Write`/`Edit` em arquivos rastreados** no repositório principal são bloqueados — o Claude é redirecionado para criar um worktree primeiro
- **Comandos `Bash`** são quase todos permitidos — apenas redirecionamentos de saída (`>`, `>>`) para arquivos rastreados do repositório são bloqueados
- **Comandos Git** (`checkout`, `reset`, `merge`, `rebase`, `stash`, etc.) são sempre permitidos — não se assume que a branch principal atual está correta, e os usuários podem precisar corrigir ou gerenciá-la
- **Gerenciadores de pacotes, comandos do sistema, utilitários de arquivo** são todos permitidos
- **Escritas em `/tmp`, caminhos ignorados pelo git ou arquivos fora do repositório** são sempre permitidas (Plan Mode, memória, arquivos temporários funcionam normalmente)

## Solução

Este plugin intercepta chamadas das ferramentas `Write`, `Edit` e `Bash` por meio de um hook `PreToolUse`. Quando o Claude tenta escrever ou editar um arquivo rastreado no repositório principal, o plugin:

1. Bloqueia a modificação (código de saída 2)
2. Instrui o Claude a chamar a ferramenta integrada `EnterWorktree`
3. O Claude cria um worktree isolado e tenta a ação novamente lá

Cada sessão do Claude recebe seu próprio worktree e branch isolados, de forma que sessões paralelas nunca entram em conflito.

## Instalação

### A partir do GitHub (recomendado)

No Claude Code, execute:

```
/plugin marketplace add rimoapp/claude-plugins
/plugin install auto-worktree@rimo-tools
```

Após a instalação, o plugin persiste entre sessões. Você pode ativá-lo ou desativá-lo a qualquer momento:

```
/plugin disable auto-worktree@rimo-tools
/plugin enable auto-worktree@rimo-tools
```

### A partir de um diretório local

Para desenvolvimento ou testes:

```bash
claude --plugin-dir /path/to/claude-plugins/plugins/auto-worktree
```

## Como Funciona

```
Usuário inicia o Claude no repositório principal
         │
         ▼
Hook SessionStart é acionado ─── Na branch padrão? → Instrui proativamente o Claude a usar EnterWorktree
         │
         ▼
Claude chama EnterWorktree → cria .claude/worktrees/<nome>/
         │
         ▼
Todas as modificações de arquivos acontecem com segurança no worktree
         │
         ▼
Sessão termina → Hook Stop exibe resumo (branch, alterações não commitadas)
```

Se o Claude ignorar a instrução proativa, o **hook PreToolUse** atua como rede de segurança:

```
Claude tenta fazer Write/Edit de um arquivo na branch padrão
         │
         ▼
Hook PreToolUse intercepta ──────── Já está em um worktree? → Permitir
         │
         ▼
Bloqueia a ação (exit 2) + instrui o Claude a chamar EnterWorktree
```

### Localização do Worktree

Os worktrees são criados pela ferramenta integrada `EnterWorktree` do Claude Code dentro do repositório:

```
my-project/
├── .claude/
│   └── worktrees/
│       ├── humble-prancing-conway/    # Sessão 1
│       └── brave-dancing-turing/      # Sessão 2
├── src/
└── ...
```

Cada worktree recebe uma branch chamada `worktree-<nome-da-sessão>`.

### Filtragem de Comandos Bash

O plugin bloqueia apenas comandos Bash que usam redirecionamentos de saída (`>`, `>>`) para escrever em arquivos rastreados dentro do repositório. Todo o resto é permitido:

- **Permitido**: todos os comandos sem redirecionamentos (`git checkout`, `npm install`, `rm`, `touch`, `mv`, etc.), redirecionamentos para `/tmp`, `/dev/null`, arquivos ignorados pelo git ou caminhos fora do repositório
- **Bloqueado**: `echo "data" > tracked-file.txt`, `cat input >> src/main.py`, etc. (redirecionamentos para arquivos rastreados do repositório)

## Configuração

O plugin suporta opções configuráveis pelo usuário por meio do mecanismo `userConfig` do Claude Code. Após instalar o plugin, você pode definir essas opções no seu `~/.claude/settings.json` em `pluginConfigs`:

| Opção | Descrição | Padrão |
|-------|-----------|--------|
| `skip_directories` | Lista de caminhos raiz de repositórios git separados por vírgula onde o auto-worktree não deve ser ativado | (vazio) |
| `pull_default_branch` | Faz pull da branch padrão mais recente do origin ao iniciar a sessão. Usa apenas fast-forward — alterações locais nunca são sobrescritas. Continua silenciosamente em caso de falha. | `true` |
| `sync_gitignored_writes` | Copia automaticamente arquivos ignorados pelo git escritos em um worktree de volta para o repositório principal. Cobre chamadas das ferramentas Write/Edit e redirecionamentos de saída do Bash. | `true` |
| `auto_return_to_default` | Volta automaticamente para a branch padrão ao iniciar a sessão se você estiver em uma branch não padrão sem alterações não commitadas. | `true` |

### Exemplo de settings.json

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

Repositórios cujo caminho raiz corresponda a uma entrada aqui serão completamente ignorados pelo plugin — sem imposição de worktree, sem instruções no início da sessão. A correspondência é baseada na raiz do repositório git, então especificar `/Users/me/notes` ignorará o repositório inteiro, independentemente do subdiretório em que o Claude esteja trabalhando. Útil para repositórios pessoais, anotações ou diretórios de rascunho onde você deseja editar diretamente na branch padrão.

### pull_default_branch

Quando habilitado (o padrão), o plugin executa `git pull --ff-only` no início da sessão (com timeout de 8 segundos) para garantir que a branch padrão local esteja atualizada antes de criar um worktree. Se o pull falhar (por exemplo, offline, timeout, histórico divergente), o plugin continua com o estado local e exibe um aviso. Defina como `false` para pular completamente.

### auto_return_to_default

Esta opção controla apenas **se a branch de trabalho é alternada automaticamente de volta para a branch padrão**. Manter a ref local da branch padrão atualizada é responsabilidade de `pull_default_branch` e é executada mesmo quando esta opção está desabilitada.

Quando habilitado (o padrão), o plugin verifica no início da sessão se o Claude está em uma branch não padrão no repositório principal. Se estiver:

- **Sem alterações não commitadas** — o plugin executa automaticamente `git checkout <default-branch>` e continua com o fluxo normal de pull + EnterWorktree. Uma breve mensagem é exibida para que o Claude possa informar o usuário.
- **Existem alterações não commitadas** — o plugin exibe um aviso pedindo ao usuário para fazer commit e push antes de trocar, e então sai sem modificar a branch de trabalho.

Defina como `false` para desabilitar completamente a troca automática. Branches não padrão não são trocadas e nenhum aviso é impresso.

Independentemente desta opção, quando `pull_default_branch=true` e o Claude está em uma branch não padrão, o plugin executa `git fetch origin <default-branch>:<default-branch>` em segundo plano para avançar a ref local padrão via fast-forward sem perturbar a árvore de trabalho do usuário (atualizações non-fast-forward são rejeitadas, e a branch padrão não está checked out neste caminho). Uma breve mensagem é impressa apenas quando a ref local padrão de fato avançou.

Arquivos não rastreados (untracked) não são considerados "alterações" na verificação de dirty — eles são preservados com segurança ao trocar de branch.

### sync_gitignored_writes

Quando habilitado (o padrão), arquivos escritos em caminhos ignorados pelo git dentro de um worktree são automaticamente copiados de volta para o repositório principal. Isso garante que artefatos de build em diretórios como `dist/` ou `build/` não sejam perdidos quando o worktree for removido.

**O que é sincronizado:**
- Arquivos escritos pelas ferramentas Write/Edit em caminhos ignorados pelo git dentro do repositório
- Redirecionamentos de saída do Bash (`>`, `>>`) para caminhos ignorados pelo git dentro do repositório

**O que NÃO é sincronizado:**
- Arquivos criados indiretamente por comandos (por exemplo, `npm install` criando `node_modules/`)
- Arquivos fora do repositório (por exemplo, `/tmp/...`)
- Arquivos em caminhos rastreados (não ignorados pelo git)

Defina como `false` para desativar completamente esse comportamento.

## Bypass de Sessão

Se o plugin bloquear uma ação incorretamente, você pode pedir ao Claude para pular a imposição do worktree na sessão atual usando linguagem natural — qualquer formulação funciona:

- "worktree作らなくていい" / "auto-worktree 無視して"
- "don't need a worktree" / "skip worktree" / "no worktree please"
- Ou qualquer outra forma de expressar a mesma intenção

O Claude executará `touch <bypass-flag-file>` para desativar a imposição pelo resto da sessão. O flag é armazenado no diretório temporário do sistema (`$TMPDIR` / `$TMP` / `$TEMP` / `/tmp`) e **não** afeta outras sessões.

## Limpeza

A limpeza de worktrees é gerenciada pela ferramenta integrada `ExitWorktree` do Claude Code. Quando uma sessão termina dentro de um worktree, o usuário é solicitado a manter ou remover o worktree.

Para limpeza manual:

```bash
git worktree list          # Ver todos os worktrees
git worktree remove <path> # Remover um worktree específico
git worktree prune         # Limpar referências obsoletas
```

## Estrutura de Arquivos

```
auto-worktree/
├── .claude-plugin/
│   ├── marketplace.json     # Definição do marketplace
│   └── plugin.json          # Manifesto do plugin
├── hooks/
│   ├── hooks.json           # Definições dos hooks
│   ├── session-start.sh     # Instrução proativa no início da sessão
│   ├── pre-tool-use.sh      # Rede de segurança: bloqueia e redireciona para EnterWorktree
│   ├── post-tool-use.sh     # Sincroniza escritas em arquivos ignorados pelo git para o repositório principal
│   └── stop.sh              # Resumo de fim de sessão
├── lib/
│   ├── json.sh              # Helpers compartilhados para parsing de JSON
│   ├── worktree.sh          # Helpers de detecção de worktree do git
│   ├── bash-filter.sh       # Heurística de detecção de mutação
│   ├── bypass.sh            # Helpers para flag de bypass de sessão
│   └── config.sh            # Helpers de configuração do usuário
├── tests/
│   ├── run-tests.sh         # Executor de testes
│   ├── test-bash-filter.sh  # Testes de detecção de mutação
│   ├── test-bypass.sh       # Testes de bypass de sessão
│   ├── test-config.sh       # Testes unitários de configuração
│   ├── test-config-integration.sh # Testes de integração de configuração
│   ├── test-json.sh         # Testes de parsing de JSON
│   ├── test-post-tool-use.sh # Testes de integração do PostToolUse
│   ├── test-worktree.sh     # Testes de detecção de worktree
│   ├── test-pre-tool-use.sh # Testes de integração do PreToolUse
│   ├── test-session-start.sh # Testes do hook SessionStart
│   └── test-stop.sh         # Testes do hook Stop
├── docs/
│   └── i18n/                # READMEs traduzidos
├── LICENSE
└── README.md
```

## Executando os Testes

```bash
bash tests/run-tests.sh
```

## Requisitos

- `git` 2.5+ (suporte a worktree)
- `jq` (preferido) ou `python3` (fallback) para parsing de JSON
- `bash` 4+

## Licença

MIT
