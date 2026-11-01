# gitctl — rediseño como gestor de worktrees

> Tras aprobarse, este diseño se guarda en
> `docs/superpowers/specs/2026-10-31-gitctl-worktrees-design.md` (commit) y se pasa a
> `superpowers:writing-plans`.

## Contexto e intención

La versión actual (commit 29798db) es un orquestador multiagente: tareas, adaptadores
de agentes, ejecución headless, verify/review/gate/approve y PRs. No es lo que Héctor
quería. Lo que quería es un **gestor de worktrees** para su día a día: crear un
worktree con su rama en un paso, entrar en él en la misma terminal, dejarlo listo para
trabajar, hacer commits ahí y, al terminar, **integrarlo en la rama principal desde la
propia CLI**, en local, y limpiarlo. Los agentes (claude, codex…) los lanza él a mano
dentro del worktree. gitctl no sabe nada de agentes.

Flujo de referencia (es el que ya usaba con otro script en otro ordenador):
repo principal → `gitctl new X` → estás en el worktree → commits → `gitctl merge` →
la rama entra en main en el repo principal → worktree y rama borrados → vuelves al principal.

## Objetivos

- Crear, ubicar, saltar, preparar, listar, integrar y limpiar worktrees con el menor
  número de pasos posible.
- `cd` en la terminal actual (función de shell).
- Integración local con merge commit, decidida y ejecutada por gitctl.

## No objetivos

- Nada de agentes, tareas, verify, review, gate, approve, eventos ni PRs.
- Nada de remoto: ni fetch/pull, ni push. Lo gestiona el usuario.
- Ni tmux, ni abrir editores, ni symlinks, ni hooks al borrar.
- Nada de integración con issues o PRs de GitHub (`gh`).

## Anti-objetivos (sería un fracaso aunque funcione)

- Perder trabajo: borrar un worktree con cambios sin commitear o una rama sin integrar
  sin confirmación explícita.
- Dejar el repo principal en un estado raro sin decírselo (un merge a medias silencioso).
- Volver a crecer hacia un orquestador.

## Restricciones

- Bash ≥ 4.4, git ≥ 2.38, Linux. **Sin `jq` ni `flock`** como dependencias.
- `.gitctl.conf` es `clave = valor` y nunca se ejecuta como código (reutilizar el parser).
- Mensajes en español, como ahora.

## Enfoques considerados

- **A. Reescritura en Bash en el mismo repo, conservando solo los helpers útiles (elegido).**
  Se mantienen el historial, el Makefile, el CI y bats, y se elimina de raíz el modelo
  de tareas y agentes. Los metadatos van en git config, así que `jq` deja de hacer falta.
- B. Recortar el código actual. Cuesta menos al principio, pero arrastra el modelo de
  estado JSON y eventos que no se quiere. Descartado.
- C. Reescribir en Go o Rust. Daría un binario único, pero la herramienta orquesta `git`
  y Bash basta. Tiraría la infraestructura existente. Descartado.

Héctor eligió A.

## Comportamiento decidido

### `gitctl new <nombre> [--base REF]`
- La rama se llama exactamente `<nombre>`, sin prefijos.
- Si la rama existe en local, se usa. Si no, se crea desde `--base` o, por defecto,
  desde la rama por defecto (`git_default_branch`).
- Ruta: `../<repo>.wt/<nombre>` (`<repo>` = nombre de la carpeta del worktree principal).
- Recuerda la base en `git config branch.<nombre>.gitctl-base <base>`.
- Preparación: copia desde el worktree principal los archivos listados en `copy`
  (solo los que existan) y luego ejecuta `setup` en el worktree. Si `setup` falla, avisa
  y el worktree se conserva. `setup` se ejecuta **siempre, sin preguntar**, aunque venga
  del `.gitctl.conf` commiteado (decisión de Héctor: son sus repos). Antes de ejecutarlo
  se muestra el comando.
- Termina dejando al usuario dentro (vía la función de shell).

### Saltar: `gitctl cd [<nombre>]`
- Con nombre, va al worktree. Sin nombre, vuelve al worktree principal.
- La función de shell se instala con `eval "$(gitctl shell-init bash|zsh)"` en el rc.
  El binario imprime la ruta destino y la función hace `cd`.

### `gitctl ls`
- Por worktree: nombre, rama, cambios sin commitear (sí/no), commits por delante y por
  detrás de su base, y marca del actual.

### `gitctl merge [<nombre>]` (por defecto, el worktree actual)
- Destino: la base guardada en `branch.<nombre>.gitctl-base`.
- Se niega si el worktree principal tiene cambios sin commitear o no está en la rama
  destino. **(Mi decisión, ver abajo.)** También se niega si el worktree que se integra
  tiene cambios sin commitear.
- Ejecuta `git merge --no-ff` de la rama en el worktree principal.
- Si hay conflictos, **pregunta cada vez**:
  1. abortar (`merge --abort`; main queda intacto) y sugerir integrar la base dentro
     del worktree, resolver allí y repetir; o
  2. dejar el merge en curso en el principal, llevar al usuario allí con `cd` y
     terminar con `gitctl merge --continue`.
- Si sale bien: pregunta y borra worktree y rama (`branch -d`), y vuelve con `cd` al principal.

### `gitctl rm <nombre> [--force]`
- Se niega si hay cambios sin commitear o la rama no está integrada en su base, salvo `--force`.

### `gitctl clean`
- Propone los worktrees cuya rama ya está integrada en su base (`merge-base --is-ancestor`)
  y que no tienen cambios, además de los que `git worktree prune` detecte huérfanos.
  Muestra la lista, pide confirmación y borra.

### Configuración (`.gitctl.conf`, leída del worktree principal)
```ini
base = main            # opcional; si no, origin/HEAD o rama actual del principal
copy = .env .env.local # archivos ignorados que se copian al crear
setup = npm ci         # comando al crear, ejecutado en el worktree
```

## Decisiones que he tomado yo (revísalas)

- Nombres de comandos: `new`, `cd`, `ls`, `merge`, `rm`, `clean`, `shell-init`, más `init`/`doctor`.
- Sin argumentos, `gitctl` ejecuta `ls`. El menú fzf desaparece.
- `merge` exige que el worktree principal esté en la rama destino; no la cambia por su cuenta.
- El mensaje del merge commit es el que git pone por defecto.
- `-y/--yes` se mantiene para responder «sí» a las confirmaciones.
- `--base` solo acepta **ramas locales**, porque `merge` tiene que poder ejecutarse sobre
  ella. Si `new` reutiliza una rama existente, se guarda como base la rama por defecto.
- Nombres de rama: cualquiera válido para git, incluido `feat/login`. En la carpeta, `/`
  pasa a `-` (`../repo.wt/feat-login`). `cd`/`merge`/`rm` aceptan el nombre de la rama
  o el de la carpeta.
- Worktrees sin `gitctl-base` (creados a mano o por la versión anterior) se listan y
  se pueden usar con `cd`/`merge`/`rm`, tomando como base la rama por defecto.
  **`clean` nunca los propone**: solo limpia lo que gitctl creó.

## Archivos

- **Se conservan y adaptan:** `bin/gitctl` (despacho nuevo), `lib/core/log.sh`,
  `lib/core/util.sh` (`confirm`, `check_name`, `need_arg`), `lib/core/git.sh`
  (`git_main_root`, `git_default_branch`, `git_is_clean`, `git_branch_exists`,
  `git_current_branch`), `lib/core/config.sh` (`_cfg_parse`, sin las claves de checks
  y agentes), Makefile, CI (sin `jq`), `install.sh`.
- **Se reescriben:** `lib/cmd/wt.sh` → `lib/cmd/{new,nav,merge,clean}.sh` (o similar),
  `lib/cmd/setup.sh` (`init`/`doctor`, `shell-init`).
- **Se eliminan:** `lib/adapters/`, `lib/prompts/`, `lib/core/{agents,state}.sh`,
  `lib/cmd/{task,run,verify,review,gate,pr,ui}.sh`, tests de esas partes, `docs/adaptadores.md`.
- **Se reescriben los docs:** `README.md`, `docs/arquitectura.md`, `docs/hoja-de-ruta.md`.

## Queda para el implementador

- Formato exacto de `ls` y de los mensajes.
- Cómo se reparte el código en archivos dentro de `lib/cmd/`.
- Detalles de la función de shell, como el autocompletado de nombres (opcional).

## Verificación

- `make lint` (shellcheck + shfmt) y `make test` (bats), con tests nuevos en un repo
  temporal: new (rama nueva o existente, copy, fallo de setup), ls, merge (limpio,
  principal con cambios, conflicto→abortar, conflicto→continuar), rm (se niega sin
  `--force`), clean y shell-init.
- Prueba manual: `eval "$(gitctl shell-init bash)"`, `gitctl new prueba`, un commit,
  `gitctl merge`, y comprobar el merge commit en main, el worktree y la rama borrados
  y la terminal de vuelta en el principal.
