# shellcheck shell=bash
# Acción Eliminar: retira un worktree administrado y, si estaba fusionada, su rama.
#
#   -CerrarSinIntegrar  retirar aunque la rama no esté integrada (se conserva)
#   -Forzar             descartar cambios sin confirmar
#   -ConfirmarEliminacion  confirmación obligatoria sin interacción
# Son independientes: ninguno sustituye a otro.

accion_eliminar() {
	if ! seleccionar_wt "retirar"; then
		cancelado
		return 0
	fi
	local i="$IDX"
	local ruta="${A_RUTA[$i]}" rama="${A_RAMA[$i]}" missing="${A_MISSING[$i]}"
	validar_asignada "$i"
	base_efectiva "$i"
	local base="$BASE" estado sha
	estado="$(estado_integracion "$rama" "$base")"
	sha="$(sha_de_rama "$rama" || true)"

	if [[ "$estado" != Fusionada && "$estado" != EquivalentePorCherryPick ]]; then
		if [[ -z "$P_CERRAR" ]]; then
			if ! interactivo; then
				die "$rama no está integrada en $base (estado: $estado). Para retirar el worktree conservando la rama añade -CerrarSinIntegrar"
			fi
			if [[ "$estado" == Pendiente ]]; then
				echo "Commits de $rama que no están en $base:"
				git_ver log --oneline --no-decorate "refs/heads/$base..refs/heads/$rama" | sed 's/^/    /'
			fi
			if ! confirmar "$rama no está integrada en $base ($estado). ¿Retirar el worktree conservando la rama?"; then
				cancelado
				return 0
			fi
		fi
	fi

	local descartar="" ya_confirmado="" rescate="$P_RESCATE" pend="(sin carpeta)" total=0
	if [[ -z "$missing" ]]; then
		calcular_pendiente "$ruta"
		pend="$PEND_SUMMARY"
		total="$PEND_TOTAL"
	else
		PEND_CLEAN=1
	fi
	if [[ -z "$PEND_CLEAN" ]]; then
		if ! interactivo; then
			if [[ -z "$P_FORZAR" ]]; then
				err "$ruta tiene cambios sin confirmar ($PEND_SUMMARY):"
				pendiente_detalle >&2
				echo "  Puedes confirmarlos (commit) desde la sesión del agente, o repetir con -Forzar para descartarlos." >&2
				echo "  Con -RescatarCambios <carpeta> se copian antes los archivos modificados y sin seguimiento." >&2
				exit 1
			fi
			descartar=1
		elif [[ -n "$P_FORZAR" ]]; then
			descartar=1
		else
			echo "$ruta tiene cambios sin confirmar ($PEND_SUMMARY):"
			pendiente_detalle
			warn "descartarlos es irreversible"
			if ! confirmar "¿Descartar estos cambios y retirar el worktree?"; then
				cancelado
				return 0
			fi
			descartar=1
			ya_confirmado=1
			if [[ -z "$rescate" ]] && confirmar "¿Guardar antes una copia de los archivos modificados y sin seguimiento?"; then
				while :; do
					leer_linea "Carpeta donde copiarlos: " || {
						cancelado
						return 0
					}
					rescate="$(_trim "$RESP")"
					[[ -n "$rescate" ]] && break
					warn "indica una carpeta"
				done
			fi
		fi
	elif [[ -n "$rescate" ]]; then
		info "el worktree no tiene cambios sin confirmar: no hay nada que rescatar"
		rescate=""
	fi

	local conservar=1
	[[ "$estado" == Fusionada ]] && conservar=""
	echo "Se retirará el worktree:"
	echo "  Ruta:        $ruta"
	echo "  Rama:        $rama"
	echo "  Base:        $base"
	echo "  Integración: $estado"
	echo "  Pendiente:   $pend"
	[[ -n "$missing" ]] && echo "  Carpeta:     no existe (solo se limpia su registro)"
	[[ -n "$descartar" ]] && echo "  Se descartarán $total cambio(s) sin confirmar"
	[[ -n "$rescate" ]] && echo "  Rescate:     $(canon "$rescate")"
	if [[ -n "$conservar" ]]; then
		echo "  La rama $rama se conservará"
	else
		echo "  La rama $rama se eliminará (está fusionada en $base)"
	fi

	if ! interactivo; then
		[[ -n "$P_CONF_ELIM" ]] || die "para retirar sin interacción añade -ConfirmarEliminacion"
	elif [[ -z "$ya_confirmado" ]] && ! confirmar "¿Retirar el worktree?"; then
		cancelado
		return 0
	fi

	[[ -n "$rescate" ]] && rescatar_cambios "$ruta" "$rescate"

	if [[ -n "${A_LOCK[i]}" ]]; then
		git_run "$REPO" worktree unlock "$ruta"
	fi
	local -a rm_args=(worktree remove)
	[[ -n "$descartar" ]] && rm_args+=(--force)
	if ! git_try "$REPO" "${rm_args[@]}" "$ruta"; then
		local e="$GIT_ERR"
		if [[ -n "${A_LOCK[i]}" ]]; then
			git -C "$REPO" worktree lock --reason "${A_MOTIVO[i]}" "$ruta" >/dev/null 2>&1 || true
		fi
		die "no se pudo retirar $ruta: $e"
	fi

	if [[ -z "$conservar" ]]; then
		if git_try "$REPO" update-ref -d "refs/heads/$rama" "$sha"; then
			ok "se retiró el worktree $ruta y su rama $rama"
		else
			warn "se retiró el worktree, pero la rama $rama cambió desde que se verificó su integración: se conserva"
		fi
	else
		ok "se retiró el worktree $ruta; la rama $rama se conserva"
		case "$estado" in
		EquivalentePorCherryPick) info "sus parches ya están en $base, pero la historia no es la misma: bórrala tú si ya no la necesitas (git branch -D $rama)" ;;
		*) info "la rama no estaba integrada; sigue disponible con sus commits" ;;
		esac
	fi
	return 0
}

# rescatar_cambios <worktree> <destino> — copia los archivos modificados y sin
# seguimiento (del último calcular_pendiente), conservando las rutas relativas.
# Es una copia del contenido actual: no guarda el índice ni el staging.
rescatar_cambios() {
	local wt dest p src rel f n=0
	wt="$(canon "$1")"
	dest="$(canon "$2")"
	if [[ "$dest" == "$wt" ]] || ruta_dentro "$dest" "$wt"; then
		die "la carpeta de rescate no puede ser el worktree ni estar dentro de él: $dest"
	fi
	local -a archivos=()
	for p in "${PEND_M[@]}" "${PEND_U[@]}"; do
		src="$(canon "$wt/$p")"
		ruta_dentro "$src" "$wt" || die "la ruta $p sale del worktree; no se rescata nada"
		if [[ -d "$src" && ! -L "$src" ]]; then
			while IFS= read -r -d '' f; do archivos+=("$f"); done < <(find "$src" \( -type f -o -type l \) -print0)
		elif [[ -e "$src" || -L "$src" ]]; then
			archivos+=("$src")
		fi
	done
	mkdir -p -- "$dest" || die "no se pudo crear la carpeta de rescate $dest; no se retira el worktree"
	for src in "${archivos[@]}"; do
		rel="${src#"$wt"/}"
		if ! mkdir -p -- "$dest/$(dirname "$rel")" || ! cp -P -- "$src" "$dest/$rel"; then
			die "falló la copia de $rel; no se retira el worktree"
		fi
		n=$((n + 1))
	done
	ok "copiados $n archivo(s) en $dest"
	if ((${#PEND_D[@]})); then
		info "${#PEND_D[@]} archivo(s) eliminados no se copian: siguen en la historia de Git (git show HEAD:<ruta>)"
	fi
	info "el rescate es una copia del contenido actual, no un stash: no conserva el staging"
}
