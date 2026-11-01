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

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_epoch() { date +%s; }

rand_hex() { od -An -N"${1:-3}" -tx1 /dev/urandom | tr -d ' \n'; }

# Identificadores válidos para tareas y agentes (seguros para ramas y rutas).
valid_name() { [[ "$1" =~ ^[a-z0-9][a-z0-9._-]{0,47}$ && "$1" != *..* ]]; }
check_name() { valid_name "$2" || die "$1 no válido: «$2» (usa minúsculas, dígitos, . _ -)"; }

# Escribe stdin en un fichero de forma atómica (tmp + mv en el mismo directorio).
atomic_write() {
	local dest="$1" tmp
	tmp="$(mktemp "${dest}.tmp.XXXXXX")"
	cat >"$tmp"
	mv -f "$tmp" "$dest"
}

sha256_file() { sha256sum "$1" | cut -d' ' -f1; }

# Convierte duraciones tipo 30m, 2h, 90s, 45 (segundos) en segundos.
duration_secs() {
	local d="$1"
	case "$d" in
	*h) echo $((${d%h} * 3600)) ;;
	*m) echo $((${d%m} * 60)) ;;
	*s) echo "${d%s}" ;;
	*[!0-9]* | "") die "duración no válida: $d" ;;
	*) echo "$d" ;;
	esac
}

fmt_secs() {
	local s="${1:-0}"
	if ((s >= 3600)); then
		printf '%dh%02dm' $((s / 3600)) $((s % 3600 / 60))
	elif ((s >= 60)); then
		printf '%dm%02ds' $((s / 60)) $((s % 60))
	else
		printf '%ds' "$s"
	fi
}

# Sustituye {{CLAVE}} por un valor en una plantilla (sin interpretar & ni \).
template_sub() {
	local tpl="$1" key="$2" val="$3"
	printf '%s' "${tpl//"{{$key}}"/"$val"}"
}

# Comprueba que el siguiente argumento existe para una opción con valor.
need_arg() { [[ $# -ge 2 && -n "$2" ]] || die "la opción $1 requiere un valor"; }

# Ayuda de subcomando: muestra el texto y sale si se pide --help.
want_help() {
	local a
	for a in "$@"; do [[ "$a" == "-h" || "$a" == "--help" ]] && return 0; done
	return 1
}
