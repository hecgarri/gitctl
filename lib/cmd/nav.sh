# shellcheck shell=bash
# gitctl cd [<nombre>] y gitctl ls

cmd_cd() {
	if want_help "$@"; then
		cat <<'H'
Uso: gitctl cd [<rama|carpeta>]

Te lleva al worktree indicado (sin argumento, al worktree principal).
Necesita la integración con el shell (gitctl shell-init); sin ella imprime la ruta:
  cd "$(gitctl cd feat/login)"
H
		return
	fi
	require_repo
	local path
	path="$(wt_resolve "${1:-}")"
	[[ -d "$path" ]] || die "la carpeta del worktree ya no existe: $path (gitctl clean)"
	printf '%s\n' "$path"
	[[ -n "${GITCTL_CD_FILE:-}" ]] && printf '%s\n' "$path" >"$GITCTL_CD_FILE"
	return 0
}

cmd_ls() {
	if want_help "$@"; then
		cat <<'H'
Uso: gitctl ls

Lista los worktrees: rama, base, commits por delante/detrás de la base (DEL/DET)
y si hay cambios sin commitear. «*» marca el worktree en el que estás.
H
		return
	fi
	require_repo
	wt_list
	local here i path branch name base ab changes mark
	here="$(git rev-parse --show-toplevel 2>/dev/null || true)"
	printf '  %-24s %-28s %-14s %-9s %s\n' NOMBRE RAMA BASE "DEL/DET" CAMBIOS
	for i in "${!WT_PATHS[@]}"; do
		path="${WT_PATHS[$i]}"
		branch="${WT_BRANCHES[$i]}"
		mark=" "
		[[ "$path" == "$here" ]] && mark="*"
		if ((i == 0)); then
			name="(principal)"
		else
			name="$(basename "$path")"
		fi
		base="-" ab="-"
		if ((i > 0)) && [[ -n "$branch" ]]; then
			base="$(wt_base_of "$branch")"
			if git_branch_exists "$base"; then
				ab="$(git rev-list --left-right --count "refs/heads/$branch...refs/heads/$base" 2>/dev/null | awk '{print $1"/"$2}')"
			else
				ab="?"
			fi
		fi
		if [[ ! -d "$path" ]]; then
			changes="ausente"
		elif git_is_clean "$path"; then
			changes="no"
		else
			changes="sí"
		fi
		printf '%s %-24s %-28s %-14s %-9s %s\n' "$mark" "$name" "${branch:-(detached)}" "$base" "$ab" "$changes"
	done
}
