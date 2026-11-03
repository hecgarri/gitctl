#!/usr/bin/env bats
load test_helper

setup() {
	setup_repo
	crear codex t
	W="$(wt codex t)"
}

@test "merge: integra con --no-ff, conserva worktree y rama, y recuerda las pruebas" {
	commit_en "$W" a.txt a "añade a"
	run g Integrar -Agente codex -Tarea t -Metodo Merge -ConfirmarIntegracion
	assert_success
	assert_output_contains "añade a"
	assert_output_contains "a.txt"
	assert_output_contains "ejecuta ahora las pruebas"
	[[ -f "$REPO/a.txt" ]]
	[[ "$(git rev-list --parents -n1 HEAD | wc -w)" == 3 ]]
	[[ -d "$W" ]]
	git show-ref --verify -q refs/heads/codex/t
}

@test "sin interacción exige -ConfirmarIntegracion y -Metodo" {
	commit_en "$W" a.txt a
	run g Integrar -Agente codex -Tarea t -Metodo Merge
	assert_failure
	assert_output_contains "-ConfirmarIntegracion"
	run g Integrar -Agente codex -Tarea t -ConfirmarIntegracion
	assert_failure
	assert_output_contains "falta -Metodo"
	run g Integrar -Metodo Merge -ConfirmarIntegracion
	assert_failure
	assert_output_contains "faltan -Agente y -Tarea"
	[[ ! -f "$REPO/a.txt" ]]
}

@test "con -Accion sigue preguntando si no hay -SinInteraccion" {
	commit_en "$W" a.txt a
	responder 'n\n' -Accion Integrar -Agente codex -Tarea t -Metodo Merge
	assert_success
	assert_output_contains "¿Hacer merge de codex/t en main? [s/N]"
	assert_output_contains "cancelado"
	[[ ! -f "$REPO/a.txt" ]]
	responder 's\n' -Accion Integrar -Agente codex -Tarea t -Metodo Merge
	assert_success
	[[ -f "$REPO/a.txt" ]]
}

@test "integración guiada: elegir worktree y método" {
	commit_en "$W" a.txt a
	responder '1\n1\ns\n' -Accion Integrar
	assert_success
	assert_output_contains "[2] CherryPick"
	[[ -f "$REPO/a.txt" ]]
}

@test "conflictos: no ejecuta el merge ni cambia HEAD" {
	commit_en "$W" README.md rama
	commit_en "$REPO" README.md main
	local antes
	antes="$(git rev-parse HEAD)"
	run g Integrar -Agente codex -Tarea t -Metodo Merge -ConfirmarIntegracion
	assert_failure
	assert_output_contains "tendría conflictos"
	assert_output_contains "README.md"
	[[ "$(git rev-parse HEAD)" == "$antes" ]]
	refute git rev-parse -q --verify MERGE_HEAD
	[[ -z "$(git status --porcelain)" ]]
}

@test "rechaza integrar con trabajo pendiente en el agente, con rutas y alternativas" {
	commit_en "$W" a.txt a
	echo x >"$W/pendiente.txt"
	run g Integrar -Agente codex -Tarea t -Metodo Merge -ConfirmarIntegracion
	assert_failure
	assert_output_contains "? pendiente.txt"
	assert_output_contains "solo se integra trabajo commiteado"
	[[ -f "$W/pendiente.txt" ]]
	[[ -z "$(git stash list)" ]]
}

@test "rechaza con el principal sucio, en otra rama o con una operación a medias" {
	commit_en "$W" a.txt a
	echo x >>"$REPO/README.md"
	run g Integrar -Agente codex -Tarea t -Metodo Merge -ConfirmarIntegracion
	assert_failure
	assert_output_contains "M README.md"
	git checkout -q README.md
	git switch -q -c otra
	run g Integrar -Agente codex -Tarea t -Metodo Merge -ConfirmarIntegracion
	assert_failure
	assert_output_contains "git -C \"$REPO\" switch main"
	[[ "$(git branch --show-current)" == otra ]]
	git switch -q main
	git rev-parse HEAD >"$(git rev-parse --git-path CHERRY_PICK_HEAD)"
	run g Integrar -Agente codex -Tarea t -Metodo Merge -ConfirmarIntegracion
	assert_failure
	assert_output_contains "CHERRY_PICK_HEAD"
}

@test "rechaza si la carpeta del agente no existe" {
	commit_en "$W" a.txt a
	rm -rf "$W"
	run g Integrar -Agente codex -Tarea t -Metodo Merge -ConfirmarIntegracion
	assert_failure
	assert_output_contains "falta la carpeta"
}

@test "rechaza si cambió la rama activa del agente" {
	commit_en "$W" a.txt a
	git -C "$W" switch -q -c otra-rama
	run g Integrar -Agente codex -Tarea t -Metodo Merge -ConfirmarIntegracion
	assert_failure
	assert_output_contains "tiene activa la rama otra-rama"
	assert_output_contains "switch codex/t"
}

@test "usa la base registrada aunque cambie la rama activa del principal" {
	git switch -q -c otra
	commit_en "$W" a.txt a
	run g Integrar -Agente codex -Tarea t -Metodo Merge -ConfirmarIntegracion
	assert_failure
	assert_output_contains "integración debe hacerse sobre main"
}

@test "cherry-pick: valida, aplica en el orden de la rama y conserva la rama" {
	commit_en "$W" a.txt a "commit a"
	commit_en "$W" b.txt b "commit b"
	commit_en "$W" c.txt c "commit c"
	local a c
	a="$(git rev-parse codex/t~2)"
	c="$(git rev-parse --short codex/t)"
	run g Integrar -Agente codex -Tarea t -Metodo CherryPick -Commits "$c, $a,$a" -ConfirmarIntegracion
	assert_success
	[[ -f "$REPO/a.txt" && -f "$REPO/c.txt" && ! -f "$REPO/b.txt" ]]
	[[ "$(git log -2 --format=%s | tr '\n' ' ')" == "commit c commit a " ]]
	git show-ref --verify -q refs/heads/codex/t
	[[ -d "$W" ]]
}

@test "cherry-pick: rechaza commits ajenos, merges y valores irreconocibles" {
	commit_en "$W" a.txt a
	commit_en "$REPO" m.txt m
	run g Integrar -Agente codex -Tarea t -Metodo CherryPick -Commits "$(git rev-parse main)" -ConfirmarIntegracion
	assert_failure
	assert_output_contains "no pertenece a main..codex/t"
	run g Integrar -Agente codex -Tarea t -Metodo CherryPick -Commits "zzz" -ConfirmarIntegracion
	assert_failure
	assert_output_contains "no se reconoce"
	git -C "$W" switch -q -c lado
	commit_en "$W" l.txt l
	git -C "$W" switch -q codex/t
	git -C "$W" merge -q --no-ff --no-edit lado
	run g Integrar -Agente codex -Tarea t -Metodo CherryPick -Commits "$(git rev-parse codex/t)" -ConfirmarIntegracion
	assert_failure
	assert_output_contains "es un merge"
	run g Integrar -Agente codex -Tarea t -Metodo CherryPick -ConfirmarIntegracion
	assert_failure
	assert_output_contains "faltan -Commits"
}

@test "cherry-pick guiado: lista numerada y números separados por coma" {
	commit_en "$W" a.txt a "commit a"
	commit_en "$W" b.txt b "commit b"
	responder '2,1\ns\n' -Accion Integrar -Agente codex -Tarea t -Metodo CherryPick
	assert_success
	assert_output_contains "[1] "
	assert_output_contains "commit a"
	[[ "$(git log -2 --format=%s | tr '\n' ' ')" == "commit b commit a " ]]
}

@test "cherry-pick con conflicto: aborta y HEAD vuelve" {
	commit_en "$W" README.md rama
	commit_en "$REPO" README.md main
	local antes
	antes="$(git rev-parse HEAD)"
	run g Integrar -Agente codex -Tarea t -Metodo CherryPick -Commits "$(git rev-parse codex/t)" -ConfirmarIntegracion
	assert_failure
	assert_output_contains "falló el cherry-pick"
	[[ "$(git rev-parse HEAD)" == "$antes" ]]
	refute git rev-parse -q --verify CHERRY_PICK_HEAD
}

@test "sin commits nuevos no hay nada que integrar" {
	run g Integrar -Agente codex -Tarea t -Metodo Merge -ConfirmarIntegracion
	assert_failure
	assert_output_contains "nada que integrar"
}
