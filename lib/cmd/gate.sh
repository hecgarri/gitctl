# shellcheck shell=bash
# Aprobación humana y puerta de integración. Todo se evalúa sobre el SHA actual
# de la rama del agente: si cambia, la evidencia y las revisiones anteriores no
# cuentan.

approval_file() { printf '%s/approvals/%s.json' "$(state_dir)" "$1"; }
approval_exists() { [[ -f "$(approval_file "$1")" ]]; }

_approve_help() {
	cat <<'EOF'
Uso: gitctl approve <tarea> <agente> [--note TEXTO] [--yes]

Registra tu aprobación humana del commit actual de la rama del agente. Pide
confirmación interactiva; --yes (en este comando) la omite para uso explícito en
scripts. Se rechaza dentro de un run de agente.
Nota: es un registro de intención humana, no una barrera de seguridad frente a
un agente con acceso libre a la shell.
EOF
}

_approver() {
	local n e
	n="$(git config user.name || echo "${USER:-desconocido}")"
	e="$(git config user.email || true)"
	printf "%s%s" "$n" "${e:+ <$e>}"
}

cmd_approve() {
	local task="" agent="" note="" yes=""
	while (($#)); do
		case "$1" in
		--note)
			need_arg "$@"
			note="$2"
			shift
			;;
		--yes) yes=1 ;;
		-h | --help)
			_approve_help
			return
			;;
		-*) die "opción desconocida: $1" ;;
		*) if [[ -z "$task" ]]; then task="$1"; else agent="$1"; fi ;;
		esac
		shift
	done
	state_init
	[[ -n "$agent" ]] || die "uso: gitctl approve <tarea> <agente>"
	[[ -z "${GITCTL_RUN_ID:-}" ]] || die "la aprobación debe darla una persona, no un agente"
	require_assign "$task" "$agent"
	local sha
	sha="$(assign_sha "$task" "$agent")"
	echo "Commit $(git_short "$sha") de $task/$agent:"
	git log --format='  %h %s (%an)' "$(task_get "$task" .base_sha)..$sha"
	echo "Verificación: $(verify_status "$sha")"
	echo "Revisiones:   $(reviews_json "$sha" | jq -r 'map("\(.reviewer)=\(.verdict)") | join(", ") | if . == "" then "-" else . end')"
	if [[ -z "$yes" ]]; then
		[[ -t 0 ]] || die "la aprobación requiere confirmación interactiva (o --yes explícito en approve)"
		local ans
		read -r -p "¿Apruebas este commit para integrarlo? [s/N] " ans
		[[ "$ans" =~ ^[sSyY]$ ]] || die "no aprobado"
	fi
	jq -n --arg sha "$sha" --arg t "$task" --arg a "$agent" --arg ts "$(now_iso)" \
		--arg by "$(_approver)" \
		--arg note "$note" --argjson inter "$([[ -z "$yes" ]] && echo true || echo false)" \
		'{sha:$sha, task:$t, agent:$a, kind:"human_approval", by:$by, note:$note, interactive:$inter, at:$ts}' |
		atomic_write "$(approval_file "$sha")"
	emit_event approve task="$task" agent="$agent" sha="$sha"
	ok "aprobado $(git_short "$sha")"
}

# Evalúa la puerta y emite JSON: {sha, pass, checks:[{name,status,detail}]}
gate_eval() {
	local task="$1" agent="$2" sha base base_ref base_now out=()
	sha="$(assign_sha "$task" "$agent")"
	base="$(task_get "$task" .base_sha)"
	base_ref="$(task_get "$task" .base_ref)"
	_g() { out+=("$(jq -cn --arg n "$1" --arg s "$2" --arg d "$3" '{name:$n,status:$s,detail:$d}')"); }

	local ahead
	ahead="$(git rev-list --count "$base..$sha")"
	if ((ahead > 0)); then _g commits ok "$ahead commit(s) sobre la base"; else _g commits fail "no hay commits que integrar"; fi

	if run_active "$task" "$agent"; then _g run fail "hay un run en curso"; else _g run ok "sin runs en curso"; fi

	local wt
	wt="$(assign_get "$task" "$agent" worktree)"
	if [[ -d "$wt" ]] && ! git_is_clean "$wt"; then
		_g worktree warn "hay cambios sin commitear que no se integrarán"
	else
		_g worktree ok "limpio"
	fi

	case "$(verify_status "$sha")" in
	pass) _g evidencia ok "todos los checks pasan en $(git_short "$sha")" ;;
	fail) _g evidencia fail "hay checks que fallan en $(git_short "$sha")" ;;
	caducada) _g evidencia fail "los checks cambiaron desde la verificación; repite gitctl verify" ;;
	*) _g evidencia fail "sin verificar en $(git_short "$sha") (gitctl verify $task $agent)" ;;
	esac

	local required approvers changes invalid diffad
	required="$(cfg review.required)"
	diffad=""
	if cfg_bool review.require_different_adapter; then diffad=1; fi
	approvers=() changes=() invalid=()
	local rf rv
	for rf in "$(reviews_dir "$sha")"/*.json; do
		[[ -f "$rf" ]] || continue
		rv="$(jq -r .reviewer "$rf")"
		[[ "$rv" == "$agent" ]] && continue
		[[ -n "$diffad" && "$(adapter_of "$rv")" == "$(adapter_of "$agent")" ]] && continue
		case "$(jq -r .verdict "$rf")" in
		approve) approvers+=("$rv") ;;
		request_changes) changes+=("$rv") ;;
		*) invalid+=("$rv") ;;
		esac
	done
	if ((${#changes[@]})); then
		_g revision fail "cambios solicitados por: ${changes[*]}"
	elif ((${#approvers[@]} >= required)); then
		_g revision ok "aprobada por: ${approvers[*]:-ninguno requerido}"
	else
		_g revision fail "${#approvers[@]}/$required revisiones aprobatorias de otros agentes"
	fi
	((${#invalid[@]})) && _g revision-invalida warn "revisiones inválidas (no cuentan): ${invalid[*]}"

	if cfg_bool gate.require_approval true; then
		if approval_exists "$sha"; then
			_g aprobacion ok "aprobado por $(jq -r .by "$(approval_file "$sha")")"
		else
			_g aprobacion fail "falta aprobación humana (gitctl approve $task $agent)"
		fi
	fi

	base_now="$(git_ref_sha "$base_ref" || true)"
	if [[ -z "$base_now" ]]; then
		_g conflictos warn "no se encuentra la base $base_ref"
	else
		local conflicts rc=0
		conflicts="$(git_merge_check "$base_now" "$sha")" || rc=$?
		case "$rc" in
		0) _g conflictos ok "se fusiona limpiamente con $base_ref" ;;
		1) _g conflictos fail "conflictos con $base_ref en: $(echo "$conflicts" | sort -u | tr '\n' ' ')" ;;
		*) _g conflictos warn "no se pudo comprobar: $conflicts" ;;
		esac
		if [[ "$base_now" != "$base" ]] && ! git merge-base --is-ancestor "$base_now" "$sha"; then
			_g base warn "$base_ref avanzó desde la creación de la tarea: la evidencia no cubre el resultado de la fusión"
		fi
	fi

	local pat touched=()
	read -ra pat <<<"$(cfg gate.protected)"
	if ((${#pat[@]})); then
		mapfile -t touched < <(git diff --name-only "$base" "$sha" -- "${pat[@]/#/:(glob)}")
		((${#touched[@]})) && _g protegidos warn "modifica ficheros protegidos: ${touched[*]}"
	fi

	printf '%s\n' "${out[@]}" | jq -s --arg sha "$sha" --arg t "$task" --arg a "$agent" \
		'{task:$t, agent:$a, sha:$sha, pass:(map(select(.status == "fail")) | length == 0), checks:.}'
}

_gate_print() {
	jq -r '.checks[] | "\(.status)\t\(.name): \(.detail)"' <<<"$1" | while IFS=$'\t' read -r st line; do
		mark "$st" "$line"
	done
}

cmd_gate() {
	local task="" agent="" json=""
	while (($#)); do
		case "$1" in
		--json) json=1 ;;
		-h | --help)
			echo "Uso: gitctl gate <tarea> <agente> [--json]   — ¿puede integrarse el commit actual?"
			return
			;;
		-*) die "opción desconocida: $1" ;;
		*) if [[ -z "$task" ]]; then task="$1"; else agent="$1"; fi ;;
		esac
		shift
	done
	state_init
	[[ -n "$agent" ]] || die "uso: gitctl gate <tarea> <agente>"
	require_assign "$task" "$agent"
	local g
	g="$(gate_eval "$task" "$agent")"
	emit_event gate task="$task" agent="$agent" sha="$(jq -r .sha <<<"$g")" pass="$(jq -r .pass <<<"$g")"
	if [[ -n "$json" ]]; then
		echo "$g"
	else
		echo "Puerta de integración · $task/$agent @ $(git_short "$(jq -r .sha <<<"$g")")"
		_gate_print "$g"
	fi
	if [[ "$(jq -r .pass <<<"$g")" == true ]]; then
		[[ -n "$json" ]] || ok "puede integrarse"
	else
		[[ -n "$json" ]] || err "la puerta no pasa"
		return 1
	fi
}
