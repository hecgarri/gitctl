# shellcheck shell=bash
# Adaptador para Codex CLI (modo headless: codex exec).
# implement: sandbox workspace-write (solo puede escribir en el worktree).
# review:    sandbox read-only.

adapter_codex_available() { command -v codex >/dev/null 2>&1; }
adapter_codex_version() { codex --version; }

# shellcheck disable=SC2034 # firma común del contrato de adaptadores
adapter_codex_run() {
	local mode="$1" agent="$2" dir="$3" prompt="$4" log="$5" result="$6" sandbox
	local -a extra
	agent_extra_args extra "$agent" "$mode"
	case "$mode" in
	implement) sandbox=workspace-write ;;
	review) sandbox=read-only ;;
	*) die "modo desconocido: $mode" ;;
	esac
	codex exec --cd "$dir" --sandbox "$sandbox" --color never \
		--output-last-message "$result" "${extra[@]}" - <"$prompt" >>"$log" 2>&1
}
