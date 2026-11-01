# shellcheck shell=bash
# Mensajes al usuario. Los datos van a stdout; los mensajes, a stderr.

GITCTL_QUIET="${GITCTL_QUIET:-}"
GITCTL_VERBOSE="${GITCTL_VERBOSE:-}"

_use_color() { [[ -t 2 && -z "${NO_COLOR:-}" ]]; }

_msg() {
	local color="$1" prefix="$2"
	shift 2
	if _use_color; then
		printf '\033[%sm%s\033[0m %s\n' "$color" "$prefix" "$*" >&2
	else
		printf '%s %s\n' "$prefix" "$*" >&2
	fi
}

info() { [[ -n "$GITCTL_QUIET" ]] || _msg "1;34" "==>" "$@"; }
ok() { [[ -n "$GITCTL_QUIET" ]] || _msg "1;32" "✓" "$@"; }
warn() { _msg "1;33" "aviso:" "$@"; }
debug() { [[ -z "$GITCTL_VERBOSE" ]] || _msg "2" "debug:" "$@"; }
err() { _msg "1;31" "error:" "$@"; }
die() {
	err "$@"
	exit 1
}

# Marca de estado para informes: mark ok|fail|warn|skip texto
mark() {
	local kind="$1"
	shift
	local sym color
	case "$kind" in
	ok) sym="✓" color="32" ;;
	fail) sym="✗" color="31" ;;
	warn) sym="!" color="33" ;;
	*) sym="-" color="2" ;;
	esac
	if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
		printf '  \033[%sm%s\033[0m %s\n' "$color" "$sym" "$*"
	else
		printf '  %s %s\n' "$sym" "$*"
	fi
}
