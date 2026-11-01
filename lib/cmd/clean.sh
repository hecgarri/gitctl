# shellcheck shell=bash
# gitctl clean [--dry-run]

# Rellena cand_paths y cand_branches (del llamador) con los worktrees gestionados,
# limpios y ya integrados en su base (en local o con una PR integrada en GitHub).
_clean_candidates() {
	local i path branch
	cand_paths=() cand_branches=()
	wt_list
	for i in "${!WT_PATHS[@]}"; do
		((i == 0)) && continue
		path="${WT_PATHS[$i]}" branch="${WT_BRANCHES[$i]}"
		[[ -d "$path" && -n "$branch" ]] || continue
		wt_is_managed "$branch" || continue
		git_is_clean "$path" || continue
		branch_integrated "$branch" "$(wt_base_of "$branch")" || continue
		cand_paths+=("$path")
		cand_branches+=("$branch")
	done
}

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

	local i
	local -a cand_paths=() cand_branches=()
	_clean_candidates

	if [[ -z "$prune" && ${#cand_paths[@]} -eq 0 ]]; then
		ok "nada que limpiar"
		return
	fi
	echo "Se eliminaría:"
	local via_pr=""
	for i in "${!cand_paths[@]}"; do
		if branch_merged_into "${cand_branches[$i]}" "$(wt_base_of "${cand_branches[$i]}")"; then
			echo "  ${cand_paths[$i]}  (rama ${cand_branches[$i]}, ya integrada)"
		else
			echo "  ${cand_paths[$i]}  (rama ${cand_branches[$i]}, PR integrada en GitHub)"
			via_pr=1
		fi
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
	[[ -z "$via_pr" ]] || info "tu rama base local aún no tiene esos cambios: actualízala en el principal con git pull"
}
