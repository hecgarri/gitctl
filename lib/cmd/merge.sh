# shellcheck shell=bash
# gitctl merge [<nombre>] [--continue] [--on-conflict=ask|abort|keep]

_merge_help() {
	cat <<'H'
Uso: gitctl merge [<rama|carpeta>] [--on-conflict=ask|abort|keep]
     gitctl merge --continue

Integra la rama del worktree (por defecto, en el que estás) en su base con un
merge commit, en el worktree principal. Si sale bien, ofrece eliminar el
worktree y la rama y te devuelve al principal.

Requisitos: el worktree y el principal sin cambios sin commitear, y el principal
en la rama base.

Si hay conflictos:
  ask    (por defecto) pregunta qué hacer; sin terminal interactiva, aborta
  abort  deshace el merge; resuelve en tu worktree (git merge <base>) y repite
  keep   deja el merge en curso en el principal y te lleva allí; al terminar:
         gitctl merge --continue
H
}

_merge_conflicted() { git -C "$1" diff --name-only --diff-filter=U; }

# Tras integrar: ofrece borrar el worktree y vuelve al principal.
_merge_cleanup() {
	local path="$1" branch="$2" main
	main="$(git_main_root)"
	if [[ -n "$path" && -d "$path" ]]; then
		wt_remove "$path" "$branch" 0 1 || info "el worktree se conserva en $path (gitctl rm $branch cuando quieras)"
	fi
	cd_to "$main"
}

_merge_path_of_branch() {
	local i
	wt_list
	for i in "${!WT_BRANCHES[@]}"; do
		((i == 0)) && continue
		[[ "${WT_BRANCHES[$i]}" == "$1" ]] && {
			printf '%s' "${WT_PATHS[$i]}"
			return
		}
	done
	return 0
}

_merge_continue() {
	local main branch path base
	main="$(git_main_root)"
	branch="$(git config --get gitctl.merging || true)"
	[[ -n "$branch" ]] || die "no hay ningún merge de gitctl en curso"
	path="$(_merge_path_of_branch "$branch")"
	base="$(wt_base_of "$branch")"
	if ! git -C "$main" rev-parse -q --verify MERGE_HEAD >/dev/null; then
		git config --unset gitctl.merging
		if branch_merged_into "$branch" "$base"; then
			ok "$branch ya está integrada en $base"
			_merge_cleanup "$path" "$branch"
			return
		fi
		warn "el merge de $branch ya no está en curso (¿se abortó a mano?); no se ha integrado"
		return 1
	fi
	local pending
	pending="$(_merge_conflicted "$main")"
	if [[ -n "$pending" ]]; then
		err "quedan archivos sin resolver en $main:"
		printf '  %s\n' "$pending" >&2
		die "resuélvelos, haz git add y vuelve a ejecutar gitctl merge --continue"
	fi
	git -C "$main" commit -q --no-edit || die "no se pudo crear el commit de merge"
	git config --unset gitctl.merging
	ok "integrada $branch en $base"
	_merge_cleanup "$path" "$branch"
}

# Pregunta qué hacer ante un conflicto. Imprime abort|keep.
_merge_ask() {
	if [[ ! -t 0 ]]; then
		warn "sin terminal interactiva: se aborta el merge (usa --on-conflict=keep para dejarlo en curso)" >&2
		echo abort
		return
	fi
	local ans
	while true; do
		read -r -p "¿[a]bortar y resolver en tu worktree, o [d]ejar el merge en curso en el principal? [a/d] " ans
		case "$ans" in
		a | A) echo abort && return ;;
		d | D) echo keep && return ;;
		esac
	done
}

cmd_merge() {
	local target="" mode="ask" cont=""
	while (($#)); do
		case "$1" in
		-h | --help)
			_merge_help
			return
			;;
		--continue) cont=1 ;;
		--on-conflict=*) mode="${1#--on-conflict=}" ;;
		--on-conflict)
			need_arg "$@"
			mode="$2"
			shift
			;;
		-*) die "opción desconocida: $1" ;;
		*) target="$1" ;;
		esac
		shift
	done
	case "$mode" in ask | abort | keep) ;; *) die "--on-conflict debe ser ask, abort o keep" ;; esac
	require_repo
	if [[ -n "$cont" ]]; then
		_merge_continue
		return
	fi

	local main path branch base
	main="$(git_main_root)"
	if [[ -n "$target" ]]; then
		path="$(wt_resolve "$target")"
	else
		path="$(wt_current)"
	fi
	wt_is_main "$path" && die "estás en el worktree principal: ejecútalo desde un worktree o indica cuál (gitctl merge <rama>)"
	branch="$(wt_branch_of "$path")"
	[[ -n "$branch" ]] || die "el worktree $path no está en ninguna rama (detached)"
	base="$(wt_base_of "$branch")"
	git_branch_exists "$base" || die "la rama base $base no existe"

	git config --get gitctl.merging >/dev/null &&
		die "hay un merge de gitctl en curso ($(git config --get gitctl.merging)): gitctl merge --continue"
	git -C "$main" rev-parse -q --verify MERGE_HEAD >/dev/null &&
		die "el principal tiene un merge en curso; termínalo o abórtalo primero"
	git_is_clean "$path" || die "$path tiene cambios sin commitear; haz commit primero"
	git_is_clean "$main" || die "el worktree principal ($main) tiene cambios sin commitear"
	local cur
	cur="$(git_current_branch "$main")"
	[[ "$cur" == "$base" ]] || die "el principal está en «${cur:-detached}», no en $base: cambia a $base (git -C $main switch $base)"

	if branch_merged_into "$branch" "$base"; then
		info "$branch no tiene nada nuevo respecto a $base"
		_merge_cleanup "$path" "$branch"
		return
	fi

	info "integrando $branch en $base (en $main)"
	if git -C "$main" merge -q --no-ff --no-edit "$branch"; then
		ok "integrada $branch en $base"
		_merge_cleanup "$path" "$branch"
		return
	fi

	git -C "$main" rev-parse -q --verify MERGE_HEAD >/dev/null ||
		die "el merge ha fallado sin dejar conflictos; revisa $main"
	err "conflictos al integrar $branch en $base:"
	_merge_conflicted "$main" | sed 's/^/  /' >&2
	[[ "$mode" == ask ]] && mode="$(_merge_ask)"
	if [[ "$mode" == keep ]]; then
		git config gitctl.merging "$branch"
		cd_to "$main"
		info "resuelve los conflictos en $main, haz git add y ejecuta: gitctl merge --continue"
	else
		git -C "$main" merge --abort
		info "merge abortado; $base no ha cambiado"
		info "para resolver en tu worktree: git merge $base, arregla, commit y repite gitctl merge"
	fi
	return 1
}
