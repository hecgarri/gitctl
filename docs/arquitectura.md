# Arquitectura

gitctl replica en Bash el contrato de `gestionar_worktrees.ps1`. El README
describe el comportamiento; aquí está cómo se organiza el código.

## Estructura

```
bin/gitctl                     parámetros, ayuda y despacho a accion_* o al menú
lib/core/log.sh                info/ok/warn/err/die (a stderr)
lib/core/params.sh             -Accion, -Agente… (sin distinguir mayúsculas), listas con comas
lib/core/ui.sh                 confirmar [s/N], elegir, elegir_dos, leer_linea
lib/core/git.sh                git_try/git_run (código, salida y stderr), operaciones a medias
lib/core/repo.sh               repositorio principal, raíz <repo>-agents, base por defecto, ids
lib/core/inventario.sh         worktree list --porcelain -z → arrays A_*, base del motivo del lock,
                               selección de worktree y validación de la rama asignada
lib/core/pendiente.sh          status --porcelain=v1 -z → M/D/?, estado de integración
lib/acciones/{crear,estado,comparar,integrar,eliminar}.sh
lib/acciones/menu.sh           menú persistente (cada acción en una subshell)
lib/acciones/evaluar/          criterios, paquete, secretos, proceso (setsid + timeout),
                               adaptadores de proveedores y dictámenes (jq)
tests/*.bats                   bats sobre repos temporales; CLIs de proveedores falsas
```

## Decisiones

- **Sin estado propio.** Los metadatos de cada worktree van en el motivo de su
  `git worktree lock`: `Agente=…; Tarea=…; Base=<rama>@<sha>`. La base se
  recupera con una expresión regular que reconoce el SHA final (40–64
  caracteres hexadecimales), así que el nombre de la base puede contener `@`.
- **Errores.** `die` termina el proceso. Con `-Accion`, eso da el código de
  salida distinto de cero. En el menú, cada acción corre en una subshell
  (`_menu_ejecutar`), así que un error vuelve al menú.
- **Funciones que devuelven en globales** (`NORM`, `RUTA`, `IDX`, `BASE`,
  `PEND_*`…), en lugar de `$(…)`, para que un `die` dentro de ellas termine de
  verdad y no solo una subshell.
- **Nada de `cmd | grep -q`** con `pipefail`: si grep sale antes, el SIGPIPE de
  `cmd` cambiaría el resultado. Se usa `grep -q … <<<"$(cmd)"`.
- **Preguntas por stderr** y sin `read -p`, para que se vean también cuando la
  entrada no es una terminal (tests, tuberías). Con `-SinInteraccion`,
  `leer_linea` aborta si alguien intenta preguntar.
- **Procesos de los proveedores.** `setsid` les da un grupo propio; el bucle de
  espera muestra el progreso, aplica el límite y atiende Ctrl+C (`trap INT`).
  Al terminar mata el grupo entero, de modo que no quedan nietos huérfanos.
