# shellcheck shell=bash
# gitctl (sin argumentos) / gitctl i — preguntas en secuencia según dónde estés:
#   en el principal  → crear un worktree o saltar a uno existente
#   en un worktree   → integrarlo en su base y limpiarlo, o volver al principal

_i_help() {
	cat <<'H'
Uso: gitctl            (con terminal interactiva)
     gitctl i

Te guía con preguntas según dónde estés:
  - en el repo principal: ofrece limpiar los worktrees ya integrados y te pide
    el nombre de un worktree; si existe te lleva a él, si no lo crea.
  - dentro de un worktree: te ofrece integrarlo en su base (merge commit) y
    eliminarlo, o volver al principal.
H
}

_i_from_main() {
	local i names=() name base
	local -a cand_paths=() cand_branches=()

	_clean_candidates
	if ((${#cand_branches[@]})); then
		if confirm "Hay ${#cand_branches[@]} worktree(s) ya integrado(s) (${cand_branches[*]}). ¿Limpiarlos?"; then
			for i in "${!cand_paths[@]}"; do
				wt_remove "${cand_paths[$i]}" "${cand_branches[$i]}" 0 0
			done
		fi
	fi

	wt_list
	for i in "${!WT_PATHS[@]}"; do
		((i == 0)) && continue
		names+=("$(basename "${WT_PATHS[$i]}")")
	done
	if ((${#names[@]})); then
		echo "Worktrees existentes: ${names[*]}" >&2
	else
		echo "Worktrees existentes: ninguno" >&2
	fi

	name="$(ask "¿Nombre del worktree? (nuevo o existente)")"
	if [[ -z "$name" ]]; then
		info "nada que hacer"
		return 0
	fi

	local path
	if path="$(wt_find "$name")"; then
		if wt_is_main "$path"; then
			info "ese es el worktree principal; ya estás en él"
			return 0
		fi
		[[ -d "$path" ]] || die "la carpeta $path ya no existe (gitctl clean)"
		ok "ya existe: $path"
		cd_to "$path"
		return 0
	fi

	if git_branch_exists "$name"; then
		cmd_new "$name"
	else
		base="$(ask "¿Desde qué rama?" "$(git_default_branch)")"
		cmd_new "$name" --base "$base"
	fi
}

_i_from_worktree() {
	local path="$1" branch base
	branch="$(wt_branch_of "$path")"
	[[ -n "$branch" ]] || die "este worktree no está en ninguna rama (detached)"
	base="$(wt_base_of "$branch")"
	local ab
	ab="$(wt_ahead_behind "$branch" "$base")"
	echo "Estás en $(basename "$path") (rama $branch, ${ab%/*} por delante / ${ab#*/} por detrás de $base)" >&2

	if ! git_is_clean "$path"; then
		warn "hay cambios sin commitear: haz commit primero y vuelve a ejecutar gitctl"
		return 1
	fi

	if confirm "¿Integrarlo en $base?"; then
		cmd_merge
		return
	fi
	if confirm "¿Volver al principal?"; then
		cd_to "$(git_main_root)"
	fi
	return 0
}

cmd_interactive() {
	if want_help "$@"; then
		_i_help
		return
	fi
	require_repo
	is_interactive || die "gitctl i necesita una terminal interactiva"
	local here
	here="$(wt_current)"
	if wt_is_main "$here"; then
		_i_from_main
	else
		_i_from_worktree "$here"
	fi
}
