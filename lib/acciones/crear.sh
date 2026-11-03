# shellcheck shell=bash
# Acción Crear: rama <agente>/<tarea> + worktree bloqueado con sus metadatos.

accion_crear() {
	local agente="$P_AGENTE" tarea="$P_TAREA" rama ruta base sha motivo
	if [[ -z "$agente" ]]; then
		interactivo || die "falta -Agente (por ejemplo: -Agente codex)"
		if ! elegir "¿Qué agente trabajará en la tarea?" Claude Codex Gemini; then
			cancelado
			return 0
		fi
		case "$ELEGIDO" in
		1) agente=claude ;;
		2) agente=codex ;;
		3) agente=gemini ;;
		esac
	fi
	if [[ -z "$tarea" ]]; then
		interactivo || die "falta -Tarea (por ejemplo: -Tarea corregir-api)"
		if ! leer_linea "Identificador de la tarea (vacío para cancelar): " || [[ -z "$(_trim "$RESP")" ]]; then
			cancelado
			return 0
		fi
		tarea="$RESP"
	fi
	normalizar_id agente "$agente"
	agente="$NORM"
	normalizar_id tarea "$tarea"
	tarea="$NORM"
	rama="$agente/$tarea"
	ruta_de "$agente" "$tarea"
	ruta="$RUTA"
	if [[ -n "$P_BASE" ]]; then
		base="$P_BASE"
	else
		requerir_base_def
		base="$BASE_DEF"
	fi
	sha="$(sha_de_rama "$base")" || die "la base $base no existe como rama local"
	if rama_local_existe "$rama"; then
		die "la rama $rama ya existe; usa otra tarea o retira antes el worktree anterior"
	fi
	if [[ -e "$ruta" || -L "$ruta" ]]; then
		die "la ruta $ruta ya existe; no se sobrescribe"
	fi

	echo "Se creará el worktree:"
	echo "  Agente: $agente"
	echo "  Tarea:  $tarea"
	echo "  Rama:   $rama"
	echo "  Ruta:   $ruta"
	echo "  Base:   $base @ $sha"
	if interactivo && ! confirmar "¿Crear el worktree?"; then
		cancelado
		return 0
	fi

	# Directorios que no existían (para revertirlos si algo falla).
	local -a creados=()
	local d
	d="$(dirname "$ruta")"
	while [[ ! -e "$d" ]]; do
		creados+=("$d")
		d="$(dirname "$d")"
	done
	mkdir -p "$(dirname "$ruta")" || die "no se pudo crear $(dirname "$ruta")"

	motivo="$(motivo_bloqueo "$agente" "$tarea" "$base" "$sha")"
	if ! git_try "$REPO" worktree add -b "$rama" "$ruta" "$sha"; then
		local e="$GIT_ERR"
		_crear_revertir "$rama" "$ruta" "$sha" "${creados[@]}"
		die "no se pudo crear el worktree: $e"
	fi
	if ! git_try "$REPO" worktree lock --reason "$motivo" "$ruta"; then
		local e="$GIT_ERR"
		_crear_revertir "$rama" "$ruta" "$sha" "${creados[@]}"
		die "no se pudo bloquear el worktree (se ha revertido la creación): $e"
	fi
	ok "worktree creado y bloqueado"
	echo "  Abre el agente en: $ruta"
	echo "  Rama asignada:     $rama"
}

# Deshace lo que se acaba de crear, sin tocar lo que existía antes.
_crear_revertir() {
	local rama="$1" ruta="$2" sha="$3" d
	shift 3
	if grep -qxF "worktree $ruta" <<<"$(git -C "$REPO" worktree list --porcelain)"; then
		git -C "$REPO" worktree unlock "$ruta" >/dev/null 2>&1 || true
		git -C "$REPO" worktree remove --force "$ruta" >/dev/null 2>&1 ||
			warn "no se pudo retirar el worktree a medio crear: $ruta"
	elif [[ -d "$ruta" ]]; then
		rm -rf -- "$ruta"
	fi
	if rama_local_existe "$rama"; then
		git -C "$REPO" update-ref -d "refs/heads/$rama" "$sha" 2>/dev/null ||
			warn "no se pudo eliminar la rama recién creada $rama"
	fi
	for d in "$@"; do
		rmdir -- "$d" 2>/dev/null || true
	done
	return 0
}
