# shellcheck shell=bash
# Acción Integrar: merge o cherry-pick de la rama de un agente en su base,
# en el worktree principal. No cambia de rama, no hace stash ni commits del
# trabajo pendiente, y conserva el worktree y la rama.

accion_integrar() {
	if ! seleccionar_wt "integrar"; then
		cancelado
		return 0
	fi
	local i="$IDX" metodo="$P_METODO"
	local ruta="${A_RUTA[$IDX]}" rama="${A_RAMA[$IDX]}"
	if [[ -z "$metodo" ]]; then
		interactivo || die "falta -Metodo (Merge o CherryPick)"
		if ! elegir "¿Cómo quieres integrar $(wt_etiqueta "$i")?" \
			"Merge (toda la rama, con un merge commit)" "CherryPick (solo los commits que elijas)"; then
			cancelado
			return 0
		fi
		if ((ELEGIDO == 1)); then metodo=Merge; else metodo=CherryPick; fi
	fi

	validar_asignada "$i"
	base_efectiva "$i"
	local base="$BASE"
	rama_local_existe "$base" || die "la base $base no existe como rama local"

	local activa
	activa="$(rama_activa "$REPO" || true)"
	if [[ "$activa" != "$base" ]]; then
		die "el principal tiene activa ${activa:-una HEAD detached}, pero la integración debe hacerse sobre $base. Cámbiala tú (gitctl no cambia de rama): git -C \"$REPO\" switch $base"
	fi
	if operacion_pendiente "$REPO"; then
		die "el principal tiene una operación de Git a medias ($OP_PENDIENTE); termínala o abórtala antes de integrar"
	fi
	calcular_pendiente "$REPO"
	if [[ -z "$PEND_CLEAN" ]]; then
		err "el worktree principal tiene cambios sin confirmar ($PEND_SUMMARY):"
		pendiente_detalle >&2
		die "confírmalos o descártalos antes de integrar (gitctl no hace stash)"
	fi
	if [[ -n "${A_MISSING[i]}" ]]; then
		die "falta la carpeta $ruta; no se puede revisar su trabajo (usa Eliminar para limpiar el registro)"
	fi
	calcular_pendiente "$ruta"
	if [[ -z "$PEND_CLEAN" ]]; then
		err "$(wt_etiqueta "$i") tiene cambios sin confirmar ($PEND_SUMMARY):"
		pendiente_detalle >&2
		die "solo se integra trabajo commiteado: confírmalo o descártalo desde la sesión del agente y repite"
	fi

	local commits
	commits="$(git_ver log --oneline --no-decorate "refs/heads/$base..refs/heads/$rama")"
	[[ -n "$commits" ]] || die "$rama no tiene commits nuevos respecto a $base: no hay nada que integrar"
	echo "Integración de $rama en $base ($metodo):"
	echo "  Commits de $rama que no están en $base:"
	printf '%s\n' "$commits" | sed 's/^/    /'
	echo "  Archivos (git diff --stat $base...$rama):"
	git_ver diff --stat "refs/heads/$base...refs/heads/$rama" | sed 's/^/    /'

	if [[ "$metodo" == Merge ]]; then
		_integrar_merge "$rama" "$base"
	else
		_integrar_cherry_pick "$rama" "$base"
	fi
}

_confirmar_integracion() {
	if interactivo; then
		confirmar "$1" && return 0
		cancelado
		return 1
	fi
	[[ -n "$P_CONF_INT" ]] || die "para integrar sin interacción añade -ConfirmarIntegracion"
	return 0
}

_recordar_pruebas() {
	echo
	info "el worktree y la rama $1 se conservan"
	info "ejecuta ahora las pruebas del proyecto en $REPO; retira el worktree (Eliminar) cuando pasen"
}

_integrar_merge() {
	local rama="$1" base="$2" antes
	_confirmar_integracion "¿Hacer merge de $rama en $base?" || return 0
	antes="$(git -C "$REPO" rev-parse HEAD)"
	if ! git_try "$REPO" merge-tree --write-tree "refs/heads/$base" "refs/heads/$rama"; then
		err "el merge de $rama en $base tendría conflictos:"
		printf '%s\n' "${GIT_LINES[@]:1}" | sed '/^$/d; s/^/    /' >&2
		die "no se ha ejecutado el merge; resuelve los conflictos en la rama del agente (p. ej. git merge $base) y repite"
	fi
	if ! git_try "$REPO" merge --no-ff --no-edit "$rama"; then
		local e="$GIT_ERR$GIT_OUT"
		git -C "$REPO" merge --abort >/dev/null 2>&1 || true
		if [[ "$(git -C "$REPO" rev-parse HEAD)" != "$antes" ]]; then
			err "tras abortar, HEAD del principal no volvió a ${antes:0:12}: revisa el principal a mano"
		fi
		die "falló el merge de $rama: $e"
	fi
	ok "$rama integrada en $base (merge commit $(git -C "$REPO" rev-parse --short HEAD))"
	_recordar_pruebas "$rama"
}

_integrar_cherry_pick() {
	local rama="$1" base="$2" antes c sha
	local -a rango=() elegidos=()
	mapfile -t rango < <(git -C "$REPO" rev-list --reverse "refs/heads/$base..refs/heads/$rama")
	local -A en_rango=() es_merge=() pedido=()
	for c in "${rango[@]}"; do
		en_rango[$c]=1
		(($(git -C "$REPO" rev-list --no-walk --parents -n 1 "$c" | wc -w) > 2)) && es_merge[$c]=1
	done

	if ((${#P_COMMITS[@]})); then
		for c in "${P_COMMITS[@]}"; do
			sha="$(git -C "$REPO" rev-parse --verify -q "$c^{commit}")" || die "no se reconoce el commit «$c»"
			[[ -n "${en_rango[$sha]:-}" ]] || die "el commit $c no pertenece a $base..$rama"
			[[ -z "${es_merge[$sha]:-}" ]] || die "el commit $c es un merge (más de un padre): no se puede seleccionar"
			pedido[$sha]=1
		done
	else
		interactivo || die "faltan -Commits para el cherry-pick sin interacción"
		_elegir_commits "${rango[@]}" || {
			cancelado
			return 0
		}
	fi
	# Orden de rev-list --reverse, sin duplicados.
	for c in "${rango[@]}"; do
		[[ -n "${pedido[$c]:-}" ]] && elegidos+=("$c")
	done
	((${#elegidos[@]})) || die "no se ha seleccionado ningún commit válido"

	echo "  Commits que se aplicarán, en este orden:"
	for c in "${elegidos[@]}"; do
		echo "    $(git -C "$REPO" log -1 --format='%h %s' "$c")"
	done
	_confirmar_integracion "¿Aplicar estos ${#elegidos[@]} commit(s) en $base con cherry-pick?" || return 0
	antes="$(git -C "$REPO" rev-parse HEAD)"
	if ! git_try "$REPO" cherry-pick "${elegidos[@]}"; then
		local e="$GIT_ERR$GIT_OUT"
		git -C "$REPO" cherry-pick --abort >/dev/null 2>&1 || true
		if [[ "$(git -C "$REPO" rev-parse HEAD)" != "$antes" ]]; then
			err "tras abortar, HEAD del principal no volvió a ${antes:0:12}: la restauración es incompleta, revisa el principal a mano"
		fi
		die "falló el cherry-pick: $e"
	fi
	ok "${#elegidos[@]} commit(s) de $rama aplicados en $base"
	_recordar_pruebas "$rama"
}

# Lista numerada de commits; pide números separados por coma → pedido[].
_elegir_commits() {
	local -a l=("$@")
	local i r n
	while :; do
		echo
		echo "Commits de la rama (del más antiguo al más reciente):" >&2
		for i in "${!l[@]}"; do
			if [[ -n "${es_merge[${l[i]}]:-}" ]]; then
				printf '  [%d] %s  (merge: no seleccionable)\n' $((i + 1)) "$(git -C "$REPO" log -1 --format='%h %s' "${l[i]}")" >&2
			else
				printf '  [%d] %s\n' $((i + 1)) "$(git -C "$REPO" log -1 --format='%h %s' "${l[i]}")" >&2
			fi
		done
		echo "  [0] Cancelar" >&2
		leer_linea "Números separados por coma: " || return 1
		r="$(_trim "$RESP")"
		[[ "$r" == 0 ]] && return 1
		local -a nums=()
		lista_dividir nums "$r"
		pedido=()
		local okk=1
		((${#nums[@]})) || okk=""
		for n in "${nums[@]}"; do
			if [[ ! "$n" =~ ^[0-9]+$ ]] || ((10#$n < 1 || 10#$n > ${#l[@]})); then
				warn "número no válido: «$n»"
				okk=""
				break
			fi
			if [[ -n "${es_merge[${l[10#$n - 1]}]:-}" ]]; then
				warn "el [$n] es un merge y no se puede seleccionar"
				okk=""
				break
			fi
			pedido[${l[10#$n - 1]}]=1
		done
		[[ -n "$okk" ]] && return 0
	done
}
