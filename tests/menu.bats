#!/usr/bin/env bats
load test_helper

setup() { setup_repo; }

@test "muestra el menú y sale con 7, salir o q sin cambios" {
	local antes
	antes="$(refs)"
	local s
	for s in 7 salir ' Q ' SALIR; do
		responder "$s\n"
		assert_success
		assert_output_contains "[1] Crear un worktree"
		assert_output_contains "[4] Evaluar con un LLM"
		assert_output_contains "[7] Salir"
		[[ "$(grep -c 'Selecciona una opción' <<<"$output")" == 1 ]]
	done
	[[ "$(refs)" == "$antes" ]]
}

@test "fin de la entrada cierra el menú" {
	responder ''
	assert_success
}

@test "opción no válida repite el menú" {
	responder '9\nx\n7\n'
	assert_success
	assert_output_contains "opción no válida: «9»"
	[[ "$(grep -c 'Selecciona una opción' <<<"$output")" == 3 ]]
}

@test "el menú es persistente: crear y luego ver el estado" {
	responder '1\n2\nmi-tarea\ns\n2\n7\n'
	assert_success
	assert_output_contains "worktree creado"
	assert_output_contains "codex  mi-tarea  codex/mi-tarea"
	[[ "$(grep -c 'Selecciona una opción' <<<"$output")" == 3 ]]
}

@test "un error en una acción se muestra y se vuelve al menú" {
	git branch codex/t
	responder '1\n2\nt\n7\n'
	assert_success
	assert_output_contains "la rama codex/t ya existe"
	assert_output_contains "vuelves al menú"
	[[ "$(grep -c 'Selecciona una opción' <<<"$output")" == 2 ]]
}

@test "con -Accion directa los errores salen con código distinto de cero" {
	git branch codex/t
	run g Crear -Agente codex -Tarea t
	[[ "$status" -ne 0 ]]
}
