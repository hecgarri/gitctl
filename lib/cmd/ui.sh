# shellcheck shell=bash
# Menú interactivo. Usa fzf si está instalado; si no, el menú «select» de bash.
# Solo es una capa sobre los comandos: no contiene lógica propia.

_ui_pick() { # título opciones... → opción elegida
	local title="$1"
	shift
	if command -v fzf >/dev/null 2>&1; then
		printf '%s\n' "$@" | fzf --prompt="$title> " --height=40% --reverse --no-multi || true
	else
		local PS3="$title> " o
		select o in "$@"; do
			[[ -n "$o" ]] && {
				echo "$o"
				break
			}
		done
	fi
}

_ui_pick_task() {
	local ids=() id
	while IFS= read -r id; do
		[[ -n "$id" ]] && ids+=("$id  $(task_get "$id" .title)")
	done < <(task_ids)
	((${#ids[@]})) || {
		warn "no hay tareas"
		return 1
	}
	if command -v fzf >/dev/null 2>&1; then
		printf '%s\n' "${ids[@]}" | fzf --prompt="tarea> " --reverse \
			--preview "'$GITCTL_BIN' task show {1}" | awk '{print $1}'
	else
		_ui_pick tarea "${ids[@]}" | awk '{print $1}'
	fi
}

_ui_pick_agent() {
	local agents
	mapfile -t agents < <(assign_agents "$1")
	((${#agents[@]})) || {
		warn "la tarea $1 no tiene agentes"
		return 1
	}
	if ((${#agents[@]} == 1)); then echo "${agents[0]}"; else _ui_pick agente "${agents[@]}"; fi
}

# Agentes candidatos: los asignados a la tarea y los adaptadores, salvo «excluido».
_ui_agent_choice() {
	local task="$1" exclude="$2" c=() x
	if [[ -n "$task" ]]; then mapfile -t c < <(assign_agents "$task"); fi
	mapfile -t -O "${#c[@]}" c < <(adapter_list)
	local opts=()
	for x in "${c[@]}"; do
		[[ "$x" == "$exclude" || " ${opts[*]} " == *" $x "* ]] || opts+=("$x")
	done
	x="$(_ui_pick agente "${opts[@]}" "otro…")"
	[[ "$x" == "otro…" ]] && x="$(_ui_ask "Nombre del agente (p. ej. claude-opus)")"
	printf '%s' "$x"
}

_ui_ask() {
	local v
	read -r -p "$1: " v
	printf '%s' "$v"
}

cmd_ui() {
	[[ -t 0 && -t 1 ]] || {
		usage
		return
	}
	require_repo
	state_init
	local acts=(
		"Ver tarea" "Nueva tarea" "Asignar agente" "Lanzar agentes" "Estado de runs"
		"Ver log de run" "Verificar" "Revisión cruzada" "Corregir (fix)" "Aprobar"
		"Puerta (gate)" "Abrir PR" "Worktrees" "Abrir shell en worktree" "Doctor" "Salir"
	)
	while true; do
		local act t a r
		act="$(_ui_pick gitctl "${acts[@]}")"
		[[ -z "$act" || "$act" == Salir ]] && return 0
		# Cada acción se ejecuta en un subproceso: un error no cierra el menú.
		case "$act" in
		"Ver tarea") t="$(_ui_pick_task)" && "$GITCTL_BIN" task show "$t" ;;
		"Nueva tarea") t="$(_ui_ask "Título")" && [[ -n "$t" ]] && "$GITCTL_BIN" task new "$t" ;;
		"Asignar agente")
			t="$(_ui_pick_task)" && a="$(_ui_agent_choice "" "")" && [[ -n "$a" ]] &&
				"$GITCTL_BIN" task assign "$t" "$a"
			;;
		"Lanzar agentes") t="$(_ui_pick_task)" && "$GITCTL_BIN" run "$t" ;;
		"Estado de runs") "$GITCTL_BIN" run status ;;
		"Ver log de run") t="$(_ui_pick_task)" && a="$(_ui_pick_agent "$t")" && "$GITCTL_BIN" run logs "$t/$a" | "${PAGER:-less}" ;;
		"Verificar") t="$(_ui_pick_task)" && a="$(_ui_pick_agent "$t")" && "$GITCTL_BIN" verify "$t" "$a" ;;
		"Revisión cruzada")
			t="$(_ui_pick_task)" && a="$(_ui_pick_agent "$t")" &&
				r="$(_ui_agent_choice "$t" "$a")" && [[ -n "$r" ]] &&
				"$GITCTL_BIN" review "$t" "$a" --by "$r"
			;;
		"Corregir (fix)") t="$(_ui_pick_task)" && a="$(_ui_pick_agent "$t")" && "$GITCTL_BIN" fix "$t" "$a" ;;
		"Aprobar") t="$(_ui_pick_task)" && a="$(_ui_pick_agent "$t")" && "$GITCTL_BIN" approve "$t" "$a" ;;
		"Puerta (gate)") t="$(_ui_pick_task)" && a="$(_ui_pick_agent "$t")" && "$GITCTL_BIN" gate "$t" "$a" ;;
		"Abrir PR") t="$(_ui_pick_task)" && a="$(_ui_pick_agent "$t")" && "$GITCTL_BIN" pr open "$t" "$a" ;;
		"Worktrees") "$GITCTL_BIN" wt ls ;;
		"Abrir shell en worktree") t="$(_ui_pick_task)" && a="$(_ui_pick_agent "$t")" && "$GITCTL_BIN" wt open "$t/$a" ;;
		"Doctor") "$GITCTL_BIN" doctor ;;
		esac || true
		echo
		read -r -p "(Intro para continuar) " _ || return 0
	done
}
