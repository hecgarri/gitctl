# shellcheck shell=bash
# Criterios de revisión: el archivo con lo que deben valorar los evaluadores.

# ¿El archivo tiene contenido significativo (alguna letra o número)?
_con_contenido() { [[ -f "$1" && -s "$1" ]] && grep -q '[[:alnum:]]' -- "$1"; }

# Resuelve una ruta de criterios: relativas, desde la raíz del repositorio.
_ruta_criterios() {
	local p="$1"
	[[ "$p" == /* ]] || p="$REPO/$p"
	canon "$p"
}

# obtener_criterios → CRITERIOS (ruta absoluta). Devuelve 1 si se cancela.
obtener_criterios() {
	if [[ -n "$P_CRITERIOS" ]]; then
		CRITERIOS="$(_ruta_criterios "$P_CRITERIOS")"
		[[ -f "$CRITERIOS" ]] || die "no existe el archivo de criterios: $CRITERIOS"
		_con_contenido "$CRITERIOS" || die "el archivo de criterios está vacío: $CRITERIOS"
		return 0
	fi
	interactivo || die "falta -CriteriosRevision (archivo con los criterios de evaluación)"
	cat >&2 <<'T'

Los criterios de revisión le dicen a los evaluadores qué debe cumplir la tarea:
objetivo, requisitos obligatorios, restricciones, pruebas esperadas y prioridades.
Sin ellos, el dictamen no tiene con qué comparar las propuestas.
T
	while :; do
		elegir "¿Cómo quieres aportar los criterios?" "Usar un archivo existente" "Redactar criterios ahora" || return 1
		if ((ELEGIDO == 1)); then
			local rc=0
			_criterios_archivo || rc=$?
			((rc == 0)) && return 0
			((rc == 2)) && return 1
		else
			_criterios_redactar
			return
		fi
	done
}

# Devuelve 0 con CRITERIOS, 1 para volver a elegir el método y 2 si se acaba la entrada.
_criterios_archivo() {
	local r
	while :; do
		leer_linea "Ruta del archivo de criterios (0 para volver): " || return 2
		r="$(_trim "$RESP")"
		[[ "$r" == 0 ]] && return 1
		if [[ "$r" =~ ^\"(.*)\"$ || "$r" =~ ^\'(.*)\'$ ]]; then r="${BASH_REMATCH[1]}"; fi
		if [[ -z "$r" ]]; then
			warn "escribe una ruta"
			continue
		fi
		r="$(_ruta_criterios "$r")"
		if [[ ! -f "$r" ]]; then
			warn "no existe el archivo: $r"
		elif ! _con_contenido "$r"; then
			warn "el archivo está vacío: $r"
		else
			CRITERIOS="$r"
			return 0
		fi
	done
}

_criterios_redactar() {
	local -a lineas=()
	local l t
	cat >&2 <<'T'

Escribe los criterios línea a línea (texto libre o listas con «-»).
  .fin       guarda y continúa
  .cancelar  descarta el borrador y cancela la evaluación
T
	while :; do
		leer_linea "> " || return 1
		l="$RESP"
		t="$(_trim "$l")"
		if [[ "$t" == .cancelar ]]; then
			info "borrador descartado"
			return 1
		fi
		if [[ "$t" == .fin ]]; then
			if grep -q '[[:alnum:]]' <<<"$(printf '%s\n' "${lineas[@]}")"; then break; fi
			warn "los criterios no tienen contenido todavía; escribe algo o .cancelar"
			continue
		fi
		lineas+=("$l")
	done
	local dir="$RAIZ/_criterios" id
	mkdir -p -- "$dir" || die "no se pudo crear $dir"
	id="$(_uuid)"
	CRITERIOS="$dir/$(date -u +%Y%m%dT%H%M%SZ)-$id.md"
	printf '%s\n' "${lineas[@]}" >"$CRITERIOS" || die "no se pudo guardar $CRITERIOS"
	ok "criterios guardados en $CRITERIOS"
}

_uuid() {
	if [[ -r /proc/sys/kernel/random/uuid ]]; then
		cat /proc/sys/kernel/random/uuid
	elif command -v uuidgen >/dev/null 2>&1; then
		uuidgen | tr '[:upper:]' '[:lower:]'
	else
		od -An -N16 -tx1 /dev/urandom | tr -d ' \n'
	fi
}
