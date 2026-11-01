# shellcheck shell=bash
# Gestión de worktrees.

_wt_help() {
	cat <<'EOF'
Uso: gitctl wt <acción>

  ls                         Lista worktrees (rama, HEAD, cambios, tarea/agente)
  new <nombre> [--base REF] [--branch RAMA]
                             Crea un worktree libre (rama wt/<nombre> por defecto)
  show <wt>                  Estado detallado
  path <wt>                  Imprime la ruta (útil: cd "$(gitctl wt path t1/claude)")
  open <wt>                  Abre una shell en el worktree
  rm <wt> [--force] [--delete-branch]
                             Elimina el worktree. Rechaza si hay cambios sin
                             commitear o un agente ejecutándose. La rama se
                             conserva salvo --delete-branch (solo si está fusionada).

<wt> puede ser «tarea/agente», un nombre de worktree o una ruta.
EOF
}

cmd_wt() {
	local action="${1:-ls}"
	[[ $# -gt 0 ]] && shift
	case "$action" in
	-h | --help | help) _wt_help ;;
	ls | list)
		state_init
		_wt_ls "$@"
		;;
	new)
		state_init
		_wt_new "$@"
		;;
	show)
		state_init
		_wt_show "$@"
		;;
	path)
		state_init
		wt_resolve "${1:?falta el worktree}"
		echo
		;;
	open)
		state_init
		_wt_open "$@"
		;;
	rm | remove)
		state_init
		_wt_rm "$@"
		;;
	*) die "acción desconocida: wt $action (ver gitctl wt --help)" ;;
	esac
}

# Crea un worktree con rama nueva. No sobrescribe nada existente.
wt_create() {
	local path="$1" branch="$2" base="$3"
	[[ -e "$path" ]] && die "ya existe $path"
	git_branch_exists "$branch" && die "ya existe la rama $branch"
	mkdir -p "$(dirname "$path")"
	git worktree add -q -b "$branch" "$path" "$base" >&2 || die "no se pudo crear el worktree $path"
}

# Worktree efímero desacoplado en un commit exacto (para verificar o revisar).
wt_ephemeral() {
	local sha="$1" kind="$2" path
	path="$(state_dir)/tmp/$kind-${sha:0:12}-$(rand_hex 3)"
	git worktree add -q --detach "$path" "$sha" >&2 || die "no se pudo crear el worktree temporal"
	printf '%s' "$path"
}
wt_ephemeral_rm() {
	# Solo se borran worktrees creados por gitctl dentro de su directorio temporal.
	[[ "$1" == "$(state_dir)/tmp/"* ]] || return 0
	git worktree remove --force "$1" >/dev/null 2>&1 || rm -rf -- "$1"
	git worktree prune 2>/dev/null || true
}

# Resuelve «tarea/agente», un nombre o una ruta a la ruta de un worktree.
wt_resolve() {
	local arg="$1" p
	if [[ "$arg" == */* && "$arg" != /* && "$arg" != .* ]]; then
		local t="${arg%%/*}" a="${arg#*/}"
		require_assign "$t" "$a"
		p="$(assign_get "$t" "$a" worktree)"
	elif [[ -d "$arg" ]]; then
		p="$(cd "$arg" && pwd)"
	else
		p="$(wt_root)/$arg"
	fi
	[[ -d "$p" ]] || die "no existe el worktree «$arg» ($p)"
	printf '%s' "$p"
}

_wt_ls() {
	local path="" head="" branch="" line
	printf '%-45s %-28s %-9s %-8s %s\n' RUTA RAMA HEAD ESTADO TAREA/AGENTE
	_wt_ls_row() {
		[[ -z "$path" ]] && return
		local st="limpio" ta="-"
		[[ "$path" == "$(state_dir)/tmp/"* ]] && return
		if [[ ! -d "$path" ]]; then
			st="ausente"
		elif ! git_is_clean "$path"; then
			st="cambios"
		fi
		[[ "$branch" == gitctl/*/* ]] && ta="${branch#gitctl/}"
		printf '%-45s %-28s %-9s %-8s %s\n' "$path" "${branch:-(detached)}" "${head:0:8}" "$st" "$ta"
	}
	while IFS= read -r line; do
		case "$line" in
		"worktree "*) path="${line#worktree }" ;;
		"HEAD "*) head="${line#HEAD }" ;;
		"branch "*) branch="${line#branch refs/heads/}" ;;
		"")
			_wt_ls_row
			path="" head="" branch=""
			;;
		esac
	done < <(
		git worktree list --porcelain
		echo
	)
}

_wt_new() {
	local name="" base="" branch=""
	while (($#)); do
		case "$1" in
		--base)
			need_arg "$@"
			base="$2"
			shift
			;;
		--branch)
			need_arg "$@"
			branch="$2"
			shift
			;;
		-h | --help)
			_wt_help
			return
			;;
		-*) die "opción desconocida: $1" ;;
		*) name="$1" ;;
		esac
		shift
	done
	[[ -n "$name" ]] || die "uso: gitctl wt new <nombre>"
	check_name "nombre de worktree" "$name"
	base="${base:-$(git_default_branch)}"
	git_ref_sha "$base" >/dev/null || die "no existe la referencia base «$base»"
	branch="${branch:-wt/$name}"
	git check-ref-format --branch "$branch" >/dev/null || die "nombre de rama no válido: $branch"
	local path
	path="$(wt_root)/$name"
	wt_create "$path" "$branch" "$base"
	emit_event wt.created path="$path" branch="$branch" base="$base"
	ok "worktree $path (rama $branch desde $base)"
	echo "$path"
}

_wt_show() {
	local p branch base
	p="$(wt_resolve "${1:?uso: gitctl wt show <wt>}")"
	branch="$(git_current_branch "$p")"
	echo "Ruta:   $p"
	echo "Rama:   ${branch:-(detached)}"
	echo "HEAD:   $(git -C "$p" log -1 --format='%h %s (%an, %ar)')"
	if [[ "$branch" == gitctl/*/* ]]; then
		local t a
		t="${branch#gitctl/}"
		a="${t#*/}"
		t="${t%%/*}"
		if assign_exists "$t" "$a" 2>/dev/null; then
			base="$(task_get "$t" .base_sha)"
			echo "Tarea:  $t ($(task_get "$t" .title))"
			echo "Commits desde la base ($(git_short "$base")):"
			git -C "$p" log --oneline "$base..HEAD" | sed 's/^/  /'
		fi
	fi
	echo "Cambios sin commitear:"
	git -C "$p" status --short | sed 's/^/  /'
}

_wt_open() {
	local p
	p="$(wt_resolve "${1:?uso: gitctl wt open <wt>}")"
	if [[ ! -t 0 ]]; then
		echo "$p"
		return
	fi
	info "abriendo una shell en $p (sal con «exit»)"
	(cd "$p" && exec "${SHELL:-bash}")
}

_wt_rm() {
	local target="" force="" delbranch=""
	while (($#)); do
		case "$1" in
		--force) force=1 ;;
		--delete-branch) delbranch=1 ;;
		-h | --help)
			_wt_help
			return
			;;
		-*) die "opción desconocida: $1" ;;
		*) target="$1" ;;
		esac
		shift
	done
	[[ -n "$target" ]] || die "uso: gitctl wt rm <wt>"
	local p branch
	p="$(wt_resolve "$target")"
	[[ "$p" == "$(git_main_root)" ]] && die "no se puede eliminar el worktree principal"
	branch="$(git_current_branch "$p")"
	if [[ "$branch" == gitctl/*/* ]]; then
		local ta="${branch#gitctl/}"
		run_active "${ta%%/*}" "${ta#*/}" && die "hay un agente ejecutándose en $p (gitctl run stop)"
	fi
	local args=()
	if ! git_is_clean "$p"; then
		[[ -n "$force" ]] || die "$p tiene cambios sin commitear; commitéalos o usa --force (se perderán)"
		confirm "¿Eliminar $p y DESCARTAR sus cambios sin commitear?" || die "cancelado"
		args+=(--force)
	fi
	git worktree remove "${args[@]}" "$p" || die "git no pudo eliminar $p"
	emit_event wt.removed path="$p" branch="$branch"
	ok "eliminado $p"
	if [[ -n "$branch" ]]; then
		if [[ -n "$delbranch" ]]; then
			git branch -d "$branch" || warn "la rama $branch no está fusionada; se conserva (git branch -D para forzar)"
		else
			info "la rama $branch se conserva"
		fi
	fi
}
