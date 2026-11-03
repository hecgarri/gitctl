# shellcheck shell=bash
# Preguntas al usuario: confirmaciones [s/N], listas numeradas y texto.
# Las preguntas y las listas van a stderr; nunca se pregunta con -SinInteraccion.

interactivo() { [[ -z "$P_SIN_INT" ]]; }

_trim() {
	local s="$1"
	s="${s#"${s%%[![:space:]]*}"}"
	s="${s%"${s##*[![:space:]]}"}"
	printf '%s' "$s"
}

# leer_linea "pregunta" → RESP. Devuelve 1 al llegar al final de la entrada.
leer_linea() {
	interactivo || die "error interno: se intentó preguntar con -SinInteraccion"
	printf '%s' "$1" >&2
	RESP=""
	if ! IFS= read -r RESP; then
		printf '\n' >&2
		return 1
	fi
	RESP="${RESP%$'\r'}"
	return 0
}

# confirmar "pregunta" → 0 solo si se responde «s» o «si». Vacío = no.
confirmar() {
	local r
	leer_linea "$1 [s/N]: " || return 1
	r="$(_trim "$RESP")"
	r="${r,,}"
	[[ "$r" == s || "$r" == si ]]
}

# elegir "pregunta" opción… → ELEGIDO (desde 1). Devuelve 1 si se cancela.
elegir() {
	local titulo="$1" i r
	shift
	local n=$#
	while :; do
		printf '\n%s\n' "$titulo" >&2
		for ((i = 1; i <= n; i++)); do
			printf '  [%d] %s\n' "$i" "${!i}" >&2
		done
		printf '  [0] Cancelar\n' >&2
		leer_linea "Opción: " || return 1
		r="$(_trim "$RESP")"
		[[ "$r" == 0 ]] && return 1
		if [[ "$r" =~ ^[0-9]+$ ]] && ((10#$r >= 1 && 10#$r <= n)); then
			ELEGIDO=$((10#$r))
			return 0
		fi
		warn "opción no válida: «$r»; escribe un número de la lista"
	done
}

# elegir_dos opción… → SEL1, SEL2 (desde 1, distintos). La lista y su
# numeración no cambian entre las dos preguntas.
elegir_dos() {
	local -a items=("$@")
	elegir "Elige la primera propuesta:" "${items[@]}" || return 1
	SEL1="$ELEGIDO"
	while :; do
		info "primera propuesta: ${items[SEL1 - 1]}"
		elegir "Elige la segunda propuesta:" "${items[@]}" || return 1
		if ((ELEGIDO != SEL1)); then
			SEL2="$ELEGIDO"
			return 0
		fi
		warn "esa ya es la primera propuesta; elige otra para la segunda"
	done
}

cancelado() { info "cancelado: no se ha modificado nada"; }

# Rellena con espacios hasta N caracteres (no bytes): pad <texto> <N>
pad() {
	local s="$1" n="$2"
	printf '%s' "$s"
	((n > ${#s})) && printf '%*s' $((n - ${#s})) ''
	return 0
}
