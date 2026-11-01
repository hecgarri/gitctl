#!/usr/bin/env bats
load test_helper

setup() { setup_repo; }

@test "shell-init bash imprime la función con el protocolo de cd" {
	run gitctl shell-init bash
	assert_success
	assert_output_contains "GITCTL_CD_FILE"
	assert_output_contains "command gitctl"
}

@test "shell-init zsh no incluye el autocompletado de bash" {
	run gitctl shell-init zsh
	assert_success
	[[ "$output" != *"complete -F"* ]]
}

@test "shell-init con un shell no soportado falla" {
	run gitctl shell-init fish
	assert_failure
}

@test "la función de shell cambia de carpeta con new y cd" {
	run bash -c 'eval "$(gitctl shell-init bash)"; gitctl new feat/x >/dev/null 2>&1; pwd; gitctl cd >/dev/null; pwd'
	assert_success
	[[ "${lines[0]}" == "$(wt_path feat-x)" ]]
	[[ "${lines[1]}" == "$REPO" ]]
}

@test "la función de shell funciona en zsh" {
	command -v zsh >/dev/null || skip "zsh no instalado"
	run zsh -c 'eval "$(gitctl shell-init zsh)"; gitctl new z >/dev/null 2>&1; pwd'
	assert_success
	[[ "$output" == "$(wt_path z)" ]]
}
