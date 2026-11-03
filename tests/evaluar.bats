#!/usr/bin/env bats
load test_helper

# CLIs falsas de los proveedores. Se controlan con variables de entorno:
#   FALSO_MODO_<PROV>  ok (por defecto) | falla | basura | lento | colgado | incompleto
#   FALSO_LOG          archivo donde cada CLI anota sus argumentos
setup() {
	setup_repo
	crear claude t
	crear codex t
	commit_en "$(wt claude t)" a.txt "versión claude" "claude: a"
	commit_en "$(wt codex t)" a.txt "versión codex" "codex: a"
	mkdir -p "$REPO/docs"
	printf '# Criterios\n- Debe crear a.txt\n' >"$REPO/docs/criterios.md"
	git add docs && git commit -q -m "criterios"
	export FALSO_LOG="$TEST_TMP/falso.log" FALSO_DIR="$TEST_TMP/falsos"
	mkdir -p "$FALSO_DIR"
	local p
	for p in codex claude gemini; do
		cat >"$FALSO_DIR/$p" <<'SH'
#!/usr/bin/env bash
prov="$(basename "$0")"
if [[ "$1" == --version ]]; then echo "$prov 9.9.9"; exit 0; fi
printf '%s %s\n' "$prov" "$*" >>"$FALSO_LOG"
echo "$prov" >>"$FALSO_LOG.orden"
cat >"$FALSO_DIR/$prov.stdin"
pwd >"$FALSO_DIR/$prov.pwd"
modo_var="FALSO_MODO_${prov^^}"
modo="${!modo_var:-ok}"
dict='{"recomendacion":"integrar_primera","confianza":"media","resumen":"La primera cumple","contradicciones":[],"commits_recomendados":["abc"],"orden_integracion":[],"pruebas_requeridas":["make test"],"advertencias":[]}'
echo "progreso en stderr" >&2
case "$modo" in
falla) echo "error del proveedor" >&2; exit 3 ;;
basura) echo "esto no es json"; exit 0 ;;
incompleto) dict='{"recomendacion":"combinar"}' ;;
lento) sleep 6 ;;
colgado)
	sleep 300 &
	echo $! >"$FALSO_DIR/nieto.pid"
	sleep 300
	;;
esac
case "$prov" in
codex)
	while (($#)); do [[ "$1" == --output-last-message ]] && out="$2"; shift; done
	printf '%s\n' "$dict" >"$out"
	echo "ruido en stdout de codex"
	;;
claude) printf '{"type":"result","result":"texto","structured_output":%s}\n' "$dict" ;;
gemini) jq -n --arg r "$(printf '```json\n%s\n```' "$dict")" '{response: $r, stats: {}}' ;;
esac
SH
		chmod +x "$FALSO_DIR/$p"
	done
	export PATH="$FALSO_DIR:$PATH"
}

ev() { g Evaluar -Ramas "claude/t,codex/t" -CriteriosRevision docs/criterios.md "$@"; }

@test "Todos: Codex, Claude y Gemini en orden, con dictámenes guardados" {
	local antes
	antes="$(refs)"
	run ev -ProveedorLlm Todos -ConfirmarEnvioLlm
	assert_success
	[[ "$(tr '\n' ' ' <"$FALSO_LOG.orden")" == "codex claude gemini " ]]
	assert_output_contains "Recomendación: integrar_primera"
	assert_output_contains "Contradicciones:"
	assert_output_contains "(ninguno)"
	assert_output_contains "  - make test"
	assert_output_contains "el dictamen es consultivo"
	[[ "$(ls "$RAIZ/_dictamenes" | wc -l)" == 3 ]]
	local f
	f="$(ls "$RAIZ/_dictamenes"/*-gemini-claude-t-codex-t.json)"
	jq -e '.format_version == 2 and .provider == "gemini" and .cli_version == "gemini 9.9.9"
		and .model_requested == null and .base_branch == "main" and .first_branch == "claude/t"
		and .second_sha != null and (.prompt_sha256 | length) == 64
		and .judgment.recomendacion == "integrar_primera"' "$f"
	[[ "$(tail -c1 "$f" | od -An -c | tr -d ' ')" == '\n' ]]
	[[ "$(refs)" == "$antes" ]]
}

@test "invocaciones de los adaptadores y directorio de trabajo temporal" {
	run ev -ProveedorLlm Todos -ConfirmarEnvioLlm -ModeloClaude opus
	assert_success
	grep -q -- "^codex exec --ephemeral --ignore-user-config --skip-git-repo-check --sandbox read-only --color never --output-schema .*esquema.json --output-last-message .*respuesta.txt -$" "$FALSO_LOG"
	grep -q -- "^claude --print --safe-mode --restricted --tools  --permission-mode plan --no-session-persistence --output-format json --json-schema {" "$FALSO_LOG"
	grep -q -- "--model opus$" "$FALSO_LOG"
	grep -q -- "^gemini --output-format json --approval-mode default$" "$FALSO_LOG"
	grep -q '"additionalProperties": false' "$FALSO_DIR/gemini.stdin"
	refute grep -q '"additionalProperties"' "$FALSO_DIR/codex.stdin"
	local d
	d="$(cat "$FALSO_DIR/codex.pwd")"
	[[ "$d" == "$(realpath "${TMPDIR:-/tmp}")"/gitctl-evaluar.* ]]
	[[ ! -e "$d" ]]
}

@test "Ambos: Codex y después Claude" {
	run ev -ProveedorLlm Ambos -ConfirmarEnvioLlm
	assert_success
	[[ "$(tr '\n' ' ' <"$FALSO_LOG.orden")" == "codex claude " ]]
}

@test "-ComandoX permite rutas a otros ejecutables" {
	cp "$FALSO_DIR/claude" "$TEST_TMP/mi-claude"
	run ev -ProveedorLlm Claude -ConfirmarEnvioLlm -ComandoClaude "$FALSO_DIR/claude"
	assert_success
	run ev -ProveedorLlm Claude -ConfirmarEnvioLlm -ComandoClaude "$TEST_TMP/no-existe"
	assert_failure
	assert_output_contains "no se encontró el comando"
}

@test "el paquete lleva parches completos y compacta el tercer diff con merge-base común" {
	run ev -ProveedorLlm Codex -ConfirmarEnvioLlm
	assert_success
	local s="$FALSO_DIR/codex.stdin"
	grep -q "^+versión claude" "$s"
	grep -q "^+versión codex" "$s"
	grep -q "Debe crear a.txt" "$s"
	grep -q "mismo merge-base" "$s"
	grep -q "1 file changed" "$s"
	grep -q "$(git rev-parse claude/t) claude: a" "$s"
	assert_output_contains "compactado a --stat"
}

@test "con merge-base distintos incluye el diff completo entre propuestas" {
	commit_en "$REPO" base.txt base
	git -C "$(wt codex t)" merge -q --no-edit main
	run ev -ProveedorLlm Codex -ConfirmarEnvioLlm
	assert_success
	grep -q "merge-base distintos" "$FALSO_DIR/codex.stdin"
	assert_output_contains "completo (merge-base distintos)"
}

@test "límite de tamaño: rechaza sin truncar" {
	local i
	for i in $(seq 1 400); do echo "línea de relleno número $i para superar el límite"; done >"$(wt codex t)/grande.txt"
	git -C "$(wt codex t)" add grande.txt
	git -C "$(wt codex t)" commit -q -m grande
	run ev -ProveedorLlm Codex -ConfirmarEnvioLlm -MaxCaracteresLlm 10000
	assert_failure
	assert_output_contains "supera el límite de 10000"
	[[ ! -e "$FALSO_LOG" ]]
}

@test "sin -ConfirmarEnvioLlm no consulta; interactivo, si dices que no, tampoco" {
	run ev -ProveedorLlm Codex
	assert_failure
	assert_output_contains "-ConfirmarEnvioLlm"
	responder 'n\n' -Accion Evaluar -Ramas "claude/t,codex/t" -CriteriosRevision docs/criterios.md -ProveedorLlm Codex
	assert_success
	assert_output_contains "se enviará a un proveedor externo"
	[[ ! -e "$FALSO_LOG" ]]
	[[ ! -e "$RAIZ/_dictamenes" ]]
}

@test "detecta credenciales literales evidentes" {
	local v
	for v in 'password = "hunter22"' "api_key: 'abcd1234'" 'Server=x;Password=s3cr3t;' '-----BEGIN RSA PRIVATE KEY-----' 'TOKEN="xyz12345"'; do
		printf '%s\n' "$v" >"$TEST_TMP/sec.md"
		run ev -ProveedorLlm Codex -ConfirmarEnvioLlm -CriteriosRevision "$TEST_TMP/sec.md"
		assert_failure
		assert_output_contains "parece contener secretos"
		assert_output_contains "heurística"
	done
	[[ ! -e "$FALSO_LOG" ]]
}

@test "un proveedor que falla no impide los demás" {
	FALSO_MODO_CODEX=falla run ev -ProveedorLlm Ambos -ConfirmarEnvioLlm
	assert_success
	assert_output_contains "Codex terminó con código 3"
	assert_output_contains "error del proveedor"
	[[ "$(ls "$RAIZ/_dictamenes")" == *-claude-* ]]
	[[ "$(ls "$RAIZ/_dictamenes" | wc -l)" == 1 ]]
}

@test "si ninguno responde válidamente termina con error" {
	FALSO_MODO_CODEX=basura FALSO_MODO_CLAUDE=incompleto run ev -ProveedorLlm Ambos -ConfirmarEnvioLlm
	assert_failure
	assert_output_contains "no es un dictamen válido"
	assert_output_contains "faltan propiedades obligatorias"
	assert_output_contains "ningún proveedor produjo un dictamen válido"
	[[ ! -e "$RAIZ/_dictamenes" ]]
}

@test "stdout y stderr separados: el progreso de stderr no rompe el JSON" {
	run ev -ProveedorLlm Claude -ConfirmarEnvioLlm
	assert_success
	assert_output_contains "Recomendación: integrar_primera"
}

@test "muestra el progreso durante una consulta lenta" {
	FALSO_MODO_GEMINI=lento run ev -ProveedorLlm Gemini -ConfirmarEnvioLlm
	assert_success
	assert_output_contains "Gemini: 5 s transcurridos (límite 600 s)"
	assert_output_contains "respuesta de Gemini recibida en"
}

@test "timeout: detiene el proceso y sus hijos, sin dictamen incompleto" {
	FALSO_MODO_CODEX=colgado run ev -ProveedorLlm Codex -ConfirmarEnvioLlm -TiempoEsperaLlmSegundos 1
	assert_failure
	assert_output_contains "no respondió en 1 s"
	local nieto
	nieto="$(cat "$FALSO_DIR/nieto.pid")"
	sleep 0.5
	refute kill -0 "$nieto" 2>/dev/null
	[[ ! -e "$RAIZ/_dictamenes" ]]
	[[ -z "$(ls -d "$(realpath "${TMPDIR:-/tmp}")"/gitctl-evaluar.* 2>/dev/null)" ]]
}

@test "precondiciones: worktrees limpios, principal limpio y ramas administradas" {
	echo x >"$(wt codex t)/p.txt"
	run ev -ProveedorLlm Codex -ConfirmarEnvioLlm
	assert_failure
	assert_output_contains "solo se evalúan commits"
	rm "$(wt codex t)/p.txt"
	echo x >"$REPO/p.txt"
	run ev -ProveedorLlm Codex -ConfirmarEnvioLlm
	assert_failure
	assert_output_contains "principal limpio"
	rm "$REPO/p.txt"
	git branch suelta
	run g Evaluar -Ramas "claude/t,suelta" -CriteriosRevision docs/criterios.md -ProveedorLlm Codex -ConfirmarEnvioLlm
	assert_failure
	assert_output_contains "exactamente un worktree administrado"
	run g Evaluar -Ramas "claude/t,codex/t" -CriteriosRevision docs/criterios.md -ConfirmarEnvioLlm
	assert_failure
	assert_output_contains "falta -ProveedorLlm"
}

@test "bases registradas distintas exigen -Base" {
	git branch dev
	g Crear -Agente gemini -Tarea t -Base dev >/dev/null 2>&1
	commit_en "$(wt gemini t)" g.txt g
	run g Evaluar -Ramas "claude/t,gemini/t" -CriteriosRevision docs/criterios.md -ProveedorLlm Codex -ConfirmarEnvioLlm
	assert_failure
	assert_output_contains "indica cuál usar con -Base"
	run g Evaluar -Ramas "claude/t,gemini/t" -CriteriosRevision docs/criterios.md -ProveedorLlm Codex -ConfirmarEnvioLlm -Base main
	assert_success
}

@test "normalización: JSON directo, result como texto, response sin bloque" {
	source "$GITCTL_ROOT/lib/core/log.sh"
	source "$GITCTL_ROOT/lib/acciones/evaluar/proveedores.sh"
	local d='{"recomendacion":"combinar","confianza":"baja","resumen":"r","contradicciones":[],"commits_recomendados":[],"orden_integracion":[],"pruebas_requeridas":[],"advertencias":[]}'
	local f="$TEST_TMP/r.json"
	echo "$d" >"$f"
	[[ "$(normalizar_dictamen "$f" | jq -r .recomendacion)" == combinar ]]
	jq -n --arg r "$d" '{result: $r}' >"$f"
	[[ "$(normalizar_dictamen "$f" | jq -r .confianza)" == baja ]]
	jq -n --argjson r "$d" '{result: $r}' >"$f"
	normalizar_dictamen "$f" >/dev/null
	jq -n --arg r "$d" '{response: $r}' >"$f"
	normalizar_dictamen "$f" >/dev/null
	jq -n --arg r "$(printf '```\n%s\n```' "$d")" '{response: $r}' >"$f"
	normalizar_dictamen "$f" >/dev/null
	jq -n '{result: "solo texto"}' >"$f"
	refute normalizar_dictamen "$f" 2>/dev/null
	echo '{no json' >"$f"
	refute normalizar_dictamen "$f" 2>/dev/null
}
