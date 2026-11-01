# Hoja de ruta

| Fase | Contenido | Estado |
|---|---|---|
| 0 | Dispatcher, núcleo (log, config, estado, git), `init`, `doctor`, tests, lint, CI, instalador | ✅ |
| 1 | Worktrees y tareas (crear, listar, mostrar, asignar, eliminar seguro), eventos | ✅ |
| 2 | Adaptadores `fake`, `claude`, `codex`; ejecución headless en paralelo; commit de huella; status/wait/logs/stop | ✅ |
| 3 | `verify`, `review`, `fix`, `approve`, `gate` ligados a SHA | ✅ |
| MVP | Fases 0–3 + `pr open` | ✅ |
| 4 | GitHub: `pr status` (CI, revisión), `pr merge` protegido por la puerta y `--match-head-commit` | ✅ básico |
| 5 | TUI con fzf (menú y vista previa de tareas; fallback `select`) | ✅ básico |
| 6 | Pendiente: issues → tareas (`gh issue`), estado de Actions por rama, utilidades de ramas/repos, adaptador gemini verificado, `gc` de estado y worktrees de tareas cerradas, comparación automática de implementaciones paralelas | ⏳ |

## Ideas a evaluar (no comprometidas)

- `gitctl compare <tarea>`: tabla de evidencia/revisiones de todas las
  implementaciones de una tarea para elegir una.
- Verificación del resultado de la fusión (base actual + rama) además de la rama.
- Exportar el historial de una tarea como informe Markdown.
