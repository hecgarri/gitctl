# shellcheck shell=bash
# Ejecución headless de agentes en su worktree, en background y en paralelo.
# Cada ejecución (run) deja huellas: prompt, log, mensaje final y un commit con
# trailers Gitctl-* que la vinculan a la tarea, el agente y el run.

_run_help() {
	cat <<'EOF'
Uso: gitctl run <tarea> [agente...] [--timeout DUR] [--wait]
     gitctl run status [tarea] [-n N]
     gitctl run wait [tarea|run...]
     gitctl run logs <run|tarea/agente> [-f]
     gitctl run show <run|tarea/agente>
     gitctl run stop <run|tarea/agente>

Lanza los agentes asignados a la tarea (todos si no se indican) en modo headless,
cada uno en su worktree y en paralelo. Al terminar cada agente, gitctl commitea los
cambios pendientes en su rama (commit de huella) con trailers Gitctl-Task/Agent/Run.

  --timeout DUR   Límite por agente (30m, 2h…; por defecto agent.timeout)
  --wait          Espera a que terminen todos y muestra el resultado
EOF
}

cmd_run() {
	case "${1:-}" in
	"" | -h | --help | help)
		_run_help
		return
		;;
	status | ls)
		shift
		state_init
		_run_status "$@"
		;;
	wait)
		shift
		state_init
		_run_wait "$@"
		;;
	logs | log)
		shift
		state_init
		_run_logs "$@"
		;;
	show)
		shift
		state_init
		_run_show "$@"
		;;
	stop)
		shift
		state_init
		_run_stop "$@"
		;;
	*)
		state_init
		_run_start "$@"
		;;
	esac
}

run_dir() { printf '%s/runs/%s' "$(state_dir)" "$1"; }
run_meta() { printf '%s/meta.json' "$(run_dir "$1")"; }
run_get() { jq -r "$2 // empty" "$(run_meta "$1")" 2>/dev/null; }

_run_metas() {
	local f
	for f in "$(state_dir)"/runs/*/meta.json; do
		[[ -f "$f" ]] || continue
		printf '%s\0' "$f"
	done
}

# Lista ids de runs (más antiguos primero), filtrando por tarea y agente opcionales.
run_ids() {
	local task="${1:-}" agent="${2:-}"
	_run_metas | xargs -0r jq -r --arg t "$task" --arg a "$agent" \
		'select(($t == "" or .task == $t) and ($a == "" or .agent == $a)) | [.created, .id] | @tsv' |
		sort | cut -f2
}
run_latest() { run_ids "$1" "$2" | tail -n1; }

_pid_alive() { [[ -n "$1" ]] && kill -0 "$1" 2>/dev/null; }

# Estado real: si figura como en curso pero el proceso no existe → perdido.
run_status() {
	local st pid
	st="$(run_get "$1" .status)"
	pid="$(run_get "$1" .pid)"
	case "$st" in
	starting)
		# Margen para que el worker arranque.
		local c
		c="$(run_get "$1" .created_epoch)"
		if ((${c:-0} + 30 < $(now_epoch))) && ! _pid_alive "$pid"; then echo perdido; else echo "$st"; fi
		;;
	running) if _pid_alive "$pid"; then echo running; else echo perdido; fi ;;
	*) echo "$st" ;;
	esac
}
run_active() {
	local r
	r="$(run_latest "$1" "$2")"
	[[ -n "$r" ]] || return 1
	case "$(run_status "$r")" in starting | running) return 0 ;; *) return 1 ;; esac
}

# Acepta un id de run o «tarea/agente» (último run).
run_resolve() {
	local arg="$1" r
	if [[ "$arg" == */* ]]; then
		r="$(run_latest "${arg%%/*}" "${arg#*/}")"
		[[ -n "$r" ]] || die "no hay runs para $arg"
	else
		r="$arg"
	fi
	[[ -f "$(run_meta "$r")" ]] || die "no existe el run «$arg»"
	printf '%s' "$r"
}

# Construye el prompt de implementación.
_run_prompt() {
	local task="$1" agent="$2" feedback_file="$3" tpl fb=""
	tpl="$(cat "$GITCTL_LIB/prompts/implement.md")"
	[[ -n "$feedback_file" ]] && fb="$(cat "$feedback_file")"
	tpl="$(template_sub "$tpl" AGENT "$agent")"
	tpl="$(template_sub "$tpl" TASK "$task")"
	tpl="$(template_sub "$tpl" TITLE "$(task_get "$task" .title)")"
	tpl="$(template_sub "$tpl" WORKTREE "$(assign_get "$task" "$agent" worktree)")"
	tpl="$(template_sub "$tpl" BRANCH "$(assign_get "$task" "$agent" branch)")"
	tpl="$(template_sub "$tpl" SPEC "$(cat "$(task_dir "$task")/spec.md")")"
	tpl="$(template_sub "$tpl" FEEDBACK "$fb")"
	printf '%s\n' "$tpl"
}

# run_launch <tarea> <agente> <timeout> [fichero_feedback] → imprime el id del run
run_launch() {
	local task="$1" agent="$2" timeout="$3" feedback="${4:-}"
	local wt id rd
	wt="$(assign_get "$task" "$agent" worktree)"
	[[ -d "$wt" ]] || die "no existe el worktree de $task/$agent ($wt)"
	run_active "$task" "$agent" && die "$task/$agent ya tiene un run en curso"
	id="r$(date +%Y%m%d-%H%M%S)-$(rand_hex 2)"
	rd="$(run_dir "$id")"
	mkdir -p "$rd"
	_run_prompt "$task" "$agent" "$feedback" >"$rd/prompt.md"
	jq -n --arg id "$id" --arg t "$task" --arg a "$agent" --arg wt "$wt" \
		--arg br "$(assign_get "$task" "$agent" branch)" --arg sha "$(git_head_sha "$wt")" \
		--arg to "$timeout" --arg ts "$(now_iso)" --argjson ep "$(now_epoch)" \
		--argjson fix "$([[ -n "$feedback" ]] && echo true || echo false)" \
		'{id:$id, task:$t, agent:$a, mode:"implement", fix:$fix, worktree:$wt, branch:$br,
		  sha_start:$sha, timeout:$to, status:"starting", created:$ts, created_epoch:$ep}' |
		atomic_write "$rd/meta.json"
	: >"$rd/output.log"
	# Proceso independiente (nueva sesión): sobrevive al terminal y se puede
	# detener en grupo con «run stop».
	setsid "$GITCTL_BIN" __run-worker "$id" </dev/null >>"$rd/worker.log" 2>&1 &
	emit_event run.started task="$task" agent="$agent" run="$id" fix="$([[ -n "$feedback" ]] && echo yes || echo no)"
	printf '%s' "$id"
}

_run_start() {
	local task="" timeout="" wait="" agents=()
	while (($#)); do
		case "$1" in
		--timeout)
			need_arg "$@"
			timeout="$2"
			shift
			;;
		--wait) wait=1 ;;
		--parallel) ;; # siempre en paralelo; se acepta por compatibilidad
		-h | --help)
			_run_help
			return
			;;
		-*) die "opción desconocida: $1" ;;
		*) if [[ -z "$task" ]]; then task="$1"; else agents+=("$1"); fi ;;
		esac
		shift
	done
	require_task "$task"
	[[ "$(task_get "$task" .status)" == open ]] || die "la tarea $task está cerrada"
	((${#agents[@]})) || mapfile -t agents < <(assign_agents "$task")
	((${#agents[@]})) || die "la tarea $task no tiene agentes asignados (gitctl task assign)"
	local a ids=()
	for a in "${agents[@]}"; do
		require_assign "$task" "$a"
		require_agent "$a"
	done
	for a in "${agents[@]}"; do
		local to="${timeout:-$(cfg "agent.$a.timeout" "$(cfg agent.timeout)")}"
		duration_secs "$to" >/dev/null
		local id
		id="$(run_launch "$task" "$a" "$to")"
		ids+=("$id")
		ok "$a lanzado: run $id (límite $to) — gitctl run logs $id -f"
	done
	if [[ -n "$wait" ]]; then
		_run_wait "${ids[@]}"
	else
		info "en background; consulta con «gitctl run status $task» o espera con «gitctl run wait $task»"
	fi
}

# ---------- worker (proceso en background) ----------

_run_set() { json_update "$(run_meta "$1")" "$2" "${@:3}"; }

_run_worker() {
	local id="$1" rd task agent wt branch timeout
	rd="$(run_dir "$id")"
	task="$(run_get "$id" .task)"
	agent="$(run_get "$id" .agent)"
	wt="$(run_get "$id" .worktree)"
	branch="$(run_get "$id" .branch)"
	timeout="$(run_get "$id" .timeout)"

	# Un solo agente por worktree a la vez, aunque se lance desde dos terminales.
	local lockfd
	exec {lockfd}>"$(state_dir)/locks/agent-$task-$agent.lock"
	if ! flock -n "$lockfd"; then
		_run_set "$id" '.status = "rechazado" | .note = "otro run ocupa el worktree"'
		return 1
	fi

	local sha_start
	sha_start="$(git_head_sha "$wt")"
	_run_set "$id" '.status = "running" | .pid = ($pid|tonumber) | .started = $ts | .sha_start = $sha' \
		--arg pid "$$" --arg ts "$(now_iso)" --arg sha "$sha_start"
	_RUN_WORKER_ID="$id"
	trap _run_on_term TERM INT

	export GITCTL_RUN_ID="$id" GITCTL_TASK="$task" GITCTL_AGENT="$agent"
	local t0 rc=0
	t0="$(now_epoch)"
	agent_invoke "$agent" implement "$wt" "$rd/prompt.md" "$rd/output.log" "$rd/result.md" "$timeout" || rc=$?
	local dur=$(($(now_epoch) - t0))

	_run_footprint "$id" "$rc" "$sha_start"
	local st=ok
	case "$rc" in
	0) st=ok ;;
	124 | 137) st=timeout ;;
	*) st=fallido ;;
	esac
	_run_set "$id" '.status = $st | .exit = ($rc|tonumber) | .duration = ($d|tonumber) | .finished = $ts' \
		--arg st "$st" --arg rc "$rc" --arg d "$dur" --arg ts "$(now_iso)"
	emit_event run.finished task="$task" agent="$agent" run="$id" status="$st" exit="$rc" \
		sha="$(run_get "$id" .sha_end)"
	trap - TERM INT
	return 0
}

_run_on_term() {
	trap - TERM INT
	agent_kill
	local id="$_RUN_WORKER_ID"
	_run_set "$id" '.status = "detenido" | .finished = $ts' --arg ts "$(now_iso)"
	emit_event run.stopped task="$(run_get "$id" .task)" agent="$(run_get "$id" .agent)" run="$id"
	exit 143
}

# Commit de huella: registra en la rama lo que el agente dejó en el worktree.
_run_footprint() {
	local id="$1" rc="$2" sha_start="$3" wt branch task agent notes=()
	wt="$(run_get "$id" .worktree)"
	branch="$(run_get "$id" .branch)"
	task="$(run_get "$id" .task)"
	agent="$(run_get "$id" .agent)"

	local cur
	cur="$(git_current_branch "$wt")"
	if [[ "$cur" != "$branch" ]]; then
		notes+=("el agente cambió de rama (HEAD en «${cur:-detached}»); no se commitea nada")
	elif ! git_is_clean "$wt"; then
		local summary="" ida=()
		git_identity_args ida
		[[ -s "$(run_dir "$id")/result.md" ]] && summary="$(head -c 4000 "$(run_dir "$id")/result.md")"
		git -C "$wt" add -A
		git "${ida[@]}" -C "$wt" commit -q --no-verify \
			--author="$agent (vía gitctl) <$agent@agents.gitctl>" \
			-m "gitctl($task): cambios de $agent [run $id]" \
			-m "Resumen del agente (afirmación, no verificada):

${summary:-(sin resumen)}" \
			--trailer "Gitctl-Task: $task" --trailer "Gitctl-Agent: $agent" \
			--trailer "Gitctl-Run: $id" --trailer "Gitctl-Exit: $rc" ||
			notes+=("no se pudo crear el commit de huella")
	fi

	local sha_end
	sha_end="$(git_ref_sha "refs/heads/$branch")"
	if ! git merge-base --is-ancestor "$sha_start" "$sha_end" 2>/dev/null; then
		notes+=("historial reescrito: $sha_start ya no es antecesor de la rama")
	fi
	local commits
	commits="$(git rev-list "$sha_start..$sha_end" 2>/dev/null | jq -Rsc 'split("\n") | map(select(. != ""))')"
	_run_set "$id" '.sha_end = $s | .commits = $c | .notes = $n' \
		--arg s "$sha_end" --argjson c "${commits:-[]}" \
		--argjson n "$(printf '%s\n' "${notes[@]}" | jq -Rsc 'split("\n") | map(select(. != ""))')"
}

# ---------- consulta ----------

_run_status() {
	local task="" n=20
	while (($#)); do
		case "$1" in
		-n)
			need_arg "$@"
			n="$2"
			shift
			;;
		*) task="$1" ;;
		esac
		shift
	done
	printf '%-22s %-6s %-12s %-10s %-8s %-9s %s\n' RUN TAREA AGENTE ESTADO DURAC. SHA NOTAS
	local r
	while IFS= read -r r; do
		[[ -z "$r" ]] && continue
		local st dur sha
		st="$(run_status "$r")"
		dur="$(run_get "$r" .duration)"
		if [[ -z "$dur" && "$st" == running ]]; then
			dur=$(($(now_epoch) - $(date -d "$(run_get "$r" .started)" +%s)))
		fi
		sha="$(run_get "$r" .sha_end)"
		printf '%-22s %-6s %-12s %-10s %-8s %-9s %s\n' "$r" "$(run_get "$r" .task)" "$(run_get "$r" .agent)" \
			"$st" "$(fmt_secs "${dur:-0}")" "${sha:0:8}" "$(run_get "$r" '(.notes // []) | join("; ")')"
	done < <(run_ids "$task" | tail -n "$n")
}

# Espera a runs concretos o a todos los de una tarea. Sale con 1 si alguno falló.
_run_wait() {
	local ids=() x
	for x in "$@"; do
		if task_exists "$x" 2>/dev/null; then
			local a
			while IFS= read -r a; do
				local r
				r="$(run_latest "$x" "$a")"
				[[ -n "$r" ]] && ids+=("$r")
			done < <(assign_agents "$x")
		else
			ids+=("$(run_resolve "$x")")
		fi
	done
	((${#ids[@]})) || mapfile -t ids < <(run_ids | tail -n 20)
	local pending=1 shown=""
	while ((pending)); do
		pending=0
		for x in "${ids[@]}"; do
			case "$(run_status "$x")" in starting | running) pending=1 ;; esac
		done
		if ((pending)); then
			[[ -z "$shown" ]] && info "esperando a ${#ids[@]} run(s)…" && shown=1
			sleep 2
		fi
	done
	local bad=0 st
	for x in "${ids[@]}"; do
		st="$(run_status "$x")"
		if [[ "$st" == ok ]]; then
			mark ok "$x $(run_get "$x" .agent): ok → $(git_short "$(run_get "$x" .sha_end)")"
		else
			mark fail "$x $(run_get "$x" .agent): $st (exit $(run_get "$x" .exit))"
			bad=1
		fi
		run_get "$x" '(.notes // [])[]' | sed 's/^/      aviso: /'
	done
	return "$bad"
}

_run_logs() {
	local target="" follow=""
	while (($#)); do
		case "$1" in
		-f | --follow) follow=1 ;;
		*) target="$1" ;;
		esac
		shift
	done
	local r
	r="$(run_resolve "${target:?uso: gitctl run logs <run|tarea/agente> [-f]}")"
	if [[ -n "$follow" ]]; then
		tail -n +1 -f "$(run_dir "$r")/output.log" --pid="$(run_get "$r" .pid || echo $$)"
	else
		cat "$(run_dir "$r")/output.log"
	fi
}

_run_show() {
	local r
	r="$(run_resolve "${1:?uso: gitctl run show <run|tarea/agente>}")"
	jq --arg st "$(run_status "$r")" '. + {status_actual:$st}' "$(run_meta "$r")"
	if [[ -s "$(run_dir "$r")/result.md" ]]; then
		echo "--- mensaje final del agente (afirmación, no verificada) ---"
		cat "$(run_dir "$r")/result.md"
	fi
}

_run_stop() {
	local r pid
	r="$(run_resolve "${1:?uso: gitctl run stop <run|tarea/agente>}")"
	pid="$(run_get "$r" .pid)"
	_pid_alive "$pid" || die "el run $r no está en ejecución"
	confirm "¿Detener el run $r ($(run_get "$r" .agent))? Los cambios quedarán sin commitear en el worktree" || die "cancelado"
	kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid"
	ok "señal enviada a $r"
}

# ---------- fix: iteración sobre huellas ----------

_fix_help() {
	cat <<'EOF'
Uso: gitctl fix <tarea> <agente> [--timeout DUR] [--wait]

Relanza al agente autor con las huellas del último commit de su rama como entrada:
hallazgos de las revisiones «request_changes» y salida de los checks fallidos.
EOF
}

cmd_fix() {
	want_help "$@" && {
		_fix_help
		return
	}
	state_init
	local task="" agent="" timeout="" wait=""
	while (($#)); do
		case "$1" in
		--timeout)
			need_arg "$@"
			timeout="$2"
			shift
			;;
		--wait) wait=1 ;;
		-*) die "opción desconocida: $1" ;;
		*) if [[ -z "$task" ]]; then task="$1"; else agent="$1"; fi ;;
		esac
		shift
	done
	[[ -n "$agent" ]] || die "uso: gitctl fix <tarea> <agente>"
	require_assign "$task" "$agent"
	require_agent "$agent"
	local sha fb findings=""
	sha="$(assign_sha "$task" "$agent")"
	findings="$(_fix_findings "$sha" "$agent")"
	[[ -n "$findings" ]] || die "no hay hallazgos ni checks fallidos registrados para $(git_short "$sha"); nada que corregir"
	fb="$(state_dir)/tmp/feedback-$task-$agent-$(rand_hex 3).md"
	local tpl
	tpl="$(cat "$GITCTL_LIB/prompts/fix.md")"
	tpl="$(template_sub "$tpl" SHA "$sha")"
	template_sub "$tpl" FINDINGS "$findings" >"$fb"
	local to="${timeout:-$(cfg "agent.$agent.timeout" "$(cfg agent.timeout)")}" id
	id="$(run_launch "$task" "$agent" "$to" "$fb")"
	rm -f "$fb"
	ok "$agent relanzado con correcciones: run $id"
	[[ -z "$wait" ]] || _run_wait "$id"
}

_fix_findings() {
	local sha="$1" vf rf
	vf="$(state_dir)/verifications/$sha.json"
	if [[ -f "$vf" ]] && [[ "$(jq -r .result "$vf")" == fail ]]; then
		echo "### Checks fallidos (evidencia)"
		local name
		while IFS= read -r name; do
			echo "#### check «$name» (exit $(jq -r --arg n "$name" '.checks[] | select(.name==$n) | .exit' "$vf"))"
			echo '```'
			tail -n 60 "$(state_dir)/verifications/$sha/$name.log" 2>/dev/null
			echo '```'
		done < <(jq -r '.checks[] | select(.exit != 0) | .name' "$vf")
		echo
	fi
	for rf in "$(state_dir)/reviews/$sha"/*.json; do
		[[ -f "$rf" ]] || continue
		[[ "$(jq -r .verdict "$rf")" == request_changes ]] || continue
		echo "### Revisión de $(jq -r .reviewer "$rf") (afirmación de otro agente)"
		jq -r '.findings[]? | "- [\(.severity // "?")] \(.file // "?"):\(.line // "?") — \(.summary // .)\(if .verified == true then " (el revisor dice haberlo comprobado)" else "" end)"' "$rf"
		echo
	done
}
