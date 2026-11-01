# shellcheck shell=bash
# Registro de adaptadores de agentes.
#
# Un adaptador es un fichero lib/adapters/<nombre>.sh (o
# ~/.config/gitctl/adapters/<nombre>.sh) que define:
#
#   adapter_<nombre>_available            → 0 si el binario está instalado
#   adapter_<nombre>_version              → imprime la versión (opcional)
#   adapter_<nombre>_run MODO AGENTE DIR PROMPT LOG RESULT
#       MODO   implement (puede escribir en DIR) | review (solo lectura)
#       PROMPT fichero con las instrucciones
#       LOG    fichero donde volcar toda la salida
#       RESULT fichero donde dejar el mensaje final del agente
#
# Un agente es un nombre libre; su adaptador es el nombre completo si existe
# ese adaptador, o el prefijo hasta el primer «-» (p. ej. claude-opus → claude).
# Así se pueden tener varios agentes del mismo tipo con distinta configuración
# (agent.claude-opus.args = --model opus).

_GITCTL_ADAPTERS_LOADED=""

_adapter_dirs() {
	printf '%s\n' "$GITCTL_LIB/adapters" "${XDG_CONFIG_HOME:-$HOME/.config}/gitctl/adapters"
}

adapters_load() {
	[[ -n "$_GITCTL_ADAPTERS_LOADED" ]] && return 0
	local d f
	while IFS= read -r d; do
		for f in "$d"/*.sh; do
			# shellcheck source=/dev/null
			[[ -f "$f" ]] && source "$f"
		done
	done < <(_adapter_dirs)
	_GITCTL_ADAPTERS_LOADED=1
}

adapter_list() {
	adapters_load
	declare -F | awk '{print $3}' | sed -n 's/^adapter_\(.*\)_run$/\1/p' | sort
}

adapter_of() {
	adapters_load
	local agent="$1"
	if declare -F "adapter_${agent//[-.]/_}_run" >/dev/null; then
		printf '%s' "${agent//[-.]/_}"
	elif declare -F "adapter_${agent%%-*}_run" >/dev/null; then
		printf '%s' "${agent%%-*}"
	fi
}

require_agent() {
	check_name "agente" "$1"
	local a
	a="$(adapter_of "$1")"
	[[ -n "$a" ]] || die "no hay adaptador para el agente «$1» (disponibles: $(adapter_list | tr '\n' ' '))"
	"adapter_${a}_available" || die "el agente «$1» no está disponible (¿está instalado «$a»?)"
}

# Argumentos extra configurados para un agente: agent.<agente>.args, o los del adaptador.
agent_extra_args() {
	local -n _arr="$1"
	local agent="$2" mode="$3" adapter s
	adapter="$(adapter_of "$agent")"
	s="$(cfg "agent.$agent.$mode.args" "$(cfg "agent.$agent.args" "$(cfg "agent.$adapter.$mode.args" "$(cfg "agent.$adapter.args")")")")"
	# shellcheck disable=SC2206 # división por palabras intencionada
	_arr=($s)
}

# Comando interno: gitctl __adapter <agente> <modo> <dir> <prompt> <log> <result>
_adapter_exec() {
	local agent="$1" mode="$2" dir="$3" prompt="$4" log="$5" result="$6" a
	a="$(adapter_of "$agent")"
	[[ -n "$a" ]] || die "adaptador desconocido: $agent"
	cd "$dir" || die "no existe $dir"
	"adapter_${a}_run" "$mode" "$agent" "$dir" "$prompt" "$log" "$result"
}

# Ejecuta un agente con límite de tiempo. Devuelve el código del agente (124 = timeout).
# Se lanza en background + wait para que las señales (run stop) se atiendan al
# momento; el pid queda en GITCTL_AGENT_PID para poder detenerlo.
GITCTL_AGENT_PID=""
agent_invoke() {
	local agent="$1" mode="$2" dir="$3" prompt="$4" log="$5" result="$6" timeout="$7" rc=0
	# shellcheck disable=SC2094 # el log se pasa como ruta y se amplía en modo append
	timeout --kill-after=15s "$(duration_secs "$timeout")" \
		"$GITCTL_BIN" __adapter "$agent" "$mode" "$dir" "$prompt" "$log" "$result" \
		</dev/null >>"$log" 2>&1 &
	GITCTL_AGENT_PID=$!
	wait "$GITCTL_AGENT_PID" || rc=$?
	GITCTL_AGENT_PID=""
	return "$rc"
}

# Detiene el agente en curso (timeout reenvía la señal a su proceso hijo).
agent_kill() {
	[[ -n "$GITCTL_AGENT_PID" ]] || return 0
	kill -TERM "$GITCTL_AGENT_PID" 2>/dev/null || true
	wait "$GITCTL_AGENT_PID" 2>/dev/null || true
}

cmd_agents() {
	if want_help "$@"; then
		echo "Uso: gitctl agents   — lista adaptadores y si están instalados"
		return
	fi
	local a v
	printf '%-10s %-12s %s\n' ADAPTADOR ESTADO VERSIÓN
	while IFS= read -r a; do
		if "adapter_${a}_available" 2>/dev/null; then
			v=""
			declare -F "adapter_${a}_version" >/dev/null && v="$("adapter_${a}_version" 2>/dev/null | head -1)"
			printf '%-10s %-12s %s\n' "$a" disponible "$v"
		else
			printf '%-10s %-12s\n' "$a" "no instalado"
		fi
	done < <(adapter_list)
}
