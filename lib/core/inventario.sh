# shellcheck shell=bash
# Inventario de worktrees administrados, reconstruido cada vez desde
# «git worktree list --porcelain». No hay base de datos propia: la base
# registrada vive en el motivo del bloqueo.
#
#   Agente=<agente>; Tarea=<tarea>; Base=<rama-base>@<sha-base>

motivo_bloqueo() { printf 'Agente=%s; Tarea=%s; Base=%s@%s' "$1" "$2" "$3" "$4"; }

# Nombre de la base registrada en un motivo de bloqueo (puede contener «@»).
base_de_motivo() {
	local re='(^|; )Base=(.+)@([0-9a-f]{40,64})$'
	if [[ "$1" =~ $re ]]; then printf '%s' "${BASH_REMATCH[2]}"; fi
	return 0
}

# cargar_inventario → arrays paralelos A_* ordenados por agente y tarea.
cargar_inventario() {
	A_AGENTE=() A_TAREA=() A_RUTA=() A_HEAD=() A_RAMA=() A_LOCK=() A_MOTIVO=() A_MISSING=() A_BASEREG=()
	local listado
	listado="$(mktemp)"
	git -C "$REPO" worktree list --porcelain -z >"$listado" || {
		rm -f "$listado"
		die "no se pudo leer la lista de worktrees"
	}
	local -a t_ag=() t_ta=() t_ru=() t_he=() t_ra=() t_lo=() t_mo=()
	local f ruta="" head="" rama="" lock="" motivo=""
	while IFS= read -r -d '' f; do
		case "$f" in
		"worktree "*) ruta="${f#worktree }" ;;
		"HEAD "*) head="${f#HEAD }" ;;
		"branch "*) rama="${f#branch refs/heads/}" ;;
		locked) lock=1 ;;
		"locked "*)
			lock=1
			motivo="${f#locked }"
			;;
		"")
			if [[ -n "$ruta" ]]; then
				local c rel
				c="$(canon "$ruta")"
				if ruta_dentro "$c" "$RAIZ"; then
					rel="${c#"$RAIZ"/}"
					if [[ "$rel" == */* && "$rel" != */*/* && "$rel" != /* && "$rel" != */ ]]; then
						t_ag+=("${rel%%/*}") t_ta+=("${rel#*/}") t_ru+=("$c") t_he+=("$head")
						t_ra+=("$rama") t_lo+=("$lock") t_mo+=("$motivo")
					fi
				fi
			fi
			ruta="" head="" rama="" lock="" motivo=""
			;;
		esac
	done <"$listado"
	rm -f "$listado"

	local i
	while IFS=$'\t' read -r _ _ i; do
		[[ -n "$i" ]] || continue
		A_AGENTE+=("${t_ag[i]}") A_TAREA+=("${t_ta[i]}") A_RUTA+=("${t_ru[i]}")
		A_HEAD+=("${t_he[i]}") A_RAMA+=("${t_ra[i]}") A_LOCK+=("${t_lo[i]}") A_MOTIVO+=("${t_mo[i]}")
		if [[ -d "${t_ru[i]}" ]]; then A_MISSING+=(""); else A_MISSING+=(1); fi
		A_BASEREG+=("$(base_de_motivo "${t_mo[i]}")")
	done < <(for i in "${!t_ag[@]}"; do printf '%s\t%s\t%s\n' "${t_ag[i]}" "${t_ta[i]}" "$i"; done | LC_ALL=C sort -t $'\t' -k1,1 -k2,2)
	return 0
}

# buscar_wt <agente> <tarea> → IDX. Devuelve 1 si no existe.
buscar_wt() {
	local i
	for i in "${!A_RUTA[@]}"; do
		if [[ "${A_AGENTE[i]}" == "$1" && "${A_TAREA[i]}" == "$2" ]]; then
			IDX="$i"
			return 0
		fi
	done
	return 1
}

# Etiqueta para las listas: agente/tarea y, si procede, su situación.
wt_etiqueta() {
	local i="$1" s="${A_AGENTE[$1]}/${A_TAREA[$1]}"
	if [[ -z "${A_RAMA[i]}" ]]; then
		s+=" (detached)"
	elif [[ "${A_RAMA[i]}" != "${A_AGENTE[i]}/${A_TAREA[i]}" ]]; then
		s+=" (rama activa: ${A_RAMA[i]})"
	fi
	[[ -n "${A_MISSING[i]}" ]] && s+=" (sin carpeta)"
	printf '%s' "$s"
}

# base_de_wt <i> → base efectiva: -Base, la registrada o la por defecto (o vacío).
base_de_wt() {
	if [[ -n "$P_BASE" ]]; then
		printf '%s' "$P_BASE"
	elif [[ -n "${A_BASEREG[$1]}" ]]; then
		printf '%s' "${A_BASEREG[$1]}"
	else
		printf '%s' "$BASE_DEF"
	fi
}

# base_efectiva <i> → BASE; aborta si no hay ninguna.
base_efectiva() {
	BASE="$(base_de_wt "$1")"
	[[ -n "$BASE" ]] || requerir_base_def
}

# seleccionar_wt "<verbo>" → IDX (por -Agente/-Tarea o con una lista).
# Devuelve 1 si el usuario cancela.
seleccionar_wt() {
	local verbo="$1" a t i
	cargar_inventario
	if [[ -n "$P_AGENTE" && -n "$P_TAREA" ]]; then
		normalizar_id agente "$P_AGENTE"
		a="$NORM"
		normalizar_id tarea "$P_TAREA"
		t="$NORM"
		buscar_wt "$a" "$t" || die "no hay un worktree administrado para $a/$t en $RAIZ (consulta -Accion Estado)"
		return 0
	fi
	interactivo || die "faltan -Agente y -Tarea para $verbo sin interacción"
	if ((${#A_RUTA[@]} == 0)); then
		info "no hay worktrees administrados en $RAIZ"
		return 1
	fi
	local -a etiquetas=()
	for i in "${!A_RUTA[@]}"; do etiquetas+=("$(wt_etiqueta "$i")"); done
	elegir "¿Qué worktree quieres $verbo?" "${etiquetas[@]}" || return 1
	IDX=$((ELEGIDO - 1))
}

# Rama asignada: la que corresponde a agente/tarea. Antes de Integrar o
# Eliminar debe ser la activa. Ni -Forzar ni -CerrarSinIntegrar lo saltan.
validar_asignada() {
	local i="$1" esperada="${A_AGENTE[$1]}/${A_TAREA[$1]}" ruta="${A_RUTA[$1]}"
	local actual="${A_RAMA[i]}" head="${A_HEAD[i]}"
	if [[ -z "$actual" ]]; then
		err "$ruta está en detached HEAD (${head:0:12}); su rama asignada es $esperada"
		if [[ -z "$(git -C "$REPO" for-each-ref --contains "$head" --format='%(refname)' refs/heads/)" ]]; then
			warn "el commit ${head:0:12} no está en ninguna rama local: podría perderse al retirar el worktree"
			echo "  Guárdalo antes con: git -C \"$ruta\" branch <nombre> HEAD" >&2
		fi
		echo "  Vuelve a la rama asignada con: git -C \"$ruta\" switch $esperada" >&2
		exit 1
	fi
	if [[ "$actual" != "$esperada" ]]; then
		err "$ruta tiene activa la rama $actual, pero su rama asignada es $esperada"
		echo "  Vuelve a la rama asignada con: git -C \"$ruta\" switch $esperada" >&2
		exit 1
	fi
	return 0
}
