# shellcheck shell=bash
# Adaptador para Gemini CLI (EXPERIMENTAL: no verificado en este entorno).
# Ajusta las opciones con agent.gemini.implement.args / agent.gemini.review.args.

adapter_gemini_available() { command -v gemini >/dev/null 2>&1; }
adapter_gemini_version() { gemini --version; }

# shellcheck disable=SC2034 # firma común del contrato de adaptadores
adapter_gemini_run() {
	local mode="$1" agent="$2" dir="$3" prompt="$4" log="$5" result="$6"
	local -a extra args
	agent_extra_args extra "$agent" "$mode"
	case "$mode" in
	implement) args=(--approval-mode auto_edit) ;;
	review) args=(--approval-mode default) ;;
	*) die "modo desconocido: $mode" ;;
	esac
	local rc=0
	gemini "${args[@]}" "${extra[@]}" -p "$(cat "$prompt")" >"$result" 2>>"$log" || rc=$?
	cat "$result" >>"$log"
	return "$rc"
}
