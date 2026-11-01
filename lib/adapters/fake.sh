# shellcheck shell=bash
# Agente simulado y determinista, para pruebas y demostraciones.
# Variables de entorno opcionales:
#   GITCTL_FAKE_IMPL    script bash a ejecutar en el worktree (modo implement)
#   GITCTL_FAKE_VERDICT veredicto en modo review (approve por defecto)
#   GITCTL_FAKE_SLEEP   segundos de espera antes de terminar
#   GITCTL_FAKE_EXIT    código de salida

adapter_fake_available() { return 0; }
adapter_fake_version() { echo "fake 1.0"; }

# shellcheck disable=SC2034 # firma común del contrato de adaptadores
adapter_fake_run() {
	local mode="$1" agent="$2" dir="$3" prompt="$4" log="$5" result="$6"
	[[ -n "${GITCTL_FAKE_SLEEP:-}" ]] && sleep "$GITCTL_FAKE_SLEEP"
	case "$mode" in
	implement)
		if [[ -n "${GITCTL_FAKE_IMPL:-}" ]]; then
			bash -c "$GITCTL_FAKE_IMPL"
		else
			printf '%s trabajó aquí (%s)\n' "$agent" "$(date +%s%N)" >>"$dir/$agent.txt"
		fi
		echo "Hecho por $agent. Afirmación sin verificar: todo funciona." >"$result"
		;;
	review)
		local v="${GITCTL_FAKE_VERDICT:-approve}"
		{
			echo "Revisión simulada de $agent."
			echo '```json'
			if [[ "$v" == "garbage" ]]; then
				echo '{no es json'
			else
				printf '{"verdict":"%s","findings":[%s]}\n' "$v" \
					"$([[ "$v" == approve ]] || echo '{"severity":"high","file":"x","summary":"falta un test"}')"
			fi
			echo '```'
		} >"$result"
		;;
	esac
	cat "$result" >>"$log"
	return "${GITCTL_FAKE_EXIT:-0}"
}
