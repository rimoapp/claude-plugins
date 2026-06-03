# claude-plugin-auto-worktree

[English](../../README.md) | [日本語](README.ja.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [中文](README.zh-cn.md) | [Русский](README.ru.md) | [Português](README.pt.md) | [한국어](README.ko.md)

Un plugin de Claude Code que redirige automáticamente a Claude a un git worktree antes de modificar archivos, permitiendo trabajo paralelo seguro sin conflictos de git.

## Problema

Cuando múltiples sesiones de Claude Code trabajan simultáneamente en el mismo repositorio, las modificaciones de archivos pueden entrar en conflicto. Los usuarios que no están familiarizados con las ramas de git pueden perder trabajo o encontrarse con conflictos de merge confusos.

## Política de diseño

**Durante el uso normal, los cambios de código ocurren en ramas de worktree.** Este es un principio rector, no una imposición estricta en cada comando.

El plugin está diseñado para ser mínimamente invasivo:

- **`Write`/`Edit` en archivos rastreados** del repositorio principal son bloqueados — Claude es redirigido para crear primero un worktree
- **Comandos `Bash`** están permitidos casi en su totalidad — solo se bloquean las redirecciones de salida (`>`, `>>`) hacia archivos rastreados del repositorio
- **Comandos Git** (`checkout`, `reset`, `merge`, `rebase`, `stash`, etc.) siempre están permitidos — no se asume que la rama principal actual sea correcta, y los usuarios pueden necesitar corregirla o gestionarla
- **Gestores de paquetes, comandos del sistema, utilidades de archivos** están todos permitidos
- **Escrituras en `/tmp`, rutas ignoradas por git o archivos fuera del repositorio** siempre están permitidas (Plan Mode, memoria, archivos temporales funcionan correctamente)

## Solución

Este plugin intercepta las llamadas a las herramientas `Write`, `Edit` y `Bash` mediante un hook `PreToolUse`. Cuando Claude intenta escribir o editar un archivo rastreado en el repositorio principal, el plugin:

1. Bloquea la modificación (código de salida 2)
2. Instruye a Claude para que llame a la herramienta integrada `EnterWorktree`
3. Claude crea un worktree aislado y reintenta la acción allí

Cada sesión de Claude obtiene su propio worktree y rama aislados, por lo que las sesiones paralelas nunca entran en conflicto.

## Instalación

### Desde GitHub (recomendado)

En Claude Code, ejecuta:

```
/plugin marketplace add rimoapp/claude-plugin-auto-worktree
/plugin install auto-worktree@rimo
```

Una vez instalado, el plugin persiste entre sesiones. Puedes habilitarlo o deshabilitarlo en cualquier momento:

```
/plugin disable auto-worktree@rimo
/plugin enable auto-worktree@rimo
```

### Desde un directorio local

Para desarrollo o pruebas:

```bash
claude --plugin-dir /path/to/claude-plugin-auto-worktree
```

## Cómo funciona

```
El usuario inicia Claude en el repositorio principal
         │
         ▼
Se activa el hook SessionStart ─── ¿En rama por defecto? → Indica proactivamente a Claude que use EnterWorktree
         │
         ▼
Claude llama a EnterWorktree → crea .claude/worktrees/<nombre>/
         │
         ▼
Todas las modificaciones de archivos ocurren de forma segura en el worktree
         │
         ▼
La sesión termina → El hook Stop imprime un resumen (rama, cambios sin confirmar)
```

Si Claude omite la instrucción proactiva, el **hook PreToolUse** actúa como red de seguridad:

```
Claude intenta hacer Write/Edit de un archivo en la rama por defecto
         │
         ▼
El hook PreToolUse intercepta ──────── ¿Ya está en un worktree? → Permitir
         │
         ▼
Bloquea la acción (exit 2) + indica a Claude que llame a EnterWorktree
```

### Ubicación del worktree

Los worktrees son creados por la herramienta integrada `EnterWorktree` de Claude Code dentro del repositorio:

```
my-project/
├── .claude/
│   └── worktrees/
│       ├── humble-prancing-conway/    # Sesión 1
│       └── brave-dancing-turing/      # Sesión 2
├── src/
└── ...
```

Cada worktree obtiene una rama llamada `worktree-<nombre-de-sesión>`.

### Filtrado de comandos Bash

El plugin solo bloquea comandos Bash que usen redirecciones de salida (`>`, `>>`) para escribir en archivos rastreados dentro del repositorio. Todo lo demás está permitido:

- **Permitido**: todos los comandos sin redirecciones (`git checkout`, `npm install`, `rm`, `touch`, `mv`, etc.), redirecciones a `/tmp`, `/dev/null`, archivos ignorados por git o rutas fuera del repositorio
- **Bloqueado**: `echo "data" > tracked-file.txt`, `cat input >> src/main.py`, etc. (redirecciones a archivos rastreados del repositorio)

## Configuración

El plugin admite opciones configurables por el usuario mediante el mecanismo `userConfig` de Claude Code. Después de instalar el plugin, puedes establecer estas opciones en tu `~/.claude/settings.json` bajo `pluginConfigs`:

| Opción | Descripción | Valor por defecto |
|--------|-------------|-------------------|
| `skip_directories` | Lista separada por comas de rutas raíz de repositorios git donde auto-worktree no debe activarse | (vacío) |
| `pull_default_branch` | Descarga la última versión de la rama por defecto desde origin al iniciar la sesión. Usa solo fast-forward — los cambios locales nunca se sobrescriben. Continúa silenciosamente en caso de fallo. | `true` |
| `sync_gitignored_writes` | Copia automáticamente los archivos ignorados por git escritos en un worktree de vuelta al repositorio principal. Cubre las llamadas a las herramientas Write/Edit y las redirecciones de salida de Bash. | `true` |
| `auto_return_to_default` | Cambia automáticamente a la rama por defecto al iniciar la sesión si estás en una rama no por defecto sin cambios sin confirmar. | `true` |

### Ejemplo de settings.json

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

Los repositorios cuya ruta raíz coincida con una entrada aquí serán completamente ignorados por el plugin — sin imposición de worktree, sin instrucciones al inicio de sesión. La coincidencia se basa en la raíz del repositorio git, por lo que especificar `/Users/me/notes` omitirá todo el repositorio independientemente del subdirectorio en el que Claude esté trabajando. Útil para repositorios personales, notas o directorios de prueba donde deseas editar directamente en la rama por defecto.

### pull_default_branch

Cuando está habilitado (valor por defecto), el plugin ejecuta `git pull --ff-only` al inicio de la sesión (con un tiempo límite de 8 segundos) para asegurar que la rama local por defecto esté actualizada antes de crear un worktree. Si el pull falla (p. ej., sin conexión, tiempo agotado, historial divergente), el plugin continúa con el estado local e imprime una advertencia. Establece en `false` para omitir esto por completo.

### auto_return_to_default

Esta opción controla únicamente **si la rama de trabajo se cambia automáticamente de vuelta a la rama por defecto**. Mantener actualizada la ref local de la rama por defecto es responsabilidad de `pull_default_branch` y se ejecuta incluso cuando esta opción está deshabilitada.

Cuando está habilitado (valor por defecto), el plugin verifica al iniciar la sesión si Claude está en una rama no por defecto en el repositorio principal. Si es así:

- **Sin cambios sin confirmar** — el plugin ejecuta automáticamente `git checkout <default-branch>` y continúa con el flujo normal de pull + EnterWorktree. Se imprime un breve aviso para que Claude pueda informar al usuario.
- **Hay cambios sin confirmar** — el plugin imprime una advertencia pidiendo al usuario que haga commit y push antes de cambiar, y luego sale sin modificar la rama de trabajo.

Establece en `false` para deshabilitar por completo el cambio automático. Las ramas no por defecto no se cambian ni se imprime ninguna advertencia.

Independientemente de esta opción, cuando `pull_default_branch=true` y Claude está en una rama no por defecto, el plugin ejecuta `git fetch origin <default-branch>:<default-branch>` en segundo plano para avanzar la ref local por defecto mediante fast-forward sin alterar el árbol de trabajo del usuario (las actualizaciones que no son fast-forward se rechazan, y la rama por defecto no está checked out en esta ruta). Se imprime un breve aviso solo cuando la ref local por defecto realmente avanzó.

Los archivos sin seguimiento (untracked) no se consideran "cambios" en la verificación de estado dirty; se mantienen de forma segura al cambiar de rama.

### sync_gitignored_writes

Cuando está habilitado (valor por defecto), los archivos escritos en rutas ignoradas por git dentro de un worktree se copian automáticamente de vuelta al repositorio principal. Esto asegura que los artefactos de compilación en directorios como `dist/` o `build/` no se pierdan cuando el worktree se elimina.

**Lo que se sincroniza:**
- Archivos escritos mediante las herramientas Write/Edit en rutas ignoradas por git dentro del repositorio
- Redirecciones de salida de Bash (`>`, `>>`) a rutas ignoradas por git dentro del repositorio

**Lo que NO se sincroniza:**
- Archivos creados indirectamente por comandos (p. ej., `npm install` creando `node_modules/`)
- Archivos fuera del repositorio (p. ej., `/tmp/...`)
- Archivos en rutas rastreadas (no ignoradas por git)

Establece en `false` para deshabilitar este comportamiento por completo.

## Omisión de sesión

Si el plugin bloquea incorrectamente una acción, puedes pedirle a Claude que omita la imposición de worktree para la sesión actual usando lenguaje natural — cualquier formulación funciona:

- "worktree作らなくていい" / "auto-worktree 無視して"
- "don't need a worktree" / "skip worktree" / "no worktree please"
- "no necesito un worktree" / "omitir worktree" / "sin worktree por favor"
- O cualquier otra forma de expresar la misma intención

Claude ejecutará `touch <bypass-flag-file>` para deshabilitar la imposición durante el resto de la sesión. La bandera se almacena en el directorio temporal del sistema (`$TMPDIR` / `$TMP` / `$TEMP` / `/tmp`) y **no** afecta a otras sesiones.

## Limpieza

La limpieza de worktrees es gestionada por la herramienta integrada `ExitWorktree` de Claude Code. Cuando una sesión termina mientras está en un worktree, se le pregunta al usuario si desea conservarlo o eliminarlo.

Para limpieza manual:

```bash
git worktree list          # Ver todos los worktrees
git worktree remove <path> # Eliminar un worktree específico
git worktree prune         # Limpiar referencias obsoletas
```

## Estructura de archivos

```
claude-plugin-auto-worktree/
├── .claude-plugin/
│   ├── marketplace.json     # Definición del marketplace
│   └── plugin.json          # Manifiesto del plugin
├── hooks/
│   ├── hooks.json           # Definiciones de hooks
│   ├── session-start.sh     # Instrucción proactiva al inicio de sesión
│   ├── pre-tool-use.sh      # Red de seguridad: bloquear y redirigir a EnterWorktree
│   ├── post-tool-use.sh     # Sincronizar escrituras ignoradas por git al repositorio principal
│   └── stop.sh              # Resumen al final de sesión
├── lib/
│   ├── json.sh              # Utilidades compartidas de análisis JSON
│   ├── worktree.sh          # Utilidades de detección de git worktree
│   ├── bash-filter.sh       # Heurística de detección de mutaciones
│   ├── bypass.sh            # Utilidades de bandera de omisión de sesión
│   └── config.sh            # Utilidades de configuración de usuario
├── tests/
│   ├── run-tests.sh         # Ejecutor de pruebas
│   ├── test-bash-filter.sh  # Pruebas de detección de mutaciones
│   ├── test-bypass.sh       # Pruebas de omisión de sesión
│   ├── test-config.sh       # Pruebas unitarias de configuración
│   ├── test-config-integration.sh # Pruebas de integración de configuración
│   ├── test-json.sh         # Pruebas de análisis JSON
│   ├── test-post-tool-use.sh # Pruebas de integración PostToolUse
│   ├── test-worktree.sh     # Pruebas de detección de worktree
│   ├── test-pre-tool-use.sh # Pruebas de integración PreToolUse
│   ├── test-session-start.sh # Pruebas del hook SessionStart
│   └── test-stop.sh         # Pruebas del hook Stop
├── docs/
│   └── i18n/                # READMEs traducidos
├── LICENSE
└── README.md
```

## Ejecución de pruebas

```bash
bash tests/run-tests.sh
```

## Requisitos

- `git` 2.5+ (soporte de worktree)
- `jq` (preferido) o `python3` (alternativa) para análisis JSON
- `bash` 4+

## Licencia

MIT
