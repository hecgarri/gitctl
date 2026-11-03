# shellcheck shell=bash
# Repositorio, raíz de worktrees, rama base e identificadores.

REPO="" RAIZ="" BASE_DEF=""

canon() { realpath -m -- "$1"; }

# ¿<hijo> está dentro de <padre> (sin ser igual)? Respeta los separadores:
# /a/foo no está dentro de /a/fo.
ruta_dentro() {
	local h="$1" p="${2%/}"
	[[ "$h" == "$p/"* ]]
}

resolver_contexto() {
	local p="${P_REPO:-$PWD}" top first
	[[ -e "$p" ]] || die "la ruta del repositorio no existe: $p"
	[[ -d "$p" ]] || die "la ruta del repositorio no es un directorio: $p"
	git_try "$p" rev-parse --show-toplevel || die "$p no está dentro de un repositorio Git"
	top="$(canon "$GIT_OUT")"
	git_run "$top" worktree list --porcelain
	first="${GIT_LINES[0]#worktree }"
	first="$(canon "$first")"
	if [[ "$top" != "$first" ]]; then
		die "$top es un worktree secundario; ejecuta gitctl desde el worktree principal: $first"
	fi
	REPO="$first"

	BASE_DEF="$(rama_activa "$REPO" || true)"
	if [[ -n "$P_BASE" ]] && ! rama_local_existe "$P_BASE"; then
		die "la base «$P_BASE» no existe como rama local (no se aceptan SHA, etiquetas ni ramas solo remotas)"
	fi

	if [[ -n "$P_RAIZ" ]]; then
		RAIZ="$(canon "$P_RAIZ")"
	else
		RAIZ="$(canon "$(dirname "$REPO")/$(basename "$REPO")-agents")"
	fi
	if [[ "$RAIZ" == "$REPO" ]]; then
		die "la raíz de worktrees no puede ser el propio repositorio ($REPO)"
	fi
	if ruta_dentro "$RAIZ" "$REPO"; then
		die "la raíz de worktrees ($RAIZ) no puede estar dentro del repositorio"
	fi
	if ruta_dentro "$REPO" "$RAIZ"; then
		die "la raíz de worktrees ($RAIZ) no puede contener al repositorio"
	fi
	return 0
}

# La base por defecto es la rama activa del principal al iniciar.
requerir_base_def() {
	[[ -n "$BASE_DEF" ]] && return 0
	die "el worktree principal está en detached HEAD: indica la rama base con -Base"
}

# normalizar_id <agente|tarea> <valor> → NORM
normalizar_id() {
	local tipo="$1" v az='abcdefghijklmnopqrstuvwxyz0123456789'
	v="$(_trim "$2")"
	v="${v,,}"
	v="$(sed -E 's/[[:space:]_]+/-/g' <<<"$v")"
	[[ -n "$v" ]] || die "el identificador de $tipo está vacío"
	if [[ "$v" == . || "$v" == .. ]]; then
		die "identificador de $tipo no válido: «$v»"
	fi
	if [[ ! "$v" =~ ^[$az][$az._-]*$ ]]; then
		die "identificador de $tipo no válido: «$2» (usa minúsculas, números, «.», «-» o «_», empezando por letra o número)"
	fi
	if [[ "$v" == *.lock ]]; then
		die "identificador de $tipo no válido: «$v» (no puede terminar en .lock)"
	fi
	if [[ "$v" == *..* ]]; then
		die "identificador de $tipo no válido: «$v» (no puede contener «..»)"
	fi
	NORM="$v"
}

# ruta_de <agente> <tarea> → RUTA (<raíz>/<agente>/<tarea>, siempre dentro de la raíz)
ruta_de() {
	RUTA="$(canon "$RAIZ/$1/$2")"
	if ! ruta_dentro "$RUTA" "$RAIZ" || [[ "${RUTA#"$RAIZ"/}" != "$1/$2" ]]; then
		die "la ruta calculada $RUTA queda fuera de la raíz $RAIZ"
	fi
}
