# shellcheck shell=bash
# gitctl new <rama> [--base RAMA]

_new_help() {
	cat <<'EOF2'
Uso: gitctl new <rama> [--base RAMA]

Crea un worktree para <rama> en ../<repo>.wt/<rama> y te deja dentro.
  - Si la rama ya existe en local, se reutiliza; si no, se crea desde --base
    (por defecto, la rama por defecto del repo).
  - Copia desde el worktree principal los archivos de «copy» y ejecuta «setup»
    (ver .gitctl.conf).
  - La rama recuerda su base: «gitctl merge» la integrará ahí.

  --base RAMA   rama local desde la que crear (y en la que se integrará)
EOF2
}

# Copia los archivos de «copy» desde el principal al worktree nuevo.
_new_copy() {
	local dest="$1" main f list
	main="$(git_main_root)"
	list="$(cfg copy)"
	[[ -n "$list" ]] || return 0
	local -a files
	read -r -a files <<<"$list"
	for f in "${files[@]}"; do
		if [[ "$f" == /* || "$f" == ".." || "$f" == ../* || "$f" == */../* || "$f" == */.. ]]; then
			warn "copy: se ignora «$f» (solo rutas relativas dentro del repo)"
			continue
		fi
		if [[ ! -e "$main/$f" ]]; then
			warn "copy: no existe $f en el worktree principal"
			continue
		fi
		mkdir -p "$dest/$(dirname "$f")"
		cp -pR "$main/$f" "$dest/$f" && info "copiado $f"
	done
}

cmd_new() {
	local branch="" base="" base_given=""
	while (($#)); do
		case "$1" in
		-h | --help)
			_new_help
			return
			;;
		--base)
			need_arg "$@"
			base="$2"
			base_given=1
			shift
			;;
		--base=*)
			base="${1#--base=}"
			base_given=1
			;;
		-*) die "opción desconocida: $1" ;;
		*)
			[[ -z "$branch" ]] || die "sobra un argumento: $1"
			branch="$1"
			;;
		esac
		shift
	done
	[[ -n "$branch" ]] || die "uso: gitctl new <rama> [--base RAMA]"
	require_repo
	git check-ref-format --branch "$branch" >/dev/null 2>&1 || die "nombre de rama no válido: «$branch»"

	if [[ -z "$base" ]]; then
		base="$(git_default_branch)"
	fi
	git_branch_exists "$base" || {
		if [[ -n "$base_given" ]]; then
			die "--base debe ser una rama local: «$base» no lo es"
		fi
		die "la rama por defecto «$base» no existe en local (define «base» en .gitctl.conf)"
	}
	[[ "$branch" != "$base" ]] || die "la rama no puede ser su propia base ($base)"

	wt_list
	local i
	for i in "${!WT_BRANCHES[@]}"; do
		[[ "${WT_BRANCHES[$i]}" == "$branch" ]] &&
			die "la rama $branch ya tiene un worktree en ${WT_PATHS[$i]} (usa gitctl cd $branch)"
	done

	local path
	path="$(wt_root)/$(wt_dir_name "$branch")"
	[[ -e "$path" ]] && die "ya existe $path"
	mkdir -p "$(wt_root)"

	if git_branch_exists "$branch"; then
		[[ -n "$base_given" ]] || base="$(git_default_branch)"
		git worktree add -q "$path" "$branch" || die "no se pudo crear el worktree"
		info "reutilizando la rama existente $branch"
	else
		git worktree add -q -b "$branch" "$path" "$base" || die "no se pudo crear el worktree"
	fi
	git config "branch.$branch.gitctl-base" "$base"
	ok "worktree $path (rama $branch, se integrará en $base)"

	local rc=0 cmd
	_new_copy "$path"
	cmd="$(cfg setup)"
	if [[ -n "$cmd" ]]; then
		info "setup: $cmd"
		if ! (cd "$path" && bash -c "$cmd" </dev/null); then
			warn "el setup ha fallado; el worktree se conserva en $path"
			rc=1
		fi
	fi
	cd_to "$path"
	return "$rc"
}
