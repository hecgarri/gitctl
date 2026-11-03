# shellcheck shell=bash
# Acción Estado: tabla de worktrees administrados. No modifica nada.

accion_estado() {
	cargar_inventario
	local n=${#A_RUTA[@]} i
	if ((n == 0)); then
		info "no hay worktrees administrados en $RAIZ (crea uno con -Accion Crear)"
		return 0
	fi
	local -a filas=($'Agent\tTask\tBranch\tBase\tPendiente\tIntegration\tMissing\tPath')
	local -a faltan=()
	local rama base pend integ miss
	for i in "${!A_RUTA[@]}"; do
		rama="${A_RAMA[i]:-(detached)}"
		base="$(base_de_wt "$i")"
		if [[ -n "${A_MISSING[i]}" ]]; then
			pend="(sin carpeta)"
			miss="sí"
			faltan+=("${A_AGENTE[i]}/${A_TAREA[i]}")
		else
			calcular_pendiente "${A_RUTA[i]}"
			pend="$PEND_SUMMARY"
			miss="no"
		fi
		integ="$(estado_integracion "${A_RAMA[i]}" "$base")"
		filas+=("${A_AGENTE[i]}"$'\t'"${A_TAREA[i]}"$'\t'"$rama"$'\t'"${base:-(sin base)}"$'\t'"$pend"$'\t'"$integ"$'\t'"$miss"$'\t'"${A_RUTA[i]}")
	done
	tabla "${filas[@]}"
	for i in "${faltan[@]}"; do
		warn "falta la carpeta de $i; Eliminar permite limpiar su registro"
	done
	return 0
}

# tabla <fila>… — columnas separadas por tabuladores, alineadas por caracteres.
tabla() {
	local -a ancho=() campos=()
	local f c j ultimo
	for f in "$@"; do
		IFS=$'\t' read -r -a campos <<<"$f"
		for j in "${!campos[@]}"; do
			c="${campos[j]}"
			((${#c} > ${ancho[j]:-0})) && ancho[j]=${#c}
		done
	done
	for f in "$@"; do
		IFS=$'\t' read -r -a campos <<<"$f"
		ultimo=$((${#campos[@]} - 1))
		for j in "${!campos[@]}"; do
			if ((j == ultimo)); then
				printf '%s\n' "${campos[j]}"
			else
				pad "${campos[j]}" "${ancho[j]}"
				printf '  '
			fi
		done
	done
}
