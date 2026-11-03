# shellcheck shell=bash
# Menú interactivo persistente (gitctl sin -Accion).

# Ejecuta una acción en una subshell: si falla, se muestra el error y se vuelve al menú.
_menu_ejecutar() {
	local rc=0
	set +e
	(
		set -e
		"$@"
	)
	rc=$?
	set -e
	if ((rc != 0)); then
		warn "la acción terminó con error (código $rc); vuelves al menú"
	fi
	return 0
}

accion_menu() {
	local r
	while :; do
		cat >&2 <<M

── gitctl │ $(basename "$REPO") │ worktrees en $RAIZ
[1] Crear un worktree
[2] Ver worktrees activos
[3] Comparar ramas
[4] Evaluar con un LLM
[5] Integrar una rama
[6] Eliminar un worktree
[7] Salir
M
		leer_linea "Selecciona una opción: " || return 0
		r="$(_trim "$RESP")"
		r="${r,,}"
		case "$r" in
		1) _menu_ejecutar accion_crear ;;
		2) _menu_ejecutar accion_estado ;;
		3) _menu_ejecutar accion_comparar ;;
		4) _menu_ejecutar accion_evaluar ;;
		5) _menu_ejecutar accion_integrar ;;
		6) _menu_ejecutar accion_eliminar ;;
		7 | salir | q) return 0 ;;
		*) warn "opción no válida: «$r»; escribe un número del 1 al 7" ;;
		esac
	done
}
