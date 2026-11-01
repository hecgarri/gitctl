# shellcheck shell=bash
# Verificación: ejecuta los checks de .gitctl.conf en una copia limpia y
# desacoplada del commit exacto. El resultado (exit codes + logs con hash) es
# la EVIDENCIA y queda ligado a ese SHA y a la definición actual de los checks.

_verify_help() {
	cat <<'EOF'
Uso: gitctl verify <tarea> <agente> [--sha SHA] [--json]

Ejecuta, en orden, los check.* definidos en .gitctl.conf (del worktree principal)
sobre una copia limpia del último commit de la rama del agente. Los cambios sin
commitear NO se verifican. Sale con 0 solo si todos los checks pasan.

Variables disponibles en los checks: GITCTL_SHA, GITCTL_TASK, GITCTL_AGENT.
EOF
}

verify_file() { printf '%s/verifications/%s.json' "$(state_dir)" "$1"; }

# none | pass | fail | caducada (los checks cambiaron desde entonces)
verify_status() {
	local f
	f="$(verify_file "$1")"
	[[ -f "$f" ]] || {
		echo none
		return
	}
	if [[ "$(jq -r .checks_digest "$f")" != "$(cfg_checks_digest)" ]]; then
		echo caducada
	else
		jq -r .result "$f"
	fi
}

cmd_verify() {
	want_help "$@" && {
		_verify_help
		return
	}
	state_init
	local task="" agent="" sha="" json=""
	while (($#)); do
		case "$1" in
		--sha)
			need_arg "$@"
			sha="$2"
			shift
			;;
		--json) json=1 ;;
		-*) die "opción desconocida: $1" ;;
		*) if [[ -z "$task" ]]; then task="$1"; else agent="$1"; fi ;;
		esac
		shift
	done
	[[ -n "$agent" ]] || die "uso: gitctl verify <tarea> <agente>"
	require_assign "$task" "$agent"
	cfg_load
	((${#GITCTL_CHECKS[@]})) || die "no hay checks definidos (check.<nombre> = <comando> en $(git_main_root)/.gitctl.conf); sin checks no hay evidencia"
	if [[ -n "$sha" ]]; then
		sha="$(git_ref_sha "$sha")" || die "commit no válido"
	else
		sha="$(assign_sha "$task" "$agent")"
	fi
	run_active "$task" "$agent" && warn "hay un run en curso para $task/$agent; se verifica el commit actual $(git_short "$sha")"
	local wt
	wt="$(assign_get "$task" "$agent" worktree)"
	[[ -d "$wt" ]] && ! git_is_clean "$wt" && warn "el worktree tiene cambios sin commitear: NO se incluyen en la verificación"

	local vdir tmp to
	vdir="$(state_dir)/verifications/$sha"
	mkdir -p "$vdir"
	to="$(duration_secs "$(cfg verify.timeout)")"
	info "verificando $(git_short "$sha") ($task/$agent) en una copia limpia…"
	tmp="$(wt_ephemeral "$sha" verify)"

	local name results=() overall=pass
	for name in "${GITCTL_CHECKS[@]}"; do
		local cmd="${GITCTL_CFG[check.$name]}" log="$vdir/$name.log" t0 rc=0
		t0="$(now_epoch)"
		(
			cd "$tmp" || exit 1
			export GITCTL_SHA="$sha" GITCTL_TASK="$task" GITCTL_AGENT="$agent"
			timeout --kill-after=10s "$to" bash -c "$cmd"
		) </dev/null >"$log" 2>&1 || rc=$?
		local d=$(($(now_epoch) - t0))
		((rc == 0)) || overall=fail
		results+=("$(jq -cn --arg n "$name" --arg c "$cmd" --argjson e "$rc" --argjson d "$d" \
			--arg h "$(sha256_file "$log")" '{name:$n, cmd:$c, exit:$e, duration:$d, log_sha256:$h}')")
		if ((rc == 0)); then mark ok "$name ($(fmt_secs "$d"))"; else mark fail "$name — exit $rc ($(fmt_secs "$d")) · log: $log"; fi
	done
	wt_ephemeral_rm "$tmp"

	printf '%s\n' "${results[@]}" | jq -s --arg sha "$sha" --arg t "$task" --arg a "$agent" \
		--arg r "$overall" --arg ts "$(now_iso)" --arg dg "$(cfg_checks_digest)" \
		'{sha:$sha, task:$t, agent:$a, kind:"evidence", result:$r, at:$ts, checks_digest:$dg, checks:.}' |
		atomic_write "$(verify_file "$sha")"
	emit_event verify.done task="$task" agent="$agent" sha="$sha" result="$overall"
	[[ -n "$json" ]] && cat "$(verify_file "$sha")"
	if [[ "$overall" == pass ]]; then
		ok "evidencia: todos los checks pasan en $(git_short "$sha")"
	else
		err "evidencia: hay checks que fallan en $(git_short "$sha") (gitctl fix $task $agent)"
		return 1
	fi
}
