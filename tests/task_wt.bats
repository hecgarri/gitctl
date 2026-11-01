#!/usr/bin/env bats
load test_helper

setup() { setup_repo; }

@test "task new crea la tarea fijando el SHA base" {
	run gitctl task new "Mi tarea"
	assert_success
	[[ "${lines[-1]}" == "t1" ]]
	[[ "$(jq -r .base_sha "$(state)/tasks/t1/task.json")" == "$(git rev-parse HEAD)" ]]
	[[ "$(cat "$(state)/tasks/t1/spec.md")" == "Mi tarea" ]]
	run gitctl task new "Otra"
	[[ "${lines[-1]}" == "t2" ]]
}

@test "task new --spec lee la especificación de un fichero o de stdin" {
	echo "Implementa X con tests" >spec.md
	gitctl task new "Con spec" --spec spec.md
	[[ "$(cat "$(state)/tasks/t1/spec.md")" == "Implementa X con tests" ]]
	echo "desde stdin" | gitctl task new "Stdin" --spec -
	[[ "$(cat "$(state)/tasks/t2/spec.md")" == "desde stdin" ]]
}

@test "task assign crea un worktree y una rama por agente" {
	gitctl task new "T"
	run gitctl task assign t1 fake-a fake-b
	assert_success
	[[ -d "$(wt_of t1 fake-a)" && -d "$(wt_of t1 fake-b)" ]]
	git show-ref --verify -q refs/heads/gitctl/t1/fake-a
	git show-ref --verify -q refs/heads/gitctl/t1/fake-b
	[[ "$(git -C "$(wt_of t1 fake-a)" rev-parse HEAD)" == "$(git rev-parse HEAD)" ]]
	run gitctl task show t1
	assert_output_contains "Agente fake-a"
	assert_output_contains "Agente fake-b"
}

@test "task assign rechaza agentes sin adaptador y nombres no válidos" {
	gitctl task new "T"
	run gitctl task assign t1 desconocido
	assert_failure
	assert_output_contains "no hay adaptador"
	run gitctl task assign t1 "Fake/../x"
	assert_failure
	assert_output_contains "no válido"
}

@test "reasignar el mismo agente no crea otro worktree" {
	gitctl task new "T"
	gitctl task assign t1 fake
	run gitctl task assign t1 fake
	assert_success
	assert_output_contains "ya está asignado"
	[[ "$(jq '.assignments | length' "$(state)/tasks/t1/task.json")" == 1 ]]
}

@test "task show --json es JSON válido con resumen" {
	gitctl task new "T"
	gitctl task assign t1 fake
	run gitctl task show t1 --json
	assert_success
	echo "$output" | jq -e '.summary[0].agent == "fake"'
}

@test "task close marca la tarea y no borra nada" {
	gitctl task new "T"
	gitctl task assign t1 fake
	gitctl task close t1
	[[ "$(jq -r .status "$(state)/tasks/t1/task.json")" == closed ]]
	[[ -d "$(wt_of t1 fake)" ]]
	run gitctl run t1
	assert_failure
	run gitctl task ls
	[[ "$output" != *"t1 "* ]]
	run gitctl task ls --all
	assert_output_contains "t1"
}

@test "wt ls muestra los worktrees y su tarea/agente" {
	gitctl task new "T"
	gitctl task assign t1 fake
	run gitctl wt ls
	assert_success
	assert_output_contains "t1/fake"
	assert_output_contains "gitctl/t1/fake"
}

@test "wt path resuelve tarea/agente" {
	gitctl task new "T"
	gitctl task assign t1 fake
	run gitctl wt path t1/fake
	assert_success
	[[ "$output" == "$(wt_of t1 fake)" ]]
}

@test "wt new crea un worktree libre fuera del repositorio" {
	run gitctl wt new experimento
	assert_success
	[[ -d "$TEST_TMP/repo.wt/experimento" ]]
	git show-ref --verify -q refs/heads/wt/experimento
}

@test "wt rm rechaza un worktree con cambios sin commitear" {
	gitctl task new "T"
	gitctl task assign t1 fake
	echo cambio >"$(wt_of t1 fake)/nuevo.txt"
	run gitctl wt rm t1/fake
	assert_failure
	assert_output_contains "sin commitear"
	[[ -f "$(wt_of t1 fake)/nuevo.txt" ]]
	# --force sin TTY ni --yes tampoco borra
	run gitctl wt rm t1/fake --force </dev/null
	assert_failure
	[[ -f "$(wt_of t1 fake)/nuevo.txt" ]]
}

@test "wt rm --force --yes elimina y conserva la rama" {
	gitctl task new "T"
	gitctl task assign t1 fake
	echo cambio >"$(wt_of t1 fake)/nuevo.txt"
	run gitctl --yes wt rm t1/fake --force
	assert_success
	[[ ! -d "$(wt_of t1 fake)" ]]
	git show-ref --verify -q refs/heads/gitctl/t1/fake
}

@test "wt rm --delete-branch no borra ramas sin fusionar" {
	task_with_runs fake
	run gitctl wt rm t1/fake --delete-branch
	assert_success
	git show-ref --verify -q refs/heads/gitctl/t1/fake
	assert_output_contains "no está fusionada"
}

@test "wt rm nunca elimina el worktree principal" {
	run gitctl wt rm "$REPO"
	assert_failure
	assert_output_contains "principal"
}

@test "los eventos quedan registrados en events.jsonl" {
	gitctl task new "T"
	gitctl task assign t1 fake
	jq -e 'select(.type == "task.created" and .task == "t1")' "$(state)/events.jsonl"
	jq -e 'select(.type == "task.assigned" and .agent == "fake")' "$(state)/events.jsonl"
	run gitctl log t1
	assert_output_contains "task.assigned"
}
