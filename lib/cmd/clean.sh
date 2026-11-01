# shellcheck shell=bash
# gitctl clean [--dry-run]

cmd_clean() {
	local dry=""
	while (($#)); do
		case "$1" in
		-h | --help)
			cat <<'H'
Uso: gitctl clean [--dry-run]

Elimina los worktrees creados por gitctl cuya rama ya está integrada en su base
y que no tienen cambios, junto con su rama, y olvida los worktrees cuya carpeta
ya no existe. Muestra la lista y pide confirmación (o -y).
Los worktrees creados a mano nunca se tocan.

  --dry-run   solo muestra qué se eliminaría
H
			return
			;;
		-n | --dry-run) dry=1 ;;
		*) die "opción desconocida: $1" ;;
		esac
		shift
	done
	require_repo
	local prune
	prune="$(git worktree prune --dry-run -v 2>&1 || true)"

	wt_list
	local i path branch
	local -a cand_paths=() cand_branches=()
	for i in "${!WT_PATHS[@]}"; do
		((i == 0)) && continue
		path="${WT_PATHS[$i]}" branch="${WT_BRANCHES[$i]}"
		[[ -d "$path" && -n "$branch" ]] || continue
		wt_is_managed "$branch" || continue
		git_is_clean "$path" || continue
		branch_merged_into "$branch" "$(wt_base_of "$branch")" || continue
		cand_paths+=("$path")
		cand_branches+=("$branch")
	done

	if [[ -z "$prune" && ${#cand_paths[@]} -eq 0 ]]; then
		ok "nada que limpiar"
		return
	fi
	echo "Se eliminaría:"
	for i in "${!cand_paths[@]}"; do
		echo "  ${cand_paths[$i]}  (rama ${cand_branches[$i]}, ya integrada)"
	done
	[[ -n "$prune" ]] && printf '%s\n' "$prune" | sed 's/^/  huérfano: /'
	[[ -n "$dry" ]] && return 0
	confirm "¿Eliminar todo lo anterior?" || {
		info "no se elimina nada"
		return 1
	}
	[[ -n "$prune" ]] && git worktree prune
	for i in "${!cand_paths[@]}"; do
		wt_remove "${cand_paths[$i]}" "${cand_branches[$i]}" 0 0
	done
}
