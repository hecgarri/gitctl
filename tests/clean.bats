#!/usr/bin/env bats
load test_helper

setup() { setup_repo; }

@test "clean sin nada que hacer" {
	run gitctl clean
	assert_success
	assert_output_contains "nada que limpiar"
}

@test "clean elimina los integrados y respeta el resto" {
	gitctl new integrado >/dev/null 2>&1
	gitctl new pendiente >/dev/null 2>&1
	commit_in "$(wt_path pendiente)" p p
	gitctl new sucio >/dev/null 2>&1
	echo s >"$(wt_path sucio)/s"
	git worktree add -q -b manual "$TEST_TMP/manual"
	run gitctl -y clean
	assert_success
	[[ ! -d "$(wt_path integrado)" ]]
	refute git show-ref -q refs/heads/integrado
	[[ -d "$(wt_path pendiente)" ]]
	[[ -d "$(wt_path sucio)" ]]
	[[ -d "$TEST_TMP/manual" ]]
}

@test "clean olvida worktrees cuya carpeta se borró" {
	gitctl new x >/dev/null 2>&1
	rm -rf "$(wt_path x)"
	run gitctl -y clean
	assert_success
	[[ "$(git worktree list | wc -l)" -eq 1 ]]
}

@test "clean --dry-run no borra" {
	gitctl new x >/dev/null 2>&1
	run gitctl clean --dry-run
	assert_success
	assert_output_contains "$(wt_path x)"
	[[ -d "$(wt_path x)" ]]
}

@test "clean sin -y ni TTY no borra" {
	gitctl new x >/dev/null 2>&1
	run gitctl clean </dev/null
	assert_failure
	[[ -d "$(wt_path x)" ]]
}
