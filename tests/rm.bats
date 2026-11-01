#!/usr/bin/env bats
load test_helper

setup() {
	setup_repo
	gitctl new x >/dev/null 2>&1
}

@test "rm se niega si hay cambios sin commitear" {
	echo sucio >"$(wt_path x)/s"
	run gitctl -y rm x
	assert_failure
	assert_output_contains "cambios sin commitear"
	[[ -d "$(wt_path x)" ]]
}

@test "rm se niega si hay commits sin integrar" {
	commit_in "$(wt_path x)" f f
	run gitctl -y rm x
	assert_failure
	assert_output_contains "sin integrar"
	git show-ref -q refs/heads/x
}

@test "rm --force descarta cambios y commits" {
	commit_in "$(wt_path x)" f f
	echo sucio >"$(wt_path x)/s"
	run gitctl -y rm x --force
	assert_success
	[[ ! -d "$(wt_path x)" ]]
	refute git show-ref -q refs/heads/x
}

@test "rm de una rama integrada borra worktree, rama y metadatos" {
	run gitctl -y rm x
	assert_success
	[[ ! -d "$(wt_path x)" ]]
	refute git show-ref -q refs/heads/x
	refute git config --get branch.x.gitctl-base
}

@test "rm sin TTY y sin -y no borra" {
	run gitctl rm x </dev/null
	assert_failure
	assert_output_contains "confirmación"
	[[ -d "$(wt_path x)" ]]
}

@test "rm del principal falla" {
	run gitctl -y rm main
	assert_failure
	assert_output_contains "principal"
}

@test "rm desde dentro del worktree te devuelve al principal" {
	cd "$(wt_path x)"
	run env GITCTL_CD_FILE="$CD_FILE" gitctl -y rm x
	assert_success
	[[ "$(cat "$CD_FILE")" == "$REPO" ]]
}
