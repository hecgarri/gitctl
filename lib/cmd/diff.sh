# shellcheck shell=bash
# gitctl diff [<rama|carpeta>] [--stat|--log|--behind|--files|--wip] [-- <archivo>...]

_diff_help() {
	cat <<'H'
Uso: gitctl diff [<rama|carpeta>] [--stat|--log|--behind|--files|--wip] [-- <archivo>...]

Compara la rama de un worktree (por defecto, en el que estás) con su base.
Muestra lo que aportaría «gitctl merge»: los cambios desde el ancestro común
(git diff base...rama), aunque la base haya avanzado después.

  (sin opción)   diff completo (con paginador)
  --stat         resumen: archivos cambiados y líneas
  --files        solo los nombres de los archivos cambiados
  --log          commits que se integrarían (git log base..rama)
  --behind       commits de la base que la rama no tiene (git log rama..base)
  --wip          cambios sin commitear del worktree
  -- <archivo>   limita el diff a esos archivos
H
}

cmd_diff() {
	local target="" mode="full"
	local -a files=()
	while (($#)); do
		case "$1" in
		-h | --help)
			_diff_help
			return
			;;
		--stat) mode=stat ;;
		--files | --name-only) mode=files ;;
		--log) mode=log ;;
		--behind) mode=behind ;;
		--wip) mode=wip ;;
		--)
			shift
			files=("$@")
			break
			;;
		-*) die "opción desconocida: $1 (ver gitctl diff --help)" ;;
		*)
			[[ -z "$target" ]] || die "sobra un argumento: $1 (para archivos usa: gitctl diff <rama> -- <archivo>)"
			target="$1"
			;;
		esac
		shift
	done
	require_repo

	local path branch base
	if [[ -n "$target" ]]; then
		path="$(wt_resolve "$target")"
	else
		path="$(wt_current)"
	fi
	wt_is_main "$path" && die "estás en el worktree principal: indica qué worktree comparar (gitctl diff <rama>)"
	branch="$(wt_branch_of "$path")"
	[[ -n "$branch" ]] || die "el worktree $path no está en ninguna rama (detached)"
	base="$(wt_base_of "$branch")"
	git_branch_exists "$base" || die "la rama base $base no existe"

	case "$mode" in
	full) git diff "refs/heads/$base...refs/heads/$branch" -- "${files[@]}" ;;
	stat) git diff --stat "refs/heads/$base...refs/heads/$branch" -- "${files[@]}" ;;
	files) git diff --name-only "refs/heads/$base...refs/heads/$branch" -- "${files[@]}" ;;
	log) git log --oneline --no-decorate "refs/heads/$base..refs/heads/$branch" -- "${files[@]}" ;;
	behind) git log --oneline --no-decorate "refs/heads/$branch..refs/heads/$base" -- "${files[@]}" ;;
	wip)
		[[ -d "$path" ]] || die "la carpeta $path ya no existe"
		if git_is_clean "$path"; then
			info "$(basename "$path") no tiene cambios sin commitear"
			return 0
		fi
		git -C "$path" status --short -- "${files[@]}"
		git -C "$path" diff HEAD -- "${files[@]}"
		;;
	esac
}
