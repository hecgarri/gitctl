# shellcheck shell=bash
# Revisión cruzada: otro agente revisa, en solo lectura, el commit exacto del
# autor. Su veredicto es una AFIRMACIÓN (claim), nunca evidencia.

_review_help() {
	cat <<'EOF'
Uso: gitctl review <tarea> <autor> --by <revisor> [--timeout DUR]

El revisor (un agente distinto del autor) recibe la especificación, el diff, el
historial y los resultados medidos de los checks, y trabaja en una copia
desacoplada y de solo lectura del commit. Debe terminar con un bloque JSON
{"verdict": "approve"|"request_changes", "findings": [...]}; si no, la revisión
se registra como «invalid». Si el revisor modifica ficheros, también.
EOF
}

reviews_dir() { printf '%s/reviews/%s' "$(state_dir)" "$1"; }

reviews_json() {
	local d f
	d="$(reviews_dir "$1")"
	for f in "$d"/*.json; do
		[[ -f "$f" ]] || continue
		cat "$f"
	done |
		jq -sc 'map({reviewer, author, verdict, at, findings: (.findings | length)})'
}

# Extrae el último bloque ```json del mensaje del revisor y lo valida.
_review_parse() {
	local file="$1" block
	block="$(awk '/^[[:space:]]*```json[[:space:]]*$/{inb=1; buf=""; next}
		inb && /^[[:space:]]*```[[:space:]]*$/{inb=0; last=buf; next}
		inb{buf = buf $0 "\n"}
		END{printf "%s", last}' "$file")"
	if [[ -z "$block" ]]; then
		block="$(grep -E '^\{.*"verdict"' "$file" | tail -n1 || true)"
	fi
	jq -ce '
		select(type == "object" and (.verdict == "approve" or .verdict == "request_changes"))
		| {verdict, findings: ((.findings // []) | if type == "array" then . else [] end)}' \
		<<<"$block" 2>/dev/null
}

_review_prompt() {
	local task="$1" author="$2" reviewer="$3" sha="$4" base="$5" tpl max diff total ver
	tpl="$(cat "$GITCTL_LIB/prompts/review.md")"
	max="$(cfg review.max_diff_lines)"
	total="$(git diff "$base" "$sha" | wc -l)"
	diff="$(git diff "$base" "$sha" | head -n "$max")"
	if ((total > max)); then
		diff+=$'\n'"[… diff truncado: $total líneas en total. Usa git diff $base $sha -- <ruta> para ver el resto.]"
	fi
	local vf
	vf="$(verify_file "$sha")"
	if [[ -f "$vf" ]]; then
		ver="$(jq -r '"Resultado global: \(.result)\n" + (.checks | map("- \(.name) (`\(.cmd)`): exit \(.exit)") | join("\n"))' "$vf")"
		[[ "$(verify_status "$sha")" == caducada ]] && ver+=$'\n(Aviso: los checks se han redefinido desde esta verificación.)'
	else
		ver="No se ha ejecutado ninguna verificación sobre este commit. No hay evidencia de que los tests pasen."
	fi
	tpl="$(template_sub "$tpl" REVIEWER "$reviewer")"
	tpl="$(template_sub "$tpl" AUTHOR "$author")"
	tpl="$(template_sub "$tpl" TASK "$task")"
	tpl="$(template_sub "$tpl" TITLE "$(task_get "$task" .title)")"
	tpl="$(template_sub "$tpl" SHA "$sha")"
	tpl="$(template_sub "$tpl" BASE "$base")"
	tpl="$(template_sub "$tpl" SPEC "$(cat "$(task_dir "$task")/spec.md")")"
	tpl="$(template_sub "$tpl" VERIFICATION "$ver")"
	tpl="$(template_sub "$tpl" LOG "$(git log --format='- %h %s (%an)' "$base..$sha")")"
	tpl="$(template_sub "$tpl" DIFFSTAT "$(git diff --stat "$base" "$sha")")"
	tpl="$(template_sub "$tpl" DIFF "$diff")"
	printf '%s\n' "$tpl"
}

cmd_review() {
	want_help "$@" && {
		_review_help
		return
	}
	state_init
	local task="" author="" reviewer="" timeout=""
	while (($#)); do
		case "$1" in
		--by)
			need_arg "$@"
			reviewer="$2"
			shift
			;;
		--timeout)
			need_arg "$@"
			timeout="$2"
			shift
			;;
		-*) die "opción desconocida: $1" ;;
		*) if [[ -z "$task" ]]; then task="$1"; else author="$1"; fi ;;
		esac
		shift
	done
	[[ -n "$author" && -n "$reviewer" ]] || die "uso: gitctl review <tarea> <autor> --by <revisor>"
	require_assign "$task" "$author"
	require_agent "$reviewer"
	[[ "$reviewer" == "$author" ]] && die "un agente no puede revisar su propio trabajo"
	if [[ "$(adapter_of "$reviewer")" == "$(adapter_of "$author")" ]]; then
		if cfg_bool review.require_different_adapter; then
			die "review.require_different_adapter: $reviewer y $author usan el mismo adaptador"
		fi
		warn "$reviewer y $author usan el mismo modelo/adaptador: la independencia de la revisión es limitada"
	fi

	local sha base
	sha="$(assign_sha "$task" "$author")"
	base="$(task_get "$task" .base_sha)"
	[[ "$sha" == "$base" ]] && die "$author no tiene commits en $task; no hay nada que revisar"
	run_active "$task" "$author" && warn "hay un run en curso de $author; se revisa el commit actual $(git_short "$sha")"

	local rd tmp to rc=0
	rd="$(reviews_dir "$sha")"
	mkdir -p "$rd"
	to="${timeout:-$(cfg review.timeout)}"
	_review_prompt "$task" "$author" "$reviewer" "$sha" "$base" >"$rd/$reviewer.prompt.md"
	: >"$rd/$reviewer.log"
	: >"$rd/$reviewer.md"
	tmp="$(wt_ephemeral "$sha" review)"
	info "$reviewer revisa $(git_short "$sha") de $author (solo lectura, límite $to)…"
	emit_event review.started task="$task" author="$author" reviewer="$reviewer" sha="$sha"
	GITCTL_TASK="$task" GITCTL_AGENT="$reviewer" \
		agent_invoke "$reviewer" review "$tmp" "$rd/$reviewer.prompt.md" "$rd/$reviewer.log" "$rd/$reviewer.md" "$to" || rc=$?

	local parsed verdict note=""
	if ! git_is_clean "$tmp"; then
		verdict=invalid
		note="el revisor modificó ficheros en la copia de solo lectura"
		parsed='{"findings":[]}'
	elif ((rc != 0)); then
		verdict=invalid
		note="el revisor terminó con código $rc"
		parsed='{"findings":[]}'
	elif parsed="$(_review_parse "$rd/$reviewer.md")"; then
		verdict="$(jq -r .verdict <<<"$parsed")"
	else
		verdict=invalid
		note="respuesta sin bloque JSON de veredicto válido"
		parsed='{"findings":[]}'
	fi
	wt_ephemeral_rm "$tmp"

	jq -n --arg sha "$sha" --arg t "$task" --arg au "$author" --arg rv "$reviewer" \
		--arg v "$verdict" --arg note "$note" --arg ts "$(now_iso)" --argjson rc "$rc" \
		--argjson p "$parsed" \
		'{sha:$sha, task:$t, author:$au, reviewer:$rv, kind:"claim", verdict:$v,
		  findings:$p.findings, exit:$rc, note:$note, at:$ts}' |
		atomic_write "$rd/$reviewer.json"
	emit_event review.done task="$task" author="$author" reviewer="$reviewer" sha="$sha" verdict="$verdict"

	case "$verdict" in
	approve) ok "$reviewer aprueba $(git_short "$sha") (afirmación; $(jq '.findings|length' <<<"$parsed") observaciones)" ;;
	request_changes)
		warn "$reviewer pide cambios en $(git_short "$sha"):"
		jq -r '.findings[]? | "  - [\(.severity // "?")] \(.file // "?"): \(.summary // .)"' <<<"$parsed" >&2
		info "siguiente paso: gitctl fix $task $author"
		;;
	*)
		err "revisión inválida: $note (log: $rd/$reviewer.log)"
		return 1
		;;
	esac
}
