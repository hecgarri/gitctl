# shellcheck shell=bash
# Paquete de revisión: el texto que se envía a los evaluadores LLM.

_gitp() { git -C "$REPO" -c core.quotePath=false -c color.ui=never --no-pager "$@"; }

# construir_paquete <base> <rama1> <rama2> <criterios> <archivo>
# → PAQ_BASE_SHA, PAQ_SHA1, PAQ_SHA2, PAQ_COMPACTO, PAQ_CHARS, PAQ_SHA256
construir_paquete() {
	local base="$1" r1="$2" r2="$3" crit="$4" out="$5" mb1 mb2
	PAQ_BASE_SHA="$(sha_de_rama "$base")"
	PAQ_SHA1="$(sha_de_rama "$r1")"
	PAQ_SHA2="$(sha_de_rama "$r2")"
	mb1="$(git -C "$REPO" merge-base "refs/heads/$base" "refs/heads/$r1")" || die "$r1 no tiene ancestro común con $base"
	mb2="$(git -C "$REPO" merge-base "refs/heads/$base" "refs/heads/$r2")" || die "$r2 no tiene ancestro común con $base"
	PAQ_COMPACTO=""
	[[ "$mb1" == "$mb2" ]] && PAQ_COMPACTO=1
	{
		echo "# Paquete de revisión de propuestas"
		echo
		echo "## Referencias"
		echo
		echo "- Base: $base @ $PAQ_BASE_SHA"
		echo "- Primera propuesta: $r1 @ $PAQ_SHA1 (merge-base con la base: $mb1)"
		echo "- Segunda propuesta: $r2 @ $PAQ_SHA2 (merge-base con la base: $mb2)"
		echo
		echo "## Instrucciones para el juez"
		echo
		cat <<'T'
- Compara las dos propuestas según los criterios de revisión de este paquete.
- Analiza exclusivamente el contenido de este paquete. No uses herramientas, no
  leas archivos adicionales y no modifiques nada.
- Evalúa la evidencia, las contradicciones entre propuestas, sus dependencias y
  sus riesgos.
- Distingue los conflictos textuales (las mismas líneas cambiadas de forma
  distinta) de las contradicciones semánticas (comportamientos incompatibles).
- Cita las ramas, los commits y los criterios presentes en el paquete. No
  inventes hechos que no aparezcan en él.
- No uses el volumen de cambios ni el número de hallazgos como medida de calidad.
- Un merge sin conflictos no demuestra consistencia semántica.
- Tu dictamen es consultivo: la autorización final la da una persona.
- Responde únicamente con el objeto JSON solicitado.
T
		echo
		echo "## Criterios de revisión"
		echo
		cat -- "$crit"
		echo
		echo "## Commits exclusivos entre propuestas"
		echo
		echo "(git log --left-right --cherry-pick --oneline $r1...$r2; «<» = primera, «>» = segunda)"
		echo
		_gitp log --left-right --cherry-pick --oneline --no-decorate "refs/heads/$r1...refs/heads/$r2"
		echo
		local n=1 r
		for r in "$r1" "$r2"; do
			echo "## Commits de la propuesta $n ($r) pendientes respecto de la base"
			echo
			_gitp log --reverse --format="%H %s" "refs/heads/$base..refs/heads/$r"
			echo
			n=$((n + 1))
		done
		n=1
		for r in "$r1" "$r2"; do
			echo "## Diff completo de la propuesta $n ($r) desde su merge-base"
			echo
			echo '```diff'
			_gitp diff --no-ext-diff --no-textconv --unified=30 "refs/heads/$base...refs/heads/$r"
			echo '```'
			echo
			n=$((n + 1))
		done
		echo "## Diferencias entre las propuestas"
		echo
		if [[ -n "$PAQ_COMPACTO" ]]; then
			echo "Ambas propuestas parten del mismo merge-base ($mb1). Para no duplicar los"
			echo "parches completos de arriba, aquí solo se incluye el resumen (--stat) de las"
			echo "diferencias entre sus árboles."
			echo
			_gitp diff --no-ext-diff --stat "refs/heads/$r1" "refs/heads/$r2"
		else
			echo "Las propuestas parten de merge-base distintos, así que se incluye el diff"
			echo "completo entre sus árboles (--unified=30)."
			echo
			echo '```diff'
			_gitp diff --no-ext-diff --no-textconv --unified=30 "refs/heads/$r1" "refs/heads/$r2"
			echo '```'
		fi
	} >"$out" || die "no se pudo construir el paquete de revisión"
	PAQ_CHARS="$(LC_ALL=C.UTF-8 wc -m <"$out" | tr -d ' ')"
	PAQ_SHA256="$(sha256sum "$out" | cut -d' ' -f1)"
}

# Detección heurística de secretos evidentes. No garantiza que no haya otros.
# detectar_secretos <archivo> → imprime «línea: patrón» y devuelve 0 si encuentra algo.
detectar_secretos() {
	local f="$1" hay=1 n
	local -a nombres=("clave privada" "asignación de credencial" "cadena de conexión con contraseña")
	local -a patrones=(
		'-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY-----'
		'(password|passwd|pwd|api[_-]?key|token|secret)["'"'"']?[[:space:]]*(:|=|:=|=>)[[:space:]]*("[^"]{4,}"|'"'"'[^'"'"']{4,}'"'"')'
		'password=[^;[:space:]"'"'"']{4,}'
	)
	for n in "${!patrones[@]}"; do
		local lineas
		lineas="$({ grep -n -i -E -o -e "${patrones[n]}" -- "$f" || true; } | cut -d: -f1 | sort -un | tr '\n' ' ')"
		if [[ -n "$lineas" ]]; then
			echo "  ${nombres[n]}: línea(s) ${lineas% } del paquete"
			hay=0
		fi
	done
	return "$hay"
}
