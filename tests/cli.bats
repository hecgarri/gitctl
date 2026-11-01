#!/usr/bin/env bats
load test_helper

setup() { setup_repo; }

@test "--version muestra la versión" {
	run gitctl --version
	assert_success
	assert_output_contains "gitctl 0.2"
}

@test "--help lista los comandos del nuevo flujo" {
	run gitctl --help
	assert_success
	assert_output_contains "new <rama>"
	assert_output_contains "merge"
	[[ "$output" != *agente* ]]
}

@test "un comando desconocido falla" {
	run gitctl inventado
	assert_failure
	assert_output_contains "comando desconocido"
}

@test "sin argumentos equivale a ls" {
	run gitctl
	assert_success
	assert_output_contains "(principal)"
}

@test "fuera de un repositorio falla con un mensaje claro" {
	cd "$TEST_TMP"
	run gitctl ls
	assert_failure
	assert_output_contains "repositorio Git"
}

@test "la configuración se parsea sin ejecutarse" {
	echo 'base = main; touch HACKED' >>.gitctl.conf
	echo 'copy = $(touch HACKED2)' >>.gitctl.conf
	run gitctl doctor
	[[ ! -e HACKED && ! -e HACKED2 ]]
}

@test "init crea un .gitctl.conf de ejemplo y no lo sobrescribe" {
	rm .gitctl.conf
	run gitctl init
	assert_success
	grep -q "copy" .gitctl.conf
	echo "base = main" >.gitctl.conf
	run gitctl init
	assert_success
	[[ "$(cat .gitctl.conf)" == "base = main" ]]
}

@test "doctor muestra copy y setup configurados" {
	set_cfg copy ".env"
	set_cfg setup "true"
	run gitctl doctor
	assert_output_contains "copy = .env"
	assert_output_contains "setup = true"
	assert_output_contains "rama por defecto: main"
}
