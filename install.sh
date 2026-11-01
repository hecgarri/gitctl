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
dest="$prefix/bin/gitctl"

if [[ -n "$uninstall" ]]; then
	if [[ -L "$dest" && "$(readlink -f "$dest")" == "$src" ]]; then
		rm -f "$dest"
		echo "eliminado $dest"
	else
		echo "$dest no es un enlace a esta copia de gitctl; no se toca" >&2
		exit 1
	fi
	exit 0
fi

if [[ -e "$dest" && ! -L "$dest" ]]; then
	echo "ya existe $dest y no es un enlace; no se sobrescribe" >&2
	exit 1
fi
mkdir -p "$prefix/bin"
ln -sfn "$src" "$dest"
echo "instalado: $dest -> $src"

command -v git >/dev/null || echo "falta la dependencia obligatoria: git (sudo apt install git)" >&2
case ":$PATH:" in
*":$prefix/bin:"*) ;;
*) echo "aviso: $prefix/bin no está en tu PATH" >&2 ;;
esac
echo "siguiente paso: añade a tu ~/.bashrc: eval \"\$(gitctl shell-init bash)\""
