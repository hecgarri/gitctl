#!/usr/bin/env bats
load test_helper

setup() { setup_repo; }

@test "crea rama, carpeta y bloqueo con los metadatos de la base" {
	run g Crear -Agente codex -Tarea corregir-api
	assert_success
	assert_output_contains "Abre el agente en: $(wt codex corregir-api)"
	assert_output_contains "Rama asignada:     codex/corregir-api"
	[[ -d "$(wt codex corregir-api)" ]]
	[[ "$(git -C "$(wt codex corregir-api)" branch --show-current)" == codex/corregir-api ]]
	local sha
	sha="$(git rev-parse main)"
	git worktree list --porcelain | grep -qxF "locked Agente=codex; Tarea=corregir-api; Base=main@$sha"
}

@test "normaliza agente y tarea" {
	run g Crear -Agente " Claude " -Tarea "Mejorar_Las  Pruebas"
	assert_success
	[[ -d "$(wt claude mejorar-las-pruebas)" ]]
	git show-ref --verify -q refs/heads/claude/mejorar-las-pruebas
}

@test "acepta agentes distintos de los tres sugeridos" {
	run g Crear -Agente mi-agente.2 -Tarea t
	assert_success
	[[ -d "$(wt mi-agente.2 t)" ]]
}

@test "rechaza nombres inseguros" {
	local n
	for n in ".." "." "a/b" "../x" "x.lock" "-x" "á" 'a\b' "a..b" ""; do
		run g Crear -Agente "$n" -Tarea t
		assert_failure
	done
	[[ ! -e "$RAIZ" ]] || [[ -z "$(ls -A "$RAIZ")" ]]
}

@test "rechaza una rama ya existente o una ruta ya existente" {
	git branch codex/t
	run g Crear -Agente codex -Tarea t
	assert_failure
	assert_output_contains "ya existe"
	mkdir -p "$(wt claude t)"
	run g Crear -Agente claude -Tarea t
	assert_failure
	assert_output_contains "ya existe"
	refute git show-ref --verify -q refs/heads/claude/t
}

@test "se puede invocar desde una subcarpeta del principal" {
	cd "$REPO/src"
	run g Crear -Agente codex -Tarea t
	assert_success
	[[ -d "$(wt codex t)" ]]
	run gitctl -Accion Estado -SinInteraccion -Repositorio "$REPO/src"
	assert_success
	assert_output_contains "codex"
}

@test "se rechaza desde un worktree secundario" {
	crear codex t
	cd "$(wt codex t)"
	run g Estado
	assert_failure
	assert_output_contains "worktree secundario"
	run gitctl -Accion Estado -SinInteraccion -Repositorio "$(wt codex t)"
	assert_failure
}

@test "-Repositorio inexistente o que no es un directorio" {
	run gitctl -Accion Estado -SinInteraccion -Repositorio "$TEST_TMP/nada"
	assert_failure
	assert_output_contains "no existe"
	: >"$TEST_TMP/archivo"
	run gitctl -Accion Estado -SinInteraccion -Repositorio "$TEST_TMP/archivo"
	assert_failure
	assert_output_contains "no es un directorio"
}

@test "la base por defecto es la rama activa (no se asume main)" {
	git switch -q -c desarrollo
	commit_en "$REPO" d.txt d
	run g Crear -Agente codex -Tarea t
	assert_success
	assert_output_contains "Base:   desarrollo @ $(git rev-parse desarrollo)"
	git switch -q -c master
	run g Crear -Agente codex -Tarea u
	assert_output_contains "Base:   master"
}

@test "-Base debe ser una rama local: no SHA, etiqueta ni rama remota" {
	git tag v1
	git update-ref refs/remotes/origin/remota HEAD
	local b
	for b in "$(git rev-parse HEAD)" v1 origin/remota remota; do
		run g Crear -Agente codex -Tarea t -Base "$b"
		assert_failure
		assert_output_contains "no existe como rama local"
	done
	git branch otra
	run g Crear -Agente codex -Tarea t -Base otra
	assert_success
}

@test "con el principal en detached HEAD y sin -Base se detiene" {
	git switch -q --detach
	run g Crear -Agente codex -Tarea t
	assert_failure
	assert_output_contains "detached HEAD"
	run g Crear -Agente codex -Tarea t -Base main
	assert_success
}

@test "la raíz no puede ser el repo, estar dentro ni contenerlo" {
	run g Estado -RaizWorktrees "$REPO"
	assert_failure
	run g Estado -RaizWorktrees "$REPO/agentes"
	assert_failure
	assert_output_contains "dentro del repositorio"
	run g Estado -RaizWorktrees "$TEST_TMP"
	assert_failure
	assert_output_contains "contener al repositorio"
	run g Estado -RaizWorktrees "${REPO}x"
	assert_success
}

@test "-RaizWorktrees relativa se resuelve a absoluta" {
	run g Crear -Agente codex -Tarea t -RaizWorktrees ../otros
	assert_success
	[[ -d "$TEST_TMP/otros/codex/t" ]]
}

@test "creación guiada: elegir agente, escribir tarea y confirmar" {
	responder '2\nmi tarea\ns\n' -Accion Crear
	assert_success
	assert_output_contains "[1] Claude"
	assert_output_contains "[0] Cancelar"
	[[ -d "$(wt codex mi-tarea)" ]]
}

@test "creación guiada: cancelar en el agente o al confirmar no crea nada" {
	responder '0\n' -Accion Crear
	assert_success
	assert_output_contains "cancelado"
	responder '1\nt\n\n' -Accion Crear
	assert_success
	assert_output_contains "cancelado"
	[[ ! -e "$(wt claude t)" ]]
	refute git show-ref --verify -q refs/heads/claude/t
}

@test "sin interacción falta agente o tarea" {
	run g Crear -Tarea t
	assert_failure
	assert_output_contains "falta -Agente"
	run g Crear -Agente codex
	assert_failure
	assert_output_contains "falta -Tarea"
}

@test "si falla el bloqueo se revierte la creación" {
	mkdir -p "$TEST_TMP/falso"
	cat >"$TEST_TMP/falso/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do [[ "\$a" == lock ]] && { echo "fallo simulado" >&2; exit 1; }; done
exec $(command -v git) "\$@"
EOF
	chmod +x "$TEST_TMP/falso/git"
	PATH="$TEST_TMP/falso:$PATH" run g Crear -Agente codex -Tarea t
	assert_failure
	assert_output_contains "se ha revertido"
	[[ ! -e "$(wt codex t)" ]]
	[[ ! -e "$RAIZ" ]]
	refute git show-ref --verify -q refs/heads/codex/t
	[[ "$(git worktree list | wc -l)" == 1 ]]
}

@test "si falla la creación no borra lo que ya existía" {
	mkdir -p "$RAIZ/codex"
	echo dato >"$RAIZ/codex/nota.txt"
	git branch codex/x
	run g Crear -Agente codex -Tarea x
	assert_failure
	[[ -f "$RAIZ/codex/nota.txt" ]]
	git show-ref --verify -q refs/heads/codex/x
}
