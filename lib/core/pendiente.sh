# shellcheck shell=bash
# Trabajo pendiente (sin confirmar) de un worktree.

# calcular_pendiente <ruta> → PEND_M, PEND_D, PEND_U (rutas), PEND_TOTAL,
# PEND_CLEAN ("1" si está limpio) y PEND_SUMMARY ("limpio", "2 modificados"…).
calcular_pendiente() {
	PEND_M=() PEND_D=() PEND_U=()
	local st f xy salto=""
	st="$(mktemp)"
	if ! git -C "$1" -c core.quotePath=false status --porcelain=v1 -z >"$st"; then
		rm -f "$st"
		die "no se pudo consultar el estado de $1"
	fi
	while IFS= read -r -d '' f; do
		if [[ -n "$salto" ]]; then
			salto=""
			continue
		fi
		xy="${f:0:2}"
		f="${f:3}"
		case "$xy" in
		'??') PEND_U+=("$f") ;;
		'!!') ;;
		*D*) PEND_D+=("$f") ;;
		*) PEND_M+=("$f") ;;
		esac
		# En renombrados y copias, -z añade después la ruta de origen.
		[[ "$xy" == [RC]* ]] && salto=1
	done <"$st"
	rm -f "$st"
	PEND_TOTAL=$((${#PEND_M[@]} + ${#PEND_D[@]} + ${#PEND_U[@]}))
	PEND_CLEAN=""
	((PEND_TOTAL == 0)) && PEND_CLEAN=1
	local -a partes=()
	((${#PEND_M[@]})) && partes+=("${#PEND_M[@]} modificados")
	((${#PEND_D[@]})) && partes+=("${#PEND_D[@]} eliminados")
	((${#PEND_U[@]})) && partes+=("${#PEND_U[@]} sin seguimiento")
	if ((PEND_TOTAL == 0)); then
		PEND_SUMMARY="limpio"
	else
		local IFS=,
		PEND_SUMMARY="${partes[*]}"
		PEND_SUMMARY="${PEND_SUMMARY//,/, }"
	fi
	return 0
}

# Muestra hasta diez rutas pendientes (M, D o ?) del último calcular_pendiente.
pendiente_detalle() {
	local -a l=()
	local p n=0
	for p in "${PEND_M[@]}"; do l+=("M $p"); done
	for p in "${PEND_D[@]}"; do l+=("D $p"); done
	for p in "${PEND_U[@]}"; do l+=("? $p"); done
	for p in "${l[@]}"; do
		((n < 10)) || break
		printf '    %s\n' "$p"
		n=$((n + 1))
	done
	if ((${#l[@]} > 10)); then
		printf '    … y %d más\n' $((${#l[@]} - 10))
	fi
	return 0
}

# Estado de integración de <rama> respecto de <base>:
# SinRama | BaseInexistente | Fusionada | EquivalentePorCherryPick | Pendiente
estado_integracion() {
	local rama="$1" base="$2"
	if [[ -z "$rama" ]] || ! rama_local_existe "$rama"; then
		echo SinRama
	elif [[ -z "$base" ]] || ! rama_local_existe "$base"; then
		echo BaseInexistente
	elif git -C "$REPO" merge-base --is-ancestor "refs/heads/$rama" "refs/heads/$base"; then
		echo Fusionada
	elif [[ -z "$(git -C "$REPO" rev-list --merges "refs/heads/$base..refs/heads/$rama")" ]] &&
		! grep -q '^+' <<<"$(git -C "$REPO" cherry "refs/heads/$base" "refs/heads/$rama")"; then
		echo EquivalentePorCherryPick
	else
		echo Pendiente
	fi
}
