#!/usr/bin/env bats
load test_helper

setup() {
	setup_repo
	crear claude t
	crear codex t
	commit_en "$(wt claude t)" a.txt a
	commit_en "$(wt codex t)" b.txt b
	mkdir -p "$REPO/docs"
	printf 'Criterio: crear a.txt\n' >"$REPO/docs/criterios.md"
	: >"$REPO/docs/vacio.md"
	git add docs && git commit -q -m docs
}

# Evaluación interactiva que se cancela al llegar a la confirmación del envío.
evaluar_guiado() { responder "$1" -Accion Evaluar -Ramas "claude/t,codex/t" -ProveedorLlm Codex "${@:2}"; }

@test "sin interacción -CriteriosRevision es obligatorio" {
	run g Evaluar -Ramas "claude/t,codex/t" -ProveedorLlm Codex -ConfirmarEnvioLlm
	assert_failure
	assert_output_contains "falta -CriteriosRevision"
}

@test "rutas relativas a la raíz del repo, aunque se invoque desde una subcarpeta" {
	cd "$REPO/src"
	evaluar_guiado 'n\n' -CriteriosRevision docs/criterios.md
	assert_success
	assert_output_contains "Criterios:       $REPO/docs/criterios.md"
}

@test "archivo inexistente o vacío se rechaza" {
	run g Evaluar -Ramas "claude/t,codex/t" -ProveedorLlm Codex -ConfirmarEnvioLlm -CriteriosRevision docs/nada.md
	assert_failure
	assert_output_contains "no existe"
	run g Evaluar -Ramas "claude/t,codex/t" -ProveedorLlm Codex -ConfirmarEnvioLlm -CriteriosRevision docs/vacio.md
	assert_failure
	assert_output_contains "vacío"
}

@test "guiado: explica, corrige rutas inválidas o vacías y admite comillas" {
	evaluar_guiado '1\nno/existe.md\ndocs/vacio.md\n"docs/criterios.md"\nn\n'
	assert_success
	assert_output_contains "objetivo, requisitos obligatorios"
	assert_output_contains "no existe el archivo"
	assert_output_contains "el archivo está vacío"
	assert_output_contains "Criterios:       $REPO/docs/criterios.md"
}

@test "guiado: 0 vuelve a la elección del método y 0 ahí cancela" {
	evaluar_guiado '1\n0\n0\n'
	assert_success
	[[ "$(grep -c '¿Cómo quieres aportar los criterios?' <<<"$output")" == 2 ]]
	assert_output_contains "cancelado"
}

@test "redacción multilínea en UTF-8, guardada fuera del repo" {
	evaluar_guiado '2\n.fin\nObjetivo: añadir ñandú\n- Requisito: pruebas en verde\n.fin\nn\n'
	assert_success
	assert_output_contains "no tienen contenido todavía"
	local f
	f="$(ls "$RAIZ"/_criterios/*.md)"
	[[ "$(basename "$f")" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f-]{36}\.md$ ]]
	[[ "$(cat "$f")" == "$(printf 'Objetivo: añadir ñandú\n- Requisito: pruebas en verde')" ]]
	[[ "$(head -c3 "$f" | od -An -tx1 | tr -d ' ')" != efbbbf ]]
	[[ -z "$(git status --porcelain)" ]]
	assert_output_contains "criterios guardados en $RAIZ/_criterios/"
}

@test "redacción: .cancelar descarta el borrador y cancela" {
	evaluar_guiado '2\nalgo\n.cancelar\n'
	assert_success
	assert_output_contains "borrador descartado"
	assert_output_contains "cancelado"
	[[ ! -e "$RAIZ/_criterios" ]] || [[ -z "$(ls -A "$RAIZ/_criterios")" ]]
}

@test "orden guiado: criterios, ramas, proveedor y confirmación" {
	responder '1\ndocs/criterios.md\n1\n2\n1\nn\n' -Accion Evaluar
	assert_success
	local o="$output"
	local c r p e
	c="${o%%¿Cómo quieres aportar*}"
	r="${o%%Elige la primera propuesta*}"
	p="${o%%¿Qué LLM quieres consultar?*}"
	e="${o%%se enviará a un proveedor externo*}"
	((${#c} < ${#r} && ${#r} < ${#p} && ${#p} < ${#e}))
}
