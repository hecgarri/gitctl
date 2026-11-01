# shellcheck shell=bash
# Pull Requests en GitHub mediante gh. Nunca se fuerza un push ni se borra la rama.

_pr_help() {
	cat <<'EOF'
Uso: gitctl pr <acción>

  open <tarea> <agente> [--draft] [--remote R]
        Hace push de la rama (sin forzar) y crea el PR con el informe de
        evidencia. Requiere que la puerta pase, salvo --draft.
  status <tarea> <agente>
        Estado del PR: checks de GitHub Actions, revisión y si el commit
        remoto coincide con el evaluado localmente.
  merge <tarea> <agente> [--squash|--rebase]
        Fusiona solo si: la puerta pasa, el HEAD del PR es exactamente el
        commit evaluado y los checks de GitHub han pasado. Pide confirmación.
EOF
}

cmd_pr() {
	local action="${1:-}"
	[[ $# -gt 0 ]] && shift
	case "$action" in
	"" | -h | --help | help) _pr_help ;;
	open | create)
		state_init
		require_cmd gh
		_pr_open "$@"
		;;
	status | view)
		state_init
		require_cmd gh
		_pr_status "$@"
		;;
	merge)
		state_init
		require_cmd gh
		_pr_merge "$@"
		;;
	*) die "acción desconocida: pr $action (ver gitctl pr --help)" ;;
	esac
}

_pr_base() {
	local b
	b="$(task_get "$1" .base_ref)"
	printf '%s' "${b#origin/}"
}

_pr_body() {
	local task="$1" agent="$2" g="$3" sha
	sha="$(jq -r .sha <<<"$g")"
	echo "## Tarea $task: $(task_get "$task" .title)"
	echo
	cat "$(task_dir "$task")/spec.md"
	echo
	echo "## Puerta de integración (gitctl) — commit \`$sha\`"
	echo
	jq -r '.checks[] | "- \(if .status == "ok" then "✅" elif .status == "fail" then "❌" else "⚠️" end) **\(.name)**: \(.detail)"' <<<"$g"
	echo
	echo "### Evidencia (checks ejecutados por gitctl en una copia limpia)"
	local vf
	vf="$(verify_file "$sha")"
	if [[ -f "$vf" ]]; then
		echo
		echo "| check | comando | exit | duración |"
		echo "|---|---|---|---|"
		jq -r '.checks[] | "| \(.name) | `\(.cmd)` | \(.exit) | \(.duration)s |"' "$vf"
	else
		echo
		echo "_Sin verificar._"
	fi
	echo
	echo "### Revisiones (afirmaciones de agentes, no evidencia)"
	echo
	reviews_json "$sha" | jq -r 'if length == 0 then "_Ninguna._" else .[] | "- **\(.reviewer)**: \(.verdict) (\(.findings) observaciones)" end'
	echo
	echo "### Commits"
	echo
	git log --format='- `%h` %s (%an)' "$(task_get "$task" .base_sha)..$sha"
	echo
	echo "<sub>Generado por gitctl · agente autor: $agent</sub>"
}

_pr_args() { # tarea agente → asigna PR_TASK PR_AGENT y el resto en PR_REST
	PR_TASK="" PR_AGENT="" PR_REST=()
	while (($#)); do
		case "$1" in
		-*) PR_REST+=("$1") ;;
		*) if [[ -z "$PR_TASK" ]]; then PR_TASK="$1"; elif [[ -z "$PR_AGENT" ]]; then PR_AGENT="$1"; else PR_REST+=("$1"); fi ;;
		esac
		shift
	done
	[[ -n "$PR_AGENT" ]] || die "faltan <tarea> <agente> (ver gitctl pr --help)"
	require_assign "$PR_TASK" "$PR_AGENT"
}

_pr_open() {
	local draft="" remote="origin" x
	_pr_args "$@"
	local task="$PR_TASK" agent="$PR_AGENT"
	for ((x = 0; x < ${#PR_REST[@]}; x++)); do
		case "${PR_REST[x]}" in
		--draft) draft=1 ;;
		--remote)
			remote="${PR_REST[x + 1]:-}"
			x=$((x + 1))
			;;
		*) die "opción desconocida: ${PR_REST[x]}" ;;
		esac
	done
	git remote get-url "$remote" >/dev/null 2>&1 || die "no existe el remoto «$remote»"
	local g branch body
	g="$(gate_eval "$task" "$agent")"
	if [[ "$(jq -r .pass <<<"$g")" != true ]]; then
		_gate_print "$g"
		[[ -n "$draft" ]] || die "la puerta no pasa; corrige lo anterior o abre un borrador con --draft"
		warn "la puerta no pasa: se abre como borrador"
	fi
	branch="$(assign_get "$task" "$agent" branch)"
	info "push de $branch a $remote (sin forzar)…"
	git push -u "$remote" "refs/heads/$branch:refs/heads/$branch" || die "falló el push (no se fuerza nunca)"
	body="$(state_dir)/tmp/pr-$task-$agent.md"
	_pr_body "$task" "$agent" "$g" >"$body"
	local args=(--base "$(_pr_base "$task")" --head "$branch" --title "[$task] $(task_get "$task" .title)" --body-file "$body")
	[[ -n "$draft" ]] && args+=(--draft)
	local url
	url="$(gh pr create "${args[@]}")" || die "gh no pudo crear el PR"
	rm -f "$body"
	json_update "$(task_file "$task")" '(.assignments[] | select(.agent == $a)) |= . + {pr:$u}' --arg a "$agent" --arg u "$url"
	emit_event pr.opened task="$task" agent="$agent" sha="$(jq -r .sha <<<"$g")" url="$url"
	ok "PR: $url"
}

_pr_view() { gh pr view "$(assign_get "$1" "$2" branch)" --json url,state,isDraft,headRefOid,reviewDecision,mergeable,statusCheckRollup; }

# ok | pending | fail | none según statusCheckRollup
_pr_ci_state() {
	jq -r '.statusCheckRollup // [] |
		if length == 0 then "none"
		elif any(.[]; (.conclusion // .state // "") | ascii_upcase | IN("FAILURE","ERROR","CANCELLED","TIMED_OUT","ACTION_REQUIRED")) then "fail"
		elif any(.[]; ((.status // "COMPLETED") | ascii_upcase) != "COMPLETED" or ((.state // "") | ascii_upcase) == "PENDING") then "pending"
		else "ok" end' <<<"$1"
}

_pr_status() {
	_pr_args "$@"
	local v sha
	v="$(_pr_view "$PR_TASK" "$PR_AGENT")" || die "no hay PR para $PR_TASK/$PR_AGENT"
	sha="$(assign_sha "$PR_TASK" "$PR_AGENT")"
	jq -r '"PR:        \(.url)", "Estado:    \(.state)\(if .isDraft then " (borrador)" else "" end)",
	       "Revisión:  \(.reviewDecision // "-")", "Fusionable: \(.mergeable)"' <<<"$v"
	echo "CI:        $(_pr_ci_state "$v")"
	if [[ "$(jq -r .headRefOid <<<"$v")" == "$sha" ]]; then
		mark ok "el HEAD remoto coincide con el commit local $(git_short "$sha")"
	else
		mark warn "el HEAD remoto ($(jq -r '.headRefOid[0:8]' <<<"$v")) difiere del local ($(git_short "$sha"))"
	fi
}

_pr_merge() {
	local method=--merge x
	_pr_args "$@"
	local task="$PR_TASK" agent="$PR_AGENT"
	for x in "${PR_REST[@]}"; do
		case "$x" in
		--squash | --rebase | --merge) method="$x" ;;
		*) die "opción desconocida: $x" ;;
		esac
	done
	local g sha v ci
	g="$(gate_eval "$task" "$agent")"
	sha="$(jq -r .sha <<<"$g")"
	_gate_print "$g"
	[[ "$(jq -r .pass <<<"$g")" == true ]] || die "la puerta no pasa"
	v="$(_pr_view "$task" "$agent")" || die "no hay PR para $task/$agent (gitctl pr open)"
	[[ "$(jq -r .headRefOid <<<"$v")" == "$sha" ]] || die "el HEAD del PR no es el commit evaluado ($(git_short "$sha")); haz push o vuelve a evaluar"
	[[ "$(jq -r .isDraft <<<"$v")" == false ]] || die "el PR es un borrador (gh pr ready)"
	ci="$(_pr_ci_state "$v")"
	case "$ci" in
	ok) mark ok "CI de GitHub en verde" ;;
	none) mark warn "el PR no tiene checks de CI" ;;
	*) die "CI de GitHub: $ci" ;;
	esac
	confirm "¿Fusionar $(jq -r .url <<<"$v") ($method)?" || die "cancelado"
	gh pr merge "$(jq -r .url <<<"$v")" "$method" --match-head-commit "$sha" || die "gh no pudo fusionar"
	emit_event pr.merged task="$task" agent="$agent" sha="$sha"
	ok "fusionado (la rama se conserva)"
}
