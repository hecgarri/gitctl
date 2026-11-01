# shellcheck shell=bash
# Tareas: unidad de trabajo con especificación, base fija y agentes asignados.

_task_help() {
	cat <<'EOF'
Uso: gitctl task <acción>

  new "<título>" [--spec FICHERO|-] [--base REF] [--id ID]
                       Crea una tarea. La especificación se guarda en el estado
                       y se entrega a los agentes. La base queda fijada a un SHA.
  ls [--all]           Lista tareas (abiertas por defecto)
  show <tarea> [--json]
                       Estado completo: agentes, commits, runs, evidencia, revisiones
  assign <tarea> <agente>...
                       Crea un worktree y una rama gitctl/<tarea>/<agente> por agente
  spec <tarea>         Muestra la especificación
  close <tarea>        Marca la tarea como cerrada (no borra ramas ni worktrees)
EOF
}

cmd_task() {
	local action="${1:-ls}"
	[[ $# -gt 0 ]] && shift
	case "$action" in
	-h | --help | help) _task_help ;;
	new)
		state_init
		_task_new "$@"
		;;
	ls | list)
		state_init
		_task_ls "$@"
		;;
	show)
		state_init
		_task_show "$@"
		;;
	assign)
		state_init
		_task_assign "$@"
		;;
	spec)
		state_init
		require_task "${1:?falta la tarea}"
		cat "$(task_dir "$1")/spec.md"
		;;
	close)
		state_init
		_task_close "$@"
		;;
	*) die "acción desconocida: task $action (ver gitctl task --help)" ;;
	esac
}

_task_next_id() {
	local f n
	f="$(state_dir)/counter"
	n="$(cat "$f" 2>/dev/null || echo 0)"
	n=$((n + 1))
	while task_exists "t$n"; do n=$((n + 1)); done
	echo "$n" | atomic_write "$f"
	echo "t$n"
}

_task_new() {
	local title="" spec="" base="" id=""
	while (($#)); do
		case "$1" in
		--spec)
			need_arg "$@"
			spec="$2"
			shift
			;;
		--base)
			need_arg "$@"
			base="$2"
			shift
			;;
		--id)
			need_arg "$@"
			id="$2"
			shift
			;;
		-h | --help)
			_task_help
			return
			;;
		-*) die "opción desconocida: $1" ;;
		*) title="$1" ;;
		esac
		shift
	done
	[[ -n "$title" ]] || die 'uso: gitctl task new "<título>" [--spec FICHERO]'
	base="${base:-$(git_default_branch)}"
	local base_sha
	base_sha="$(git_ref_sha "$base")" || die "no existe la referencia base «$base»"

	local spec_text
	if [[ "$spec" == "-" ]]; then
		spec_text="$(cat)"
	elif [[ -n "$spec" ]]; then
		[[ -r "$spec" ]] || die "no se puede leer $spec"
		spec_text="$(cat "$spec")"
	else
		spec_text="$title"
	fi

	if [[ -n "$id" ]]; then
		check_name "id de tarea" "$id"
		task_exists "$id" && die "ya existe la tarea $id"
	else
		id="$(with_lock counter _task_next_id)"
	fi
	mkdir -p "$(task_dir "$id")"
	printf '%s\n' "$spec_text" | atomic_write "$(task_dir "$id")/spec.md"
	jq -n --arg id "$id" --arg title "$title" --arg base "$base" --arg sha "$base_sha" \
		--arg ts "$(now_iso)" \
		'{id:$id, title:$title, base_ref:$base, base_sha:$sha, created:$ts, status:"open", assignments:[]}' |
		atomic_write "$(task_file "$id")"
	emit_event task.created task="$id" title="$title" base="$base" base_sha="$base_sha"
	ok "tarea $id creada sobre $base ($(git_short "$base_sha"))"
	echo "$id"
}

_task_assign() {
	local task="${1:-}"
	[[ -n "$task" && $# -ge 2 ]] || die "uso: gitctl task assign <tarea> <agente>..."
	shift
	require_task "$task"
	[[ "$(task_get "$task" .status)" == open ]] || die "la tarea $task está cerrada"
	local agent base_sha
	base_sha="$(task_get "$task" .base_sha)"
	for agent in "$@"; do
		check_name "agente" "$agent"
		[[ -n "$(adapter_of "$agent")" ]] || die "no hay adaptador para «$agent» (ver gitctl agents)"
		if assign_exists "$task" "$agent"; then
			warn "$agent ya está asignado a $task"
			continue
		fi
		local branch="gitctl/$task/$agent" path
		path="$(wt_root)/$task-$agent"
		wt_create "$path" "$branch" "$base_sha"
		json_update "$(task_file "$task")" \
			'.assignments += [{agent:$a, role:"impl", branch:$b, worktree:$p, created:$ts}]' \
			--arg a "$agent" --arg b "$branch" --arg p "$path" --arg ts "$(now_iso)"
		emit_event task.assigned task="$task" agent="$agent" branch="$branch" worktree="$path"
		ok "$agent → $path (rama $branch)"
	done
}

_task_ls() {
	local all=""
	[[ "${1:-}" == "--all" ]] && all=1
	printf '%-6s %-8s %-40s %s\n' ID ESTADO TÍTULO AGENTES
	local id
	while IFS= read -r id; do
		[[ -z "$id" ]] && continue
		local st
		st="$(task_get "$id" .status)"
		[[ -z "$all" && "$st" != open ]] && continue
		printf '%-6s %-8s %-40.40s %s\n' "$id" "$st" "$(task_get "$id" .title)" \
			"$(task_get "$id" '[.assignments[].agent] | join(",")')"
	done < <(task_ids)
}

# Resumen de una asignación como JSON (lo usan show, gate y la TUI).
assign_summary_json() {
	local task="$1" agent="$2" sha wt base dirty="false" ahead=0
	sha="$(assign_sha "$task" "$agent" || true)"
	wt="$(assign_get "$task" "$agent" worktree)"
	base="$(task_get "$task" .base_sha)"
	if [[ -d "$wt" ]]; then git_is_clean "$wt" || dirty="true"; fi
	[[ -n "$sha" ]] && ahead="$(git rev-list --count "$base..$sha")"
	local run
	run="$(run_latest "$task" "$agent")"
	jq -n --arg agent "$agent" --arg sha "$sha" --arg wt "$wt" --argjson dirty "$dirty" \
		--argjson ahead "$ahead" --arg run "$run" \
		--arg runst "$([[ -n "$run" ]] && run_status "$run")" \
		--arg ver "$([[ -n "$sha" ]] && verify_status "$sha")" \
		--argjson reviews "$([[ -n "$sha" ]] && reviews_json "$sha" || echo '[]')" \
		--arg appr "$([[ -n "$sha" ]] && approval_exists "$sha" && echo yes)" \
		'{agent:$agent, sha:$sha, worktree:$wt, worktree_exists:($wt != ""), dirty:$dirty,
		  commits_ahead:$ahead, last_run:$run, last_run_status:$runst,
		  verification:$ver, reviews:$reviews, approved:($appr == "yes")}'
}

_task_show() {
	local task="" json=""
	while (($#)); do
		case "$1" in
		--json) json=1 ;;
		*) task="$1" ;;
		esac
		shift
	done
	require_task "${task:?uso: gitctl task show <tarea>}"
	if [[ -n "$json" ]]; then
		local a sums=()
		while IFS= read -r a; do sums+=("$(assign_summary_json "$task" "$a")"); done < <(assign_agents "$task")
		jq --argjson s "$(printf '%s\n' "${sums[@]}" | jq -s .)" '. + {summary:$s}' "$(task_file "$task")"
		return
	fi
	echo "Tarea $task: $(task_get "$task" .title)"
	echo "Estado: $(task_get "$task" .status) · base $(task_get "$task" .base_ref) @ $(git_short "$(task_get "$task" .base_sha)") · creada $(task_get "$task" .created)"
	echo
	local a
	while IFS= read -r a; do
		[[ -z "$a" ]] && continue
		local s
		s="$(assign_summary_json "$task" "$a")"
		echo "Agente $a  [$(jq -r '.sha[0:8]' <<<"$s")]  rama $(assign_get "$task" "$a" branch)"
		jq -r '"  worktree:     \(.worktree)\(if .dirty then "  (cambios sin commitear)" else "" end)",
		       "  commits:      \(.commits_ahead) desde la base",
		       "  último run:   \(if .last_run == "" then "-" else "\(.last_run) (\(.last_run_status))" end)",
		       "  verificación: \(if .verification == "" then "-" else .verification end)",
		       "  revisiones:   \(if (.reviews|length) == 0 then "-" else (.reviews | map("\(.reviewer)=\(.verdict)") | join(", ")) end)",
		       "  aprobación:   \(if .approved then "sí" else "no" end)"' <<<"$s"
		echo
	done < <(assign_agents "$task")
	[[ -n "$(assign_agents "$task")" ]] || info "sin agentes asignados (gitctl task assign $task <agente>)"
}

_task_close() {
	local task="${1:?uso: gitctl task close <tarea>}"
	require_task "$task"
	json_update "$(task_file "$task")" '.status = "closed" | .closed = $ts' --arg ts "$(now_iso)"
	emit_event task.closed task="$task"
	ok "tarea $task cerrada (ramas y worktrees se conservan; usa gitctl wt rm)"
}
