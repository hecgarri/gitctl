# shellcheck shell=bash
# Núcleo de worktrees: ubicación, listado, resolución de nombres, base y cd.
#
# Metadatos (en la config local de git, sin archivos propios):
#   branch.<rama>.gitctl-base   rama en la que se integra (la marca como gestionada)
#   gitctl.merging              rama con un merge de gitctl en curso en el principal

# Carpeta donde viven los worktrees: ../<repo>.wt
wt_root() {
	local main
	main="$(git_main_root)"
	printf '%s/%s.wt' "$(dirname "$main")" "$(basename "$main")"
}

# Rama → nombre de carpeta (feat/login → feat-login).
wt_dir_name() { printf '%s' "${1//\//-}"; }

# Rellena WT_PATHS, WT_BRANCHES y WT_HEADS (índice 0 = worktree principal).
wt_list() {
	WT_PATHS=() WT_BRANCHES=() WT_HEADS=()
	local line path="" branch="" head="" bare=""
	while IFS= read -r line; do
		case "$line" in
		"worktree "*) path="${line#worktree }" ;;
		"HEAD "*) head="${line#HEAD }" ;;
		"branch "*) branch="${line#branch refs/heads/}" ;;
		bare) bare=1 ;;
		"")
			if [[ -n "$path" && -z "$bare" ]]; then
				WT_PATHS+=("$path")
				WT_BRANCHES+=("$branch")
				WT_HEADS+=("$head")
			fi
			path="" branch="" head="" bare=""
			;;
		esac
	done < <(
		git worktree list --porcelain
		echo
	)
}

# Nombre, rama o ruta → ruta del worktree. Vacío = worktree principal.
wt_resolve() {
	local arg="${1:-}" i abs=""
	if [[ -z "$arg" ]]; then
		git_main_root
		return
	fi
	wt_list
	for i in "${!WT_PATHS[@]}"; do
		[[ "${WT_BRANCHES[$i]}" == "$arg" ]] && {
			printf '%s' "${WT_PATHS[$i]}"
			return
		}
	done
	for i in "${!WT_PATHS[@]}"; do
		((i == 0)) && continue
		[[ "$(basename "${WT_PATHS[$i]}")" == "$arg" ]] && {
			printf '%s' "${WT_PATHS[$i]}"
			return
		}
	done
	[[ -d "$arg" ]] && abs="$(cd "$arg" && pwd -P)"
	if [[ -n "$abs" ]]; then
		for i in "${!WT_PATHS[@]}"; do
			[[ "$(cd "${WT_PATHS[$i]}" 2>/dev/null && pwd -P)" == "$abs" ]] && {
				printf '%s' "${WT_PATHS[$i]}"
				return
			}
		done
	fi
	die "no existe el worktree «$arg» (ver gitctl ls)"
}

# Raíz del worktree en el que estás.
wt_current() { git rev-parse --show-toplevel 2>/dev/null || die "no estás dentro de un worktree"; }

# ¿Es $1 el worktree principal?
wt_is_main() { [[ "$(cd "$1" && pwd -P)" == "$(cd "$(git_main_root)" && pwd -P)" ]]; }

wt_branch_of() { git_current_branch "$1"; }

# Rama base de una rama: la guardada al crearla o la rama por defecto.
wt_base_of() { git config --get "branch.$1.gitctl-base" 2>/dev/null || git_default_branch; }

# ¿Lo creó gitctl? (solo estos los toca clean)
wt_is_managed() { git config --get "branch.$1.gitctl-base" >/dev/null 2>&1; }

# ¿Está la rama $1 completamente integrada en $2?
branch_merged_into() { git merge-base --is-ancestor "refs/heads/$1" "refs/heads/$2" 2>/dev/null; }

# Pide a la función de shell que haga cd al terminar (ver gitctl shell-init).
cd_to() {
	local dir="$1"
	if [[ -n "${GITCTL_CD_FILE:-}" ]]; then
		printf '%s\n' "$dir" >"$GITCTL_CD_FILE"
	else
		info "cd $dir   (para que gitctl cambie de carpeta solo: eval \"\$(gitctl shell-init bash)\")"
	fi
}

# Elimina un worktree y su rama. Sin force exige que esté limpio e integrado.
# wt_remove <ruta> <rama> <force:0|1> <preguntar:0|1>
wt_remove() {
	local path="$1" branch="$2" force="${3:-0}" ask="${4:-1}" base here
	wt_is_main "$path" && die "no se puede eliminar el worktree principal"
	if [[ "$force" != 1 ]]; then
		git_is_clean "$path" || die "$path tiene cambios sin commitear (usa --force para descartarlos)"
		if [[ -n "$branch" ]]; then
			base="$(wt_base_of "$branch")"
			branch_merged_into "$branch" "$base" ||
				die "la rama $branch tiene commits sin integrar en $base (usa gitctl merge, o --force para descartarlos)"
		fi
	fi
	if [[ "$ask" == 1 ]]; then
		confirm "¿Eliminar el worktree $path${branch:+ y la rama $branch}?" || {
			info "no se elimina nada"
			return 1
		}
	fi
	here="$(pwd -P)"
	local real
	real="$(cd "$path" && pwd -P)"
	cd "$(git_main_root)" || return 1
	if [[ "$force" == 1 ]]; then
		git worktree remove --force "$path" || die "no se pudo eliminar $path"
	else
		git worktree remove "$path" || die "no se pudo eliminar $path"
	fi
	if [[ -n "$branch" ]]; then
		# Ya se comprobó que está integrada en su base (o se forzó): -D evita que git
		# compare con la rama del principal, que puede no ser la base.
		if git branch -q -D "$branch"; then
			git config --remove-section "branch.$branch" 2>/dev/null || true
		else
			warn "no se pudo borrar la rama $branch"
		fi
	fi
	ok "eliminado $path${branch:+ (rama $branch)}"
	[[ "$here/" == "$real/"* ]] && cd_to "$(git_main_root)"
	return 0
}
