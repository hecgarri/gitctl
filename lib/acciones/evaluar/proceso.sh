# shellcheck shell=bash
# Ejecución de las CLIs de los proveedores con límite de tiempo, progreso y
# cancelación. Cada consulta corre en su propio grupo de procesos (setsid),
# para poder detenerla junto con sus procesos hijos.

PROC_PID=""

# _matar_grupo <pid> — TERM y, si sigue vivo, KILL a todo el grupo.
_matar_grupo() {
	local pid="$1" k
	kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
	for k in 1 2 3 4 5 6 7 8 9 10; do
		kill -0 -- "-$pid" 2>/dev/null || break
		sleep 0.2
	done
	kill -KILL -- "-$pid" 2>/dev/null || true
	wait "$pid" 2>/dev/null || true
}

# ejecutar_proceso <nombre> <segundos> <stdin> <stdout> <stderr> <dir> <progreso:1|""> -- <cmd> args…
# → PROC_RC (124 = tiempo agotado), PROC_SEGUNDOS. Ctrl+C detiene la consulta y aborta.
ejecutar_proceso() {
	local nombre="$1" limite="$2" in="$3" out="$4" errf="$5" dir="$6" progreso="$7"
	shift 8
	local cmd
	cmd="$(command -v -- "$1")" || {
		PROC_RC=127
		PROC_SEGUNDOS=0
		printf 'no se encontró el comando «%s»\n' "$1" >"$errf"
		return 0
	}
	shift
	local inicio=$SECONDS t ultimo=0 interrumpido=""
	(cd -- "$dir" && exec setsid -w "$cmd" "$@" <"$in" >"$out" 2>"$errf") &
	PROC_PID=$!
	trap 'interrumpido=1' INT TERM
	while kill -0 "$PROC_PID" 2>/dev/null; do
		[[ -n "$interrumpido" ]] && break
		t=$((SECONDS - inicio))
		if ((t >= limite)); then
			break
		fi
		if [[ -n "$progreso" ]] && ((t - ultimo >= 5)); then
			ultimo=$t
			printf '  … %s: %d s transcurridos (límite %d s)\n' "$nombre" "$t" "$limite" >&2
		fi
		sleep 0.2
	done
	PROC_SEGUNDOS=$((SECONDS - inicio))
	if kill -0 "$PROC_PID" 2>/dev/null; then
		_matar_grupo "$PROC_PID"
		trap - INT TERM
		PROC_PID=""
		if [[ -n "$interrumpido" ]]; then
			die "consulta a $nombre cancelada (Ctrl+C); no se guarda ningún dictamen"
		fi
		PROC_RC=124
		return 0
	fi
	PROC_RC=0
	wait "$PROC_PID" || PROC_RC=$?
	trap - INT TERM
	PROC_PID=""
	[[ -n "$interrumpido" ]] && die "consulta a $nombre cancelada (Ctrl+C); no se guarda ningún dictamen"
	return 0
}
