# Plan de implementación — gitctl como gestor de worktrees

Diseño: [`docs/superpowers/specs/2026-10-31-gitctl-worktrees-design.md`](../specs/2026-10-31-gitctl-worktrees-design.md).
Rama de trabajo: `rediseno-worktrees`.

Reglas para todo el plan:
- Cada tarea termina con `make lint && make test` en verde y **un commit**.
- Primero los tests (bats), después el código.
- Mensajes al usuario en español y por stderr (`info/ok/warn/die` de `lib/core/log.sh`); los datos van por stdout.
- Nada destructivo sin `confirm` (respeta `-y`). Sin TTY y sin `-y`, se rechaza.

---

## Tarea 1 — Quitar el orquestador y dejar un esqueleto mínimo

**Objetivo:** que el repo solo contenga el núcleo reutilizable y un `gitctl` que arranca.

1. Borrar:
   - `lib/adapters/`, `lib/prompts/`
   - `lib/core/agents.sh`, `lib/core/state.sh`
   - `lib/cmd/{task,run,verify,review,gate,pr,ui,wt}.sh`
   - `tests/{pr,quality,run,task_wt}.bats`
   - `docs/adaptadores.md`
2. `lib/core/config.sh`:
   - `_cfg_defaults` queda vacío (sin claves de agentes, checks ni gate).
   - Se eliminan `GITCTL_CHECKS`, la rama `check.*` de `_cfg_parse` y `cfg_checks_digest`.
   - Se conservan `_cfg_parse`, `cfg_load`, `cfg` y `cfg_bool`.
   - Se actualiza el comentario de cabecera.
3. `lib/core/util.sh`:
   - Se conservan `require_cmd`, `confirm`, `need_arg` y `want_help`.
   - Se borran `rand_hex`, `atomic_write`, `sha256_file`, `duration_secs`, `fmt_secs`, `template_sub`, `now_*`, `valid_name` y `check_name`.
4. `lib/core/git.sh`:
   - Se conservan `in_git_repo`, `require_repo`, `git_common_dir`, `git_main_root`, `git_short`, `git_branch_exists`, `git_is_clean`, `git_current_branch`, `git_default_branch` y `git_version_ok`.
   - Se borran `git_identity_args` y `git_merge_check`.
5. `bin/gitctl`:
   - Se quitan `adapters_load` y el despacho viejo.
   - `usage` nuevo con los comandos `new`, `cd`, `ls`, `merge`, `rm`, `clean`, `shell-init`, `init` y `doctor`.
   - Sin argumentos ejecuta `cmd_ls`.
   - Por ahora cada comando no implementado hace `die "pendiente"`.
   - `GITCTL_VERSION="0.2.0"`.
6. `lib/cmd/setup.sh`:
   - Se reduce a `cmd_init` y `cmd_doctor`, sin estado ni agentes; el contenido real llega en la tarea 9.
   - Por ahora `init` solo escribe un `.gitctl.conf` de ejemplo si no existe.
7. `install.sh`:
   - Dependencias obligatorias: solo `git`.
   - Siguiente paso sugerido: `eval "$(gitctl shell-init bash)"`.
8. `.github/workflows/ci.yml`: se quita `jq` del `apt-get install`.
9. `tests/test_helper.bash`:
   - Se quitan `add_check`, `state`, `wt_of`, `task_with_runs` y `unset GITCTL_RUN_ID`.
   - `setup_repo` deja de llamar a `gitctl init` y crea `.gitctl.conf` vacío a mano.
   - Se añade `wt_path() { echo "$TEST_TMP/repo.wt/$1"; }`.
10. `tests/cli.bats` se reescribe con:
    - `--version`.
    - `--help` contiene «new» y «merge».
    - Un comando desconocido falla.
    - Fuera de un repo falla con «repositorio Git».
    - La config no se ejecuta: `base = main; touch HACKED` no crea el archivo al lanzar `gitctl ls`, que de momento puede dar «pendiente».

Verificar: `grep -rn "jq\|flock\|state_\|emit_event\|adapter" bin lib install.sh` no encuentra nada.
Commit: `refactor: eliminar el orquestador multiagente`.

---

## Tarea 2 — Núcleo de worktrees (`lib/core/wt.sh`)

Funciones de biblioteca que usan todos los comandos. Se prueban a través de los
comandos en las tareas siguientes; aquí basta con un test mínimo de `wt_dir_name`
mediante un comando interno oculto `gitctl __wt-dir <rama>`, o se prueba directamente
en la tarea 4.

```bash
wt_root()          # "$(dirname "$(git_main_root)")/$(basename "$(git_main_root)").wt"
wt_dir_name()      # rama → nombre de carpeta: ${1//\//-}
wt_list()          # parsea `git worktree list --porcelain` y rellena tres arrays
                   # paralelos WT_PATHS, WT_BRANCHES y WT_HEADS (índice 0 = principal).
                   # Ignora worktrees bare o prunable si su ruta no existe.
wt_resolve <arg>   # devuelve la ruta. Sin argumento o con «main», la del principal.
                   # Busca en orden: nombre de rama exacto → basename de la carpeta → ruta existente.
                   # Si no encuentra nada: die "no existe el worktree «arg»".
wt_branch_of <path>  # rama del worktree (git_current_branch); vacía si está detached.
wt_base_of <rama>    # git config --get branch.<rama>.gitctl-base || git_default_branch
wt_is_managed <rama> # ¿tiene gitctl-base?  (clean solo toca estos)
wt_current()       # ruta del worktree que contiene $PWD (git rev-parse --show-toplevel)
```

**Protocolo de `cd`** (también en `wt.sh`):

```bash
# Pide a la función de shell que haga cd al terminar.
cd_to() {
	local dir="$1"
	if [[ -n "${GITCTL_CD_FILE:-}" ]]; then
		printf '%s\n' "$dir" >"$GITCTL_CD_FILE"
	else
		info "cd $dir    (instala la integración: eval \"\$(gitctl shell-init bash)\")"
	fi
}
```

Usar un archivo y no stdout permite que `setup` imprima lo que quiera y que
`confirm` siga siendo interactivo.

Commit: `feat: núcleo de worktrees y protocolo de cd`.

---

## Tarea 3 — `gitctl shell-init bash|zsh`

Archivo: `lib/cmd/shell.sh`. Imprime la función por stdout:

```bash
gitctl() {
	local __f __rc __d
	__f="$(mktemp "${TMPDIR:-/tmp}/gitctl-cd.XXXXXX")" || return 1
	GITCTL_CD_FILE="$__f" command gitctl "$@"
	__rc=$?
	__d="$(cat "$__f" 2>/dev/null)"
	rm -f "$__f"
	[ -n "$__d" ] && [ -d "$__d" ] && cd "$__d"
	return $__rc
}
```

- La misma función sirve para bash y para zsh (sintaxis POSIX). Con cualquier otro shell, `die`.
- Autocompletado opcional (la especificación lo deja a criterio del implementador): en bash, `complete -W "new cd ls merge rm clean"` más los nombres de los worktrees. Si complica, se pospone.

Tests (`tests/shell.bats`):
- `gitctl shell-init bash` contiene `GITCTL_CD_FILE` y `command gitctl`.
- `gitctl shell-init fish` falla.
- Test de integración: `bash -c 'eval "$(gitctl shell-init bash)"; gitctl cd <wt>; pwd'` acaba en la ruta del worktree. Este test se activa en la tarea 5.

Commit: `feat: shell-init con la función de cd`.

---

## Tarea 4 — `gitctl new <rama> [--base RAMA]`

Archivo: `lib/cmd/new.sh`. Tests primero (`tests/new.bats`):

| Caso | Esperado |
|---|---|
| `new feat/login` | crea `../repo.wt/feat-login`, la rama `feat/login` desde `main` y `branch.feat/login.gitctl-base = main` |
| rama ya existente en local | reutiliza la rama sin moverla; la base guardada es la rama por defecto |
| `--base dev` (existe en local) | crea desde `dev`; base guardada = `dev` |
| `--base origin/main`, un tag o un SHA | falla con «--base debe ser una rama local» |
| nombre no válido (`git check-ref-format --branch`) | falla |
| la carpeta destino ya existe | falla sin tocar nada |
| la rama ya tiene un worktree | falla y sugiere `gitctl cd <rama>` |
| `copy = .env falta.txt` con `.env` en el principal | copia `.env` y avisa de que falta `falta.txt`, sin fallar |
| `copy` con una ruta en subcarpeta (`config/local.yml`) | crea la subcarpeta y copia |
| `setup = touch LISTO` | `LISTO` existe en el worktree |
| `setup = false` | aviso, código de salida ≠ 0, el worktree existe |
| con `GITCTL_CD_FILE` | el archivo contiene la ruta del worktree |

Implementación:
1. `require_repo`; parsear `--base` con `need_arg`.
2. Validar con `git check-ref-format --branch "$rama"`.
3. La base es `--base` o `git_default_branch`, y debe cumplir `git_branch_exists`.
4. `path="$(wt_root)/$(wt_dir_name "$rama")"`. Si `[[ -e $path ]]`, `die`.
5. Si la rama existe, `git worktree add "$path" "$rama"`. Si no, `git worktree add -b "$rama" "$path" "$base"`.
6. `git config "branch.$rama.gitctl-base" "$base"` (en el caso de una rama reutilizada, la rama por defecto).
7. `copy`: separar por espacios. Rechazar rutas absolutas o con `..`. `mkdir -p` del directorio y `cp -p` desde `git_main_root`.
8. `setup`: `info "setup: $cmd"`, luego `(cd "$path" && bash -c "$cmd")`. Si falla, `warn` y se guarda rc=1.
9. `ok "worktree $path (rama $rama desde $base)"`, `cd_to "$path"` y `return $rc`.

Commit: `feat: gitctl new`.

---

## Tarea 5 — `gitctl cd [<nombre>]` y `gitctl ls`

Archivo: `lib/cmd/nav.sh`.

`cd`: `cd_to "$(wt_resolve "${1:-}")"`, y además imprime la ruta por stdout para
poder usarlo en scripts (`cd "$(command gitctl cd x)"`).

`ls`: una fila por worktree, con columnas (formato libre):

```
  NOMBRE        RAMA           BASE   ↑/↓     CAMBIOS
* (principal)   main           -      -       no
  feat-login    feat/login     main   3/1     sí
```

- Las cifras salen de `git rev-list --left-right --count "$base...$rama"`.
- `*` marca el worktree actual.
- Un worktree con la carpeta borrada aparece como «ausente».
- Si está detached, se muestra `(detached)`.

Tests (`tests/nav.bats`):
- `ls` muestra el principal y uno creado, con 1/0 tras un commit.
- «sí» si hay cambios.
- `cd feat/login` y `cd feat-login` resuelven a la misma ruta.
- `cd` sin argumento resuelve al principal.
- `cd inexistente` falla.
- Activar aquí el test de integración de shell-init de la tarea 3.

Commit: `feat: gitctl cd y gitctl ls`.

---

## Tarea 6 — `gitctl rm <nombre> [--force]`

Archivo: `lib/cmd/rm.sh`, con una función reutilizable `wt_remove <path> <rama> <force>`
que también usan `merge` y `clean`.

1. Nunca borra el principal (`die`).
2. Sin `--force`, se niega si `! git_is_clean` o si la rama no está integrada en su base (`git merge-base --is-ancestor "$rama" "$base"`).
3. `confirm "¿Eliminar worktree $path y rama $rama?"`.
4. `git worktree remove [--force] "$path"`, después `git branch -d` (o `-D` con `--force`) y `git config --remove-section "branch.$rama"` si queda algo, ignorando errores.
5. Si `$PWD` estaba dentro del worktree borrado, `cd_to "$(git_main_root)"`.

Tests (`tests/rm.bats`):
- Se niega con cambios.
- Se niega si hay commits sin integrar.
- Con `--force -y` borra worktree y rama.
- Con la rama integrada y `-y`, borra.
- Sin TTY y sin `-y`, rechaza.
- `rm main` falla.

Commit: `feat: gitctl rm`.

---

## Tarea 7 — `gitctl merge [<nombre>] [--continue] [--on-conflict=ask|abort|keep]`

Archivo: `lib/cmd/merge.sh`. Es la pieza principal.

**Flujo normal:**
1. `path` = `wt_resolve "$1"` o, si no se da, `wt_current`. Si `path` es el principal, `die "ejecútalo desde un worktree o indica cuál"`.
2. `rama` = `wt_branch_of`, `base` = `wt_base_of`, `main` = `git_main_root`.
3. Comprobaciones (cada una con un `die` claro):
   - el worktree está limpio;
   - el principal está limpio (`git_is_clean "$main"`);
   - `git_current_branch "$main" == "$base"`; si no, `die "el principal está en X; cambia a $base"`;
   - el principal no tiene un merge en curso (`git -C "$main" rev-parse -q --verify MERGE_HEAD`);
   - hay algo que integrar: si `git merge-base --is-ancestor "$rama" "$base"`, se avisa de «nada que integrar» y se pasa directamente a la limpieza.
4. `git -C "$main" merge --no-ff --no-edit "$rama"`.
5. Si sale bien: `ok`, y luego `wt_remove "$path" "$rama"` (pregunta) y `cd_to "$main"`. Si el usuario dice que no, se queda todo y se hace `cd_to "$main"` de todos modos.

**Conflictos** (el merge devuelve ≠ 0 y existe `MERGE_HEAD`):
- Se listan los archivos (`git -C "$main" diff --name-only --diff-filter=U`).
- Modo `ask` (por defecto). Con TTY se pregunta: «[a] abortar y resolver en el worktree / [d] dejar el merge en el principal». Sin TTY y sin `--on-conflict`, se comporta como `abort`, que es lo seguro.
- `abort`: `git -C "$main" merge --abort` y luego: `info "resuelve en el worktree: git merge $base, arregla, commit, y repite gitctl merge"`. Sale con 1.
- `keep`: `git -C "$main" config gitctl.merging "$rama"`, `cd_to "$main"` y `info "resuelve, haz git add y ejecuta gitctl merge --continue"`. Sale con 1.

**`--continue`** (se ejecuta en cualquier sitio):
1. `rama="$(git config --get gitctl.merging)"`; si no existe, `die "no hay ningún merge de gitctl en curso"`.
2. Si quedan archivos sin resolver, `die` con la lista.
3. `git -C "$main" commit --no-edit`, luego `git config --unset gitctl.merging`, y el mismo paso de limpieza que el flujo normal.
4. Si el usuario abortó a mano (`MERGE_HEAD` ya no existe y la rama no está integrada), se limpia `gitctl.merging`, se avisa y se sale.

Tests (`tests/merge.bats`). Para crear un conflicto: el mismo archivo modificado en
`main` y en la rama.
- Merge limpio con `-y`: `main` tiene un commit de merge (`git log -1 --merges`), worktree y rama borrados, y `GITCTL_CD_FILE` apunta al principal.
- Merge limpio sin `-y` y sin TTY: integra pero no borra (confirm rechaza) y avisa.
- Falla si el worktree está sucio.
- Falla si el principal está sucio.
- Falla si el principal está en otra rama.
- Usa la base guardada (`--base dev` → integra en `dev`, con el principal en `dev`).
- Un worktree no gestionado (creado con `git worktree add`) integra en la rama por defecto.
- Conflicto con `--on-conflict=abort`: `main` intacto y sin `MERGE_HEAD`, salida 1.
- Conflicto con `--on-conflict=keep`: existe `MERGE_HEAD` y `gitctl.merging` está puesto; tras resolver y hacer `git add`, `merge --continue -y` deja el commit de merge y la limpieza.
- `--continue` con archivos sin resolver falla con la lista.
- `--continue` sin merge en curso falla.

Commit: `feat: gitctl merge con gestión de conflictos`.

---

## Tarea 8 — `gitctl clean`

Archivo: `lib/cmd/clean.sh`.

1. `git worktree prune --dry-run -v` para listar los huérfanos.
2. Candidatos: worktrees con `wt_is_managed` que estén limpios y cuya rama `--is-ancestor` de su base. Los no gestionados **no se proponen nunca**.
3. Si no hay nada: `ok "nada que limpiar"`.
4. Se muestra la lista y se pide `confirm` una vez. Luego `git worktree prune` y `wt_remove` (sin volver a preguntar) para cada candidato.
5. `--dry-run` solo muestra la lista.

Tests (`tests/clean.bats`):
- Propone y borra uno integrado con `-y`.
- No toca uno con cambios ni uno con commits sin integrar.
- No toca uno creado con `git worktree add` aunque esté integrado.
- Un worktree cuya carpeta se borró a mano desaparece de `git worktree list`.
- `--dry-run` no borra.

Commit: `feat: gitctl clean`.

---

## Tarea 9 — `init` y `doctor`

`lib/cmd/setup.sh`:
- `init` escribe un `.gitctl.conf` de ejemplo comentado (claves `base`, `copy`, `setup`) si no existe, y muestra la línea de `shell-init` para añadir al rc. No crea ningún estado.
- `doctor` muestra:
  - `git` ≥ 2.38 (`git_version_ok`);
  - si está dentro de un repo;
  - la rama por defecto;
  - las claves de config leídas;
  - si la función de shell está activa (detectarlo con una variable exportada por la función, por ejemplo `GITCTL_SHELL=1`, que hay que añadir en la tarea 3).

Tests en `tests/cli.bats`:
- `init` crea el archivo y no lo sobrescribe.
- `doctor` muestra «copy» y «setup» cuando están configurados.

Commit: `feat: init y doctor para el nuevo flujo`.

---

## Tarea 10 — Documentación

- `README.md`: nueva descripción (gestor de worktrees), instalación (sin `jq`), integración con el shell, un flujo de ejemplo `new → commits → merge`, tabla de comandos, `.gitctl.conf` con `base`/`copy`/`setup` y la nota de que `setup` se ejecuta sin preguntar.
- `docs/arquitectura.md`: estructura de `lib/`, metadatos en git config (`branch.<rama>.gitctl-base`, `gitctl.merging`), protocolo `GITCTL_CD_FILE` y garantías de seguridad (qué nunca se borra).
- `docs/hoja-de-ruta.md`: posibles mejoras fuera del alcance actual (autocompletado, `--squash` opcional, etc.), sin comprometer nada.
- Revisar que ningún texto mencione agentes, tareas o PRs.

Commit: `docs: README y arquitectura del nuevo gitctl`.

---

## Tarea 11 — Verificación final

1. `make lint && make test` en verde.
2. Prueba manual en un repo de usar y tirar (scratchpad):
   ```bash
   eval "$(gitctl shell-init bash)"
   cd /tmp/x && git init -b main && git commit --allow-empty -m init
   echo 'copy = .env' > .gitctl.conf; echo 'setup = echo listo' >> .gitctl.conf; echo A=1 > .env
   gitctl new prueba         # → dentro de ../x.wt/prueba, .env copiado, «listo»
   echo hola > f && git add f && git commit -m f
   gitctl ls                 # prueba 1/0
   gitctl merge              # pregunta → sí → de vuelta en /tmp/x
   git log --oneline --graph # commit de merge en main
   gitctl ls                 # solo el principal
   ```
3. Repetir provocando un conflicto y probar las dos respuestas de la pregunta.
4. Abrir el PR de `rediseno-worktrees` hacia `main` (solo si Héctor lo pide).
