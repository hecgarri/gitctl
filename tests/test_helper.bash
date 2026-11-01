# shellcheck shell=bash
# Utilidades comunes para los tests: repositorio temporal aislado.

GITCTL_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup_repo() {
	export TEST_TMP="$BATS_TEST_TMPDIR"
	export HOME="$TEST_TMP/home"
	export XDG_CONFIG_HOME="$HOME/.config"
	mkdir -p "$HOME"
	export GIT_AUTHOR_NAME="Tester" GIT_AUTHOR_EMAIL="tester@example.com"
	export GIT_COMMITTER_NAME="Tester" GIT_COMMITTER_EMAIL="tester@example.com"
	export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
	export NO_COLOR=1
	export PATH="$GITCTL_ROOT/bin:$PATH"
	unset GITCTL_YES GITCTL_CD_FILE GITCTL_SHELL
	REPO="$TEST_TMP/repo"
	mkdir -p "$REPO"
	cd "$REPO" || return 1
	git init -q -b main
	echo "hola" >README.md
	printf '.env\nconfig/local.yml\n' >.gitignore
	: >.gitctl.conf
	git add README.md .gitignore .gitctl.conf
	git commit -q -m "inicial"
	export CD_FILE="$TEST_TMP/cd-file"
	: >"$CD_FILE"
}

set_cfg() { echo "$1 = $2" >>"$REPO/.gitctl.conf"; }
wt_path() { echo "$TEST_TMP/repo.wt/$1"; }

# Commit de un archivo en un directorio: commit_in <dir> <archivo> <contenido>
commit_in() {
	echo "$3" >"$1/$2"
	git -C "$1" add "$2"
	git -C "$1" commit -q -m "cambio $2"
}

assert_success() {
	if [[ "$status" -ne 0 ]]; then
		echo "estado $status, salida:"
		echo "$output"
		return 1
	fi
}
assert_failure() {
	if [[ "$status" -eq 0 ]]; then
		echo "se esperaba fallo; salida:"
		echo "$output"
		return 1
	fi
}
assert_output_contains() {
	if [[ "$output" != *"$1"* ]]; then
		echo "la salida no contiene «$1»:"
		echo "$output"
		return 1
	fi
}

# Falla si el comando tiene éxito («! cmd» no hace fallar un test de bats).
refute() {
	if "$@"; then
		echo "no debía cumplirse: $*"
		return 1
	fi
}
