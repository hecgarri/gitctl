# gitctl

CLI en Bash para coordinar **desarrollo paralelo con agentes de IA** (Claude Code,
Codex, Gemini CLI…) usando **Git worktrees**, con verificación y revisión cruzada
ligadas a commits concretos y una puerta de integración basada en **evidencia**.

> Un agente que dice «los tests pasan» está haciendo una afirmación.
> gitctl ejecutando los tests sobre el commit exacto produce evidencia.
> Solo la evidencia (más una revisión ajena y tu aprobación) abre la puerta.

## Ideas clave

- **Aislamiento**: cada agente que escribe código tiene su propio worktree y su
  rama `gitctl/<tarea>/<agente>`, fuera del repositorio (`../<repo>.wt/`).
- **Huellas, no conversación**: los agentes no hablan entre sí. Cada ejecución deja
  huellas (commit con trailers `Gitctl-*`, prompt, log, mensaje final) y gitctl las
  entrega como entrada al siguiente paso (revisión, corrección).
- **Headless**: los agentes se ejecutan en modo no interactivo, en background y en
  paralelo, con límite de tiempo.
- **Ligado al SHA**: verificaciones, revisiones y aprobaciones se registran para un
  commit exacto. Un commit nuevo las invalida automáticamente.
- **Afirmación ≠ evidencia**: el veredicto de un revisor es una afirmación (`claim`);
  el exit code de un check medido por gitctl es evidencia (`evidence`).
- **Nada destructivo automático**: sin `push --force`, sin `reset --hard`, sin borrar
  ramas sin fusionar; los worktrees con cambios no se eliminan sin `--force`.

## Instalación

Requisitos: Linux (probado en Ubuntu), `bash` ≥ 4.4, `git` ≥ 2.38, `jq`, `flock`
y `timeout` (util-linux/coreutils). Opcionales: `gh` (PRs), `fzf` (menú), y los
agentes que quieras usar (`claude`, `codex`, `gemini`).

```bash
git clone <este-repo> ~/src/gitctl
cd ~/src/gitctl && make install        # enlace en ~/.local/bin/gitctl
gitctl doctor
```

## Uso rápido

```bash
cd mi-proyecto
gitctl init                       # crea .git/gitctl/ y un .gitctl.conf de ejemplo
echo 'check.test = make test' >> .gitctl.conf   # define la evidencia
git add .gitctl.conf && git commit -m "gitctl"

gitctl task new "Validar emails en el registro" --spec spec.md   # → t1
gitctl task assign t1 claude codex      # dos worktrees, dos ramas
gitctl run t1 --wait                    # ambos en paralelo, headless

gitctl verify t1 claude                 # checks en copia limpia del commit
gitctl review t1 claude --by codex      # codex revisa a claude (solo lectura)
gitctl fix t1 claude --wait             # si hubo request_changes o checks rojos
gitctl verify t1 claude && gitctl review t1 claude --by codex

gitctl approve t1 claude                # tu aprobación (interactiva)
gitctl gate t1 claude                   # ✓/✗ de todo lo anterior + conflictos
gitctl pr open t1 claude                # push + PR con el informe de evidencia
gitctl pr merge t1 claude               # solo si el HEAD del PR = commit evaluado y CI en verde
```

Sin argumentos, `gitctl` abre un menú interactivo (con `fzf` si está instalado).

## Comandos

| Comando | Qué hace |
|---|---|
| `init`, `doctor` | Preparar el repo; comprobar dependencias y agentes |
| `wt ls\|new\|show\|path\|open\|rm` | Gestión de worktrees |
| `task new\|ls\|show\|assign\|spec\|close` | Tareas y asignación de agentes |
| `agents` | Adaptadores disponibles |
| `run <tarea> [agente…]` | Lanzar agentes en background (`--wait`, `--timeout`) |
| `run status\|wait\|logs\|show\|stop` | Seguimiento de ejecuciones |
| `fix <tarea> <agente>` | Relanzar al autor con hallazgos y checks fallidos |
| `verify <tarea> <agente>` | Evidencia: checks sobre el commit exacto |
| `review <tarea> <autor> --by <revisor>` | Revisión cruzada de solo lectura |
| `approve <tarea> <agente>` | Aprobación humana ligada al commit |
| `gate <tarea> <agente>` | ¿Puede integrarse? (`--json` para scripts) |
| `pr open\|status\|merge` | Pull Requests vía `gh` |
| `log [tarea]` | Historial de eventos |

Cada comando acepta `--help`.

## Configuración (`.gitctl.conf`)

Formato `clave = valor`, **nunca se ejecuta** como código. Se lee siempre del
worktree principal, así que un agente no puede relajar los checks desde su rama.

```ini
base = main
check.test = make test             # los checks son la evidencia, en orden
check.lint = shellcheck src/*.sh
agent.timeout = 30m
review.required = 1                # revisiones aprobatorias de OTROS agentes
review.require_different_adapter = false
gate.require_approval = true
gate.protected = .gitctl.conf .github/workflows/*   # aviso si se modifican
agent.claude.implement.args = --allowedTools Bash(make test:*)
agent.claude-opus.args = --model opus   # agente «claude-opus» con el adaptador claude
```

Los checks se ejecutan en una copia limpia: si necesitan dependencias, inclúyelas
(`check.test = npm ci && npm test`).

## Varios agentes del mismo tipo

El nombre del agente es libre; su adaptador es el prefijo hasta el primer `-`:
`claude-opus`, `claude-sonnet` y `claude` usan el adaptador `claude` con distinta
configuración. Revisar con el mismo adaptador está permitido pero se avisa de que la
independencia es limitada (o se prohíbe con `review.require_different_adapter`).

## Documentación

- [Arquitectura y modelo de estado](docs/arquitectura.md)
- [Escribir un adaptador de agente](docs/adaptadores.md)
- [Hoja de ruta](docs/hoja-de-ruta.md)

## Desarrollo

```bash
make deps    # descarga bats-core si no está instalado
make test    # tests (bats), con un agente simulado «fake»
make lint    # shellcheck + shfmt
```
