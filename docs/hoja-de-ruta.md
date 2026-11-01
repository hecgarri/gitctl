# Hoja de ruta

Estado actual (0.2): gestor de worktrees con `new`, `cd`, `ls`, `merge`, `rm`,
`clean`, `shell-init`, `init` y `doctor`. Ver el
[diseño](superpowers/specs/2026-10-31-gitctl-worktrees-design.md).

## Ideas a evaluar (no comprometidas)

- Autocompletado para zsh (en bash ya existe con `shell-init bash`).
- Modos de integración alternativos (`--squash`, rebase + fast-forward).
- Ubicación configurable de los worktrees.
- Selector interactivo opcional (por ejemplo con `fzf`) para `cd`.
