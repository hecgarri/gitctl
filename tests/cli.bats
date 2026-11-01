#!/usr/bin/env bats
load test_helper

setup() { setup_repo; }

@test "--version muestra la versión" {
	run gitctl --version
	assert_success
	assert_output_contains "gitctl 0."
}

@test "--help y help muestran la ayuda en español" {
	run gitctl --help
	assert_success
	assert_output_contains "Tareas y agentes"
	run gitctl task --help
	assert_success
	assert_output_contains "Uso: gitctl task"
}

@test "un comando desconocido falla" {
	run gitctl inventado
	assert_failure
	assert_output_contains "comando desconocido"
}

@test "sin TTY y sin argumentos muestra la ayuda en vez del menú" {
	run gitctl </dev/null
	assert_success
	assert_output_contains "Uso: gitctl"
}

@test "doctor detecta que no hay checks" {
	run gitctl doctor
	assert_output_contains "no hay checks"
	add_check test "true"
	run gitctl doctor
	assert_output_contains "checks: test"
}

@test "agents lista el adaptador fake" {
	run gitctl agents
	assert_success
	assert_output_contains "fake"
}

@test "fuera de un repositorio falla con un mensaje claro" {
	cd "$TEST_TMP"
	run gitctl task ls
	assert_failure
	assert_output_contains "repositorio Git"
}

@test "la configuración se parsea sin ejecutarse" {
	echo 'check.x = $(touch HACKED)' >>.gitctl.conf
	echo 'base = main; touch HACKED2' >>.gitctl.conf
	run gitctl doctor
	[[ ! -e HACKED && ! -e HACKED2 ]]
}

@test "init no sobrescribe un .gitctl.conf existente" {
	echo "# mío" >.gitctl.conf
	run gitctl init
	assert_success
	[[ "$(cat .gitctl.conf)" == "# mío" ]]
}
