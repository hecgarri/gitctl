# shellcheck shell=bash
# Acción Evaluar: dictamen consultivo de uno o varios LLM sobre dos propuestas.
# Es la única acción que envía contenido fuera (con confirmación previa).
# No modifica ramas ni referencias.

EV_TMP=""

_ev_limpiar() {
	[[ -n "$PROC_PID" ]] && _matar_grupo "$PROC_PID"
	PROC_PID=""
	if [[ -n "$EV_TMP" ]]; then
		local raiz
		raiz="$(canon "${TMPDIR:-/tmp}")"
		if ruta_dentro "$(canon "$EV_TMP")" "$raiz"; then
			rm -rf -- "$EV_TMP"
		else
			warn "no se borra $EV_TMP: está fuera del directorio temporal"
		fi
		EV_TMP=""
	fi
	return 0
}

accion_evaluar() {
	command -v jq >/dev/null 2>&1 || die "Evaluar necesita jq (sudo apt install jq)"

	# 1. Criterios · 2. Ramas · 3. Proveedor · 4. Preparación y confirmación
	if ! obtener_criterios; then
		cancelado
		return 0
	fi
	if ! obtener_dos_ramas; then
		cancelado
		return 0
	fi
	EV_RAMA1="$RAMA1" EV_RAMA2="$RAMA2"
	local proveedor="$P_PROVEEDOR"
	if [[ -z "$proveedor" ]]; then
		interactivo || die "falta -ProveedorLlm (Codex, Claude, Gemini, Ambos o Todos)"
		if ! elegir "¿Qué LLM quieres consultar?" Codex Claude Gemini \
			"Ambos (Codex y después Claude)" "Todos (Codex, Claude y Gemini)"; then
			cancelado
			return 0
		fi
		proveedor="$(echo Codex Claude Gemini Ambos Todos | cut -d' ' -f"$ELEGIDO")"
	fi

	_ev_precondiciones
	local base="$EV_BASE"

	EV_TMP="$(mktemp -d "$(canon "${TMPDIR:-/tmp}")/gitctl-evaluar.XXXXXXXX")" || die "no se pudo crear el directorio temporal"
	trap _ev_limpiar EXIT
	local paquete="$EV_TMP/paquete.txt"
	construir_paquete "$base" "$EV_RAMA1" "$EV_RAMA2" "$CRITERIOS" "$paquete"

	if ((PAQ_CHARS > P_MAX_CHARS)); then
		die "el paquete tiene $PAQ_CHARS caracteres y supera el límite de $P_MAX_CHARS (-MaxCaracteresLlm). No se recorta: reduce el alcance (menos commits o archivos por propuesta) o aumenta el límite (máximo 1000000)"
	fi
	local hallazgos
	if hallazgos="$(detectar_secretos "$paquete")"; then
		err "el paquete parece contener secretos:"
		printf '%s\n' "$hallazgos" >&2
		die "retira esos valores (de los commits o de los criterios) antes de consultar. Esta detección es heurística: no garantiza que no haya otros secretos"
	fi

	local -a provs
	read -r -a provs <<<"$(lista_proveedores "$proveedor")"
	echo
	echo "Preparado el envío para evaluación:"
	echo "  Proveedor(es):   ${provs[*]}"
	echo "  Ramas:           $EV_RAMA1  vs.  $EV_RAMA2  (base $base)"
	echo "  Criterios:       $CRITERIOS"
	echo "  Tamaño:          $PAQ_CHARS caracteres"
	echo "  SHA-256:         $PAQ_SHA256"
	echo "  Contenido:       criterios, commits y diff completo de cada propuesta desde"
	echo "                   su merge-base, y las diferencias entre ellas"
	if [[ -n "$PAQ_COMPACTO" ]]; then
		echo "  Diff entre propuestas: compactado a --stat (mismo merge-base)"
	else
		echo "  Diff entre propuestas: completo (merge-base distintos)"
	fi
	warn "este contenido se enviará a un proveedor externo"
	if interactivo; then
		if ! confirmar "¿Enviar el paquete a ${provs[*]}?"; then
			_ev_limpiar
			trap - EXIT
			cancelado
			return 0
		fi
	elif [[ -z "$P_CONF_LLM" ]]; then
		die "para enviar sin interacción añade -ConfirmarEnvioLlm"
	fi

	local prov validos=0
	for prov in "${provs[@]}"; do
		if consultar_proveedor "$prov" "$paquete" "$EV_TMP"; then
			mostrar_dictamen "$prov" "$DICTAMEN"
			guardar_dictamen "$prov" "$DICTAMEN"
			ok "dictamen de $prov guardado en $DICTAMEN_RUTA"
			validos=$((validos + 1))
		else
			err "$PROV_ERROR"
		fi
	done
	_ev_limpiar
	trap - EXIT
	((validos > 0)) || die "ningún proveedor produjo un dictamen válido"
	echo
	info "el dictamen es consultivo: no se ha integrado ni modificado nada"
	info "puedes volver a comparar (-Accion Comparar) o integrar (-Accion Integrar) cuando decidas"
}

# Precondiciones de §13 → EV_BASE.
_ev_precondiciones() {
	local r i n idx
	local -a idxs=()
	cargar_inventario
	for r in "$EV_RAMA1" "$EV_RAMA2"; do
		n=0
		for i in "${!A_RUTA[@]}"; do
			if [[ "${A_RAMA[i]}" == "$r" ]]; then
				n=$((n + 1))
				idx="$i"
			fi
		done
		((n == 1)) || die "$r debe corresponder a exactamente un worktree administrado (hay $n)"
		idxs+=("$idx")
	done
	for i in "${idxs[@]}"; do
		[[ -z "${A_MISSING[i]}" ]] || die "falta la carpeta de ${A_AGENTE[i]}/${A_TAREA[i]}: ${A_RUTA[i]}"
		calcular_pendiente "${A_RUTA[i]}"
		if [[ -z "$PEND_CLEAN" ]]; then
			err "${A_AGENTE[i]}/${A_TAREA[i]} tiene cambios sin confirmar ($PEND_SUMMARY):"
			pendiente_detalle >&2
			die "solo se evalúan commits: confírmalos o descártalos desde la sesión del agente"
		fi
	done
	calcular_pendiente "$REPO"
	if [[ -z "$PEND_CLEAN" ]]; then
		err "el worktree principal tiene cambios sin confirmar ($PEND_SUMMARY):"
		pendiente_detalle >&2
		die "deja el principal limpio antes de evaluar"
	fi
	if [[ -n "$P_BASE" ]]; then
		EV_BASE="$P_BASE"
	else
		local -a bases=()
		local b
		for i in "${idxs[@]}"; do
			b="${A_BASEREG[i]}"
			[[ -n "$b" ]] || continue
			[[ " ${bases[*]-} " == *" $b "* ]] || bases+=("$b")
		done
		if ((${#bases[@]} > 1)); then
			die "los worktrees tienen bases registradas distintas (${bases[*]}): indica cuál usar con -Base"
		elif ((${#bases[@]} == 1)); then
			EV_BASE="${bases[0]}"
		else
			requerir_base_def
			EV_BASE="$BASE_DEF"
		fi
	fi
	for r in "$EV_RAMA1" "$EV_RAMA2" "$EV_BASE"; do
		rama_local_existe "$r" || die "$r no existe como rama local"
	done
	return 0
}
