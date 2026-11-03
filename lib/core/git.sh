# shellcheck shell=bash
# Capa de Git: todas las llamadas que necesitan inspeccionar el resultado pasan
# por aquí. El éxito se decide por el código de salida, no por que haya stderr
# (git escribe también el progreso en stderr).

# git_try <dir> args… → GIT_RC, GIT_OUT, GIT_LINES, GIT_ERR. No aborta.
git_try() {
	local dir="$1" errf
	shift
	errf="$(mktemp)"
	GIT_RC=0
	GIT_OUT="$(git -C "$dir" -c core.quotePath=false "$@" 2>"$errf")" || GIT_RC=$?
	GIT_ERR="$(<"$errf")"
	rm -f "$errf"
	GIT_LINES=()
	[[ -n "$GIT_OUT" ]] && mapfile -t GIT_LINES <<<"$GIT_OUT"
	return "$GIT_RC"
}

# git_run <dir> args… — como git_try, pero aborta con el comando y el detalle.
git_run() {
	git_try "$@" && return 0
	local dir="$1"
	shift
	die "falló «git $*» en $dir (código $GIT_RC)${GIT_ERR:+: $GIT_ERR}"
}

# git del principal, sin paginador y con rutas sin escapar (para mostrar).
git_ver() { git -C "$REPO" -c core.quotePath=false --no-pager "$@"; }

rama_local_existe() { git -C "$REPO" show-ref --verify -q "refs/heads/$1"; }

sha_de_rama() { git -C "$REPO" rev-parse --verify -q "refs/heads/$1^{commit}"; }

rama_activa() { git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null; }

# ¿Hay un merge, cherry-pick, revert o rebase a medias en <dir>? → OP_PENDIENTE
operacion_pendiente() {
	local m p
	OP_PENDIENTE=""
	for m in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
		p="$(git -C "$1" rev-parse --git-path "$m")"
		[[ "$p" == /* ]] || p="$1/$p"
		if [[ -e "$p" ]]; then
			OP_PENDIENTE="$m"
			return 0
		fi
	done
	return 1
}
