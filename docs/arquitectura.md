# Arquitectura

## Estructura

```
bin/gitctl           punto de entrada: opciones globales y despacho
lib/core/log.sh      mensajes (stderr) y marcas de estado
lib/core/util.sh     confirm, need_arg, want_help, require_cmd
lib/core/git.sh      consultas a git (raíz del principal, rama por defecto…)
lib/core/config.sh   lector de .gitctl.conf («clave = valor», sin ejecutar)
lib/core/wt.sh       worktrees: ubicación, listado, resolución, base, borrado y cd
lib/core/picker.sh   selector del menú: lista numerada, o fzf si está instalado
lib/cmd/*.sh         un archivo por comando (new, nav, diff, merge, pr, rm, clean, shell, setup)
lib/cmd/interactive.sh  el menú (gitctl a secas)
tests/*.bats         tests con bats sobre repos temporales
```

Los datos van por stdout y los mensajes por stderr.

## Metadatos

gitctl no tiene archivos de estado propios: todo vive en la config local del repo.

| Clave | Significado |
|---|---|
| `branch.<rama>.gitctl-base` | Rama en la que se integra `<rama>`. Que exista marca el worktree como **gestionado** |
| `branch.<rama>.gitctl-pr` | URL de la PR creada con `gitctl pr`. `clean` y `rm` consultan su estado con `gh`: si está integrada en GitHub, la rama cuenta como integrada |
| `gitctl.merging` | Rama con un merge de gitctl en curso en el principal (`merge --on-conflict=keep`) |

Los worktrees sin `gitctl-base` (creados con `git worktree add`) se pueden usar con
`cd`, `merge` y `rm`, tomando como base la rama por defecto; `clean` no los toca nunca.

Rama por defecto: `base` en la config → `origin/HEAD` → rama actual del principal.

## Ubicación

Los worktrees viven en `../<repo>.wt/<carpeta>`, donde `<carpeta>` es la rama con
`/` cambiada por `-`. Un nombre se resuelve, en este orden, como rama, como nombre
de carpeta y como ruta.

## Cambio de carpeta

Un programa no puede cambiar el directorio de la shell que lo lanza. `gitctl
shell-init` imprime una función `gitctl` que:

1. crea un archivo temporal y lo pasa en `GITCTL_CD_FILE` (y `GITCTL_SHELL=1`);
2. ejecuta el binario real (`command gitctl`);
3. si el binario escribió una ruta en ese archivo, hace `cd` a ella.

Se usa un archivo y no stdout para que `setup` pueda imprimir lo que quiera y las
confirmaciones sigan siendo interactivas.

## Menú interactivo

`gitctl` sin argumentos (con terminal) abre un bucle de menú. Cada acción se
ejecuta como **proceso hijo** (`bin/gitctl <comando>`), igual que en gcpctl: un
`die` dentro de un comando muestra su error y vuelve al menú en vez de cerrarlo,
y menú y comandos sueltos comparten el mismo código.

Cada hijo recibe su propio `GITCTL_CD_FILE`; el menú guarda la carpeta pedida y
la escribe en el `GITCTL_CD_FILE` real al salir. «Nuevo» y «Entrar» salen del
menú en el acto. Si la carpeta actual desaparece (se integró y borró el worktree
en el que estabas), el menú sigue desde el principal.

Antes de `merge`, el menú repite sus comprobaciones y ofrece arreglar cada una
(entrar a commitear, `git stash -u` en el principal, `git switch <base>`).

## Integración (`merge`)

1. Comprobaciones: worktree y principal limpios, principal en la base, ningún merge
   en curso.
2. `git -C <principal> merge --no-ff --no-edit <rama>`.
3. Si sale bien: `_merge_publish` y después `wt_remove` (pregunta) y `cd` al
   principal. `_merge_publish` compara la base con `refs/remotes/<remoto>/<base>`:
   con `--push` muestra los commits, confirma y hace `git push -u <remoto> <base>`;
   sin `--push` solo avisa si quedó por delante. Un push rechazado o fallido no
   deshace el merge, pero el comando termina con 1.
4. Con conflictos: `abort` → `merge --abort`; `keep` → se guarda `gitctl.merging`
   y `merge --continue [--push]` hace el commit, el push si se pidió y la limpieza.

## Garantías

- Nunca se borra el worktree principal.
- Sin `--force`, no se borra un worktree con cambios ni una rama con commits no
  integrados en su base (`git merge-base --is-ancestor`).
- Todo borrado pide confirmación (o `-y`); sin terminal y sin `-y`, se rechaza.
- Un conflicto sin terminal interactiva aborta el merge: el principal nunca queda
  a medias sin que lo hayas pedido.
- `.gitctl.conf` se parsea como texto; solo `setup` se ejecuta, a propósito.
