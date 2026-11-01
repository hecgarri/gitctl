# shellcheck shell=bash
# Configuración: valores por defecto → ~/.config/gitctl/config → .gitctl.conf
# Formato «clave = valor»; las líneas con # son comentarios. Nunca se ejecuta.
#
# IMPORTANTE: .gitctl.conf se lee del worktree principal, no del worktree del
# agente, para que un agente no pueda relajar los checks desde su rama.

declare -gA GITCTL_CFG=()
declare -ga GITCTL_CHECKS=()
GITCTL_CFG_LOADED=""

_cfg_defaults() {
	GITCTL_CFG=(
		[agent.timeout]="30m"
		[verify.timeout]="30m"
		[review.timeout]="20m"
		[review.required]="1"
		[review.max_diff_lines]="2000"
		[review.require_different_adapter]="false"
		[gate.require_approval]="true"
		[gate.protected]=".gitctl.conf .github/workflows/*"
	)
	GITCTL_CHECKS=()
}

_cfg_parse() {
	local file="$1" line key val n=0
	[[ -r "$file" ]] || return 0
	while IFS= read -r line || [[ -n "$line" ]]; do
		n=$((n + 1))
		line="${line#"${line%%[![:space:]]*}"}"
		[[ -z "$line" || "$line" == \#* ]] && continue
		if [[ "$line" != *=* ]]; then
			warn "$file:$n: línea ignorada (falta «=»)"
			continue
		fi
		key="${line%%=*}"
		val="${line#*=}"
		key="${key%"${key##*[![:space:]]}"}"
		val="${val#"${val%%[![:space:]]*}"}"
		val="${val%"${val##*[![:space:]]}"}"
		if [[ "$key" == check.* ]]; then
			local name="${key#check.}"
			[[ -v "GITCTL_CFG[$key]" ]] || GITCTL_CHECKS+=("$name")
		fi
		GITCTL_CFG["$key"]="$val"
	done <"$file"
}

cfg_load() {
	[[ -n "$GITCTL_CFG_LOADED" ]] && return 0
	_cfg_defaults
	_cfg_parse "${XDG_CONFIG_HOME:-$HOME/.config}/gitctl/config"
	if in_git_repo; then
		_cfg_parse "$(git_main_root)/.gitctl.conf"
	fi
	GITCTL_CFG_LOADED=1
}

cfg() {
	cfg_load
	printf '%s' "${GITCTL_CFG[$1]:-${2:-}}"
}

cfg_bool() {
	case "$(cfg "$1" "${2:-false}")" in
	1 | true | yes | si | sí | on) return 0 ;;
	*) return 1 ;;
	esac
}

# Resumen estable de la definición de checks: si cambia, la evidencia antigua caduca.
cfg_checks_digest() {
	cfg_load
	local n
	for n in "${GITCTL_CHECKS[@]}"; do
		printf '%s=%s\n' "$n" "${GITCTL_CFG[check.$n]}"
	done | sha256sum | cut -c1-16
}
