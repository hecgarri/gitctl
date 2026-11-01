# gitctl

Gestor de **Git worktrees** en Bash: crea una rama con su worktree en un paso,
salta entre ellos desde tu misma terminal, integra el trabajo en la rama
principal con un merge commit y limpia lo que ya no hace falta.

```bash
gitctl new login-oauth     # rama + worktree en ../<repo>.wt/login-oauth, preparado, y estás dentro
# … trabajas y haces commits (tú, o un agente que lances a mano ahí) …
gitctl merge               # merge commit en main (en el repo principal), borra worktree y rama, vuelves al principal
```

## Instalación

Requisitos: Linux, `bash` ≥ 4.4 y `git` ≥ 2.38. Nada más.

```bash
git clone <este-repo> ~/src/gitctl
cd ~/src/gitctl && make install        # enlace en ~/.local/bin/gitctl
```

Añade a tu `~/.bashrc` (o `~/.zshrc` con `zsh`) la integración con el shell, para
que `new`, `cd` y `merge` puedan cambiar la carpeta de tu terminal:

```bash
eval "$(gitctl shell-init bash)"
```

Sin ella todo funciona igual, pero gitctl te dice a qué carpeta ir en vez de llevarte.
`gitctl doctor` comprueba que todo está en su sitio.

## Flujo

```bash
cd mi-proyecto
gitctl new feat/login          # crea ../mi-proyecto.wt/feat-login (rama feat/login desde main)
git commit -am "…"             # trabajas dentro del worktree
gitctl ls                      # estado de todos los worktrees
gitctl cd                      # vuelves al principal;  gitctl cd feat/login  para volver
gitctl merge feat/login        # integra (desde el worktree basta con «gitctl merge»)
```

`merge` necesita que el worktree y el principal no tengan cambios sin commitear y
que el principal esté en la rama base. Si hay **conflictos**, te pregunta:

- **abortar**: el principal queda intacto; integra la base en tu worktree
  (`git merge main`), resuelve allí y repite `gitctl merge`;
- **dejar el merge en curso** en el principal: te lleva allí, resuelves, `git add`
  y `gitctl merge --continue`.

Sin terminal interactiva aborta; `--on-conflict=abort|keep` decide por ti.

## Comandos

| Comando | Qué hace |
|---|---|
| `new <rama> [--base RAMA]` | Crea (o reutiliza) la rama y su worktree, copia archivos, ejecuta `setup` y te deja dentro |
| `cd [<rama>]` | Salta a un worktree; sin argumento, al principal |
| `ls` | Worktrees con rama, base, commits por delante/detrás y cambios (también `gitctl` a secas) |
| `merge [<rama>]` | Merge commit en la base, en el principal; luego ofrece borrar worktree y rama |
| `merge --continue` | Termina un merge que dejaste con conflictos |
| `rm <rama> [--force]` | Borra worktree y rama; sin `--force` se niega si hay algo sin commitear o sin integrar |
| `clean [--dry-run]` | Borra los worktrees creados por gitctl ya integrados y olvida los que no existen |
| `shell-init bash\|zsh` | Imprime la función de shell |
| `init`, `doctor` | `.gitctl.conf` de ejemplo; comprobaciones |

Las ramas pueden llevar `/`: `feat/login` vive en la carpeta `feat-login`, y
`cd`/`merge`/`rm` aceptan cualquiera de los dos nombres. `-y` responde «sí» a
las confirmaciones. Cada comando acepta `--help`.

## Configuración (`.gitctl.conf`)

En la raíz del repo (se lee siempre del worktree principal). Formato
`clave = valor`; el archivo **nunca se ejecuta** como código.

```ini
base = main              # rama en la que se crean e integran los worktrees
copy = .env .env.local   # archivos ignorados que se copian del principal a cada worktree nuevo
setup = npm ci           # comando que se ejecuta en cada worktree nuevo
```

`setup` se ejecuta **siempre, sin preguntar**: revisa el `.gitctl.conf` de los
repos que no sean tuyos. Si falla, el worktree se conserva y se avisa.
También puedes poner valores por defecto en `~/.config/gitctl/config`.

## Qué no hace

Nada con el remoto (ni `fetch`, ni `pull`, ni `push`), nada de PRs y nada de
agentes: los lanzas tú dentro del worktree. Nunca borra un worktree con cambios ni
una rama sin integrar sin `--force`, y siempre pide confirmación antes de borrar.

## Documentación

- [Arquitectura](docs/arquitectura.md)
- [Hoja de ruta](docs/hoja-de-ruta.md)

## Desarrollo

```bash
make deps    # descarga bats-core si no está instalado
make test    # tests (bats)
make lint    # shellcheck + shfmt
```
