# shellcheck shell=bash
# Parámetros con los mismos nombres que gestionar_worktrees.ps1. Como en
# PowerShell, los nombres y los valores enumerados no distinguen mayúsculas.

P_ACCION="" P_AGENTE="" P_TAREA="" P_BASE="" P_REPO="" P_RAIZ="" P_METODO=""
P_COMMITS=() P_RAMAS=()
P_DIFF_COMPLETO="" P_CERRAR="" P_FORZAR="" P_RESCATE=""
P_CONF_INT="" P_CONF_ELIM="" P_CONF_LLM="" P_SIN_INT=""
P_CRITERIOS="" P_PROVEEDOR=""
P_MODELO_CODEX="" P_MODELO_CLAUDE="" P_MODELO_GEMINI=""
P_CMD_CODEX="codex" P_CMD_CLAUDE="claude" P_CMD_GEMINI="gemini"
P_MAX_CHARS=200000 P_TIMEOUT=600
P_AYUDA="" P_VERSION=""

# _enum <parámetro> <valor> <opciones…> → ENUM con la opción canónica.
_enum() {
	local p="$1" v="$2" o
	shift 2
	for o in "$@"; do
		if [[ "${v,,}" == "${o,,}" ]]; then
			ENUM="$o"
			return 0
		fi
	done
	local lista="$*"
	die "valor no válido para -$p: «$v» (valores admitidos: ${lista// /, })"
}

# _entero <parámetro> <valor> <mín> <máx> → ENTERO
_entero() {
	[[ "$2" =~ ^[0-9]+$ ]] || die "-$1 debe ser un número entero: «$2»"
	ENTERO=$((10#$2))
	((ENTERO >= $3 && ENTERO <= $4)) || die "-$1 debe estar entre $3 y $4 (recibido: $2)"
}

# _switch <valor-en-línea> <¿había valor?> → SWITCH ("1" o vacío). Admite -X:$false.
_switch() {
	SWITCH=1
	if [[ -n "$2" ]]; then
		# shellcheck disable=SC2016 # «$false» es literal, como en PowerShell
		case "${1,,}" in
		false | '$false' | 0 | no) SWITCH="" ;;
		true | '$true' | 1 | si | sí | '') SWITCH=1 ;;
		*) die "valor no válido para un modificador: «$1»" ;;
		esac
	fi
}

# lista_dividir <nombre-array> <valor> — divide por comas, recorta y descarta vacíos.
lista_dividir() {
	local -n _dest="$1"
	local -a _partes=()
	local _p
	IFS=, read -r -a _partes <<<"$2,"
	for _p in "${_partes[@]}"; do
		_p="$(_trim "$_p")"
		[[ -n "$_p" ]] && _dest+=("$_p")
	done
	return 0
}

parse_params() {
	local a name val inline
	while (($#)); do
		a="$1"
		shift
		case "$a" in
		-h | --help | -\? | -ayuda | --ayuda)
			P_AYUDA=1
			continue
			;;
		--version | -version)
			P_VERSION=1
			continue
			;;
		--*) name="${a#--}" ;;
		-*) name="${a#-}" ;;
		*) die "argumento inesperado: «$a» (los parámetros van con nombre, p. ej. -Accion Estado; ver gitctl -h)" ;;
		esac
		val="" inline=""
		if [[ "$name" == *:* ]]; then
			val="${name#*:}"
			name="${name%%:*}"
			inline=1
		fi
		case "${name,,}" in
		accion | agente | tarea | base | repositorio | raizworktrees | metodo | rescatarcambios | \
			criteriosrevision | proveedorllm | modelocodex | modeloclaude | modelogemini | \
			comandocodex | comandoclaude | comandogemini | maxcaracteresllm | tiempoesperallmsegundos)
			if [[ -z "$inline" ]]; then
				(($#)) || die "falta el valor de -$name"
				val="$1"
				shift
			fi
			;;
		esac
		case "${name,,}" in
		accion)
			_enum Accion "$val" Crear Estado Comparar Evaluar Integrar Eliminar
			P_ACCION="$ENUM"
			;;
		agente) P_AGENTE="$val" ;;
		tarea) P_TAREA="$val" ;;
		base) P_BASE="$val" ;;
		repositorio) P_REPO="$val" ;;
		raizworktrees) P_RAIZ="$val" ;;
		metodo)
			_enum Metodo "$val" Merge CherryPick
			P_METODO="$ENUM"
			;;
		rescatarcambios) P_RESCATE="$val" ;;
		criteriosrevision) P_CRITERIOS="$val" ;;
		proveedorllm)
			_enum ProveedorLlm "$val" Codex Claude Gemini Ambos Todos
			P_PROVEEDOR="$ENUM"
			;;
		modelocodex) P_MODELO_CODEX="$val" ;;
		modeloclaude) P_MODELO_CLAUDE="$val" ;;
		modelogemini) P_MODELO_GEMINI="$val" ;;
		comandocodex) P_CMD_CODEX="$val" ;;
		comandoclaude) P_CMD_CLAUDE="$val" ;;
		comandogemini) P_CMD_GEMINI="$val" ;;
		maxcaracteresllm)
			_entero MaxCaracteresLlm "$val" 10000 1000000
			P_MAX_CHARS="$ENTERO"
			;;
		tiempoesperallmsegundos)
			_entero TiempoEsperaLlmSegundos "$val" 1 3600
			P_TIMEOUT="$ENTERO"
			;;
		ramas | commits)
			local -a _vals=()
			if [[ -n "$inline" ]]; then
				_vals=("$val")
			else
				if (($# == 0)) || [[ "$1" == -* ]]; then die "falta el valor de -$name"; fi
				while (($#)) && [[ "$1" != -* ]]; do
					_vals+=("$1")
					shift
				done
			fi
			local _v
			for _v in "${_vals[@]}"; do
				if [[ "${name,,}" == ramas ]]; then lista_dividir P_RAMAS "$_v"; else lista_dividir P_COMMITS "$_v"; fi
			done
			;;
		mostrardiffcompleto)
			_switch "$val" "$inline"
			P_DIFF_COMPLETO="$SWITCH"
			;;
		cerrarsinintegrar)
			_switch "$val" "$inline"
			P_CERRAR="$SWITCH"
			;;
		forzar)
			_switch "$val" "$inline"
			P_FORZAR="$SWITCH"
			;;
		confirmarintegracion)
			_switch "$val" "$inline"
			P_CONF_INT="$SWITCH"
			;;
		confirmareliminacion)
			_switch "$val" "$inline"
			P_CONF_ELIM="$SWITCH"
			;;
		confirmarenviollm)
			_switch "$val" "$inline"
			P_CONF_LLM="$SWITCH"
			;;
		sininteraccion)
			_switch "$val" "$inline"
			P_SIN_INT="$SWITCH"
			;;
		*) die "parámetro desconocido: -$name (ver gitctl -h)" ;;
		esac
	done
	if [[ -n "$P_SIN_INT" && -z "$P_ACCION" ]]; then
		die "-SinInteraccion requiere -Accion (sin acción se abre el menú interactivo)"
	fi
	return 0
}
