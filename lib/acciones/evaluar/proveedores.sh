# shellcheck shell=bash
# Adaptadores de los proveedores LLM y normalización del dictamen.

DICTAMEN_CLAVES=(recomendacion confianza resumen contradicciones commits_recomendados orden_integracion pruebas_requeridas advertencias)

esquema_dictamen() {
	cat <<'J'
{
  "type": "object",
  "additionalProperties": false,
  "required": ["recomendacion", "confianza", "resumen", "contradicciones", "commits_recomendados", "orden_integracion", "pruebas_requeridas", "advertencias"],
  "properties": {
    "recomendacion": {"type": "string", "enum": ["integrar_primera", "integrar_segunda", "combinar", "cherry_pick", "no_integrar", "revision_humana"]},
    "confianza": {"type": "string", "enum": ["alta", "media", "baja"]},
    "resumen": {"type": "string"},
    "contradicciones": {"type": "array", "items": {"type": "string"}},
    "commits_recomendados": {"type": "array", "items": {"type": "string"}},
    "orden_integracion": {"type": "array", "items": {"type": "string"}},
    "pruebas_requeridas": {"type": "array", "items": {"type": "string"}},
    "advertencias": {"type": "array", "items": {"type": "string"}}
  }
}
J
}

# Proveedores de -ProveedorLlm, en orden de ejecución.
lista_proveedores() {
	case "$1" in
	Ambos) echo Codex Claude ;;
	Todos) echo Codex Claude Gemini ;;
	*) echo "$1" ;;
	esac
}

comando_de() {
	case "$1" in
	Codex) printf '%s' "$P_CMD_CODEX" ;;
	Claude) printf '%s' "$P_CMD_CLAUDE" ;;
	Gemini) printf '%s' "$P_CMD_GEMINI" ;;
	esac
}

modelo_de() {
	case "$1" in
	Codex) printf '%s' "$P_MODELO_CODEX" ;;
	Claude) printf '%s' "$P_MODELO_CLAUDE" ;;
	Gemini) printf '%s' "$P_MODELO_GEMINI" ;;
	esac
}

# consultar_proveedor <proveedor> <paquete> <dir-temporal> → DICTAMEN (JSON
# normalizado) y PROV_VERSION. Devuelve 1 (con el motivo en PROV_ERROR) si falla.
consultar_proveedor() {
	local prov="$1" paquete="$2" tmp="$3" cmd modelo p
	cmd="$(comando_de "$prov")"
	modelo="$(modelo_de "$prov")"
	p="$tmp/${prov,,}"
	mkdir -p -- "$p"
	esquema_dictamen >"$p/esquema.json"
	local -a args=()
	local salida="$p/stdout"
	{
		echo "Eres un evaluador de propuestas de código. A continuación tienes un paquete de"
		echo "revisión con todo el material. Sigue sus instrucciones."
		if [[ "$prov" == Gemini ]]; then
			echo
			echo "Responde únicamente con un objeto JSON que cumpla este esquema JSON:"
			cat "$p/esquema.json"
		fi
		echo
		cat -- "$paquete"
	} >"$p/prompt.txt"
	case "$prov" in
	Codex)
		args=(exec --ephemeral --ignore-user-config --skip-git-repo-check
			--sandbox read-only --color never
			--output-schema "$p/esquema.json"
			--output-last-message "$p/respuesta.txt")
		[[ -n "$modelo" ]] && args+=(--model "$modelo")
		args+=(-)
		;;
	Claude)
		args=(--print --safe-mode --restricted --tools ""
			--permission-mode plan --no-session-persistence
			--output-format json --json-schema "$(<"$p/esquema.json")")
		[[ -n "$modelo" ]] && args+=(--model "$modelo")
		;;
	Gemini)
		args=(--output-format json --approval-mode default)
		[[ -n "$modelo" ]] && args+=(--model "$modelo")
		;;
	esac

	echo
	info "consultando a $prov ($cmd${modelo:+, modelo $modelo}; límite $P_TIMEOUT s por consulta)"
	echo "  Se espera el dictamen completo; puede tardar varios minutos." >&2
	ejecutar_proceso "$prov" "$P_TIMEOUT" "$p/prompt.txt" "$salida" "$p/stderr" "$tmp" 1 -- "$cmd" "${args[@]}"
	if ((PROC_RC == 124)); then
		PROV_ERROR="$prov no respondió en $P_TIMEOUT s: se detuvo la consulta y no se guarda ningún dictamen"
		return 1
	fi
	if ((PROC_RC != 0)); then
		PROV_ERROR="$prov terminó con código $PROC_RC: $(tail -n 5 "$p/stderr")"
		return 1
	fi
	info "respuesta de $prov recibida en $PROC_SEGUNDOS s"
	if [[ "$prov" == Codex ]]; then
		[[ -f "$p/respuesta.txt" ]] || {
			PROV_ERROR="Codex terminó sin escribir el archivo de respuesta (--output-last-message)"
			return 1
		}
		salida="$p/respuesta.txt"
	fi
	if ! DICTAMEN="$(normalizar_dictamen "$salida" 2>"$p/jq.err")"; then
		PROV_ERROR="la respuesta de $prov no es un dictamen válido: $(head -c 300 "$p/jq.err")"
		return 1
	fi
	ejecutar_proceso "$prov --version" 30 /dev/null "$p/version" "$p/version.err" "$tmp" "" -- "$cmd" --version
	PROV_VERSION=""
	((PROC_RC == 0)) && PROV_VERSION="$(head -n 1 "$p/version")"
	return 0
}

# normalizar_dictamen <archivo> → imprime el dictamen. Admite: objeto directo,
# structured_output, result (objeto o texto JSON) y response (texto JSON o un
# bloque ```json … ```). Solo comprueba que sea JSON y que estén las 8 claves.
normalizar_dictamen() {
	local claves
	claves="$(printf '%s\n' "${DICTAMEN_CLAVES[@]}" | jq -R . | jq -sc .)"
	jq -c --argjson claves "$claves" "$(
		cat <<'JQ'
def desbloque:
  if test("^\\s*```") then
    (capture("^\\s*```[A-Za-z]*[ \\t]*\\n(?<c>[\\s\\S]*?)\\n[ \\t]*```\\s*$") // error("bloque Markdown incompleto")).c
  else . end;
def texto_json(origen): try fromjson catch error(origen + " no contiene JSON estructurado");
if type != "object" then error("no es un objeto JSON")
elif has("recomendacion") then .
elif (.structured_output | type) == "object" then .structured_output
elif has("result") then
  (if (.result | type) == "object" then .result
   elif (.result | type) == "string" then (.result | texto_json("result"))
   else error("result no contiene JSON estructurado") end)
elif (.response | type) == "string" then (.response | desbloque | texto_json("response"))
else . end
| if type != "object" then error("el dictamen no es un objeto JSON") else . end
| ($claves - keys) as $faltan
| if ($faltan | length) > 0 then error("faltan propiedades obligatorias: " + ($faltan | join(", "))) else . end
JQ
	)" "$1"
}

mostrar_dictamen() {
	local prov="$1" json="$2"
	echo
	echo "== Dictamen de $prov =="
	jq -r '
		def lista(t): "\(t):", (if (. | type) != "array" or length == 0 then "  (ninguno)" else .[] | "  - \(.)" end);
		"Recomendación: \(.recomendacion)",
		"Confianza:     \(.confianza)",
		"Resumen:       \(.resumen)",
		(.contradicciones | lista("Contradicciones")),
		(.commits_recomendados | lista("Commits recomendados")),
		(.orden_integracion | lista("Orden de integración")),
		(.pruebas_requeridas | lista("Pruebas requeridas")),
		(.advertencias | lista("Advertencias"))
	' <<<"$json"
}

# guardar_dictamen <proveedor> <json> → DICTAMEN_RUTA
guardar_dictamen() {
	local prov="$1" json="$2" dir="$RAIZ/_dictamenes" fecha n1 n2
	mkdir -p -- "$dir" || die "no se pudo crear $dir"
	fecha="$(date -u +%Y%m%dT%H%M%SZ)"
	n1="${EV_RAMA1//[^[:alnum:]._-]/-}"
	n2="${EV_RAMA2//[^[:alnum:]._-]/-}"
	DICTAMEN_RUTA="$dir/$fecha-${prov,,}-$n1-$n2.json"
	jq -n \
		--arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		--arg provider "${prov,,}" \
		--arg cli_version "$PROV_VERSION" \
		--arg model "$(modelo_de "$prov")" \
		--arg base_branch "$EV_BASE" --arg base_sha "$PAQ_BASE_SHA" \
		--arg first_branch "$EV_RAMA1" --arg first_sha "$PAQ_SHA1" \
		--arg second_branch "$EV_RAMA2" --arg second_sha "$PAQ_SHA2" \
		--arg prompt_sha256 "$PAQ_SHA256" \
		--argjson judgment "$json" \
		'{format_version: 2, generated_utc: $generated, provider: $provider,
		  cli_version: (if $cli_version == "" then null else $cli_version end),
		  model_requested: (if $model == "" then null else $model end),
		  base_branch: $base_branch, base_sha: $base_sha,
		  first_branch: $first_branch, first_sha: $first_sha,
		  second_branch: $second_branch, second_sha: $second_sha,
		  prompt_sha256: $prompt_sha256, judgment: $judgment}' >"$DICTAMEN_RUTA" ||
		die "no se pudo guardar el dictamen en $DICTAMEN_RUTA"
}
