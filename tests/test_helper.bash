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
	unset GITCTL_RUN_ID GITCTL_YES
	REPO="$TEST_TMP/repo"
	mkdir -p "$REPO"
	cd "$REPO" || return 1
	git init -q -b main
	echo "hola" >README.md
	git add README.md
	git commit -q -m "inicial"
	gitctl init >/dev/null 2>&1
	# El .gitctl.conf de ejemplo se sustituye por uno mínimo en cada test.
	: >.gitctl.conf
	git add .gitctl.conf
	git commit -q -m "config"
}

add_check() { echo "check.$1 = $2" >>"$REPO/.gitctl.conf"; }
set_cfg() { echo "$1 = $2" >>"$REPO/.gitctl.conf"; }

state() { echo "$REPO/.git/gitctl"; }
wt_of() { echo "$TEST_TMP/repo.wt/$1-$2"; }

# Crea la tarea t1 con los agentes indicados y ejecuta un run de cada uno.
task_with_runs() {
	gitctl task new "Tarea de prueba" >/dev/null 2>&1
	gitctl task assign t1 "$@" >/dev/null 2>&1
	gitctl run t1 --wait >/dev/null 2>&1
}

# Imprime la salida de run (útil al depurar con bats --print-output-on-failure).
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
