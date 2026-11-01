#!/usr/bin/env bats
load test_helper

setup() { setup_repo; }

@test "dos agentes en paralelo trabajan aislados en su rama" {
	gitctl task new "T"
	gitctl task assign t1 fake-a fake-b
	run gitctl run t1 --wait
	assert_success
	# Cada rama contiene solo el fichero de su agente.
	git cat-file -e gitctl/t1/fake-a:fake-a.txt
	git cat-file -e gitctl/t1/fake-b:fake-b.txt
	run git cat-file -e gitctl/t1/fake-a:fake-b.txt
	assert_failure
	run git cat-file -e gitctl/t1/fake-b:fake-a.txt
	assert_failure
	# La rama principal no se toca.
	run git cat-file -e main:fake-a.txt
	assert_failure
}

@test "los runs se ejecutan realmente en paralelo" {
	gitctl task new "T"
	gitctl task assign t1 fake-a fake-b fake-c
	local t0=$SECONDS
	GITCTL_FAKE_SLEEP=3 run gitctl run t1 --wait
	assert_success
	(( SECONDS - t0 < 8 ))
}

@test "el commit de huella lleva autor del agente y trailers Gitctl-*" {
	task_with_runs fake
	local r
	r="$(jq -r .id "$(state)"/runs/*/meta.json)"
	run git log -1 --format='%an%n%(trailers:only,unfold)' gitctl/t1/fake
	assert_output_contains "fake (vía gitctl)"
	assert_output_contains "Gitctl-Task: t1"
	assert_output_contains "Gitctl-Agent: fake"
	assert_output_contains "Gitctl-Run: $r"
	assert_output_contains "Gitctl-Exit: 0"
	# El resumen del agente se marca como afirmación.
	run git log -1 --format=%b gitctl/t1/fake
	assert_output_contains "afirmación, no verificada"
}

@test "run registra prompt, log, resultado y SHAs" {
	task_with_runs fake
	local d
	d="$(dirname "$(ls "$(state)"/runs/*/meta.json)")"
	[[ -s "$d/prompt.md" && -s "$d/output.log" && -s "$d/result.md" ]]
	grep -q "Tarea de prueba" "$d/prompt.md"
	jq -e '.status == "ok" and .exit == 0 and (.commits | length) == 1 and .sha_end != .sha_start' "$d/meta.json"
}

@test "si el agente ya commitea, no se crea un commit extra" {
	gitctl task new "T"
	gitctl task assign t1 fake
	GITCTL_FAKE_IMPL='echo x > a.txt && git add a.txt && git commit -q -m "commit del agente"' \
		gitctl run t1 --wait
	[[ "$(git log -1 --format=%s gitctl/t1/fake)" == "commit del agente" ]]
	jq -e '(.commits | length) == 1' "$(state)"/runs/*/meta.json
}

@test "un agente que falla queda como fallido pero deja huella" {
	gitctl task new "T"
	gitctl task assign t1 fake
	GITCTL_FAKE_EXIT=3 run gitctl run t1 --wait
	assert_failure
	assert_output_contains "fallido"
	jq -e '.status == "fallido" and .exit == 3' "$(state)"/runs/*/meta.json
	git log -1 --format='%(trailers:only)' gitctl/t1/fake | grep -q "Gitctl-Exit: 3"
}

@test "el límite de tiempo detiene al agente" {
	gitctl task new "T"
	gitctl task assign t1 fake
	GITCTL_FAKE_SLEEP=30 run gitctl run t1 --timeout 1s --wait
	assert_failure
	assert_output_contains "timeout"
}

@test "no se permiten dos runs simultáneos en el mismo worktree" {
	gitctl task new "T"
	gitctl task assign t1 fake
	GITCTL_FAKE_SLEEP=5 gitctl run t1
	run gitctl run t1
	assert_failure
	assert_output_contains "run en curso"
	gitctl run wait t1
}

@test "run stop detiene un agente en curso" {
	gitctl task new "T"
	gitctl task assign t1 fake
	GITCTL_FAKE_SLEEP=60 gitctl run t1
	sleep 1
	run gitctl --yes run stop t1/fake
	assert_success
	run gitctl run wait t1
	assert_failure
	assert_output_contains "detenido"
}

@test "si el agente cambia de rama no se commitea en otra rama" {
	gitctl task new "T"
	gitctl task assign t1 fake
	GITCTL_FAKE_IMPL='git switch -q -c otra && echo x > b.txt' run gitctl run t1 --wait
	assert_output_contains "cambió de rama"
	[[ "$(git rev-parse gitctl/t1/fake)" == "$(git rev-parse main)" ]]
}

@test "se detecta historial reescrito" {
	gitctl task new "T"
	gitctl task assign t1 fake
	gitctl run t1 --wait
	GITCTL_FAKE_IMPL='git reset -q --hard HEAD~1' run gitctl run t1 --wait
	assert_output_contains "historial reescrito"
}

@test "run status y run logs muestran la información" {
	task_with_runs fake
	run gitctl run status t1
	assert_success
	assert_output_contains "fake"
	assert_output_contains "ok"
	run gitctl run logs t1/fake
	assert_success
	assert_output_contains "Hecho por fake"
	run gitctl run show t1/fake
	assert_output_contains "mensaje final del agente"
}

@test "el prompt entrega la especificación y las reglas de aislamiento" {
	echo "Requisito secreto 42" >spec.md
	gitctl task new "T" --spec spec.md
	gitctl task assign t1 fake
	gitctl run t1 --wait
	local p
	p="$(ls "$(state)"/runs/*/prompt.md)"
	grep -q "Requisito secreto 42" "$p"
	grep -q "EXCLUSIVAMENTE" "$p"
	grep -q "$(wt_of t1 fake)" "$p"
}

@test "el agente recibe variables GITCTL_* de su run" {
	gitctl task new "T"
	gitctl task assign t1 fake
	GITCTL_FAKE_IMPL='echo "$GITCTL_TASK/$GITCTL_AGENT/$GITCTL_RUN_ID" > env.txt' gitctl run t1 --wait
	git show gitctl/t1/fake:env.txt | grep -q "^t1/fake/r"
}
