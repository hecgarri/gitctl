# shellcheck shell=bash
# Utilidades comunes para los tests: repositorio temporal aislado.

GITCTL_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup_repo() {
	export TEST_TMP="$BATS_TEST_TMPDIR"
	export HOME="$TEST_TMP/home"
	mkdir -p "$HOME"
	export GIT_AUTHOR_NAME="Tester" GIT_AUTHOR_EMAIL="tester@example.com"
	export GIT_COMMITTER_NAME="Tester" GIT_COMMITTER_EMAIL="tester@example.com"
	export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
	export NO_COLOR=1
	export PATH="$GITCTL_ROOT/bin:$PATH"
	REPO="$TEST_TMP/repo"
	RAIZ="$TEST_TMP/repo-agents"
	mkdir -p "$REPO"
	cd "$REPO" || return 1
	git init -q -b main
	echo "hola" >README.md
	mkdir -p src
	echo "uno" >src/app.txt
	git add README.md src
	git commit -q -m "inicial"
}

# gitctl sin interacción: g <acción> [parámetros…]
g() { gitctl -Accion "$1" "${@:2}" -SinInteraccion; }

# Crea el worktree de <agente>/<tarea>.
crear() { g Crear -Agente "$1" -Tarea "$2" >/dev/null 2>&1; }

wt() { echo "$RAIZ/$1/$2"; }

# Commit de un archivo en un directorio: commit_en <dir> <archivo> <contenido> [mensaje]
commit_en() {
	mkdir -p "$(dirname "$1/$2")"
	echo "$3" >"$1/$2"
	git -C "$1" add "$2"
	git -C "$1" commit -q -m "${4:-cambio $2}"
}

# Ejecuta gitctl con las respuestas dadas por stdin: responder "<líneas>" [parámetros…]
responder() {
	local input="$1"
	shift
	run bash -c 'printf "%b" "$1" | gitctl "${@:2}"' _ "$input" "$@"
}

# Huella de todas las referencias (para comprobar que no cambian).
refs() { git -C "$REPO" for-each-ref --format='%(refname) %(objectname)'; }

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
refute_output_contains() {
	if [[ "$output" == *"$1"* ]]; then
		echo "la salida no debía contener «$1»:"
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
