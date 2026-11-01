# Arquitectura

## Estructura

```
bin/gitctl            dispatcher: carga lib/, enruta subcomandos a cmd_*
lib/core/             lógica transversal sin interfaz
  log.sh              mensajes (stderr) y marcas ✓/✗
  util.sh             confirmaciones, ids, escritura atómica, duraciones, plantillas
  config.sh           parseo de configuración (nunca `source`)
  git.sh              consultas Git y comprobación de conflictos (merge-tree)
  state.sh            estado JSON, cerrojos (flock), eventos, tareas/asignaciones
  agents.sh           registro de adaptadores e invocación con timeout
lib/cmd/              un fichero por grupo de comandos
lib/adapters/         un fichero por agente (claude, codex, gemini, fake)
lib/prompts/          plantillas de prompts (implement, fix, review)
tests/                bats, con repositorios temporales y el agente «fake»
```

La TUI (`lib/cmd/ui.sh`) solo invoca comandos de `gitctl`; no contiene lógica.

## Ciclo de vida

```
task new ──► task assign ──► run ──► verify ──► review ──► approve ──► gate ──► pr open ──► pr merge
                              ▲                    │
                              └────── fix ◄────────┘  (request_changes o checks rojos)
```

1. **task new** fija la especificación y el **SHA base**.
2. **task assign** crea un worktree + rama por agente desde ese SHA.
3. **run** lanza cada agente en un proceso independiente (`setsid`), con `timeout`,
   en su worktree. Al terminar, gitctl hace el **commit de huella**: añade lo que el
   agente dejó sin commitear, con autor `<agente> (vía gitctl)` y trailers
   `Gitctl-Task`, `Gitctl-Agent`, `Gitctl-Run`, `Gitctl-Exit`. Detecta si el agente
   cambió de rama o reescribió historial.
4. **verify** crea un worktree temporal `--detach` en el SHA, ejecuta los `check.*`
   y guarda exit codes, duraciones y hash de cada log.
5. **review** crea otro worktree temporal de solo lectura y entrega al revisor
   especificación, diff, commits y la evidencia medida. Exige un bloque JSON con el
   veredicto; si falta, si el revisor falla o si modifica ficheros → `invalid`.
6. **fix** convierte las huellas (hallazgos + logs de checks fallidos) en el prompt de
   una nueva ejecución del autor. Los hallazgos se presentan como afirmaciones que
   pueden ser erróneas.
7. **approve** registra la intención humana para ese SHA.
8. **gate** evalúa, sobre el SHA actual: commits, run en curso, worktree limpio,
   evidencia vigente, revisiones ajenas, aprobación, conflictos con la base
   (`git merge-tree --write-tree`), avance de la base y ficheros protegidos.
9. **pr merge** solo fusiona si la puerta pasa, el HEAD del PR coincide con el SHA
   evaluado (`--match-head-commit`) y el CI de GitHub está en verde.

## Estado (`<git-common-dir>/gitctl/`)

Compartido por todos los worktrees, fuera del árbol versionado.

```
tasks/<id>/task.json           tarea: título, base_ref, base_sha, estado, asignaciones
tasks/<id>/spec.md             especificación entregada a los agentes
runs/<run>/meta.json           agente, sha_start, sha_end, commits, exit, estado, notas
runs/<run>/prompt.md           prompt exacto enviado
runs/<run>/output.log          salida completa del agente
runs/<run>/result.md           mensaje final del agente (afirmación)
verifications/<sha>.json       evidencia: checks, exit, duración, sha256 del log, digest de checks
verifications/<sha>/<check>.log
reviews/<sha>/<revisor>.json   veredicto (claim), hallazgos, exit, nota
reviews/<sha>/<revisor>.{md,log,prompt.md}
approvals/<sha>.json           aprobación humana
events.jsonl                   registro append-only de todo
locks/                         cerrojos flock
tmp/                           worktrees efímeros (se eliminan al terminar)
```

## Concurrencia y seguridad

- Escrituras de JSON con `flock` + fichero temporal + `mv` (atómicas).
- Un cerrojo por worktree impide dos runs simultáneos del mismo agente.
- `run stop` envía SIGTERM al grupo del worker; el worker detiene al agente y
  marca el run como `detenido` sin commitear nada.
- La configuración del repo se **parsea**, no se ejecuta, y se lee del worktree
  principal.
- Los adaptadores usan los modos restringidos de cada CLI: Codex con
  `--sandbox workspace-write` (implementar) o `read-only` (revisar); Claude Code con
  `--permission-mode acceptEdits` (implementar) o `dontAsk` + herramientas de solo
  lectura (revisar).

### Límites honestos

- gitctl no es un sandbox. Un agente con acceso libre a la shell podría escribir
  fuera de su worktree o manipular `.git/gitctl/`. La protección real viene de los
  modos restringidos de cada CLI de agente; gitctl añade aislamiento por worktree,
  detección (cambio de rama, historial reescrito, revisor que modifica ficheros) y
  trazabilidad.
- La aprobación humana es un registro de intención, no una barrera criptográfica.
- La evidencia es tan buena como los checks: si los tests no cubren algo, la puerta
  no lo sabrá. Por eso la revisión ajena y la aprobación humana siguen siendo
  necesarias.
- Si la base avanza, la evidencia cubre la rama, no el resultado de la fusión; la
  puerta lo avisa.
