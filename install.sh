#!/usr/bin/env bash
# Instala gitctl enlazando bin/gitctl en <prefijo>/bin (por defecto ~/.local).
set -euo pipefail

prefix="$HOME/.local"
uninstall=""
while (($#)); do
	case "$1" in
	--prefix)
		prefix="${2:?falta el prefijo}"
		shift
		;;
	--uninstall) uninstall=1 ;;
	-h | --help)
		echo "Uso: ./install.sh [--prefix DIR] [--uninstall]"
		exit 0
		;;
	*)
		echo "opción desconocida: $1" >&2
		exit 1
		;;
	esac
	shift
done

src="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/bin/gitctl"
# gestionar_worktrees: el mismo nombre que el script de Windows.
nombres=(gitctl gestionar_worktrees)

if [[ -n "$uninstall" ]]; then
	for n in "${nombres[@]}"; do
		dest="$prefix/bin/$n"
		if [[ -L "$dest" && "$(readlink -f "$dest")" == "$src" ]]; then
			rm -f "$dest"
			echo "eliminado $dest"
		elif [[ -e "$dest" || -L "$dest" ]]; then
			echo "$dest no es un enlace a esta copia de gitctl; no se toca" >&2
		fi
	done
	exit 0
fi

mkdir -p "$prefix/bin"
for n in "${nombres[@]}"; do
	dest="$prefix/bin/$n"
	if [[ -e "$dest" && ! -L "$dest" ]]; then
		echo "ya existe $dest y no es un enlace; no se sobrescribe" >&2
		exit 1
	fi
	ln -sfn "$src" "$dest"
	echo "instalado: $dest -> $src"
done

command -v git >/dev/null || echo "falta la dependencia obligatoria: git (sudo apt install git)" >&2
command -v jq >/dev/null || echo "aviso: falta jq, necesario solo para Evaluar (sudo apt install jq)" >&2
case ":$PATH:" in
*":$prefix/bin:"*) ;;
*) echo "aviso: $prefix/bin no está en tu PATH" >&2 ;;
esac
