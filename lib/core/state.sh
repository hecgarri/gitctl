# shellcheck shell=bash
# Estado de gitctl en <git-common-dir>/gitctl (compartido entre worktrees,
# nunca versionado). JSON con jq, escrituras atómicas y bloqueo con flock.
#
#   tasks/<id>/task.json, spec.md
#   runs/<run-id>/meta.json, prompt.md, output.log, result.md
#   verifications/<sha>.json, verifications/<sha>/<check>.log
#   reviews/<sha>/<revisor>.json, .md
#   approvals/<sha>.json
#   events.jsonl

state_dir() {
	if [[ -z "${_GITCTL_STATE:-}" ]]; then
		_GITCTL_STATE="$(git_common_dir)/gitctl"
	fi
	printf '%s' "$_GITCTL_STATE"
}

state_init() {
	require_repo
	require_cmd jq flock
	local sd
	sd="$(state_dir)"
	mkdir -p "$sd"/{tasks,runs,verifications,reviews,approvals,tmp,locks}
	[[ -f "$sd/events.jsonl" ]] || : >"$sd/events.jsonl"
}

# Directorio raíz donde se crean los worktrees (fuera del repo).
wt_root() {
	local r
	r="$(cfg wt_root)"
	if [[ -z "$r" ]]; then
		local main
		main="$(git_main_root)"
		r="$(dirname "$main")/$(basename "$main").wt"
	fi
	r="${r/#\~/$HOME}"
	printf '%s' "$r"
}

# with_lock <nombre> cmd args... — ejecuta bajo un cerrojo exclusivo.
with_lock() {
	local name="$1" fd rc=0
	shift
	exec {fd}>"$(state_dir)/locks/$name.lock"
	flock -w 60 "$fd" || die "no se pudo obtener el cerrojo «$name»"
	"$@" || rc=$?
	exec {fd}>&-
	return "$rc"
}

# json_update <fichero> <filtro jq> [args jq...] — modifica un JSON con cerrojo.
_json_update_unlocked() {
	local file="$1" filter="$2"
	shift 2
	local out
	out="$(jq "$@" "$filter" "$file")" || die "no se pudo actualizar $file"
	printf '%s\n' "$out" | atomic_write "$file"
}
json_update() { with_lock state _json_update_unlocked "$@"; }

# emit_event <tipo> [clave=valor...] — registro append-only.
emit_event() {
	local type="$1"
	shift
	local args=(--arg ts "$(now_iso)" --arg type "$type" --arg user "${USER:-?}")
	local filter='{ts:$ts,type:$type,user:$user}' kv k i=0
	for kv in "$@"; do
		k="${kv%%=*}"
		args+=(--arg "v$i" "${kv#*=}")
		filter+=" + {\"$k\": \$v$i}"
		i=$((i + 1))
	done
	jq -cn "${args[@]}" "$filter" >>"$(state_dir)/events.jsonl"
}

# ---------- tareas ----------

task_dir() { printf '%s/tasks/%s' "$(state_dir)" "$1"; }
task_file() { printf '%s/task.json' "$(task_dir "$1")"; }
task_exists() { [[ -f "$(task_file "$1")" ]]; }
require_task() {
	check_name "id de tarea" "$1"
	task_exists "$1" || die "no existe la tarea «$1» (ver gitctl task ls)"
}
task_get() { jq -r "$2" "$(task_file "$1")"; }
task_ids() {
	local d
	for d in "$(state_dir)"/tasks/*/task.json; do
		[[ -f "$d" ]] || continue
		basename "$(dirname "$d")"
	done | sort -V
}

# Asignación de un agente a una tarea: assign_get <tarea> <agente> <campo>
assign_get() {
	jq -r --arg a "$2" --arg f "$3" \
		'(.assignments[] | select(.agent == $a) | .[$f]) // empty' "$(task_file "$1")"
}
assign_exists() { [[ -n "$(assign_get "$1" "$2" agent)" ]]; }
require_assign() {
	require_task "$1"
	check_name "agente" "$2"
	assign_exists "$1" "$2" || die "el agente «$2» no está asignado a la tarea «$1»"
}
assign_agents() { jq -r '.assignments[].agent' "$(task_file "$1")"; }

# SHA actual de la rama de una asignación (la huella que se verifica/revisa).
assign_sha() { git_ref_sha "refs/heads/$(assign_get "$1" "$2" branch)"; }
