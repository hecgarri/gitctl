#!/usr/bin/env bats
load test_helper

setup() {
	setup_repo
	crear codex t
	W="$(wt codex t)"
}

integrar() { g Integrar -Agente codex -Tarea t -Metodo "${1:-Merge}" "${@:2}" -ConfirmarIntegracion >/dev/null 2>&1; }

@test "merge seguido de retiro: borra worktree y rama" {
	commit_en "$W" a.txt a
	integrar
	run g Eliminar -Agente codex -Tarea t -ConfirmarEliminacion
	assert_success
	assert_output_contains "Integración: Fusionada"
	assert_output_contains "y su rama codex/t"
	[[ ! -d "$W" ]]
	refute git show-ref --verify -q refs/heads/codex/t
	[[ "$(git worktree list | wc -l)" == 1 ]]
}

@test "sin interacción exige -ConfirmarEliminacion" {
	run g Eliminar -Agente codex -Tarea t
	assert_failure
	assert_output_contains "-ConfirmarEliminacion"
	[[ -d "$W" ]]
}

@test "con -Accion pregunta si no hay -SinInteraccion" {
	responder '\n' -Accion Eliminar -Agente codex -Tarea t
	assert_success
	assert_output_contains "¿Retirar el worktree? [s/N]"
	[[ -d "$W" ]]
	responder 'si\n' -Accion Eliminar -Agente codex -Tarea t
	assert_success
	[[ ! -d "$W" ]]
}

@test "cherry-pick y retiro: conserva la rama (EquivalentePorCherryPick)" {
	commit_en "$REPO" m.txt m
	commit_en "$W" a.txt a
	integrar CherryPick -Commits "$(git rev-parse codex/t)"
	run g Eliminar -Agente codex -Tarea t -ConfirmarEliminacion
	assert_success
	assert_output_contains "EquivalentePorCherryPick"
	assert_output_contains "la rama codex/t se conserva"
	[[ ! -d "$W" ]]
	git show-ref --verify -q refs/heads/codex/t
}

@test "rama sin integrar: exige -CerrarSinIntegrar y la conserva" {
	commit_en "$W" a.txt a
	run g Eliminar -Agente codex -Tarea t -ConfirmarEliminacion
	assert_failure
	assert_output_contains "-CerrarSinIntegrar"
	run g Eliminar -Agente codex -Tarea t -ConfirmarEliminacion -Forzar
	assert_failure
	assert_output_contains "-CerrarSinIntegrar"
	[[ -d "$W" ]]
	run g Eliminar -Agente codex -Tarea t -ConfirmarEliminacion -CerrarSinIntegrar
	assert_success
	[[ ! -d "$W" ]]
	git show-ref --verify -q refs/heads/codex/t
}

@test "rama sin integrar en modo interactivo pregunta si conservarla" {
	commit_en "$W" a.txt a
	responder 'n\n' -Accion Eliminar -Agente codex -Tarea t
	assert_success
	assert_output_contains "conservando la rama"
	[[ -d "$W" ]]
	responder 's\ns\n' -Accion Eliminar -Agente codex -Tarea t
	assert_success
	[[ ! -d "$W" ]]
	git show-ref --verify -q refs/heads/codex/t
}

@test "retiro sucio sin -Forzar: se rechaza con rutas y alternativas" {
	echo x >"$W/p.txt"
	echo y >>"$W/README.md"
	run g Eliminar -Agente codex -Tarea t -ConfirmarEliminacion
	assert_failure
	assert_output_contains "? p.txt"
	assert_output_contains "M README.md"
	assert_output_contains "-Forzar"
	assert_output_contains "-RescatarCambios"
	[[ -f "$W/p.txt" ]]
}

@test "-Forzar no sustituye a -ConfirmarEliminacion" {
	echo x >"$W/p.txt"
	run g Eliminar -Agente codex -Tarea t -Forzar
	assert_failure
	assert_output_contains "-ConfirmarEliminacion"
	[[ -f "$W/p.txt" ]]
	run g Eliminar -Agente codex -Tarea t -Forzar -ConfirmarEliminacion
	assert_success
	assert_output_contains "Se descartarán 1 cambio(s)"
	[[ ! -d "$W" ]]
}

@test "rescate de archivos y directorios sin seguimiento con -Forzar -CerrarSinIntegrar" {
	commit_en "$W" a.txt a
	echo cambio >>"$W/src/app.txt"
	mkdir -p "$W/nuevo/sub dir"
	echo uno >"$W/nuevo/sub dir/ñ uno.txt"
	echo dos >"$W/nuevo/dos.txt"
	rm "$W/README.md"
	run g Eliminar -Agente codex -Tarea t -CerrarSinIntegrar -Forzar -RescatarCambios "$TEST_TMP/rescate" -ConfirmarEliminacion
	assert_success
	assert_output_contains "copiados 3 archivo(s)"
	assert_output_contains "eliminados no se copian"
	[[ "$(cat "$TEST_TMP/rescate/src/app.txt")" == "$(printf 'uno\ncambio')" ]]
	[[ -f "$TEST_TMP/rescate/nuevo/sub dir/ñ uno.txt" ]]
	[[ -f "$TEST_TMP/rescate/nuevo/dos.txt" ]]
	[[ ! -e "$TEST_TMP/rescate/README.md" ]]
	[[ ! -d "$W" ]]
	git show-ref --verify -q refs/heads/codex/t
}

@test "el rescate no puede ir dentro del worktree" {
	echo x >"$W/p.txt"
	run g Eliminar -Agente codex -Tarea t -Forzar -RescatarCambios "$W/rescate" -ConfirmarEliminacion
	assert_failure
	assert_output_contains "no puede ser el worktree"
	[[ -d "$W" ]]
}

@test "rescate de un worktree limpio: nada que rescatar" {
	run g Eliminar -Agente codex -Tarea t -RescatarCambios "$TEST_TMP/rescate" -ConfirmarEliminacion
	assert_success
	assert_output_contains "no hay nada que rescatar"
	[[ ! -e "$TEST_TMP/rescate" ]]
}

@test "descarte interactivo autorizado con copia previa, sin pregunta redundante" {
	echo x >"$W/p.txt"
	responder 's\ns\n\n'"$TEST_TMP"'/copia\n' -Accion Eliminar -Agente codex -Tarea t
	assert_success
	assert_output_contains "descartarlos es irreversible"
	refute_output_contains "¿Retirar el worktree? [s/N]"
	[[ -f "$TEST_TMP/copia/p.txt" ]]
	[[ ! -d "$W" ]]
}

@test "descarte interactivo rechazado: no modifica nada" {
	echo x >"$W/p.txt"
	responder 'n\n' -Accion Eliminar -Agente codex -Tarea t
	assert_success
	assert_output_contains "cancelado"
	[[ -f "$W/p.txt" ]]
}

@test "con -Forzar interactivo no pregunta el descarte pero sí el retiro" {
	echo x >"$W/p.txt"
	responder 's\n' -Accion Eliminar -Agente codex -Tarea t -Forzar
	assert_success
	refute_output_contains "¿Descartar estos cambios"
	assert_output_contains "¿Retirar el worktree? [s/N]"
	[[ ! -d "$W" ]]
}

@test "rechaza si cambió la rama activa, aun con -Forzar y -CerrarSinIntegrar" {
	git -C "$W" switch -q -c otra
	run g Eliminar -Agente codex -Tarea t -Forzar -CerrarSinIntegrar -ConfirmarEliminacion
	assert_failure
	assert_output_contains "switch codex/t"
	[[ -d "$W" ]]
}

@test "detached con un commit sin rama: avisa que podría perderse" {
	git -C "$W" switch -q --detach
	commit_en "$W" huerfano.txt h
	run g Eliminar -Agente codex -Tarea t -Forzar -CerrarSinIntegrar -ConfirmarEliminacion
	assert_failure
	assert_output_contains "podría perderse"
	assert_output_contains "branch <nombre> HEAD"
	[[ -d "$W" ]]
}

@test "borra una rama fusionada respecto de una base distinta de HEAD" {
	git branch dev
	g Crear -Agente codex -Tarea d -Base dev >/dev/null 2>&1
	commit_en "$(wt codex d)" d.txt d
	git switch -q dev
	git merge -q --no-ff --no-edit codex/d
	git switch -q main
	run g Eliminar -Agente codex -Tarea d -ConfirmarEliminacion
	assert_success
	assert_output_contains "Base:        dev"
	refute git show-ref --verify -q refs/heads/codex/d
}

@test "limpia el registro cuando falta la carpeta" {
	rm -rf "$W"
	run g Eliminar -Agente codex -Tarea t -ConfirmarEliminacion
	assert_success
	assert_output_contains "solo se limpia su registro"
	[[ "$(git worktree list | wc -l)" == 1 ]]
}

@test "seleccionar de la lista y cancelar" {
	responder '0\n' -Accion Eliminar
	assert_success
	assert_output_contains "[1] codex/t"
	assert_output_contains "cancelado"
	[[ -d "$W" ]]
}
