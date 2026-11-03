# shellcheck shell=bash
# Acción Comparar: compara solo commits entre dos ramas locales. No modifica nada.

# obtener_dos_ramas → RAMA1, RAMA2 (por -Ramas o eligiendo dos worktrees).
# RAMAS_ELEGIDAS=1 si se eligieron con el selector. Devuelve 1 si se cancela.
obtener_dos_ramas() {
	RAMAS_ELEGIDAS=""
	if ((${#P_RAMAS[@]})); then
		((${#P_RAMAS[@]} == 2)) || die "-Ramas necesita exactamente dos ramas (recibidas: ${#P_RAMAS[@]})"
		RAMA1="${P_RAMAS[0]}" RAMA2="${P_RAMAS[1]}"
		[[ "$RAMA1" != "$RAMA2" ]] || die "las dos ramas deben ser distintas: $RAMA1"
		local r
		for r in "$RAMA1" "$RAMA2"; do
			rama_local_existe "$r" || die "$r no existe como rama local"
		done
		return 0
	fi
	interactivo || die "faltan las dos ramas: -Ramas \"agente1/tarea,agente2/tarea\""
	cargar_inventario
	if ((${#A_RUTA[@]} < 2)); then
		info "se necesitan al menos dos worktrees administrados (hay ${#A_RUTA[@]})"
		return 1
	fi
	local -a etiquetas=()
	local i
	for i in "${!A_RUTA[@]}"; do etiquetas+=("$(wt_etiqueta "$i")"); done
	elegir_dos "${etiquetas[@]}" || return 1
	for i in "$SEL1" "$SEL2"; do
		[[ -n "${A_RAMA[i - 1]}" ]] || die "${A_AGENTE[i - 1]}/${A_TAREA[i - 1]} está en detached HEAD: no tiene una rama que comparar"
	done
	RAMA1="${A_RAMA[SEL1 - 1]}" RAMA2="${A_RAMA[SEL2 - 1]}"
	RAMAS_ELEGIDAS=1
}

# Avisa del trabajo sin confirmar de los worktrees de esas ramas (queda fuera).
# → HAY_PENDIENTE=1 si alguno tiene cambios.
avisar_pendiente_ramas() {
	local i
	HAY_PENDIENTE=""
	cargar_inventario
	for i in "${!A_RUTA[@]}"; do
		[[ "${A_RAMA[i]}" == "$1" || "${A_RAMA[i]}" == "$2" ]] || continue
		if [[ -n "${A_MISSING[i]}" ]]; then
			warn "${A_AGENTE[i]}/${A_TAREA[i]}: falta su carpeta; no se puede revisar su trabajo pendiente"
			continue
		fi
		calcular_pendiente "${A_RUTA[i]}"
		echo "  ${A_AGENTE[i]}/${A_TAREA[i]} (${A_RAMA[i]}): $PEND_SUMMARY"
		if [[ -z "$PEND_CLEAN" ]]; then
			HAY_PENDIENTE=1
			pendiente_detalle
			warn "esos cambios sin confirmar de ${A_AGENTE[i]}/${A_TAREA[i]} quedan fuera de la comparación"
		fi
	done
	return 0
}

accion_comparar() {
	obtener_dos_ramas || {
		cancelado
		return 0
	}
	local a="$RAMA1" b="$RAMA2" completo="$P_DIFF_COMPLETO"
	if [[ -n "$RAMAS_ELEGIDAS" ]] && confirmar "¿Mostrar el diff completo (en lugar del resumen --stat)?"; then
		completo=1
	fi
	echo
	echo "Se comparan solo los cambios confirmados (commits) de $a y $b."
	echo "Los cambios sin confirmar de los worktrees no forman parte de la comparación."
	avisar_pendiente_ramas "$a" "$b"

	echo
	echo "== Commits que solo están en $a =="
	_listar_o_nada "$(git_ver log --oneline --no-decorate "refs/heads/$b..refs/heads/$a")" "(ninguno)"
	echo
	echo "== Commits que solo están en $b =="
	_listar_o_nada "$(git_ver log --oneline --no-decorate "refs/heads/$a..refs/heads/$b")" "(ninguno)"
	echo
	echo "== Diferencias entre los árboles de $a y $b =="
	if git -C "$REPO" diff --quiet "refs/heads/$a" "refs/heads/$b"; then
		echo "(sin diferencias entre commits)"
	elif [[ -n "$completo" ]]; then
		git_ver diff "refs/heads/$a" "refs/heads/$b"
	else
		git_ver diff --stat "refs/heads/$a" "refs/heads/$b"
	fi
	if [[ -n "$HAY_PENDIENTE" ]]; then
		echo
		warn "recuerda: hay cambios sin confirmar (listados arriba) que no se han comparado"
	fi
	return 0
}

_listar_o_nada() {
	if [[ -n "$1" ]]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi
}
