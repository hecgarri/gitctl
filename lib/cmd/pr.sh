# shellcheck shell=bash
# gitctl pr [<rama|carpeta>] [--title TÍTULO]

_pr_help() {
	cat <<'H'
Uso: gitctl pr [<rama|carpeta>] [--title TÍTULO]

Sube la rama del worktree (por defecto, en el que estás) a GitHub y abre una
pull request hacia su base, con gh. El título propuesto es el del commit (si
hay uno) o el nombre de la rama; la descripción, la lista de commits.
Si ya hay una PR abierta para la rama, solo sube los commits nuevos.

Requisitos: gh instalado y con sesión (gh auth login), el remoto «origin» (o el
de «remote» en .gitctl.conf), la base subida al remoto y el worktree sin
cambios sin commitear. Pide confirmación antes de subir nada (o -y).

Cuando la PR se integre en GitHub, «gitctl clean» borra el worktree y la rama.
H
}

# Remoto al que se suben las ramas.
pr_remote() { cfg remote origin; }

# ¿Se pueden crear PRs aquí? (gh instalado y el remoto existe)
pr_available() {
	command -v gh >/dev/null 2>&1 && git remote get-url "$(pr_remote)" >/dev/null 2>&1
}

# Estado y URL de la PR de una rama o URL: «OPEN https://…», o nada si no hay.
pr_info() {
	command -v gh >/dev/null 2>&1 || return 1
	gh pr view "$1" --json state,url --jq '.state + " " + .url' 2>/dev/null
}

# ¿La PR que gitctl creó para la rama ya está integrada en GitHub?
pr_merged() {
	local url
	url="$(git config --get "branch.$1.gitctl-pr" 2>/dev/null)" || return 1
	[[ "$(pr_info "$url")" == MERGED* ]]
}

cmd_pr() {
	local target="" title=""
	while (($#)); do
		case "$1" in
		-h | --help)
			_pr_help
			return
			;;
		--title)
			need_arg "$@"
			title="$2"
			shift
			;;
		--title=*) title="${1#--title=}" ;;
		-*) die "opción desconocida: $1 (ver gitctl pr --help)" ;;
		*)
			[[ -z "$target" ]] || die "sobra un argumento: $1"
			target="$1"
			;;
		esac
		shift
	done
	require_repo
	command -v gh >/dev/null 2>&1 || die "falta gh (la CLI de GitHub): instálala y ejecuta gh auth login"
	local remote
	remote="$(pr_remote)"
	git remote get-url "$remote" >/dev/null 2>&1 ||
		die "el repositorio no tiene el remoto «$remote» (git remote add $remote <url>)"

	local path branch base ab
	if [[ -n "$target" ]]; then
		path="$(wt_resolve "$target")"
	else
		path="$(wt_current)"
	fi
	wt_is_main "$path" && die "estás en el worktree principal: indica de qué worktree hacer la PR (gitctl pr <rama>)"
	branch="$(wt_branch_of "$path")"
	[[ -n "$branch" ]] || die "el worktree $path no está en ninguna rama (detached)"
	base="$(wt_base_of "$branch")"
	git_branch_exists "$base" || die "la rama base $base no existe"
	git_is_clean "$path" || die "$path tiene cambios sin commitear; haz commit primero"
	ab="$(wt_ahead_behind "$branch" "$base")"
	[[ "${ab%/*}" != 0 ]] || die "$branch no tiene commits nuevos respecto a $base: no hay nada que proponer"

	local existing
	existing="$(pr_info "$branch" || true)"
	if [[ "$existing" == OPEN* ]]; then
		existing="${existing#OPEN }"
		info "ya hay una PR abierta para $branch: $existing"
		confirm "¿Subir los commits nuevos a esa PR (git push)?" || {
			info "no se ha subido nada"
			return 1
		}
		git push -q "$remote" "$branch" || die "no se pudo subir $branch a $remote"
		git config "branch.$branch.gitctl-pr" "$existing"
		ok "PR actualizada: $existing"
		return 0
	fi

	git ls-remote --exit-code --heads "$remote" "$base" >/dev/null 2>&1 ||
		die "la rama base $base no está en $remote; súbela antes: git push $remote $base"

	local default body
	if [[ "${ab%/*}" == 1 ]]; then
		default="$(git log -1 --format=%s "refs/heads/$branch")"
	else
		default="$branch"
	fi
	if [[ -z "$title" ]]; then
		if is_interactive && [[ -z "$GITCTL_YES" ]]; then
			title="$(ask "Título de la PR" "$default")"
		fi
		title="${title:-$default}"
	fi
	body="$(printf 'Commits:\n\n'; git log --reverse --format='- %s' "refs/heads/$base..refs/heads/$branch")"

	{
		echo "Se subirá la rama $branch a $remote y se abrirá una PR hacia $base:"
		echo "  Título: $title"
		git log --reverse --format='    %h %s' "refs/heads/$base..refs/heads/$branch"
	} >&2
	confirm "¿Crear la PR?" || {
		info "no se ha subido nada"
		return 1
	}
	git push -q -u "$remote" "$branch" || die "no se pudo subir $branch a $remote"
	local out url
	out="$(gh pr create --base "$base" --head "$branch" --title "$title" --body "$body")" ||
		die "gh no pudo crear la PR (la rama ya está subida; vuelve a intentarlo con gitctl pr $branch)"
	url="$(printf '%s\n' "$out" | tail -n1)"
	git config "branch.$branch.gitctl-pr" "$url"
	ok "PR creada: $url"
	info "cuando la integren en GitHub, «gitctl clean» (o Limpiar en el menú) borra el worktree y la rama"
}
