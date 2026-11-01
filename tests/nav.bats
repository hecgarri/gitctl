#!/usr/bin/env bats
load test_helper

setup() { setup_repo; }

@test "ls muestra el principal y los worktrees con delante/detrás y cambios" {
	gitctl new feat/login >/dev/null 2>&1
	commit_in "$(wt_path feat-login)" f.txt f
	run gitctl ls
	assert_success
	assert_output_contains "(principal)"
	[[ "$output" =~ feat-login\ +feat/login\ +main\ +1/0\ +no ]]
	echo x >"$(wt_path feat-login)/sucio"
	run gitctl ls
	[[ "$output" =~ feat/login\ +main\ +1/0\ +sí ]]
}

@test "ls marca el worktree actual" {
	gitctl new x >/dev/null 2>&1
	cd "$(wt_path x)"
	run gitctl ls
	[[ "$output" =~ \*\ x ]]
}

@test "ls marca como ausente un worktree borrado a mano" {
	gitctl new x >/dev/null 2>&1
	rm -rf "$(wt_path x)"
	run gitctl ls
	assert_success
	assert_output_contains "ausente"
}

@test "cd resuelve por rama, por carpeta y sin argumento" {
	gitctl new feat/login >/dev/null 2>&1
	run gitctl cd feat/login
	[[ "$output" == "$(wt_path feat-login)" ]]
	run gitctl cd feat-login
	[[ "$output" == "$(wt_path feat-login)" ]]
	cd "$(wt_path feat-login)"
	run gitctl cd
	[[ "$output" == "$REPO" ]]
}

@test "cd escribe la ruta para la función de shell" {
	gitctl new x >/dev/null 2>&1
	run env GITCTL_CD_FILE="$CD_FILE" gitctl cd x
	[[ "$(cat "$CD_FILE")" == "$(wt_path x)" ]]
}

@test "cd a un worktree inexistente falla" {
	run gitctl cd nada
	assert_failure
	assert_output_contains "no existe"
}
