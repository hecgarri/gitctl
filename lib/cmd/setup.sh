# shellcheck shell=bash
# init, doctor y log.

_conf_example() {
	cat <<'EOF'
# Configuración de gitctl para este repositorio («clave = valor»).
# Se lee SIEMPRE del worktree principal: los agentes no pueden cambiarla desde su rama.

# Rama base para nuevas tareas (por defecto: origin/HEAD o la rama actual).
# base = main

# Dónde crear los worktrees (por defecto: ../<repo>.wt).
# wt_root = ~/worktrees/mi-repo

# Checks que constituyen la EVIDENCIA. Se ejecutan, en orden, en una copia limpia
# del commit exacto. Ningún check definido = no hay evidencia = la puerta no pasa.
# check.test = make test
# check.lint = shellcheck **/*.sh

# Límites de tiempo.
# agent.timeout = 30m
# verify.timeout = 30m
# review.timeout = 20m

# Revisión y puerta de integración.
# review.required = 1
# review.require_different_adapter = false
# gate.require_approval = true
# gate.protected = .gitctl.conf .github/workflows/*

# Argumentos extra por agente/adaptador y modo (implement|review).
# agent.claude.implement.args = --allowedTools Bash(make test:*)
# agent.claude-opus.args = --model opus
# agent.codex.args = --model gpt-5-codex
EOF
}

cmd_init() {
	if want_help "$@"; then
		echo "Uso: gitctl init   — crea el estado en .git/gitctl y un .gitctl.conf de ejemplo"
		return
	fi
	state_init
	local main conf
	main="$(git_main_root)"
	conf="$main/.gitctl.conf"
	if [[ -f "$conf" ]]; then
		info "ya existe $conf (no se modifica)"
	else
		_conf_example >"$conf"
		ok "creado $conf — define al menos un check.* y añádelo al repositorio"
	fi
	ok "estado en $(state_dir)"
	info "worktrees en $(wt_root)"
	emit_event init
}

_doc_line() { # nombre obligatorio(1/0) descripción
	local name="$1" required="$2" desc="$3" v
	if command -v "$name" >/dev/null 2>&1; then
		v="$("$name" --version 2>/dev/null | head -1 || true)"
		mark ok "$name ${v:+— $v}"
	elif [[ "$required" == 1 ]]; then
		mark fail "$name — OBLIGATORIO: $desc"
		return 1
	else
		mark warn "$name — opcional: $desc"
	fi
}

cmd_doctor() {
	if want_help "$@"; then
		echo "Uso: gitctl doctor   — comprueba dependencias, repositorio y agentes"
		return
	fi
	local bad=0
	echo "Herramientas:"
	_doc_line git 1 "control de versiones" || bad=1
	if command -v git >/dev/null && ! git_version_ok; then
		mark fail "git >= 2.38 necesario (merge-tree --write-tree)"
		bad=1
	fi
	_doc_line jq 1 "estado JSON (apt install jq)" || bad=1
	_doc_line flock 1 "cerrojos (util-linux)" || bad=1
	_doc_line timeout 1 "límites de tiempo (coreutils)" || bad=1
	_doc_line gh 0 "Pull Requests y GitHub (apt install gh)"
	_doc_line fzf 0 "menú interactivo (apt install fzf)"
	if command -v gh >/dev/null 2>&1; then
		if gh auth status >/dev/null 2>&1; then mark ok "gh autenticado"; else mark warn "gh sin autenticar (gh auth login)"; fi
	fi
	echo "Agentes:"
	local a
	while IFS= read -r a; do
		[[ "$a" == fake ]] && continue
		if "adapter_${a}_available"; then mark ok "$a"; else mark warn "$a — no instalado"; fi
	done < <(adapter_list)
	echo "Repositorio:"
	if in_git_repo; then
		mark ok "$(git_main_root)"
		if [[ -d "$(git_common_dir)/gitctl" ]]; then mark ok "estado inicializado"; else mark warn "sin inicializar (gitctl init)"; fi
		cfg_load
		if ((${#GITCTL_CHECKS[@]})); then
			mark ok "checks: ${GITCTL_CHECKS[*]}"
		else
			mark warn "no hay checks definidos en .gitctl.conf: no habrá evidencia"
		fi
	else
		mark skip "no estás en un repositorio Git"
	fi
	return "$bad"
}

cmd_log() {
	if want_help "$@"; then
		echo "Uso: gitctl log [tarea] [-n N] [--json]   — historial de eventos"
		return
	fi
	state_init
	local task="" n=50 json=""
	while (($#)); do
		case "$1" in
		-n)
			need_arg "$@"
			n="$2"
			shift
			;;
		--json) json=1 ;;
		*) task="$1" ;;
		esac
		shift
	done
	local f
	f="$(state_dir)/events.jsonl"
	local sel='select($t == "" or .task == $t)'
	if [[ -n "$json" ]]; then
		jq -c --arg t "$task" "$sel" "$f" | tail -n "$n"
	else
		jq -r --arg t "$task" "$sel"' | [.ts, .type, (del(.ts,.type,.user) | to_entries | map("\(.key)=\(.value)") | join(" "))] | @tsv' "$f" |
			tail -n "$n" | column -t -s $'\t'
	fi
}
