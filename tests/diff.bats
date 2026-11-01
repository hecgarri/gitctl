#!/usr/bin/env bats
load test_helper

setup() {
	setup_repo
	export GIT_PAGER=cat
	gitctl new feat/a >/dev/null 2>&1
	commit_in "$(wt_path feat-a)" f.txt contenido
}

@test "diff muestra el diff completo respecto a la base" {
	run gitctl diff feat-a
	assert_success
	assert_output_contains "+contenido"
}

@test "diff --stat y --files" {
	run gitctl diff feat/a --stat
	assert_success
	assert_output_contains "1 file changed"
	run gitctl diff feat/a --files
	assert_success
	[[ "$output" == "f.txt" ]]
}

@test "diff --log lista los commits que se integrarían" {
	run gitctl diff feat-a --log
	assert_success
	assert_output_contains "cambio f.txt"
}

@test "diff -- <archivo> limita el diff" {
	commit_in "$(wt_path feat-a)" g.txt otro
	run gitctl diff feat-a -- g.txt
	assert_success
	assert_output_contains "+otro"
	[[ "$output" != *"+contenido"* ]]
}

@test "diff desde el worktree no necesita argumento" {
	cd "$(wt_path feat-a)"
	run gitctl diff --files
	assert_success
	[[ "$output" == "f.txt" ]]
}

@test "con la base avanzada no muestra sus cambios, y --behind sí los lista" {
	commit_in "$REPO" base.txt base
	run gitctl diff feat-a --files
	assert_success
	[[ "$output" == "f.txt" ]]
	run gitctl diff feat-a --behind
	assert_success
	assert_output_contains "cambio base.txt"
}

@test "diff --wip muestra los cambios sin commitear" {
	echo nuevo >"$(wt_path feat-a)/README.md"
	run gitctl diff feat-a --wip
	assert_success
	assert_output_contains "+nuevo"
}

@test "diff desde el principal sin argumento falla con una explicación" {
	run gitctl diff
	assert_failure
	assert_output_contains "indica qué worktree comparar"
}
