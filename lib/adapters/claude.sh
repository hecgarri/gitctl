# shellcheck shell=bash
# Adaptador para Claude Code (modo headless: claude -p).
# implement: puede editar ficheros del worktree (permission-mode acceptEdits).
#            Para permitir comandos (tests, etc.) añade en .gitctl.conf, p. ej.:
#              agent.claude.implement.args = --allowedTools Bash(npm test:*) Bash(make:*)
# review:    solo herramientas de lectura; el resto se deniega (dontAsk).

adapter_claude_available() { command -v claude >/dev/null 2>&1; }
adapter_claude_version() { claude --version; }

# shellcheck disable=SC2034 # firma común del contrato de adaptadores
adapter_claude_run() {
	local mode="$1" agent="$2" dir="$3" prompt="$4" log="$5" result="$6"
	local -a extra args
	agent_extra_args extra "$agent" "$mode"
	case "$mode" in
	implement)
		args=(--permission-mode acceptEdits)
		;;
	review)
		args=(--permission-mode dontAsk
			--allowedTools "Read" "Grep" "Glob"
			"Bash(git diff:*)" "Bash(git log:*)" "Bash(git show:*)" "Bash(git status:*)")
		;;
	*) die "modo desconocido: $mode" ;;
	esac
	# stdout = mensaje final (texto); stderr = diagnóstico.
	local rc=0
	claude -p --output-format text "${args[@]}" "${extra[@]}" <"$prompt" >"$result" 2>>"$log" || rc=$?
	cat "$result" >>"$log"
	return "$rc"
}
