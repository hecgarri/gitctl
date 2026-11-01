#!/usr/bin/env bats
load test_helper

# Menú: 1 nuevo · 2 entrar · 3 comparar · 4 integrar · 5 ls · 6 eliminar
#       7 limpiar · 8 doctor · 9 volver al principal (solo en un worktree) · 0 salir

setup() {
	setup_repo
	export GITCTL_ASSUME_TTY=1 GITCTL_PICKER=basic GIT_PAGER=cat
}

# Ejecuta gitctl interactivo con las respuestas dadas (una por línea), como si
# tuviera la integración con el shell.
answer() {
	local input="$1"
	shift
	run bash -c 'printf "%b" "$1" | GITCTL_SHELL=1 GITCTL_CD_FILE="$2" gitctl "${@:3}"' _ "$input" "$CD_FILE" "$@"
}

# Cuántas veces se mostró el menú principal.
menu_count() { grep -c "¿Qué quieres hacer?" <<<"$output"; }

@test "sin terminal, gitctl sin argumentos sigue siendo ls" {
	unset GITCTL_ASSUME_TTY
	run gitctl </dev/null
	assert_success
	assert_output_contains "(principal)"
}

@test "muestra el menú con la cabecera y sale con 0" {
	gitctl new feat/a >/dev/null 2>&1
	answer '0\n'
	assert_success
	assert_output_contains "estás en: (principal) rama main"
	assert_output_contains "feat-a"
	assert_output_contains "Comparar ramas"
	assert_output_contains "0) Salir"
	[[ ! -s "$CD_FILE" ]]
}

@test "fin de la entrada cierra el menú" {
	answer ''
	assert_success
}

@test "nuevo: crea el worktree con la base por defecto y sale dentro" {
	answer '1\nnuevo\n\n'
	assert_success
	[[ -d "$(wt_path nuevo)" ]]
	[[ "$(git config branch.nuevo.gitctl-base)" == "main" ]]
	[[ "$(cat "$CD_FILE")" == "$(wt_path nuevo)" ]]
	[[ "$(menu_count)" == 1 ]]
}

@test "nuevo: se puede elegir otra base" {
	git branch dev
	answer '1\nx\ndev\n'
	assert_success
	[[ "$(git config branch.x.gitctl-base)" == "dev" ]]
}

@test "nuevo: con una rama existente no pregunta la base" {
	git branch vieja
	answer '1\nvieja\n'
	assert_success
	assert_output_contains "reutilizando"
	[[ -d "$(wt_path vieja)" ]]
}

@test "nuevo: un nombre existente ofrece entrar" {
	gitctl new feat/a >/dev/null 2>&1
	answer '1\nfeat-a\ns\n'
	assert_success
	[[ "$(cat "$CD_FILE")" == "$(wt_path feat-a)" ]]
}

@test "nuevo: nombre vacío vuelve al menú" {
	answer '1\n\n\n0\n'
	assert_success
	[[ "$(menu_count)" == 2 ]]
}

@test "entrar: elige de la lista y sale dentro" {
	gitctl new feat/a >/dev/null 2>&1
	answer '2\n1\n'
	assert_success
	[[ "$(cat "$CD_FILE")" == "$(wt_path feat-a)" ]]
}

@test "entrar: sin worktrees avisa y vuelve al menú" {
	answer '2\n\n0\n'
	assert_success
	assert_output_contains "no hay worktrees"
	[[ "$(menu_count)" == 2 ]]
}

@test "integrar desde el worktree: integra, elimina y sigue en el principal" {
	gitctl new x >/dev/null 2>&1
	commit_in "$(wt_path x)" f.txt f
	cd "$(wt_path x)"
	answer '4\n1\ns\n\n0\n'
	assert_success
	[[ -f "$REPO/f.txt" ]]
	[[ -n "$(git -C "$REPO" log -1 --merges --format=%H)" ]]
	[[ ! -d "$(wt_path x)" ]]
	[[ "$(cat "$CD_FILE")" == "$REPO" ]]
	[[ "$(menu_count)" == 2 ]]
}

@test "integrar con el principal en otra rama ofrece cambiar a la base" {
	gitctl new x >/dev/null 2>&1
	commit_in "$(wt_path x)" f.txt f
	git switch -q -c otra
	answer '4\n1\ns\ns\n\n0\n'
	assert_success
	assert_output_contains "el principal está en la rama «otra»"
	assert_output_contains "antes estaba en otra"
	[[ "$(git -C "$REPO" branch --show-current)" == "main" ]]
	[[ -f "$REPO/f.txt" ]]
}

@test "integrar con el principal en otra rama: si dices que no, no toca nada" {
	gitctl new x >/dev/null 2>&1
	commit_in "$(wt_path x)" f.txt f
	git switch -q -c otra
	answer '4\n1\nn\n\n0\n'
	assert_success
	assert_output_contains "no se integra nada"
	[[ "$(git branch --show-current)" == "otra" ]]
	[[ -d "$(wt_path x)" ]]
}

@test "integrar con el principal sucio ofrece stash y recuerda cómo recuperarlo" {
	gitctl new x >/dev/null 2>&1
	commit_in "$(wt_path x)" f.txt f
	echo suelto >"$REPO/suelto.txt"
	answer '4\n1\ns\ns\n\n0\n'
	assert_success
	assert_output_contains "suelto.txt"
	assert_output_contains "git stash pop"
	[[ -f "$REPO/f.txt" ]]
	[[ ! -f "$REPO/suelto.txt" ]]
	[[ -n "$(git stash list)" ]]
}

@test "integrar con el principal sucio: si dices que no, no integra" {
	gitctl new x >/dev/null 2>&1
	commit_in "$(wt_path x)" f.txt f
	echo suelto >"$REPO/suelto.txt"
	answer '4\n1\nn\n\n0\n'
	assert_success
	assert_output_contains "no se integra nada"
	[[ -f "$REPO/suelto.txt" ]]
	[[ ! -f "$REPO/f.txt" ]]
}

@test "integrar un worktree con cambios sin commitear ofrece entrar" {
	gitctl new x >/dev/null 2>&1
	echo s >"$(wt_path x)/sucio"
	answer '4\n1\ns\n'
	assert_success
	assert_output_contains "hay que hacer commit"
	assert_output_contains "sucio"
	[[ "$(cat "$CD_FILE")" == "$(wt_path x)" ]]
}

@test "un merge con conflictos vuelve al menú" {
	gitctl new x >/dev/null 2>&1
	commit_in "$(wt_path x)" README.md rama
	commit_in "$REPO" README.md main
	answer '4\n1\na\n\n0\n'
	assert_success
	assert_output_contains "merge abortado"
	refute git -C "$REPO" rev-parse -q --verify MERGE_HEAD
	[[ "$(menu_count)" == 2 ]]
}

@test "comparar: el resumen muestra los archivos del worktree" {
	gitctl new x >/dev/null 2>&1
	commit_in "$(wt_path x)" f.txt contenido
	answer '3\n1\n1\n\n0\n0\n'
	assert_success
	assert_output_contains "x: x vs. main  (1 por delante / 0 por detrás)"
	assert_output_contains "f.txt"
	assert_output_contains "1 file changed"
}

@test "comparar: commits y diff de un archivo" {
	gitctl new x >/dev/null 2>&1
	commit_in "$(wt_path x)" f.txt contenido
	answer '3\n1\n2\n\n4\n1\n\n0\n0\n'
	assert_success
	assert_output_contains "cambio f.txt"
	assert_output_contains "+contenido"
}

@test "comparar: ofrece ver los cambios sin commitear" {
	gitctl new x >/dev/null 2>&1
	echo nuevo >"$(wt_path x)/README.md"
	answer '3\n1\n5\n\n0\n0\n'
	assert_success
	assert_output_contains "Cambios sin commitear"
	assert_output_contains "+nuevo"
}

@test "limpiar: elimina los ya integrados" {
	gitctl new hecho >/dev/null 2>&1
	answer '7\ns\n\n0\n'
	assert_success
	assert_output_contains "eliminado"
	[[ ! -d "$(wt_path hecho)" ]]
}

@test "eliminar: con commits sin integrar avisa y pide confirmar dos veces" {
	gitctl new x >/dev/null 2>&1
	commit_in "$(wt_path x)" f.txt f
	answer '6\n1\ns\ns\n\n0\n'
	assert_success
	assert_output_contains "tiene commits que no están en main"
	[[ ! -d "$(wt_path x)" ]]
	refute git show-ref --verify -q refs/heads/x
}

@test "eliminar: si dices que no, se conserva" {
	gitctl new x >/dev/null 2>&1
	commit_in "$(wt_path x)" f.txt f
	answer '6\n1\nn\n\n0\n'
	assert_success
	[[ -d "$(wt_path x)" ]]
}

@test "volver al principal solo aparece dentro de un worktree" {
	gitctl new x >/dev/null 2>&1
	answer '0\n'
	[[ "$output" != *"Volver al principal"* ]]
	cd "$(wt_path x)"
	answer '9\n'
	assert_success
	[[ "$(cat "$CD_FILE")" == "$REPO" ]]
}

@test "sin integración con el shell ofrece añadirla una sola vez" {
	export SHELL=/bin/bash
	run bash -c 'printf "s\n0\n" | gitctl'
	assert_success
	grep -q 'eval "$(gitctl shell-init bash)"' "$HOME/.bashrc"
	run bash -c 'printf "0\n" | gitctl'
	assert_success
	assert_output_contains "source $HOME/.bashrc"
	[[ "$(grep -c 'gitctl shell-init' "$HOME/.bashrc")" == 1 ]]
}

@test "sin integración, entrar indica a qué carpeta ir" {
	gitctl new x >/dev/null 2>&1
	mkdir -p "$XDG_CONFIG_HOME/gitctl" && : >"$XDG_CONFIG_HOME/gitctl/shell-offered"
	run bash -c 'printf "2\n1\n" | gitctl'
	assert_success
	assert_output_contains "cd $(wt_path x)"
}
