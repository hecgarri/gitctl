# shellcheck shell=bash
# Integración con el shell: una función gitctl que hace cd al terminar.

cmd_shell_init() {
	local sh="${1:-}"
	case "$sh" in
	-h | --help | "")
		cat <<'H'
Uso: gitctl shell-init bash|zsh

Imprime una función de shell que envuelve a gitctl para que «new», «cd» y
«merge» puedan cambiar la carpeta de tu terminal. Añade a tu ~/.bashrc o ~/.zshrc:

  eval "$(gitctl shell-init bash)"     # o zsh
H
		[[ -n "$sh" ]] || return 1
		return 0
		;;
	bash | zsh) ;;
	*) die "shell no soportado: $sh (usa bash o zsh)" ;;
	esac
	cat <<'F'
gitctl() {
	local __gitctl_f __gitctl_rc __gitctl_d
	__gitctl_f="$(mktemp "${TMPDIR:-/tmp}/gitctl-cd.XXXXXX")" || return 1
	GITCTL_SHELL=1 GITCTL_CD_FILE="$__gitctl_f" command gitctl "$@"
	__gitctl_rc=$?
	__gitctl_d="$(cat "$__gitctl_f" 2>/dev/null)"
	rm -f "$__gitctl_f"
	if [ -n "$__gitctl_d" ] && [ -d "$__gitctl_d" ]; then
		cd "$__gitctl_d" || return 1
	fi
	return $__gitctl_rc
}
F
	if [[ "$sh" == bash ]]; then
		cat <<'C'
_gitctl_complete() {
	local cur="${COMP_WORDS[COMP_CWORD]}" words
	if [ "$COMP_CWORD" -eq 1 ]; then
		words="new cd ls merge rm clean init doctor shell-init help"
	else
		case "${COMP_WORDS[1]}" in
		cd | merge | rm) words="$(command git worktree list --porcelain 2>/dev/null | sed -n 's|^branch refs/heads/||p')" ;;
		*) words="" ;;
		esac
	fi
	COMPREPLY=($(compgen -W "$words" -- "$cur"))
}
complete -F _gitctl_complete gitctl
C
	fi
}
