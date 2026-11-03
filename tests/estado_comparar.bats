#!/usr/bin/env bats
load test_helper

setup() {
	setup_repo
	crear claude t
	crear codex t
}

@test "estado sin worktrees lo dice claramente" {
	git worktree list --porcelain >/dev/null
	run g Estado -RaizWorktrees "$TEST_TMP/vacia"
	assert_success
	assert_output_contains "no hay worktrees administrados"
}

@test "estado: tabla con columnas, pendiente y estado de integración" {
	commit_en "$(wt claude t)" a.txt a
	echo m >>"$(wt codex t)/README.md"
	echo m >>"$(wt codex t)/src/app.txt"
	rm "$(wt codex t)/src/app.txt"
	echo x >"$(wt codex t)/nuevo con espacios.txt"
	echo y >"$(wt codex t)/ñandú.txt"
	run g Estado
	assert_success
	assert_output_contains "Agent"
	assert_output_contains "Integration"
	assert_output_contains "Missing"
	assert_output_contains "1 modificados, 1 eliminados, 2 sin seguimiento"
	[[ "$(grep '^claude' <<<"$output")" == *Pendiente* ]]
	[[ "$(grep '^codex' <<<"$output")" == *Fusionada* ]]
}

@test "estado: los worktrees fuera de agente/tarea no se administran" {
	git worktree add -q "$RAIZ/suelto" -b suelto
	git worktree add -q "$TEST_TMP/fuera" -b fuera
	run g Estado
	assert_success
	refute_output_contains "suelto"
	refute_output_contains "fuera"
}

@test "estado: ordenado por agente y tarea" {
	crear alfa z
	crear alfa b
	run g Estado
	local orden
	orden="$(awk 'NR>1 {print $1"/"$2}' <<<"$output" | tr '\n' ' ')"
	[[ "$orden" == "alfa/b alfa/z claude/t codex/t " ]]
}

@test "estado: EquivalentePorCherryPick y BaseInexistente y SinRama" {
	commit_en "$(wt claude t)" a.txt a
	commit_en "$REPO" m.txt m
	git cherry-pick claude/t >/dev/null
	run g Estado
	[[ "$(grep '^claude' <<<"$output")" == *EquivalentePorCherryPick* ]]
	run g Estado -Base main
	assert_success
	git -C "$(wt codex t)" switch -q --detach
	run g Estado
	[[ "$(grep '^codex' <<<"$output")" == *SinRama* ]]
	[[ "$(grep '^codex' <<<"$output")" == *"(detached)"* ]]
	git branch temporal
	g Crear -Agente beta -Tarea t -Base temporal >/dev/null 2>&1
	git branch -D -q temporal
	run g Estado
	[[ "$(grep '^beta' <<<"$output")" == *BaseInexistente* ]]
}

@test "estado: con un merge exclusivo no declara equivalencia por cherry-pick" {
	local w
	w="$(wt claude t)"
	git -C "$w" switch -q -c lado
	commit_en "$w" l.txt l
	git -C "$w" switch -q claude/t
	git -C "$w" merge -q --no-ff --no-edit lado
	git cherry-pick lado >/dev/null
	run g Estado
	[[ "$(grep '^claude' <<<"$output")" == *" Pendiente "* ]]
}

@test "estado: la base registrada se usa aunque cambie la rama activa del principal" {
	git switch -q -c otra
	commit_en "$REPO" o.txt o
	run g Estado
	[[ "$(grep '^claude' <<<"$output")" == *" main "* ]]
	run g Estado -Base otra
	[[ "$(grep '^claude' <<<"$output")" == *" otra "* ]]
}

@test "estado: carpeta que falta se marca y se avisa" {
	rm -rf "$(wt codex t)"
	run g Estado
	assert_success
	assert_output_contains "(sin carpeta)"
	assert_output_contains "Eliminar permite limpiar su registro"
	[[ "$(grep '^codex' <<<"$output")" == *" sí "* ]]
}

@test "comparar: commits exclusivos y --stat, sin tocar referencias" {
	commit_en "$(wt claude t)" a.txt claude "solo claude"
	commit_en "$(wt codex t)" b.txt codex "solo codex"
	local antes
	antes="$(refs)"
	run g Comparar -Ramas "claude/t,codex/t"
	assert_success
	assert_output_contains "solo claude"
	assert_output_contains "solo codex"
	assert_output_contains "2 files changed"
	[[ "$(refs)" == "$antes" ]]
	run g Comparar -Ramas "claude/t,codex/t" -MostrarDiffCompleto
	assert_output_contains "-claude"
	assert_output_contains "+codex"
}

@test "comparar: sin diferencias lo dice, y avisa del trabajo pendiente" {
	echo pendiente >"$(wt codex t)/p.txt"
	run g Comparar -Ramas "claude/t,codex/t"
	assert_success
	assert_output_contains "(ninguno)"
	assert_output_contains "(sin diferencias entre commits)"
	assert_output_contains "? p.txt"
	assert_output_contains "quedan fuera de la comparación"
	[[ "$(cat "$(wt codex t)/p.txt")" == pendiente ]]
	[[ -n "$(git -C "$(wt codex t)" status --porcelain)" ]]
}

@test "comparar: carpeta ausente avisa" {
	rm -rf "$(wt codex t)"
	run g Comparar -Ramas "claude/t,codex/t"
	assert_success
	assert_output_contains "no se puede revisar su trabajo pendiente"
}

@test "comparar: ramas iguales, inexistentes o sin -Ramas" {
	run g Comparar -Ramas "claude/t,claude/t"
	assert_failure
	run g Comparar -Ramas "claude/t,nada"
	assert_failure
	assert_output_contains "no existe como rama local"
	run g Comparar
	assert_failure
	assert_output_contains "-Ramas"
}

@test "comparar guiado: misma numeración, reintento con la misma y diff completo" {
	commit_en "$(wt codex t)" b.txt codex
	responder '1\n1\n2\ns\n' -Accion Comparar
	assert_success
	assert_output_contains "primera propuesta: claude/t"
	assert_output_contains "esa ya es la primera propuesta"
	[[ "$(grep -c '\[2\] codex/t' <<<"$output")" == 3 ]]
	assert_output_contains "+codex"
}

@test "comparar guiado: cancelar en cualquiera de las dos selecciones" {
	local antes
	antes="$(refs)"
	responder '0\n' -Accion Comparar
	assert_success
	assert_output_contains "cancelado"
	responder '1\n0\n' -Accion Comparar
	assert_success
	assert_output_contains "cancelado"
	[[ "$(refs)" == "$antes" ]]
}

@test "comparar guiado: necesita al menos dos worktrees" {
	run bash -c 'printf "1\n" | gitctl -Accion Comparar -RaizWorktrees "$1"' _ "$TEST_TMP/vacia"
	assert_success
	assert_output_contains "al menos dos worktrees"
}

@test "entradas inválidas repiten la pregunta" {
	responder 'x\n9\n1\n2\n\n' -Accion Comparar
	assert_success
	assert_output_contains "opción no válida: «x»"
	assert_output_contains "opción no válida: «9»"
}
