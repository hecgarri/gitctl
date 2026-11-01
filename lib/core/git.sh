# shellcheck shell=bash
# Operaciones Git de solo lectura y utilidades seguras.

in_git_repo() { git rev-parse --git-dir >/dev/null 2>&1; }
require_repo() {
	require_cmd git
	in_git_repo || die "no estás dentro de un repositorio Git"
	git rev-parse --verify -q HEAD >/dev/null || die "el repositorio no tiene commits todavía; haz un commit inicial"
}

# Directorio .git común a todos los worktrees.
git_common_dir() { git rev-parse --path-format=absolute --git-common-dir; }

# Raíz del worktree principal (no la del worktree actual).
git_main_root() {
	local common
	common="$(git_common_dir)"
	if [[ "$(git -C "$common" rev-parse --is-bare-repository)" == "true" ]]; then
		echo "$common"
	else
		dirname "$common"
	fi
}

git_head_sha() { git -C "${1:-.}" rev-parse HEAD; }
git_ref_sha() { git rev-parse --verify -q "$1^{commit}"; }
git_short() { git rev-parse --short "$1" 2>/dev/null || printf '%s' "${1:0:8}"; }
git_branch_exists() { git show-ref --verify -q "refs/heads/$1"; }
git_is_clean() { [[ -z "$(git -C "$1" status --porcelain 2>/dev/null)" ]]; }
git_current_branch() { git -C "${1:-.}" symbolic-ref --quiet --short HEAD 2>/dev/null || true; }

# Rama base por defecto: config «base», origin/HEAD, o rama actual del principal.
git_default_branch() {
	local b
	b="$(cfg base)"
	[[ -n "$b" ]] && {
		echo "$b"
		return
	}
	b="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
	[[ -n "$b" ]] && {
		echo "${b#origin/}"
		return
	}
	b="$(git_current_branch "$(git_main_root)")"
	echo "${b:-main}"
}

# Identidad para commits de gitctl si el usuario no tiene ninguna configurada.
git_identity_args() {
	local -n _out="$1"
	_out=()
	git config user.name >/dev/null 2>&1 || _out+=(-c "user.name=gitctl")
	git config user.email >/dev/null 2>&1 || _out+=(-c "user.email=gitctl@localhost")
}

# ¿Se puede fusionar $2 en $1 sin conflictos? (no toca el árbol de trabajo)
# Devuelve 0 si limpio, 1 si conflictos, 2 si error.
git_merge_check() {
	local out rc=0
	out="$(git merge-tree --write-tree --name-only --no-messages "$1" "$2" 2>&1)" || rc=$?
	if ((rc == 1)); then
		printf '%s\n' "$out" | tail -n +2
		return 1
	fi
	((rc == 0)) || {
		printf '%s\n' "$out"
		return 2
	}
}

git_version_ok() {
	local v major minor
	v="$(git --version | awk '{print $3}')"
	major="${v%%.*}"
	minor="${v#*.}"
	minor="${minor%%.*}"
	((major > 2 || (major == 2 && minor >= 38)))
}
