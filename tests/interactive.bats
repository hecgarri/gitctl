#!/usr/bin/env bats
load test_helper

setup() {
	setup_repo
	export GITCTL_ASSUME_TTY=1
}

# Ejecuta gitctl interactivo con las respuestas dadas (una por línea).
answer() {
	local input="$1"
	shift
	run bash -c 'printf "%b" "$1" | GITCTL_CD_FILE="$2" gitctl "${@:3}"' _ "$input" "$CD_FILE" "$@"
}

@test "sin terminal, gitctl sin argumentos sigue siendo ls" {
	unset GITCTL_ASSUME_TTY
	run gitctl </dev/null
	assert_success
	assert_output_contains "(principal)"
}

@test "desde el principal crea un worktree con la base por defecto" {
	answer 'nuevo\n\n'
	assert_success
	assert_output_contains "Worktrees existentes: ninguno"
	[[ -d "$(wt_path nuevo)" ]]
	[[ "$(git config branch.nuevo.gitctl-base)" == "main" ]]
	[[ "$(cat "$CD_FILE")" == "$(wt_path nuevo)" ]]
}

@test "desde el principal se puede elegir otra base" {
	git branch dev
	answer 'x\ndev\n'
	assert_success
	[[ "$(git config branch.x.gitctl-base)" == "dev" ]]
}

@test "con una rama existente sin worktree no pregunta la base" {
	git branch vieja
	answer 'vieja\n'
	assert_success
	assert_output_contains "reutilizando"
	[[ -d "$(wt_path vieja)" ]]
}

@test "un nombre existente te lleva al worktree" {
	gitctl new feat/a >/dev/null 2>&1
	commit_in "$(wt_path feat-a)" f f
	answer 'feat-a\n'
	assert_success
	assert_output_contains "Worktrees existentes: feat-a"
	assert_output_contains "ya existe"
	[[ "$(cat "$CD_FILE")" == "$(wt_path feat-a)" ]]
}

@test "respuesta vacía no hace nada" {
	answer '\n'
	assert_success
	assert_output_contains "nada que hacer"
	[[ ! -d "$TEST_TMP/repo.wt" ]] || [[ -z "$(ls -A "$TEST_TMP/repo.wt")" ]]
}

@test "ofrece limpiar los worktrees ya integrados" {
	gitctl new hecho >/dev/null 2>&1
	answer 's\n\n'
	assert_success
	assert_output_contains "eliminado"
	[[ ! -d "$(wt_path hecho)" ]]
}

@test "desde un worktree: integrar y eliminar" {
	gitctl new x >/dev/null 2>&1
	commit_in "$(wt_path x)" f.txt f
	cd "$(wt_path x)"
	answer 's\ns\n'
	assert_success
	assert_output_contains "1 por delante / 0 por detrás de main"
	[[ -f "$REPO/f.txt" ]]
	[[ -n "$(git -C "$REPO" log -1 --merges --format=%H)" ]]
	[[ ! -d "$(wt_path x)" ]]
	[[ "$(cat "$CD_FILE")" == "$REPO" ]]
}

@test "desde un worktree: no integrar y volver al principal" {
	gitctl new x >/dev/null 2>&1
	commit_in "$(wt_path x)" f.txt f
	cd "$REPO/../repo.wt/x"
	answer 'n\ns\n'
	assert_success
	[[ ! -f "$REPO/f.txt" ]]
	[[ "$(cat "$CD_FILE")" == "$REPO" ]]
}

@test "desde un worktree con cambios pide commit primero" {
	gitctl new x >/dev/null 2>&1
	echo s >"$(wt_path x)/sucio"
	cd "$(wt_path x)"
	answer 's\n'
	assert_failure
	assert_output_contains "haz commit primero"
}

@test "desde un worktree con conflictos pregunta qué hacer" {
	gitctl new x >/dev/null 2>&1
	commit_in "$(wt_path x)" README.md rama
	commit_in "$REPO" README.md main
	cd "$(wt_path x)"
	answer 's\na\n'
	assert_failure
	assert_output_contains "merge abortado"
	refute git -C "$REPO" rev-parse -q --verify MERGE_HEAD
}
