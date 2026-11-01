# shellcheck shell=bash
# gitctl rm <nombre> [--force]

cmd_rm() {
	local target="" force=0
	while (($#)); do
		case "$1" in
		-h | --help)
			cat <<'H'
Uso: gitctl rm <rama|carpeta> [--force]

Elimina el worktree y su rama. Se niega si hay cambios sin commitear o si la
rama tiene commits sin integrar en su base, salvo con --force (que los descarta).
Siempre pide confirmación (o -y).
H
			return
			;;
		-f | --force) force=1 ;;
		-*) die "opción desconocida: $1" ;;
		*) target="$1" ;;
		esac
		shift
	done
	[[ -n "$target" ]] || die "uso: gitctl rm <rama|carpeta> [--force]"
	require_repo
	local path
	path="$(wt_resolve "$target")"
	[[ -d "$path" ]] || die "la carpeta $path ya no existe; usa gitctl clean"
	wt_remove "$path" "$(wt_branch_of "$path")" "$force" 1
}
