# shellcheck shell=bash
# Selector para el menú interactivo: lista numerada (o fzf si está instalado).
#
# Convención: el valor elegido va a stdout; la lista y las preguntas, a stderr.
# Código 130 = el usuario canceló o quiere volver.

PICK_CANCELLED=130

# Backend: fzf si está disponible y hay terminal; GITCTL_PICKER=basic|fzf lo fuerza.
_pick_backend() {
	case "${GITCTL_PICKER:-auto}" in
	basic | fzf) printf '%s' "$GITCTL_PICKER" ;;
	*) if command -v fzf >/dev/null 2>&1 && [[ -t 0 && -t 2 ]]; then printf fzf; else printf basic; fi ;;
	esac
}

# pick "título" "valor<TAB>etiqueta"... → imprime el valor elegido.
# Sin TAB, el elemento es a la vez valor y etiqueta.
pick() {
	local title="$1" it
	shift
	(($#)) || return "$PICK_CANCELLED"
	local -a items=()
	for it in "$@"; do
		[[ "$it" == *$'\t'* ]] || it="$it"$'\t'"$it"
		items+=("$it")
	done
	if [[ "$(_pick_backend)" == fzf ]]; then
		_pick_fzf "$title" "${items[@]}"
	else
		_pick_basic "$title" "${items[@]}"
	fi
}

_pick_fzf() {
	local title="$1" sel
	shift
	sel="$(printf '%s\n' "$@" | fzf --delimiter=$'\t' --with-nth=2.. \
		--header="$title"$'\n'"Enter: elegir · Esc: volver · escribe para filtrar" \
		--height=~90% --layout=reverse --border=rounded --info=inline --cycle --no-multi)" ||
		return "$PICK_CANCELLED"
	printf '%s' "${sel%%$'\t'*}"
}

# Lista numerada. 0, q o Enter vacío = volver (PICK_ZERO cambia el texto del 0).
_pick_basic() {
	local title="$1" ans n it
	shift
	while true; do
		{
			printf '\n%s\n' "$title"
			n=0
			for it in "$@"; do
				n=$((n + 1))
				printf '  %d) %s\n' "$n" "${it#*$'\t'}"
			done
			printf '  0) %s\n' "${PICK_ZERO:-← Volver}"
		} >&2
		ans=""
		read -r -p "Opción: " ans || return "$PICK_CANCELLED"
		case "$ans" in
		"" | 0 | q | Q) return "$PICK_CANCELLED" ;;
		*[!0-9]*) echo "Escribe el número de una opción." >&2 ;;
		*)
			if ((ans >= 1 && ans <= $#)); then
				it="${!ans}"
				printf '%s' "${it%%$'\t'*}"
				return 0
			fi
			echo "No hay opción $ans." >&2
			;;
		esac
	done
}

# Espera a que el usuario pulse Enter (para que lea un resultado antes del menú).
pause() {
	is_interactive || return 0
	local _x
	read -r -p "(Enter para continuar) " _x || true
}
