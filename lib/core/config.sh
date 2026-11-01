# shellcheck shell=bash
# Configuración: ~/.config/gitctl/config → .gitctl.conf del worktree principal.
# Formato «clave = valor»; las líneas con # son comentarios. Nunca se ejecuta
# como código: los valores se leen como texto.
#
# Claves: base, copy, setup, remote.

declare -gA GITCTL_CFG=()
GITCTL_CFG_LOADED=""

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
		GITCTL_CFG["$key"]="$val"
	done <"$file"
}

cfg_load() {
	[[ -n "$GITCTL_CFG_LOADED" ]] && return 0
	GITCTL_CFG=()
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
