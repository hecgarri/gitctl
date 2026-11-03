# gitctl

Worktrees de Git **por agente y tarea**, en Bash. Es la réplica para Linux de
`gestionar_worktrees.ps1` (Windows): mismos parámetros, mismo menú y mismo
comportamiento, para no cambiar de costumbres al cambiar de sistema.

Varios agentes (Claude, Codex, Gemini u otros) trabajan en la misma tarea, cada
uno en su worktree y su rama. Después se comparan las propuestas, opcionalmente
se pide un dictamen a uno o varios LLM, y se integra la elegida (completa o
solo algunos commits).

```
~/dev/mi-proyecto                  → worktree principal
~/dev/mi-proyecto-agents/
    claude/corregir-api/           → rama claude/corregir-api
    codex/corregir-api/            → rama codex/corregir-api
    gemini/revisar-pruebas/        → rama gemini/revisar-pruebas
    _criterios/                    → criterios de evaluación redactados en el menú
    _dictamenes/                   → resultados de las evaluaciones LLM
```

## Flujo habitual

1. **Crear** los worktrees desde una rama base.
2. Abrir cada agente **a mano** en su carpeta (gitctl no los inicia).
3. Trabajar y hacer commit desde cada sesión de agente.
4. Consultar el **Estado**.
5. **Comparar** las propuestas.
6. Opcionalmente, **Evaluar** con uno o varios LLM.
7. **Integrar** una propuesta completa (Merge) o algunos commits (CherryPick).
8. Ejecutar las pruebas del proyecto (gitctl no lo hace: lo recuerda).
9. **Eliminar** los worktrees.

Todas las operaciones de Git son locales: nada de fetch, pull ni push. La única
acción que envía contenido fuera es Evaluar, y siempre pide confirmación.

## Instalación

Requisitos: bash ≥ 4.4, git ≥ 2.38 (por `git merge-tree --write-tree`) y, solo
para Evaluar, `jq` y las CLIs de los proveedores que uses.

```bash
git clone <este repo> ~/dev/gitctl
cd ~/dev/gitctl && ./install.sh        # enlaces en ~/.local/bin
```

`install.sh` crea dos enlaces al mismo script: `gitctl` y `gestionar_worktrees`
(el nombre de Windows). Desinstalar: `./install.sh --uninstall`.

> Si venías de una versión anterior: ya no hace falta la línea
> `eval "$(gitctl shell-init bash)"` del `~/.bashrc`. Puedes quitarla.

## Uso

Se ejecuta desde el worktree principal o cualquiera de sus subcarpetas (o con
`-Repositorio`). Desde un worktree secundario se rechaza.

```bash
gitctl          # menú interactivo
```

```
[1] Crear un worktree
[2] Ver worktrees activos
[3] Comparar ramas
[4] Evaluar con un LLM
[5] Integrar una rama
[6] Eliminar un worktree
[7] Salir
```

También acepta `salir` y `q`. Si una acción falla, se muestra el error y vuelves
al menú. En las listas, `[0] Cancelar` vuelve sin cambiar nada; las
confirmaciones son `[s/N]` (solo «s» o «si» confirman; vacío es no).

Con `-Accion` se ejecuta una acción y termina; si falla, el código de salida es
distinto de cero. **`-Accion` no implica ejecución desatendida**: sigue
preguntando lo que falte. Para no preguntar nunca, añade `-SinInteraccion` (y
entonces los datos y confirmaciones van por parámetros).

### Ejemplos

```bash
gitctl -Accion Crear -Agente codex -Tarea corregir-api -SinInteraccion

gitctl -Accion Estado -SinInteraccion

gitctl -Accion Comparar -Ramas "claude/corregir-api,codex/corregir-api" \
  -MostrarDiffCompleto -SinInteraccion

gitctl -Accion Evaluar -Ramas "claude/corregir-api,codex/corregir-api" \
  -ProveedorLlm Todos -CriteriosRevision docs/criterios.md \
  -ConfirmarEnvioLlm -SinInteraccion

gitctl -Accion Integrar -Agente codex -Tarea corregir-api -Metodo Merge \
  -ConfirmarIntegracion -SinInteraccion

gitctl -Accion Integrar -Agente codex -Tarea corregir-api -Metodo CherryPick \
  -Commits "abc1234,def5678" -ConfirmarIntegracion -SinInteraccion

gitctl -Accion Eliminar -Agente codex -Tarea corregir-api \
  -ConfirmarEliminacion -SinInteraccion

gitctl -Accion Eliminar -Agente codex -Tarea corregir-api \
  -CerrarSinIntegrar -Forzar -RescatarCambios /tmp/rescate-codex \
  -ConfirmarEliminacion -SinInteraccion
```

### Parámetros

Los nombres y los valores no distinguen mayúsculas (como en PowerShell); también
se aceptan con dos guiones (`--accion estado`). Los modificadores admiten
`-Forzar:$false`.

| Parámetro | Descripción |
|---|---|
| `-Accion` | `Crear`, `Estado`, `Comparar`, `Evaluar`, `Integrar`, `Eliminar` |
| `-Agente`, `-Tarea` | Identidad del worktree. Se normalizan: minúsculas, espacios y `_` → `-`, patrón `^[a-z0-9][a-z0-9._-]*$`, sin `.`, `..` ni `.lock` final. Cualquier agente vale, no solo los tres sugeridos |
| `-Base` | Rama **local** base. No acepta SHA, etiquetas ni ramas solo remotas |
| `-Repositorio` | Repositorio o subcarpeta del principal. Por defecto, la carpeta actual |
| `-RaizWorktrees` | Carpeta de worktrees. Por defecto, la hermana `<repo>-agents`. No puede ser el repo, estar dentro ni contenerlo |
| `-Metodo` | `Merge` o `CherryPick` |
| `-Commits` | Commits para el cherry-pick |
| `-Ramas` | Las dos ramas que comparar o evaluar |
| `-MostrarDiffCompleto` | Diff completo al comparar, en lugar de `--stat` |
| `-CerrarSinIntegrar` | Retirar aunque la rama no esté integrada (la rama se conserva) |
| `-Forzar` | Descartar cambios sin confirmar al retirar |
| `-RescatarCambios` | Carpeta donde copiar los archivos pendientes antes de retirar |
| `-ConfirmarIntegracion`, `-ConfirmarEliminacion`, `-ConfirmarEnvioLlm` | Confirmaciones obligatorias con `-SinInteraccion` |
| `-SinInteraccion` | No preguntar nunca. Requiere `-Accion` |
| `-CriteriosRevision` | Archivo de criterios para Evaluar (relativo a la raíz del repo) |
| `-ProveedorLlm` | `Codex`, `Claude`, `Gemini`, `Ambos` (Codex y Claude) o `Todos` (Codex, Claude y Gemini) |
| `-ModeloCodex`, `-ModeloClaude`, `-ModeloGemini` | Modelo. Si se omite, el predeterminado de cada CLI |
| `-ComandoCodex`, `-ComandoClaude`, `-ComandoGemini` | Comando o ruta de cada CLI (por defecto `codex`, `claude`, `gemini`) |
| `-MaxCaracteresLlm` | Límite del paquete de revisión: 10000–1000000 (200000) |
| `-TiempoEsperaLlmSegundos` | Límite por consulta: 1–3600 (600) |

`-Ramas` y `-Commits` aceptan `"a,b"`, varios valores seguidos (`-Ramas a b`) o
el parámetro repetido; se recortan los espacios y se descartan los vacíos.

## Conceptos

### Commits y trabajo sin confirmar

Comparar, Evaluar e Integrar trabajan **solo con commits**. Los cambios sin
confirmar de un worktree no entran en la comparación (gitctl los lista y avisa
de que quedan fuera), bloquean Evaluar e Integrar, y gitctl nunca hace stash,
commit ni descarte automático: eso se hace desde la sesión del agente.

### Base de cada worktree

Al crearlo, el worktree se bloquea (`git worktree lock`) con este motivo, que
guarda sus metadatos:

```
Agente=codex; Tarea=corregir-api; Base=main@<sha>
```

No hay base de datos propia: el inventario se reconstruye siempre con
`git worktree list --porcelain`. Para Estado, Integrar y Eliminar, la base es,
por orden: `-Base`, la registrada al crear el worktree, o la rama activa del
principal al arrancar gitctl. La registrada se sigue usando aunque luego
cambies de rama en el principal. Si el principal está en detached HEAD, hay que
indicar `-Base` donde no haya una base registrada.

### Estado de integración

| Estado | Significado |
|---|---|
| `Fusionada` | La rama es ancestro de la base (`git merge-base --is-ancestor`) |
| `EquivalentePorCherryPick` | No es ancestro, pero sus parches ya están en la base (`git cherry` sin `+`) y no tiene commits merge propios |
| `Pendiente` | Tiene trabajo que la base no tiene |
| `SinRama` | El worktree no tiene rama activa o la rama no existe |
| `BaseInexistente` | La base efectiva no existe como rama local |

Al retirar, una rama **Fusionada** se borra (`git update-ref -d` con el SHA
verificado: si la rama cambió entretanto, se conserva). Una
**EquivalentePorCherryPick** se conserva, porque tener los mismos parches no
significa tener la misma historia.

### Rama asignada

La rama de `codex/corregir-api` es `codex/corregir-api`. Si alguien la cambió a
mano en ese worktree, Integrar y Eliminar se niegan y te dan el `git switch`
para volver. Si está en detached HEAD con un commit que no está en ninguna
rama, avisan de que podría perderse y sugieren `git branch <nombre> HEAD`.
Ni `-Forzar` ni `-CerrarSinIntegrar` se saltan esta comprobación.

### -Forzar, -CerrarSinIntegrar y las confirmaciones

Son independientes y ninguno sustituye a otro:

- `-CerrarSinIntegrar` permite retirar un worktree cuya rama no está integrada;
  la rama se conserva.
- `-Forzar` solo permite descartar cambios sin confirmar. No dice nada sobre la
  integración.
- `-ConfirmarEliminacion` (o la respuesta en modo interactivo) es siempre la
  confirmación final.

En modo interactivo, si el worktree tiene cambios, gitctl los muestra, advierte
de que descartarlos es irreversible y pregunta. Esa respuesta vale como
confirmación del retiro, y además ofrece guardar una copia antes.

### Rescate y sus límites

`-RescatarCambios <carpeta>` copia los archivos modificados y sin seguimiento
(también el contenido de las carpetas sin seguimiento), conservando sus rutas
relativas, antes de retirar el worktree. Si la copia falla, no se retira nada.
Los archivos eliminados no se copian: siguen en la historia de Git. Es una
copia del contenido actual, **no un stash**: no conserva el índice ni lo que
estaba en staging.

## Integrar

Requisitos: el principal tiene activa la base (gitctl no cambia de rama por
ti), está limpio y sin un merge, cherry-pick, revert o rebase a medias, y el
worktree del agente existe y está limpio. Antes de confirmar se muestran los
commits y el `diff --stat`.

- **Merge**: primero comprueba conflictos con `git merge-tree --write-tree`, sin
  tocar nada. Si los hay, no ejecuta el merge. Si no, `git merge --no-ff
  --no-edit`. Si aun así falla, aborta y comprueba que HEAD volvió a su sitio.
- **CherryPick**: con `-Commits`, o eligiendo de una lista numerada. Solo
  commits de `<base>..<rama>`, sin merges ni duplicados, y siempre en el orden
  de la rama. Se aplican en un único `git cherry-pick`; si falla, aborta.

El worktree y la rama se conservan: ejecuta las pruebas y luego Eliminar.

## Evaluar con un LLM

Pide un **dictamen consultivo** sobre dos propuestas. No integra, no elige rama
y no modifica referencias.

### Criterios de revisión

Los criterios le dicen al evaluador qué debe cumplir la tarea: objetivo,
requisitos obligatorios, restricciones, pruebas esperadas y prioridades.
`-CriteriosRevision` es obligatorio sin interacción. En el menú puedes elegir un
archivo (admite comillas; `0` vuelve atrás) o redactarlos línea a línea:
`.fin` guarda en `<raíz>/_criterios/<fecha>-<uuid>.md` (fuera del repo) y
`.cancelar` descarta el borrador.

Orden del flujo guiado: criterios, ramas, proveedor, y preparación con
confirmación.

### Precondiciones

Cada rama corresponde a exactamente un worktree administrado, las dos carpetas
existen y están limpias, el principal está limpio y las ramas y la base existen.
Sin `-Base`: si los dos worktrees tienen la misma base registrada, se usa esa;
si tienen bases distintas, hay que indicar `-Base`; si no tienen ninguna, se usa
la por defecto.

### El paquete

Contiene las referencias (base y propuestas con sus SHA y merge-base), las
instrucciones para el juez, los criterios completos, los commits de cada
propuesta, el **diff completo** de cada una desde su merge-base
(`--unified=30`) y las diferencias entre ellas. Si las dos parten del mismo
merge-base, esas diferencias se resumen con `--stat` para no duplicar los
parches. Si no, se incluye el diff completo. El paquete lo dice.

Si supera `-MaxCaracteresLlm`, se rechaza: nunca se recorta. Antes de enviar,
una detección **heurística** busca secretos evidentes (claves privadas,
`password`/`token`/`api_key`/`secret` con valores literales entre comillas y
cadenas de conexión con `password=`). Si encuentra algo, se detiene. No
garantiza que no haya otros secretos. Después muestra los proveedores, las
ramas, los criterios, el tamaño, el SHA-256 y el contenido, y pide
confirmación (o `-ConfirmarEnvioLlm`).

### Proveedores

Se consultan uno detrás de otro, desde un directorio temporal fuera del repo y
con el prompt por stdin:

```
codex exec --ephemeral --ignore-user-config --skip-git-repo-check --sandbox read-only
      --color never --output-schema <esquema> --output-last-message <respuesta> [--model M] -
claude --print --safe-mode --restricted --tools "" --permission-mode plan
       --no-session-persistence --output-format json --json-schema <esquema> [--model M]
gemini --output-format json --approval-mode default [--model M]   (el esquema va en el prompt)
```

Durante cada consulta se muestra el tiempo transcurrido cada 5 s. Si se agota
`-TiempoEsperaLlmSegundos`, o con Ctrl+C, se detiene la consulta con todos sus
procesos hijos y no se guarda nada. Si un proveedor falla, se sigue con el
siguiente. Si ninguno da un dictamen válido, termina con error.

El dictamen tiene ocho campos: `recomendacion` (`integrar_primera`,
`integrar_segunda`, `combinar`, `cherry_pick`, `no_integrar` o
`revision_humana`), `confianza` (`alta`, `media` o `baja`), `resumen` y las
listas `contradicciones`, `commits_recomendados`, `orden_integracion`,
`pruebas_requeridas` y `advertencias`. Se admite como objeto directo, en
`structured_output`, en `result` (objeto o texto JSON) o en `response` (texto
JSON o un bloque ```` ```json ````). Localmente solo se comprueba que sea JSON y
que estén las ocho propiedades, igual que en el script de referencia.

Cada dictamen válido se guarda en
`<raíz>/_dictamenes/<fecha>-<proveedor>-<rama1>-<rama2>.json`
(`format_version: 2`, con la versión de la CLI, el modelo pedido, las ramas, los
SHA y el `prompt_sha256` del paquete).

## Diferencias con la versión de Windows

Son inherentes a Bash y Linux; el comportamiento es el mismo:

- **Wrappers `.ps1`, `.cmd` y `.bat`**: en Linux, `-ComandoX` acepta cualquier
  ejecutable o script con shebang. Los argumentos se pasan como array: no hay
  que escapar nada ni se genera código a partir del prompt.
- **`taskkill /T`**: cada consulta corre en su propio grupo de procesos
  (`setsid`). Al agotarse el tiempo o con Ctrl+C se envía TERM y después KILL a
  todo el grupo. stdout y stderr van a archivos separados, así que no hay
  bloqueos con paquetes grandes.
- **Consola OEM 850**: no aplica. Los archivos se escriben en UTF-8 sin BOM y
  las rutas se leen con `core.quotePath=false`.
- **Pester → bats**.

## Pruebas

```bash
make test     # bats, con repos temporales reales y CLIs de proveedores falsas
make lint     # shellcheck + shfmt
```

Las pruebas nunca consultan servicios LLM reales.
