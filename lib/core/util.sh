# shellcheck shell=bash
# Utilidades generales.

GITCTL_YES="${GITCTL_YES:-}"

require_cmd() {
	local c
	for c in "$@"; do
		command -v "$c" >/dev/null 2>&1 || die "falta la herramienta «$c»; instálala (ver gitctl doctor)"
	done
}

# ¿Se puede preguntar al usuario? (GITCTL_ASSUME_TTY=1 lo fuerza, para los tests)
is_interactive() { [[ -n "${GITCTL_ASSUME_TTY:-}" || -t 0 ]]; }

# ask "pregunta" [defecto] → imprime la respuesta (o el defecto si se deja vacía).
ask() {
	local ans=""
	read -r -p "$1${2:+ [$2]}: " ans || true
	printf '%s' "${ans:-${2:-}}"
}

# confirm "pregunta" → 0 si el usuario acepta. Sin TTY y sin --yes: rechaza.
confirm() {
	[[ -n "$GITCTL_YES" ]] && return 0
	if ! is_interactive; then
		err "se necesita confirmación ($1); usa --yes en modo no interactivo"
		return 1
	fi
	local ans
	read -r -p "$1 [s/N] " ans
	[[ "$ans" =~ ^[sSyY]$ ]]
}

# Comprueba que el siguiente argumento existe para una opción con valor.
need_arg() { [[ $# -ge 2 && -n "$2" ]] || die "la opción $1 requiere un valor"; }

# Ayuda de subcomando: muestra el texto y sale si se pide --help.
want_help() {
	local a
	for a in "$@"; do [[ "$a" == "-h" || "$a" == "--help" ]] && return 0; done
	return 1
}
