# shellcheck shell=bash
# gitctl (sin argumentos) / gitctl i — menú interactivo que se repite tras cada
# acción, al estilo de gcpctl.
#
# Cada acción se ejecuta como proceso hijo (el propio bin/gitctl): así un «die»
# dentro de un comando muestra su error y vuelve al menú en vez de cerrarlo, y
# el menú comparte exactamente el mismo código que los comandos sueltos.

MENU_MAIN=""   # Worktree principal.
MENU_CD=""     # Carpeta a la que llevar al usuario al salir.
MENU_EXIT=0    # 1 = salir del menú tras la acción en curso.
MENU_REQ=""    # Carpeta que pidió el último proceso hijo (cd_to).
MENU_ITEMS=()  # Elementos «ruta<TAB>etiqueta» de la última lista de worktrees.

_i_help() {
	cat <<'H'
Uso: gitctl            (con terminal interactiva)
     gitctl i

Abre un menú con todo lo que puede hacer gitctl: crear un worktree, entrar en
uno, compararlo con su base, integrarlo, eliminarlo, limpiar los ya integrados…
Tras cada acción vuelves al menú; «Nuevo» y «Entrar» lo cierran y te dejan
dentro del worktree.

Si algo impide integrar (cambios sin commitear, el principal en otra rama…),
el menú te explica qué pasa y te ofrece arreglarlo. Nunca descarta cambios sin
preguntar.
H
}

# --- Ejecución ---------------------------------------------------------------

# Ejecuta «gitctl <args>» como proceso hijo. Si hay integración con el shell, le
# da su propio archivo de cd y guarda lo que pida en MENU_REQ / MENU_CD.
_menu_exec() {
	local rc=0 f
	MENU_REQ=""
	if [[ -n "${GITCTL_CD_FILE:-}" ]]; then
		f="$(mktemp "${TMPDIR:-/tmp}/gitctl-menu.XXXXXX")" || return 1
		GITCTL_CD_FILE="$f" "$GITCTL_HOME/bin/gitctl" "$@" || rc=$?
		MENU_REQ="$(cat "$f" 2>/dev/null || true)"
		rm -f "$f"
	else
		env -u GITCTL_CD_FILE "$GITCTL_HOME/bin/gitctl" "$@" || rc=$?
	fi
	[[ -n "$MENU_REQ" ]] && MENU_CD="$MENU_REQ"
	return "$rc"
}

# Sale del menú y lleva al usuario a <carpeta>.
_menu_leave() {
	MENU_CD="$1"
	MENU_EXIT=1
}

# Si la carpeta actual desapareció (p. ej. se integró y borró este worktree),
# el menú sigue desde el principal.
_menu_fix_cwd() {
	[[ -d "$PWD" ]] && return 0
	cd "$MENU_MAIN" || return 1
	[[ -n "${GITCTL_CD_FILE:-}" ]] && MENU_CD="$MENU_MAIN"
	return 0
}

# Ruta del worktree (no principal) en el que estás, o nada.
_menu_here_wt() {
	local here
	here="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
	wt_is_main "$here" || printf '%s' "$here"
}

# --- Presentación --------------------------------------------------------------

# Estado corto de un worktree: «3 por delante · sin cambios», «ya integrado»…
_menu_wt_status() {
	local path="$1" branch="$2" base ab parts=()
	[[ -d "$path" ]] || {
		printf 'la carpeta ya no existe'
		return
	}
	[[ -n "$branch" ]] || {
		printf 'sin rama (detached)'
		return
	}
	base="$(wt_base_of "$branch")"
	ab="$(wt_ahead_behind "$branch" "$base")"
	if [[ "$ab" == "?" ]]; then
		parts+=("base $base no existe")
	elif [[ "${ab%/*}" == 0 ]]; then
		parts+=("sin commits nuevos")
	else
		parts+=("${ab%/*} por delante")
	fi
	[[ "$ab" == "?" || "${ab#*/}" == 0 ]] || parts+=("${ab#*/} por detrás")
	if git_is_clean "$path"; then parts+=("sin cambios"); else parts+=("con cambios sin commitear"); fi
	local IFS='|'
	local s="${parts[*]}"
	printf '%s' "${s//|/ · }"
}

# Etiqueta de un worktree para listas: «nombre  rama → base  estado».
_menu_wt_label() {
	local path="$1" branch="$2" here="${3:-}" mark="  "
	[[ "$path" == "$here" ]] && mark="▸ "
	printf '%s%-20s %-28s %s' "$mark" "$(basename "$path")" \
		"${branch:-(detached)} → $(wt_base_of "${branch:-x}")" "$(_menu_wt_status "$path" "$branch")"
}

_menu_header() {
	local here repo where i
	here="$(git rev-parse --show-toplevel 2>/dev/null || true)"
	repo="$(basename "$MENU_MAIN")"
	if [[ -n "$here" ]] && ! wt_is_main "$here"; then
		where="$(basename "$here") (rama $(git_current_branch "$here"))"
	else
		where="(principal) rama $(git_current_branch "$MENU_MAIN")"
	fi
	wt_list
	{
		printf '\n── gitctl │ %s │ estás en: %s\n' "$repo" "$where"
		if ((${#WT_PATHS[@]} <= 1)); then
			printf '   Worktrees: ninguno todavía (opción 1 para crear uno)\n'
		else
			printf '   Worktrees:\n'
			for i in "${!WT_PATHS[@]}"; do
				((i == 0)) && continue
				printf '   %s\n' "$(_menu_wt_label "${WT_PATHS[$i]}" "${WT_BRANCHES[$i]}" "$here")"
			done
		fi
		[[ -n "${GITCTL_SHELL:-}" ]] ||
			printf '   (sin cd automático: al salir te diré a qué carpeta ir; ver gitctl doctor)\n'
	} >&2
}

# Rellena MENU_ITEMS con los worktrees (no principales); <preferido> va primero.
_menu_wt_items() {
	local prefer="${1:-}" here i
	here="$(git rev-parse --show-toplevel 2>/dev/null || true)"
	MENU_ITEMS=()
	wt_list
	for i in "${!WT_PATHS[@]}"; do
		((i == 0)) && continue
		[[ "${WT_PATHS[$i]}" == "$prefer" ]] &&
			MENU_ITEMS+=("${WT_PATHS[$i]}"$'\t'"$(_menu_wt_label "${WT_PATHS[$i]}" "${WT_BRANCHES[$i]}" "$here")")
	done
	for i in "${!WT_PATHS[@]}"; do
		((i == 0)) && continue
		[[ "${WT_PATHS[$i]}" == "$prefer" ]] && continue
		MENU_ITEMS+=("${WT_PATHS[$i]}"$'\t'"$(_menu_wt_label "${WT_PATHS[$i]}" "${WT_BRANCHES[$i]}" "$here")")
	done
}

# Elige un worktree. Imprime su ruta; 130 si no hay o el usuario vuelve.
_menu_pick_wt() {
	local title="$1" prefer="${2:-}"
	_menu_wt_items "$prefer"
	if ((${#MENU_ITEMS[@]} == 0)); then
		warn "no hay worktrees todavía: crea uno con la opción 1"
		return "$PICK_CANCELLED"
	fi
	pick "$title" "${MENU_ITEMS[@]}"
}

# --- Acciones ------------------------------------------------------------------

_menu_new() {
	local name base path
	name="$(ask "Nombre de la rama nueva (Enter para volver)")"
	[[ -n "$name" ]] || return 0
	if path="$(wt_find "$name")"; then
		if wt_is_main "$path"; then
			warn "«$name» es la rama del worktree principal; elige otro nombre"
			return 1
		fi
		confirm "Ya existe el worktree $(basename "$path"). ¿Entrar en él?" && _menu_leave "$path"
		return 0
	fi
	if git_branch_exists "$name"; then
		info "la rama $name ya existe: se crea su worktree"
		_menu_exec new "$name"
	else
		base="$(ask "¿Desde qué rama? (ahí se integrará después)" "$(git_default_branch)")"
		_menu_exec new "$name" --base "$base"
	fi
	# Aunque falle el setup, si el worktree se creó, el usuario va a él.
	wt_find "$name" >/dev/null || return 1
	MENU_EXIT=1
}

_menu_enter() {
	local path
	path="$(_menu_pick_wt "¿A qué worktree quieres entrar?" "$(_menu_here_wt)")" || return 0
	[[ -d "$path" ]] || {
		err "la carpeta $path ya no existe (usa la opción Limpiar)"
		return 1
	}
	_menu_leave "$path"
}

_menu_diff() {
	local path branch base ab choice f title
	local -a items files
	path="$(_menu_pick_wt "¿Qué worktree quieres comparar con su base?" "$(_menu_here_wt)")" || return 0
	branch="$(wt_branch_of "$path")"
	[[ -n "$branch" ]] || {
		err "el worktree $path no está en ninguna rama (detached)"
		return 1
	}
	base="$(wt_base_of "$branch")"
	git_branch_exists "$base" || {
		err "la rama base $base no existe"
		return 1
	}
	while true; do
		ab="$(wt_ahead_behind "$branch" "$base")"
		title="$(basename "$path"): $branch vs. $base  (${ab%/*} por delante / ${ab#*/} por detrás)"
		items=(
			$'stat\tResumen: archivos cambiados'
			$'log\tCommits que se integrarían'
			$'full\tDiff completo'
			$'file\tDiff de un archivo'
		)
		[[ "${ab#*/}" == 0 ]] || items+=("behind"$'\t'"Commits de $base que la rama no tiene")
		git_is_clean "$path" || items+=($'wip\tCambios sin commitear del worktree')
		choice="$(pick "$title" "${items[@]}")" || return 0
		echo >&2
		case "$choice" in
		stat | log | full | file) [[ "${ab%/*}" != 0 ]] || info "$branch no tiene commits nuevos respecto a $base" ;;
		esac
		case "$choice" in
		stat) _menu_exec diff "$path" --stat ;;
		log) _menu_exec diff "$path" --log ;;
		full) _menu_exec diff "$path" ;;
		behind) _menu_exec diff "$path" --behind ;;
		wip) _menu_exec diff "$path" --wip ;;
		file)
			mapfile -t files < <(git diff --name-only "refs/heads/$base...refs/heads/$branch")
			if ((${#files[@]} == 0)); then
				info "no hay archivos cambiados"
			else
				f="$(pick "¿Qué archivo?" "${files[@]}")" || continue
				_menu_exec diff "$path" -- "$f"
			fi
			;;
		esac
		pause
	done
}

# Integra un worktree comprobando antes lo mismo que «gitctl merge»
# (lib/cmd/merge.sh) y ofreciendo arreglar cada bloqueo.
_menu_merge() {
	local main path branch base cur merging stashed="" from=""
	main="$MENU_MAIN"
	merging="$(git config --get gitctl.merging || true)"
	if [[ -n "$merging" ]]; then
		warn "hay un merge de $merging a medias en el principal ($main)"
		if confirm "¿Ya resolviste los conflictos? ¿Terminarlo ahora (gitctl merge --continue)?"; then
			_menu_exec merge --continue
			return
		fi
		info "resuelve los conflictos en $main, haz git add y vuelve a esta opción"
		return 0
	fi

	path="$(_menu_pick_wt "¿Qué worktree quieres integrar?" "$(_menu_here_wt)")" || return 0
	branch="$(wt_branch_of "$path")"
	[[ -n "$branch" ]] || {
		err "el worktree $path no está en ninguna rama (detached)"
		return 1
	}
	base="$(wt_base_of "$branch")"
	git_branch_exists "$base" || {
		err "la rama base $base no existe"
		return 1
	}

	# 1. El worktree necesita estar commiteado.
	if ! git_is_clean "$path"; then
		warn "$(basename "$path") tiene cambios sin commitear; hay que hacer commit antes de integrar:"
		git -C "$path" status --short | sed 's/^/    /' >&2
		confirm "¿Entrar al worktree para hacer commit?" && _menu_leave "$path"
		return 0
	fi

	# 2. Un merge a mano en el principal: no lo tocamos.
	if git -C "$main" rev-parse -q --verify MERGE_HEAD >/dev/null; then
		err "el principal tiene un merge en curso que no es de gitctl: termínalo (git commit) o abórtalo (git merge --abort) en $main"
		return 1
	fi

	cur="$(git_current_branch "$main")"

	# 3. El principal tiene cambios: gitctl integra ahí, así que estorban.
	if ! git_is_clean "$main"; then
		warn "el principal ($main) tiene cambios sin commitear, y gitctl integra ahí:"
		git -C "$main" status --short | sed 's/^/    /' >&2
		echo "  Puedo guardarlos aparte con «git stash -u»: no se pierden y los recuperas con «git stash pop»." >&2
		if ! confirm "¿Guardarlos en el stash y seguir?"; then
			info "no se integra nada; haz commit de esos cambios en el principal (o bórralos si sobran) y vuelve"
			return 0
		fi
		git -C "$main" stash push -q -u -m "gitctl: antes de integrar $branch" || {
			err "no se pudo hacer git stash en $main"
			return 1
		}
		stashed=1
		ok "cambios del principal guardados en el stash"
	fi

	# 4. El principal tiene que estar en la base.
	if [[ "$cur" != "$base" ]]; then
		warn "el principal está en la rama «${cur:-detached}», pero $branch se integra en $base"
		if confirm "¿Cambiar el principal a $base?"; then
			if git -C "$main" switch -q "$base"; then
				ok "el principal ahora está en $base"
				from="$cur"
			else
				err "no se pudo cambiar el principal a $base"
				_menu_stash_note "$stashed" "$cur"
				return 1
			fi
		else
			info "no se integra nada; el principal sigue en ${cur:-detached}"
			_menu_stash_note "$stashed" "$cur"
			return 0
		fi
	fi

	local rc=0
	_menu_exec merge "$path" || rc=$?
	[[ -n "$from" ]] && info "el principal queda en $base (antes estaba en $from: git switch $from para volver)"
	_menu_stash_note "$stashed" "$cur"
	return "$rc"
}

# Recuerda cómo recuperar lo guardado en el stash. _menu_stash_note <1|""> <rama>
_menu_stash_note() {
	[[ -n "$1" ]] || return 0
	if [[ -n "$2" && "$2" != "$(git_current_branch "$MENU_MAIN")" ]]; then
		info "tus cambios del principal están en el stash; para recuperarlos: git switch $2 && git stash pop"
	else
		info "tus cambios del principal están en el stash; para recuperarlos: git stash pop"
	fi
}

_menu_rm() {
	local path branch base problems=()
	path="$(_menu_pick_wt "¿Qué worktree quieres eliminar?")" || return 0
	branch="$(wt_branch_of "$path" 2>/dev/null || true)"
	if [[ -d "$path" ]] && ! git_is_clean "$path"; then
		problems+=("tiene cambios sin commitear")
	fi
	if [[ -n "$branch" ]]; then
		base="$(wt_base_of "$branch")"
		branch_merged_into "$branch" "$base" || problems+=("la rama $branch tiene commits que no están en $base")
	fi
	if ((${#problems[@]})); then
		warn "$(basename "$path"): ${problems[*]}"
		echo "  Si lo eliminas, eso se pierde. Para conservarlo, intégralo antes (opción 4)." >&2
		confirm "¿Eliminarlo igualmente y descartarlo? No se puede deshacer" || return 0
		_menu_exec rm --force "$path"
	else
		_menu_exec rm "$path"
	fi
}

# Ofrece (una vez) añadir la integración con el shell, para que «Entrar» funcione.
_menu_offer_shell() {
	[[ -n "${GITCTL_SHELL:-}" ]] && return 0
	local sh=bash rc_file="$HOME/.bashrc" marker="${XDG_CONFIG_HOME:-$HOME/.config}/gitctl/shell-offered"
	if [[ "${SHELL##*/}" == zsh ]]; then
		sh=zsh rc_file="$HOME/.zshrc"
	fi
	if [[ -f "$rc_file" ]] && grep -q 'gitctl shell-init' "$rc_file"; then
		warn "la integración con el shell está en $rc_file pero no en esta terminal: sal y ejecuta «source $rc_file» (o abre otra terminal)"
		return 0
	fi
	[[ -e "$marker" ]] && return 0
	mkdir -p "$(dirname "$marker")" && : >"$marker"
	{
		echo
		echo "Para que gitctl te deje dentro de un worktree al elegir «Entrar» o «Nuevo», tu"
		echo "terminal necesita una línea en $rc_file:"
		echo "  eval \"\$(gitctl shell-init $sh)\""
	} >&2
	if confirm "¿La añado ahora?"; then
		printf '\n# gitctl: cambiar de carpeta a los worktrees\neval "$(gitctl shell-init %s)"\n' "$sh" >>"$rc_file"
		ok "añadida a $rc_file"
		info "para activarla en esta terminal: sal del menú (0) y ejecuta «source $rc_file»"
	else
		info "de acuerdo; puedes hacerlo cuando quieras (ver gitctl doctor)"
	fi
}

# --- Bucle principal -------------------------------------------------------------

cmd_interactive() {
	if want_help "$@"; then
		_i_help
		return
	fi
	require_repo
	is_interactive || die "gitctl i necesita una terminal interactiva"
	MENU_MAIN="$(git_main_root)"
	MENU_CD="" MENU_EXIT=0
	_menu_offer_shell

	local choice rc
	local -a items
	while ((MENU_EXIT == 0)); do
		_menu_header
		items=(
			$'new\tNuevo worktree'
			$'enter\tEntrar a un worktree'
			$'diff\tComparar ramas (worktree vs. su base)'
			$'merge\tIntegrar un worktree en su base'
			$'ls\tVer estado (ls)'
			$'rm\tEliminar un worktree'
			$'clean\tLimpiar los ya integrados'
			$'doctor\tDiagnóstico (doctor)'
		)
		[[ -n "$(_menu_here_wt)" ]] && items+=($'home\tVolver al principal')
		choice="$(PICK_ZERO="Salir" pick "¿Qué quieres hacer?" "${items[@]}")" || break
		echo >&2
		rc=0
		case "$choice" in
		new) _menu_new || rc=$? ;;
		enter) _menu_enter || rc=$? ;;
		diff) _menu_diff || rc=$? ;;
		merge) _menu_merge || rc=$? ;;
		ls) _menu_exec ls || rc=$? ;;
		rm) _menu_rm || rc=$? ;;
		clean) _menu_exec clean || rc=$? ;;
		doctor) _menu_exec doctor || rc=$? ;;
		home) _menu_leave "$MENU_MAIN" ;;
		esac
		_menu_fix_cwd
		# Deja leer el resultado antes de volver a pintar el menú.
		if ((MENU_EXIT == 0)) && [[ "$choice" != diff ]]; then pause; fi
		((rc == 0)) || debug "la acción $choice terminó con código $rc"
	done
	[[ -n "$MENU_CD" ]] && cd_to "$MENU_CD"
	return 0
}
