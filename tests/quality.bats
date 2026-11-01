#!/usr/bin/env bats
load test_helper

setup() {
	setup_repo
	add_check tiene_fichero 'test -f fake-a.txt'
}

full_ok() { # verifica, revisa (approve) y aprueba fake-a
	gitctl verify t1 fake-a
	gitctl review t1 fake-a --by fake-b
	gitctl approve t1 fake-a --yes
}

@test "verify sin checks se niega: sin checks no hay evidencia" {
	: >.gitctl.conf
	task_with_runs fake-a
	run gitctl verify t1 fake-a
	assert_failure
	assert_output_contains "no hay checks"
}

@test "verify registra evidencia ligada al SHA" {
	task_with_runs fake-a
	run gitctl verify t1 fake-a
	assert_success
	local sha
	sha="$(git rev-parse gitctl/t1/fake-a)"
	jq -e '.result == "pass" and .kind == "evidence" and .checks[0].exit == 0 and (.checks[0].log_sha256 | length) == 64' \
		"$(state)/verifications/$sha.json"
	[[ -f "$(state)/verifications/$sha/tiene_fichero.log" ]]
}

@test "verify falla si un check falla y guarda el log" {
	add_check falla 'echo "error visible"; exit 7'
	task_with_runs fake-a
	run gitctl verify t1 fake-a
	assert_failure
	local sha
	sha="$(git rev-parse gitctl/t1/fake-a)"
	jq -e '.result == "fail" and (.checks[] | select(.name == "falla") | .exit) == 7' "$(state)/verifications/$sha.json"
	grep -q "error visible" "$(state)/verifications/$sha/falla.log"
}

@test "verify usa una copia limpia: los cambios sin commitear no cuentan" {
	add_check sin_commitear 'test -f extra.txt'
	task_with_runs fake-a
	echo x >"$(wt_of t1 fake-a)/extra.txt"
	run gitctl verify t1 fake-a
	assert_failure
	assert_output_contains "sin commitear"
	# Y no deja worktrees temporales.
	[[ -z "$(ls -A "$(state)/tmp")" ]]
}

@test "los checks se leen del worktree principal, no de la rama del agente" {
	gitctl task new "T"
	gitctl task assign t1 fake-a
	GITCTL_FAKE_IMPL='echo "check.tiene_fichero = true" > .gitctl.conf' gitctl run t1 --wait
	run gitctl verify t1 fake-a
	assert_failure
}

@test "review cruzada registra el veredicto como afirmación" {
	task_with_runs fake-a fake-b
	run gitctl review t1 fake-a --by fake-b
	assert_success
	local sha
	sha="$(git rev-parse gitctl/t1/fake-a)"
	jq -e '.verdict == "approve" and .kind == "claim" and .author == "fake-a"' "$(state)/reviews/$sha/fake-b.json"
	grep -q "No se ha ejecutado ninguna verificación" "$(state)/reviews/$sha/fake-b.prompt.md"
}

@test "el revisor recibe la evidencia medida y el diff" {
	task_with_runs fake-a fake-b
	gitctl verify t1 fake-a
	gitctl review t1 fake-a --by fake-b
	local p
	p="$(state)/reviews/$(git rev-parse gitctl/t1/fake-a)/fake-b.prompt.md"
	grep -q "Resultado global: pass" "$p"
	grep -q "+++ b/fake-a.txt" "$p"
}

@test "un agente no puede revisarse a sí mismo" {
	task_with_runs fake-a
	run gitctl review t1 fake-a --by fake-a
	assert_failure
	assert_output_contains "propio trabajo"
}

@test "review.require_different_adapter exige otro adaptador" {
	set_cfg review.require_different_adapter true
	task_with_runs fake-a
	run gitctl review t1 fake-a --by fake-b
	assert_failure
	assert_output_contains "mismo adaptador"
}

@test "una respuesta sin JSON válido es una revisión inválida" {
	task_with_runs fake-a
	GITCTL_FAKE_VERDICT=garbage run gitctl review t1 fake-a --by fake-b
	assert_failure
	jq -e '.verdict == "invalid"' "$(state)/reviews/$(git rev-parse gitctl/t1/fake-a)/fake-b.json"
}

@test "un revisor que modifica ficheros invalida su revisión" {
	task_with_runs fake-a
	mkdir -p "$XDG_CONFIG_HOME/gitctl/adapters"
	cat >"$XDG_CONFIG_HOME/gitctl/adapters/evil.sh" <<'A'
adapter_evil_available() { return 0; }
adapter_evil_run() { echo hack >"$3/hack.txt"; printf '```json\n{"verdict":"approve","findings":[]}\n```\n' >"$6"; }
A
	run gitctl review t1 fake-a --by evil
	assert_failure
	jq -e '.verdict == "invalid"' "$(state)/reviews/$(git rev-parse gitctl/t1/fake-a)/evil.json"
}

@test "la puerta pasa con evidencia, revisión ajena y aprobación humana" {
	task_with_runs fake-a fake-b
	full_ok
	run gitctl gate t1 fake-a
	assert_success
	assert_output_contains "puede integrarse"
	run gitctl gate t1 fake-a --json
	echo "$output" | jq -e '.pass == true'
}

@test "la puerta no pasa sin verificación, revisión o aprobación" {
	task_with_runs fake-a fake-b
	run gitctl gate t1 fake-a
	assert_failure
	assert_output_contains "sin verificar"
	assert_output_contains "0/1"
	assert_output_contains "falta aprobación"
}

@test "request_changes bloquea la puerta y fix entrega los hallazgos al autor" {
	task_with_runs fake-a fake-b
	gitctl verify t1 fake-a
	GITCTL_FAKE_VERDICT=request_changes gitctl review t1 fake-a --by fake-b
	run gitctl gate t1 fake-a
	assert_failure
	assert_output_contains "cambios solicitados por: fake-b"
	run gitctl fix t1 fake-a --wait
	assert_success
	local r
	r="$(gitctl run status t1 | awk '$3 == "fake-a" {print $1}' | tail -1)"
	grep -q "falta un test" "$(state)/runs/$r/prompt.md"
	grep -q "Correcciones solicitadas" "$(state)/runs/$r/prompt.md"
}

@test "fix sin hallazgos no relanza nada" {
	task_with_runs fake-a
	run gitctl fix t1 fake-a
	assert_failure
	assert_output_contains "nada que corregir"
}

@test "fix entrega la salida de los checks fallidos" {
	add_check roto 'echo "AssertionError: esperado 2"; exit 1'
	task_with_runs fake-a
	gitctl verify t1 fake-a || true
	gitctl fix t1 fake-a --wait
	local r
	r="$(gitctl run status t1 | awk '$3 == "fake-a" {print $1}' | tail -1)"
	grep -q "AssertionError: esperado 2" "$(state)/runs/$r/prompt.md"
}

@test "un commit nuevo invalida evidencia, revisión y aprobación anteriores" {
	task_with_runs fake-a fake-b
	full_ok
	gitctl gate t1 fake-a
	gitctl run t1 fake-a --wait
	run gitctl gate t1 fake-a
	assert_failure
	assert_output_contains "sin verificar"
	assert_output_contains "falta aprobación"
}

@test "si cambian los checks, la evidencia caduca" {
	task_with_runs fake-a fake-b
	full_ok
	add_check otro 'true'
	run gitctl gate t1 fake-a
	assert_failure
	assert_output_contains "los checks cambiaron"
}

@test "approve exige confirmación interactiva o --yes explícito" {
	task_with_runs fake-a
	run gitctl approve t1 fake-a </dev/null
	assert_failure
	assert_output_contains "interactiva"
	# El --yes global no sirve para aprobar.
	run gitctl --yes approve t1 fake-a </dev/null
	assert_failure
}

@test "approve se rechaza dentro de un run de agente" {
	task_with_runs fake-a
	GITCTL_RUN_ID=r-falso run gitctl approve t1 fake-a --yes
	assert_failure
	assert_output_contains "persona"
}

@test "la puerta detecta conflictos con la rama base" {
	gitctl task new "T"
	gitctl task assign t1 fake-a fake-b
	GITCTL_FAKE_IMPL='echo agente > README.md; echo x > fake-a.txt' gitctl run t1 fake-a --wait
	echo "humano" >README.md
	git commit -qam "cambio en main"
	full_ok
	run gitctl gate t1 fake-a
	assert_failure
	assert_output_contains "conflictos con main en: README.md"
	assert_output_contains "avanzó"
}

@test "la puerta avisa si se modifican ficheros protegidos" {
	gitctl task new "T"
	gitctl task assign t1 fake-a fake-b
	GITCTL_FAKE_IMPL='mkdir -p .github/workflows; echo x > .github/workflows/ci.yml; echo x > fake-a.txt' \
		gitctl run t1 fake-a --wait
	full_ok
	run gitctl gate t1 fake-a
	assert_output_contains "ficheros protegidos: .github/workflows/ci.yml"
}

@test "gate.require_approval = false no exige aprobación humana" {
	set_cfg gate.require_approval false
	task_with_runs fake-a fake-b
	gitctl verify t1 fake-a
	gitctl review t1 fake-a --by fake-b
	run gitctl gate t1 fake-a
	assert_success
}
