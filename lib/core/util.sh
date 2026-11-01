# shellcheck shell=bash
# Utilidades generales.

GITCTL_YES="${GITCTL_YES:-}"

require_cmd() {
	local c
	for c in "$@"; do
		command -v "$c" >/dev/null 2>&1 || die "falta la herramienta «$c»; instálala (ver gitctl doctor)"
	done
}

# confirm "pregunta" → 0 si el usuario acepta. Sin TTY y sin --yes: rechaza.
confirm() {
	[[ -n "$GITCTL_YES" ]] && return 0
	if [[ ! -t 0 ]]; then
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
