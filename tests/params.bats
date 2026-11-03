#!/usr/bin/env bats
load test_helper

setup() { setup_repo; }

@test "--help y --version" {
	run gitctl --help
	assert_success
	assert_output_contains "-Accion"
	run gitctl --version
	assert_success
	assert_output_contains "gitctl "
}

@test "-SinInteraccion sin -Accion se rechaza" {
	run gitctl -SinInteraccion
	assert_failure
	assert_output_contains "requiere -Accion"
}

@test "nombres y valores sin distinguir mayúsculas, también con --" {
	run gitctl -accion estado -sininteraccion
	assert_success
	run gitctl --ACCION Estado --SinInteraccion
	assert_success
}

@test "valores no válidos de enumerados y rangos" {
	run g Bailar
	assert_failure
	assert_output_contains "valores admitidos"
	run g Estado -MaxCaracteresLlm 5
	assert_failure
	assert_output_contains "entre 10000 y 1000000"
	run g Estado -TiempoEsperaLlmSegundos 0
	assert_failure
	run g Estado -TiempoEsperaLlmSegundos abc
	assert_failure
	run g Estado -ProveedorLlm otro
	assert_failure
}

@test "parámetro desconocido o argumento suelto" {
	run g Estado -Nada 1
	assert_failure
	assert_output_contains "desconocido"
	run gitctl suelto
	assert_failure
	assert_output_contains "argumento inesperado"
}

@test "-Ramas acepta comas, espacios y varios valores" {
	crear claude t
	crear codex t
	run g Comparar -Ramas " claude/t , ,codex/t "
	assert_success
	assert_output_contains "solo están en claude/t"
	run g Comparar -Ramas claude/t codex/t
	assert_success
	run g Comparar -Ramas claude/t -Ramas codex/t
	assert_success
	run g Comparar -Ramas "claude/t,codex/t,main"
	assert_failure
	assert_output_contains "exactamente dos"
}

@test "lista separada por comas a través de bash -c (equivalente a powershell -File)" {
	crear claude t
	crear codex t
	run bash -c 'gitctl -Accion Comparar -Ramas "claude/t,codex/t" -SinInteraccion'
	assert_success
}

@test "un modificador admite :\$false" {
	run g Estado -MostrarDiffCompleto:\$false
	assert_success
}
